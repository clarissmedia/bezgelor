defmodule BezgelorProtocol.Packets.World.ServerQuestStateChange do
  @moduledoc "Build 16042 QuestStateChange: quest ID (15), state (32), random result (32)."
  @behaviour BezgelorProtocol.Packet.Writable
  alias BezgelorProtocol.PacketWriter

  defstruct [:quest_id, :state, random_result_id: 0]
  @impl true
  def opcode, do: :server_quest_state_change

  @impl true
  def write(packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.quest_id, 15)
      |> PacketWriter.write_u32(state_id(packet.state))
      |> PacketWriter.write_u32(packet.random_result_id)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  def state_id(:accepted), do: 1
  def state_id(:complete), do: 2
  def state_id(:completed), do: 3
  def state_id(:failed), do: 4
  def state_id(:abandoned), do: 6
  def state_id(state) when is_integer(state) and state in 0..7, do: state
end
