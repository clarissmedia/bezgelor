defmodule BezgelorWorld.Spell4CombatRegressionTest do
  use ExUnit.Case, async: false

  alias BezgelorCore.{AI, EntityGuid, Spell}
  alias BezgelorDb.{Accounts, Characters, Repo}
  alias BezgelorProtocol.Packets.World.ClientCastSpell
  alias BezgelorWorld.{BuffManager, SpellManager, WorldManager}
  alias BezgelorWorld.Handler.SpellHandler
  alias BezgelorWorld.World.Instance

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    for module <- [SpellManager, BuffManager] do
      if Process.whereis(module) == nil, do: start_supervised!(module)
    end

    unique = System.unique_integer([:positive])

    realm =
      Repo.insert!(%BezgelorDb.Schema.Realm{
        name: "Spell4",
        address: "127.0.0.1",
        port: 24000,
        type: :pve
      })

    {:ok, account} = Accounts.create_account("spell4#{unique}@test.invalid", "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "Spell#{unique}",
        realm_id: realm.id,
        sex: 0,
        race: 1,
        class: 0,
        faction_id: 166,
        world_id: 426,
        world_zone_id: 1
      })

    guid = EntityGuid.new(:player, character.id)
    world_id = 900_000 + unique
    key = {world_id, 1}
    pid = start_supervised!({Instance, world_id: world_id, instance_id: 1, lazy_loading: true})
    {:ok, target} = Instance.spawn_creature(pid, 1, {1.0, 0.0, 0.0})
    WorldManager.register_session(account.id, character.id, character.name, self())
    WorldManager.set_entity_guid(account.id, guid)
    assert WorldManager.get_session_by_entity_guid(guid)

    state = %{
      session_data: %{
        in_world: true,
        entity_guid: guid,
        character: nil,
        position: {0.0, 0.0, 0.0},
        world_id: world_id,
        instance_id: 1,
        target_guid: target,
        action_set_shortcuts: [%{slot: 0, spec_index: 0, spell_id: 3}]
      }
    }

    on_exit(fn ->
      WorldManager.unregister_session(account.id)
      SpellManager.clear_player(guid)
      BuffManager.clear_entity(guid)
    end)

    {:ok, state: state, guid: guid, target: target, key: key, character: character}
  end

  test "real Quick Draw and damage proxies fail before creating a cast or cooldown", ctx do
    for id <- [43468, 43498, 43499] do
      assert %Spell{effects: []} = Spell.get(id)

      assert {:error, :unverified_spell4_combat} =
               SpellManager.cast_spell(ctx.guid, id, ctx.target, nil, %{power: 99999}, self())

      refute SpellManager.casting?(ctx.guid)
      refute SpellManager.spell_ready?(ctx.guid, id)
      assert SpellManager.get_cooldown(ctx.guid, id) == 0
      assert SpellManager.spell_ready?(ctx.guid, 3)
    end

    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    assert Characters.get_character(ctx.character.id).total_xp == ctx.character.total_xp
    refute_receive {:spell_cast_completed, _, _, _, _, _, _}
  end

  test "Quick Draw request returns a failure instead of a successful empty spell", ctx do
    state =
      put_in(ctx.state, [:session_data, :action_set_shortcuts], [
        %{slot: 0, spec_index: 0, spell_id: 43468}
      ])

    assert {:reply_world_encrypted, :server_cast_result, <<1, 0, 43468::little-32>>, ^state} =
             cast(state)

    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    refute SpellManager.casting?(ctx.guid)
  end

  test "completion entry point cannot bypass the Quick Draw gate", ctx do
    effects = [%{type: :damage, amount: 99999, is_crit: false}]

    assert {:reply_world_encrypted, :server_cast_result, <<1, 0, 43468::little-32>>, _} =
             SpellHandler.complete_cast(ctx.guid, 43468, ctx.target, nil, effects, 1, ctx.state)

    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
  end

  test "existing demonstration attack reaches actual creature health", ctx do
    assert {:reply_multi_world_encrypted, packets, _} = cast(ctx.state)
    assert Enum.any?(packets, &(elem(&1, 0) == :server_spell_effect))
    # Existing demo formula and crit roll produce 80 or 120; this is not Quick Draw damage.
    creature = Instance.get_creature(ctx.key, ctx.target)
    assert creature.entity.health in [20, 0]
  end

  for {label, target} <- [
        {"zero", 0},
        {"player", EntityGuid.new(:player, 100)},
        {"absent creature", EntityGuid.new(:creature, 500_000_000)}
      ] do
    test "rejects #{label} target without cooldown or damage", ctx do
      state = put_in(ctx.state, [:session_data, :target_guid], unquote(target))

      assert {:reply_world_encrypted, :server_cast_result, <<1, 4, 3::little-32>>, _} =
               cast(state)

      assert SpellManager.spell_ready?(ctx.guid, 3)
      assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    end
  end

  test "rejects a creature in another instance", ctx do
    state = put_in(ctx.state, [:session_data, :instance_id], 2)
    assert {:reply_world_encrypted, :server_cast_result, <<1, 4, 3::little-32>>, _} = cast(state)
    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
  end

  test "checks actual range before consuming cooldown", ctx do
    state = put_in(ctx.state, [:session_data, :position], {20.0, 0.0, 0.0})
    assert {:reply_world_encrypted, :server_cast_result, <<1, 5, 3::little-32>>, _} = cast(state)
    assert SpellManager.spell_ready?(ctx.guid, 3)
    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
  end

  test "cancelled cast cannot apply damage or XP through its stale timer", ctx do
    assert {:ok, :casting, _} =
             SpellManager.cast_spell(ctx.guid, 1, ctx.target, nil, %{crit_chance: 0}, self())

    pending = SpellManager.get_cast(ctx.guid)
    assert :ok = SpellManager.cancel_cast(ctx.guid)
    send(SpellManager, {:cast_complete, ctx.guid, 1, pending.token})
    _ = :sys.get_state(SpellManager)
    refute_receive {:spell_cast_completed, _, _, _, _, _, _}
    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    assert Characters.get_character(ctx.character.id).total_xp == ctx.character.total_xp
  end

  test "timed demo cast kills once and persists XP once despite repeated timer", ctx do
    assert {:ok, :casting, _} =
             SpellManager.cast_spell(
               ctx.guid,
               1,
               ctx.target,
               nil,
               %{power: 0, crit_chance: 0},
               self()
             )

    pending = SpellManager.get_cast(ctx.guid)
    completion = {:cast_complete, ctx.guid, 1, pending.token}
    send(SpellManager, completion)
    assert_receive {:spell_cast_completed, guid, 1, target, nil, effects, casting_id}
    assert effects == [%{type: :damage, amount: 100, is_crit: false}]

    assert {:reply_multi_world_encrypted, _, _} =
             SpellHandler.complete_cast(guid, 1, target, nil, effects, casting_id, ctx.state)

    creature = Instance.get_creature(ctx.key, ctx.target)
    assert creature.entity.health == 0
    assert AI.dead?(creature.ai)
    assert_receive {:send_packet, :server_entity_death, _}
    assert_receive {:send_packet, :server_xp_gain, _}

    assert Characters.get_character(ctx.character.id).total_xp ==
             ctx.character.total_xp + creature.template.xp_reward

    send(SpellManager, completion)
    _ = :sys.get_state(SpellManager)
    refute_receive {:spell_cast_completed, _, _, _, _, _, _}

    assert {:reply_world_encrypted, :server_cast_result, <<1, 4, 1::little-32>>, _} =
             SpellHandler.complete_cast(guid, 1, target, nil, effects, casting_id, ctx.state)

    refute_receive {:send_packet, :server_xp_gain, _}

    assert Characters.get_character(ctx.character.id).total_xp ==
             ctx.character.total_xp + creature.template.xp_reward
  end

  test "target is revalidated when a timed cast completes", ctx do
    assert {:ok, :casting, _} =
             SpellManager.cast_spell(ctx.guid, 1, ctx.target, nil, %{crit_chance: 0}, self())

    pending = SpellManager.get_cast(ctx.guid)
    state = put_in(ctx.state, [:session_data, :position], {100.0, 0.0, 0.0})
    send(SpellManager, {:cast_complete, ctx.guid, 1, pending.token})
    assert_receive {:spell_cast_completed, guid, 1, target, nil, effects, casting_id}

    assert {:reply_world_encrypted, :server_cast_result, <<1, 5, 1::little-32>>, _} =
             SpellHandler.complete_cast(guid, 1, target, nil, effects, casting_id, state)

    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    assert Characters.get_character(ctx.character.id).total_xp == ctx.character.total_xp
  end

  test "dead target is rejected before casting and again at timed completion", ctx do
    assert {:ok, :casting, _} =
             SpellManager.cast_spell(ctx.guid, 1, ctx.target, nil, %{crit_chance: 0}, self())

    pending = SpellManager.get_cast(ctx.guid)
    assert {:ok, :killed, _} = Instance.damage_creature(ctx.key, ctx.target, ctx.guid, 100)

    assert {:reply_world_encrypted, :server_cast_result, <<1, 4, 3::little-32>>, _} =
             cast(ctx.state)

    send(SpellManager, {:cast_complete, ctx.guid, 1, pending.token})
    assert_receive {:spell_cast_completed, guid, 1, target, nil, effects, casting_id}

    assert {:reply_world_encrypted, :server_cast_result, <<1, 4, 1::little-32>>, _} =
             SpellHandler.complete_cast(guid, 1, target, nil, effects, casting_id, ctx.state)

    assert Characters.get_character(ctx.character.id).total_xp == ctx.character.total_xp
    refute_receive {:send_packet, :server_xp_gain, _}
  end

  defp cast(state), do: SpellHandler.handle_cast_request(%ClientCastSpell{bag_index: 0}, state)
end
