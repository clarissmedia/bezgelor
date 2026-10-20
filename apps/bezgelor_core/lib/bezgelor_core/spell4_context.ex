defmodule BezgelorCore.Spell4Context do
  @moduledoc """
  Explicit raw-stat context for Spell4 formula inspection.

  `caster` and `target` contain level, health/max_health, shield/max_shield,
  and `properties` keyed by NexusForever Property IDs. The caster also has
  `type: :player`. Missing operands are errors, never substituted from the
  demonstration CharacterStats power/support maps. This is not a snapshot
  of live authoritative stats until equipment/property integration exists.
  """
  @enforce_keys [:caster, :target]
  defstruct [:caster, :target]
end
