defmodule BezgelorWorld.Spell4Diagnostics do
  @moduledoc "Read-only inspection of sourced Spell4 records and optional base-damage operands."
  alias BezgelorData.Spell4Catalog, as: Catalog
  alias BezgelorCore.{Spell4BaseDamage, Spell4Chain, Spell4PhasePlan}
  require Logger

  def inspect_spell(id, context \\ nil) do
    if Catalog.covered?(id) do
      chain =
        Spell4Chain.inspect(id, fn spell ->
          if Catalog.covered?(spell), do: {:ok, Catalog.effects(spell)}, else: :error
        end)

      base_damage =
        for {_spell, effects} <- chain.spells,
            effect <- effects,
            effect.kind == :damage,
            into: %{} do
          result =
            if context,
              do:
                Spell4BaseDamage.calculate(effect.raw, context, Catalog.row("GameFormula", 1266)),
              else: {:error, :missing_combat_context}

          {effect.id, result}
        end

      Logger.debug("Spell4 audit spell=#{id} nodes=#{map_size(chain.spells)} executable=false")

      telegraphs =
        for spell <- Map.keys(chain.spells), into: %{} do
          shapes =
            for link <- Catalog.rows("Spell4Telegraph"),
                link["spell4Id"] == spell,
                do: Catalog.row("TelegraphDamage", link["telegraphDamageId"])

          {spell, shapes}
        end

      constraints =
        Map.new(Map.keys(chain.spells), fn spell ->
          entry = Catalog.row("Spell4", spell)

          {spell,
           Catalog.row("Spell4AoeTargetConstraints", entry["spell4AoeTargetConstraintsId"])}
        end)

      {:ok,
       %{
         chain: chain,
         spell: Catalog.row("Spell4", id),
         phases: Catalog.phases(id),
         phase_plan:
           Spell4PhasePlan.build(
             Catalog.row("Spell4", id),
             Catalog.phases(id),
             Catalog.effects(id)
           ),
         thresholds: Catalog.thresholds(id),
         base_damage: base_damage,
         telegraphs: telegraphs,
         constraints: constraints,
         geometry_execution: :unsupported,
         geometry_diagnostic: :nexusforever_zero_radius_points_only,
         execution_blocker: :unverified_spell4_combat,
         remaining: [
           :phase_execution,
           :target_policy,
           :prerequisite_policy,
           :resources,
           :cooldowns,
           :authoritative_stats,
           :final_damage,
           :protocol
         ]
       }}
    else
      :error
    end
  end
end
