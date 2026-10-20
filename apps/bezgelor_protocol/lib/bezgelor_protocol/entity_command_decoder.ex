defmodule BezgelorProtocol.EntityCommandDecoder do
  @moduledoc "Read common 16042 entity commands without losing bit alignment. Unknown models stop decoding."
  alias BezgelorProtocol.PacketReader

  def read(reader, count) when count in 0..31, do: read_commands(reader, count, [])
  def read(_reader, _count), do: {:error, :invalid_command_count}

  defp read_commands(reader, 0, acc), do: {:ok, Enum.reverse(acc), reader}

  defp read_commands(reader, count, acc) do
    with {:ok, type, reader} <- PacketReader.read_bits(reader, 5) do
      case read_model(type, reader) do
        {:ok, command, reader} -> read_commands(reader, count - 1, [command | acc])
        {:error, :unsupported_command} -> {:unsupported, type, Enum.reverse(acc)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp read_model(type, reader) when type in [0, 1, 24, 27] do
    with {:ok, value, reader} <- PacketReader.read_bits(reader, 32),
         do: {:ok, %{type: type, value: value}, reader}
  end

  defp read_model(type, reader) when type in [2, 14] do
    with {:ok, x, reader} <- read_float(reader),
         {:ok, y, reader} <- read_float(reader),
         {:ok, z, reader} <- read_float(reader),
         {:ok, blend, reader} <- PacketReader.read_bit(reader) do
      {:ok, %{type: type, vector: {x, y, z}, blend: blend == 1}, reader}
    end
  end

  defp read_model(type, reader) when type in [8, 11] do
    with {:ok, _vector, reader} <- PacketReader.read_bits(reader, 48),
         {:ok, blend, reader} <- PacketReader.read_bit(reader),
         do: {:ok, %{type: type, blend: blend == 1}, reader}
  end

  defp read_model(type, reader) when type in [10, 13, 21, 26] do
    with {:ok, blend, reader} <- PacketReader.read_bit(reader),
         do: {:ok, %{type: type, blend: blend == 1}, reader}
  end

  defp read_model(22, reader) do
    with {:ok, _scale, reader} <- PacketReader.read_bits(reader, 16),
         {:ok, blend, reader} <- PacketReader.read_bit(reader),
         do: {:ok, %{type: 22, blend: blend == 1}, reader}
  end

  defp read_model(_type, _reader), do: {:error, :unsupported_command}

  defp read_float(reader) do
    with {:ok, value, reader} <- PacketReader.read_bits(reader, 32) do
      <<number::little-float-32>> = <<value::little-32>>
      if abs(number) <= 1_000_000, do: {:ok, number, reader}, else: {:error, :invalid_coordinate}
    end
  rescue
    MatchError -> {:error, :invalid_coordinate}
  end
end
