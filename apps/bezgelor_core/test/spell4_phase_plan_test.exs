defmodule BezgelorCore.Spell4PhasePlanTest do
  use ExUnit.Case, async: true
  alias BezgelorCore.{Spell4EventLedger, Spell4PhasePlan}

  test "phase evidence keeps order and masks without making them event identities" do
    spell = %{"ID" => 1, "castTime" => 1000}

    phases = [
      phase(2, 1, 366, 512),
      phase(1, 0, 0, 0),
      %{phase(3, 2, 200, 4) | "spell4IdOwner" => 9}
    ]

    effects = [effect(10, 8), effect(11, 2), effect(12, 4)]
    plan = Spell4PhasePlan.build(spell, phases, effects)
    assert Enum.map(plan.phases, & &1["ID"]) == [1, 2]
    assert Enum.map(plan.effects, & &1["ID"]) == [10, 11, 12]
    assert Enum.all?(plan.effects, &(&1["dataBits00"] == 43498))
    assert plan.recognized_triggers == []
    assert plan.timing_fields == %{"castTime" => 1000}
    assert {:error, :unverified_phase_triggers} = Spell4PhasePlan.schedule(plan)
  end

  test "the same occurrence is claimed once but repeated proxy edges stay distinct" do
    ledger = Spell4EventLedger.new(:cast_a)
    assert {:ok, ledger} = Spell4EventLedger.claim(ledger, :cast_a, {5883, 196_513, 100})

    assert {:ignored, :duplicate, ^ledger} =
             Spell4EventLedger.claim(ledger, :cast_a, {5883, 196_513, 100})

    assert {:ok, ledger} = Spell4EventLedger.claim(ledger, :cast_a, {5883, 196_515, 100})
    assert {:ok, ledger} = Spell4EventLedger.claim(ledger, :cast_a, {5883, 196_513, 101})
    assert MapSet.size(ledger.claimed) == 3
  end

  test "stale, cancelled and finished events cannot be claimed" do
    ledger = Spell4EventLedger.new(:cast_b)
    assert {:ignored, :stale_cast, ^ledger} = Spell4EventLedger.claim(ledger, :cast_a, :event)
    cancelled = Spell4EventLedger.cancel(ledger)

    assert {:ignored, :cancelled, ^cancelled} =
             Spell4EventLedger.claim(cancelled, :cast_b, :event)

    finished = Spell4EventLedger.finish(ledger)
    assert {:ignored, :finished, ^finished} = Spell4EventLedger.claim(finished, :cast_b, :event)
    assert {:ok, _} = Spell4EventLedger.claim(Spell4EventLedger.new(:cast_c), :cast_c, :event)
  end

  test "ledger storage has a hard bound" do
    ledger = %{Spell4EventLedger.new(:cast) | limit: 1}
    assert {:ok, ledger} = Spell4EventLedger.claim(ledger, :cast, :first)
    assert {:ignored, :event_limit, ^ledger} = Spell4EventLedger.claim(ledger, :cast, :second)
    assert {:ignored, :duplicate, ^ledger} = Spell4EventLedger.claim(ledger, :cast, :first)
  end

  defp phase(id, order, delay, flags),
    do: %{
      "ID" => id,
      "spell4IdOwner" => 1,
      "orderIndex" => order,
      "phaseDelay" => delay,
      "phaseFlags" => flags
    }

  defp effect(id, flags),
    do: %{
      "ID" => id,
      "spellId" => 1,
      "orderIndex" => 0,
      "effectType" => 26,
      "dataBits00" => 43498,
      "phaseFlags" => flags
    }
end
