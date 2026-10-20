using System.Numerics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using NexusForever.Game.Abstract.Entity;
using NexusForever.Game.Spell;
using NexusForever.GameTable.Model;

// Emit observations from the actual reference algorithm, not reimplemented math.
// Usage: GeometryReader INPUT.json OUTPUT.json SOURCE_DIRECTORY
if (args.Length != 3) throw new ArgumentException("INPUT.json OUTPUT.json SOURCE_DIRECTORY");
string output = Path.GetFullPath(args[1]);
if (!output.StartsWith(Directory.GetCurrentDirectory() + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
    || Path.GetExtension(output) != ".json") throw new ArgumentException("workspace JSON output required");
var input = JsonNode.Parse(File.ReadAllText(args[0]));
var options = new JsonSerializerOptions { IncludeFields = true, PropertyNameCaseInsensitive = true };
Vector3 Position(JsonNode node) => new Vector3((float)node[0], (float)node[1], (float)node[2]);
foreach (var item in input["vectors"].AsArray())
{
    var entry = item["row"].Deserialize<TelegraphDamageEntry>(options);
    var telegraph = new Telegraph(entry, new ReferenceCaster(), Position(item["origin"]),
        new Vector3((float)item["yaw"], 0, 0));
    item["expected"] = telegraph.InsideTelegraph(Position(item["point"]), 0);
}
var hashes = new JsonObject();
foreach (string path in new[] { "NexusForever.Game/Spell/Telegraph.cs", "NexusForever.Game/MathsExtensions.cs",
    "NexusForever.Game.Static/Spell/DamageShape.cs", "NexusForever.GameTable/Model/TelegraphDamageEntry.cs" })
    hashes[path] = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(args[2], path)))).ToLowerInvariant();
input["reference_source_sha256"] = hashes;
File.WriteAllText(output, input.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + "\n");
Console.WriteLine($"Emitted {input["vectors"].AsArray().Count} zero-radius reference vectors");
