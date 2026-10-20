defmodule BezgelorCore.Spell4EffectCatalog do
  @moduledoc """
  Read-only research catalog of selected Spell4 effect chains.
  This does NOT calculate damage or schedule proxy/phase effects.
  """

  @max_depth 8
  @effects %{
    43468 => [
      %{id: 196513, type: 26, target_flags: 1, phase_flags: 2, proxy_spell_id: 43498},
      %{id: 196514, type: 26, target_flags: 1, phase_flags: 4, proxy_spell_id: 43499},
      %{id: 196515, type: 26, target_flags: 1, phase_flags: 8, proxy_spell_id: 43498},
      %{id: 196516, type: 26, target_flags: 1, phase_flags: 8, proxy_spell_id: 43500},
      %{id: 196517, type: 26, target_flags: 1, phase_flags: 2, proxy_spell_id: 43499},
      %{id: 196518, type: 26, target_flags: 1, phase_flags: 4, proxy_spell_id: 43498},
      %{id: 196519, type: 26, target_flags: 1, phase_flags: 8, proxy_spell_id: 43499},
      %{id: 196521, type: 80, target_flags: 1, phase_flags: 8, proxy_spell_id: nil},
      %{id: 196522, type: 26, target_flags: 1, phase_flags: 1, proxy_spell_id: 43500},
    ],
    43498 => [
      %{id: 99526, type: 8, target_flags: 4, phase_flags: 4294967295, proxy_spell_id: nil},
    ],
    43499 => [
      %{id: 99528, type: 8, target_flags: 4, phase_flags: 4294967295, proxy_spell_id: nil},
    ],
    43500 => [
      %{id: 99472, type: 17, target_flags: 1, phase_flags: 4294967295, proxy_spell_id: nil},
    ],
    32078 => [
      %{id: 177146, type: 26, target_flags: 1, phase_flags: 4294967295, proxy_spell_id: 70033},
    ],
    70033 => [
      %{id: 177056, type: 8, target_flags: 4, phase_flags: 1, proxy_spell_id: nil},
      %{id: 177057, type: 26, target_flags: 4, phase_flags: 1, proxy_spell_id: 53865},
    ],
    53865 => [
      %{id: 127603, type: 1, target_flags: 1, phase_flags: 1, proxy_spell_id: nil},
      %{id: 147972, type: 1, target_flags: 1, phase_flags: 1, proxy_spell_id: nil},
      %{id: 177873, type: 26, target_flags: 1, phase_flags: 4294967295, proxy_spell_id: 60947},
    ],
    60947 => [
      %{id: 147971, type: 17, target_flags: 1, phase_flags: 4294967295, proxy_spell_id: nil},
    ],
    34718 => [
      %{id: 75878, type: 17, target_flags: 1, phase_flags: 4294967295, proxy_spell_id: nil},
    ],
    34355 => [
      %{id: 67776, type: 3, target_flags: 1, phase_flags: 1, proxy_spell_id: nil},
      %{id: 67777, type: 11, target_flags: 1, phase_flags: 1, proxy_spell_id: nil},
      %{id: 67778, type: 26, target_flags: 1, phase_flags: 1, proxy_spell_id: 25190},
      %{id: 67779, type: 26, target_flags: 1, phase_flags: 1, proxy_spell_id: 30436},
    ],
    25190 => [
      %{id: 40372, type: 17, target_flags: 1, phase_flags: 1, proxy_spell_id: nil},
    ],
    30436 => [
      %{id: 100836, type: 4, target_flags: 4, phase_flags: 1, proxy_spell_id: nil},
    ],
    58524 => [
      %{id: 177439, type: 26, target_flags: 1, phase_flags: 4294967295, proxy_spell_id: 70135},
    ],
    70135 => [
      %{id: 177438, type: 8, target_flags: 4, phase_flags: 4294967295, proxy_spell_id: nil},
    ],
  }

  @spec supported_ids() :: [non_neg_integer()]
  def supported_ids, do: Map.keys(@effects) |> Enum.sort()

  @spec direct_effects(non_neg_integer()) :: {:ok, [map()]} | :error
  def direct_effects(id) when is_integer(id) do
    case Map.fetch(@effects, id) do
      {:ok, effects} -> {:ok, effects}
      :error -> :error
    end
  end

  @doc """
  Expand references for inspection only. Identical proxies are kept as separate
  records; no assumption is made about their timing or hit count.
  """
  @spec analyze(non_neg_integer()) :: {:ok, map()} | :error
  def analyze(id) when is_integer(id) do
    case Map.fetch(@effects, id) do
      :error -> :error
      {:ok, _} ->
        nodes = expand(id, [id], 0)
        {:ok, %{spell_id: id, nodes: nodes, execution_enabled: false,
                 damage_formula_verified: false, safe_to_apply_damage: false}}
    end
  end

  defp expand(id, path, depth) do
    Enum.flat_map(Map.get(@effects, id, []), fn effect ->
      record = Map.merge(effect, %{spell_id: id, depth: depth, path: path,
          amount: nil, executable: false})
      next_id = effect.proxy_spell_id
      children =
        cond do
          not is_integer(next_id) -> []
          next_id in path -> []
          depth >= @max_depth -> []
          not Map.has_key?(@effects, next_id) -> []
          true -> expand(next_id, path ++ [next_id], depth + 1)
        end
      [record | children]
    end)
  end
end
