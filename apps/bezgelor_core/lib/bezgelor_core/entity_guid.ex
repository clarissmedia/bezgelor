defmodule BezgelorCore.EntityGuid do
  @moduledoc "32-bit wire entity IDs: 3 type bits and a nonzero 29-bit counter."
  import Bitwise

  @types %{player: 1, creature: 2, object: 3, vehicle: 4, corpse: 5}
  @max_counter 0x1FFFFFFF

  def new(type, counter) when is_integer(counter) and counter in 1..@max_counter do
    Map.fetch!(@types, type) <<< 29 ||| counter
  end

  def new(_type, _counter), do: raise(ArgumentError, "Entity ID counter exhausted or invalid")

  def type(guid) when is_integer(guid) and guid > 0 and guid <= 0xFFFFFFFF do
    code = guid >>> 29
    Enum.find_value(@types, :unknown, fn {name, value} -> if value == code, do: name end)
  end

  def type(_guid), do: :unknown
end
