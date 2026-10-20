defmodule BezgelorData.Tbl do
  @moduledoc """
  Read-only ClientDB reader for reproducible Spell4 extraction.

  Layout follows NexusForever.GameTable.GameTable<T>.ReadEntries, including
  its extra four bytes after a string with offset1 == 0 followed by a scalar.
  Unlike the historical Python extractor, float32 values are not rounded to
  six decimal places. Field names remain strings; unknown types are rejected.
  """

  import Bitwise

  def read!(path), do: path |> File.read!() |> decode!()

  def decode!(
        <<0x4454424C::little-32, _version::little-32, _name_length::little-64,
          _unknown::little-64, record_size::little-64, field_count::little-64,
          field_offset::little-64, record_count::little-64, _total_size::little-64,
          record_offset::little-64, _max_id::little-64, _lookup::little-64, _unknown2::little-64,
          _rest::binary>> = data
      )
      when record_size > 0 and field_count > 0 do
    fields_start = 96 + field_offset
    names_start = fields_start + field_count * 24 + 15 &&& bnot(15)
    records_start = 96 + record_offset

    fields =
      for index <- 0..(field_count - 1) do
        <<length::little-64, offset::little-64, type::little-16, _::48>> =
          binary_part(data, fields_start + index * 24, 24)

        name =
          data
          |> binary_part(names_start + offset, length * 2)
          |> :unicode.characters_to_binary({:utf16, :little}, :utf8)
          |> String.trim_trailing(<<0>>)

        if not is_binary(name) or name == "", do: raise(ArgumentError, "invalid field name")
        {name, type}
      end

    if records_start + record_size * record_count > byte_size(data),
      do: raise(ArgumentError, "truncated records")

    rows =
      for index <- indices(record_count) do
        start = records_start + index * record_size
        record = binary_part(data, start, record_size)
        read_fields(fields, record, data, records_start, %{})
      end

    %{fields: fields, record_size: record_size, rows: rows}
  end

  def decode!(_data), do: raise(ArgumentError, "invalid ClientDB header")

  defp indices(0), do: []
  defp indices(count), do: 0..(count - 1)

  defp read_fields([], _record, _data, _base, row), do: row

  defp read_fields([{name, type} | fields], record, data, base, row) do
    {value, rest} = value(type, record, data, base, fields)
    read_fields(fields, rest, data, base, Map.put(row, name, value))
  end

  defp value(3, <<value::little-32, rest::binary>>, _, _, _), do: {value, rest}
  defp value(4, <<value::little-float-32, rest::binary>>, _, _, _), do: {value, rest}
  defp value(11, <<value::little-32, rest::binary>>, _, _, _), do: {value != 0, rest}
  defp value(20, <<value::little-64, rest::binary>>, _, _, _), do: {value, rest}

  defp value(130, <<first::little-32, second::little-32, rest::binary>>, data, base, next) do
    offset = max(first, second)
    value = if offset == 0, do: "", else: utf16_string(data, base + offset)

    rest =
      case {first, next} do
        {0, [{_, type} | _]} when type != 130 ->
          <<_padding::32, remaining::binary>> = rest
          remaining

        _ ->
          rest
      end

    {value, rest}
  end

  defp value(type, _record, _data, _base, _next),
    do: raise(ArgumentError, "unsupported or truncated ClientDB field #{type}")

  defp utf16_string(data, offset) do
    remaining = binary_part(data, offset, byte_size(data) - offset)
    bytes = utf16_bytes(remaining, []) |> Enum.reverse() |> IO.iodata_to_binary()

    case :unicode.characters_to_binary(bytes, {:utf16, :little}, :utf8) do
      value when is_binary(value) -> value
      _ -> raise ArgumentError, "invalid UTF-16 string"
    end
  end

  defp utf16_bytes(<<0::16, _::binary>>, bytes), do: bytes

  defp utf16_bytes(<<pair::binary-size(2), rest::binary>>, bytes),
    do: utf16_bytes(rest, [pair | bytes])

  defp utf16_bytes(_, _), do: raise(ArgumentError, "unterminated UTF-16 string")
end
