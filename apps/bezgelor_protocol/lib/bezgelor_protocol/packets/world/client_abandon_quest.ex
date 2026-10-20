defmodule BezgelorProtocol.Packets.World.ClientAbandonQuest do
  @moduledoc """
  Client abandons a quest.

  ## Wire Format
  quest_id : 15 bits
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:quest_id]

  @impl true
  def opcode, do: :client_abandon_quest

  @impl true
  def read(reader) do
    with {:ok, quest_id, reader} <- PacketReader.read_bits(reader, 15) do
      {:ok, %__MODULE__{quest_id: quest_id}, reader}
    end
  end
end
