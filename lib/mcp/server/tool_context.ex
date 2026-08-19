defmodule MCP.Server.ToolContext do
  @moduledoc """
  Per-request context passed to identity-capable handler callbacks.

  In the 2026-07-28 stateless core this struct is **the per-request handler
  context**: it is constructed once per request by the transport driver
  (`MCP.Transport.StreamableHTTP.Plug` for HTTP, `MCP.Server.Connection` for
  stdio / in-process) and handed to every identity-capable callback via
  `MCP.Server.Dispatch`. There is no session and no per-session GenServer.

  ## The `:identity` field (security-critical)

  `:identity` holds the caller principal established by the **authenticated
  transport pipeline** — for HTTP, resolved per request from `conn`; for
  stdio/in-process, resolved once at launch (PO Comment B). It is populated by
  the transport driver **before** the handler runs and is **never** derived
  from the JSON-RPC `params`/`arguments`. Handlers MUST read the caller
  identity from `ctx.identity`, never from a model-supplied argument.

  ## The `:input` field (MRTR continuation — NOT identity)

  For Multi Round-Trip Requests (SEP-2322), a resumed request carries the
  server's continuation token and the client's fulfilled inputs. `:input` is
  `nil` on a first attempt, or `%{request_state: binary(), responses: term()}`
  on a retry. `MCP.Server.Dispatch` populates it from the request `params`
  (`requestState` / `inputResponses`) before invoking the tool handler. It is
  handler-continuation data, orthogonal to identity.

  ## The `:stream_sink` field (subscription-stream emitter) — NOT `:reply_sink`

  `:stream_sink` is the emitter for a `subscriptions/listen` stream, and it is
  a **different field with a different lifetime** rather than a second mode of
  `:reply_sink`. That separation is what makes the spec's two stream MUST NOTs
  structural:

    * It is `nil` on every context except the one passed to
      `c:MCP.Server.Handler.handle_listen/3`. `MCP.Server.Dispatch` strips it
      once, for every other method, so a tool/resource/prompt callback has no
      value to emit through — a request-scoped notification cannot reach a
      listen stream even if a handler tries.
    * It writes to the process holding the stream and is never a
      `MCP.Server.NotificationCollector`, so a listen stream cannot be drained
      into some other request's response, and cannot be stopped by one.

  > #### Correction (review F4, round 1) {: .warning}
  >
  > This paragraph used to add "so the request path's `drain/1` + `stop/1` has
  > nothing to act on". **That was false.** The HTTP driver starts a collector
  > for *every* POST, a `subscriptions/listen` included, and drains and stops
  > it — `warn_dropped_request_scoped/2` exists precisely because it can have
  > collected something (a handler emitting through `:reply_sink` during
  > `handle_listen/3`). The claim overreached the code in the safe direction,
  > which is why nothing broke.
  >
  > The true property, and the one the driver actually relies on: **the
  > collector's lifetime ends strictly before the stream's**, so the two can
  > never overlap. The collector is drained and stopped *before* the stream is
  > opened, deliberately — a subscription can be open for an hour, and holding
  > a per-request process for it would be a leak measured in hours.

  Unlike `:reply_sink`, it may be called from **any** process and at any later
  time: a handler stores it during `handle_listen/3` and emits from wherever
  its change events actually arrive. It returns `:ok`, or `{:error, :closed}`
  once the stream is gone — see `stream/3`.

  ## The `:reply_sink` field (per-request notification emitter)

  The stateless core removes the per-session server GenServer, so a handler can
  no longer `GenServer.call` a long-lived server to emit progress/logging
  notifications (dispatch runs synchronously *inside* the transport driver
  process — such a call would self-deadlock). Instead, `:reply_sink` is an
  optional `(method, params -> :ok)` function bound by the driver to that
  request's outbound channel. When `nil`, notifications are dropped.

  Server→client **requests** (sampling/elicitation) are NOT made through this
  context in the stateless core: they convert to MRTR (a tool returns
  `{:input_required, input_requests, request_state, state}`, which
  `Dispatch` shapes into an `InputRequiredResult`; the client fulfils the
  inputs and retries carrying `requestState`). The old blocking
  `request_sampling/3` / `request_elicitation/3` / `request/4` helpers are
  removed (they depended on the deleted per-session GenServer).
  """

  defstruct [:request_id, :meta, :identity, :input, :reply_sink, :stream_sink]

  @type input :: %{request_state: binary(), responses: term()} | nil

  @type t :: %__MODULE__{
          request_id: term(),
          meta: map() | nil,
          identity: term() | nil,
          input: input(),
          reply_sink: (String.t(), map() -> :ok) | nil,
          stream_sink: (String.t(), map() -> :ok | {:error, :closed}) | nil
        }

  @doc """
  Sends a JSON-RPC notification to the client during request handling.

  Routed through the per-request `:reply_sink`. A no-op when no sink is bound
  (e.g. an HTTP JSON-mode response with no open stream).
  """
  @spec send_notification(t(), String.t(), map()) :: :ok
  def send_notification(%__MODULE__{reply_sink: sink}, method, params)
      when is_function(sink, 2) do
    sink.(method, params)
    :ok
  end

  def send_notification(%__MODULE__{}, _method, _params), do: :ok

  @doc """
  Sends a log message notification to the client (convenience over
  `send_notification/3`).
  """
  @spec log(t(), String.t(), term(), String.t() | nil) :: :ok
  def log(%__MODULE__{} = ctx, level, data, logger \\ nil) do
    params = %{"level" => level, "data" => data}
    params = if logger, do: Map.put(params, "logger", logger), else: params
    send_notification(ctx, "notifications/message", params)
  end

  @doc """
  Sends a progress notification to the client. Uses the `progressToken` from
  `_meta` when available.
  """
  @spec send_progress(t(), number(), number() | nil) :: :ok
  def send_progress(%__MODULE__{} = ctx, progress, total \\ nil) do
    token = get_progress_token(ctx)

    params = %{"progressToken" => token, "progress" => progress}
    params = if total, do: Map.put(params, "total", total), else: params
    send_notification(ctx, "notifications/progress", params)
  end

  defp get_progress_token(%__MODULE__{meta: meta}) when is_map(meta) do
    Map.get(meta, "progressToken", 0)
  end

  defp get_progress_token(_ctx), do: 0

  @doc """
  Emits a notification onto this context's `subscriptions/listen` stream.

  Available only inside `c:MCP.Server.Handler.handle_listen/3` (elsewhere
  `:stream_sink` is `nil` and this is a no-op returning `{:error, :no_stream}`
  — deliberately distinguishable from `{:error, :closed}`, since "there was
  never a stream here" and "the client went away" are different bugs).

  The notification is filtered against the subscription's honoured set before
  it reaches the wire, so an unrequested or request-scoped type is dropped
  rather than sent (`MCP.Server.Subscription.frame/3`). A `:ok` return
  therefore means "accepted for delivery", not "the client asked for this".

  `params` keys may be **strings or atoms**, uniformly across every
  notification type, and the choice changes nothing: both encode to the same
  wire bytes, and the one filter that reads a field out of `params` — the URI
  check on `notifications/resources/updated` — reads it under either. Nothing
  is dropped on account of key style. (Before this was uniform, an atom-keyed
  `%{uri: …}` was dropped by that filter while this function still answered
  `:ok` — review F6.)

  Returns `{:error, :closed}` once the stream has ended. That check is
  inherently racy — the peer can vanish immediately after it returns `:ok` —
  so it is a promptness aid, not a delivery guarantee. The delivery guarantee
  the spec actually requires (nothing further after a close) is enforced by the
  stream owner, which stops writing, not by callers checking first.
  """
  @spec stream(t(), String.t(), map()) :: :ok | {:error, :closed | :no_stream}
  def stream(%__MODULE__{stream_sink: sink}, method, params) when is_function(sink, 2) do
    sink.(method, params)
  end

  def stream(%__MODULE__{}, _method, _params), do: {:error, :no_stream}
end
