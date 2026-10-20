defmodule BezgelorWorld.Handler.NpcHandlerDialogueTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.Handler.NpcHandler
  alias BezgelorProtocol.Packets.World.{ClientNpcInteract, ServerDialogStart}
  alias BezgelorWorld.World.Instance
  alias BezgelorCore.{Entity, EntityGuid}

  setup do
    key = {30_001, 91}

    pid =
      start_supervised!(
        {Instance, world_id: elem(key, 0), instance_id: elem(key, 1), lazy_loading: true}
      )

    for counter <- [12345, 99999] do
      Instance.add_entity(pid, %Entity{
        guid: EntityGuid.new(:creature, counter),
        type: :creature,
        creature_id: 53532
      })
    end

    _ = :sys.get_state(pid)
    {:ok, session: %{character_id: 1, world_id: elem(key, 0), instance_id: elem(key, 1)}}
  end

  describe "handle_interact/4 with dialogue event" do
    test "sends ServerDialogStart for event 37", %{session: session} do
      guid = EntityGuid.new(:creature, 12345)
      packet = %ClientNpcInteract{npc_guid: guid, event: 37}
      NpcHandler.handle_interact(self(), 1, packet, session)
      assert_receive {:send_packet, %ServerDialogStart{dialog_unit_id: ^guid, unused: false}}
    end

    test "sends ServerDialogStart for dialogue event with different GUID", %{session: session} do
      guid = EntityGuid.new(:creature, 99999)
      packet = %ClientNpcInteract{npc_guid: guid, event: ClientNpcInteract.event_dialogue()}
      NpcHandler.handle_interact(self(), 1, packet, session)
      assert_receive {:send_packet, %ServerDialogStart{dialog_unit_id: ^guid}}
    end

    test "ignores zero and unregistered GUIDs", %{session: session} do
      for guid <- [0, EntityGuid.new(:creature, 88)] do
        NpcHandler.handle_interact(
          self(),
          1,
          %ClientNpcInteract{npc_guid: guid, event: 37},
          session
        )
      end

      refute_receive {:send_packet, _}
    end
  end
end
