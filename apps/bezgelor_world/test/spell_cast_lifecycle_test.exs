defmodule BezgelorWorld.SpellCastLifecycleTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.SpellManager

  setup do
    if Process.whereis(SpellManager) == nil do
      start_supervised!(SpellManager)
    end

    player_guid = System.unique_integer([:positive])
    on_exit(fn ->
      if Process.whereis(SpellManager), do: SpellManager.clear_player(player_guid)
    end)
    {:ok, player_guid: player_guid}
  end

  test "a timed cast preserves its wire ID and cannot complete twice", %{player_guid: guid} do
    assert {:ok, :casting, _} = SpellManager.cast_spell(guid, 1, 123, nil, %{}, self())
    cast = SpellManager.get_cast(guid)
    assert is_integer(cast.casting_id)
    assert cast.casting_id > 0
    assert is_reference(cast.token)

    completion = {:cast_complete, guid, 1, cast.token}
    send(SpellManager, completion)
    assert_receive {:spell_cast_completed, ^guid, 1, 123, nil, effects, casting_id}, 1000
    assert casting_id == cast.casting_id
    assert is_list(effects)

    send(SpellManager, completion)
    refute_receive {:spell_cast_completed, ^guid, 1, _, _, _, _}, 100
  end

  test "cancel prevents a stale timer from applying effects", %{player_guid: guid} do
    assert {:ok, :casting, _} = SpellManager.cast_spell(guid, 1, 123, nil, %{}, self())
    cast = SpellManager.get_cast(guid)
    assert :ok = SpellManager.cancel_cast(guid)
    send(SpellManager, {:cast_complete, guid, 1, cast.token})
    refute_receive {:spell_cast_completed, ^guid, 1, _, _, _, _}, 100
  end
end
