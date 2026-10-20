defmodule BezgelorProtocol.CreatureVisibility do
  @moduledoc "Refresh nearby creature entities when the player moves between visibility ranges."
  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.Packets.World.{ServerEntityCreate, ServerEntityDestroy}
  @view_range 200.0

  def refresh(session, position) do
    key = {session.world_id, session[:instance_id] || 1}

    creatures =
      apply(BezgelorWorld.World.Instance, :get_creatures_in_range, [key, position, @view_range])

    visible = MapSet.new(creatures, & &1.entity.guid)
    previous = session[:visible_creature_guids] || MapSet.new()

    creates =
      for creature <- creatures, not MapSet.member?(previous, creature.entity.guid) do
        encode(ServerEntityCreate, ServerEntityCreate.from_creature(creature))
      end

    destroys =
      for guid <- MapSet.difference(previous, visible) do
        encode(ServerEntityDestroy, %ServerEntityDestroy{guid: guid})
      end

    {Map.put(session, :visible_creature_guids, visible), destroys ++ creates}
  end

  defp encode(module, packet) do
    {:ok, writer} = module.write(packet, PacketWriter.new())
    {module.opcode(), PacketWriter.to_binary(writer)}
  end
end
