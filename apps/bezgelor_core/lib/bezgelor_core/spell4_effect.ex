defmodule BezgelorCore.Spell4Effect do
  @moduledoc """
  Typed identity of the effect codes found in the six-class reference subset.
  Names come from NexusForever.Game.Static.Spell.SpellEffectType at upstream
  f9bb26efddbf304003fc8ebf484ac75bc6be84da. A name never grants execution.
  """
  @enforce_keys [:id, :spell_id, :kind, :raw]
  defstruct [:id, :spell_id, :kind, :raw, :proxy_spell_id]

  @kinds %{
    1 => :vital_modifier,
    3 => :forced_move,
    4 => :cc_state_set,
    8 => :damage,
    10 => :heal,
    11 => :unit_property_modifier,
    17 => :fluff,
    26 => :proxy,
    73 => :modify_spell_cooldown,
    80 => :spell_force_remove
  }

  def from_row(%{"ID" => id, "spellId" => spell, "effectType" => type} = raw)
      when is_integer(id) and id > 0 and is_integer(spell) and spell > 0 do
    %__MODULE__{
      id: id,
      spell_id: spell,
      kind: Map.get(@kinds, type, {:unsupported, type}),
      proxy_spell_id: if(type == 26, do: raw["dataBits00"]),
      raw: raw
    }
  end
end
