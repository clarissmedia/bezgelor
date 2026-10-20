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

  test "all audited roots remain blocked before mutation, including Gate's speculative movement",
       ctx do
    for id <- BezgelorData.Spell4Catalog.spell_ids() do
      assert {:error, :unverified_spell4_combat} =
               SpellManager.cast_spell(ctx.guid, id, ctx.target, nil, %{}, self())

      assert SpellManager.get_cooldown(ctx.guid, id) == 0
      refute SpellManager.casting?(ctx.guid)
    end

    state =
      put_in(ctx.state, [:session_data, :action_set_shortcuts], [
        %{slot: 0, spec_index: 0, spell_id: 34355}
      ])

    assert {:reply_world_encrypted, :server_cast_result, <<1, 0, 34355::little-32>>, ^state} =
             cast(state)

    assert state.session_data.position == {0.0, 0.0, 0.0}
    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    assert Characters.get_character(ctx.character.id).total_xp == ctx.character.total_xp
  end

  test "real Quick Draw base arithmetic is inspectable but cannot authorize an impact", ctx do
    context = %BezgelorCore.Spell4Context{
      caster: %{type: :player, level: 50, properties: %{35 => 400, 141 => 1.0}},
      target: %{}
    }

    assert {:ok, audit} = BezgelorWorld.Spell4Diagnostics.inspect_spell(43468, context)
    assert audit.spell["castTime"] == 1000
    assert length(audit.phases) == 5
    assert length(audit.chain.edges) == 8
    assert map_size(audit.chain.spells) == 4
    assert map_size(audit.base_damage) == 2
    assert audit.constraints[43498]["targetCount"] == 3
    assert audit.constraints[43498]["maxRange"] == 25.0
    assert [%{"damageShapeEnum" => 8, "zPositionOffset" => -2.0}] = audit.telegraphs[43498]
    assert audit.geometry_execution == :unsupported

    for effect <- [99526, 99528] do
      assert {:ok, %{raw_damage: 286, final_damage_verified: false}} = audit.base_damage[effect]
    end

    refute audit.chain.execution_enabled
    assert audit.execution_blocker == :unverified_spell4_combat
    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    assert Characters.get_character(ctx.character.id).total_xp == ctx.character.total_xp
    assert BezgelorWorld.Spell4Diagnostics.inspect_spell(999_999_999) == :error
  end

  test "Charged Shot and Soothe threshold spells are retained without guessing a charge level",
       _ctx do
    for id <- [34718, 33140] do
      assert {:ok, audit} = BezgelorWorld.Spell4Diagnostics.inspect_spell(id)
      assert length(audit.thresholds) == 3
      refute audit.chain.execution_enabled
    end
  end

  test "Quick Draw exposes sourced phase order and repeated edges without a guessed schedule",
       ctx do
    assert {:ok, audit} = BezgelorWorld.Spell4Diagnostics.inspect_spell(43468)
    plan = audit.phase_plan

    assert Enum.map(
             plan.phases,
             &{&1["ID"], &1["orderIndex"], &1["phaseDelay"], &1["phaseFlags"]}
           ) == [
             {5882, 0, 0, 0},
             {5883, 1, 366, 512},
             {5884, 2, 200, 0},
             {5885, 3, 200, 4},
             {5886, 4, 234, 0}
           ]

    assert plan.timing_fields == %{
             "castTime" => 1000,
             "channelMaxTime" => 1000,
             "channelInitialDelay" => 366,
             "channelPulseTime" => 634
           }

    proxies = Enum.filter(plan.effects, &(&1["effectType"] == 26))
    assert length(proxies) == 8
    assert Enum.count(proxies, &(&1["dataBits00"] == 43498)) == 3
    assert Enum.count(proxies, &(&1["dataBits00"] == 43499)) == 3
    assert Enum.map(proxies, & &1["ID"]) |> Enum.uniq() |> length() == 8
    assert {:error, :unverified_phase_triggers} = BezgelorCore.Spell4PhasePlan.schedule(plan)
    assert audit.geometry_diagnostic == :nexusforever_zero_radius_points_only

    assert {:ok, true} =
             BezgelorCore.Spell4TelegraphGeometry.point_inside(
               hd(audit.telegraphs[43498]),
               {0, 0, 0},
               0,
               {0, 0, -25},
               %{caster: 0, target: 0}
             )

    assert {:error, :unverified_target_policy} =
             BezgelorCore.Spell4TelegraphGeometry.select_targets(
               [ctx.target],
               audit.constraints[43498]
             )

    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    assert Characters.get_character(ctx.character.id).total_xp == ctx.character.total_xp
  end

  test "sourced effect rows from all six classes reproduce base-only float32 vectors", ctx do
    context = %BezgelorCore.Spell4Context{
      caster: %{
        type: :player,
        level: 50,
        properties: %{35 => 400, 141 => 1.0, 142 => 1.0, 143 => 1.0}
      },
      target: %{}
    }

    # Explicit fixture properties, not generated live-character statistics.
    # Shred's 220 (not 221) preserves the source's float32 arithmetic and truncation.
    for {effect_id, expected} <- [
          {177_056, 385},
          {177_438, 710},
          {62159, 934},
          {83788, 220},
          {79090, 588},
          {99526, 286},
          {141_368, 223}
        ] do
      effect = BezgelorData.Spell4Catalog.row("Spell4Effects", effect_id)
      formula = BezgelorData.Spell4Catalog.row("GameFormula", 1266)

      assert {:ok, %{raw_damage: ^expected, final_damage_verified: false}} =
               BezgelorCore.Spell4BaseDamage.calculate(effect, context, formula)
    end

    assert Instance.get_creature(ctx.key, ctx.target).entity.health == 100
    assert Characters.get_character(ctx.character.id).total_xp == ctx.character.total_xp
  end
end
