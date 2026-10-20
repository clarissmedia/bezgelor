defmodule BezgelorCore.Spell4BaseDamage do
  @moduledoc """
  Diagnostic base-damage equation documented by NexusForever, not final damage.

  Source commit f9bb26efddbf304003fc8ebf484ac75bc6be84da:
  NexusForever.Game/Combat/DamageCalculator.cs CalculateBaseDamage,
  CalculateBasePropertyDamage, CalculateBaseEntityDamage;
  NexusForever.Game.Static/Spell/SpellEffectParameterType.cs; GameFormula 1266.

  Operations round to IEEE float32, the property sum rounds away from zero,
  and the nonnegative final base value truncates to uint32. Only documented
  operands are accepted. No mitigation, variance, crit, healing, phase,
  targeting or world mutation is authorized by a successful result.
  """

  alias BezgelorCore.Spell4Context

  @property_ids %{1 => 0, 2 => 1, 3 => 2, 4 => 3, 5 => 4, 11 => 40}

  def calculate(effect, %Spell4Context{caster: caster, target: target} = context, formula)
      when is_map(effect) and is_map(caster) and is_map(target) and is_map(formula) do
    try do
      require_value(effect["effectType"] == 8, :unsupported_effect_type)
      require_value(Map.get(context.caster, :type) == :player, :unsupported_caster_type)
      require_value(effect["damageType"] in [1, 2, 3], :unsupported_damage_type)
      require_value(formula["ID"] == 1266, :missing_game_formula_1266)

      {property_sum, entity_sum} =
        Enum.reduce(0..3, {0.0, 0.0}, fn index, {properties, entities} ->
          type = fetch(effect, "parameterType0#{index}")
          coefficient = f32(fetch(effect, "parameterValue0#{index}"))
          {property, entity} = operand(type, context, formula)

          {f32(properties + f32(property * coefficient)),
           f32(entities + f32(entity * coefficient))}
        end)

      rounded_property =
        if property_sum >= 0, do: Float.ceil(property_sum), else: Float.floor(property_sum)

      bits = fetch(effect, "dataBits00")
      require_value(is_integer(bits) and bits in 0..0xFFFFFFFF, :invalid_multiplier_bits)
      <<multiplier::little-float-32>> = <<bits::little-32>>
      fixed_bits = fetch(effect, "dataBits01")
      require_value(is_integer(fixed_bits) and fixed_bits in 0..0xFFFFFFFF, :invalid_fixed_damage)
      fixed = f32(fixed_bits)
      base = f32(rounded_property + f32(f32(fixed + entity_sum) * multiplier))
      scaled = f32(base * property(context.caster, effect["damageType"] + 140))
      require_value(scaled >= 0 and scaled < 4_294_967_296, :base_damage_out_of_uint32_range)

      {:ok,
       %{
         raw_damage: trunc(scaled),
         property_term: rounded_property,
         entity_term: entity_sum,
         multiplier: multiplier,
         final_damage_verified: false
       }}
    rescue
      _error in [ArithmeticError, ArgumentError, MatchError] -> {:error, :invalid_numeric_data}
    catch
      {:spell4_operand_error, reason} -> {:error, reason}
    end
  end

  def calculate(_effect, _context, _formula), do: {:error, :invalid_context}

  defp operand(0, _context, _formula), do: {0.0, 0.0}

  defp operand(type, context, _formula) when is_map_key(@property_ids, type),
    do: {property(context.caster, Map.fetch!(@property_ids, type)), 0.0}

  defp operand(type, context, formula) when type in [12, 13] do
    {id, field} = if type == 12, do: {35, "datafloat0"}, else: {36, "datafloat01"}
    {f32(property(context.caster, id) * f32(fetch(formula, field))), 0.0}
  end

  defp operand(7, context, _), do: {0.0, stat(context.target, :max_health)}
  defp operand(8, context, _), do: {0.0, stat(context.caster, :max_health)}
  defp operand(10, context, _), do: {0.0, stat(context.caster, :level)}
  defp operand(14, context, _), do: {0.0, stat(context.caster, :shield)}
  defp operand(15, context, _), do: {0.0, stat(context.target, :shield)}
  defp operand(16, context, _), do: {0.0, stat(context.caster, :max_shield)}
  defp operand(17, context, _), do: {0.0, stat(context.target, :max_shield)}
  defp operand(19, context, _), do: {0.0, stat(context.target, :health)}

  defp operand(21, context, _),
    do: {0.0, missing(context.target, :max_health, :health)}

  defp operand(22, context, _),
    do: {0.0, missing(context.target, :max_shield, :shield)}

  defp operand(23, context, _), do: {0.0, stat(context.caster, :health)}

  defp operand(25, context, _),
    do: {0.0, missing(context.caster, :max_health, :health)}

  defp operand(26, context, _),
    do: {0.0, missing(context.caster, :max_shield, :shield)}

  defp operand(type, _context, _),
    do: throw({:spell4_operand_error, {:unsupported_parameter, type}})

  defp property(entity, id), do: entity |> fetch(:properties) |> fetch(id) |> f32()

  defp stat(entity, name), do: entity |> raw_stat(name) |> f32()

  defp raw_stat(entity, name) do
    value = fetch(entity, name)

    require_value(
      is_integer(value) and value in 0..0xFFFFFFFF and
        (name != :level or value > 0),
      {:invalid_stat, name}
    )

    value
  end

  defp missing(entity, maximum, current) do
    maximum_value = raw_stat(entity, maximum)
    current_value = raw_stat(entity, current)
    require_value(maximum_value >= current_value, {:invalid_stat, current})
    f32(maximum_value - current_value)
  end

  defp fetch(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> throw({:spell4_operand_error, {:missing_operand, key}})
    end
  end

  defp fetch(_map, key), do: throw({:spell4_operand_error, {:invalid_operand_container, key}})

  defp require_value(true, _), do: :ok
  defp require_value(false, reason), do: throw({:spell4_operand_error, reason})

  defp f32(value) when is_number(value) do
    <<rounded::float-32>> = <<value * 1.0::float-32>>
    rounded
  end

  defp f32(_), do: throw({:spell4_operand_error, :invalid_numeric_data})
end
