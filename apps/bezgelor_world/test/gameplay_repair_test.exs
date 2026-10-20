defmodule BezgelorWorld.GameplayRepairTest do
  use ExUnit.Case, async: false

  alias BezgelorCore.{Entity, EntityGuid}
  alias BezgelorDb.{Accounts, Characters, Quests, Repo}
  alias BezgelorProtocol.{Connection, PacketReader, PacketWriter}
  alias BezgelorProtocol.Handler.{EntityCommandHandler, PackedHandler, PackedWorldHandler}
  alias BezgelorProtocol.Packets.World.{ClientNpcInteract, ServerEntityCreate}
  alias BezgelorWorld.{CreatureDeath, WorldManager}
  alias BezgelorWorld.Handler.{NpcHandler, QuestHandler}
  alias BezgelorWorld.Quest.{QuestCache, SessionQuestManager}
  alias BezgelorWorld.World.{CreatureState, Instance}
  alias BezgelorData.Store

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    realm =
      Repo.insert!(%BezgelorDb.Schema.Realm{
        name: "Gameplay repair",
        address: "127.0.0.1",
        port: 24000,
        type: :pve
      })

    unique = System.unique_integer([:positive])
    {:ok, account} = Accounts.create_account("gameplay#{unique}@test.invalid", "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "Repair#{unique}",
        realm_id: realm.id,
        sex: 0,
        race: 1,
        class: 0,
        faction_id: 166,
        world_id: 426,
        world_zone_id: 1
      })

    state = %Connection{
      current_opcode: :client_accept_quest,
      session_data: %{
        character_id: character.id,
        active_quests: %{},
        completed_quest_ids: MapSet.new()
      }
    }

    {:ok, character: character, state: state}
  end

  test "0x035B acceptance is durable and emits an encrypted state change", %{
    state: state,
    character: character
  } do
    assert {:reply_world_encrypted, :server_quest_state_change, packet, updated} =
             QuestHandler.handle(accept_payload(5861), state)

    assert Quests.get_quest(character.id, 5861).state == :accepted
    assert Map.has_key?(updated.session_data.active_quests, 5861)
    assert_state_packet(packet, 5861, 1)
    assert {:ok, ^updated} = QuestHandler.handle(accept_payload(5861), updated)
  end

  test "packed wrappers pass the inner quest opcode to a Connection struct", %{state: state} do
    inner = <<0x035B::little-16>> <> accept_payload(5861)
    payload = <<byte_size(inner) + 4::little-32>> <> inner

    assert {:reply_world_encrypted, :server_quest_state_change, _, updated} =
             PackedHandler.handle(payload, %{state | current_opcode: :client_packed})

    inner = <<0x035A::little-16, 5861::little-16>>
    payload = <<19, byte_size(inner) + 4::little-32>> <> inner

    assert {:reply_world_encrypted, :server_quest_state_change, packet, updated} =
             PackedWorldHandler.handle(payload, %{updated | current_opcode: :client_packed_world})

    assert updated.session_data.active_quests == %{}
    assert_state_packet(packet, 5861, 6)
  end

  test "a durable insert failure is not acknowledged in the session", %{
    state: state,
    character: character
  } do
    {:ok, _record} = Quests.accept_quest(character.id, 5861)

    assert {:error, :already_have_quest} =
             SessionQuestManager.accept_quest(state.session_data, character.id, 5861)

    assert {:ok, ^state} = QuestHandler.handle(accept_payload(5861), state)
  end

  test "kill progression survives reload and immediate turn-in before persistence tick", %{
    state: state,
    character: character
  } do
    {:ok, _} = Quests.accept_quest(character.id, 5861)

    quest = %{
      quest_id: 5861,
      state: :accepted,
      dirty: false,
      objectives: [%{index: 0, type: 2, data: 456, current: 0, target: 1}]
    }

    session = Map.put(state.session_data, :active_quests, %{5861 => quest})

    {session, packets} =
      SessionQuestManager.process_game_event(session, :kill, %{creature_id: 456})

    assert [{:server_quest_objective_update, _}, {:server_quest_state_change, achieved}] = packets
    assert_state_packet(achieved, 5861, 2)
    assert Quests.get_quest(character.id, 5861).state == :accepted

    {same_session, []} =
      SessionQuestManager.process_game_event(session, :kill, %{creature_id: 456})

    assert same_session.active_quests == session.active_quests

    assert {:ok, completed, {:server_quest_state_change, packet}} =
             SessionQuestManager.turn_in_quest(session, character.id, 5861)

    assert_state_packet(packet, 5861, 3)
    assert completed.active_quests == %{}
    assert Quests.get_quest(character.id, 5861) == nil
    assert Quests.has_completed?(character.id, 5861)
    assert {:ok, %{}, completed_ids} = QuestCache.load_quests_for_character(character.id)
    assert MapSet.member?(completed_ids, 5861)
  end

  test "quest definitions load all six objective slots in source order" do
    # Pin a real definition with a secondary objective, rather than allowing missing data.
    quest = Store.list(:quests) |> Enum.find(fn q -> Map.get(q, :objective01, 0) > 0 end)
    assert quest
    {:ok, loaded} = Store.get_quest_with_objectives(quest.id)

    ids =
      for key <- [
            :objective0,
            :objective01,
            :objective02,
            :objective03,
            :objective04,
            :objective05
          ],
          id = Map.get(quest, key, 0),
          id > 0,
          do: id

    assert Enum.map(loaded.objectives, & &1.id) == ids
    {:ok, cached} = QuestCache.create_session_quest(quest.id)
    assert length(cached.objectives) == length(ids)
    assert length(ids) >= 2
  end

  test "spawn GUIDs survive packet serialization and resolve the same NPC", %{state: state} do
    key = {888_991, 37}

    pid =
      start_supervised!(
        {Instance, world_id: elem(key, 0), instance_id: elem(key, 1), lazy_loading: true}
      )

    # Use a real spawn from the interrupted mission's starting world.
    {:ok, data} = Store.get_creature_spawns(426)

    spawn =
      Enum.find(data.creature_spawns, fn s ->
        match?({:ok, _, _}, CreatureState.build_from_spawn_def(s, 426, %{}))
      end)

    assert spawn
    {:ok, guid, creature} = CreatureState.build_from_spawn_def(spawn, 426, %{})
    assert EntityGuid.type(guid) == :creature
    assert guid != WorldManager.generate_guid(:player)
    Instance.add_entity(pid, creature.entity)
    _ = :sys.get_state(pid)

    {:ok, writer} =
      ServerEntityCreate.write(ServerEntityCreate.from_creature(creature), PacketWriter.new())

    <<wire_guid::little-32, _::binary>> = PacketWriter.to_binary(writer)
    assert wire_guid == guid
    assert {:ok, creature.entity.creature_id} == Instance.get_entity_creature_id(key, wire_guid)
    session = Map.merge(state.session_data, %{world_id: elem(key, 0), instance_id: elem(key, 1)})

    :ok =
      NpcHandler.handle_interact(
        self(),
        session.character_id,
        %ClientNpcInteract{npc_guid: guid, event: 37},
        session
      )

    assert_receive {:send_packet,
                    %BezgelorProtocol.Packets.World.ServerDialogStart{dialog_unit_id: ^guid}}

    :ok =
      NpcHandler.handle_interact(
        self(),
        session.character_id,
        %ClientNpcInteract{npc_guid: 0, event: 37},
        session
      )

    refute_receive {:send_packet, _}
  end

  test "movement updates instance, session and saved position with aligned relay", %{
    state: state,
    character: character
  } do
    key = {888_991, 38}

    pid =
      start_supervised!(
        {Instance, world_id: elem(key, 0), instance_id: elem(key, 1), lazy_loading: true}
      )

    guid = EntityGuid.new(:player, character.id)
    assert CreatureDeath.is_player_guid?(guid)
    refute CreatureDeath.is_player_guid?(EntityGuid.new(:creature, 1))
    entity = %Entity{guid: guid, type: :player}
    Instance.add_entity(pid, entity)
    _ = :sys.get_state(pid)

    # Observe the relay as a second session in this same world instance.
    :ok =
      WorldManager.register_session(character.account_id, character.id, character.name, self())

    WorldManager.set_entity_guid(
      character.account_id,
      EntityGuid.new(:player, character.id + 100_000)
    )

    WorldManager.update_session_zone(character.account_id, elem(key, 0), elem(key, 1))
    _ = :sys.get_state(WorldManager)
    on_exit(fn -> WorldManager.unregister_session(character.account_id) end)

    session =
      Map.merge(state.session_data, %{
        world_id: elem(key, 0),
        instance_id: elem(key, 1),
        in_world: true,
        entity_guid: guid,
        entity: entity
      })

    payload =
      PacketWriter.new()
      |> PacketWriter.write_u32(123)
      |> PacketWriter.write_u32(2)
      |> PacketWriter.write_bits(2, 5)
      |> PacketWriter.write_vector3({10.0, 20.0, 30.0})
      |> PacketWriter.write_bits(0, 1)
      |> PacketWriter.write_bits(14, 5)
      |> PacketWriter.write_vector3({0.0, 0.0, 1.5})
      |> PacketWriter.write_bits(0, 1)
      |> PacketWriter.flush_bits()
      |> PacketWriter.to_binary()

    assert {:ok, updated} = EntityCommandHandler.handle(payload, %{state | session_data: session})
    assert updated.session_data.entity.position == {10.0, 20.0, 30.0}
    assert updated.session_data.entity.rotation == {0.0, 0.0, 1.5}
    assert_receive {:"$gen_cast", {:send_packet, :server_entity_command, relay}}
    {:ok, ^guid, reader} = PacketReader.read_bits(PacketReader.new(relay), 32)
    {:ok, 123, reader} = PacketReader.read_bits(reader, 32)
    {:ok, 0, reader} = PacketReader.read_bits(reader, 1)
    {:ok, 0, reader} = PacketReader.read_bits(reader, 1)
    {:ok, 2, reader} = PacketReader.read_bits(reader, 5)

    assert {:ok, [%{type: 2, vector: position}, %{type: 14}], _} =
             BezgelorProtocol.EntityCommandDecoder.read(reader, 2)

    assert position == {10.0, 20.0, 30.0}
    assert {:ok, moved} = Instance.get_entity(key, guid)
    assert moved.position == {10.0, 20.0, 30.0}
    saved = Characters.get_character(character.id)
    assert {saved.location_x, saved.location_y, saved.location_z} == {10.0, 20.0, 30.0}

    assert {:ok, ^updated} =
             EntityCommandHandler.handle(<<123::little-32, 32::little-32>>, updated)

    assert {:ok, ^updated} =
             EntityCommandHandler.handle(<<123::little-32, 1::little-32, 2>>, updated)
  end

  test "a lethal first hit keeps the killer's credit and dead entity state", %{
    character: character
  } do
    key = {888_991, 39}

    start_supervised!(
      {Instance, world_id: elem(key, 0), instance_id: elem(key, 1), lazy_loading: true}
    )

    guid = EntityGuid.new(:player, character.id)

    :ok =
      WorldManager.register_session(character.account_id, character.id, character.name, self())

    WorldManager.set_entity_guid(character.account_id, guid)
    _ = :sys.get_state(WorldManager)
    on_exit(fn -> WorldManager.unregister_session(character.account_id) end)

    {:ok, creature_guid} = Instance.spawn_creature(key, 1, {0.0, 0.0, 0.0})
    {:ok, :killed, result} = Instance.damage_creature(key, creature_guid, guid, 100)
    assert result.participant_character_ids == [character.id]
    assert result.xp_reward == 10
    assert {:ok, dead} = Instance.get_entity(key, creature_guid)
    assert dead.health == 0
    refute Instance.creature_targetable?(key, creature_guid)
    assert {:error, :creature_dead} = Instance.damage_creature(key, creature_guid, guid, 100)
    previous_xp = Characters.get_character(character.id).total_xp
    :ok = BezgelorWorld.CombatBroadcaster.send_kill_rewards(guid, creature_guid, result)
    assert Characters.get_character(character.id).total_xp == previous_xp + 10
    assert_receive {:send_packet, :server_xp_gain, _}

    :ok =
      BezgelorWorld.CombatBroadcaster.notify_creature_kill_multi(
        elem(key, 0),
        elem(key, 1),
        result.participant_character_ids,
        result.creature_id
      )

    assert_receive {:game_event, :kill, %{creature_id: 1}}
    # Deliver the real timer message deterministically, without sleeping.
    send(
      GenServer.whereis(Instance.via_tuple(elem(key, 0), elem(key, 1))),
      {:respawn_creature, creature_guid}
    )

    assert {:ok, respawned} = Instance.get_entity(key, creature_guid)
    assert respawned.health == 100
    assert Instance.creature_targetable?(key, creature_guid)
  end

  test "walking beyond the initial 200-unit radius creates and removes creatures", %{state: state} do
    key = {888_991, 41}

    start_supervised!(
      {Instance, world_id: elem(key, 0), instance_id: elem(key, 1), lazy_loading: true}
    )

    {:ok, near_guid} = Instance.spawn_creature(key, 1, {0.0, 0.0, 0.0})
    {:ok, far_guid} = Instance.spawn_creature(key, 1, {450.0, 0.0, 0.0})
    session = Map.merge(state.session_data, %{world_id: elem(key, 0), instance_id: elem(key, 1)})

    {session, [{:server_entity_create, near}]} =
      BezgelorProtocol.CreatureVisibility.refresh(session, {0.0, 0.0, 0.0})

    assert <<near_guid::little-32>> == binary_part(near, 0, 4)
    assert {^session, []} = BezgelorProtocol.CreatureVisibility.refresh(session, {0.0, 0.0, 0.0})
    {session, packets} = BezgelorProtocol.CreatureVisibility.refresh(session, {450.0, 0.0, 0.0})

    assert [{:server_entity_destroy, <<^near_guid::little-32, 0>>}, {:server_entity_create, far}] =
             packets

    assert <<far_guid::little-32>> == binary_part(far, 0, 4)
    assert session.visible_creature_guids == MapSet.new([far_guid])
  end

  test "nonlethal damage updates both creature and entity registries" do
    key = {888_991, 40}

    start_supervised!(
      {Instance, world_id: elem(key, 0), instance_id: elem(key, 1), lazy_loading: true}
    )

    {:ok, guid} = Instance.spawn_creature(key, 1, {0.0, 0.0, 0.0})

    {:ok, :damaged, %{remaining_health: 75}} =
      Instance.damage_creature(key, guid, EntityGuid.new(:player, 1), 25)

    assert {:ok, entity} = Instance.get_entity(key, guid)
    assert entity.health == 75
    assert Instance.get_creature(key, guid).entity.health == 75
  end

  test "selection drives spell damage in a nondefault instance", %{
    state: state,
    character: character
  } do
    key = {888_991, 42}

    start_supervised!(
      {Instance, world_id: elem(key, 0), instance_id: elem(key, 1), lazy_loading: true}
    )

    {:ok, creature_guid} = Instance.spawn_creature(key, 1, {0.0, 0.0, 0.0})
    guid = EntityGuid.new(:player, character.id)

    session =
      Map.merge(state.session_data, %{
        world_id: elem(key, 0),
        instance_id: elem(key, 1),
        in_world: true,
        entity_guid: guid,
        position: {0.0, 0.0, 0.0},
        action_set_shortcuts: [%{slot: 0, spec_index: 0, spell_id: 3}]
      })

    {:ok, selected} =
      BezgelorProtocol.Handler.EntitySelectHandler.handle(<<creature_guid::little-32>>, %{
        state
        | session_data: session
      })

    assert selected.session_data.target_guid == creature_guid
    payload = <<123::little-32, 0::little-16, guid::little-32, 1>>

    assert {:reply_multi_world_encrypted, packets, _} =
             BezgelorWorld.Handler.SpellHandler.handle(payload, selected)

    assert Keyword.has_key?(packets, :server_spell_go)
    assert {:ok, damaged} = Instance.get_entity(key, creature_guid)
    assert damaged.health < 100

    {:ok, deselected} =
      BezgelorProtocol.Handler.EntitySelectHandler.handle(<<0::little-32>>, selected)

    assert deselected.session_data.target_guid == 0
  end

  test "quest progress game events are sent in the world encrypted envelope", %{state: state} do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listener)
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener)
    on_exit(fn -> Enum.each([client, server, listener], &:gen_tcp.close/1) end)

    quest = %{
      quest_id: 5861,
      state: :accepted,
      dirty: false,
      objectives: [%{index: 0, type: 2, data: 456, current: 0, target: 2}]
    }

    crypt = BezgelorCrypto.PacketCrypt.new(0x123456789ABCDEF)

    connection = %{
      state
      | connection_type: :world,
        socket: server,
        transport: :gen_tcp,
        encryption: crypt,
        state: :authenticated,
        session_data: Map.put(state.session_data, :active_quests, %{5861 => quest})
    }

    assert {:noreply, updated} =
             Connection.handle_info({:game_event, :kill, %{creature_id: 456}}, connection)

    assert hd(updated.session_data.active_quests[5861].objectives).current == 1
    assert {:ok, <<size::little-32, 0x03DC::little-16>>} = :gen_tcp.recv(client, 6, 1000)

    assert {:ok, <<_encrypted_size::little-32, encrypted::binary>>} =
             :gen_tcp.recv(client, size - 6, 1000)

    assert {:ok, <<0x0361::little-16, objective::binary>>} =
             BezgelorCrypto.PacketCrypt.decrypt(crypt, encrypted)

    assert {:ok, 5861, _} = PacketReader.read_bits(PacketReader.new(objective), 15)
  end

  test "quest reward XP survives a fresh character read", %{character: character} do
    quest =
      Store.list(:quests)
      |> Enum.find(fn q ->
        Map.get(q, :reward_xpOverride, 0) > 0 and Map.get(q, :reward_cashOverride, 0) == 0 and
          Map.get(q, :pushed_itemId0, 0) == 0 and Store.get_quest_rewards(q.id) == []
      end)

    assert quest
    previous_xp = Characters.get_character(character.id).total_xp

    assert {:ok, summary} =
             BezgelorWorld.Quest.RewardHandler.grant_quest_rewards(self(), character.id, quest.id)

    assert summary.xp > 0
    assert Characters.get_character(character.id).total_xp == previous_xp + summary.xp
  end

  defp accept_payload(quest_id) do
    PacketWriter.new()
    |> PacketWriter.write_bits(300, 9)
    |> PacketWriter.write_u32(0)
    |> PacketWriter.write_bits(quest_id, 15)
    |> PacketWriter.flush_bits()
    |> PacketWriter.to_binary()
  end

  defp assert_state_packet(packet, quest_id, state_id) do
    {:ok, ^quest_id, reader} = PacketReader.read_bits(PacketReader.new(packet), 15)
    assert {:ok, ^state_id, _} = PacketReader.read_bits(reader, 32)
  end
end
