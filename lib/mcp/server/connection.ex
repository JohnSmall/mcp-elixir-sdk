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
    config_opts = Keyword.put(opts, :handler_opts, handler_opts)

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
    end
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
