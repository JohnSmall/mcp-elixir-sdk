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
           capabilities: detect_capabilities(handler_module, streaming: streaming),
           instructions: Keyword.get(opts, :instructions),
           protocol_version: Dispatch.protocol_version(),
           cache_defaults: Keyword.get(opts, :cache_defaults, {0, "public"}),
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

  defp build_server_info(%Implementation{} = impl), do: impl

  defp build_server_info(map) when is_map(map) do
    %Implementation{
      name: Map.get(map, :name) || Map.get(map, "name", "mcp_elixir_sdk"),
      version: Map.get(map, :version) || Map.get(map, "version", "1.0.0")
    }
  end

  defp default_info, do: %{name: "mcp_elixir_sdk", version: "1.0.0"}
end
