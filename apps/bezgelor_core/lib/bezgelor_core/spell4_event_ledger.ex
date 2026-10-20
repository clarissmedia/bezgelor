defmodule BezgelorCore.Spell4EventLedger do
  @moduledoc """
  Pure cast-scoped idempotency guard for a future verified event producer.

  It does not authorize, schedule or interpret Spell4 events. The producer
  must supply an occurrence identity including the original effect/edge ID
  and target. Using only a proxy spell ID would collapse distinct references.
  A new ledger/token belongs to each cast, as in SpellManager's cast lifecycle.
  """
  defstruct [:token, status: :active, claimed: MapSet.new(), limit: 4096]

  def new(token), do: %__MODULE__{token: token}

  def claim(%__MODULE__{token: token} = ledger, token, identity) do
    cond do
      ledger.status != :active -> {:ignored, ledger.status, ledger}
      MapSet.member?(ledger.claimed, identity) -> {:ignored, :duplicate, ledger}
      MapSet.size(ledger.claimed) >= ledger.limit -> {:ignored, :event_limit, ledger}
      true -> {:ok, %{ledger | claimed: MapSet.put(ledger.claimed, identity)}}
    end
  end

  def claim(%__MODULE__{} = ledger, _token, _identity), do: {:ignored, :stale_cast, ledger}

  def cancel(%__MODULE__{} = ledger), do: %{ledger | status: :cancelled}
  def finish(%__MODULE__{} = ledger), do: %{ledger | status: :finished}
end
