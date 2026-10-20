# mix run --no-start tools/audit_spell4_phases.exs TBL_DIR NF_JSON_DIR OUTPUT.json
# Independent C# exports must be produced with tools/spell4_reference_reader.
[table_dir, nf_dir, output] = System.argv()
alias BezgelorData.{Spell4Catalog, Tbl}
alias BezgelorCore.Spell4PhasePlan

relative = Path.relative_to(Path.expand(output), File.cwd!())

if Path.type(relative) == :absolute or String.starts_with?(relative, "../") or
     Path.extname(output) != ".json",
   do: raise(ArgumentError, "workspace JSON output required")

names = ~w(Spell4 Spell4Base Spell4Effects SpellEffectType GameFormula SpellPhase
  Spell4Thresholds Spell4Telegraph TelegraphDamage Spell4Runner Spell4ValidTargets
  Spell4TargetMechanics Spell4CastResult Spell4AoeTargetConstraints
  Spell4EffectModification Spell4EffectGroupList SpellCoolDown Prerequisite
  Spell4Conditions Spell4CCConditions)

{comparisons, tables} =
  Enum.map_reduce(names, %{}, fn name, tables ->
    bytes = File.read!(Path.join(table_dir, name <> ".tbl"))
    table = Tbl.decode!(bytes)
    reference = nf_dir |> Path.join("nf-#{name}.json") |> File.read!() |> Jason.decode!()
    unless table.rows == reference, do: raise("NexusForever row mismatch: #{name}")

    unless name in ~w(Spell4Conditions Spell4CCConditions) do
      original = Map.new(table.rows, &{&1["ID"], &1})

      unless Enum.all?(Spell4Catalog.rows(name), &(original[&1["ID"]] == &1)),
        do: raise("catalog row mismatch: #{name}")

      unless Spell4Catalog.metadata(name)["sha256"] ==
               Base.encode16(:crypto.hash(:sha256, bytes), case: :lower),
             do: raise("catalog source hash mismatch: #{name}")
    end

    result = %{
      table: name,
      rows_compared: length(reference),
      equal: true,
      sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    }

    {result, Map.put(tables, name, table.rows)}
  end)

ids = [43468, 43498, 43499, 43500]
spells = Enum.filter(tables["Spell4"], &(&1["ID"] in ids))
base_ids = Enum.map(spells, & &1["spell4BaseIdBaseSpell"])
bases = Enum.filter(tables["Spell4Base"], &(&1["ID"] in base_ids))

condition_ids =
  Enum.flat_map(spells, &[&1["spell4ConditionsIdCaster"], &1["spell4ConditionsIdTarget"]])

cc_ids =
  Enum.flat_map(spells, &[&1["spell4CCConditionsIdCaster"], &1["spell4CCConditionsIdTarget"]])

effects = Enum.filter(tables["Spell4Effects"], &(&1["spellId"] in ids))
phases = Enum.filter(tables["SpellPhase"], &(&1["spell4IdOwner"] in ids))
links = Enum.filter(tables["Spell4Telegraph"], &(&1["spell4Id"] in ids))
telegraph_ids = Enum.map(links, & &1["telegraphDamageId"])
constraints = Enum.map(spells, & &1["spell4AoeTargetConstraintsId"])
mechanics = Enum.map(bases, & &1["spell4TargetMechanicId"])
valid_targets = Enum.map(bases, & &1["spell4ValidTargetId"])

evidence = %{
  comparisons: comparisons,
  spells: spells,
  bases: bases,
  effects: effects,
  phases: phases,
  telegraph_links: links,
  telegraphs: Enum.filter(tables["TelegraphDamage"], &(&1["ID"] in telegraph_ids)),
  constraints: Enum.filter(tables["Spell4AoeTargetConstraints"], &(&1["ID"] in constraints)),
  conditions: Enum.filter(tables["Spell4Conditions"], &(&1["ID"] in condition_ids)),
  cc_conditions: Enum.filter(tables["Spell4CCConditions"], &(&1["ID"] in cc_ids)),
  target_mechanics: Enum.filter(tables["Spell4TargetMechanics"], &(&1["ID"] in mechanics)),
  valid_targets: Enum.filter(tables["Spell4ValidTargets"], &(&1["ID"] in valid_targets)),
  thresholds: Enum.filter(tables["Spell4Thresholds"], &(&1["spell4IdParent"] in ids)),
  plans: Enum.map(spells, &Spell4PhasePlan.build(&1, phases, effects)),
  event_schedule: nil,
  selected_targets: nil,
  execution_enabled: false,
  source_reader:
    "unmodified NexusForever.GameTable.GameTable<T>.ReadEntries, dynamically emitted scalar models",
  comparison:
    "all rows and fields, exact decoded float32 values; catalog subset and source SHA256 also checked"
}

# Map enumeration (especially atom keys) can differ between VM boots. Sort
# object keys recursively so the evidence is byte-reproducible as well as equal.
canonical = fn canonical, value ->
  cond do
    is_map(value) ->
      value
      |> Enum.map(fn {key, item} -> {to_string(key), canonical.(canonical, item)} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Jason.OrderedObject.new()

    is_list(value) ->
      Enum.map(value, &canonical.(canonical, &1))

    true ->
      value
  end
end

File.write!(output, Jason.encode!(canonical.(canonical, evidence), pretty: true) <> "\n")

IO.puts(
  "Verified #{Enum.sum(Enum.map(comparisons, & &1.rows_compared))} rows in #{length(names)} tables; wrote #{output}"
)
