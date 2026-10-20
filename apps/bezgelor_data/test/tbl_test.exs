defmodule BezgelorData.TblTest do
  use ExUnit.Case, async: true
  alias BezgelorData.Tbl

  test "the string padding used by NexusForever does not shift scalar columns" do
    fields = [{"ID", 3}, {"description", 130}, {"baseId", 3}, {"coefficient", 4}]

    record =
      <<43468::little-32, 0::little-32, 24::little-32, 0::little-32, 27638::little-32,
        0.1029::little-float-32>>

    table =
      table(
        fields,
        record,
        :unicode.characters_to_binary("Quick Draw\0", :utf8, {:utf16, :little})
      )

    assert %{rows: [row], record_size: 24} = Tbl.decode!(table)
    assert row["ID"] == 43468
    assert row["description"] == "Quick Draw"
    assert row["baseId"] == 27638
    assert row["coefficient"] == 0.10289999842643738
    refute row["coefficient"] == 0.1029
  end

  test "a string with a nonzero first offset does not consume padding" do
    record = <<8::little-32, 16::little-32, 0::little-32, 99::little-32>>
    data = table([{"ID", 3}, {"text", 130}, {"value", 3}], record, <<65, 0, 0, 0>>)
    assert %{rows: [%{"text" => "A", "value" => 99}]} = Tbl.decode!(data)
  end

  test "unsigned integers, booleans and float32 are decoded without guessing" do
    data =
      table(
        [{"ID", 3}, {"flag", 11}, {"wide", 20}, {"value", 4}],
        <<1::little-32, 1::little-32, 0x100000001::little-64, -0.25::little-float-32>>
      )

    assert %{rows: [%{"ID" => 1, "flag" => true, "wide" => 0x100000001, "value" => -0.25}]} =
             Tbl.decode!(data)
  end

  test "invalid headers, truncated records and unknown field types are rejected" do
    assert_raise ArgumentError, fn -> Tbl.decode!(<<0::768>>) end
    good = table([{"ID", 3}], <<1::little-32>>)
    assert_raise ArgumentError, fn -> Tbl.decode!(binary_part(good, 0, byte_size(good) - 1)) end
    assert_raise ArgumentError, fn -> Tbl.decode!(table([{"ID", 999}], <<1::little-32>>)) end
  end

  defp table(fields, record, strings \\ <<>>) do
    {definitions, names} =
      Enum.map_reduce(fields, <<>>, fn {name, type}, names ->
        encoded = :unicode.characters_to_binary(name <> "\0", :utf8, {:utf16, :little})

        definition =
          <<div(byte_size(encoded), 2)::little-64, byte_size(names)::little-64, type::little-16,
            0::48>>

        {definition, names <> encoded}
      end)

    definitions = IO.iodata_to_binary(definitions)
    padding = rem(16 - rem(96 + byte_size(definitions), 16), 16)
    metadata = definitions <> :binary.copy(<<0>>, padding) <> names
    size = byte_size(record)

    header =
      <<0x4454424C::little-32, 0::little-32, 0::little-64, 0::little-64, size::little-64,
        length(fields)::little-64, 0::little-64, 1::little-64,
        size + byte_size(strings)::little-64, byte_size(metadata)::little-64, 1::little-64,
        0::little-64, 0::little-64>>

    header <> metadata <> record <> strings
  end
end
