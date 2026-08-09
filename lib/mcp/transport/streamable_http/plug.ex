defmodule MCP.Transport.StreamableHTTP.Plug do
  @moduledoc """
  Dual-era Plug endpoint for the MCP Streamable HTTP transport.

  The preferred 2026 path is a thin **per-request driver** for
  `MCP.Server.Dispatch`: there is no
  `initialize` handshake, no `Mcp-Session-Id`, and no session affinity — any
  request is serviceable by any instance behind a round-robin balancer
  (SEP-2575 / SEP-2567). The dispatch `config` is built once at `init/1`; every
  request builds its own `MCP.Server.ToolContext` and calls `Dispatch`.

  The compatibility 2025 path creates an isolated OTP session at initialize,
  requires `Mcp-Session-Id` afterward, serves server messages via GET SSE, and
  closes on DELETE. Both paths share the endpoint without sharing lifecycle
  state.

  ## Usage

      plug = MCP.Transport.StreamableHTTP.Plug.new(server_mod: MyApp.Handler)
      {:ok, _} = Bandit.start_link(plug: plug, port: 8080)

  ## Per-request pipeline (strict order)

    1. **Enforcement** — localhost/Origin (and any host auth) runs first, on
       every request, before the identity factory (MC-5 / AC7). A rejected
       request never runs the factory.
    2. **Decode + request metadata** — parse the JSON-RPC body and validate the
       required 2026-07-28 `_meta` fields.
    3. **Standard routing headers** — validate
       `Mcp-Method` / `Mcp-Name` against it (SEP-2243) — mismatch → `-32020`.
    4. **Identity resolution** — the `:handler_opts` factory is evaluated
       against *this request's* `conn` (or the static keyword's `:identity`);
       the result populates `ToolContext.identity`, never from `params`
       (MC-2/Comment B, MC-3, MC-4). Factory failure → controlled `-32603`,
       no dispatch (MC-6).
    5. **Custom routing headers** — resolve the selected tool schema using the
       authenticated identity and validate recognized `Mcp-Param-*` values.
    6. **Dispatch** — `Dispatch.dispatch(message, ctx, config)`.

  ## Options

    * `:server_mod` (required) — the `MCP.Server.Handler` module.
    * `:server_opts` — `:server_info`, `:instructions`, `:cache_defaults`
      forwarded to `MCP.Server.Config`. If you raise `:cache_defaults` above the
      no-store default on identity-dependent results, set `cacheScope: "private"`
      — see the security warning on `MCP.Server.Config.build/2`.
    * `:handler_opts` — static `keyword()` **or** a `(Plug.Conn.t() ->
      keyword())` factory. The factory is evaluated **per request** for 2026,
      and once at session initialization for 2025. Its `:identity` populates
      the request context for that request or negotiated session.
      The static form's `:identity` is used as a constant. (The non-identity
      base is passed once to `Handler.init/1` at mount.)

      > #### Factory last-mile responsibility {: .warning}
      >
      > The factory receives the **whole** `conn`, which carries **both**
      > authenticated material (assigns your upstream auth Plug set) **and**
      > model-reachable material (raw request headers, the request body). The
      > invariant's last mile is yours: read the **authenticated** part only.
      >
      >     # RIGHT — an assign established server-side by your auth pipeline:
      >     handler_opts: fn conn -> [identity: conn.assigns[:current_user]] end
      >
      >     # WRONG — a raw header is caller-supplied and unauthenticated;
      >     # anyone (including the model) can set it, defeating the invariant:
      >     handler_opts: fn conn -> [identity: get_req_header(conn, "x-user")] end
      >
      > This is the one identity-leak path the SDK cannot close by construction:
      > it drops model-controlled `params`/`arguments`/`_meta` and never reads a
      > header into identity itself, but it cannot tell which part of the `conn`
      > **your** factory chooses to trust. Read `conn.assigns`, not raw input.
    * `:enable_json_response` — return `application/json` instead of SSE for
      request/response (default: false).
    * `:max_body_length` — maximum accepted POST body size in bytes (default:
      `8_000_000`). Larger or multi-chunk bodies are rejected with HTTP 413
      before JSON decoding.
    * `:protocol_version` — advertised version (default: the stateless core's).
    * `:tool_schemas` — either `%{tool_name => input_schema}` or a
      `(tool_name, identity -> input_schema | nil)` resolver. Static schemas
      are compiled and validated at mount. The resolver runs after identity
      resolution, allowing identity-dependent catalogs without invoking
      `handle_list_tools/3` as a routing side effect. It must return the same
      selected schema that the handler advertises from `tools/list`.

  ## Security

  Identity must be established server-side by the authenticated Plug pipeline
  (e.g. an upstream auth Plug setting `conn.assigns`) and resolved by the
  factory — never supplied by the model via tool-call arguments. The handler
  stays transport-agnostic: it reads `ctx.identity`; the `conn` is never leaked
  into a handler callback. A factory that raises or returns a non-keyword
  yields a clean `-32603` (HTTP 500) with no handler invoked; the detail is
  logged server-side and never returned to the client.
  """

  @behaviour Plug

  require Logger

  alias MCP.Protocol
  alias MCP.Protocol.Error
  alias MCP.Protocol.Messages.{Notification, Request, Response}
  alias MCP.Protocol.Messages.Subscriptions.ListenParams
  alias MCP.Protocol.Meta
  alias MCP.Protocol.ToolRouting
  alias MCP.Protocol.Types.SubscriptionFilter
  alias MCP.Server.{Config, Dispatch, LegacyDispatch, SubscriptionWorker, ToolContext}
  alias MCP.Transport.SSE
  alias MCP.Transport.StreamableHTTP.LegacySession

  @typedoc """
  Options threaded into the handler's identity resolution: a static keyword
  list, or a factory `(Plug.Conn.t() -> keyword())` evaluated per request.
  """
  @type handler_opts :: keyword() | (Plug.Conn.t() -> keyword())

  defstruct [
    :server_mod,
    :server_opts,
    :handler_opts,
    :enable_json_response,
    :protocol_version,
    :tool_schemas,
    :subscription_supervisor,
    :subscription_registry,
    :subscription_endpoint,
    :subscription_queue_limit,
    :subscription_keepalive_interval,
    :max_body_length,
    :legacy_sessions,
    :legacy_sse_timeout,
    :config
  ]

  # Per-request notification collector key (process-local). Declared here, above
  # its first use in `dispatch/5`, so the security clears in `dispatch/5`
  # reference the real key (a module attribute used before definition resolves
  # to nil — Ruling 7 fix must not silently no-op).
  @notifications_key :mcp_plug_notifications

  @doc """
  Creates a Plug configuration tuple suitable for Bandit.
  """
  def new(opts), do: {__MODULE__, opts}

  # --- Plug callbacks ---

  @impl Plug
  def init(%__MODULE__{} = config), do: config

  def init(opts) do
    server_mod = Keyword.fetch!(opts, :server_mod)
    server_opts = Keyword.get(opts, :server_opts, [])
    handler_opts = validate_handler_opts!(Keyword.get(opts, :handler_opts, []))
    enable_json_response = Keyword.get(opts, :enable_json_response, false)
    protocol_version = Keyword.get(opts, :protocol_version, Dispatch.protocol_version())
    tool_schemas = compile_tool_schemas!(Keyword.get(opts, :tool_schemas, %{}))
    subscription_supervisor = Keyword.get(opts, :subscription_supervisor)
    subscription_registry = Keyword.get(opts, :subscription_registry)
    subscription_endpoint = Keyword.get(opts, :subscription_endpoint, server_mod)
    subscription_queue_limit = Keyword.get(opts, :subscription_queue_limit, 256)
    subscription_keepalive_interval = Keyword.get(opts, :subscription_keepalive_interval, 15_000)
    max_body_length = Keyword.get(opts, :max_body_length, 8_000_000)
    legacy_sse_timeout = Keyword.get(opts, :legacy_sse_timeout, 25_000)

    unless is_integer(max_body_length) and max_body_length > 0 do
      raise ArgumentError, ":max_body_length must be a positive integer"
    end

    unless is_integer(legacy_sse_timeout) and legacy_sse_timeout > 0 do
      raise ArgumentError, ":legacy_sse_timeout must be a positive integer"
    end

    validate_subscription_options!(
      subscription_supervisor,
      subscription_registry,
      subscription_queue_limit,
      subscription_keepalive_interval
    )

    # Build the immutable dispatch config once. Only the non-identity static
    # base reaches Handler.init/1; per-request identity rides ToolContext.
    static_base = if is_function(handler_opts), do: [], else: handler_opts

    config_opts =
      [
        handler_opts: static_base,
        subscriptions_enabled:
          not is_nil(subscription_supervisor) and not is_nil(subscription_registry)
      ] ++
        Keyword.take(server_opts, [:server_info, :instructions, :cache_defaults, :extensions])

    dispatch_config =
      case Config.build(server_mod, config_opts) do
        {:ok, config} -> config
        {:error, reason} -> raise "MCP Plug: handler init failed: #{inspect(reason)}"
      end

    legacy_sessions = :ets.new(:mcp_legacy_sessions, [:set, :public])

    %__MODULE__{
      server_mod: server_mod,
      server_opts: server_opts,
      handler_opts: handler_opts,
      enable_json_response: enable_json_response,
      protocol_version: protocol_version,
      tool_schemas: tool_schemas,
      subscription_supervisor: subscription_supervisor,
      subscription_registry: subscription_registry,
      subscription_endpoint: subscription_endpoint,
      subscription_queue_limit: subscription_queue_limit,
      subscription_keepalive_interval: subscription_keepalive_interval,
      max_body_length: max_body_length,
      legacy_sessions: legacy_sessions,
      legacy_sse_timeout: legacy_sse_timeout,
      config: dispatch_config
    }
  end

  @impl Plug
  def call(conn, config) do
    # Step 1 — enforcement precedes everything (MC-5 / AC7).
    if localhost_request?(conn) do
      route_method(conn, config)
    else
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(403, "Forbidden: non-localhost origin")
    end
  end

  @doc "Returns active legacy session IDs and their server connection pids."
  @spec legacy_sessions(%__MODULE__{}) :: [{String.t(), pid()}]
  def legacy_sessions(%__MODULE__{} = config) do
    :ets.tab2list(config.legacy_sessions)
    |> Enum.map(fn {session_id, session} -> {session_id, session.server} end)
  rescue
    ArgumentError -> []
  end

  defp route_method(conn, config) do
    case conn.method do
      "POST" -> handle_post(conn, config)
      "GET" -> handle_get(conn, config)
      "DELETE" -> handle_legacy_delete(conn, config)
      _ -> method_not_allowed(conn)
    end
  end

  # --- POST: the request/response path ---

  defp handle_post(conn, config) do
    with {:ok, body, conn} <-
           Plug.Conn.read_body(conn,
             length: config.max_body_length,
             read_length: min(config.max_body_length, 1_000_000)
           ),
         {:ok, message} <- Jason.decode(body) do
      handle_decoded_post(conn, config, message)
    else
      {:more, _partial_body, conn} ->
        send_json_error(
          conn,
          413,
          Error.invalid_request_code(),
          "Request body too large",
          "request body exceeds configured maximum"
        )

      {:error, %Jason.DecodeError{} = e} ->
        send_json_error(conn, 400, Error.parse_error_code(), "Parse error", inspect(e))

      {:error, reason} ->
        send_json_error(
          conn,
          400,
          Error.invalid_request_code(),
          "Invalid request",
          inspect(reason)
        )
    end
  end

  defp handle_decoded_post(conn, config, message) when is_map(message) do
    cond do
      stateless_initialize?(conn, message) ->
        send_json_error(
          conn,
          404,
          Error.method_not_found_code(),
          "Method not found",
          "initialize is not part of 2026-07-28",
          Map.get(message, "id")
        )

      legacy_request?(conn, message) ->
        handle_legacy_post(conn, config, message)

      true ->
        handle_stateless_post(conn, config, message)
    end
  end

  defp handle_decoded_post(conn, _config, _message) do
    send_json_error(conn, 400, Error.invalid_request_code(), "Invalid request", "expected object")
  end

  defp handle_stateless_post(conn, config, message) do
    with :ok <- validate_message_shape(message),
         :ok <- validate_required_request_meta(message),
         :ok <- check_routing_headers(conn, message),
         {:ok, identity} <- resolve_identity(config.handler_opts, conn),
         :ok <- check_custom_routing_headers(conn, message, config.tool_schemas, identity),
         {:ok, decoded} <- Protocol.decode_message(message) do
      dispatch(conn, config, decoded, message, identity)
    else
      {:error, {:routing_mismatch, detail}} ->
        send_json_error(
          conn,
          400,
          Error.header_mismatch_code(),
          "Header mismatch",
          detail,
          Map.get(message, "id")
        )

      {:error, {:invalid_params, detail}} ->
        send_json_error(
          conn,
          400,
          Error.invalid_params_code(),
          "Invalid params",
          inspect(detail),
          Map.get(message, "id")
        )

      {:error, {:factory_failed, reason}} ->
        Logger.error("MCP Plug: handler_opts factory failed: #{inspect(reason)}")

        send_json_error(
          conn,
          500,
          Error.internal_error_code(),
          "Internal error",
          "handler_opts factory error",
          Map.get(message, "id")
        )

      {:error, reason} ->
        send_json_error(
          conn,
          400,
          Error.invalid_request_code(),
          "Invalid request",
          inspect(reason),
          Map.get(message, "id")
        )
    end
  end

  defp legacy_request?(conn, message) do
    first_header(conn, "mcp-protocol-version") == LegacyDispatch.protocol_version() or
      (Map.get(message, "method") == "initialize" and
         is_nil(first_header(conn, "mcp-protocol-version"))) or
      not is_nil(first_header(conn, "mcp-session-id"))
  end

  defp stateless_initialize?(conn, %{"method" => "initialize"}) do
    first_header(conn, "mcp-protocol-version") == Dispatch.protocol_version()
  end

  defp stateless_initialize?(_conn, _message), do: false

  defp handle_legacy_post(conn, config, %{"method" => "initialize"} = message) do
    with {:ok, %Request{}} <- Protocol.decode_message(message),
         {:ok, handler_opts} <- resolve_handler_options(config.handler_opts, conn),
         {:ok, session, response, notifications} <-
           start_and_initialize_legacy(config, handler_opts, message) do
      session_id = UUID.uuid4()

      true = :ets.insert(config.legacy_sessions, {session_id, session})

      conn
      |> Plug.Conn.put_resp_header("mcp-session-id", session_id)
      |> send_response(config, response, notifications)
    else
      {:error, {:factory_failed, reason}} ->
        Logger.error("MCP Plug: legacy handler_opts factory failed: #{inspect(reason)}")

        send_json_error(
          conn,
          500,
          Error.internal_error_code(),
          "Internal error",
          "handler_opts factory error",
          Map.get(message, "id")
        )

      {:error, reason} ->
        send_json_error(
          conn,
          400,
          Error.invalid_request_code(),
          "Invalid request",
          inspect(reason),
          Map.get(message, "id")
        )
    end
  end

  defp handle_legacy_post(conn, config, message) do
    session_id = first_header(conn, "mcp-session-id")

    with :ok <- validate_legacy_protocol_header(conn),
         {:ok, session} <- legacy_session(config, session_id) do
      dispatch_legacy_http(conn, config, message, session)
    else
      {:error, detail} -> legacy_protocol_header_error(conn, message, detail)
      :error -> send_json_error(conn, 404, -32_000, "Session not found", session_id)
    end
  end

  defp dispatch_legacy_http(conn, config, message, session) do
    case LegacySession.deliver(session, message, config.legacy_sse_timeout) do
      {:ok, response, notifications} ->
        send_response(conn, config, response, notifications)

      :accepted ->
        Plug.Conn.send_resp(conn, 202, "")

      {:error, :timeout} ->
        send_json_error(
          conn,
          504,
          Error.internal_error_code(),
          "Request timeout",
          "legacy session did not respond",
          Map.get(message, "id")
        )

      {:error, reason} ->
        send_json_error(
          conn,
          400,
          Error.invalid_request_code(),
          "Invalid request",
          inspect(reason),
          Map.get(message, "id")
        )
    end
  end

  defp handle_legacy_delete(conn, config) do
    session_id = first_header(conn, "mcp-session-id")

    with :ok <- validate_legacy_protocol_header(conn),
         {:ok, session} <- legacy_session(config, session_id) do
      LegacySession.close(session)
      true = :ets.delete(config.legacy_sessions, session_id)
      Plug.Conn.send_resp(conn, 200, "")
    else
      {:error, detail} -> legacy_protocol_header_error(conn, %{}, detail)
      :error -> send_json_error(conn, 404, -32_000, "Session not found", session_id)
    end
  end

  defp validate_legacy_protocol_header(conn) do
    legacy_version = LegacyDispatch.protocol_version()

    case first_header(conn, "mcp-protocol-version") do
      ^legacy_version -> :ok
      nil -> {:error, "missing MCP-Protocol-Version"}
      version -> {:error, "unsupported MCP-Protocol-Version: #{inspect(version)}"}
    end
  end

  defp legacy_protocol_header_error(conn, message, detail) do
    send_json_error(
      conn,
      400,
      Error.unsupported_protocol_version_code(),
      "Unsupported protocol version",
      detail,
      Map.get(message, "id")
    )
  end

  defp legacy_session(_config, nil), do: :error

  defp legacy_session(config, session_id) do
    case :ets.lookup(config.legacy_sessions, session_id) do
      [{^session_id, session}] ->
        if Process.alive?(session.server) and Process.alive?(session.transport) do
          {:ok, session}
        else
          :ets.delete(config.legacy_sessions, session_id)
          :error
        end

      [] ->
        :error
    end
  rescue
    ArgumentError -> :error
  end

  defp resolve_handler_options(handler_opts, conn) when is_function(handler_opts, 1) do
    case handler_opts.(conn) do
      opts when is_list(opts) ->
        if Keyword.keyword?(opts),
          do: {:ok, opts},
          else: {:error, {:factory_failed, :not_keyword}}

      _other ->
        {:error, {:factory_failed, :not_keyword}}
    end
  rescue
    exception -> {:error, {:factory_failed, {:raised, exception, __STACKTRACE__}}}
  catch
    kind, reason -> {:error, {:factory_failed, {kind, reason}}}
  end

  defp resolve_handler_options(handler_opts, _conn) when is_list(handler_opts),
    do: {:ok, handler_opts}

  defp start_legacy_session(config, handler_opts) do
    server_opts =
      Keyword.take(config.server_opts, [:server_info, :instructions, :request_timeout])

    LegacySession.start(config.server_mod, handler_opts, server_opts)
  end

  defp start_and_initialize_legacy(config, handler_opts, message) do
    with {:ok, session} <- start_legacy_session(config, handler_opts) do
      case LegacySession.deliver(session, message, config.legacy_sse_timeout) do
        {:ok, response, notifications} ->
          {:ok, session, response, notifications}

        {:error, reason} ->
          LegacySession.close(session)
          {:error, reason}
      end
    end
  end

  defp validate_message_shape(%{"method" => method} = message) when is_binary(method) do
    params = Map.get(message, "params", %{})

    cond do
      not is_map(params) ->
        {:error, :params_must_be_an_object}

      Map.has_key?(params, "_meta") and not is_map(Map.get(params, "_meta")) ->
        {:error, :meta_must_be_an_object}

      method == "tools/call" and Map.has_key?(params, "arguments") and
          not is_map(Map.get(params, "arguments")) ->
        {:error, :arguments_must_be_an_object}

      true ->
        :ok
    end
  end

  defp validate_message_shape(_message), do: :ok

  defp validate_required_request_meta(%{"id" => _id, "method" => _method} = message) do
    case message |> Map.get("params") |> Meta.from_params() |> Meta.validate_required() do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_params, reason}}
    end
  end

  defp validate_required_request_meta(_message), do: :ok

  # The stateless core issues no server-to-client requests, so a response has
  # nothing to correlate. It is still a valid routing-header-free JSON-RPC
  # message and receives the same empty acknowledgment as on stdio.
  defp dispatch(conn, _config, %Response{}, _raw_message, _identity) do
    Plug.Conn.send_resp(conn, 202, "")
  end

  defp dispatch(
         conn,
         config,
         %Request{method: "subscriptions/listen", params: params, id: id},
         _raw_message,
         identity
       ) do
    open_subscription_stream(conn, config, id, params, identity)
  end

  defp dispatch(conn, config, decoded, raw_message, identity) do
    # Security (Ruling 7): the notification collector is process-local, and a
    # request process may be reused. Clear any residue at request START so a
    # prior request's notifications can never survive INTO this one, and wrap
    # dispatch in an `after` so a *raising* handler cannot leave residue behind
    # for the NEXT request. Belt and braces: either guard alone suffices; both
    # together mean no code path can flush one principal's notifications into
    # another principal's response.
    Process.delete(@notifications_key)

    request_id = Map.get(raw_message, "id")

    ctx = %ToolContext{
      request_id: request_id,
      meta: get_in(raw_message, ["params", "_meta"]),
      identity: identity,
      reply_sink: notification_collector()
    }

    try do
      case Dispatch.dispatch(decoded, ctx, config.config) do
        {:reply, response} ->
          notifications = take_notifications()
          send_response(conn, config, response, notifications)

        :noreply ->
          Plug.Conn.send_resp(conn, 202, "")
      end
    after
      Process.delete(@notifications_key)
    end
  end

  # --- GET: empty event stream (no standing session stream in stateless mode) ---

  defp handle_get(conn, config) do
    if accepts_sse?(conn) do
      case first_header(conn, "mcp-session-id") do
        nil -> send_empty_sse(conn)
        session_id -> handle_legacy_get(conn, config, session_id)
      end
    else
      send_json_error(conn, 406, -32_000, "Not Acceptable", "Must accept text/event-stream")
    end
  end

  defp handle_legacy_get(conn, config, session_id) do
    with :ok <- validate_legacy_protocol_header(conn),
         {:ok, session} <- legacy_session(config, session_id) do
      body =
        case LegacySession.next_event(session, config.legacy_sse_timeout) do
          {:ok, message} -> SSE.encode_message(message)
          {:error, :timeout} -> ""
          {:error, _reason} -> ""
        end

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_resp(200, body)
    else
      {:error, detail} -> legacy_protocol_header_error(conn, %{}, detail)
      :error -> send_json_error(conn, 404, -32_000, "Session not found", session_id)
    end
  end

  defp send_empty_sse(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.send_resp(200, "")
  end

  # --- Routing headers (SEP-2243) ---

  # Routing headers are required on JSON-RPC requests. They must match the
  # request body, and `Mcp-Name` must decode to the request's
  # **method-appropriate** target (SEP-2243, §"Mcp-Name":
  # `params.name` for `tools/call`/`prompts/get`, `params.uri` for
  # `resources/read`). Enables gateways to route without inspecting the body.
  defp check_routing_headers(conn, %{"id" => _id, "method" => method} = message) do
    params = Map.get(message, "params", %{})
    version = get_in(params, ["_meta", "io.modelcontextprotocol/protocolVersion"])

    with {:ok, header_version} <- required_header(conn, "mcp-protocol-version"),
         :ok <- matching_header("mcp-protocol-version", header_version, version),
         {:ok, header_method} <- required_header(conn, "mcp-method"),
         :ok <- matching_header("mcp-method", header_method, method) do
      check_name_header(conn, method, params)
    end
  end

  defp check_routing_headers(_conn, _message), do: :ok

  defp required_header(conn, name) do
    case first_header(conn, name) do
      nil -> {:error, {:routing_mismatch, "missing required #{name} header"}}
      value -> {:ok, value}
    end
  end

  defp matching_header(_name, value, value), do: :ok

  defp matching_header(name, header_value, body_value) do
    {:error,
     {:routing_mismatch, "#{name} #{inspect(header_value)} != body value #{inspect(body_value)}"}}
  end

  defp check_name_header(conn, method, params)
       when method in ["tools/call", "prompts/get", "resources/read"] do
    target = routing_target(method, params)

    with {:ok, header_name} <- required_header(conn, "mcp-name"),
         {:ok, decoded_name} <- decode_header_value(header_name) do
      matching_header("mcp-name", decoded_name, target)
    end
  end

  defp check_name_header(conn, _method, _params) do
    case first_header(conn, "mcp-name") do
      nil -> :ok
      value -> {:error, {:routing_mismatch, "unexpected mcp-name header #{inspect(value)}"}}
    end
  end

  defp decode_header_value("=?base64?" <> encoded_with_suffix = value) do
    if String.ends_with?(encoded_with_suffix, "?=") do
      encoded = binary_part(encoded_with_suffix, 0, byte_size(encoded_with_suffix) - 2)

      with {:ok, decoded} <- Base.decode64(encoded),
           true <- String.valid?(decoded) do
        {:ok, decoded}
      else
        _ -> {:error, {:routing_mismatch, "invalid Base64-sentinel mcp-name header"}}
      end
    else
      decode_plain_header_value(value)
    end
  end

  defp decode_header_value(value), do: decode_plain_header_value(value)

  defp decode_plain_header_value(value) do
    trimmed = String.trim(value)

    if plain_header_value?(trimmed) do
      {:ok, trimmed}
    else
      {:error, {:routing_mismatch, "invalid plain mcp-name header"}}
    end
  end

  defp plain_header_value?(value) do
    String.valid?(value) and
      Enum.all?(:binary.bin_to_list(value), &(&1 == 0x09 or &1 in 0x20..0x7E))
  end

  # SEP-2243: the `Mcp-Name` target is the method-appropriate field —
  # `params.name` for tool/prompt calls, `params.uri` for resource reads.
  defp routing_target(method, params) when is_map(params) do
    case method do
      "tools/call" -> Map.get(params, "name")
      "prompts/get" -> Map.get(params, "name")
      "resources/read" -> Map.get(params, "uri")
      _ -> nil
    end
  end

  defp routing_target(_method, _params), do: nil

  defp check_custom_routing_headers(
         conn,
         %{"method" => "tools/call", "params" => params},
         tool_schemas,
         identity
       )
       when is_map(params) do
    name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    with {:ok, descriptors} <- resolve_tool_descriptors(tool_schemas, name, identity),
         do: validate_custom_descriptors(conn, arguments, descriptors)
  end

  defp check_custom_routing_headers(_conn, _message, _tool_schemas, _identity), do: :ok

  defp validate_custom_descriptors(conn, arguments, descriptors) do
    Enum.reduce_while(descriptors, :ok, fn descriptor, :ok ->
      case check_custom_header(conn, arguments, descriptor) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp check_custom_header(conn, arguments, descriptor) do
    header_name = "mcp-param-#{String.downcase(descriptor.header)}"
    header_value = first_header(conn, header_name)

    case ToolRouting.argument_value(arguments, descriptor) do
      :missing when is_nil(header_value) ->
        :ok

      :missing ->
        routing_mismatch("unexpected #{header_name} header")

      {:ok, _expected} when is_nil(header_value) ->
        routing_mismatch("missing required #{header_name} header")

      {:ok, expected} ->
        with {:ok, decoded} <- decode_header_value(header_value) do
          matching_custom_header(header_name, decoded, expected, descriptor.type)
        end

      {:error, reason} ->
        routing_mismatch("invalid #{header_name} argument: #{reason}")
    end
  end

  defp matching_custom_header(name, header_value, body_value, "integer") do
    with {header_integer, ""} <- Integer.parse(header_value),
         {body_integer, ""} <- Integer.parse(body_value),
         true <- header_integer == body_integer do
      :ok
    else
      _ -> matching_header(name, header_value, body_value)
    end
  end

  defp matching_custom_header(name, header_value, body_value, _type),
    do: matching_header(name, header_value, body_value)

  defp resolve_tool_descriptors(tool_schemas, name, _identity) when is_map(tool_schemas),
    do: {:ok, Map.get(tool_schemas, name, [])}

  defp resolve_tool_descriptors(resolver, name, identity) when is_function(resolver, 2) do
    case resolver.(name, identity) do
      nil -> {:ok, []}
      schema -> ToolRouting.descriptors(schema)
    end
  rescue
    exception -> {:error, {:factory_failed, {:raised, exception, __STACKTRACE__}}}
  end

  defp routing_mismatch(detail), do: {:error, {:routing_mismatch, detail}}

  defp compile_tool_schemas!(resolver) when is_function(resolver, 2), do: resolver

  defp compile_tool_schemas!(schemas) when is_map(schemas) do
    Map.new(schemas, fn {name, schema} ->
      case ToolRouting.descriptors(schema) do
        {:ok, descriptors} ->
          {name, descriptors}

        {:error, reason} ->
          raise ArgumentError,
                "invalid tool schema for #{inspect(name)}: #{inspect(reason)}"
      end
    end)
  end

  defp compile_tool_schemas!(other) do
    raise ArgumentError,
          "tool_schemas must be a map or a 2-arity function, got: #{inspect(other)}"
  end

  # --- Long-lived subscriptions/listen response ---

  defp open_subscription_stream(conn, config, id, params, identity) do
    with :ok <- Dispatch.validate_request(params, config.config),
         :ok <- reject_resumption(conn),
         :ok <- subscription_configuration(config),
         {:ok, requested} <- parse_subscription_filter(params),
         {:ok, honored} <- authorize_subscription(config, id, params, requested, identity),
         {:ok, worker} <-
           SubscriptionWorker.start(
             config.subscription_supervisor,
             config.subscription_registry,
             config.subscription_endpoint,
             id,
             self(),
             requested,
             honored,
             queue_limit: config.subscription_queue_limit
           ) do
      conn =
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.put_resp_header("cache-control", "no-cache")
        |> Plug.Conn.put_resp_header("x-accel-buffering", "no")
        |> Plug.Conn.send_chunked(200)

      stream_subscription(conn, worker, config.subscription_keepalive_interval)
    else
      {:error, :resumption_unsupported} ->
        send_json_error(
          conn,
          400,
          Error.invalid_request_code(),
          "Invalid request",
          "Last-Event-ID resumption is unsupported",
          id
        )

      {:error, %Error{} = error} ->
        send_json_error(conn, 400, error.code, error.message, inspect(error.data), id)

      {:error, reason} ->
        send_json_error(
          conn,
          500,
          Error.internal_error_code(),
          "Internal error",
          inspect(reason),
          id
        )
    end
  end

  defp reject_resumption(conn) do
    if Plug.Conn.get_req_header(conn, "last-event-id") == [],
      do: :ok,
      else: {:error, :resumption_unsupported}
  end

  defp subscription_configuration(config) do
    if config.subscription_supervisor && config.subscription_registry,
      do: :ok,
      else: {:error, Error.method_not_found("subscriptions/listen")}
  end

  defp parse_subscription_filter(params) do
    {:ok, ListenParams.from_map(params).notifications}
  rescue
    error in [ArgumentError, KeyError] -> {:error, Error.invalid_params(Exception.message(error))}
  end

  defp authorize_subscription(config, id, params, requested, identity) do
    module = config.config.handler_module

    if function_exported?(module, :handle_listen_subscriptions, 3) do
      context = %ToolContext{
        request_id: id,
        meta: Map.get(params || %{}, "_meta"),
        identity: identity,
        reply_sink: notification_collector()
      }

      case module.handle_listen_subscriptions(requested, context, config.config.handler_state) do
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

  defp stream_subscription(conn, worker, keepalive_interval) do
    case SubscriptionWorker.next(worker, keepalive_interval) do
      {:ok, message} ->
        case Plug.Conn.chunk(conn, SSE.encode_message(message)) do
          {:ok, conn} -> stream_subscription(conn, worker, keepalive_interval)
          {:error, _reason} -> close_disconnected_subscription(conn, worker)
        end

      {:error, :timeout} ->
        case Plug.Conn.chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> stream_subscription(conn, worker, keepalive_interval)
          {:error, _reason} -> close_disconnected_subscription(conn, worker)
        end

      {:error, _reason} ->
        conn
    end
  end

  defp close_disconnected_subscription(conn, worker) do
    if Process.alive?(worker), do: GenServer.stop(worker, :normal)
    conn
  end

  defp validate_subscription_options!(nil, nil, _queue_limit, _keepalive), do: :ok

  defp validate_subscription_options!(supervisor, registry, queue_limit, keepalive) do
    if is_nil(supervisor) or is_nil(registry) do
      raise ArgumentError,
            "subscription_supervisor and subscription_registry must be configured together"
    end

    unless is_integer(queue_limit) and queue_limit > 0 do
      raise ArgumentError, "subscription_queue_limit must be a positive integer"
    end

    unless is_integer(keepalive) and keepalive > 0 do
      raise ArgumentError, "subscription_keepalive_interval must be a positive integer"
    end

    :ok
  end

  # --- Per-request identity resolution (MC-2/Comment B) ---

  defp resolve_identity(fun, conn) when is_function(fun, 1) do
    case fun.(conn) do
      result when is_list(result) ->
        if Keyword.keyword?(result),
          do: {:ok, Keyword.get(result, :identity)},
          else: {:error, {:factory_failed, {:non_keyword_result, result}}}

      other ->
        {:error, {:factory_failed, {:non_keyword_result, other}}}
    end
  rescue
    exception -> {:error, {:factory_failed, {:raised, exception, __STACKTRACE__}}}
  end

  defp resolve_identity(list, _conn) when is_list(list), do: {:ok, Keyword.get(list, :identity)}

  # --- handler_opts validation (fail-fast at mount) ---

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

  # --- Notification collection (per-request, process-local) ---

  # dispatch runs synchronously in this request process, so a handler emitting
  # progress/logging calls this sink inline; collected notifications are flushed
  # as SSE events before the final result. (JSON mode is single-response.) The
  # `@notifications_key` attribute is declared near the top of the module so the
  # security clears in `dispatch/5` bind the real key (see Ruling 7).
  defp notification_collector do
    key = @notifications_key

    fn method, params ->
      encoded = Jason.decode!(Jason.encode!(Notification.new(method, params)))
      Process.put(key, [encoded | Process.get(key, [])])
      :ok
    end
  end

  defp take_notifications do
    notifications = @notifications_key |> Process.get([]) |> Enum.reverse()
    Process.delete(@notifications_key)
    notifications
  end

  # --- Response shaping ---

  defp send_response(conn, config, response, notifications) do
    status = response_status(response)

    if config.enable_json_response do
      send_json_response(conn, response, status)
    else
      send_sse_response(conn, response, notifications, status)
    end
  end

  defp response_status(%{"error" => %{"code" => code}})
       when code in [-32_022, -32_021, -32_602],
       do: 400

  defp response_status(%{"error" => %{"code" => -32_601}}), do: 404

  defp response_status(_response), do: 200

  defp send_json_response(conn, response, status) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(response))
  end

  defp send_sse_response(conn, response, notifications, status) do
    body =
      (notifications ++ [response])
      |> Enum.map_join(&SSE.encode_message/1)

    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.send_resp(status, body)
  end

  defp send_json_error(conn, http_status, code, message, data, id \\ nil) do
    error = %{
      "jsonrpc" => "2.0",
      "id" => id,
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

  # --- Header / origin helpers ---

  defp first_header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp accepts_sse?(conn) do
    conn
    |> Plug.Conn.get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "text/event-stream"))
  end

  @localhost_patterns ~w(localhost 127.0.0.1 [::1])

  defp localhost_request?(conn) do
    origin = Plug.Conn.get_req_header(conn, "origin")
    host = Plug.Conn.get_req_header(conn, "host")

    local_header?(origin) && local_header?(host)
  end

  defp local_header?([]), do: true
  defp local_header?([value]), do: localhost_value?(value)
  defp local_header?(_multiple_values), do: false

  defp localhost_value?(value) do
    host_part =
      value
      |> String.replace(~r{^https?://}, "")
      |> String.split("/")
      |> hd()

    host_without_port = String.replace(host_part, ~r{:\d+$}, "")
    host_without_port in @localhost_patterns
  end
end
