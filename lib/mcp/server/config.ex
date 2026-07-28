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
        cache_defaults: {non_neg_integer(), String.t()}
      }

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
  """
  @spec build(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(handler_module, opts) do
    handler_opts = Keyword.get(opts, :handler_opts, [])

    case handler_module.init(handler_opts) do
      {:ok, handler_state} ->
        {:ok,
         %{
           handler_module: handler_module,
           handler_state: handler_state,
           server_info: build_server_info(Keyword.get(opts, :server_info, default_info())),
           capabilities: detect_capabilities(handler_module),
           instructions: Keyword.get(opts, :instructions),
           protocol_version: Dispatch.protocol_version(),
           cache_defaults: Keyword.get(opts, :cache_defaults, {0, "public"})
         }}

      {:error, reason} ->
        {:error, {:handler_init_failed, reason}}
    end
  end

  @doc "Detects server capabilities from the handler's stateless (context-bearing) callback arities."
  @spec detect_capabilities(module()) :: ServerCapabilities.t()
  def detect_capabilities(handler_module) do
    callbacks = handler_module.__info__(:functions)

    %ServerCapabilities{
      tools: if({:handle_list_tools, 3} in callbacks, do: %ToolCapabilities{list_changed: true}),
      resources: detect_resource_capabilities(callbacks),
      prompts:
        if({:handle_list_prompts, 3} in callbacks, do: %PromptCapabilities{list_changed: true}),
      completions: if({:handle_complete, 4} in callbacks, do: %CompletionCapabilities{})
    }
  end

  defp detect_resource_capabilities(callbacks) do
    if {:handle_list_resources, 3} in callbacks do
      %ResourceCapabilities{list_changed: true}
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
