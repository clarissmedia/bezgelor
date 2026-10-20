defmodule BezgelorCore.Spell4EffectCatalogTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Spell
  alias BezgelorCore.Spell4EffectCatalog

  test "Quick Draw has nine raw effects and points to two damage spell IDs" do
    assert {:ok, direct} = Spell4EffectCatalog.direct_effects(43468)
    assert length(direct) == 9
    assert Enum.any?(direct, &(&1.proxy_spell_id == 43498))
    assert Enum.any?(direct, &(&1.proxy_spell_id == 43499))
    assert {:ok, analysis} = Spell.effect_analysis(43468)
    damage_ids = analysis.nodes |> Enum.filter(&(&1.type == 8))
      |> Enum.map(& &1.spell_id) |> Enum.uniq() |> Enum.sort()
    assert damage_ids == [43498, 43499]
  end

  test "unverified damage formula cannot create executable effects" do
    assert {:ok, analysis} = Spell.effect_analysis(43468)
    refute analysis.execution_enabled
    refute analysis.damage_formula_verified
    refute analysis.safe_to_apply_damage
    assert Enum.all?(analysis.nodes, fn e -> e.amount == nil and e.executable == false end)
  end

  test "unknown spells do not inherit speculative combat data" do
    assert :error == Spell.effect_analysis(999_999_999)
  end

  test "repeated proxy references remain distinct research records" do
    assert {:ok, direct} = Spell4EffectCatalog.direct_effects(43468)
    assert Enum.count(direct, &(&1.proxy_spell_id == 43498)) == 3
  end
end
