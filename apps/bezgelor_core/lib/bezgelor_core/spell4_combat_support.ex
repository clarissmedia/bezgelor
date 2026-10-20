defmodule BezgelorCore.Spell4CombatSupport do
  @moduledoc """
  Execution gate for the audited Quick Draw damage chain.

  NexusForever identifies type 8 as Damage and type 26 as Proxy (DataBits00),
  but its damage handler uses a TODO and the placeholder 1337. The phase
  masks and telegraph target selection cannot be replaced by a flattened
  list of effects. Keep both damage proxies and their root non-executable
  until those semantics and the damage formula are verified.

  This gate grants no execution support to other Spell4 entries.
  """

  @blocked_ids [43468, 43498, 43499]

  @spec execution_blocker(non_neg_integer()) :: :unverified_spell4_combat | nil
  def execution_blocker(id) when id in @blocked_ids, do: :unverified_spell4_combat
  def execution_blocker(_id), do: nil
end
