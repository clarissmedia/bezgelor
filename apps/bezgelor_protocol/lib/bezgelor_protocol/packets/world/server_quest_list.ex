defmodule BezgelorProtocol.Packets.World.ServerQuestList do
  @moduledoc "Build 16042 ServerQuestInit: completed, inactive, active records and daily seed."
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.Packets.World.ServerQuestStateChange

  defstruct quests: [], completed: [], daily_random_seed: 0

  @impl true
  def opcode, do: :server_quest_list

  @impl true
  def write(packet, writer) do
    writer = PacketWriter.write_u32(writer, length(packet.completed))

    writer =
      Enum.reduce(packet.completed, writer, fn quest_id, acc ->
        acc
        |> PacketWriter.write_bits(quest_id, 15)
        |> PacketWriter.write_bits(0, 1)
      end)

    writer = writer |> PacketWriter.write_u32(0) |> PacketWriter.write_u32(length(packet.quests))
    writer = Enum.reduce(packet.quests, writer, &write_active/2)
    {:ok, writer |> PacketWriter.write_u64(packet.daily_random_seed) |> PacketWriter.flush_bits()}
  end

  defp write_active(quest, writer) do
    objectives = get_in(quest.progress, ["objectives"]) || []

    writer =
      writer
      |> PacketWriter.write_bits(quest.quest_id, 15)
      |> PacketWriter.write_bits(ServerQuestStateChange.state_id(quest.state), 4)
      |> PacketWriter.write_u32(0)
      |> PacketWriter.write_u32(0)
      |> PacketWriter.write_u32(length(objectives))

    writer =
      Enum.reduce(objectives, writer, fn obj, acc ->
        PacketWriter.write_u32(acc, obj["current"] || 0)
      end)

    writer = PacketWriter.write_u32(writer, 0)
    Enum.reduce(objectives, writer, fn _obj, acc -> PacketWriter.write_u32(acc, 0) end)
  end
end
