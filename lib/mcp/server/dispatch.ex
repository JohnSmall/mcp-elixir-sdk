defmodule MCP.Server.Dispatch do
  @moduledoc """
  Stateless per-request dispatch for the MCP 2026-07-28 protocol core.

  This is the stateless successor to the per-session `MCP.Server` GenServer: a
  **pure, per-request** entry point that a transport calls once per decoded
  message. There is no `initialize` handshake, no `:ready` gate, and no
  session — every request stands alone (SEP-2575 / SEP-2567).

  ## Contract

      dispatch(message, context, config)
        :: {:reply, response_map, handler_state}
         | {:noreply, handler_state}
         | {:stream, MCP.Server.Subscription.t(), handler_state}
         | {:listen_refused, response_map, handler_state}

  The third shape is MES-15's `subscriptions/listen`: the driver must hold the
  response open, write `subscription.ack` first, and then write frames until
  the stream ends.

  The fourth is the same method **refused by the handler**
  (`handle_listen/3` returning `{:error, ...}`). It carries an ordinary error
  response the driver sends exactly like a `{:reply, ...}` — it is a separate
  shape only because of what else the driver owes: `handle_listen/3` *ran*, and
  was handed a live `context.stream_sink`, so the driver must tear the
  subscription down and tell the handler, precisely as it does when a stream it
  did open ends. The two cases a driver must NOT treat that way — a malformed
  filter, and a deployment that does not stream — never reach the handler and
  stay `{:reply, ...}`. Distinguishing them from outside the dispatch would
  mean re-deriving its routing decisions from the response, so the dispatch
  says which happened instead.

  > #### A driver opts in; it is never surprised {: .warning}
  >
  > `{:stream, ...}` and `{:listen_refused, ...}` are returned **only** when
  > `config.streaming` is true — which a driver sets to say it can hold a
  > response open. A driver that does not set it gets `-32601` for
  > `subscriptions/listen` and can never receive either, so adding them cannot
  > turn a missing `case` clause into a runtime `FunctionClauseError`. That
  > guarantee extends to third-party drivers this project never compiles, which
  > is why the flag exists rather than the contract simply widening. Both
  > shapes are gated on the *same* flag, so a driver that already handles
  > `{:stream, ...}` has one clause to add and no new condition to check.

  * `message` — a decoded `MCP.Protocol.Messages.Request` or `Notification`.
  * `context` — the per-request `MCP.Server.ToolContext` carrying `:identity`,
    already populated by the transport pipeline (HTTP: per request from `conn`;
    stdio: once at launch — PO Comment B). **The dispatch never derives identity
    from the message body** — see MC-2/MC-4.
  * `config` — `%{handler_module, handler_state, server_info, capabilities,
    instructions, protocol_version}`.

  The context is passed to **every identity-capable handler callback** (MC-1).
  MC-1 is **strict** (PO Ruling 4): the context-bearing callback arity is
  *required* for every identity-capable family — there is **no legacy
  no-context fallback**. A handler that does not implement the required context
  arity is a contract error, surfaced as method-not-found; the legacy arity is
  **never** invoked.

  > #### Provenance {: .info}
  > This paragraph corrects doc drift: the MES-8 F3 correction removed the
  > legacy-arity fallback from `call/6`, but the moduledoc still described it
  > (MES-9 review F3). Doc statements about removed behaviour are claims too.

  Removed methods return the stateless behaviour (no legacy path): `initialize`
  → `UnsupportedProtocolVersion` (-32022); `ping` and `logging/setLevel` →
  method-not-found.
  """

  alias MCP.Protocol.Error
  alias MCP.Protocol.Messages.{Discover, MRTR, Notification, Request, Subscriptions}
  alias MCP.Protocol.Meta
  alias MCP.Protocol.Methods
  alias MCP.Server.Subscription
  alias MCP.Server.ToolContext

  # Conservative caching policy default (SEP-2549): no-store (ttlMs 0), public
  # scope. `resultType` "complete" is the Result base requirement (schema.ts:658).
  @default_cache_defaults {0, "public"}

  @stateless_protocol_version "2026-07-28"

  @doc "The protocol version this stateless core targets."
  def protocol_version, do: @stateless_protocol_version

  @type config :: %{optional(atom()) => term()}
  @type result ::
          {:reply, map(), term()}
          | {:noreply, term()}
          | {:stream, Subscription.t(), term()}
          | {:listen_refused, map(), term()}

  @spec dispatch(Request.t() | Notification.t(), ToolContext.t(), config()) :: result()
  def dispatch(%Request{id: id, method: method, params: params}, %ToolContext{} = ctx, config) do
    handle_request(method, id, params, seal_stream_sink(ctx, method), config)
  end

  def dispatch(%Notification{method: method, params: params}, %ToolContext{} = ctx, config) do
    handle_notification(method, params, seal_stream_sink(ctx, nil), config)
  end

  # The stream sink is reachable ONLY from the listen open callback. Clearing it
  # here — once, for every other method, present and future — is what makes
  # "a request-scoped notification cannot reach a listen stream" a property of
  # the dispatch rather than of each route remembering to do it. A new route
  # added later inherits the guarantee without knowing it exists.
  defp seal_stream_sink(ctx, method) do
    if method == Methods.subscriptions_listen(), do: ctx, else: %{ctx | stream_sink: nil}
  end

  # --- Removed methods: stateless behaviour, no legacy path ---

  defp handle_request("initialize", id, _params, _ctx, config) do
    reply(
      id,
      Error.unsupported_protocol_version(
        "the initialize handshake is removed in 2026-07-28; carry protocol version in per-request _meta"
      ),
      config
    )
  end

  defp handle_request(method, id, _params, _ctx, config)
       when method in ["ping", "logging/setLevel"] do
    reply(id, Error.method_not_found(method), config)
  end

  # --- server/discover: the version-discovery probe (no version gate) ---

  defp handle_request("server/discover", id, _params, _ctx, config) do
    result =
      Discover.Result.to_map(%Discover.Result{
        supported_versions: [target_version(config)],
        capabilities: Map.get(config, :capabilities),
        server_info: Map.get(config, :server_info),
        instructions: Map.get(config, :instructions)
      })

    {:reply, success(id, result), config.handler_state}
  end

  # --- Everything else: per-request version gate, then route ---

  defp handle_request(method, id, params, ctx, config) do
    meta = Meta.from_params(params)

    case Meta.validate_protocol_version(meta, target_version(config)) do
      :ok -> route(method, id, params, ctx, config)
      {:error, _} -> reply(id, Error.unsupported_protocol_version(meta.protocol_version), config)
    end
  end

  # --- Routing to identity-capable handler callbacks (context passed to each) ---

  defp route("tools/list", id, params, ctx, config) do
    cursor = get_in_params(params, "cursor")

    call(
      config,
      ctx,
      :handle_list_tools,
      [cursor],
      fn
        {:ok, tools, next_cursor, state} ->
          {cacheable(list_result("tools", tools, next_cursor), config), state}
      end,
      id
    )
  end

  # tools/call is the MRTR entry point: the per-request context carries any
  # continuation (requestState/inputResponses) parsed from params (SEP-2322),
  # and the handler may return `{:input_required, ...}` to request client input.
  defp route("tools/call", id, params, ctx, config) do
    name = Map.get(params || %{}, "name", "")
    args = Map.get(params || %{}, "arguments", %{})
    ctx = %{ctx | input: MRTR.continuation_from_params(params)}

    call(
      config,
      ctx,
      :handle_call_tool,
      [name, args],
      fn
        {:ok, content, state} ->
          {complete(%{"content" => content}), state}

        {:ok, content, is_error, state} ->
          {complete(maybe_error(%{"content" => content}, is_error)), state}

        {:input_required, input_requests, request_state, state} ->
          {MRTR.input_required(input_requests, request_state), state}

        {:error, code, message, state} ->
          {{:error, %Error{code: code, message: message}}, state}
      end,
      id
    )
  end

  defp route("resources/list", id, params, ctx, config) do
    cursor = get_in_params(params, "cursor")

    call(
      config,
      ctx,
      :handle_list_resources,
      [cursor],
      fn
        {:ok, resources, next_cursor, state} ->
          {cacheable(list_result("resources", resources, next_cursor), config), state}
      end,
      id
    )
  end

  defp route("resources/read", id, params, ctx, config) do
    uri = Map.get(params || %{}, "uri", "")

    call(
      config,
      ctx,
      :handle_read_resource,
      [uri],
      fn
        {:ok, contents, state} -> {cacheable(%{"contents" => contents}, config), state}
        {:error, code, message, state} -> {{:error, %Error{code: code, message: message}}, state}
      end,
      id
    )
  end

  defp route("resources/templates/list", id, params, ctx, config) do
    cursor = get_in_params(params, "cursor")

    call(
      config,
      ctx,
      :handle_list_resource_templates,
      [cursor],
      fn
        {:ok, templates, next_cursor, state} ->
          {cacheable(list_result("resourceTemplates", templates, next_cursor), config), state}
      end,
      id
    )
  end

  defp route("prompts/list", id, params, ctx, config) do
    cursor = get_in_params(params, "cursor")

    call(
      config,
      ctx,
      :handle_list_prompts,
      [cursor],
      fn
        {:ok, prompts, next_cursor, state} ->
          {cacheable(list_result("prompts", prompts, next_cursor), config), state}
      end,
      id
    )
  end

  defp route("prompts/get", id, params, ctx, config) do
    name = Map.get(params || %{}, "name", "")
    args = Map.get(params || %{}, "arguments")

    call(
      config,
      ctx,
      :handle_get_prompt,
      [name, args],
      fn
        {:ok, result, state} -> {complete(result), state}
        {:error, code, message, state} -> {{:error, %Error{code: code, message: message}}, state}
      end,
      id
    )
  end

  defp route("completion/complete", id, params, ctx, config) do
    ref = Map.get(params || %{}, "ref", %{})
    argument = Map.get(params || %{}, "argument", %{})

    call(
      config,
      ctx,
      :handle_complete,
      [ref, argument],
      fn
        {:ok, completion, state} -> {complete(%{"completion" => completion}), state}
      end,
      id
    )
  end

  # --- subscriptions/listen: the long-lived notification stream ---

  defp route("subscriptions/listen", id, params, ctx, config) do
    if Map.get(config, :streaming, false) do
      listen(id, params, ctx, config)
    else
      # This deployment cannot hold a response stream open (HTTP JSON mode,
      # or a driver that has not opted in), and the listen response IS an SSE
      # stream — there is no conforming way to render it as a single JSON
      # body (streamable-http.mdx:107-113, :217-234). So the honest answer is
      # an explicit refusal rather than a stream that silently delivers
      # nothing.
      #
      # -32601 rather than a new code: -32020..-32099 is reserved for the
      # spec and off limits, and allocating from the implementation-defined
      # -32000..-32019 range would invent SDK-private semantics no client
      # understands. -32601 is already what this endpoint returns for a
      # method it does not implement, and is what the spec's own
      # compatibility guidance treats as the "not supported" signal
      # (stdio.mdx:131-141). It is honest only because such a deployment also
      # advertises no subscription capability (MCP.Server.Config), so a
      # conforming client never calls this here in the first place.
      reply(id, Error.method_not_found("subscriptions/listen"), config)
    end
  end

  defp route(method, id, _params, _ctx, config) do
    reply(id, Error.method_not_found(method), config)
  end

  defp listen(id, params, ctx, config) do
    case Subscriptions.parse_filter(params) do
      {:ok, requested} ->
        open_subscription(id, requested, ctx, config)

      {:error, reason} ->
        # `notifications` is REQUIRED (schema.ts:1301) even though every field
        # inside it is optional, so an absent one is a malformed request while
        # an empty `{}` is a legal "subscribe to nothing".
        reply(
          id,
          Error.invalid_params("subscriptions/listen requires params.notifications (#{reason})"),
          config
        )
    end
  end

  defp open_subscription(id, requested, ctx, config) do
    mod = config.handler_module

    if function_exported?(mod, :handle_listen, 3) do
      case mod.handle_listen(requested, ctx, config.handler_state) do
        {:ok, handler_honoured, state} ->
          {:stream, Subscription.new(id, narrow(requested, handler_honoured, config)), state}

        # Not `{:reply, ...}`: the handler ran and holds a sink, so the driver
        # owes it the same teardown a closed stream gets. See the contract note
        # in the moduledoc.
        {:error, code, message, state} ->
          {:listen_refused, error_response(id, %Error{code: code, message: message}), state}
      end
    else
      reply(id, Error.method_not_found("subscriptions/listen"), config)
    end
  end

  # The honoured set is the intersection of three INDEPENDENT narrowings, so no
  # single one of them can widen it:
  #
  #   1. what the client asked for  — the MUST NOT at subscriptions.mdx:14-16;
  #   2. what the handler agreed to — the per-principal authorization decision;
  #   3. what the server advertises — so the acknowledgment can never claim more
  #      than `server/discover` did, which is what keeps the two honest about
  #      each other rather than merely both plausible.
  #
  # Applying (3) here rather than trusting the handler also means a handler that
  # over-returns is corrected rather than believed.
  defp narrow(requested, handler_honoured, config) do
    advertised = Subscriptions.permitted_by(Map.get(config, :capabilities))

    requested
    |> Subscriptions.intersect(handler_honoured)
    |> Subscriptions.restrict_to_advertised(advertised)
  end

  # --- Notifications (SDK-internal; never dispatched to consumer callbacks) ---

  defp handle_notification("notifications/initialized", _params, _ctx, config) do
    # Removed in the stateless core (no handshake). Tolerated as a no-op.
    {:noreply, config.handler_state}
  end

  defp handle_notification(_method, _params, _ctx, config) do
    {:noreply, config.handler_state}
  end

  # --- Callback invocation: prefer the context-bearing arity (MC-1) ---

  # Calls the **context-bearing** callback `name` (leading_args ++ [context, state]).
  #
  # MC-1 is strict (PO Ruling 4): the context arity is REQUIRED for every
  # identity-capable family — there is NO legacy no-context fallback (that would
  # be uncharted dual-era support, contra PO ruling 2). A handler that does not
  # implement the required context arity is a contract error, surfaced as
  # method-not-found rather than silently invoked without a context.
  defp call(config, ctx, name, leading_args, shape, id) do
    mod = config.handler_module
    state = config.handler_state
    ctx_args = leading_args ++ [ctx, state]

    if function_exported?(mod, name, length(ctx_args)) do
      apply(mod, name, ctx_args) |> finish(shape, id, config)
    else
      reply(id, Error.method_not_found(Atom.to_string(name)), config)
    end
  end

  defp finish(callback_return, shape, id, _config) do
    case shape.(callback_return) do
      {{:error, %Error{} = e}, state} -> {:reply, error_response(id, e), state}
      {result_map, state} -> {:reply, success(id, result_map), state}
    end
  end

  # --- Result/response helpers ---

  defp list_result(key, items, next_cursor) do
    base = %{key => items}
    if next_cursor, do: Map.put(base, "nextCursor", next_cursor), else: base
  end

  # Every result carries `resultType` (Result base, schema.ts:658).
  defp complete(map), do: Map.put(map, "resultType", "complete")

  # CacheableResult (list/read) additionally carries ttlMs/cacheScope
  # (schema.ts:969). Policy default is no-store; a config `:cache_defaults`
  # {ttl_ms, scope} overrides.
  defp cacheable(map, config) do
    {ttl_ms, cache_scope} = Map.get(config, :cache_defaults, @default_cache_defaults)

    map
    |> complete()
    |> Map.put("ttlMs", ttl_ms)
    |> Map.put("cacheScope", cache_scope)
  end

  defp maybe_error(result, true), do: Map.put(result, "isError", true)
  defp maybe_error(result, _), do: result

  defp reply(id, %Error{} = error, config) do
    {:reply, error_response(id, error), config.handler_state}
  end

  defp success(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp error_response(id, %Error{} = e) do
    error = %{"code" => e.code, "message" => e.message}
    error = if e.data, do: Map.put(error, "data", e.data), else: error
    %{"jsonrpc" => "2.0", "id" => id, "error" => error}
  end

  defp target_version(config), do: Map.get(config, :protocol_version, @stateless_protocol_version)

  defp get_in_params(nil, _key), do: nil
  defp get_in_params(params, key), do: Map.get(params, key)
end
