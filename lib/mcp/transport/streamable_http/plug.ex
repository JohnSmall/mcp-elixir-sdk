defmodule MCP.Transport.StreamableHTTP.Plug do
  @moduledoc """
  Plug endpoint for the MCP Streamable HTTP transport.

  Handles POST, GET, and DELETE HTTP methods at the MCP endpoint:

    * **POST** — receive JSON-RPC messages from clients, route to the
      appropriate MCP.Server session, and return the response
    * **GET** — open an SSE stream for server-initiated messages
    * **DELETE** — terminate a session

  ## Usage

  Mount this Plug in your HTTP server (e.g., with Bandit):

      # Create a Plug with a server factory function
      plug = MCP.Transport.StreamableHTTP.Plug.new(
        server_mod: MyApp.McpHandler,
        server_opts: []
      )

      # Start Bandit with the Plug
      {:ok, _} = Bandit.start_link(plug: plug, port: 8080)

  The public Plug option is `:server_mod`. Do **not** use `:handler` here —
  `:handler` is the internal `MCP.Server.start_link/1` key that this Plug
  constructs for you; passing it to the Plug has no effect.

  ## Client handshake (initialize → initialized → tools/call)

  Each session's `MCP.Server` starts in the `:waiting` state and only becomes
  `:ready` after it receives the `notifications/initialized` notification. A
  client MUST drive the full MCP handshake, in order:

    1. `POST` an `initialize` request — the response carries the
       `MCP-Session-Id` header identifying the new session.
    2. `POST` a `notifications/initialized` notification on that session
       (include the `MCP-Session-Id` header). The server returns `202 Accepted`
       and transitions to `:ready`.
    3. Only then `POST` `tools/call` (and other requests) on that session.

  Going straight from `initialize` to `tools/call` — skipping step 2 — is the
  single most common integration mistake: the server rejects the request with
  "Server not initialized", which can surface as a hang or a confusing error.
  `MCP.Client.connect/1` performs this handshake for you; if you drive the
  transport with a raw HTTP client, you must send `notifications/initialized`
  yourself.

  ## Options

    * `:server_mod` (required) — the `MCP.Server.Handler` module. This is the
      **public** Plug option (not `:handler`, which is internal to `MCP.Server`).
    * `:server_opts` — options to pass to `MCP.Server.start_link/1`
      (only `:server_info`, `:capabilities`, and `:instructions` are forwarded)
    * `:handler_opts` — options passed to the handler's `c:MCP.Server.Handler.init/1`
      for each session. Either a static keyword list, or a factory function
      `(Plug.Conn.t() -> keyword())` evaluated once per session at `initialize`
      (default: `[]`). See "Request-scoped handler options" below.
    * `:session_id_generator` — function that generates session IDs
      (default: `UUID.uuid4/0`). Pass `nil` for stateless mode.
    * `:enable_json_response` — if true, return `application/json` instead
      of SSE for simple request/response (default: false)
    * `:protocol_version` — expected protocol version (default: "2025-11-25")

  ## Request-scoped handler options

  `:handler_opts` threads options into the per-session handler's
  `c:MCP.Server.Handler.init/1`. This is the supported seam for carrying a
  request-established identity — validated by an upstream auth Plug and placed
  in `conn.assigns` — into handler state, **without forking this Plug**.

  Two forms:

    * **Static** — `handler_opts: [region: "eu"]`. Passed verbatim to `init/1`.
    * **Factory** — `handler_opts: fn conn -> [identity: conn.assigns.identity] end`.
      Evaluated **once per session, at the `initialize` POST**, against that
      request's `conn`. The returned keyword list is bound into handler state for
      the session's whole life; later requests on the same session reuse it and do
      **not** re-run the factory.

  Example:

      # Your auth Plug runs first and sets conn.assigns.identity
      plug = MCP.Transport.StreamableHTTP.Plug.new(
        server_mod: MyApp.McpHandler,
        handler_opts: fn conn -> [identity: conn.assigns.identity] end
      )

      defmodule MyApp.McpHandler do
        @behaviour MCP.Server.Handler
        @impl true
        def init(opts), do: {:ok, %{identity: Keyword.fetch!(opts, :identity)}}

        @impl true
        def handle_call_tool("whoami", _args, state),
          # acts as the bound principal — NEVER an identity taken from tool args
          do: {:ok, [%{"type" => "text", "text" => state.identity.subject}], state}
      end

  Security: identity must be established server-side by the authenticated Plug
  pipeline and bound at the `initialize` trust boundary — never supplied by the
  model via tool-call arguments, which are model-controlled and spoofable. The
  handler stays transport-agnostic: identity arrives through `init/1` opts, and
  the `conn` is never leaked into `handle_call_tool/3,4`.

  The factory form requires a `conn`, so it is supported only on the Plug's
  `initialize` request path. Conn-less start paths (a directly supervised
  `MCP.Server`, stdio, `MCP.Transport.StreamableHTTP.PreStarted`) support the
  **static** keyword form only.

  A factory that raises or returns a non-keyword produces a clean JSON-RPC
  "Internal error" (HTTP 500, code -32603) at `initialize` with no session
  started; the detail is logged server-side and never returned to the client.
  """

  @behaviour Plug

  require Logger

  alias MCP.Transport.SSE
  alias MCP.Transport.StreamableHTTP.Server, as: HTTPTransport

  @protocol_version "2025-11-25"

  @typedoc """
  Options threaded into the handler's `c:MCP.Server.Handler.init/1`.

  Either a static keyword list, or a factory `(Plug.Conn.t() -> keyword())`
  evaluated once per session at `initialize` against that request's conn.
  """
  @type handler_opts :: keyword() | (Plug.Conn.t() -> keyword())

  defstruct [
    :server_mod,
    :server_opts,
    :handler_opts,
    :session_id_generator,
    :enable_json_response,
    :protocol_version,
    :sessions
  ]

  @doc """
  Creates a new Plug configuration.

  Returns a tuple `{MCP.Transport.StreamableHTTP.Plug, opts}` suitable
  for passing to Bandit or other HTTP servers.
  """
  def new(opts) do
    {__MODULE__, opts}
  end

  # --- Plug callbacks ---

  @impl Plug
  def init(%__MODULE__{} = config), do: config

  def init(opts) do
    server_mod = Keyword.fetch!(opts, :server_mod)
    server_opts = Keyword.get(opts, :server_opts, [])
    handler_opts = validate_handler_opts!(Keyword.get(opts, :handler_opts, []))

    session_id_generator =
      case Keyword.get(opts, :session_id_generator, :default) do
        :default -> fn -> UUID.uuid4() end
        nil -> nil
        fun when is_function(fun, 0) -> fun
      end

    enable_json_response = Keyword.get(opts, :enable_json_response, false)
    protocol_version = Keyword.get(opts, :protocol_version, @protocol_version)

    # Create an ETS table to store session mappings
    sessions = :ets.new(:mcp_sessions, [:set, :public])

    %__MODULE__{
      server_mod: server_mod,
      server_opts: server_opts,
      handler_opts: handler_opts,
      session_id_generator: session_id_generator,
      enable_json_response: enable_json_response,
      protocol_version: protocol_version,
      sessions: sessions
    }
  end

  @impl Plug
  def call(conn, config) do
    if localhost_request?(conn) do
      route_method(conn, config)
    else
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(403, "Forbidden: non-localhost origin")
    end
  end

  defp route_method(conn, config) do
    case conn.method do
      "POST" -> handle_post(conn, config)
      "GET" -> handle_get(conn, config)
      "DELETE" -> handle_delete(conn, config)
      _ -> method_not_allowed(conn)
    end
  end

  # --- POST handler ---

  defp handle_post(conn, config) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn),
         {:ok, message} <- Jason.decode(body) do
      route_post(conn, config, message)
    else
      {:error, reason} ->
        send_json_error(conn, 400, -32_700, "Parse error", inspect(reason))
    end
  end

  defp route_post(conn, config, message) do
    cond do
      Map.get(message, "method") == "initialize" ->
        handle_initialize(conn, config, message)

      config.session_id_generator == nil ->
        handle_stateless_request(conn, config, message)

      true ->
        handle_session_request(conn, config, message)
    end
  end

  defp handle_initialize(conn, config, message) do
    session_id = generate_session_id(config)

    # Resolve handler_opts against this request's conn BEFORE any transport or
    # server is started, so a factory failure orphans nothing (no ETS row, no
    # transport, no half-started MCP.Server). Bound once, for the session's life.
    case resolve_handler_opts(config.handler_opts, conn) do
      {:ok, handler_opts} ->
        case create_session_and_deliver(config, session_id, message, handler_opts) do
          {:ok, response} ->
            conn
            |> maybe_set_session_header(session_id)
            |> send_response(config, response)

          :accepted ->
            Plug.Conn.send_resp(conn, 202, "")

          {:error, reason} ->
            send_json_error(conn, 500, -32_603, "Internal error", inspect(reason))
        end

      {:error, reason} ->
        # Server-side fault (server-supplied factory). Log full detail; return a
        # controlled, non-leaking message — a factory closure may hold secrets.
        Logger.error("MCP Plug: handler_opts factory failed: #{inspect(reason)}")
        send_json_error(conn, 500, -32_603, "Internal error", "handler_opts factory error")
    end
  end

  defp handle_session_request(conn, config, message) do
    validate_protocol_version(conn, config)

    with {:ok, session_id} <- require_session_id(conn),
         {:ok, transport_pid} <- lookup_session(config, session_id) do
      deliver_and_respond(conn, config, transport_pid, message)
    else
      {:error, :missing_session_id} ->
        send_json_error(conn, 400, -32_600, "Bad request", "Missing MCP-Session-Id header")

      :not_found ->
        send_json_error(conn, 404, -32_600, "Not found", "Session not found")
    end
  end

  defp handle_stateless_request(conn, config, message) do
    case :ets.first(config.sessions) do
      :"$end_of_table" ->
        send_json_error(conn, 400, -32_600, "Bad request", "Not initialized")

      session_id ->
        case lookup_session(config, session_id) do
          {:ok, transport_pid} -> deliver_and_respond(conn, config, transport_pid, message)
          :not_found -> send_json_error(conn, 400, -32_600, "Bad request", "Session expired")
        end
    end
  end

  defp deliver_and_respond(conn, config, transport_pid, message) do
    is_request = Map.has_key?(message, "id") && Map.has_key?(message, "method")

    if is_request && !config.enable_json_response && accepts_sse?(conn) do
      stream_request(conn, transport_pid, message)
    else
      sync_deliver(conn, config, transport_pid, message)
    end
  end

  defp sync_deliver(conn, config, transport_pid, message) do
    case HTTPTransport.deliver_message(transport_pid, message) do
      {:ok, response} -> send_response(conn, config, response)
      :accepted -> Plug.Conn.send_resp(conn, 202, "")
      {:error, reason} -> send_json_error(conn, 500, -32_603, "Internal error", inspect(reason))
    end
  end

  defp stream_request(conn, transport_pid, message) do
    request_id = Map.get(message, "id")

    # Register this Plug process as a stream endpoint
    HTTPTransport.register_stream(transport_pid, request_id, self())

    # Open chunked SSE response
    conn =
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_chunked(200)

    # Deliver message to transport (non-blocking)
    HTTPTransport.deliver_message_async(transport_pid, message)

    # Enter receive loop to stream events
    stream_loop(conn)
  end

  defp stream_loop(conn) do
    receive do
      {:sse_event, data} ->
        case Plug.Conn.chunk(conn, data) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      {:sse_done, data} ->
        case Plug.Conn.chunk(conn, data) do
          {:ok, conn} -> conn
          {:error, _} -> conn
        end

      {:sse_error, _reason} ->
        conn
    after
      120_000 ->
        conn
    end
  end

  defp accepts_sse?(conn) do
    accept = Plug.Conn.get_req_header(conn, "accept")
    Enum.any?(accept, &String.contains?(&1, "text/event-stream"))
  end

  # --- GET handler ---

  defp handle_get(conn, config) do
    with :ok <- require_sse_accept(conn),
         {:ok, session_id} <- require_session_id_if_stateful(conn, config),
         {:ok, _transport_pid} <- lookup_session(config, session_id) do
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_resp(200, "")
    else
      {:error, :not_acceptable} ->
        send_json_error(conn, 406, -32_000, "Not Acceptable", "Must accept text/event-stream")

      {:error, :missing_session_id} ->
        send_json_error(conn, 400, -32_600, "Bad request", "Missing MCP-Session-Id header")

      :not_found ->
        send_json_error(conn, 404, -32_600, "Not found", "Session not found")
    end
  end

  # --- DELETE handler ---

  defp handle_delete(conn, config) do
    with {:ok, session_id} <- require_session_id(conn),
         {:ok, transport_pid} <- lookup_session(config, session_id) do
      HTTPTransport.close(transport_pid)
      :ets.delete(config.sessions, session_id)
      Plug.Conn.send_resp(conn, 200, "")
    else
      {:error, :missing_session_id} ->
        send_json_error(conn, 400, -32_600, "Bad request", "Missing MCP-Session-Id header")

      :not_found ->
        Plug.Conn.send_resp(conn, 404, "")
    end
  end

  # --- Helpers ---

  defp generate_session_id(config) do
    if config.session_id_generator do
      config.session_id_generator.()
    else
      nil
    end
  end

  defp create_session_and_deliver(config, session_id, message, handler_opts) do
    case start_session(config, session_id, handler_opts) do
      {:ok, transport_pid} ->
        if session_id, do: :ets.insert(config.sessions, {session_id, transport_pid})
        HTTPTransport.deliver_message(transport_pid, message)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_session(config, session_id, handler_opts) do
    transport_opts = [owner: self(), session_id: session_id]

    case HTTPTransport.start_link(transport_opts) do
      {:ok, transport_pid} ->
        case start_mcp_server(config, transport_pid, handler_opts) do
          {:ok, _server_pid} ->
            {:ok, transport_pid}

          {:error, reason} ->
            HTTPTransport.close(transport_pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_mcp_server(config, transport_pid, handler_opts) do
    server_opts = [
      handler: {config.server_mod, handler_opts},
      transport: {MCP.Transport.StreamableHTTP.PreStarted, pid: transport_pid}
    ]

    server_opts =
      server_opts ++
        Keyword.take(config.server_opts, [:server_info, :capabilities, :instructions])

    MCP.Server.start_link(server_opts)
  end

  # Resolves `handler_opts` for a session. Static keyword lists (already
  # validated at init) pass through; a factory is evaluated once against the
  # `initialize` request's conn. Returns `{:error, reason}` — never raises — if
  # the factory raises or returns a non-keyword, so the caller can fail the
  # request cleanly without starting a session.
  defp resolve_handler_opts(fun, conn) when is_function(fun, 1) do
    case fun.(conn) do
      result when is_list(result) ->
        if Keyword.keyword?(result) do
          {:ok, result}
        else
          {:error, {:non_keyword_result, result}}
        end

      other ->
        {:error, {:non_keyword_result, other}}
    end
  rescue
    exception -> {:error, {:factory_raised, exception, __STACKTRACE__}}
  end

  defp resolve_handler_opts(list, _conn) when is_list(list), do: {:ok, list}

  # Fail-fast validation at Plug.init/1: the static form must be a keyword list,
  # or the option must be a 1-arity factory. A config error surfaces at mount
  # time, never per-request.
  defp validate_handler_opts!(fun) when is_function(fun, 1), do: fun

  defp validate_handler_opts!(list) when is_list(list) do
    if Keyword.keyword?(list) do
      list
    else
      raise ArgumentError,
            "handler_opts must be a keyword list or a 1-arity function " <>
              "(Plug.Conn.t() -> keyword()), got a non-keyword list: #{inspect(list)}"
    end
  end

  defp validate_handler_opts!(other) do
    raise ArgumentError,
          "handler_opts must be a keyword list or a 1-arity function " <>
            "(Plug.Conn.t() -> keyword()), got: #{inspect(other)}"
  end

  defp require_session_id(conn) do
    case Plug.Conn.get_req_header(conn, "mcp-session-id") do
      [session_id | _] -> {:ok, session_id}
      [] -> {:error, :missing_session_id}
    end
  end

  defp require_session_id_if_stateful(conn, config) do
    if config.session_id_generator == nil do
      {:ok, :ets.first(config.sessions)}
    else
      require_session_id(conn)
    end
  end

  defp require_sse_accept(conn) do
    accept = Plug.Conn.get_req_header(conn, "accept")
    accepts_sse = Enum.any?(accept, &String.contains?(&1, "text/event-stream"))

    if accepts_sse do
      :ok
    else
      {:error, :not_acceptable}
    end
  end

  defp validate_protocol_version(conn, config) do
    case Plug.Conn.get_req_header(conn, "mcp-protocol-version") do
      [] ->
        :ok

      [version | _] when version == config.protocol_version ->
        :ok

      [version | _] ->
        # MCP spec says servers MAY reject unsupported versions.
        # We log a warning but accept to maximize interoperability.
        Logger.debug(
          "MCP Plug: client sent protocol version #{version}, expected #{config.protocol_version}"
        )

        :ok
    end
  end

  defp lookup_session(config, session_id) do
    case :ets.lookup(config.sessions, session_id) do
      [{^session_id, pid}] ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          :ets.delete(config.sessions, session_id)
          :not_found
        end

      [] ->
        :not_found
    end
  end

  defp maybe_set_session_header(conn, nil), do: conn

  defp maybe_set_session_header(conn, session_id) do
    Plug.Conn.put_resp_header(conn, "mcp-session-id", session_id)
  end

  defp send_response(conn, config, response) do
    if config.enable_json_response do
      send_json_response(conn, response)
    else
      send_sse_response(conn, response)
    end
  end

  defp send_json_response(conn, response) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(response))
  end

  defp send_sse_response(conn, response) do
    sse_data = SSE.encode_message(response)

    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.send_resp(200, sse_data)
  end

  defp send_json_error(conn, http_status, code, message, data) do
    error = %{
      "jsonrpc" => "2.0",
      "error" => %{"code" => code, "message" => message, "data" => data}
    }

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(http_status, Jason.encode!(error))
  end

  defp method_not_allowed(conn) do
    conn
    |> Plug.Conn.put_resp_header("allow", "GET, POST, DELETE")
    |> Plug.Conn.send_resp(405, "")
  end

  @localhost_patterns ~w(localhost 127.0.0.1 [::1])

  defp localhost_request?(conn) do
    origin = Plug.Conn.get_req_header(conn, "origin")
    host = Plug.Conn.get_req_header(conn, "host")

    origin_ok = origin == [] || Enum.any?(origin, &localhost_value?/1)
    host_ok = host == [] || Enum.any?(host, &localhost_value?/1)

    origin_ok && host_ok
  end

  defp localhost_value?(value) do
    # Strip scheme prefix if present
    host_part =
      value
      |> String.replace(~r{^https?://}, "")
      |> String.split("/")
      |> hd()

    # Strip port suffix
    host_without_port = String.replace(host_part, ~r{:\d+$}, "")

    host_without_port in @localhost_patterns
  end
end
