defmodule BezgelorProtocol.Packets.World.ClientTurnInQuest do
  @moduledoc """
  Client turns in a completed quest.

  ## Wire Format
  quest_id      : 15 bits
  reward_choice : 15 bits
  is_communique : 1 bit
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:quest_id, :reward_choice, :is_communique]

  @impl true
  def opcode, do: :client_turn_in_quest

  @impl true
  def read(reader) do
    with {:ok, quest_id, reader} <- PacketReader.read_bits(reader, 15),
         {:ok, reward_choice, reader} <- PacketReader.read_bits(reader, 15),
         {:ok, is_communique, reader} <- PacketReader.read_bit(reader) do
      packet = %__MODULE__{
        quest_id: quest_id,
        is_communique: is_communique == 1,
        reward_choice: reward_choice
      }

      {:ok, packet, reader}
    end
  end
end
