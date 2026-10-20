defmodule BezgelorData.Spell4CatalogTest do
  use ExUnit.Case, async: true
  alias BezgelorData.Spell4Catalog, as: Catalog

  test "original Spell4 data fixes the shifted base, tier, cast and cooldown fields" do
    assert {:ok, quick_draw} = BezgelorData.get_spell4_entry(43468)
    assert quick_draw.spell4BaseIdBaseSpell == 27638
    assert quick_draw.tierIndex == 1
    assert quick_draw.castTime == 1000
    assert quick_draw.spellDuration == 0
    assert quick_draw.channelMaxTime == 1000
    assert {:ok, gate} = BezgelorData.get_spell4_entry(34355)
    assert gate.spellCoolDown == 30000
    assert {:ok, esper} = BezgelorData.get_spell4_entry(32893)
    assert esper.castTime == 1250
  end

  test "real damage rows retain coefficients and table provenance" do
    effect = Catalog.row("Spell4Effects", 99526)
    assert effect["spellId"] == 43498
    assert effect["effectType"] == 8
    assert effect["parameterType00"] == 12
    assert effect["parameterValue00"] == 0.10289999842643738
    assert effect["parameterType01"] == 10
    assert effect["parameterValue01"] == 5.5
    assert Catalog.row("GameFormula", 1266)["datafloat0"] == 0.25
    assert Catalog.metadata("Spell4Effects")["record_count"] == 131_010
    assert byte_size(Catalog.metadata("Spell4Effects")["sha256"]) == 64
  end

  test "coverage includes roots and explicit threshold and proxy references for six classes" do
    assert length(Catalog.roots()) == 11
    assert length(Catalog.spell_ids()) == 48

    for id <- [32078, 34355, 34718, 43468, 58524, 32893, 33140, 38765, 42276, 58832, 58841] do
      assert Catalog.covered?(id)
      refute Catalog.effects(id) == []
    end

    assert Catalog.thresholds(34718) |> Enum.map(& &1["spell4IdToCast"]) |> Enum.sort() == [
             34720,
             34722,
             36691
           ]

    assert length(Catalog.phases(43468)) == 5
    refute Catalog.covered?(999_999_999)
    assert Catalog.spell_entry(999_999_999) == :error
  end
end
