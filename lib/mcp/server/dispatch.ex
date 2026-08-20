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

  require Logger

  # Conservative caching policy default (SEP-2549): no-store (ttlMs 0), public
  # scope. `resultType` "complete" is the Result base requirement (schema.ts:658).
  @default_cache_defaults {0, "public"}

  @stateless_protocol_version "2026-07-28"

  # The whole of `t:MCP.Server.Handler.call_tool_extras/0`. Anything else in the
  # slot-3 map is dropped, and named in a warning when it is (see
  # `warn_unusable_extras/2`).
  @extras_keys [:structured_content, :is_error]

  # F-11: the unrecognised-key warning enumerates a consumer-supplied map, whose
  # key COUNT is unbounded while Logger truncates the message at ~8 KB — so a
  # handler that returns its state map in slot 3 (R-3's own premise) had the
  # join build a multi-kilobyte string that Logger provably discarded: 5000 keys
  # cost 7.567 ms/call against 0.053 ms for a correct extras map. The list is
  # capped and the elided count is stated in the same line, because a truncated
  # list that does not say it truncated is the silent-drop class wearing a hat
  # (MES-16 R-10's ruling, applied to a logger written this ticket).
  @unknown_keys_logged 10

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

        # SEP-2106: a map in slot 3 carries structuredContent (and optionally
        # isError). Slot 3 was `boolean()` and nothing else, so this shape is
        # additive — no existing handler return can match it.
        {:ok, content, extras, state} when is_map(extras) ->
          {complete(tool_extras(%{"content" => content}, content, extras, name)), state}

        {:ok, content, is_error, state} when is_boolean(is_error) ->
          {complete(maybe_error(%{"content" => content}, is_error)), state}

        # F-10: slot 3 that is neither a map nor the legacy boolean. The drop is
        # unchanged — `maybe_error/2` dropped it before this clause existed, and
        # still would — so this adds a warning and nothing else, closing the
        # fifth of S4's five plausible mistakes.
        {:ok, content, other, state} ->
          warn_unusable_extras(other, name)
          {complete(%{"content" => content}), state}

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

  # --- SEP-2106 structured tool output ---

  # `structuredContent` keys off PRESENCE, never truthiness: `false`, `0`, `""`,
  # `[]`, `%{}` and `null` are all legal values (schema.ts:1819-1821), so a
  # present key with value nil emits JSON null and an absent key omits the
  # field. That is the whole absent-vs-null distinction, with no sentinel.
  defp tool_extras(result, content, extras, name) do
    warn_unusable_extras(extras, name)
    result = maybe_error(result, Map.get(extras, :is_error))

    case Map.fetch(extras, :structured_content) do
      {:ok, value} ->
        warn_missing_text_fallback(value, content, name)
        Map.put(result, "structuredContent", value)

      :error ->
        result
    end
  end

  # The extras map is consumer-supplied, and every key this SDK does not
  # recognise is dropped. Dropping ALONE is the posture MES-16 ruled against on
  # `:extensions`: `%{structuredContent: v}` (camelCase), `%{"structured_content"
  # => v}` (string key), a struct in slot 3, and `%{is_error: "true"}` each
  # produced a successful, silently empty result — four plausible mistakes, no
  # error, no warning, and no dialyzer complaint (the type is all-`optional()`,
  # so a misspelled key is not a mismatch). This names what was dropped and why.
  #
  # It NEVER raises: a stray key must not fail a tool call that otherwise works.
  #
  # F-9: a struct IS a map, so `tool_extras/4` reads `:structured_content` and
  # `:is_error` off it with the same `Map.fetch/2` and `Map.get/2` it uses on a
  # plain map, and whatever it finds DOES reach the wire. The behaviour is the
  # right one; the old sentence ("structuredContent and isError are IGNORED")
  # was a universal claim over a conditional code path, false for exactly the
  # struct that carries those field names — and false in an operator's log at
  # the moment they are trying to work out where their output went. So the line
  # names what could not be used instead of asserting that everything was.
  defp warn_unusable_extras(extras, name) when is_struct(extras) do
    outcome =
      case Enum.filter(@extras_keys, &Map.has_key?(extras, &1)) do
        [] ->
          "it has none of #{inspect(@extras_keys)} as fields, so NO extras are read from it " <>
            "and every field is IGNORED"

        carried ->
          "its #{inspect(carried)} field(s) ARE read, exactly as a plain extras map's would " <>
            "be, and DO reach the wire; every OTHER field is IGNORED"
      end

    Logger.warning(
      "MCP Server: tool #{inspect(name)} returned a #{inspect(extras.__struct__)} struct in " <>
        "slot 3 where a `t:MCP.Server.Handler.call_tool_extras/0` map was expected — " <>
        outcome <> ". Nothing is raised."
    )
  end

  # F-10: slot 3 is dispatched on `is_map/1`, so anything that is neither a map
  # nor the legacy `boolean()` never reaches the extras path at all — it is
  # dropped by `maybe_error/2`, exactly as it was before this ticket. The drop
  # is inherited; the SILENCE is what S4 ruled against, and a keyword list is
  # both the most idiomatic Elixir spelling of an options map and newly
  # plausible precisely BECAUSE this ticket made slot 3 a map.
  defp warn_unusable_extras(extras, name) when not is_map(extras) do
    Logger.warning(
      "MCP Server: tool #{inspect(name)} returned " <>
        "#{inspect(extras, limit: 5, printable_limit: 120)} in slot 3, where a " <>
        "`t:MCP.Server.Handler.call_tool_extras/0` map (or the legacy `boolean()` isError) " <>
        "was expected — it is IGNORED in full: neither structuredContent nor isError " <>
        "reaches the wire. Nothing is raised."
    )
  end

  defp warn_unusable_extras(extras, name) do
    case extras_complaints(extras) do
      [] ->
        :ok

      complaints ->
        Logger.warning(
          "MCP Server: tool #{inspect(name)} returned an extras map this SDK cannot use — " <>
            Enum.join(complaints, "; ") <>
            ". The recognised keys are #{inspect(@extras_keys)} " <>
            "(`t:MCP.Server.Handler.call_tool_extras/0`). Nothing is raised."
        )
    end
  end

  defp extras_complaints(extras) do
    unknown = extras |> Map.keys() |> Enum.reject(&(&1 in @extras_keys)) |> Enum.sort()

    unknown_complaint =
      case unknown do
        [] ->
          []

        keys ->
          count = length(keys)
          elided = count - @unknown_keys_logged

          [
            "#{count} unrecognised key(s) IGNORED: " <>
              Enum.map_join(
                Enum.take(keys, @unknown_keys_logged),
                ", ",
                &inspect(&1, printable_limit: 120)
              ) <> if(elided > 0, do: ", and #{elided} more", else: "")
          ]
      end

    is_error_complaint =
      case Map.fetch(extras, :is_error) do
        {:ok, value} when not is_boolean(value) ->
          [
            "`:is_error` is not a boolean " <>
              "(#{inspect(value, limit: 5, printable_limit: 120)}) and is IGNORED"
          ]

        _ ->
          []
      end

    unknown_complaint ++ is_error_complaint
  end

  # SEP-2106 Backward Compatibility: "servers using array or primitive
  # structuredContent MUST also emit a TextContent block containing the
  # serialized JSON". We do not inject that block — the content list is
  # handler-authored, model-visible data (see MCP.Server.Handler) — but we
  # notice, and the check is the exact condition rather than a proxy for it:
  # each text block is JSON-decoded and compared to the structured value.
  defp warn_missing_text_fallback(value, content, name)
       when is_list(value) or not is_map(value) do
    unless Enum.any?(List.wrap(content), &serialized_json_of?(&1, value)) do
      Logger.warning(
        "MCP Server: tool #{inspect(name)} returned array/primitive structuredContent " <>
          "without a TextContent block carrying the serialized JSON. SEP-2106 Backward " <>
          "Compatibility makes that block a MUST for older clients; this SDK does not " <>
          "add it for you."
      )
    end
  end

  defp warn_missing_text_fallback(_value, _content, _name), do: :ok

  # R-8: `MCP.Server.Handler` promises this warning fires "never on a compliant
  # result", so the match must be as wide as "a block the peer receives as a
  # TextContent" — not as wide as one spelling of it. A
  # `%MCP.Protocol.Types.Content.TextContent{}` (public, `Jason.Encoder`-derived,
  # `type: "text"` by default) and an atom-keyed content map both encode to
  # exactly the right JSON, so both count; the second clause covers both,
  # because a struct matches a map pattern on its fields.
  defp serialized_json_of?(%{"type" => "text", "text" => text}, value),
    do: json_text_of?(text, value)

  defp serialized_json_of?(%{type: "text", text: text}, value),
    do: json_text_of?(text, value)

  defp serialized_json_of?(_block, _value), do: false

  defp json_text_of?(text, value) when is_binary(text),
    do: json_first_byte_can_match?(text, value) and match?({:ok, ^value}, Jason.decode(text))

  defp json_text_of?(_text, _value), do: false

  # A cheap gate in front of the decode: a JSON text can only decode to `value`
  # if its first significant byte is the one `value`'s JSON form must begin
  # with, so a large non-matching block is rejected on ONE byte rather than a
  # full parse. It can never reject a block that would have matched — the
  # mapping is the JSON grammar's own first-character rule, and RFC 8259
  # leading whitespace is skipped first.
  #
  # Measured on the dispatch path, 200 calls per case, gate off then on:
  #
  #     array[2] + a 20k-key JSON object text block   4.671 -> 0.001 ms/call
  #     array[20k] + its own serialized JSON          1.075 -> 1.109 ms/call
  #
  # **It does not help the compliant case, which is the one that matters most**
  # — a block that really is the serialized JSON passes the gate and is then
  # parsed in full, as it must be. No sound cheap check exists for that case:
  # confirming equality needs either this decode or an encode of the value
  # (same order of cost), and a byte comparison would be wrong, since JSON key
  # order inside an array element is not semantic. So a compliant server does
  # pay a re-parse of what it just serialized, per call, and that is stated
  # rather than papered over.
  defp json_first_byte_can_match?(text, value) do
    case json_first_bytes(value) do
      :any ->
        true

      allowed ->
        case skip_json_ws(text) do
          <<byte, _rest::binary>> -> byte in allowed
          <<>> -> false
        end
    end
  end

  defp json_first_bytes(value) when is_list(value), do: ~c"["
  defp json_first_bytes(value) when is_binary(value), do: ~c"\""
  defp json_first_bytes(nil), do: ~c"n"
  defp json_first_bytes(true), do: ~c"t"
  defp json_first_bytes(false), do: ~c"f"
  defp json_first_bytes(value) when is_number(value), do: ~c"-0123456789"
  defp json_first_bytes(value) when is_map(value), do: ~c"{"
  # Anything else (a bare atom, a tuple) has no first byte we can predict
  # without encoding it, so the gate stands aside rather than guess.
  defp json_first_bytes(_value), do: :any

  defp skip_json_ws(<<c, rest::binary>>) when c in ~c" \t\n\r", do: skip_json_ws(rest)
  defp skip_json_ws(text), do: text

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
