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
  alias MCP.Server.{Config, Dispatch, ToolContext}

  defstruct [:transport_module, :transport_pid, :config, :identity]

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

  # --- GenServer callbacks ---

  @impl GenServer
  def init(opts) do
    {transport_spec, opts} = Keyword.pop!(opts, :transport)
    {handler_spec, opts} = Keyword.pop!(opts, :handler)
    {handler_module, handler_opts} = handler_spec

    identity = Keyword.get(opts, :identity, Keyword.get(handler_opts, :identity))

    # stdio/in-process subscription streams are MES-29, not this driver's
    # capability today. Declaring `streaming: false` is what makes that honest:
    # nothing list-changed is advertised over this transport, and dispatch
    # cannot hand this driver a streaming result (see `handle_stream_result/2`).
    config_opts =
      opts
      |> Keyword.put(:handler_opts, handler_opts)
      |> Keyword.put_new(:streaming, false)

    with {:ok, config} <- Config.build(handler_module, config_opts),
         {:ok, module, pid} <- start_transport(transport_spec) do
      {:ok,
       %__MODULE__{
         transport_module: module,
         transport_pid: pid,
         config: config,
         identity: identity
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:get_transport, _from, state), do: {:reply, state.transport_pid, state}

  def handle_call(:close, _from, state) do
    if state.transport_pid, do: state.transport_module.close(state.transport_pid)
    {:stop, :normal, :ok, state}
  catch
    _, _ -> {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_info({:mcp_message, message}, state) do
    case Protocol.decode_message(message) do
      {:ok, %Request{} = request} ->
        dispatch(request, request.id, state)

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
      {:reply, response, _handler_state} ->
        state.transport_module.send_message(state.transport_pid, response)
        {:noreply, state}

      {:noreply, _handler_state} ->
        {:noreply, state}

      # Unreachable for the same reason as `{:stream, ...}` below, and by the
      # same flag: a handler refusal of a listen can only arise after
      # `handle_listen/3` ran, which needs `streaming: true`. Answered like any
      # other reply — the refusal response IS the right thing to put on the
      # wire, and there is no stream on this driver to tear down.
      {:listen_refused, response, _handler_state} ->
        state.transport_module.send_message(state.transport_pid, response)
        {:noreply, state}

      {:stream, subscription, _handler_state} ->
        reject_stream(subscription, request_id, state)
    end
  end

  # Unreachable by construction: this driver declares `streaming: false`, and
  # `MCP.Server.Dispatch` returns `{:stream, ...}` only when that flag is true —
  # so a `subscriptions/listen` request here is answered -32601 long before it
  # gets this far. The clause exists anyway because the alternative to an
  # explicit rejection is a FunctionClauseError, which the compiler does not
  # catch and dialyzer does not flag: a `case` is exhaustive at runtime or not
  # at all. It is deliberately loud rather than silent — a stream that was
  # opened and then dropped without a word would look to the client exactly
  # like a working subscription that never fires.
  #
  # MES-29 replaces this with real stdio subscription support (shared-channel
  # registry, per-subscription-id ack ordering, notifications/cancelled
  # teardown). Until then this transport genuinely does not have the feature,
  # and says so.
  defp reject_stream(subscription, request_id, state) do
    Logger.error(
      "MCP.Server.Connection: received a streaming dispatch result for subscription " <>
        "#{inspect(subscription.id)}, but this driver declares streaming: false. " <>
        "Refusing the subscription. This indicates the dispatch config was built " <>
        "with :streaming true for an owner-based transport."
    )

    response = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "error" => %{
        "code" => Error.method_not_found("subscriptions/listen").code,
        "message" => "Method not found",
        "data" => "subscriptions/listen is not supported by this transport"
      }
    }

    state.transport_module.send_message(state.transport_pid, response)
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
