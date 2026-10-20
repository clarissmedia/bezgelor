defmodule BezgelorProtocol.Handler.EntityCommandHandler do
  @moduledoc """
  Handles ClientEntityCommand packets (opcode 0x0637).

  This is the primary movement packet sent by the client. It contains
  a list of entity commands that describe movement, rotation, and state changes.

  ## Packet Structure (from NexusForever)

  - Time: uint32 - client timestamp
  - CommandCount: uint32 - number of commands
  - Commands: list of EntityCommand structures
    - Command: 5 bits - EntityCommand enum value
    - Model: variable - command-specific data

  ## EntityCommand Types

  - SetTime (0): Time synchronization
  - SetPlatform (1): Platform attachment
  - SetPosition (2): Position update
  - SetPositionKeys (3): Position keyframes
  - SetPositionPath (4): Path following
  - SetPositionSpline (5): Spline movement
  - SetPositionMultiSpline (6): Multi-spline movement
  - SetPositionProjectile (7): Projectile movement
  - SetVelocity (8): Velocity update
  - SetVelocityKeys (9): Velocity keyframes
  - SetVelocityDefaults (10): Reset velocity
  - SetMove (11): Movement state
  - SetMoveKeys (12): Movement keyframes
  - SetMoveDefaults (13): Reset movement
  - SetRotation (14): Rotation update
  - SetRotationKeys (15): Rotation keyframes
  - SetRotationSpline (16): Rotation spline
  - SetRotationMultiSpline (17): Multi-spline rotation
  - SetRotationFaceUnit (18): Face target unit
  - SetRotationFacePosition (19): Face position
  - SetRotationSpin (20): Spin rotation
  - SetRotationDefaults (21): Reset rotation
  - SetScale (22): Scale update
  - SetScaleKeys (23): Scale keyframes
  - SetState (24): State update
  - SetStateKeys (25): State keyframes
  - SetStateDefault (26): Reset state
  - SetMode (27): Mode update
  - SetModeKeys (28): Mode keyframes
  """

  @behaviour BezgelorProtocol.Handler
  @compile {:no_warn_undefined,
            [BezgelorWorld.VisibilityBroadcaster, BezgelorWorld.World.Instance]}

  alias BezgelorProtocol.PacketReader
  alias BezgelorWorld.VisibilityBroadcaster

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:ok, time, reader} <- PacketReader.read_uint32(reader),
         {:ok, command_count, reader} <- PacketReader.read_uint32(reader),
         true <- command_count <= 31,
         {:ok, commands} <- decode_commands(reader, command_count) do
      if command_count > 0 do
        Logger.debug("[EntityCommand] Received #{command_count} commands at time #{time}")
      end

      # Broadcast movement to other players in zone
      state = update_server_position(commands, state)
      broadcast_movement(payload, state)

      # Position persistence handled by:
      # - MovementHandler: periodic saves every 5 seconds
      # - Connection.terminate: save on logout/disconnect
      # Anti-cheat: MovementSpeedUpdateHandler validates speed bounds

      {:ok, state}
    else
      false ->
        Logger.warning("[EntityCommand] Too many commands to relay")
        {:ok, state}

      {:error, reason} ->
        Logger.warning("[EntityCommand] Failed to parse: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Broadcast player movement to other players in the same zone
  defp broadcast_movement(payload, state) do
    entity_guid = state.session_data[:entity_guid]
    zone_id = state.session_data[:world_id]
    instance_id = state.session_data[:instance_id] || 1

    if entity_guid && zone_id do
      # Build a server entity command packet from the client data
      # The format is similar - we just need to prepend the entity GUID
      # Client sends: time(4) + count(4) + commands
      # Server sends: guid(4) + time(4) + flags(1 bit) + server_controlled(1 bit) + count(5 bits) + commands

      # For simplicity, we relay the raw client movement data with the entity GUID prepended
      # This works because ServerEntityCommand has a similar structure
      movement_packet = build_server_entity_command(entity_guid, payload)

      VisibilityBroadcaster.broadcast_player_movement(
        entity_guid,
        movement_packet,
        zone_id,
        instance_id
      )
    end
  end

  # Build a ServerEntityCommand packet from client movement data
  defp build_server_entity_command(entity_guid, client_payload) do
    alias BezgelorProtocol.PacketWriter

    # Parse client payload to extract time and commands
    reader = PacketReader.new(client_payload)

    case PacketReader.read_uint32(reader) do
      {:ok, time, reader} ->
        case PacketReader.read_uint32(reader) do
          {:ok, command_count, _reader} ->
            # Get remaining bytes for commands (after time and count)
            commands_start = 8

            commands_data =
              binary_part(
                client_payload,
                commands_start,
                byte_size(client_payload) - commands_start
              )

            # Build server packet
            writer =
              PacketWriter.new()
              |> PacketWriter.write_u32(entity_guid)
              |> PacketWriter.write_u32(time)
              # time_reset = false
              |> PacketWriter.write_bits(0, 1)
              # server_controlled = false
              |> PacketWriter.write_bits(0, 1)
              |> PacketWriter.write_bits(command_count, 5)

            # The command data format is the same between client and server
            # so we can append the raw command bytes
            writer =
              writer |> PacketWriter.write_bytes_bits(commands_data) |> PacketWriter.flush_bits()

            PacketWriter.to_binary(writer)

          _ ->
            # Fallback: just prepend guid to original payload
            <<entity_guid::little-32>> <> client_payload
        end

      _ ->
        # Fallback: just prepend guid to original payload
        <<entity_guid::little-32>> <> client_payload
    end
  end

  defp decode_commands(reader, count) do
    case BezgelorProtocol.EntityCommandDecoder.read(reader, count) do
      {:ok, commands, _reader} ->
        {:ok, commands}

      {:unsupported, type, commands} ->
        Logger.debug("EntityCommand model #{type} not decoded; retaining verified prefix only")
        {:ok, commands}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_server_position(commands, state) do
    Enum.reduce(commands, state, fn
      %{type: 2, vector: position}, acc ->
        update_position(position, acc)

      %{type: 14, vector: rotation}, acc ->
        acc = put_in(acc.session_data[:rotation], rotation)

        case acc.session_data[:entity] do
          nil -> acc
          entity -> put_in(acc.session_data[:entity], %{entity | rotation: rotation})
        end

      _command, acc ->
        acc
    end)
  end

  defp update_position(position, state) do
    world_id = state.session_data[:world_id]
    guid = state.session_data[:entity_guid]

    if state.session_data[:in_world] == true and not is_nil(world_id) and not is_nil(guid) do
      key = {world_id, state.session_data[:instance_id] || 1}

      case BezgelorWorld.World.Instance.update_entity_position(key, guid, position) do
        :ok -> persist_position(position, state)
        :error -> state
      end
    else
      state
    end
  end

  defp persist_position(position, state) do
    {session, packets} = BezgelorProtocol.CreatureVisibility.refresh(state.session_data, position)
    Enum.each(packets, fn {opcode, payload} -> send(self(), {:send_packet, opcode, payload}) end)
    state = %{state | session_data: session}
    state = put_in(state.session_data[:position], position)

    state =
      case state.session_data[:entity] do
        nil -> state
        entity -> put_in(state.session_data[:entity], %{entity | position: position})
      end

    # Use nil for the initial save: monotonic time can be negative.
    now = System.monotonic_time(:millisecond)
    last = state.session_data[:last_position_save]

    if is_nil(last) or now - last >= 5_000 do
      character_id = state.session_data[:character_id]
      {x, y, z} = position

      case BezgelorDb.Characters.get_character(character_id) do
        nil ->
          state

        character ->
          case BezgelorDb.Characters.update_position(character, %{
                 location_x: x,
                 location_y: y,
                 location_z: z
               }) do
            {:ok, _character} ->
              put_in(state.session_data[:last_position_save], now)

            {:error, reason} ->
              Logger.warning("Position persistence failed: #{inspect(reason)}")
              state
          end
      end
    else
      state
    end
  end
end
