defmodule MCP.Transport.StreamableHTTP.Plug do
  @moduledoc """
  Stateless Plug endpoint for the MCP Streamable HTTP transport (2026-07-28).

  A thin **per-request driver** for `MCP.Server.Dispatch`: there is no
  `initialize` handshake, no `Mcp-Session-Id`, and no session affinity — any
  request is serviceable by any instance behind a round-robin balancer
  (SEP-2575 / SEP-2567). The dispatch `config` is built once at `init/1`; every
  request builds its own `MCP.Server.ToolContext` and calls `Dispatch`.

  Handles `POST` (JSON-RPC request/response) and returns `application/json` or
  `text/event-stream` per the client's `Accept`. `GET` opens an (empty) event
  stream; server→client messages only flow while a client request is being
  processed (SEP-2260), so there is no standing session stream to feed it.

  ## Usage

      plug = MCP.Transport.StreamableHTTP.Plug.new(server_mod: MyApp.Handler)
      {:ok, _} = Bandit.start_link(plug: plug, port: 8080)

  ## Per-request pipeline (strict order)

    1. **Enforcement** — localhost/Origin (and any host auth) runs first, on
       every request, before the identity factory (MC-5 / AC7). A rejected
       request never runs the factory.
    2. **Decode + standard routing headers** — parse the JSON-RPC body; validate
       `Mcp-Method` / `Mcp-Name` against it (SEP-2243) — mismatch → `-32020`.
    3. **Identity resolution** — the `:handler_opts` factory is evaluated
       against *this request's* `conn` (or the static keyword's `:identity`);
       the result populates `ToolContext.identity`, never from `params`
       (MC-2/Comment B, MC-3, MC-4). Factory failure → controlled `-32603`,
       no dispatch (MC-6).
    4. **Custom routing headers** — resolve the selected tool schema using the
       authenticated identity and validate recognized `Mcp-Param-*` values.
    5. **Dispatch** — `Dispatch.dispatch(message, ctx, config)`.

  ## Options

    * `:server_mod` (required) — the `MCP.Server.Handler` module.
    * `:server_opts` — `:server_info`, `:instructions`, `:cache_defaults`
      forwarded to `MCP.Server.Config`. If you raise `:cache_defaults` above the
      no-store default on identity-dependent results, set `cacheScope: "private"`
      — see the security warning on `MCP.Server.Config.build/2`.
    * `:handler_opts` — static `keyword()` **or** a `(Plug.Conn.t() ->
      keyword())` factory. The factory is evaluated **per request** against the
      request's `conn` and its `:identity` populates the per-request context.
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
  alias MCP.Protocol.Messages.{Notification, Response}
  alias MCP.Protocol.ToolRouting
  alias MCP.Server.{Config, Dispatch, ToolContext}
  alias MCP.Transport.SSE

  @typedoc """
  Options threaded into the handler's identity resolution: a static keyword
  list, or a factory `(Plug.Conn.t() -> keyword())` evaluated per request.
  """
  @type handler_opts :: keyword() | (Plug.Conn.t() -> keyword())

  defstruct [
    :server_mod,
    :handler_opts,
    :enable_json_response,
    :protocol_version,
    :tool_schemas,
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

    # Build the immutable dispatch config once. Only the non-identity static
    # base reaches Handler.init/1; per-request identity rides ToolContext.
    static_base = if is_function(handler_opts), do: [], else: handler_opts

    config_opts =
      [handler_opts: static_base] ++
        Keyword.take(server_opts, [:server_info, :instructions, :cache_defaults])

    dispatch_config =
      case Config.build(server_mod, config_opts) do
        {:ok, config} -> config
        {:error, reason} -> raise "MCP Plug: handler init failed: #{inspect(reason)}"
      end

    %__MODULE__{
      server_mod: server_mod,
      handler_opts: handler_opts,
      enable_json_response: enable_json_response,
      protocol_version: protocol_version,
      tool_schemas: tool_schemas,
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

  defp route_method(conn, config) do
    case conn.method do
      "POST" -> handle_post(conn, config)
      "GET" -> handle_get(conn)
      _ -> method_not_allowed(conn)
    end
  end

  # --- POST: the request/response path ---

  defp handle_post(conn, config) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn),
         {:ok, message} <- Jason.decode(body),
         :ok <- check_routing_headers(conn, message),
         {:ok, identity} <- resolve_identity(config.handler_opts, conn),
         :ok <- check_custom_routing_headers(conn, message, config.tool_schemas, identity),
         {:ok, decoded} <- Protocol.decode_message(message) do
      dispatch(conn, config, decoded, message, identity)
    else
      {:error, %Jason.DecodeError{} = e} ->
        send_json_error(conn, 400, Error.parse_error_code(), "Parse error", inspect(e))

      {:error, {:routing_mismatch, detail}} ->
        send_json_error(conn, 400, Error.header_mismatch_code(), "Header mismatch", detail)

      {:error, {:factory_failed, reason}} ->
        Logger.error("MCP Plug: handler_opts factory failed: #{inspect(reason)}")

        send_json_error(
          conn,
          500,
          Error.internal_error_code(),
          "Internal error",
          "handler_opts factory error"
        )

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

  # The stateless core issues no server-to-client requests, so a response has
  # nothing to correlate. It is still a valid routing-header-free JSON-RPC
  # message and receives the same empty acknowledgment as on stdio.
  defp dispatch(conn, _config, %Response{}, _raw_message, _identity) do
    Plug.Conn.send_resp(conn, 202, "")
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
        {:reply, response, _state} ->
          notifications = take_notifications()
          send_response(conn, config, response, notifications)

        {:noreply, _state} ->
          Plug.Conn.send_resp(conn, 202, "")
      end
    after
      Process.delete(@notifications_key)
    end
  end

  # --- GET: empty event stream (no standing session stream in stateless mode) ---

  defp handle_get(conn) do
    if accepts_sse?(conn) do
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_resp(200, "")
    else
      send_json_error(conn, 406, -32_000, "Not Acceptable", "Must accept text/event-stream")
    end
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
         :ok <- valid_protocol_version_header(header_version),
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

  defp valid_protocol_version_header(value) do
    case Date.from_iso8601(value) do
      {:ok, _date} -> :ok
      {:error, _reason} -> {:error, {:routing_mismatch, "malformed mcp-protocol-version"}}
    end
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

  defp decode_header_value("=?base64?" <> encoded_with_suffix) do
    with true <- String.ends_with?(encoded_with_suffix, "?="),
         encoded <- binary_part(encoded_with_suffix, 0, byte_size(encoded_with_suffix) - 2),
         {:ok, decoded} <- Base.decode64(encoded),
         true <- String.valid?(decoded) do
      {:ok, decoded}
    else
      _ -> {:error, {:routing_mismatch, "invalid Base64-sentinel mcp-name header"}}
    end
  end

  defp decode_header_value(value) do
    if plain_header_value?(value) do
      {:ok, value}
    else
      {:error, {:routing_mismatch, "invalid plain mcp-name header"}}
    end
  end

  defp plain_header_value?(value) do
    String.valid?(value) and
      String.trim(value) == value and
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
       when code == -32_022,
       do: 400

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
    |> Plug.Conn.put_resp_header("allow", "GET, POST")
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

    origin_ok = origin == [] || Enum.any?(origin, &localhost_value?/1)
    host_ok = host == [] || Enum.any?(host, &localhost_value?/1)

    origin_ok && host_ok
  end

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
