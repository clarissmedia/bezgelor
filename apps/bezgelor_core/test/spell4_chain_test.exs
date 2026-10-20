defmodule BezgelorCore.Spell4ChainTest do
  use ExUnit.Case, async: true
  alias BezgelorCore.{Spell4Chain, Spell4Effect}

  test "repeated proxies retain edges and phase masks but materialize damage only once" do
    source = %{1 => [row(11, 1, 26, 2, 2), row(12, 1, 26, 2, 4)], 2 => [row(21, 2, 8)]}
    result = resolve(1, source)
    assert map_size(result.spells) == 2
    assert length(result.spells[2]) == 1
    assert Enum.map(result.edges, & &1.phase_flags) == [2, 4]
    assert Enum.map(result.edges, & &1.effect_id) == [11, 12]
    assert result.errors == []
    refute result.execution_enabled
  end

  test "cycles and missing children are explicit diagnostics" do
    cycle = resolve(1, %{1 => [row(11, 1, 26, 2)], 2 => [row(21, 2, 26, 1)]})
    assert cycle.errors == [{:cycle, [1, 2, 1]}]
    assert map_size(cycle.spells) == 2
    assert resolve(1, %{1 => [row(11, 1, 26, 2)]}).errors == [{:missing_spell, 2}]
  end

  test "depth and node limits prevent unbounded expansion" do
    source = %{1 => [row(11, 1, 26, 2)], 2 => [row(21, 2, 26, 3)], 3 => []}
    assert resolve(1, source, max_depth: 0).errors == [{:depth_limit, 2}]
    assert resolve(1, source, max_nodes: 1).errors == [{:node_limit, 2}]
  end

  test "Fluff and SpellForceRemove are not traversed as damage proxies" do
    result = resolve(1, %{1 => [row(11, 1, 17, 99), row(12, 1, 80, 99)]})
    assert result.edges == []
    assert Enum.map(result.spells[1], & &1.kind) == [:fluff, :spell_force_remove]
    assert Spell4Effect.from_row(row(13, 1, 999)).kind == {:unsupported, 999}
  end

  defp resolve(id, source, opts \\ []) do
    Spell4Chain.inspect(id, &Map.fetch(source, &1), opts)
  end

  defp row(id, spell, type, child \\ 0, phase \\ 1),
    do: %{
      "ID" => id,
      "spellId" => spell,
      "effectType" => type,
      "dataBits00" => child,
      "phaseFlags" => phase,
      "targetFlags" => 1,
      "delayTime" => 0
    }
end
