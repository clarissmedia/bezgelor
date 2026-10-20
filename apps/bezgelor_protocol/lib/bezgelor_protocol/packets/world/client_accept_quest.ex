defmodule BezgelorProtocol.Packets.World.ClientAcceptQuest do
  @moduledoc """
  Client accepts a quest from NPC.

  ## Wire Format
  inventory_location : 9 bits (300 = no source item)
  bag_index          : 32 bits, without byte alignment
  quest_id           : 15 bits
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:quest_id, :inventory_location, :bag_index]

  @impl true
  def opcode, do: :client_accept_quest

  @impl true
  def read(reader) do
    with {:ok, inventory_location, reader} <- PacketReader.read_bits(reader, 9),
         {:ok, bag_index, reader} <- PacketReader.read_bits(reader, 32),
         {:ok, quest_id, reader} <- PacketReader.read_bits(reader, 15) do
      packet = %__MODULE__{
        quest_id: quest_id,
        inventory_location: inventory_location,
        bag_index: bag_index
      }

      {:ok, packet, reader}
    end
  end
end
