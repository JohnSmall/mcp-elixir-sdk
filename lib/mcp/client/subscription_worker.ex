defmodule MCP.Client.SubscriptionWorker do
  @moduledoc false

  use GenServer

  @default_queue_limit 256

  defstruct [
    :id,
    :owner,
    :owner_ref,
    :waiter,
    queue: :queue.new(),
    queue_size: 0,
    queue_limit: @default_queue_limit
  ]

  @type request_id :: String.t() | number()

  @spec start(GenServer.server(), request_id(), pid(), keyword()) ::
          DynamicSupervisor.on_start_child() | {:error, {:invalid_queue_limit, term()}}
  def start(supervisor, id, owner, opts \\ []) do
    queue_limit = Keyword.get(opts, :queue_limit, @default_queue_limit)

    if is_integer(queue_limit) and queue_limit > 0 do
      DynamicSupervisor.start_child(supervisor, {__MODULE__, {id, owner, queue_limit}})
    else
      {:error, {:invalid_queue_limit, queue_limit}}
    end
  end

  @spec enqueue(pid(), term()) :: :ok
  def enqueue(worker, event) do
    GenServer.cast(worker, {:enqueue, event})
  end

  @spec start_link({request_id(), pid(), pos_integer()}) :: GenServer.on_start()
  def start_link({id, owner, queue_limit}) do
    GenServer.start_link(__MODULE__, {id, owner, queue_limit})
  end

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary,
      type: :worker
    }
  end

  @impl true
  def init({id, owner, queue_limit}) do
    state = %__MODULE__{
      id: id,
      owner: owner,
      owner_ref: Process.monitor(owner),
      queue_limit: queue_limit
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:next, from, %__MODULE__{queue_size: 0, waiter: nil} = state) do
    {:noreply, %{state | waiter: from}}
  end

  def handle_call(:next, _from, %__MODULE__{queue_size: 0} = state) do
    {:reply, {:error, :concurrent_next}, state}
  end

  def handle_call(:next, _from, %__MODULE__{} = state) do
    {{:value, event}, queue} = :queue.out(state.queue)
    {:reply, {:ok, event}, %{state | queue: queue, queue_size: state.queue_size - 1}}
  end

  def handle_call(:close, _from, %__MODULE__{} = state) do
    reply_waiter(state.waiter, {:error, :closed})
    {:stop, :normal, :ok, %{state | waiter: nil}}
  end

  @impl true
  def handle_cast({:enqueue, event}, %__MODULE__{waiter: waiter} = state)
      when not is_nil(waiter) do
    GenServer.reply(waiter, {:ok, event})
    {:noreply, %{state | waiter: nil}}
  end

  def handle_cast({:enqueue, event}, %__MODULE__{} = state)
      when state.queue_size < state.queue_limit do
    {:noreply, %{state | queue: :queue.in(event, state.queue), queue_size: state.queue_size + 1}}
  end

  def handle_cast({:enqueue, _event}, %__MODULE__{} = state) do
    {:stop, :queue_overflow, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, owner, _reason}, %__MODULE__{} = state)
      when ref == state.owner_ref and owner == state.owner do
    reply_waiter(state.waiter, {:error, :closed})
    {:stop, :normal, %{state | waiter: nil}}
  end

  defp reply_waiter(nil, _reply), do: :ok
  defp reply_waiter(waiter, reply), do: GenServer.reply(waiter, reply)
end
