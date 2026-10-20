defmodule BezgelorCore.Spell4TelegraphGeometryTest do
  use ExUnit.Case, async: true
  alias BezgelorCore.Spell4TelegraphGeometry, as: Geometry
  @radii %{caster: 0, target: 0}

  test "sixteen observations emitted by unmodified NexusForever match the point diagnostic" do
    path =
      Path.expand("../../../docs/reports/2026-10-20-quick-draw-geometry-vectors.json", __DIR__)

    fixture = path |> File.read!() |> Jason.decode!()
    assert length(fixture["vectors"]) == 16

    for vector <- fixture["vectors"] do
      assert {:ok, vector["expected"]} ==
               Geometry.point_inside(
                 vector["row"],
                 List.to_tuple(vector["origin"]),
                 vector["yaw"],
                 List.to_tuple(vector["point"]),
                 @radii
               ),
             vector["name"]
    end
  end

  test "cone yaw zero faces negative Z, not a radius query" do
    row = cone()
    assert {:ok, true} = inside(row, {0, 0, -10})
    assert {:ok, false} = inside(row, {0, 0, 10})
    assert {:ok, false} = inside(row, {10, 0, 0})
    assert {:ok, true} = inside(row, {0, 900, -10})
  end

  test "inner and outer boundaries are inclusive in the reference algorithm" do
    for distance <- [3, 27], do: assert({:ok, true} == inside(cone(), {0, 0, -distance}))
    for distance <- [2.999, 27.001], do: assert({:ok, false} == inside(cone(), {0, 0, -distance}))
    # Param02 + Param00/2 = 16.5 degrees total, not a guessed 15-degree cone.
    for angle <- [-8.249, 8.249], do: assert({:ok, true} == inside(cone(), point(angle)))
    for angle <- [-8.251, 8.251], do: assert({:ok, false} == inside(cone(), point(angle)))
    # Exact angular boundary at axis-aligned 90-degree cone, avoiding trig inversion noise.
    row = %{cone() | "param00" => 0.0, "param02" => 90.0}
    assert {:ok, true} = inside(row, {10, 0, -10})
    assert {:ok, true} = inside(row, {-10, 0, -10})
  end

  test "translation, yaw, Z offset and rotation offset follow the reference coordinates" do
    assert {:ok, true} =
             Geometry.point_inside(cone(), {10, 2, 20}, :math.pi() / 2, {0, 2, 20}, @radii)

    assert {:ok, false} =
             Geometry.point_inside(cone(), {10, 2, 20}, :math.pi() / 2, {10, 2, 10}, @radii)

    row = %{cone() | "zPositionOffset" => -2.0}
    assert {:ok, true} = inside(row, {0, 0, -25})
    assert {:ok, false} = inside(row, {0, 0, -25.001})
    row = %{cone() | "rotationDegrees" => 90.0}
    assert {:ok, true} = inside(row, {-10, 0, 0})
    assert {:ok, false} = inside(row, {0, 0, -10})
  end

  test "missing collisions, nonzero radii, invalid coordinates and shapes are refused" do
    assert {:error, :missing_collision_radii} =
             Geometry.point_inside(cone(), {0, 0, 0}, 0, {0, 0, -10}, %{})

    assert {:error, :unsupported_collision_radii} =
             Geometry.point_inside(cone(), {0, 0, 0}, 0, {0, 0, -10}, %{caster: 1, target: 1})

    assert {:error, :invalid_geometry_input} =
             Geometry.point_inside(cone(), nil, 0, {0, 0, -10}, @radii)

    assert {:error, :invalid_geometry_input} = inside(%{}, {0, 0, -10})
    assert {:error, :unsupported_shape} = inside(%{cone() | "damageShapeEnum" => 2}, {0, 0, -10})
  end

  test "circle uses XZ distance and selection never silently truncates to three targets" do
    row = %{cone() | "damageShapeEnum" => 0, "param00" => 3.0}
    assert {:ok, true} = inside(row, {3, 100, 0})
    assert {:ok, false} = inside(row, {3.001, 0, 0})

    assert {:error, :unverified_target_policy} =
             Geometry.select_targets([4, 3, 2, 1], %{"targetCount" => 3, "targetSelection" => 1})
  end

  defp inside(row, point), do: Geometry.point_inside(row, {0, 0, 0}, 0, point, @radii)

  defp point(degrees),
    do:
      {:math.sin(degrees * :math.pi() / 180) * 10, 0, -:math.cos(degrees * :math.pi() / 180) * 10}

  defp cone,
    do: %{
      "damageShapeEnum" => 8,
      "param00" => 3.0,
      "param01" => 27.0,
      "param02" => 15.0,
      "rotationDegrees" => 0.0,
      "xPositionOffset" => 0.0,
      "yPositionOffset" => 0.0,
      "zPositionOffset" => 0.0
    }
end
