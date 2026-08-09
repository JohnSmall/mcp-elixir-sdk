defmodule MCP.Client.SubscriptionHandle do
  @moduledoc """
  Ownership token for consuming a client subscription.

  Handles are created by the client subscription API. Events are consumed with
  `next/2`, and `close/1` is idempotent.
  """

  @enforce_keys [:id, :worker, :monitor_ref]
  defstruct [:id, :worker, :monitor_ref]

  @opaque t :: %__MODULE__{
            id: String.t() | number(),
            worker: pid(),
            monitor_ref: reference()
          }

  @doc false
  @spec new(String.t() | number(), pid()) :: t()
  def new(id, worker) when is_pid(worker) do
    %__MODULE__{id: id, worker: worker, monitor_ref: Process.monitor(worker)}
  end

  @doc "Returns the next subscription event, or a terminal/local error."
  @spec next(t(), timeout()) :: {:ok, term()} | {:error, term()}
  def next(%__MODULE__{} = handle, timeout \\ 5_000) do
    case take_down(handle) do
      {:down, reason} -> {:error, normalize_reason(reason)}
      :none -> next_from_worker(handle, timeout)
    end
  end

  @doc "Closes the subscription. Calling this function more than once is safe."
  @spec close(t()) :: :ok
  def close(%__MODULE__{} = handle) do
    case take_down(handle) do
      {:down, _reason} -> :ok
      :none -> call_close(handle)
    end
  end

  defp call_next(handle, timeout) do
    GenServer.call(handle.worker, :next, timeout)
  catch
    :exit, reason -> {:error, down_or_call_reason(handle, reason)}
  end

  defp next_from_worker(handle, timeout) do
    case Process.info(handle.worker, :status) do
      nil -> {:error, :closed}
      {:status, _status} -> call_next(handle, timeout)
    end
  end

  defp call_close(handle) do
    GenServer.call(handle.worker, :close)
  catch
    :exit, _reason -> :ok
  end

  defp down_or_call_reason(handle, call_reason) do
    case take_down(handle) do
      {:down, reason} -> normalize_reason(reason)
      :none -> normalize_reason(call_reason)
    end
  end

  defp take_down(%__MODULE__{monitor_ref: ref, worker: worker}) do
    receive do
      {:DOWN, ^ref, :process, ^worker, reason} -> {:down, reason}
    after
      0 -> :none
    end
  end

  defp normalize_reason(:queue_overflow), do: :queue_overflow
  defp normalize_reason({:queue_overflow, _call}), do: :queue_overflow
  defp normalize_reason(:normal), do: :closed
  defp normalize_reason({:normal, _call}), do: :closed
  defp normalize_reason(:noproc), do: :closed
  defp normalize_reason({:noproc, _call}), do: :closed
  defp normalize_reason({:timeout, _call}), do: :timeout
  defp normalize_reason(reason), do: reason
end
