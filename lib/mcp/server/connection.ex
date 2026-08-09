defmodule MCP.Server.Connection do
  @moduledoc """
  Stateless per-request driver for **owner-based** transports (stdio,
  in-process/`BridgeTransport`) in the MCP 2026-07-28 core.

  This is the conn-less analogue of `MCP.Transport.StreamableHTTP.Plug`: a thin
  GenServer that owns a transport, receives decoded messages, builds one
  per-request `MCP.Server.ToolContext`, and drives `MCP.Server.Dispatch`. It is
  the stateless successor to the retired per-session `MCP.Server` GenServer —
  **no `initialize` handshake, no `:ready` gate, no session** (SEP-2575/2567).

  ## Identity (PO Comment B — stdio/in-process)

  There is no `conn`; the trust boundary is the pipe/process. A launch-static
  `:identity` option (part of `:handler_opts`, or given directly) is resolved
  **once at launch** and stamped on every per-request context. All other
  constraints (MC-1, MC-3, MC-4, MC-6) apply identically.

  ## Options

    * `:transport` — `{module, opts}` transport spec (started here, owner = self)
    * `:handler` — `{module, opts}` handler spec (module implements
      `MCP.Server.Handler`)
    * `:server_info` / `:instructions` / `:cache_defaults` — forwarded to
      `MCP.Server.Config.build/2`
    * `:identity` — launch-static caller identity for every request (optional)
  """

  use GenServer

  require Logger

  alias MCP.Protocol
  alias MCP.Protocol.Error
  alias MCP.Protocol.Messages.{Notification, Request, Response}
  alias MCP.Protocol.Messages.Subscriptions.{ListenParams, ListenResult}
  alias MCP.Protocol.Types.SubscriptionFilter
  alias MCP.Server.{Config, Dispatch, SubscriptionRegistry, SubscriptionWorker, ToolContext}

  @subscription_id_key "io.modelcontextprotocol/subscriptionId"

  defstruct [
    :transport_module,
    :transport_pid,
    :config,
    :identity,
    :subscription_supervisor,
    :subscription_registry,
    :subscription_endpoint,
    subscription_queue_limit: 256,
    subscriptions: %{}
  ]

  # --- Public API ---

  @doc "Starts the stateless connection and its transport."
  def start_link(opts) do
    {gen_opts, server_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, server_opts, gen_opts)
  end

  @doc "Returns the transport pid (testing convenience)."
  def transport(server), do: GenServer.call(server, :get_transport)

  @doc "Closes the connection and its transport."
  def close(server) do
    GenServer.call(server, :close)
  catch
    :exit, _ -> :ok
  end

  @doc "Gracefully closes one active subscription and emits its final result."
  @spec close_subscription(GenServer.server(), String.t() | integer()) ::
          :ok | {:error, :not_found}
  def close_subscription(server, request_id) do
    GenServer.call(server, {:close_subscription, request_id})
  end

  # --- GenServer callbacks ---

  @impl GenServer
  def init(opts) do
    {transport_spec, opts} = Keyword.pop!(opts, :transport)
    {handler_spec, opts} = Keyword.pop!(opts, :handler)
    {handler_module, handler_opts} = handler_spec

    identity = Keyword.get(opts, :identity, Keyword.get(handler_opts, :identity))

    subscriptions_enabled =
      not is_nil(Keyword.get(opts, :subscription_supervisor)) and
        not is_nil(Keyword.get(opts, :subscription_registry))

    config_opts =
      opts
      |> Keyword.put(:handler_opts, handler_opts)
      |> Keyword.put(:subscriptions_enabled, subscriptions_enabled)

    with :ok <- validate_subscription_options(opts),
         {:ok, config} <- Config.build(handler_module, config_opts),
         {:ok, module, pid} <- start_transport(transport_spec) do
      {:ok,
       %__MODULE__{
         transport_module: module,
         transport_pid: pid,
         config: config,
         identity: identity,
         subscription_supervisor: Keyword.get(opts, :subscription_supervisor),
         subscription_registry: Keyword.get(opts, :subscription_registry),
         subscription_endpoint: Keyword.get(opts, :subscription_endpoint, self()),
         subscription_queue_limit: Keyword.get(opts, :subscription_queue_limit, 256),
         subscriptions: %{}
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:get_transport, _from, state), do: {:reply, state.transport_pid, state}

  def handle_call(:close, _from, state) do
    state = close_all_subscriptions(state)
    if state.transport_pid, do: state.transport_module.close(state.transport_pid)
    {:stop, :normal, :ok, state}
  catch
    _, _ -> {:stop, :normal, :ok, state}
  end

  def handle_call({:close_subscription, request_id}, _from, state) do
    case graceful_close_subscription(state, request_id) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, :not_found} -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info({:mcp_message, message}, state) do
    case Protocol.decode_message(message) do
      {:ok, %Request{method: "subscriptions/listen"} = request} ->
        open_subscription(request, state)

      {:ok, %Request{} = request} ->
        dispatch(request, request.id, state)

      {:ok, %Notification{method: "notifications/cancelled"} = notification} ->
        cancel_subscription(notification, state)

      {:ok, %Notification{} = notification} ->
        dispatch(notification, nil, state)

      # Responses are only relevant to server→client requests, which the
      # stateless core does not make (server→client input rides MRTR). Ignore.
      {:ok, %Response{}} ->
        {:noreply, state}

      {:error, error} ->
        Logger.warning("MCP.Server.Connection: failed to decode message: #{inspect(error)}")
        {:noreply, state}
    end
  end

  def handle_info({:mcp_transport_closed, _reason}, state), do: {:stop, :normal, state}

  def handle_info({:mcp_subscription_ready, id, worker}, state) do
    deliver_subscription_message(id, worker, state)
  end

  def handle_info({:DOWN, ref, :process, worker, reason}, state) do
    case subscription_by_monitor(state.subscriptions, ref, worker) do
      nil ->
        {:noreply, state}

      {id, _subscription} when reason == :normal ->
        {:noreply, remove_subscription(state, id)}

      {id, _subscription} ->
        state = remove_subscription(state, id)

        send_protocol_error(
          state,
          id,
          Error.internal_error(%{"reason" => subscription_exit_reason(reason)})
        )
    end
  end

  def handle_info(msg, state) do
    Logger.debug("MCP.Server.Connection: unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Internals ---

  defp dispatch(message, request_id, state) do
    ctx = %ToolContext{
      request_id: request_id,
      meta: extract_meta(message),
      identity: state.identity,
      reply_sink: reply_sink(state)
    }

    case Dispatch.dispatch(message, ctx, state.config) do
      {:reply, response} ->
        state.transport_module.send_message(state.transport_pid, response)
        {:noreply, state}

      :noreply ->
        {:noreply, state}
    end
  end

  defp open_subscription(%Request{id: id, params: params}, state) do
    with :ok <- Dispatch.validate_request(params, state.config),
         :ok <- subscription_configuration(state),
         false <- Map.has_key?(state.subscriptions, id),
         {:ok, requested} <- parse_subscription_filter(params),
         {:ok, honored} <- authorize_subscription(id, params, requested, state),
         {:ok, worker} <- start_subscription_worker(id, requested, honored, state) do
      monitor_ref = Process.monitor(worker)
      subscription = %{worker: worker, monitor_ref: monitor_ref}

      {:noreply, %{state | subscriptions: Map.put(state.subscriptions, id, subscription)}}
    else
      true ->
        send_protocol_error(state, id, Error.invalid_request(:duplicate_request_id))

      {:error, %Error{} = error} ->
        send_protocol_error(state, id, error)

      {:error, reason} ->
        send_protocol_error(state, id, Error.internal_error(inspect(reason)))
    end
  end

  defp subscription_configuration(%{
         subscription_supervisor: supervisor,
         subscription_registry: registry,
         subscription_queue_limit: queue_limit
       }) do
    cond do
      is_nil(supervisor) or is_nil(registry) ->
        {:error, Error.method_not_found("subscriptions/listen")}

      not (is_integer(queue_limit) and queue_limit > 0) ->
        {:error, {:invalid_subscription_queue_limit, queue_limit}}

      true ->
        :ok
    end
  end

  defp validate_subscription_options(opts) do
    supervisor = Keyword.get(opts, :subscription_supervisor)
    registry = Keyword.get(opts, :subscription_registry)
    queue_limit = Keyword.get(opts, :subscription_queue_limit, 256)

    cond do
      not (is_integer(queue_limit) and queue_limit > 0) ->
        {:error, {:invalid_subscription_queue_limit, queue_limit}}

      is_nil(supervisor) and is_nil(registry) ->
        :ok

      is_nil(supervisor) or is_nil(registry) ->
        {:error, :incomplete_subscription_configuration}

      true ->
        with {:ok, _registry_name} <- SubscriptionRegistry.name(registry) do
          validate_subscription_supervisor(supervisor)
        end
    end
  end

  defp validate_subscription_supervisor(supervisor) do
    case GenServer.whereis(supervisor) do
      pid when is_pid(pid) -> :ok
      nil -> {:error, :invalid_subscription_supervisor}
    end
  end

  defp parse_subscription_filter(params) do
    {:ok, ListenParams.from_map(params).notifications}
  rescue
    error in [ArgumentError, KeyError] -> {:error, Error.invalid_params(Exception.message(error))}
  end

  defp authorize_subscription(id, params, requested, state) do
    module = state.config.handler_module

    if function_exported?(module, :handle_listen_subscriptions, 3) do
      context = %ToolContext{
        request_id: id,
        meta: Map.get(params || %{}, "_meta"),
        identity: state.identity,
        reply_sink: reply_sink(state)
      }

      case module.handle_listen_subscriptions(requested, context, state.config.handler_state) do
        {:ok, %SubscriptionFilter{} = honored} -> {:ok, honored}
        {:error, code, message} -> {:error, %Error{code: code, message: message}}
        other -> {:error, {:invalid_subscription_callback_result, other}}
      end
    else
      {:error, Error.method_not_found("subscriptions/listen")}
    end
  rescue
    exception -> {:error, {:subscription_callback_raised, exception, __STACKTRACE__}}
  end

  defp start_subscription_worker(id, requested, honored, state) do
    SubscriptionWorker.start(
      state.subscription_supervisor,
      state.subscription_registry,
      state.subscription_endpoint,
      id,
      self(),
      requested,
      honored,
      queue_limit: state.subscription_queue_limit,
      notify_owner: true
    )
  end

  defp cancel_subscription(%Notification{params: params} = notification, state) do
    case Map.get(params || %{}, "requestId") do
      id when is_binary(id) or is_integer(id) ->
        case graceful_close_subscription(state, id) do
          {:ok, state} -> {:noreply, state}
          {:error, :not_found} -> dispatch(notification, nil, state)
        end

      _invalid ->
        dispatch(notification, nil, state)
    end
  end

  defp deliver_subscription_message(id, worker, state) do
    case Map.get(state.subscriptions, id) do
      %{worker: ^worker} ->
        case SubscriptionWorker.next(worker, 0) do
          {:ok, message} ->
            send_subscription_message(state, id, message)

          {:error, :timeout} ->
            {:noreply, state}

          {:error, reason} ->
            state = remove_subscription(state, id)

            send_protocol_error(
              state,
              id,
              Error.internal_error(%{"reason" => subscription_delivery_error(reason)})
            )
        end

      _missing ->
        {:noreply, state}
    end
  end

  defp send_subscription_message(state, id, message) do
    case state.transport_module.send_message(state.transport_pid, message) do
      :ok -> {:noreply, state}
      {:error, _reason} -> stop_subscription_abruptly(state, id)
    end
  end

  defp graceful_close_subscription(state, id) do
    case Map.fetch(state.subscriptions, id) do
      {:ok, subscription} ->
        state = remove_subscription(state, id)
        GenServer.stop(subscription.worker, :normal)

        result = %ListenResult{meta: %{@subscription_id_key => id}}
        response = Response.success(id, ListenResult.to_map(result)) |> encode()
        _ = state.transport_module.send_message(state.transport_pid, response)
        {:ok, state}

      :error ->
        {:error, :not_found}
    end
  end

  defp stop_subscription_abruptly(state, id) do
    case Map.fetch(state.subscriptions, id) do
      {:ok, subscription} ->
        state = remove_subscription(state, id)
        GenServer.stop(subscription.worker, :normal)
        {:noreply, state}

      :error ->
        {:noreply, state}
    end
  end

  defp remove_subscription(state, id) do
    case Map.pop(state.subscriptions, id) do
      {nil, _subscriptions} ->
        state

      {subscription, subscriptions} ->
        Process.demonitor(subscription.monitor_ref, [:flush])
        %{state | subscriptions: subscriptions}
    end
  end

  defp subscription_by_monitor(subscriptions, ref, worker) do
    Enum.find(subscriptions, fn {_id, subscription} ->
      subscription.monitor_ref == ref and subscription.worker == worker
    end)
  end

  defp subscription_exit_reason(:queue_overflow), do: "subscription_queue_overflow"
  defp subscription_exit_reason(reason), do: inspect(reason)

  defp subscription_delivery_error(:closed), do: "subscription_closed_abruptly"
  defp subscription_delivery_error({:noproc, _call}), do: "subscription_closed_abruptly"
  defp subscription_delivery_error(reason), do: inspect(reason)

  defp close_all_subscriptions(state) do
    Enum.reduce(Map.keys(state.subscriptions), state, fn id, acc ->
      case graceful_close_subscription(acc, id) do
        {:ok, next_state} -> next_state
        {:error, :not_found} -> acc
      end
    end)
  end

  defp send_protocol_error(state, id, %Error{} = error) do
    response = Response.error(id, error) |> encode()
    _ = state.transport_module.send_message(state.transport_pid, response)
    {:noreply, state}
  end

  # Per-request notification emitter: writes straight to the transport (no
  # GenServer round-trip — dispatch runs in this process synchronously).
  defp reply_sink(state) do
    transport_module = state.transport_module
    transport_pid = state.transport_pid

    fn method, params ->
      transport_module.send_message(transport_pid, Notification.new(method, params) |> encode())
      :ok
    end
  end

  defp encode(struct), do: Jason.decode!(Jason.encode!(struct))

  defp extract_meta(%Request{params: params}) when is_map(params), do: Map.get(params, "_meta")
  defp extract_meta(_), do: nil

  defp start_transport({module, opts}) do
    case module.start_link([{:owner, self()} | opts]) do
      {:ok, pid} -> {:ok, module, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
