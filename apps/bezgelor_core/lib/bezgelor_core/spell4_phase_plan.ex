defmodule BezgelorCore.Spell4PhasePlan do
  @moduledoc """
  Lossless phase evidence, not a WildStar event scheduler.

  SpellPhase.OrderIndex orders rows. No available implementation establishes
  the time origin of PhaseDelay, or a mapping between SpellPhase.PhaseFlags
  and Spell4Effects.PhaseFlags. In particular, neither mask is a phase ID.
  References with distinct effect IDs are retained, even with the same proxy.
  """
  def build(spell, phases, effects) do
    id = Map.fetch!(spell, "ID")

    %{
      spell_id: id,
      timing_fields:
        Map.take(spell, ~w(castTime channelInitialDelay channelPulseTime channelMaxTime)),
      phases:
        phases
        |> Enum.filter(&(&1["spell4IdOwner"] == id))
        |> Enum.sort_by(&{&1["orderIndex"], &1["ID"]}),
      effects:
        effects
        |> Enum.filter(&(&1["spellId"] == id))
        |> Enum.sort_by(&{&1["orderIndex"], &1["ID"]}),
      recognized_triggers: [],
      unresolved: [:delay_origin, :phase_flag_domains, :effect_triggers, :interruption_policy],
      execution_enabled: false
    }
  end

  def schedule(%{execution_enabled: false}), do: {:error, :unverified_phase_triggers}
end
