using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using NexusForever.GameTable;

// IO-only comparison adapter: field values are read by the unmodified NF reader.
// Dynamic models avoid depending on manually transcribed names or array models.
// Usage: ReferenceReader TABLE.tbl OUTPUT.json (output must stay in workspace).
if (args.Length != 2) throw new ArgumentException("TABLE.tbl OUTPUT.json");
string workspace = Directory.GetCurrentDirectory();
string output = Path.GetFullPath(args[1]);
if (!output.StartsWith(workspace + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
    || Path.GetExtension(output) != ".json")
    throw new ArgumentException("Output must be a JSON file inside the workspace");

byte[] bytes = File.ReadAllBytes(args[0]);
var header = MemoryMarshal.Read<GameTableHeader>(bytes);
int headerSize = Marshal.SizeOf<GameTableHeader>();
int fieldSize = Marshal.SizeOf<GameTableField>();
int fieldsStart = headerSize + (int)header.FieldOffset;
int namesStart = (fieldsStart + (int)header.FieldCount * fieldSize + 15) & ~15;
var module = AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("TblModel"), AssemblyBuilderAccess.Run)
    .DefineDynamicModule("TblModel");
var model = module.DefineType("Row", TypeAttributes.Public);
for (int i = 0; i < (int)header.FieldCount; i++)
{
    var field = MemoryMarshal.Read<GameTableField>(bytes.AsSpan(fieldsStart + i * fieldSize));
    string name = Encoding.Unicode.GetString(bytes, namesStart + (int)field.NameOffset,
        (int)field.NameLength * 2).TrimEnd('\0');
    Type type = field.Type switch
    {
        DataType.UInt => typeof(uint), DataType.Single => typeof(float),
        DataType.Boolean => typeof(bool), DataType.ULong => typeof(ulong),
        DataType.String => typeof(string), _ => throw new InvalidDataException("Unsupported field type")
    };
    model.DefineField(name, type, FieldAttributes.Public);
}
Type rowType = model.CreateType();
Type tableType = typeof(GameTable<>).MakeGenericType(rowType);
object table = Activator.CreateInstance(tableType, args[0]);
var entries = (Array)tableType.GetProperty("Entries").GetValue(table);
var rows = new List<Dictionary<string, object>>();
foreach (object entry in entries)
{
    var row = new Dictionary<string, object>();
    foreach (FieldInfo field in rowType.GetFields())
    {
        object value = field.GetValue(entry);
        // Expose the full float32 value instead of System.Text.Json's shortened float text.
        row[field.Name] = value is float f ? (object)(double)f : value;
    }
    rows.Add(row);
}
File.WriteAllText(output, JsonSerializer.Serialize(rows) + "\n");
Console.WriteLine($"{Path.GetFileName(args[0])}: {rows.Count} rows, header={headerSize}");
