defmodule BezgelorCore.Spell4TelegraphGeometry do
  @moduledoc """
  Diagnostic point containment from NexusForever f9bb26e Telegraph.cs and
  MathsExtensions.cs. This is NOT an authoritative WildStar target selector.

  Only zero-radius point targets/casters are supported. Entity collision
  radii, player-specific edge intersections, faction, visibility, line of
  sight, targetSelection and targetCount are deliberately unresolved.
  Coordinates are {X,Y,Z}; yaw 0 faces -Z, positive yaw faces toward -X.
  The reference uses XZ distance, including for cones (height is ignored).
  Arithmetic here is BEAM float64, not a bit-exact MathF emulation.
  """
  @pi :math.pi()

  def point_inside(row, origin, yaw, point, radii) do
    with :ok <- supported_radii(radii),
         true <- position?(origin) and position?(point) and is_number(yaw),
         true <- valid_row?(row) do
      position = offset(row, origin, yaw)
      rotation = yaw + row["rotationDegrees"] * @pi / 180
      distance = distance(position, point)

      case row["damageShapeEnum"] do
        0 ->
          {:ok, distance <= row["param00"]}

        shape when shape in [4, 8] ->
          {x, _, z} = position
          {tx, _, tz} = point
          angle = normalize(:math.atan2(z - tz, tx - x) - @pi / 2 - rotation)
          half_angle = (row["param02"] + row["param00"] / 2) * @pi / 360

          {:ok,
           distance >= row["param00"] and distance <= row["param01"] and
             abs(angle) <= half_angle}

        _ ->
          {:error, :unsupported_shape}
      end
    else
      false -> {:error, :invalid_geometry_input}
      error -> error
    end
  end

  # No candidate ordering or truncation until targetSelection=1 is established.
  def select_targets(_candidates, _constraints), do: {:error, :unverified_target_policy}

  defp supported_radii(%{caster: caster, target: target}) when caster == 0 and target == 0,
    do: :ok

  defp supported_radii(%{caster: caster, target: target})
       when is_number(caster) and caster >= 0 and is_number(target) and target >= 0,
       do: {:error, :unsupported_collision_radii}

  defp supported_radii(_), do: {:error, :missing_collision_radii}

  defp position?({x, y, z}), do: is_number(x) and is_number(y) and is_number(z)
  defp position?(_), do: false

  defp valid_row?(row) when is_map(row) do
    Enum.all?(
      ~w(param00 param01 param02 xPositionOffset yPositionOffset zPositionOffset rotationDegrees),
      &is_number(row[&1])
    ) and row["param00"] >= 0 and row["param01"] >= 0
  end

  defp valid_row?(_), do: false

  defp offset(row, origin, yaw) do
    {x, y, z} = point_at(origin, yaw + @pi / 2, row["zPositionOffset"])
    point_at({x, y + row["yPositionOffset"], z}, yaw + @pi, row["xPositionOffset"])
  end

  defp point_at({x, y, z}, angle, distance),
    do: {x + :math.cos(angle) * distance, y, z - :math.sin(angle) * distance}

  defp distance({x, _, z}, {tx, _, tz}), do: :math.sqrt((tx - x) ** 2 + (tz - z) ** 2)

  defp normalize(angle) do
    wrapped = angle - :math.floor((angle + @pi) / (2 * @pi)) * 2 * @pi
    if wrapped <= -@pi, do: wrapped + 2 * @pi, else: wrapped
  end
end
