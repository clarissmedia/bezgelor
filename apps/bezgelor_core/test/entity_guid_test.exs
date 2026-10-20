defmodule BezgelorCore.EntityGuidTest do
  use ExUnit.Case, async: true
  alias BezgelorCore.{Entity, EntityGuid}

  test "wire IDs preserve distinct type namespaces without uint32 truncation" do
    ids =
      for type <- [:player, :creature, :object, :vehicle, :corpse] do
        guid = EntityGuid.new(type, 123)
        assert guid in 1..0xFFFFFFFF
        <<decoded::little-32>> = <<guid::little-32>>
        assert decoded == guid
        assert EntityGuid.type(decoded) == type
        guid
      end

    assert length(Enum.uniq(ids)) == 5
    assert EntityGuid.new(:player, 1) == 0x20000001
    assert EntityGuid.new(:creature, 1) == 0x40000001
    assert EntityGuid.type(0) == :unknown
    assert EntityGuid.type(0x1000000000000001) == :unknown
  end

  test "invalid counters cannot wrap into another namespace" do
    for counter <- [0, -1, 0x20000000] do
      assert_raise ArgumentError, fn -> EntityGuid.new(:creature, counter) end
    end

    assert EntityGuid.new(:corpse, 0x1FFFFFFF) == 0xBFFFFFFF
  end

  test "corpse IDs remain addressable on the wire" do
    creature = %Entity{guid: EntityGuid.new(:creature, 7), type: :creature}
    corpse = Entity.create_corpse(creature, [{1, 1}])
    assert EntityGuid.type(corpse.guid) == :corpse
    assert corpse.guid <= 0xFFFFFFFF
    assert corpse.source_guid == creature.guid
  end
end
