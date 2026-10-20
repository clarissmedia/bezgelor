defmodule BezgelorCore.Spell4CombatSupport do
  @moduledoc """
  Execution gate for the audited Spell4 combat reference subset.

  The old local NexusForever uses placeholder damage; current upstream has
  a documented base equation but unresolved final damage and phase semantics.
  Raw graph discovery and base arithmetic never authorize world effects.

  This gate grants no execution support to other Spell4 entries.
  """

  @compile {:no_warn_undefined, BezgelorData.Spell4Catalog}

  @spec execution_blocker(non_neg_integer()) :: :unverified_spell4_combat | nil
  def execution_blocker(id) do
    if id in [43468, 43498, 43499] or
         (Code.ensure_loaded?(BezgelorData.Spell4Catalog) and
            BezgelorData.Spell4Catalog.covered?(id)) do
      :unverified_spell4_combat
    end
  end
end
