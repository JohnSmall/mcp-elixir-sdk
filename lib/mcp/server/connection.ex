defmodule MCP.Server.Connection do
  @moduledoc """
  Dual-era connection driver for **owner-based** transports (stdio and
  in-process/`BridgeTransport`).

  The first protocol request selects either the 2026 stateless dispatcher or
  the 2025 initialize/session state machine. Modes cannot be mixed. Both paths
  use one immutable handler configuration and per-request `ToolContext`.

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
  alias MCP.Protocol.Methods
  alias MCP.Protocol.Types.SubscriptionFilter

  alias MCP.Server.{
    Config,
    Dispatch,
    LegacyDispatch,
    SubscriptionRegistry,
    SubscriptionWorker,
    ToolContext
  }

  @subscription_id_key "io.modelcontextprotocol/subscriptionId"

  defstruct [
    :transport_module,
    :transport_pid,
    :config,
    :identity,
    :subscription_supervisor,
    :subscription_registry,
    :subscription_endpoint,
    :protocol_mode,
    :legacy_status,
    :legacy_client_info,
    :legacy_client_capabilities,
    :legacy_log_level,
    :next_id,
    :pending_client_requests,
    :request_timeout,
    :task_supervisor,
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

  @doc "Requests sampling from a negotiated MCP 2025-11-25 client."
  def request_sampling(server, params, timeout \\ 60_000),
    do: request_client(server, Methods.sampling_create_message(), params, timeout)

  @doc "Requests roots from a negotiated MCP 2025-11-25 client."
  def request_roots(server, timeout \\ 30_000),
    do: request_client(server, Methods.roots_list(), %{}, timeout)

  @doc "Requests elicitation from a negotiated MCP 2025-11-25 client."
  def request_elicitation(server, params, timeout \\ 60_000),
    do: request_client(server, Methods.elicitation_create(), params, timeout)

  defp request_client(server, method, params, timeout),
    do: GenServer.call(server, {:request_client, method, params, timeout}, :infinity)

  @doc "Notifies a legacy client that the tool list changed."
  def notify_tools_changed(server),
    do: GenServer.cast(server, {:legacy_notify, Methods.tools_list_changed(), nil})

  @doc "Notifies a legacy client that the resource list changed."
  def notify_resources_changed(server),
    do: GenServer.cast(server, {:legacy_notify, Methods.resources_list_changed(), nil})

  @doc "Notifies a legacy client that one resource changed."
  def notify_resource_updated(server, uri),
    do: GenServer.cast(server, {:legacy_notify, Methods.resources_updated(), %{"uri" => uri}})

  @doc "Notifies a legacy client that the prompt list changed."
  def notify_prompts_changed(server),
    do: GenServer.cast(server, {:legacy_notify, Methods.prompts_list_changed(), nil})

  @doc "Sends a legacy logging notification when allowed by the negotiated level."
  def log(server, level, data, logger_name \\ nil),
    do: GenServer.cast(server, {:legacy_log, level, data, logger_name})

  @doc "Sends a legacy progress notification."
  def send_progress(server, progress_token, progress, total \\ nil) do
    params = %{"progressToken" => progress_token, "progress" => progress}
    params = if is_nil(total), do: params, else: Map.put(params, "total", total)
    GenServer.cast(server, {:legacy_notify, Methods.progress(), params})
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

    with {:ok, task_supervisor} <- Task.Supervisor.start_link(),
         :ok <- validate_subscription_options(opts),
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
         protocol_mode: :undetermined,
         legacy_status: :waiting,
         legacy_log_level: "info",
         next_id: 1,
         pending_client_requests: %{},
         request_timeout: Keyword.get(opts, :request_timeout, 30_000),
         task_supervisor: task_supervisor,
         subscriptions: %{}
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:get_transport, _from, state), do: {:reply, state.transport_pid, state}

  def handle_call(:close, _from, state) do
    state = state |> fail_pending_client_requests(:closed) |> close_all_subscriptions()
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

  def handle_call(
        {:request_client, method, params, timeout},
        from,
        %{protocol_mode: :legacy, legacy_status: :ready} = state
      ) do
    timeout = timeout || state.request_timeout
    id = state.next_id
    message = Request.new(id, method, params) |> Jason.encode!() |> Jason.decode!()

    case state.transport_module.send_message(state.transport_pid, message) do
      :ok ->
        timeout_ref = Process.send_after(self(), {:client_request_timeout, id}, timeout)
        pending = Map.put(state.pending_client_requests, id, {from, timeout_ref})
        {:noreply, %{state | next_id: id + 1, pending_client_requests: pending}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:request_client, _method, _params, _timeout}, _from, state),
    do: {:reply, {:error, :legacy_client_not_ready}, state}

  @impl GenServer
  def handle_cast(
        {:legacy_notify, method, params},
        %{protocol_mode: :legacy, legacy_status: :ready} = state
      ) do
    send_legacy_notification(state, method, params)
    {:noreply, state}
  end

  def handle_cast({:legacy_notify, _method, _params}, state), do: {:noreply, state}

  def handle_cast(
        {:legacy_log, level, data, logger_name},
        %{protocol_mode: :legacy, legacy_status: :ready} = state
      ) do
    if log_level_allowed?(level, state.legacy_log_level) do
      params = %{"level" => level, "data" => data}
      params = if is_nil(logger_name), do: params, else: Map.put(params, "logger", logger_name)
      send_legacy_notification(state, Methods.logging_message(), params)
    end

    {:noreply, state}
  end

  def handle_cast({:legacy_log, _level, _data, _logger_name}, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({:mcp_message, message}, state),
    do: message |> Protocol.decode_message() |> handle_decoded_message(state)

  def handle_info({:mcp_transport_closed, reason}, state) do
    {:stop, :normal, fail_pending_client_requests(state, {:transport_closed, reason})}
  end

  def handle_info({:client_request_timeout, id}, state) do
    case Map.pop(state.pending_client_requests, id) do
      {{from, _timeout_ref}, pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_client_requests: pending}}

      {nil, _pending} ->
        {:noreply, state}
    end
  end

  def handle_info({:legacy_inputs_resolved, request, responses, request_state}, state) do
    params =
      (request.params || %{})
      |> Map.put("inputResponses", responses)
      |> maybe_put_request_state(request_state)

    dispatch_legacy(%{request | params: params}, state)
  end

  def handle_info({:legacy_inputs_failed, id, reason}, state),
    do: send_protocol_error(state, id, Error.internal_error(%{"reason" => inspect(reason)}))

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

  defp handle_decoded_message({:ok, %Request{method: "initialize"} = request}, state),
    do: initialize_legacy(request, state)

  defp handle_decoded_message(
         {:ok, %Request{method: "subscriptions/listen"} = request},
         %{protocol_mode: :legacy} = state
       ),
       do: dispatch_legacy(request, state)

  defp handle_decoded_message(
         {:ok, %Request{method: "subscriptions/listen"} = request},
         state
       ),
       do: open_subscription(request, %{state | protocol_mode: :stateless})

  defp handle_decoded_message({:ok, %Request{} = request}, state),
    do: dispatch_versioned(request, state)

  defp handle_decoded_message(
         {:ok, %Notification{method: "notifications/initialized"}},
         state
       ),
       do: initialize_legacy_notification(state)

  defp handle_decoded_message(
         {:ok, %Notification{method: "notifications/cancelled"} = notification},
         state
       ),
       do: cancel_subscription(notification, state)

  defp handle_decoded_message({:ok, %Notification{} = notification}, state),
    do: dispatch(notification, nil, %{state | protocol_mode: :stateless})

  defp handle_decoded_message({:ok, %Response{} = response}, state),
    do: handle_client_response(response, state)

  defp handle_decoded_message({:error, error}, state) do
    Logger.warning("MCP.Server.Connection: failed to decode message: #{inspect(error)}")
    {:noreply, state}
  end

  defp handle_client_response(%Response{id: id} = response, state) do
    case Map.pop(state.pending_client_requests, id) do
      {{from, timeout_ref}, pending} ->
        Process.cancel_timer(timeout_ref)
        reply = if response.error, do: {:error, response.error}, else: {:ok, response.result}
        GenServer.reply(from, reply)
        {:noreply, %{state | pending_client_requests: pending}}

      {nil, _pending} ->
        Logger.warning("MCP.Server.Connection: response for unknown request id=#{inspect(id)}")
        {:noreply, state}
    end
  end

  defp initialize_legacy(%Request{id: id} = request, %{protocol_mode: mode} = state)
       when mode in [:undetermined, :legacy] do
    if state.legacy_status == :waiting do
      case LegacyDispatch.initialize(request, state.config) do
        {:ok, response, initialize} ->
          state.transport_module.send_message(state.transport_pid, response)

          {:noreply,
           %{
             state
             | protocol_mode: :legacy,
               legacy_client_info: initialize.client_info,
               legacy_client_capabilities: initialize.capabilities
           }}

        {:error, response} ->
          state.transport_module.send_message(state.transport_pid, response)
          {:noreply, state}
      end
    else
      send_protocol_error(state, id, Error.invalid_request("Already initialized"))
    end
  end

  defp initialize_legacy(%Request{id: id}, state),
    do: send_protocol_error(state, id, Error.invalid_request("Protocol mode already selected"))

  defp initialize_legacy_notification(%{protocol_mode: :legacy, legacy_status: :waiting} = state),
    do: {:noreply, %{state | legacy_status: :ready}}

  defp initialize_legacy_notification(%{protocol_mode: :legacy} = state), do: {:noreply, state}

  defp initialize_legacy_notification(state),
    do: dispatch(%Notification{method: "notifications/initialized", params: nil}, nil, state)

  defp dispatch_versioned(%Request{id: id} = request, %{protocol_mode: :legacy} = state) do
    if stateless_request?(request) do
      send_protocol_error(state, id, Error.invalid_request("Protocol mode already selected"))
    else
      dispatch_legacy(request, state)
    end
  end

  defp dispatch_versioned(request, state),
    do: dispatch(request, request.id, %{state | protocol_mode: :stateless})

  defp dispatch_legacy(%Request{id: id}, %{legacy_status: status} = state)
       when status != :ready,
       do: send_protocol_error(state, id, Error.invalid_request("Server not initialized"))

  defp dispatch_legacy(%Request{} = request, state) do
    context = %ToolContext{
      request_id: request.id,
      meta: Map.get(request.params || %{}, "_meta"),
      identity: state.identity,
      reply_sink: reply_sink(state, request.id)
    }

    case LegacyDispatch.dispatch(request, context, state.config) do
      {:reply, response} ->
        state.transport_module.send_message(state.transport_pid, response)
        {:noreply, update_legacy_request_state(state, request, response)}

      {:input_required, requests, request_state} ->
        case resolve_legacy_inputs(state.task_supervisor, request, requests, request_state) do
          {:ok, _pid} ->
            {:noreply, state}

          {:error, reason} ->
            send_protocol_error(
              state,
              request.id,
              Error.internal_error(%{
                "message" => "Unable to start legacy input request",
                "reason" => inspect(reason)
              })
            )
        end
    end
  end

  defp resolve_legacy_inputs(task_supervisor, request, requests, request_state) do
    server = self()

    Task.Supervisor.start_child(task_supervisor, fn ->
      server
      |> collect_legacy_inputs(requests)
      |> report_legacy_inputs(server, request, request_state)
    end)
  end

  defp collect_legacy_inputs(server, requests) do
    Enum.reduce_while(requests, {:ok, %{}}, fn {key, input_request}, {:ok, responses} ->
      method = Map.get(input_request, "method")
      params = Map.get(input_request, "params", %{})

      case request_client(server, method, params, 60_000) do
        {:ok, response} -> {:cont, {:ok, Map.put(responses, key, response)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp report_legacy_inputs({:ok, responses}, server, request, request_state),
    do: send(server, {:legacy_inputs_resolved, request, responses, request_state})

  defp report_legacy_inputs({:error, reason}, server, request, _request_state),
    do: send(server, {:legacy_inputs_failed, request.id, reason})

  defp maybe_put_request_state(params, nil), do: Map.delete(params, "requestState")

  defp maybe_put_request_state(params, request_state),
    do: Map.put(params, "requestState", request_state)

  defp stateless_request?(%Request{params: params}) do
    get_in(params || %{}, ["_meta", "io.modelcontextprotocol/protocolVersion"]) ==
      Dispatch.protocol_version()
  end

  defp fail_pending_client_requests(state, reason) do
    Enum.each(state.pending_client_requests, fn {_id, {from, timeout_ref}} ->
      Process.cancel_timer(timeout_ref)
      GenServer.reply(from, {:error, reason})
    end)

    %{state | pending_client_requests: %{}}
  end

  defp update_legacy_request_state(
         state,
         %Request{method: "logging/setLevel", params: params},
         %{"result" => _result}
       ),
       do: %{state | legacy_log_level: Map.get(params || %{}, "level", "info")}

  defp update_legacy_request_state(state, _request, _response), do: state

  defp send_legacy_notification(state, method, params) do
    message = Notification.new(method, params) |> Jason.encode!() |> Jason.decode!()
    state.transport_module.send_message(state.transport_pid, message)
  end

  defp log_level_allowed?(level, minimum) do
    levels = ~w(debug info notice warning error critical alert emergency)
    level_index = Enum.find_index(levels, &(&1 == level))
    minimum_index = Enum.find_index(levels, &(&1 == minimum))
    is_integer(level_index) and is_integer(minimum_index) and level_index >= minimum_index
  end

  defp dispatch(message, request_id, state) do
    ctx = %ToolContext{
      request_id: request_id,
      meta: extract_meta(message),
      identity: state.identity,
      reply_sink: reply_sink(state, request_id)
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
        reply_sink: reply_sink(state, id)
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
  defp reply_sink(state, request_id) do
    transport_module = state.transport_module
    transport_pid = state.transport_pid

    fn method, params ->
      message = Notification.new(method, params) |> encode()

      if state.protocol_mode == :legacy and
           function_exported?(transport_module, :send_request_notification, 3) do
        transport_module.send_request_notification(transport_pid, request_id, message)
      else
        transport_module.send_message(transport_pid, message)
      end

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
