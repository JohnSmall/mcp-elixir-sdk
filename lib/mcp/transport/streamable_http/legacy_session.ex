defmodule MCP.Transport.StreamableHTTP.LegacySession do
  @moduledoc false

  use GenServer

  @behaviour MCP.Transport

  alias MCP.Server.Connection

  defstruct owner: nil,
            owner_ref: nil,
            pending_posts: %{},
            events: :queue.new(),
            event_queue_limit: 256,
            event_waiter: nil,
            closed?: false

  @type session :: %{required(:server) => pid(), required(:transport) => pid()}

  @spec start(module(), keyword(), keyword()) :: {:ok, session()} | {:error, term()}
  def start(handler_module, handler_opts, server_opts) do
    case GenServer.start(__MODULE__, []) do
      {:ok, transport} ->
        case GenServer.start(
               Connection,
               [
                 transport: {__MODULE__, [pid: transport]},
                 handler: {handler_module, handler_opts}
               ] ++ server_opts
             ) do
          {:ok, server} ->
            {:ok, %{server: server, transport: transport}}

          {:error, reason} ->
            close(transport)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec deliver(session(), map(), timeout()) ::
          {:ok, map(), [map()]} | :accepted | {:error, term()}
  def deliver(session, %{"id" => _id, "method" => _method} = message, timeout) do
    GenServer.call(session.transport, {:request, message}, timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
    :exit, reason -> {:error, {:session_closed, reason}}
  end

  def deliver(session, message, _timeout) when is_map(message) do
    with {:ok, owner} <- GenServer.call(session.transport, {:deliver, message}),
         _state <- :sys.get_state(owner) do
      :accepted
    else
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, reason -> {:error, {:session_closed, reason}}
  end

  @spec next_event(session(), timeout()) :: {:ok, map()} | {:error, term()}
  def next_event(session, timeout) do
    GenServer.call(session.transport, :next_event, timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
    :exit, reason -> {:error, {:session_closed, reason}}
  end

  @impl MCP.Transport
  def start_link(opts) do
    transport = Keyword.fetch!(opts, :pid)
    owner = Keyword.fetch!(opts, :owner)

    case GenServer.call(transport, {:set_owner, owner}) do
      :ok -> {:ok, transport}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl MCP.Transport
  def send_message(transport, message), do: GenServer.call(transport, {:send_message, message})

  @doc false
  def send_request_notification(transport, request_id, message),
    do: GenServer.call(transport, {:request_notification, request_id, message})

  @spec close(session() | pid()) :: :ok
  def close(%{server: server}), do: Connection.close(server)

  @impl MCP.Transport
  def close(transport) when is_pid(transport) do
    GenServer.call(transport, :close)
  catch
    :exit, _reason -> :ok
  end

  @impl GenServer
  def init(_opts), do: {:ok, %__MODULE__{}}

  @impl GenServer
  def handle_call({:set_owner, owner}, _from, %{owner: nil} = state) do
    {:reply, :ok, %{state | owner: owner, owner_ref: Process.monitor(owner)}}
  end

  def handle_call({:set_owner, _owner}, _from, state),
    do: {:reply, {:error, :owner_already_set}, state}

  def handle_call({:request, _message}, _from, %{closed?: true} = state),
    do: {:reply, {:error, :closed}, state}

  def handle_call({:request, %{"id" => id} = message}, from, state) do
    if Map.has_key?(state.pending_posts, id) do
      {:reply, {:error, :duplicate_request_id}, state}
    else
      send(state.owner, {:mcp_message, message})
      pending = %{from: from, notifications: []}
      {:noreply, %{state | pending_posts: Map.put(state.pending_posts, id, pending)}}
    end
  end

  def handle_call({:deliver, _message}, _from, %{closed?: true} = state),
    do: {:reply, {:error, :closed}, state}

  def handle_call({:deliver, message}, _from, state) do
    send(state.owner, {:mcp_message, message})
    {:reply, {:ok, state.owner}, state}
  end

  def handle_call({:send_message, %{"id" => id} = response}, _from, state)
      when is_map_key(response, "result") or is_map_key(response, "error") do
    case Map.pop(state.pending_posts, id) do
      {nil, _pending} ->
        enqueue_event(response, state)

      {%{from: waiter, notifications: notifications}, pending} ->
        GenServer.reply(waiter, {:ok, response, Enum.reverse(notifications)})
        {:reply, :ok, %{state | pending_posts: pending}}
    end
  end

  def handle_call({:send_message, message}, _from, state), do: enqueue_event(message, state)

  def handle_call({:request_notification, request_id, message}, _from, state) do
    case Map.fetch(state.pending_posts, request_id) do
      {:ok, pending} ->
        pending = %{pending | notifications: [message | pending.notifications]}
        {:reply, :ok, %{state | pending_posts: Map.put(state.pending_posts, request_id, pending)}}

      :error ->
        enqueue_event(message, state)
    end
  end

  def handle_call(:next_event, _from, %{closed?: true} = state),
    do: {:reply, {:error, :closed}, state}

  def handle_call(:next_event, from, state) do
    case :queue.out(state.events) do
      {{:value, event}, events} -> {:reply, {:ok, event}, %{state | events: events}}
      {:empty, _events} -> put_event_waiter(from, state)
    end
  end

  def handle_call(:close, _from, state) do
    state = fail_waiters(state, :closed)
    {:stop, :normal, :ok, %{state | closed?: true}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, owner, _reason}, %{owner: owner, owner_ref: ref} = state) do
    state = fail_waiters(state, :closed)
    {:stop, :normal, %{state | closed?: true}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{event_waiter: {_, ref}} = state),
    do: {:noreply, %{state | event_waiter: nil}}

  def handle_info(_message, state), do: {:noreply, state}

  defp enqueue_event(message, %{event_waiter: {waiter, monitor_ref}} = state) do
    Process.demonitor(monitor_ref, [:flush])
    GenServer.reply(waiter, {:ok, message})
    {:reply, :ok, %{state | event_waiter: nil}}
  end

  defp enqueue_event(message, state) do
    if :queue.len(state.events) < state.event_queue_limit do
      {:reply, :ok, %{state | events: :queue.in(message, state.events)}}
    else
      {:reply, {:error, :queue_overflow}, state}
    end
  end

  defp put_event_waiter(from, %{event_waiter: nil} = state) do
    monitor_ref = Process.monitor(elem(from, 0))
    {:noreply, %{state | event_waiter: {from, monitor_ref}}}
  end

  defp put_event_waiter(_from, state), do: {:reply, {:error, :event_waiter_exists}, state}

  defp fail_waiters(state, reason) do
    Enum.each(state.pending_posts, fn {_id, pending} ->
      GenServer.reply(pending.from, {:error, reason})
    end)

    case state.event_waiter do
      {waiter, monitor_ref} ->
        Process.demonitor(monitor_ref, [:flush])
        GenServer.reply(waiter, {:error, reason})

      nil ->
        :ok
    end

    %{state | pending_posts: %{}, event_waiter: nil}
  end
end
