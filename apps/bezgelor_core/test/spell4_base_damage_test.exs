defmodule BezgelorCore.Spell4BaseDamageTest do
  use ExUnit.Case, async: true
  alias BezgelorCore.{Spell4BaseDamage, Spell4Context}

  setup do
    effect =
      Map.merge(
        %{"effectType" => 8, "damageType" => 1, "dataBits00" => 0x3F800000, "dataBits01" => 0},
        Map.new(
          for i <- 0..3,
              {prefix, value} <- [{"parameterType0", 0}, {"parameterValue0", 0.0}],
              do: {prefix <> Integer.to_string(i), value}
        )
      )

    context = %Spell4Context{
      caster: %{
        type: :player,
        level: 50,
        health: 500,
        max_health: 1000,
        shield: 25,
        max_shield: 100,
        properties: %{0 => 1.25, 35 => 400, 36 => 200, 141 => 1.0, 142 => 1.0, 143 => 1.0}
      },
      target: %{health: 100, max_health: 400, shield: 10, max_shield: 50}
    }

    {:ok,
     effect: effect,
     context: context,
     formula: %{"ID" => 1266, "datafloat0" => 0.25, "datafloat01" => 0.25}}
  end

  test "documented assault and per-level terms have separate rounding", ctx do
    effect =
      Map.merge(ctx.effect, %{
        "parameterType00" => 12,
        "parameterValue00" => 0.10289999842643738,
        "parameterType01" => 10,
        "parameterValue01" => 5.5
      })

    assert {:ok,
            %{
              raw_damage: 286,
              property_term: 11.0,
              entity_term: 275.0,
              final_damage_verified: false
            }} = calculate(effect, ctx)
  end

  test "float32 accumulation rounds only after the entire property sum", ctx do
    effect =
      Map.merge(ctx.effect, %{
        "parameterType00" => 1,
        "parameterValue00" => 0.4,
        "parameterType01" => 1,
        "parameterValue01" => 0.4
      })

    assert {:ok, %{raw_damage: 1, property_term: 1.0}} = calculate(effect, ctx)
  end

  test "negative property sum rounds away from zero before fixed damage", ctx do
    effect =
      Map.merge(ctx.effect, %{
        "parameterType00" => 1,
        "parameterValue00" => -1.0,
        "dataBits01" => 10
      })

    assert {:ok, %{raw_damage: 8, property_term: -2.0}} = calculate(effect, ctx)
  end

  test "fixed damage is uint32 data, multiplier is IEEE float32 data", ctx do
    effect = Map.merge(ctx.effect, %{"dataBits00" => 0x3F000000, "dataBits01" => 11})
    assert {:ok, %{raw_damage: 5, multiplier: 0.5}} = calculate(effect, ctx)
  end

  test "the type multiplier does not multiply the rounded property term", ctx do
    effect =
      Map.merge(ctx.effect, %{
        "dataBits00" => 0x3F000000,
        "dataBits01" => 11,
        "parameterType00" => 1,
        "parameterValue00" => 1.0
      })

    assert {:ok, %{raw_damage: 7, property_term: 2.0}} = calculate(effect, ctx)
  end

  test "invalid fixed operands and nonpositive levels fail structural validation", ctx do
    assert {:error, :invalid_fixed_damage} = calculate(Map.put(ctx.effect, "dataBits01", -1), ctx)
    effect = Map.merge(ctx.effect, %{"parameterType00" => 10, "parameterValue00" => 1.0})
    context = %{ctx.context | caster: Map.put(ctx.context.caster, :level, 0)}

    assert {:error, {:invalid_stat, :level}} =
             Spell4BaseDamage.calculate(effect, context, ctx.formula)
  end

  test "support rating uses its own GameFormula field", ctx do
    effect = Map.merge(ctx.effect, %{"parameterType00" => 13, "parameterValue00" => 1.0})
    formula = Map.put(ctx.formula, "datafloat01", 0.5)
    assert {:ok, %{raw_damage: 100}} = Spell4BaseDamage.calculate(effect, ctx.context, formula)
  end

  test "health and shield operands are explicit, not stat-name guesses", ctx do
    for {type, expected} <- [
          {7, 400},
          {8, 1000},
          {10, 50},
          {14, 25},
          {15, 10},
          {16, 100},
          {17, 50},
          {19, 100},
          {21, 300},
          {22, 40},
          {23, 500},
          {25, 500},
          {26, 75}
        ] do
      effect = Map.merge(ctx.effect, %{"parameterType00" => type, "parameterValue00" => 1.0})
      assert {:ok, %{raw_damage: ^expected}} = calculate(effect, ctx)
    end
  end

  test "integer health subtraction precedes float32 conversion", ctx do
    effect = Map.merge(ctx.effect, %{"parameterType00" => 21, "parameterValue00" => 1.0})
    context = %{ctx.context | target: %{max_health: 16_777_217, health: 16_777_216}}
    assert {:ok, %{raw_damage: 1}} = Spell4BaseDamage.calculate(effect, context, ctx.formula)
  end

  test "unknown weapon, ambiguous item-budget and duplicate shield parameter codes fail closed",
       ctx do
    for type <- [6, 9, 18, 20, 24, 999] do
      effect = Map.merge(ctx.effect, %{"parameterType00" => type, "parameterValue00" => 1.0})
      assert {:error, {:unsupported_parameter, ^type}} = calculate(effect, ctx)
    end
  end

  test "no assault stat or damage multiplier is silently substituted", ctx do
    effect = Map.merge(ctx.effect, %{"parameterType00" => 12, "parameterValue00" => 1.0})
    caster = Map.put(ctx.context.caster, :properties, %{141 => 1.0, power: 99999})

    assert {:error, {:missing_operand, 35}} =
             Spell4BaseDamage.calculate(effect, %{ctx.context | caster: caster}, ctx.formula)

    caster = Map.put(ctx.context.caster, :properties, %{35 => 400})

    assert {:error, {:missing_operand, 141}} =
             Spell4BaseDamage.calculate(effect, %{ctx.context | caster: caster}, ctx.formula)

    caster = Map.put(ctx.context.caster, :properties, nil)

    assert {:error, {:invalid_operand_container, 35}} =
             Spell4BaseDamage.calculate(effect, %{ctx.context | caster: caster}, ctx.formula)

    assert {:error, :invalid_context} =
             Spell4BaseDamage.calculate(effect, %{ctx.context | caster: nil}, ctx.formula)
  end

  test "missing GameFormula, heals and NPC-specific calculations are not guessed", ctx do
    assert {:error, :missing_game_formula_1266} =
             Spell4BaseDamage.calculate(ctx.effect, ctx.context, %{})

    assert {:error, :unsupported_effect_type} =
             calculate(Map.put(ctx.effect, "effectType", 10), ctx)

    context = %{ctx.context | caster: Map.put(ctx.context.caster, :type, :creature)}

    assert {:error, :unsupported_caster_type} =
             Spell4BaseDamage.calculate(ctx.effect, context, ctx.formula)
  end

  test "nonfinite multipliers and uint32 overflow are rejected", ctx do
    for bits <- [0x7FC00000, 0x7F800000] do
      assert {:error, :invalid_numeric_data} =
               calculate(Map.put(ctx.effect, "dataBits00", bits), ctx)
    end

    effect = Map.merge(ctx.effect, %{"dataBits00" => 0x40000000, "dataBits01" => 0xFFFFFFFF})
    assert {:error, :base_damage_out_of_uint32_range} = calculate(effect, ctx)
  end

  defp calculate(effect, ctx), do: Spell4BaseDamage.calculate(effect, ctx.context, ctx.formula)
end
