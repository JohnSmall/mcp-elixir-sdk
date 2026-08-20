defmodule MCP.Transport.StreamableHTTP.Plug do
  @moduledoc """
  Stateless Plug endpoint for the MCP Streamable HTTP transport (2026-07-28).

  A thin **per-request driver** for `MCP.Server.Dispatch`: there is no
  `initialize` handshake, no `Mcp-Session-Id`, and no session affinity — any
  request is serviceable by any instance behind a round-robin balancer
  (SEP-2575 / SEP-2567). The dispatch `config` is built once at `init/1`; every
  request builds its own `MCP.Server.ToolContext` and calls `Dispatch`.

  Handles `POST` only. `GET` is `405 Method Not Allowed`, which is also what the
  spec SHOULDs for a server that offers no standing stream
  (streamable-http.mdx:683-684).

  The response to a POST is `application/json` when `:enable_json_response` is
  set and `text/event-stream` otherwise — chosen from **static configuration,
  not from the request's `Accept`**. Stated plainly because it is a real
  limitation rather than a detail: a client that accepts only
  `application/json` against an SSE-mode server gets SSE anyway.

  Server→client messages flow only while a client request is being processed
  (SEP-2260). A long-lived `subscriptions/listen` stream is not an exception to
  that — it *is* one client request, held open, carrying notifications only.

  > #### No backward compatibility {: .warning}
  >
  > The spec's Backward Compatibility section (streamable-http.mdx:680-687)
  > describes accommodations for pre-2026-07-28 clients. **None are
  > implemented** (PO ruling). There is no `Mcp-Session-Id` handling, no
  > `Last-Event-ID` resumption, and no GET endpoint.

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
      request/response (default: false). Also **disables** `subscriptions/listen`
      — see below.
    * `:protocol_version` — advertised version (default: the stateless core's).
    * `:max_stream_lifetime` — how long a `subscriptions/listen` stream may stay
      open, in milliseconds (default: one hour). At expiry the server closes
      gracefully and the client re-listens.
    * `:keepalive_interval` — how often an idle subscription stream emits an SSE
      comment-line keep-alive, in milliseconds (default: 15 s).

  ## Subscription streams (`subscriptions/listen`)

  A `subscriptions/listen` POST is answered with an SSE stream held open, which
  carries the change notifications the client opted in to. Three consequences
  worth knowing before you deploy it:

  ### It is a per-node stream, and that is a deliberate boundary

  Notifications reach a client only when the handler emits them **on the node
  holding that client's stream**. A resource that changes on instance B does
  *not* appear on a stream held by instance A. The SDK provides no fan-out seam
  and takes no broadcast dependency; distributing change events across
  instances is the consumer's job, and this SDK will not pretend otherwise by
  offering an API that half-does it.

  This is a considered deferral rather than an oversight or a temporary gap.
  The 2026-07-28 core is specifically stateless — every *request* is
  serviceable by any instance behind a round-robin balancer — and a
  long-lived stream is the one thing in it that is genuinely pinned to a node.
  It is acknowledged that this forgoes something Elixir would serve better than
  most runtimes. The boundary is pinned by an executable test, not only by this
  paragraph.

  ### Identity is resolved once, at stream open

  Every other request in this transport resolves identity freshly from its own
  `conn`. A subscription stream is **one** request that happens to last a long
  time, so the identity it resolved at open is the identity it keeps: a
  credential that expires ten minutes into a stream stays bound until the
  stream ends.

  What that does and does not expose. A stream carries only notifications, and
  a `notifications/resources/updated` carries a URI and nothing else — so a
  principal whose access is revoked mid-stream keeps learning **that** a
  subscribed URI changed, and never **what** it now says. Reading it still
  costs a fresh `resources/read` under a freshly resolved identity. Two things
  bound it: `:max_stream_lifetime` caps how long it can last, and
  `handle_listen/3` decides at open which URIs this principal may observe at
  all. Lower `:max_stream_lifetime` if your credentials are short-lived and
  even that leak matters to you.

  ### A vanished client is detected by the next write

  The keep-alive doubles as a liveness probe: the first chunk written after the
  peer closes fails, and the stream is torn down without sending anything
  further. Detection therefore costs at most one `:keepalive_interval` plus a
  round trip. One case escapes it — a client that TCP half-closes (sends FIN
  but never fully closes) is indistinguishable from a healthy quiet client,
  because writing to a half-closed socket legitimately keeps succeeding. That
  stream is reclaimed by `:max_stream_lifetime`, which is the other reason its
  default is finite.

  ### JSON mode refuses it outright

  With `enable_json_response: true` there is no way to hold a stream open, and
  the listen response *is* an SSE stream — so the method returns `-32601`
  rather than opening something that silently delivers nothing. Such a
  deployment also advertises no subscription capability, so a conforming client
  never calls it.

  ## Security

  Identity must be established server-side by the authenticated Plug pipeline
  (e.g. an upstream auth Plug setting `conn.assigns`) and resolved by the
  factory — never supplied by the model via tool-call arguments. The handler
  stays transport-agnostic: it reads `ctx.identity`; the `conn` is never leaked
  into a handler callback. A factory that raises or returns a non-keyword
  yields a clean `-32603` (HTTP 500) with no handler invoked; the detail is
  logged server-side and never returned to the client.

  ### Cache-scope footgun warning

  When `handler_opts` resolves a per-caller identity **and** `:cache_defaults`
  would stamp `ttlMs > 0` with `cacheScope: "public"` onto the cacheable
  list/read results, `init/1` logs a one-time warning: identity-dependent data
  authorised for a shared cache can be served across principals. Set a
  `"private"` scope (or keep `ttlMs` at 0) for identity-dependent results.

  The warning is emitted from `init/1`, so it fires **once per configuration,
  never per request**. Note the surfacing depends on when your deployment runs
  `init/1`: `Bandit`/`Plug.Cowboy` started with `plug: {#{inspect(__MODULE__)},
  opts}` call it at **server startup** (the warning reaches the runtime log —
  this SDK's documented shape). A module-based pipeline that mounts this plug
  with `plug_init_mode: :compile` (a Phoenix production default) runs `init/1`
  at **compile time**, so the warning would appear in the build log instead;
  set `plug_init_mode: :runtime`, or prefer the Bandit `plug: {Module, opts}`
  form, if you mount it that way.
  """

  @behaviour Plug

  require Logger

  alias MCP.Protocol
  alias MCP.Protocol.Error
  alias MCP.Protocol.Messages.Request
  alias MCP.Protocol.Methods
  alias MCP.Server.{Config, Dispatch, NotificationCollector, Subscription, ToolContext}
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
    :config,
    :collector_start,
    :stream_start,
    :max_stream_lifetime,
    :keepalive_interval
  ]

  # A subscription stream lives at most an hour unless the deployment says
  # otherwise. Finite is the safe default and infinite is not: identity is
  # resolved once, at stream open, so an unbounded stream is an unbounded
  # freeze of a credential's authority (see the moduledoc). It also bounds the
  # one case peer-close detection cannot see — a client that half-closes and
  # walks away is invisible to us indefinitely, because TCP half-close is a
  # legitimate "I have finished sending" and writes to it keep succeeding.
  # Expiry is a graceful close the spec explicitly contemplates, not a
  # workaround: the client re-listens (subscriptions.mdx:155-161).
  @default_max_stream_lifetime :timer.hours(1)

  # The keep-alive comment frame doubles as the liveness probe: measured, the
  # first chunk/2 after a peer close returns {:error, :closed}, so orphan
  # detection costs one write and is bounded by this interval plus a round
  # trip rather than being unbounded. 15s sits under the common 30-60s proxy
  # idle timeout the keep-alive exists to defeat.
  @default_keepalive_interval :timer.seconds(15)

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

    # Injectable per-request collector start (MES-14 MC-6). Defaults to the real
    # collector; a 0-arity fun returning `{:ok, pid} | {:error, reason}`. The
    # seam exists so the MC-6 clean-failure path (a collector that fails to
    # start) is exercised by a permanent test rather than a manual injection.
    collector_start = Keyword.get(opts, :collector_start, &NotificationCollector.start_link/0)

    # Injectable stream start, for the same reason MES-14 made the collector
    # start injectable (MC-6): the clean-failure path is only a guarantee if a
    # permanent test exercises it, and a chunked-response start cannot be made
    # to fail from outside. A 1-arity fun `(conn -> {:ok, conn} | {:error, term})`.
    stream_start = Keyword.get(opts, :stream_start, &start_chunked/1)

    max_stream_lifetime = Keyword.get(opts, :max_stream_lifetime, @default_max_stream_lifetime)
    keepalive_interval = Keyword.get(opts, :keepalive_interval, @default_keepalive_interval)

    # AC7 (MES-14): config-time cache-scope footgun warning. init/1 runs once
    # per plug configuration (call/2 has no path here), so this emits at most
    # once regardless of request volume.
    warn_if_public_cache_of_identity_scoped(handler_opts, server_opts)

    # Build the immutable dispatch config once. Only the non-identity static
    # base reaches Handler.init/1; per-request identity rides ToolContext.
    static_base = if is_function(handler_opts), do: [], else: handler_opts

    # The driver's own streaming ability, declared to the config rather than
    # inferred by it: SSE mode can hold a response stream open, JSON mode
    # cannot. This gates capability advertisement (C3 — a `listChanged` claim
    # needs a channel to honour it on) and, from MES-15, whether dispatch may
    # hand this driver a streaming result at all.
    config_opts =
      [handler_opts: static_base, streaming: not enable_json_response] ++
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
      config: dispatch_config,
      collector_start: collector_start,
      stream_start: stream_start,
      max_stream_lifetime: max_stream_lifetime,
      keepalive_interval: keepalive_interval
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
      _ -> method_not_allowed(conn)
    end
  end

  # --- POST: the request/response path ---

  defp handle_post(conn, config) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn),
         {:ok, message} <- Jason.decode(body),
         :ok <- check_routing_headers(conn, message),
         {:ok, identity} <- resolve_identity(config.handler_opts, conn),
         {:ok, decoded} <- Protocol.decode_message(message),
         {:ok, collector} <- start_collector(config.collector_start) do
      dispatch(conn, config, decoded, message, identity, collector)
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

      # MC-6 (clean failure): a collector that fails to start yields a
      # controlled internal error before any handler runs — the detail is
      # logged server-side and never returned to the client. This is the path
      # the /plan MC-6 row promised; it was previously an unguarded match
      # (MatchError). Placed after identity resolution, before dispatch.
      {:error, {:collector_start_failed, reason}} ->
        Logger.error("MCP Plug: notification collector failed to start: #{inspect(reason)}")

        send_json_error(
          conn,
          500,
          Error.internal_error_code(),
          "Internal error",
          "notification collector unavailable"
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

  # Starts the per-request notification collector, mapping a start failure to a
  # controlled `{:error, {:collector_start_failed, reason}}` for the with-chain
  # (MC-6) rather than crashing on an unguarded match.
  defp start_collector(start_fun) do
    case start_fun.() do
      {:ok, _collector} = ok -> ok
      {:error, reason} -> {:error, {:collector_start_failed, reason}}
    end
  end

  defp dispatch(conn, config, decoded, raw_message, identity, collector) do
    # The notification collector is a per-request process (MES-14): its pid is
    # held only by this request's reply_sink closure on `ctx`. No later request
    # can name it, so a prior request's notifications are unaddressable — not
    # merely cleared (AC2, reachability-bounded). This replaces the Sprint 3
    # process-dictionary collector whose process-keyed slot leaked across
    # same-process requests (evidence-log I10). `start_link` (in the with-chain)
    # links the collector to this request process, so it dies with a crashing
    # request; `stop/1` in the `after` is prompt cleanup, not the safety
    # guarantee.
    stream = new_stream_handle()

    ctx = %ToolContext{
      request_id: Map.get(raw_message, "id"),
      meta: get_in(raw_message, ["params", "_meta"]),
      identity: identity,
      reply_sink: fn method, params -> NotificationCollector.push(collector, method, params) end,
      stream_sink: stream_sink(stream)
    }

    # The listen lifecycle is bracketed ONCE, here, around everything the
    # request does — `Dispatch.dispatch/3` included, because that call is where
    # `handle_listen/3` runs and where the handler is handed a live sink.
    #
    # Correction round 2 (review R1): teardown used to be established per
    # branch, and the branch is chosen from a value `Dispatch.dispatch/3` has
    # to return in order to exist. So the two exits that raise *before* there
    # is a value — a `handle_listen/3` that raises after capturing the sink,
    # and a `:stream_start` that raises rather than returning `{:error, _}` —
    # ran neither call and one of the two calls respectively. Counting more
    # branches was round 1's fix and was the wrong shape; the bracket is the
    # fix, because it is established before the first thing that can fail.
    #
    # Correction round 3 (review R4): what the bracket is armed FROM is
    # `decoded`, not the raw map — see `listen_request?/1`.
    if listen_request?(decoded), do: arm_listen_teardown(stream)

    try do
      # The collector is drained and stopped BEFORE any stream runs: a
      # subscription can be open for an hour, and keeping a per-request process
      # alive for it would be a leak measured in hours. Dispatch runs inside the
      # `try` so a raising handler still reclaims it.
      {result, notifications} =
        try do
          {Dispatch.dispatch(decoded, ctx, config.config), NotificationCollector.drain(collector)}
        after
          NotificationCollector.stop(collector)
        end

      case result do
        {:reply, response, _state} ->
          # A listen answered from ABOVE the handler call is owed nothing, and
          # this is the only place that can be known: `MCP.Server.Dispatch`
          # returns `{:reply, ...}` for `subscriptions/listen` only from the
          # paths that never reach `handle_listen/3` — JSON mode's -32601, a
          # malformed or absent filter's -32602, a handler that exports no
          # `handle_listen/3`. Telling a handler its subscription closed when it
          # never opened is the same false claim pointed the other way.
          disarm_listen_teardown(stream)
          send_response(conn, config, response, notifications)

        {:noreply, _state} ->
          # Defence in depth since round 3, not a live path: `{:noreply, _}` is
          # returned only for a `%Notification{}`, and a notification no longer
          # arms the obligation at all (`listen_request?/1` matches `%Request{}`
          # only). A listen sent as a notification therefore reaches here
          # already disarmed — correctly, since it never reaches
          # `handle_listen/3`. The clear stays because the cost is one atomic
          # write and the alternative is a clause that silently depends on the
          # predicate's shape.
          disarm_listen_teardown(stream)
          Plug.Conn.send_resp(conn, 202, "")

        # LISTEN EXIT 1 — refused by the handler. `handle_listen/3` ran and was
        # handed a live `ctx.stream_sink`, so this is a teardown like any other:
        # the subscription the handler may have registered is dead and it has to
        # be told. Reachable only when `config.streaming` is true, exactly like
        # `{:stream, ...}` (MCP.Server.Dispatch's contract).
        #
        # Correction round 2 (review R3): the refusal response is written
        # BEFORE the handler is told. `release_stream/1` first so nothing the
        # callback does can produce a frame, then the response, then the
        # notification — so a `handle_listen_closed/3` that faults for its own
        # reasons cannot replace a clean -32xxx with a bare 500 and an empty
        # body. `notify_listen_closed/4` also catches exits now; that guard is
        # the property and this ordering is defence in depth behind it.
        {:listen_refused, response, state} ->
          release_stream(stream)
          conn = send_response(conn, config, response, notifications)
          teardown(config, ctx, state, stream)
          conn

        {:stream, subscription, state} ->
          open_stream(conn, config, subscription, ctx, state, stream, notifications)
      end
    after
      # The stream handle is released on the way out of EVERY request, not only
      # the ones that opened a stream: a sink that has outlived its request must
      # not answer `:ok`. `teardown/4` releases too, and is idempotent, so a
      # listen that already tore down explicitly pays only the release here.
      #
      # `config.config.handler_state` rather than a handler state returned by
      # dispatch, because on the paths this `after` exists for there is no
      # return value to have carried one. The state a handler is told with on a
      # crash is therefore its pre-request state; the paths that CAN do better
      # (the explicit teardowns) still do.
      if listen_teardown_owed?(stream) do
        teardown(config, ctx, config.config.handler_state, stream)
      else
        release_stream(stream)
      end
    end
  end

  # The driver's own read of the method, taken from the DECODED message rather
  # than from the dispatch result: the obligation has to be armed before the
  # call that would tell us, which is the whole point of R1's fix. `decoded` is
  # produced by the `with`-chain in `handle_post/2`, strictly before
  # `dispatch/6` is entered, so arming off it gives up none of that ordering.
  #
  # Correction round 3 (review R4): this used to read `Map.get(raw, "method")`,
  # and a string in the raw map is not what makes a message a listen request.
  # `Protocol.decode_message/1` classifies by SHAPE, and its `cond` tests
  # Response (`id` + `result`/`error`) BEFORE Request (`id` + `method`) — so a
  # message carrying `id` + `result` + `method` decodes as a `%Response{}`,
  # which `MCP.Server.Dispatch` has no clause for. Under the old predicate that
  # message armed the obligation, raised above every routing decision, and paid
  # the bracket's teardown with a subscription id the CLIENT chose: a second
  # client could name a first client's live subscription and have the handler
  # told it had closed while its stream was still running. Matching the struct
  # makes the driver's answer to "is this a listen?" the same one Dispatch will
  # act on — nothing arms an obligation that routing will not honour.
  defp listen_request?(%Request{method: method}),
    do: method == Methods.subscriptions_listen()

  defp listen_request?(_decoded), do: false

  # --- subscriptions/listen: the long-lived response stream ---
  #
  # A listen request can end in SEVEN named ways, and every one of them runs
  # `teardown/4` — release the sink, then tell the handler exactly once.
  # **Count these against the code; the number is here to be checked, not
  # trusted.** It has been wrong twice: round 1 said four and shipped five,
  # round 2 found seven.
  #
  #   1. the handler refuses it            — `{:listen_refused, ...}`, dispatch/6
  #   2. `handle_listen/3` raises          — dispatch/6's outer `after`
  #   3. the stream cannot be started      — open_stream/7, `{:error, exception}`
  #   4. starting the stream raises        — dispatch/6's outer `after`
  #   5. the lifetime expires              — close_stream/7, `:lifetime_expired`
  #   6. the peer goes away                — close_stream/7, `:peer_closed`
  #      (from the ack write or any later one)
  #   7. anything in the loop raises       — open_stream/7's `after`
  #
  # 5 and 6 are one code path that differs only in what goes on the wire
  # (`Subscription.close_frame/2`); they are counted separately because what
  # matters here is the ways OUT, not the close reasons. There is no eighth for
  # a server-initiated `:shutdown`: this driver cannot yet initiate one, and
  # `close_frame/2` carries the case for the transport that will.
  #
  # **The list is documentation; the guarantee is the shape.** Teardown is
  # established ONCE, in dispatch/6, around the whole lifecycle including the
  # dispatch call — so 2, 4 and any eighth nobody has thought of are covered by
  # construction rather than by having been listed. 3, 5, 6 and 7 tear down
  # explicitly as well, which buys nothing for reachability and buys the
  # handler a more accurate `state` (see the `after` in dispatch/6).
  #
  # **What that bracket does NOT cover, stated because a bound nobody states is
  # a bound nobody can check:** an `after` runs when the process unwinds — a
  # `raise`, a `throw`, or an `exit/1` the process calls itself. It does NOT
  # run when the process is terminated by a signal from outside
  # (`Process.exit(pid, :kill)`, or a supervisor shutting the Bandit connection
  # down). Measured, not assumed: killing the connection process holding a live
  # stream runs no teardown and leaves the sink answering `:ok`. Closing that
  # gap needs a monitoring process, which is construction this driver does not
  # have; the honest statement is that abrupt process death by signal is the
  # one termination mode with no cleanup, and `:max_stream_lifetime` does not
  # help because the reaper dies with it.
  #
  # Correction round 1 (review F1/F2): 1 and 7 previously ran neither call, so
  # a refused or crashed listen left the handler believing its subscription was
  # open and left `ToolContext.stream/3` answering `:ok` for a stream that
  # would never exist. Correction round 2 (review R1): 2 and 4 were still
  # uncovered and unlisted, because teardown was reachable from branches rather
  # than established around the lifecycle.

  # A handle the sink and the stream owner share. The flag is an `:atomics`
  # rather than a liveness check on the owner pid, because on HTTP/1 keep-alive
  # the owner IS the Bandit connection process and outlives the stream by
  # design — `Process.alive?` would report a dead stream as live for as long as
  # the connection is reused.
  # Slot 1 is the open/closed flag the sink reads. Slot 2 is the teardown
  # claim: it makes "the handler is told exactly once" survive a path that
  # tears down explicitly and is then unwound through the bracketing `after`,
  # without either site having to know about the other. Slot 3 is the
  # notification obligation — armed for a `subscriptions/listen` request before
  # anything can fail, cleared only where it is provable that `handle_listen/3`
  # never ran.
  defp new_stream_handle do
    flag = :atomics.new(3, signed: false)
    :atomics.put(flag, 1, 1)
    %{owner: self(), ref: make_ref(), flag: flag}
  end

  # Armed BEFORE dispatch and cleared only by a return value that proves the
  # handler never ran, so a raise leaves it armed. That is deliberately
  # conservative: on a raise the driver cannot see how far into
  # `MCP.Server.Dispatch` the request got, so it errs toward telling the
  # handler. Over-telling costs a `handle_listen_closed/3` for an id the
  # handler never registered — inspectable, and the handler holds the id;
  # under-telling is a leak nothing else reaps. The PM's round-2 ruling names
  # the same tie-break: a raise inside `handle_listen/3` is "it ran".
  defp arm_listen_teardown(%{flag: flag}), do: :atomics.put(flag, 3, 1)

  defp disarm_listen_teardown(%{flag: flag}), do: :atomics.put(flag, 3, 0)

  defp listen_teardown_owed?(%{flag: flag}), do: :atomics.get(flag, 3) == 1

  # Callable from ANY process and at any later time — a handler stores it during
  # handle_listen/3 and emits from wherever its change events actually arrive.
  # It only ever posts a message: the honoured-filter check and the
  # subscriptionId stamp happen in the stream owner, at the single point where
  # a message becomes a frame, so there is one enforcement site per transport
  # rather than one per emitter.
  defp stream_sink(%{owner: owner, ref: ref, flag: flag}) do
    fn method, params ->
      if :atomics.get(flag, 1) == 1 do
        send(owner, {:mcp_stream, ref, method, params})
        :ok
      else
        {:error, :closed}
      end
    end
  end

  defp open_stream(conn, config, subscription, ctx, state, stream, dropped) do
    warn_dropped_request_scoped(dropped, subscription)

    # MC-6 (clean failure): starting the stream is the one new failure point
    # this path adds. If the response cannot be started, nothing has been
    # written yet, so a controlled -32603 is still possible — after the first
    # chunk it would not be.
    case config.stream_start.(conn) do
      {:ok, conn} ->
        # LISTEN EXITS 5, 6 and 7. Since round 2 this `after` is no longer the
        # only thing standing on exit 7 — dispatch/6's bracket is below it and
        # would catch the same unwind. It stays because it is the innermost
        # place that still has the handler `state` returned by
        # `handle_listen/3`; the bracket can only offer the pre-request state.
        try do
          {conn, reason} = write_ack_then_loop(conn, config, subscription, stream)
          close_stream(conn, config, subscription, ctx, state, stream, reason)
        after
          teardown(config, ctx, state, stream)
        end

      {:error, exception} ->
        # LISTEN EXIT 3 — the stream could not be started. The handler already
        # ran handle_listen/3 and is holding a sink for a stream that will
        # never exist. Telling it so is the same obligation as on any other
        # teardown — a subscription the handler believes is open and the SDK
        # knows is dead is precisely the leak handle_listen_closed/3 exists to
        # prevent. Response before notification, for R3's reason on exit 1.
        Logger.error("MCP Plug: could not start the subscription stream: #{inspect(exception)}")
        release_stream(stream)

        conn =
          send_json_error(
            conn,
            500,
            Error.internal_error_code(),
            "Internal error",
            "subscription stream unavailable"
          )

        teardown(config, ctx, state, stream)
        conn
    end
  end

  @doc false
  # Public only so the default can be captured as `&start_chunked/1` in init/1.
  def start_chunked(conn) do
    conn =
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      # SHOULD, streamable-http.mdx:136-142 — tells nginx and friends not to
      # buffer the response, without which SSE frames arrive in clumps or not
      # at all. There is no Last-Event-ID counterpart: resumption is explicitly
      # not supported in this revision (:157).
      |> Plug.Conn.put_resp_header("x-accel-buffering", "no")
      |> Plug.Conn.send_chunked(200)

    {:ok, conn}
  rescue
    exception -> {:error, exception}
  end

  defp write_ack_then_loop(conn, config, subscription, stream) do
    # Ack-first is true by construction rather than by discipline: anything the
    # handler emitted during handle_listen/3 is sitting in this process's
    # mailbox, and the mailbox is not read until after this write. Nothing
    # bearing this subscription's id can precede its own acknowledgment
    # (schema.ts:1386-1392).
    case Plug.Conn.chunk(conn, SSE.encode_message(subscription.ack)) do
      {:ok, conn} ->
        deadline = System.monotonic_time(:millisecond) + config.max_stream_lifetime
        stream_loop(conn, config, subscription, stream, deadline)

      {:error, _reason} ->
        {conn, :peer_closed}
    end
  end

  defp stream_loop(conn, config, subscription, stream, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {conn, :lifetime_expired}
    else
      wait = min(config.keepalive_interval, remaining)
      wait_for_frame(conn, config, subscription, stream, deadline, wait)
    end
  end

  defp wait_for_frame(conn, config, subscription, %{ref: ref} = stream, deadline, wait) do
    receive do
      {:mcp_stream, ^ref, method, params} ->
        case Subscription.frame(subscription, method, params) do
          {:ok, wire} ->
            write_frame(conn, config, subscription, stream, deadline, SSE.encode_message(wire))

          :drop ->
            stream_loop(conn, config, subscription, stream, deadline)
        end
    after
      wait ->
        # The keep-alive write IS the liveness probe: a peer that has closed
        # fails this chunk, which is what bounds orphan detection to one
        # interval plus a round trip instead of leaving it unbounded.
        write_frame(conn, config, subscription, stream, deadline, SSE.comment())
    end
  end

  defp write_frame(conn, config, subscription, stream, deadline, iodata) do
    case Plug.Conn.chunk(conn, iodata) do
      {:ok, conn} -> stream_loop(conn, config, subscription, stream, deadline)
      {:error, _reason} -> {conn, :peer_closed}
    end
  end

  # LISTEN EXITS 5 and 6. Order matters: stop accepting emissions BEFORE
  # anything else, so nothing a teardown callback does can produce a frame for
  # a stream that is over — which is why this releases first and calls
  # `teardown/4` (a second, idempotent release) only after the close frame.
  defp close_stream(conn, config, subscription, ctx, state, stream, reason) do
    release_stream(stream)
    conn = maybe_send_close_response(conn, subscription, reason)
    teardown(config, ctx, state, stream)
    conn
  end

  # The one teardown for a `subscriptions/listen` request, reached from all
  # seven exits. Safe to call more than once, which is what lets every exit call
  # it without knowing whether another already has: `release_stream/1` is
  # idempotent, and the handler notification is claimed exactly once through
  # the handle's second atomics slot.
  #
  # The subscription id is `ctx.request_id` rather than `subscription.id`: they
  # are the same value (`Subscription.new/2` is given the request id), and on
  # the refusal exit there is no subscription struct to read it from.
  defp teardown(config, %ToolContext{request_id: id} = ctx, state, stream) do
    release_stream(stream)

    if claim_teardown(stream) do
      notify_listen_closed(config, id, ctx, state)
    end

    :ok
  end

  # `compare_exchange` returns `:ok` for the caller that moves the slot 0 -> 1
  # and the current value for every later one, so the claim is exactly one
  # regardless of how many exits run or from which process.
  defp claim_teardown(%{flag: flag}), do: :atomics.compare_exchange(flag, 2, 0, 1) == :ok

  # The graceful-versus-abrupt decision is Subscription.close_frame/2's, not
  # this driver's — it is protocol, it is identical on every transport, and
  # keeping it there is what makes it testable at all (end to end it is not:
  # with the peer gone, "sent nothing" and "tried and failed" are
  # indistinguishable from outside).
  defp maybe_send_close_response(conn, subscription, reason) do
    case Subscription.close_frame(subscription, reason) do
      :none ->
        conn

      {:send, response} ->
        case Plug.Conn.chunk(conn, SSE.encode_message(response)) do
          {:ok, conn} -> conn
          {:error, _reason} -> conn
        end
    end
  end

  defp notify_listen_closed(config, subscription_id, ctx, state) do
    mod = config.config.handler_module

    if function_exported?(mod, :handle_listen_closed, 3) do
      # BOTH sinks are nil, because by this point neither has a channel behind
      # it: the stream is over, and the request-scoped collector was drained
      # and stopped before the stream ever opened. A context whose sinks are
      # nil says that structurally, and `ToolContext` answers accordingly
      # (`{:error, :no_stream}` / a dropped notification).
      #
      # `:reply_sink` was NOT nil here until correction round 1, and the
      # comment that stood in its place claimed a handler emitting from this
      # callback "is dropped" — which was true of the stream sink and false of
      # the reply sink: pushing to a stopped collector is an `Agent.update`
      # against a dead pid, so it EXITED, and this function only rescues. On
      # the refusal exit K1 added, that exit would land before the refusal
      # response is written, turning a clean -32xxx into a dropped connection.
      # Reported to the PM rather than absorbed silently (K7's "report it").
      mod.handle_listen_closed(subscription_id, %{ctx | stream_sink: nil, reply_sink: nil}, state)
    end

    :ok
  rescue
    exception ->
      Logger.error("MCP Plug: handle_listen_closed/3 raised: #{inspect(exception)}")
      :ok
  catch
    # Correction round 2 (review R3): `rescue` alone let a handler-side EXIT
    # through — a `GenServer.call` to its own dead process, say — and on the
    # refusal exit that replaced a clean -32xxx response with a bare 500 and an
    # empty body. A fault in the handler's teardown callback must not change
    # what the client receives for that request; the callback is being told
    # about a stream that is already over, so there is nothing left for it to
    # break.
    kind, value ->
      Logger.error("MCP Plug: handle_listen_closed/3 #{kind}: #{inspect(value)}")
      :ok
  end

  # Flips the sink off and drains any frame that was already in flight when it
  # flipped. The drain is not hygiene: on HTTP/1 keep-alive this process serves
  # later requests, so an unread {:mcp_stream, ...} would sit in its mailbox for
  # the life of the connection.
  defp release_stream(%{flag: flag, ref: ref}) do
    :atomics.put(flag, 1, 0)
    flush_stream_messages(ref)
  end

  defp flush_stream_messages(ref) do
    receive do
      {:mcp_stream, ^ref, _method, _params} -> flush_stream_messages(ref)
    after
      0 -> :ok
    end
  end

  defp warn_dropped_request_scoped([], _subscription), do: :ok

  defp warn_dropped_request_scoped(dropped, subscription) do
    # Emitted through ctx.reply_sink from inside handle_listen/3. Request-scoped
    # notifications MUST NOT ride a listen stream (streamable-http.mdx:130-134),
    # and there is no response stream on this path to carry them either, so they
    # are discarded. Loudly: a silently swallowed notification looks to the
    # handler author exactly like one that was delivered.
    #
    # This is reached only from `open_stream/7` — i.e. only when a stream
    # actually opened — and that asymmetry is deliberate rather than an
    # oversight (recorded at review round 2, L4). On a REFUSED listen the same
    # notifications ride the refusal response, because no stream opened and the
    # response stream is exactly where request-scoped notifications belong. The
    # rule is "not on a listen stream", not "not on this request".
    Logger.warning(
      "MCP Plug: discarded #{length(dropped)} request-scoped notification(s) emitted via " <>
        "ctx.reply_sink during handle_listen/3 for subscription " <>
        "#{inspect(subscription.id)}. Request-scoped notifications must not be delivered " <>
        "on a subscriptions/listen stream; use ctx.stream_sink for stream notifications."
    )
  end

  # --- Routing headers (SEP-2243) ---

  # `Mcp-Method` must match the body method; `Mcp-Name` (when present) must
  # match the request's **method-appropriate** target (SEP-2243, §"Mcp-Name":
  # `params.name` for `tools/call`/`prompts/get`, `params.uri` for
  # `resources/read`). Enables gateways to route without inspecting the body.
  # `Mcp-Name` is compared AFTER Base64-sentinel decoding. Servers "MUST decode
  # an encoded `Mcp-Name` or `Mcp-Param-{Name}` value before comparing it to
  # the corresponding request body value" (`streamable-http.mdx:501-504`), and
  # a client "MUST" encode a name that is not header-safe (`:486-492`) — tool
  # and prompt names are only SHOULD-constrained to header-safe characters, so
  # a non-ASCII name is legitimate.
  #
  # This was unreachable until MES-18: our client sent no `Mcp-Name` at all, so
  # nothing ever arrived encoded. The moment CG1 landed it became a
  # deterministic self-rejection — our own conformant client refused by our own
  # server with -32020 on any non-header-safe tool name — which is why the fix
  # rides the ticket that made it reachable rather than MES-35, which owns the
  # `Mcp-Param-*` half. The distinction is not the ticket boundary but the
  # breakage: this server never compares `Mcp-Param-*` at all, so no
  # self-incompatibility exists there to fix.
  defp check_routing_headers(conn, message) do
    method = Map.get(message, "method")
    header_method = first_header(conn, "mcp-method")
    header_name = decode_header_name(first_header(conn, "mcp-name"))
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

  defp decode_header_name(nil), do: nil
  defp decode_header_name(value), do: MCP.Protocol.HeaderMirror.decode_value(value)

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

  # --- AC7: config-time cache-scope footgun warning (once, never per request) ---

  # Fires only when the handler resolves a per-caller identity AND the effective
  # :cache_defaults would stamp ttlMs > 0 with cacheScope "public" onto the
  # cacheable list/read results — i.e. identity-dependent data authorised for a
  # shared cache. Safe configurations (no identity resolution; private scope;
  # or ttlMs 0, the default) emit nothing.
  defp warn_if_public_cache_of_identity_scoped(handler_opts, server_opts) do
    {ttl_ms, cache_scope} = Keyword.get(server_opts, :cache_defaults, {0, "public"})

    if identity_scoped?(handler_opts) and ttl_ms > 0 and cache_scope == "public" do
      Logger.warning(
        "MCP.Transport.StreamableHTTP.Plug: identity-dependent responses may be cached " <>
          "publicly — handler_opts resolves a per-caller identity while :cache_defaults is " <>
          "{#{ttl_ms}, \"public\"} (ttlMs > 0, public scope). Cacheable list/read results " <>
          "carrying caller-specific data can then be served from a shared cache across " <>
          "principals. Set cache_defaults to a \"private\" scope (e.g. {#{ttl_ms}, \"private\"}) " <>
          "— or keep ttlMs at 0 — for identity-dependent results. See MCP.Server.Config.build/2."
      )
    end

    :ok
  end

  # "Configured to resolve identity" = a per-request factory, or a static
  # keyword carrying a non-nil :identity.
  defp identity_scoped?(handler_opts) when is_function(handler_opts, 1), do: true

  defp identity_scoped?(handler_opts) when is_list(handler_opts),
    do: not is_nil(Keyword.get(handler_opts, :identity))

  defp identity_scoped?(_), do: false

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

  # `POST` alone: GET is refused now that no standing stream exists, so
  # advertising it in `allow` would name a method this endpoint will reject.
  defp method_not_allowed(conn) do
    conn
    |> Plug.Conn.put_resp_header("allow", "POST")
    |> Plug.Conn.send_resp(405, "")
  end

  # --- Header / origin helpers ---

  defp first_header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
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
