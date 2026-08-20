defmodule MCP.Server.Handler do
  @moduledoc """
  Behaviour for implementing MCP server feature handlers.

  Implement this behaviour to define how your server responds to client
  requests for tools, resources, prompts, completions, and logging.

  All callbacks are optional — the server only advertises capabilities
  for callbacks that your module actually implements.

  ## Example

      defmodule MyHandler do
        @behaviour MCP.Server.Handler

        @impl true
        def init(opts) do
          {:ok, %{tools: Keyword.get(opts, :tools, [])}}
        end

        @impl true
        def handle_list_tools(_cursor, state) do
          {:ok, state.tools, nil, state}
        end

        @impl true
        def handle_call_tool("echo", %{"message" => msg}, state) do
          {:ok, [%{"type" => "text", "text" => msg}], state}
        end
      end

  ## Tool schemas: what this SDK does, and what it leaves to you

  A tool map returned by `c:handle_list_tools/2,3` reaches the wire verbatim.
  Whatever you put in `"inputSchema"` and `"outputSchema"` is what the peer
  sees, byte for byte, and this SDK never parses, resolves, interprets or
  validates either one. Three consequences are policy, not accident, and each
  is stated here so it is a decision rather than an omission:

  * **Arguments are not validated against `inputSchema`.** `c:handle_call_tool/3,4`
    receives the peer's `arguments` map exactly as decoded — nothing is
    re-ordered, coerced, defaulted or `$ref`-expanded on the way in. Validating
    them is your handler's job. When you reject a call, the spec's settled
    answer is `-32602` (`schema.ts:315`, `:362-372`), whose own worked example
    (`examples/InvalidParamsError/invalid-tool-arguments.json`) carries **no
    `data` member** — one sentence in `message` naming the tool and the single
    failing constraint, echoing the property *name* and no argument *value*.
  * **`$ref` is never dereferenced.** SEP-2106's Security Implications section
    makes this a **MUST NOT** for anything that is not a same-document JSON
    Pointer or an internal `$anchor`, on SSRF and fetch-DoS grounds. This SDK
    dereferences nothing at all, so the prohibition holds by construction
    rather than by a check that could regress silently — there is a test that
    fails the day it stops holding.
  * **Structured output is not validated against `outputSchema`.**
    `schema.ts:2467` makes conformance a **SHOULD**, and failing a call because
    *your* handler's own output did not match *your* handler's own schema would
    convert that SHOULD into a MUST and break working tools. Your
    `:structured_content` reaches the wire verbatim, conforming or not. Note
    that `server/tools.mdx` states the same obligation as a **MUST** on
    *servers* — that duty is yours as the server author, and this SDK cannot
    discharge it for you; it only declines to enforce it against you.
  """

  @type state :: term()
  @type cursor :: String.t() | nil

  # --- Required callback ---

  @doc """
  Initialize handler state. Called when the server starts.
  """
  @callback init(opts :: keyword()) :: {:ok, state()} | {:error, term()}

  # --- Optional callbacks ---

  @doc """
  Return a list of tools. Called on `tools/list`.
  """
  @callback handle_list_tools(cursor(), state()) ::
              {:ok, tools :: [map()], next_cursor :: cursor(), state()}

  @typedoc """
  Optional extras a tool result may carry, returned in slot 3 of
  `c:handle_call_tool/3,4` **as a map** — the shape that also accepts a bare
  `boolean()` there means `is_error` and nothing else.

  `:structured_content` is keyed off **presence**, not value: including the key
  emits `structuredContent` even when the value is `nil` (which reaches the
  wire as JSON `null`, one of the enumerated legal values at
  `schema.ts:1819-1821`), and omitting the key omits the field. That is the
  only way to distinguish "no structured result" from "a structured result
  that is null", and it needs no sentinel.

      # no structuredContent on the wire
      {:ok, content, %{}, state}
      # "structuredContent": null
      {:ok, content, %{structured_content: nil}, state}
      # "structuredContent": false  -- a legitimate value, not an absence
      {:ok, content, %{structured_content: false}, state}

  > #### Anything else in this map is dropped, and named {: .warning}
  >
  > The two keys above are the whole type. A map carrying anything else —
  > `%{structuredContent: v}` (camelCase), `%{"structured_content" => v}`
  > (a string key), a struct in slot 3, or an `:is_error` that is not a
  > boolean — is a shape this SDK cannot use, and dialyzer cannot catch it
  > (every key is `optional()`, so a misspelled one is not a mismatch).
  >
  > Rather than drop it silently, the dispatch emits a `Logger.warning` naming
  > the tool and the unusable keys, and then continues: **a stray key never
  > raises and never fails a tool call that otherwise works.** A correct extras
  > map — including an empty one, which is what a handler that adds keys
  > conditionally returns — is silent.
  """
  @type call_tool_extras :: %{
          optional(:structured_content) => term(),
          optional(:is_error) => boolean()
        }

  @doc """
  Execute a tool. Called on `tools/call`.

  ## Returning structured content

  The 4-tuple with a **map** in slot 3 carries `structuredContent` (and
  optionally `isError`) — see `t:call_tool_extras/0`. The 4-tuple with a bare
  `boolean()` in slot 3 is the older `is_error` shape and keeps working
  unchanged; a map and a boolean cannot be confused.

  `structuredContent` may be **any** JSON value — object, array, string,
  number, boolean or null (`schema.ts:1819-1821`) — not only an object.

  > #### The backwards-compatibility fallback is yours to emit {: .warning}
  >
  > SEP-2106's Backward Compatibility section: "servers using array or
  > primitive `structuredContent` **MUST** also emit a `TextContent` block
  > containing the serialized JSON". `server/tools.mdx` states the wider form
  > of the same rule as a SHOULD ("a tool that returns structured content
  > SHOULD also return the serialized JSON in a TextContent block").
  >
  > This SDK **does not inject that block for you**, for the same reason it
  > does not validate your output: your `content` list is model-visible data
  > you authored, and silently adding to it would change what every existing
  > tool shows an LLM. What it does instead is *notice* — when a result carries
  > array or primitive structured content and no content block's text is the
  > serialized JSON, it emits a `Logger.warning` naming the tool. The check is
  > exact (each text block is JSON-decoded and compared to the structured
  > value), so the warning fires on precisely the condition the MUST describes
  > and never on a compliant result.
  >
  > "Compliant" is judged at the width of the wire, not of one spelling
  > (R-8): a `MCP.Protocol.Types.Content.TextContent` struct and an atom-keyed
  > `%{type: "text", text: ...}` map both encode to exactly the right JSON, so
  > both satisfy the check, as does a string-keyed map. Leading JSON
  > whitespace in the text is skipped. What does *not* satisfy it is a prose
  > summary of the structured value — including the one `server/tools.mdx`
  > uses in its own array-output example.
  """
  @callback handle_call_tool(name :: String.t(), arguments :: map(), state()) ::
              {:ok, content :: [map()], state()}
              | {:ok, content :: [map()], is_error :: boolean(), state()}
              | {:ok, content :: [map()], extras :: call_tool_extras(), state()}
              | {:error, code :: integer(), message :: String.t(), state()}

  @doc """
  Execute a tool with context. Called on `tools/call` when the handler
  implements this 4-arity version.

  The context (`MCP.Server.ToolContext`) allows sending notifications
  (logging, progress) and making server-to-client requests (sampling,
  elicitation) during tool execution.

  When this callback is implemented, tool execution runs asynchronously,
  enabling SSE streaming of intermediate messages.

  Structured content is returned exactly as in `c:handle_call_tool/3` — a
  `t:call_tool_extras/0` map in slot 3.
  """
  @callback handle_call_tool(
              name :: String.t(),
              arguments :: map(),
              context :: MCP.Server.ToolContext.t(),
              state()
            ) ::
              {:ok, content :: [map()], state()}
              | {:ok, content :: [map()], is_error :: boolean(), state()}
              | {:ok, content :: [map()], extras :: call_tool_extras(), state()}
              | {:error, code :: integer(), message :: String.t(), state()}

  @doc """
  Return a list of resources. Called on `resources/list`.
  """
  @callback handle_list_resources(cursor(), state()) ::
              {:ok, resources :: [map()], next_cursor :: cursor(), state()}

  @doc """
  Read a resource by URI. Called on `resources/read`.
  """
  @callback handle_read_resource(uri :: String.t(), state()) ::
              {:ok, contents :: [map()], state()}
              | {:error, code :: integer(), message :: String.t(), state()}

  @doc """
  Return a list of resource templates. Called on `resources/templates/list`.
  """
  @callback handle_list_resource_templates(cursor(), state()) ::
              {:ok, templates :: [map()], next_cursor :: cursor(), state()}

  @doc """
  Return a list of prompts. Called on `prompts/list`.
  """
  @callback handle_list_prompts(cursor(), state()) ::
              {:ok, prompts :: [map()], next_cursor :: cursor(), state()}

  @doc """
  Get a specific prompt. Called on `prompts/get`.
  """
  @callback handle_get_prompt(name :: String.t(), arguments :: map() | nil, state()) ::
              {:ok, result :: map(), state()}
              | {:error, code :: integer(), message :: String.t(), state()}

  @doc """
  Complete an argument value. Called on `completion/complete`.
  """
  @callback handle_complete(ref :: map(), argument :: map(), state()) ::
              {:ok, completion :: map(), state()}

  @doc """
  Set the logging level. Called on `logging/setLevel`.

  > **Deprecated in the 2026-07-28 stateless core.** `logging/setLevel` is
  > removed as a control method (SEP-2575); the log level now rides each
  > request's `io.modelcontextprotocol/logLevel` `_meta` key. The Logging
  > feature (server→client notifications) is retained-deprecated. This callback
  > is not invoked by the stateless dispatch and is removed in MES-9.
  """
  @callback handle_set_log_level(level :: String.t(), state()) :: {:ok, state()}

  # --- Stateless per-request callbacks (2026-07-28) ---
  #
  # The stateless dispatch (`MCP.Server.Dispatch`) constructs one per-request
  # context (`MCP.Server.ToolContext`, carrying the pipeline-established
  # `:identity`) and passes it to the identity-capable callback for the request.
  # These context-bearing arities are the stateless successors to the arities
  # above; a handler implements the context arity for any request type where it
  # makes an identity-dependent decision. `handle_call_tool/4` (defined above)
  # already carries the context and doubles as the stateless tools/call callback.

  @typedoc "The per-request handler context carrying `:identity`."
  @type context :: MCP.Server.ToolContext.t()

  @doc "Stateless `tools/list` (context-bearing). Successor to `handle_list_tools/2`."
  @callback handle_list_tools(cursor(), context(), state()) ::
              {:ok, tools :: [map()], next_cursor :: cursor(), state()}

  @doc "Stateless `resources/list` (context-bearing). Successor to `handle_list_resources/2`."
  @callback handle_list_resources(cursor(), context(), state()) ::
              {:ok, resources :: [map()], next_cursor :: cursor(), state()}

  @doc "Stateless `resources/read` (context-bearing). Successor to `handle_read_resource/2`."
  @callback handle_read_resource(uri :: String.t(), context(), state()) ::
              {:ok, contents :: [map()], state()}
              | {:error, code :: integer(), message :: String.t(), state()}

  @doc "Stateless `resources/templates/list` (context-bearing)."
  @callback handle_list_resource_templates(cursor(), context(), state()) ::
              {:ok, templates :: [map()], next_cursor :: cursor(), state()}

  @doc "Stateless `prompts/list` (context-bearing). Successor to `handle_list_prompts/2`."
  @callback handle_list_prompts(cursor(), context(), state()) ::
              {:ok, prompts :: [map()], next_cursor :: cursor(), state()}

  @doc "Stateless `prompts/get` (context-bearing). Successor to `handle_get_prompt/3`."
  @callback handle_get_prompt(name :: String.t(), arguments :: map() | nil, context(), state()) ::
              {:ok, result :: map(), state()}
              | {:error, code :: integer(), message :: String.t(), state()}

  @doc "Stateless `completion/complete` (context-bearing). Successor to `handle_complete/3`."
  @callback handle_complete(ref :: map(), argument :: map(), context(), state()) ::
              {:ok, completion :: map(), state()}

  # --- Subscriptions (2026-07-28 `subscriptions/listen`) ---

  @doc """
  Open a notification subscription. Called on `subscriptions/listen`.

  Replaces the removed `resources/subscribe` / `resources/unsubscribe` pair and
  the removed GET SSE endpoint: one long-lived request carries every kind of
  server-initiated change notification the client opts in to.

  Identity-capable, and therefore inheriting MC-1…MC-6 (see
  `docs/stateless-identity-threading-design-spec.md`). `context.identity` is
  the pipeline-established principal; the requested `filter` arrives in
  `params` and is **model-reachable data**, so it is a request, never a grant.

  ## Returning the honoured subset IS the authorization hook

  Return `{:ok, honoured_filter, state}` where `honoured_filter` is the subset
  of `filter` this principal may actually observe. A URI this caller may not
  watch is simply absent from it, and the acknowledgment — which reports the
  honoured subset, not the requested one — tells the client so. There is no
  second authorization callback, because a second place to say no is a second
  place to forget to.

  **The check is made once, at open.** A principal whose access is revoked
  mid-stream keeps learning *that* a subscribed URI changed — never its
  content, since `notifications/resources/updated` carries a URI and nothing
  else (schema.ts:1409-1418), and reading it still costs a fresh
  `resources/read` under a freshly resolved identity. `:max_stream_lifetime`
  bounds how long that lasts. This is a stated limitation, not an oversight; a
  handler wanting per-emission checks can simply decline to emit.

  Return `{:error, code, message, state}` to refuse the subscription outright.

  `context.stream_sink` is live for the duration of this callback: store it
  (see `MCP.Server.ToolContext.stream/3`) to emit notifications later, from any
  process. Anything emitted before the acknowledgment reaches the wire is
  queued, never reordered ahead of it.
  """
  @callback handle_listen(
              filter :: map(),
              context(),
              state()
            ) ::
              {:ok, honoured :: map(), state()}
              | {:error, code :: integer(), message :: String.t(), state()}

  @doc """
  A subscription has ended. Called after the stream closes, for any reason —
  client disconnect, server teardown, or lifetime expiry.

  Exists so the *handler* can drop the sink it stored in `handle_listen/3`.
  Without it the SDK leaks nothing but every handler leaks a stale entry per
  subscription, which is the same bug one layer up. The return value is
  ignored; the stream is already gone.

  **Called on every exit from a `subscriptions/listen` request**, not only the
  ones that opened a stream: a handler that ran `handle_listen/3` and was handed
  a sink is told when that sink dies, including when the listen was *refused*,
  when the stream could not be started at all, and when `handle_listen/3`
  itself raised — a callback that raised after capturing the sink still ran,
  and may still hold a registration nothing else will reap.

  > #### The one exit it is not called on {: .warning}
  >
  > A transport driver establishes this callback by unwinding the request, so
  > it runs for a `raise`, a `throw` or a self-initiated `exit`, and **not** for
  > a process killed by a signal from outside — `Process.exit(pid, :kill)`, or
  > a supervisor shutting the connection down. Measured on the HTTP driver, not
  > assumed. Guaranteeing cleanup against a kill needs a monitoring process the
  > SDK does not have; if your handler's registrations must survive that, hold
  > them somewhere that can outlive the request and reap them itself.
  >
  > On the exits where the request crashed rather than returned, the `state`
  > passed here is the handler's **pre-request** state: there is no return value
  > from which a newer one could have been carried.

  > #### And one case where it IS called and should not be {: .warning}
  >
  > The obligation is armed for **any** `subscriptions/listen` request, before
  > anything that could fail has run, so a request that raises inside the SDK's
  > own dispatch *above* the `handle_listen/3` call pays this callback for a
  > subscription that never opened — the driver cannot know at that point
  > whether your handler ran, and it errs towards telling you rather than
  > silently not. The `subscription_id` you are handed is the listen request's
  > JSON-RPC id, chosen by the client that sent it, so treat an id you do not
  > recognise as a no-op and make your teardown idempotent.

  **The context has no channels.** Both `:stream_sink` and `:reply_sink` are
  `nil` — the stream is over, and the request-scoped notification collector was
  drained and stopped before the stream ever opened. Anything emitted from here
  goes nowhere; drop your state and return.
  """
  @callback handle_listen_closed(subscription_id :: term(), context(), state()) :: any()

  @doc """
  Declare which `SubscriptionFilter` keys this handler can ever honour.

  A **static** declaration, read once by `MCP.Server.Config.detect_capabilities/2`
  to decide what the server advertises — as distinct from `handle_listen/3`'s
  per-request, per-principal answer. Valid keys are
  `MCP.Protocol.Messages.Subscriptions.filter_keys/0`.

  When not implemented, the three `listChanged` keys are implied (they need
  only a channel, which `handle_listen/3` supplies) and `resourceSubscriptions`
  is not — per-URI resource watching is extra machinery that must be declared
  rather than assumed. Implement this to advertise `resources.subscribe`, or to
  advertise less than the default.

  > #### The SDK takes this declaration on trust {: .warning}
  >
  > Two containments are involved and only one of them is enforced.
  >
  > **Enforced:** the acknowledgment can never claim more than `server/discover`
  > advertised. `MCP.Server.Dispatch` intersects what the client asked for, what
  > `handle_listen/3` returned, and what this declaration permits, so a handler
  > that over-returns is corrected rather than believed.
  >
  > **Not enforceable, and stated here rather than left to be discovered:**
  > that what you declare is what you will actually honour. This callback is
  > **static and zero-arity**; `handle_listen/3`'s answer is per-request and
  > per-principal. No check can compare them, because at the moment this is
  > read there is no request and no principal to compare against. So a handler
  > declaring `resourceSubscriptions` and then refusing every URI leaves
  > `server/discover` advertising a capability the server will not honour —
  > exactly the over-claim the SDK stopped making about itself when
  > `detect_capabilities/2` started gating each claim on a channel to honour it
  > on. Removing the SDK's own over-claim handed you the same failure mode; it
  > should not have handed it to you silently.
  >
  > Declare the keys you can honour for **some** principal, and say no to the
  > rest per-request by narrowing the honoured subset. Declaring a key you can
  > never honour for anyone is a false advertisement no gate will catch.
  """
  @callback supported_subscriptions() :: [String.t()]

  @optional_callbacks [
    handle_list_tools: 2,
    handle_list_tools: 3,
    handle_call_tool: 3,
    handle_call_tool: 4,
    handle_list_resources: 2,
    handle_list_resources: 3,
    handle_read_resource: 2,
    handle_read_resource: 3,
    handle_list_resource_templates: 2,
    handle_list_resource_templates: 3,
    handle_list_prompts: 2,
    handle_list_prompts: 3,
    handle_get_prompt: 3,
    handle_get_prompt: 4,
    handle_complete: 3,
    handle_complete: 4,
    handle_set_log_level: 2,
    handle_listen: 3,
    handle_listen_closed: 3,
    supported_subscriptions: 0
  ]
end
