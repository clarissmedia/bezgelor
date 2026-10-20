# mix run --no-start tools/report_spell4_combat.exs > REPORT.json
# No world processes or database access. All properties below are test vectors.
alias BezgelorData.Spell4Catalog, as: Catalog
alias BezgelorCore.{Spell4BaseDamage, Spell4Context, Spell4Effect}

discover = fn discover, pending, visited ->
  case pending do
    [] ->
      visited

    [id | rest] ->
      if MapSet.member?(visited, id) do
        discover.(discover, rest, visited)
      else
        spell = Catalog.row("Spell4", id)

        proxies =
          for effect <- Catalog.effects(id), effect["effectType"] == 26, do: effect["dataBits00"]

        thresholds = Enum.map(Catalog.thresholds(id), & &1["spell4IdToCast"])
        events = for index <- 0..3, do: spell["spell4IdCastEvent0#{index}"]
        children = Enum.filter(proxies ++ thresholds ++ events, &(is_integer(&1) and &1 > 0))
        discover.(discover, rest ++ children, MapSet.put(visited, id))
      end
  end
end

coverage =
  for id <- Catalog.roots() do
    spell = Catalog.row("Spell4", id)
    base = Catalog.row("Spell4Base", spell["spell4BaseIdBaseSpell"])
    reachable = discover.(discover, [id], MapSet.new()) |> Enum.sort()
    effects = Enum.flat_map(reachable, &Catalog.effects/1)

    %{
      spell_id: id,
      description: spell["description"],
      class_id: base["classIdPlayer"],
      base_id: base["ID"],
      reachable_spells: reachable,
      effect_types: effects |> Enum.map(& &1["effectType"]) |> Enum.uniq() |> Enum.sort(),
      direct_effect_ids: Enum.map(Catalog.effects(id), & &1["ID"]),
      damage_effect_ids: for(effect <- effects, effect["effectType"] == 8, do: effect["ID"]),
      heal_effect_ids: for(effect <- effects, effect["effectType"] == 10, do: effect["ID"]),
      cast_time: spell["castTime"],
      cooldown: spell["spellCoolDown"],
      phases: Catalog.phases(id),
      thresholds: Catalog.thresholds(id),
      execution_enabled: false,
      blocker: "Final damage, authoritative stats, phases/events and target policy are incomplete"
    }
  end

context = %Spell4Context{
  caster: %{
    type: :player,
    level: 50,
    properties: %{35 => 400, 36 => 200, 141 => 1.0, 142 => 1.0, 143 => 1.0}
  },
  target: %{}
}

vectors =
  for effect <- Catalog.rows("Spell4Effects"), effect["effectType"] == 8 do
    result =
      case Spell4BaseDamage.calculate(effect, context, Catalog.row("GameFormula", 1266)) do
        {:ok, result} -> result
        {:error, reason} -> %{error: inspect(reason)}
      end

    %{effect_id: effect["ID"], spell_id: effect["spellId"], result: result}
  end

types =
  Catalog.rows("Spell4Effects")
  |> Enum.uniq_by(& &1["effectType"])
  |> Enum.sort_by(& &1["effectType"])
  |> Enum.map(fn raw -> %{code: raw["effectType"], name: Spell4Effect.from_row(raw).kind} end)

IO.puts(
  Jason.encode!(
    %{
      schema_version: 1,
      source_commit: "f9bb26efddbf304003fc8ebf484ac75bc6be84da",
      notice:
        "All vectors use explicit synthetic properties, not live stats or final damage. No world effects.",
      synthetic_context: %{
        level: 50,
        assault_rating: 400,
        support_rating: 200,
        damage_dealt_multipliers: 1.0
      },
      coverage: coverage,
      effect_types: types,
      base_damage_vectors: vectors,
      execution_enabled: false
    },
    pretty: true
  )
)
