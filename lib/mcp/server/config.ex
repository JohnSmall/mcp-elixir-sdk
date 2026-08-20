defmodule MCP.Server.Config do
  @moduledoc """
  Builds the immutable per-connection dispatch `config` for the 2026-07-28
  stateless core.

  In the stateless model there is no per-session server GenServer: a transport
  driver (`MCP.Transport.StreamableHTTP.Plug`, `MCP.Server.Connection`) builds
  this config **once** and hands it to `MCP.Server.Dispatch` on every request.
  It is immutable — identity is supplied per request via
  `MCP.Server.ToolContext`, never re-derived here.

  `config` shape (the Note A contract's third element):

      %{
        handler_module: module(),
        handler_state: term(),          # from handler.init/1, launch-time only
        server_info: Implementation.t(),
        capabilities: ServerCapabilities.t(),
        instructions: String.t() | nil,
        protocol_version: String.t(),
        cache_defaults: {non_neg_integer(), String.t()},
        tool_order: :name | :handler,
        streaming: boolean()
      }

  `:streaming` records whether the **driver** can hold a response stream open
  (`MCP.Transport.StreamableHTTP.Plug` in SSE mode: yes; in
  `enable_json_response` mode: no). It gates both what the server advertises
  (see `detect_capabilities/2`) and whether `MCP.Server.Dispatch` will ever
  return a streaming result to that driver.

  `handler.init/1` is called once with the **static** handler options
  (non-identity launch config such as `region:`). The HTTP per-request identity
  factory result does NOT flow through `init/1` — it rides `ToolContext.identity`
  (D2 v4 §5). For stdio/in-process, a launch-static `identity:` option is
  resolved once (PO Comment B) by the caller and stamped on every context.
  """

  alias MCP.Protocol.Capabilities.{
    CompletionCapabilities,
    PromptCapabilities,
    ResourceCapabilities,
    ServerCapabilities,
    ToolCapabilities
  }

  alias MCP.Protocol.Extensions
  alias MCP.Protocol.Types.Implementation
  alias MCP.Server.Dispatch

  @doc """
  Builds the dispatch config from a handler module and options.

  Returns `{:ok, config}` or `{:error, reason}` if `handler.init/1` fails.

  ## Options of note

    * `:streaming` — whether the calling driver can hold a response stream open
      (default `false`). See the `config` shape above.
    * `:cache_defaults` — `{ttl_ms, cache_scope}` applied to cacheable results
      (`tools/list`, `resources/list`, `resources/read`, etc. via
      `CacheableResult`, SEP-2549). Defaults to `{0, "public"}` — **no-store**,
      so nothing is cached and there is no cross-principal cache exposure.
    * `:tool_order` — how `tools/list` orders the tools your handler returned.
      `:name` (default) sorts each response by the tool's `"name"`; `:handler`
      passes your order through verbatim. See the section below.
    * `:extensions` — MCP extensions (SEP-2133) this server supports, as
      `%{identifier => settings_object}` (schema.ts:882). Default `nil`:
      **this SDK implements no extension**, and a server declares one only
      because its handler implements it. Normalised by
      `MCP.Protocol.Extensions.normalise/2` — invalid identifiers and settings
      that would not encode as a JSON object are **dropped here, named in a
      `Logger.warning`, and never advertised**, so a mistake in this option
      cannot surface later than this call; an empty result is absent from the
      wire rather than `{}`. **Launch-static**, like `:instructions` and
      `:server_info`: a server's supported set does not vary per request. The
      *client's* set does, and is read per request from that request's `_meta`
      via `MCP.Protocol.Extensions.from_meta/1` — the two lifetimes are
      different and this SDK keeps them apart.

  > #### Security — cache scope on identity-dependent results {: .warning}
  >
  > If you raise `ttl_ms` above the no-store default **and** a result varies by
  > caller identity (e.g. a per-principal `tools/list` gated on
  > `ctx.identity`), you MUST set the scope to `"private"`:
  > `cache_defaults: {60_000, "private"}`. A `"public"` scope authorises shared
  > caches / gateways to serve one principal's identity-dependent result to
  > another — an identity leak. The SDK cannot detect which of *your* results
  > are identity-dependent (that is handler-author knowledge, the D2 §4.2
  > author-responsibility boundary), so this is a configuration guarantee you
  > own. The shipped default (`{0, "public"}`) is safe because nothing is
  > stored.

  ## `:tool_order` — what the default guarantees, and what it does not

  `server/tools.mdx` (2026-07-28) makes deterministic `tools/list` ordering a
  **SHOULD**, and states the requirement as *stability*, not sortedness: *"the
  same ordering across requests when the underlying set of tools has not
  changed"*. A curated, non-alphabetical order that never changes already
  satisfies it.

  So this is an option and not an unconditional sort. `:name` is the default
  because it closes the requirement for the handler who never considered
  ordering — a registry backed by an unordered store, whose iteration order
  depends on how it was populated. That is the realistic case under the
  2026-07-28 stateless core, where any instance behind a balancer may serve any
  request: two instances holding the identical tool set can disagree on its
  order, and a client's tool-list cache is invalidated by which instance
  answered. `:handler` preserves a curated order rather than silently
  overriding one that was already conformant — the same reason
  `MCP.Server.Handler` declines to enforce the `outputSchema` SHOULD against
  you.

  > #### The bound {: .info}
  >
  > The guarantee is **deterministic within each response, given a
  > deterministic page** — not "this SDK makes your listing deterministic".
  > `tools/list` is paginated and the sort is applied per response: sorting a
  > page does not make the concatenated listing sorted, and if your own paging
  > returns different page *contents* per request, per-page sorting neither
  > fixes that nor reveals it. Deterministic paging remains yours.
  """
  @spec build(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(handler_module, opts) do
    handler_opts = Keyword.get(opts, :handler_opts, [])

    streaming = Keyword.get(opts, :streaming, false)

    case handler_module.init(handler_opts) do
      {:ok, handler_state} ->
        {:ok,
         %{
           handler_module: handler_module,
           handler_state: handler_state,
           server_info: build_server_info(Keyword.get(opts, :server_info, default_info())),
           capabilities:
             handler_module
             |> detect_capabilities(streaming: streaming)
             |> declare_extensions(Keyword.get(opts, :extensions)),
           instructions: Keyword.get(opts, :instructions),
           protocol_version: Dispatch.protocol_version(),
           cache_defaults: Keyword.get(opts, :cache_defaults, {0, "public"}),
           tool_order: tool_order(Keyword.get(opts, :tool_order, :name)),
           streaming: streaming
         }}

      {:error, reason} ->
        {:error, {:handler_init_failed, reason}}
    end
  end

  @doc """
  Detects server capabilities from the handler's stateless (context-bearing)
  callback arities and from whether this deployment can actually deliver
  server-initiated notifications.

  ## Why `:streaming` is part of capability detection

  A capability is a **claim**, and a claim the deployment cannot honour is a
  defect whether or not anything downstream notices. `listChanged: true` says
  "I will tell you when this list changes"; delivering on it requires a
  *channel* to say it on. In the 2026-07-28 stateless core the only such
  channel is a `subscriptions/listen` stream, which requires both

    * a driver that can hold a stream open (`:streaming`), and
    * a handler that implements `c:MCP.Server.Handler.handle_listen/3`, since
      the SDK never invents notifications of its own.

  Neither is inferable from a list callback's presence, so both are checked
  here. A handler with `handle_list_tools/3` behind a JSON-mode driver
  advertises no `tools.listChanged` — correctly, because that deployment has
  no way to send one.

  ## `resources.subscribe` is declared, never inferred

  The three `listChanged` capabilities follow from having the corresponding
  list callback: nothing beyond a channel is needed to emit them. Per-URI
  resource watching (`resourceSubscriptions`, the successor to the removed
  `resources/subscribe` RPC — schema.ts:1287, :846-855) is extra machinery a
  handler either has or does not, so it is advertised only when the handler
  **says so** via the optional `c:MCP.Server.Handler.supported_subscriptions/0`
  declaration. Inferring it would reproduce exactly the over-claim this
  function exists to prevent.

  ## Options

    * `:streaming` — whether the calling driver can hold a response stream
      open. Default `false`, the safe direction: a driver that does not say it
      can stream is assumed unable to, so nothing is over-claimed by omission.
  """
  @spec detect_capabilities(module(), keyword()) :: ServerCapabilities.t()
  def detect_capabilities(handler_module, opts \\ []) do
    callbacks = handler_module.__info__(:functions)
    deliverable? = Keyword.get(opts, :streaming, false) and {:handle_listen, 3} in callbacks
    declared = declared_subscriptions(handler_module, callbacks)

    %ServerCapabilities{
      tools:
        if({:handle_list_tools, 3} in callbacks,
          do: %ToolCapabilities{
            list_changed: honoured(deliverable?, declared, "toolsListChanged")
          }
        ),
      resources: detect_resource_capabilities(callbacks, deliverable?, declared),
      prompts:
        if({:handle_list_prompts, 3} in callbacks,
          do: %PromptCapabilities{
            list_changed: honoured(deliverable?, declared, "promptsListChanged")
          }
        ),
      completions: if({:handle_complete, 4} in callbacks, do: %CompletionCapabilities{})
    }
  end

  defp detect_resource_capabilities(callbacks, deliverable?, declared) do
    if {:handle_list_resources, 3} in callbacks do
      %ResourceCapabilities{
        list_changed: honoured(deliverable?, declared, "resourcesListChanged"),
        subscribe: honoured(deliverable?, declared, "resourceSubscriptions")
      }
    end
  end

  # `nil` rather than `false` for a capability we cannot deliver: the encoder
  # drops nil keys, so the capability is *absent* from the wire rather than
  # present-and-false. Absent is the honest shape — "I make no such claim" —
  # and it is what a server without the feature has always sent.
  defp honoured(deliverable?, declared, key) do
    if deliverable? and key in declared, do: true
  end

  # The filter keys a handler declares it can honour. Absent the optional
  # declaration, the three list-changed keys are implied (they need only a
  # channel) and `resourceSubscriptions` is not (it needs per-URI watching).
  @implied_subscriptions ["toolsListChanged", "promptsListChanged", "resourcesListChanged"]

  defp declared_subscriptions(handler_module, callbacks) do
    if {:supported_subscriptions, 0} in callbacks do
      handler_module.supported_subscriptions()
    else
      @implied_subscriptions
    end
  end

  # Extension support is DECLARED, never detected. There is nothing in a
  # handler's shape to infer it from — an extension is a wire contract, not a
  # callback arity — so inferring one would be the same over-claim
  # `detect_capabilities/2` exists to prevent. Undeclared leaves the field
  # `nil`, which the encoder drops, so zero-by-default is structural rather
  # than a default value someone can forget (seps/2133-extensions.md:99).
  defp declare_extensions(%ServerCapabilities{} = capabilities, declared) do
    normalised =
      Extensions.normalise(declared, source: "MCP.Server.Config.build/2 `:extensions`")

    %{capabilities | extensions: normalised}
  end

  # `:tool_order` is validated here, at config-build time, for the same reason
  # `:extensions` is: a mistake in this option must not be able to surface later
  # than this call. An unrecognised value falls back to the default rather than
  # raising — the failure mode of a typo should be "you got the safe default and
  # were told", not "your server would not start".
  defp tool_order(order) when order in [:name, :handler], do: order

  defp tool_order(other) do
    require Logger

    Logger.warning("""
    MCP.Server.Config.build/2: unrecognised `:tool_order` #{inspect(other)}; \
    expected :name or :handler. Falling back to :name (sort each tools/list \
    response by tool name).\
    """)

    :name
  end

  defp build_server_info(%Implementation{} = impl), do: impl

  defp build_server_info(map) when is_map(map) do
    %Implementation{
      name: Map.get(map, :name) || Map.get(map, "name", "mcp_elixir_sdk"),
      version: Map.get(map, :version) || Map.get(map, "version", "1.0.0")
    }
  end

  defp default_info, do: %{name: "mcp_elixir_sdk", version: "1.0.0"}
end
