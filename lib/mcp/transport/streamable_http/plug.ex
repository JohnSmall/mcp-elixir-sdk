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
    2. **Decode + routing headers** — parse the JSON-RPC body; validate any
       `Mcp-Method` / `Mcp-Name` routing headers against it (SEP-2243) —
       mismatch → `-32020`.
    3. **Identity resolution** — the `:handler_opts` factory is evaluated
       against *this request's* `conn` (or the static keyword's `:identity`);
       the result populates `ToolContext.identity`, never from `params`
       (MC-2/Comment B, MC-3, MC-4). Factory failure → controlled `-32603`,
       no dispatch (MC-6).
    4. **Dispatch** — `Dispatch.dispatch(message, ctx, config)`.

  ## Options

    * `:server_mod` (required) — the `MCP.Server.Handler` module.
    * `:server_opts` — `:server_info`, `:instructions`, `:cache_defaults`
      forwarded to `MCP.Server.Config`.
    * `:handler_opts` — static `keyword()` **or** a `(Plug.Conn.t() ->
      keyword())` factory. The factory is evaluated **per request** against the
      request's `conn` and its `:identity` populates the per-request context.
      The static form's `:identity` is used as a constant. (The non-identity
      base is passed once to `Handler.init/1` at mount.)
    * `:enable_json_response` — return `application/json` instead of SSE for
      request/response (default: false).
    * `:protocol_version` — advertised version (default: the stateless core's).

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
  alias MCP.Protocol.Messages.Notification
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
    :config
  ]

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

  defp dispatch(conn, config, decoded, raw_message, identity) do
    request_id = Map.get(raw_message, "id")

    ctx = %ToolContext{
      request_id: request_id,
      meta: get_in(raw_message, ["params", "_meta"]),
      identity: identity,
      reply_sink: notification_collector()
    }

    case Dispatch.dispatch(decoded, ctx, config.config) do
      {:reply, response, _state} ->
        notifications = take_notifications()
        send_response(conn, config, response, notifications)

      {:noreply, _state} ->
        Plug.Conn.send_resp(conn, 202, "")
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

  # `Mcp-Method` must match the body method; `Mcp-Name` (when present) must
  # match the request's **method-appropriate** target (SEP-2243, §"Mcp-Name":
  # `params.name` for `tools/call`/`prompts/get`, `params.uri` for
  # `resources/read`). Enables gateways to route without inspecting the body.
  defp check_routing_headers(conn, message) do
    method = Map.get(message, "method")
    header_method = first_header(conn, "mcp-method")
    header_name = first_header(conn, "mcp-name")
    target = routing_target(method, Map.get(message, "params"))

    cond do
      header_method && header_method != method ->
        {:error, {:routing_mismatch, "Mcp-Method #{header_method} != #{inspect(method)}"}}

      header_name && target && header_name != target ->
        {:error, {:routing_mismatch, "Mcp-Name #{header_name} != #{inspect(target)}"}}

      true ->
        :ok
    end
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
  # as SSE events before the final result. (JSON mode is single-response.)
  @notifications_key :mcp_plug_notifications

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
    if config.enable_json_response do
      send_json_response(conn, response)
    else
      send_sse_response(conn, response, notifications)
    end
  end

  defp send_json_response(conn, response) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(response))
  end

  defp send_sse_response(conn, response, notifications) do
    body =
      (notifications ++ [response])
      |> Enum.map_join(&SSE.encode_message/1)

    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.send_resp(200, body)
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
