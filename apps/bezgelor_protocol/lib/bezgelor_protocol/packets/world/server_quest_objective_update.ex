defmodule BezgelorProtocol.Packets.World.ServerQuestObjectiveUpdate do
  @moduledoc "Build 16042 objective update: quest ID (15), index (32), progress (32)."
  @behaviour BezgelorProtocol.Packet.Writable
  alias BezgelorProtocol.PacketWriter

  defstruct [:quest_id, :objective_index, :current]
  @impl true
  def opcode, do: :server_quest_objective_update

  @impl true
  def write(packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.quest_id, 15)
      |> PacketWriter.write_u32(packet.objective_index)
      |> PacketWriter.write_u32(packet.current)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
