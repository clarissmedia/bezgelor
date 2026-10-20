defmodule BezgelorProtocol.GameplayQuestWireTest do
  use ExUnit.Case, async: true
  alias BezgelorProtocol.{Opcode, PacketReader, PacketWriter}

  alias BezgelorProtocol.Packets.World.{
    ClientAcceptQuest,
    ClientAbandonQuest,
    ClientTurnInQuest,
    ServerQuestStateChange,
    ServerQuestObjectiveUpdate,
    ServerQuestList
  }

  test "build 16042 quest opcodes round trip" do
    for {opcode, value} <- [
          client_abandon_quest: 0x035A,
          client_accept_quest: 0x035B,
          server_quest_state_change: 0x035C,
          client_turn_in_quest: 0x035D,
          server_quest_list: 0x035F,
          server_quest_objective_update: 0x0361
        ] do
      assert Opcode.to_integer(opcode) == value
      assert Opcode.from_integer(value) == {:ok, opcode}
    end
  end

  test "truncated client quest packets fail rather than reading partial fields" do
    for {module, size} <- [
          {ClientAcceptQuest, 7},
          {ClientAbandonQuest, 2},
          {ClientTurnInQuest, 4}
        ],
        bytes <- 0..(size - 1) do
      assert {:error, :eof} = module.read(PacketReader.new(:binary.copy(<<0>>, bytes)))
    end
  end

  test "state and objective packets match independent LSB packed fixtures" do
    assert encode(ServerQuestStateChange, %ServerQuestStateChange{
             quest_id: 5861,
             state: :complete
           }) ==
             Base.decode16!("E5160100000000000000")

    assert encode(ServerQuestObjectiveUpdate, %ServerQuestObjectiveUpdate{
             quest_id: 5861,
             objective_index: 3,
             current: 7
           }) ==
             Base.decode16!("E5960100008003000000")
  end

  test "quest init retains objective and seed alignment after an active record" do
    packet = %ServerQuestList{
      completed: [42],
      daily_random_seed: 0x123456789ABCDEF0,
      quests: [
        %{
          quest_id: 5861,
          state: :complete,
          progress: %{"objectives" => [%{"current" => 7}, %{"current" => 2}]}
        }
      ]
    }

    reader = PacketReader.new(encode(ServerQuestList, packet))
    # Widths and order come from the local NexusForever ServerQuestInit reference.
    {values, _reader} =
      Enum.map_reduce(
        [32, 15, 1, 32, 32, 15, 4, 32, 32, 32, 32, 32, 32, 32, 32, 64],
        reader,
        fn bits, acc ->
          {:ok, value, acc} = PacketReader.read_bits(acc, bits)
          {value, acc}
        end
      )

    assert values == [1, 42, 0, 0, 1, 5861, 2, 0, 0, 2, 7, 2, 0, 0, 0, 0x123456789ABCDEF0]
  end

  test "empty quest init has the reference count and seed fields" do
    assert encode(ServerQuestList, %ServerQuestList{}) == :binary.copy(<<0>>, 20)
  end

  defp encode(module, packet) do
    {:ok, writer} = module.write(packet, PacketWriter.new())
    PacketWriter.to_binary(writer)
  end
end
