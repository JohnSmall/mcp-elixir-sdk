defmodule MCP.Server.SubscriptionWorker do
  @moduledoc false

  use GenServer

  alias MCP.Protocol.Messages.Subscriptions.AcknowledgedParams
  alias MCP.Protocol.Methods
  alias MCP.Protocol.Types.SubscriptionFilter
  alias MCP.Server.SubscriptionRegistry

  @default_queue_limit 256
  @subscription_id_key "io.modelcontextprotocol/subscriptionId"

  defstruct [
    :id,
    :registry,
    :registry_key,
    :endpoint,
    :owner,
    :owner_ref,
    :requested,
    :honored,
    :acknowledgment,
    :waiter,
    queue: :queue.new(),
    queue_size: 0,
    queue_limit: @default_queue_limit,
    registered?: false
  ]

  @type request_id :: String.t() | number()

  @spec start(
          GenServer.server(),
          atom() | pid(),
          term(),
          request_id(),
          pid(),
          SubscriptionFilter.t(),
          SubscriptionFilter.t(),
          keyword()
        ) :: DynamicSupervisor.on_start_child() | {:error, term()}
  def start(supervisor, registry, endpoint, id, owner, requested, honored, opts \\ []) do
    queue_limit = Keyword.get(opts, :queue_limit, @default_queue_limit)

    with {:ok, registry_name} <- SubscriptionRegistry.name(registry) do
      cond do
        not (is_integer(queue_limit) and queue_limit > 0) ->
          {:error, {:invalid_queue_limit, queue_limit}}

        not subset?(honored, requested) ->
          {:error, :honored_filter_not_subset}

        true ->
          args = {registry_name, endpoint, id, owner, requested, honored, queue_limit}
          DynamicSupervisor.start_child(supervisor, {__MODULE__, args})
      end
    end
  end

  @spec publish(pid(), String.t(), map() | nil) :: :ok
  def publish(worker, method, params) do
    GenServer.cast(worker, {:publish, method, params})
  end

  @spec next(pid(), timeout()) :: {:ok, map()} | {:error, term()}
  def next(worker, timeout \\ 5_000) do
    GenServer.call(worker, :next, timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
    :exit, {:noproc, _call} -> {:error, :closed}
    :exit, reason -> {:error, reason}
  end

  @spec start_link(tuple()) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
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
  def init({registry, endpoint, id, owner, requested, honored, queue_limit}) do
    registry_key = {:mcp_subscriptions, endpoint}

    state = %__MODULE__{
      id: id,
      registry: registry,
      registry_key: registry_key,
      endpoint: endpoint,
      owner: owner,
      owner_ref: Process.monitor(owner),
      requested: requested,
      honored: honored,
      acknowledgment: acknowledgment(id, honored),
      queue_limit: queue_limit
    }

    {:ok, state, {:continue, :register}}
  end

  @impl true
  def handle_continue(:register, %__MODULE__{} = state) do
    {:ok, _value} =
      Registry.register(state.registry, state.registry_key, %{honored: state.honored})

    {:noreply, %{state | registered?: true}}
  end

  @impl true
  def handle_call(:next, _from, %__MODULE__{acknowledgment: acknowledgment} = state)
      when not is_nil(acknowledgment) do
    {:reply, {:ok, acknowledgment}, %{state | acknowledgment: nil}}
  end

  def handle_call(:next, from, %__MODULE__{queue_size: 0, waiter: nil} = state) do
    {:noreply, %{state | waiter: from}}
  end

  def handle_call(:next, _from, %__MODULE__{queue_size: 0} = state) do
    {:reply, {:error, :concurrent_next}, state}
  end

  def handle_call(:next, _from, %__MODULE__{} = state) do
    {{:value, notification}, queue} = :queue.out(state.queue)
    {:reply, {:ok, notification}, %{state | queue: queue, queue_size: state.queue_size - 1}}
  end

  @impl true
  def handle_cast({:publish, method, params}, %__MODULE__{waiter: waiter} = state)
      when not is_nil(waiter) do
    GenServer.reply(waiter, {:ok, notification(state.id, method, params)})
    {:noreply, %{state | waiter: nil}}
  end

  def handle_cast({:publish, method, params}, %__MODULE__{} = state)
      when state.queue_size < state.queue_limit do
    notification = notification(state.id, method, params)

    {:noreply,
     %{
       state
       | queue: :queue.in(notification, state.queue),
         queue_size: state.queue_size + 1
     }}
  end

  def handle_cast({:publish, _method, _params}, %__MODULE__{} = state) do
    {:stop, :queue_overflow, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, owner, _reason}, %__MODULE__{} = state)
      when ref == state.owner_ref and owner == state.owner do
    reply_waiter(state.waiter, {:error, :closed})
    {:stop, :normal, %{state | waiter: nil}}
  end

  @impl true
  def terminate(_reason, %__MODULE__{registered?: true} = state) do
    Registry.unregister(state.registry, state.registry_key)
    :ok
  end

  def terminate(_reason, %__MODULE__{}), do: :ok

  defp acknowledgment(id, honored) do
    params = %AcknowledgedParams{
      notifications: honored,
      meta: %{@subscription_id_key => id}
    }

    %{
      "jsonrpc" => "2.0",
      "method" => Methods.subscriptions_acknowledged(),
      "params" => AcknowledgedParams.to_map(params)
    }
  end

  defp notification(id, method, params) do
    params = params || %{}
    meta = Map.get(params, "_meta", %{})
    params = Map.put(params, "_meta", Map.put(meta, @subscription_id_key, id))

    %{"jsonrpc" => "2.0", "method" => method, "params" => params}
  end

  defp subset?(%SubscriptionFilter{} = honored, %SubscriptionFilter{} = requested) do
    boolean_subset?(honored.tools_list_changed, requested.tools_list_changed) and
      boolean_subset?(honored.prompts_list_changed, requested.prompts_list_changed) and
      boolean_subset?(honored.resources_list_changed, requested.resources_list_changed) and
      Enum.all?(honored.resource_subscriptions, &(&1 in requested.resource_subscriptions))
  end

  defp boolean_subset?(false, _requested), do: true
  defp boolean_subset?(true, true), do: true
  defp boolean_subset?(true, false), do: false

  defp reply_waiter(nil, _reply), do: :ok
  defp reply_waiter(waiter, reply), do: GenServer.reply(waiter, reply)
end
