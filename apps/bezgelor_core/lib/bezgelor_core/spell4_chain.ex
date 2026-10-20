defmodule BezgelorCore.Spell4Chain do
  @moduledoc """
  Bounded inspection of real Proxy (26) references, never an execution plan.

  Each spell is materialized once; every proxy edge keeps its original effect
  ID, phase mask, target flags and delay. Repeated references are not extra
  hits, and deduplicating nodes is not a decision about the number of shots.
  The lookup returns {:ok, raw_effect_rows} or :error for an absent spell.
  """
  alias BezgelorCore.Spell4Effect

  def inspect(root, lookup, opts \\ []) when is_function(lookup, 1) do
    state = %{
      spells: %{},
      edges: [],
      errors: [],
      max_nodes: Keyword.get(opts, :max_nodes, 256),
      max_depth: Keyword.get(opts, :max_depth, 16)
    }

    state = visit(root, lookup, [], state)

    %{
      spell_id: root,
      spells: state.spells,
      edges: Enum.reverse(state.edges),
      errors: Enum.reverse(state.errors),
      execution_enabled: false
    }
  end

  defp visit(id, lookup, path, state) do
    cond do
      id in path ->
        error(state, {:cycle, Enum.reverse([id | path])})

      Map.has_key?(state.spells, id) ->
        state

      length(path) > state.max_depth ->
        error(state, {:depth_limit, id})

      map_size(state.spells) >= state.max_nodes ->
        error(state, {:node_limit, id})

      true ->
        case lookup.(id) do
          :error ->
            error(state, {:missing_spell, id})

          {:ok, rows} ->
            effects = Enum.map(rows, &Spell4Effect.from_row/1)
            state = %{state | spells: Map.put(state.spells, id, effects)}

            Enum.reduce(effects, state, fn effect, state ->
              if effect.kind == :proxy do
                edge = %{
                  from: id,
                  to: effect.proxy_spell_id,
                  effect_id: effect.id,
                  phase_flags: effect.raw["phaseFlags"],
                  target_flags: effect.raw["targetFlags"],
                  delay_time: effect.raw["delayTime"]
                }

                state = %{state | edges: [edge | state.edges]}

                if is_integer(edge.to) and edge.to > 0,
                  do: visit(edge.to, lookup, [id | path], state),
                  else: error(state, {:invalid_proxy, effect.id})
              else
                state
              end
            end)
        end
    end
  end

  defp error(state, reason), do: %{state | errors: [reason | state.errors]}
end
