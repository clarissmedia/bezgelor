# mix run --no-start tools/extract_spell4_combat.exs TABLE_DIRECTORY OUTPUT_JSON
# Reads copies or originals; only OUTPUT_JSON is written. Does not start the world.
[table_directory, output] = System.argv()
alias BezgelorData.Tbl

project_root = Path.expand("..", __DIR__)
output_path = Path.expand(output)
relative_output = Path.relative_to(output_path, project_root)

if Path.extname(output_path) != ".json" or Path.type(relative_output) == :absolute or
     String.starts_with?(relative_output, "../"),
   do: raise(ArgumentError, "output must be a JSON artifact inside the workspace")

roots = [32078, 34355, 34718, 43468, 58524, 32893, 33140, 38765, 42276, 58832, 58841]
names = ~w(Spell4 Spell4Base Spell4Effects SpellEffectType GameFormula SpellPhase
  Spell4Thresholds Spell4Telegraph TelegraphDamage Spell4Runner Spell4ValidTargets
  Spell4TargetMechanics Spell4CastResult Spell4AoeTargetConstraints
  Spell4EffectModification Spell4EffectGroupList SpellCoolDown Prerequisite)

tables =
  Map.new(names, fn name ->
    path = Path.join(table_directory, name <> ".tbl")
    data = File.read!(path)
    table = Tbl.decode!(data)
    IO.puts("#{name}: #{length(table.rows)} records")
    {name, Map.put(table, :sha256, Base.encode16(:crypto.hash(:sha256, data), case: :lower))}
  end)

spells = Map.new(tables["Spell4"].rows, &{&1["ID"], &1})
effects = Enum.group_by(tables["Spell4Effects"].rows, & &1["spellId"])
thresholds = Enum.group_by(tables["Spell4Thresholds"].rows, & &1["spell4IdParent"])

expand = fn expand, pending, visited ->
  case pending do
    [] ->
      visited

    [id | rest] ->
      if MapSet.member?(visited, id) do
        expand.(expand, rest, visited)
      else
        spell = Map.fetch!(spells, id)
        proxies = for e <- Map.get(effects, id, []), e["effectType"] == 26, do: e["dataBits00"]
        charged = Enum.map(Map.get(thresholds, id, []), & &1["spell4IdToCast"])
        events = for index <- 0..3, do: spell["spell4IdCastEvent0#{index}"]
        references = Enum.filter(proxies ++ charged ++ events, &(is_integer(&1) and &1 > 0))
        expand.(expand, rest ++ references, MapSet.put(visited, id))
      end
  end
end

ids = expand.(expand, roots, MapSet.new())
selected_spells = ids |> Enum.sort() |> Enum.map(&Map.fetch!(spells, &1))
base_ids = MapSet.new(selected_spells, & &1["spell4BaseIdBaseSpell"])
telegraphs = Enum.filter(tables["Spell4Telegraph"].rows, &MapSet.member?(ids, &1["spell4Id"]))
telegraph_ids = MapSet.new(telegraphs, & &1["telegraphDamageId"])

formula_ids = [
  1230,
  1231,
  1232,
  1233,
  1234,
  1235,
  1236,
  1237,
  1240,
  1241,
  1243,
  1244,
  1245,
  1265,
  1266,
  1269,
  1270,
  1271,
  1272,
  1274,
  549,
  1288
]

constraint_ids = MapSet.new(selected_spells, & &1["spell4AoeTargetConstraintsId"])
effect_ids = ids |> Enum.flat_map(&Map.get(effects, &1, [])) |> MapSet.new(& &1["ID"])

prerequisite_ids =
  (selected_spells ++ Enum.flat_map(ids, &Map.get(effects, &1, [])))
  |> Enum.flat_map(fn row ->
    for {field, value} <- row, String.starts_with?(field, "prerequisiteId"), value > 0, do: value
  end)
  |> MapSet.new()

rows = %{
  "Spell4" => selected_spells,
  "Spell4Base" => Enum.filter(tables["Spell4Base"].rows, &MapSet.member?(base_ids, &1["ID"])),
  "Spell4Effects" =>
    Enum.filter(tables["Spell4Effects"].rows, &MapSet.member?(ids, &1["spellId"])),
  "SpellPhase" =>
    Enum.filter(tables["SpellPhase"].rows, &MapSet.member?(ids, &1["spell4IdOwner"])),
  "Spell4Thresholds" =>
    Enum.filter(tables["Spell4Thresholds"].rows, &MapSet.member?(ids, &1["spell4IdParent"])),
  "Spell4Telegraph" => telegraphs,
  "TelegraphDamage" =>
    Enum.filter(tables["TelegraphDamage"].rows, &MapSet.member?(telegraph_ids, &1["ID"])),
  "GameFormula" => Enum.filter(tables["GameFormula"].rows, &(&1["ID"] in formula_ids)),
  "Spell4AoeTargetConstraints" =>
    Enum.filter(
      tables["Spell4AoeTargetConstraints"].rows,
      &MapSet.member?(constraint_ids, &1["ID"])
    ),
  "Spell4EffectModification" =>
    Enum.filter(
      tables["Spell4EffectModification"].rows,
      &MapSet.member?(effect_ids, &1["spell4EffectsId"])
    ),
  "Prerequisite" =>
    Enum.filter(tables["Prerequisite"].rows, &MapSet.member?(prerequisite_ids, &1["ID"]))
}

reference = %{
  "schema_version" => 1,
  "execution_enabled" => false,
  "roots" => roots,
  "reader_source" =>
    "NexusForever.GameTable/GameTable.cs ReadEntries; string padding and exact float32",
  "tables" =>
    Map.new(tables, fn {name, table} ->
      {name,
       %{
         "sha256" => table.sha256,
         "record_count" => length(table.rows),
         "record_size" => table.record_size,
         "fields" =>
           Enum.map(table.fields, fn {field, type} -> %{"name" => field, "type" => type} end),
         "rows" => Map.get(rows, name, table.rows) |> Enum.sort_by(& &1["ID"])
       }}
    end)
}

# No rounding, timestamp, or machine-specific path in the reproducible artifact.
File.write!(output, Jason.encode!(reference, pretty: true) <> "\n")
IO.puts("Wrote #{MapSet.size(ids)} spell entries to #{output}; execution remains disabled")
