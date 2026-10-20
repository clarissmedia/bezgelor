defmodule BezgelorProtocol.EntityCommandDecoderTest do
  use ExUnit.Case, async: true
  alias BezgelorProtocol.{EntityCommandDecoder, PacketReader, PacketWriter}

  test "position, state and rotation retain alignment across commands" do
    reader =
      PacketWriter.new()
      |> PacketWriter.write_bits(24, 5)
      |> PacketWriter.write_u32(17)
      |> PacketWriter.write_bits(2, 5)
      |> PacketWriter.write_vector3({1.25, -2.5, 3.0})
      |> PacketWriter.write_bits(1, 1)
      |> PacketWriter.write_bits(14, 5)
      |> PacketWriter.write_vector3({0.0, 0.0, 1.5})
      |> PacketWriter.write_bits(0, 1)
      |> PacketWriter.flush_bits()
      |> PacketWriter.to_binary()
      |> PacketReader.new()

    assert {:ok,
            [
              %{type: 24, value: 17},
              %{type: 2, vector: {1.25, -2.5, 3.0}, blend: true},
              %{type: 14, vector: rotation, blend: false}
            ], _} = EntityCommandDecoder.read(reader, 3)

    assert rotation == {0.0, 0.0, 1.5}
  end

  test "unknown models stop without interpreting their payload as commands" do
    reader = PacketReader.new(<<3, 0, 0, 0>>)
    assert {:unsupported, 3, []} = EntityCommandDecoder.read(reader, 2)
  end

  test "truncation, oversized counts and nonfinite coordinates are rejected" do
    assert {:error, :eof} = EntityCommandDecoder.read(PacketReader.new(<<2>>), 1)

    assert {:error, :invalid_command_count} =
             EntityCommandDecoder.read(PacketReader.new(<<>>), 32)

    reader =
      PacketWriter.new()
      |> PacketWriter.write_bits(2, 5)
      |> PacketWriter.write_u32(0x7F800000)
      |> PacketWriter.flush_bits()
      |> PacketWriter.to_binary()
      |> PacketReader.new()

    assert {:error, :invalid_coordinate} = EntityCommandDecoder.read(reader, 1)
  end
end
