# MCP Ex — Usage Rules

> Condensed rules for AI agents and developers using `mcp_ex`.
> For full documentation see [hexdocs](https://hexdocs.pm/mcp_ex).

## What This Package Does

`mcp_ex` is an Elixir implementation of the [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) — an open protocol for integrating LLM applications with external data sources and tools. It provides both **client** and **server** implementations with pluggable transports. Protocol version: **2025-11-25**.

## Installation

```elixir
# mix.exs deps
{:mcp_ex, "~> 1.0"}

# Also add these for Streamable HTTP transport:
{:req, "~> 0.5"}      # HTTP client
{:plug, "~> 1.16"}    # HTTP framework
{:bandit, "~> 1.5"}   # HTTP server
```

The stdio transport requires no additional dependencies.

## Client Rules

### Starting a Client

Always provide `:transport` and `:client_info`:

```elixir
{:ok, client} = MCP.Client.start_link(
  transport: {MCP.Transport.Stdio, command: "mcp-server", args: []},
  client_info: %{name: "my_app", version: "1.0.0"}
)
```

### Connection Lifecycle

You **must** call `connect/1` before any other operation. It performs the MCP initialization handshake:

```elixir
{:ok, info} = MCP.Client.connect(client)
# info contains server_info, capabilities, protocol_version, instructions
```

Call `MCP.Client.close/1` when done.

### Available Client Operations

| Function | Purpose |
|----------|---------|
| `connect/1` | Initialize handshake (required first) |
| `list_tools/1,2` | List server tools (with optional cursor) |
| `call_tool/3,4` | Call a tool by name with arguments |
| `list_resources/1,2` | List server resources |
| `read_resource/2` | Read a resource by URI |
| `list_prompts/1,2` | List server prompts |
| `get_prompt/3` | Get a prompt by name with arguments |
| `list_all_tools/1` | Auto-paginate all tools |
| `list_all_resources/1` | Auto-paginate all resources |
| `list_all_prompts/1` | Auto-paginate all prompts |
| `close/1` | Disconnect and clean up |

### Client Feature Callbacks

To support server-initiated requests, pass callback options to `start_link/1`:

```elixir
MCP.Client.start_link(
  transport: {transport_mod, transport_opts},
  client_info: %{name: "my_app", version: "1.0.0"},
  on_sampling: fn params -> {:ok, %{"role" => "assistant", "content" => %{"type" => "text", "text" => "response"}, "model" => "my-model", "stopReason" => "endTurn"}} end,
  on_roots_list: fn _params -> {:ok, %{"roots" => [%{"uri" => "file:///path", "name" => "Root"}]}} end,
  on_elicitation: fn params -> {:ok, %{"action" => "accept", "content" => %{}}} end,
  notification_handler: fn method, params -> IO.puts("#{method}") end
)
```

Capabilities are auto-advertised when callbacks are provided.

## Server Rules

### Implementing a Handler

Create a module with `@behaviour MCP.Server.Handler`. Only `init/1` is required — implement additional callbacks to enable features. The server auto-detects capabilities based on which callbacks you implement.

```elixir
defmodule MyHandler do
  @behaviour MCP.Server.Handler

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_list_tools(_cursor, state) do
    tools = [
      %{
        "name" => "my_tool",
        "description" => "Does something",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"arg" => %{"type" => "string"}},
          "required" => ["arg"]
        }
      }
    ]
    {:ok, tools, nil, state}
  end

  @impl true
  def handle_call_tool("my_tool", %{"arg" => arg}, state) do
    {:ok, [%{"type" => "text", "text" => "Result: #{arg}"}], state}
  end
end
```

### Handler Callback Signatures

| Callback | Arity | Return |
|----------|-------|--------|
| `init/1` | 1 | `{:ok, state}` |
| `handle_list_tools/2` | 2 | `{:ok, tools, next_cursor, state}` |
| `handle_call_tool/3` | 3 | `{:ok, content, state}` or `{:error, code, message, state}` |
| `handle_call_tool/4` | 4 | Same as /3, but receives `ToolContext` for async ops |
| `handle_list_resources/2` | 2 | `{:ok, resources, next_cursor, state}` |
| `handle_read_resource/2` | 2 | `{:ok, contents, state}` or `{:error, code, message, state}` |
| `handle_list_prompts/2` | 2 | `{:ok, prompts, next_cursor, state}` |
| `handle_get_prompt/3` | 3 | `{:ok, result, state}` or `{:error, code, message, state}` |
| `handle_complete/3` | 3 | `{:ok, completion, state}` |
| `handle_set_log_level/2` | 2 | `{:ok, state}` |
| `handle_subscribe/2` | 2 | `{:ok, state}` or `{:error, code, message, state}` |
| `handle_unsubscribe/2` | 2 | `{:ok, state}` or `{:error, code, message, state}` |
| `handle_list_resource_templates/2` | 2 | `{:ok, templates, next_cursor, state}` |

### Starting a Server

**Stdio:**

```elixir
{:ok, server} = MCP.Server.start_link(
  transport: {MCP.Transport.Stdio, mode: :server},
  handler: {MyHandler, []},
  server_info: %{name: "my_server", version: "1.0.0"}
)
```

**Streamable HTTP (Plug + Bandit):**

```elixir
plug_config = MCP.Transport.StreamableHTTP.Plug.init(
  server_mod: MyHandler,
  server_opts: [server_info: %{name: "my_server", version: "1.0.0"}]
)

{:ok, _bandit} = Bandit.start_link(
  plug: {MCP.Transport.StreamableHTTP.Plug, plug_config},
  port: 8080,
  ip: {127, 0, 0, 1}
)
```

### Async Tool Execution with ToolContext

Implement `handle_call_tool/4` (4-arity) instead of `/3` to get a `ToolContext` for sending log messages, progress updates, and making server-to-client requests:

```elixir
def handle_call_tool("analyze", args, ctx, state) do
  ToolContext.log(ctx, "info", "Starting analysis")
  ToolContext.send_progress(ctx, 0, 100)

  {:ok, result} = ToolContext.request_sampling(ctx, %{
    "messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => "Analyze: #{args["code"]}"}}],
    "maxTokens" => 1000
  })

  ToolContext.send_progress(ctx, 100, 100)
  {:ok, [%{"type" => "text", "text" => result["content"]["text"]}], state}
end
```

**ToolContext functions:** `log/3`, `send_progress/3`, `send_notification/3`, `request/4`, `request_sampling/2`, `request_elicitation/2`.

## Transport Rules

### Stdio Transport

- Client mode: `{MCP.Transport.Stdio, command: "cmd", args: ["arg1"]}`
- Server mode: `{MCP.Transport.Stdio, mode: :server}`
- Messages are newline-delimited JSON-RPC. Must NOT contain embedded newlines.
- Works with zero additional dependencies.

### Streamable HTTP Transport

- Client: `{MCP.Transport.StreamableHTTP.Client, url: "http://host:port/mcp"}`
- Server: Use `MCP.Transport.StreamableHTTP.Plug` with Bandit (see above)
- Requires `:req`, `:plug`, and `:bandit` dependencies.
- Uses POST for sending, GET for SSE listening, `MCP-Session-Id` header for stateful sessions.

## Critical Gotchas

1. **Always call `connect/1` first.** No operations work before the initialization handshake completes (except ping).

2. **Sampling over HTTP times out.** When using `ToolContext.request_sampling/2` over Streamable HTTP, the client's `Req.post` blocks until the SSE stream completes, so the client cannot respond to the sampling request. The server's `request_timeout` (default 30s) returns `{:error, :timeout}`. **Always handle the error case.** Sampling works correctly over stdio.

3. **Content is always a list of maps.** Tool results, resource contents, and prompt messages use `[%{"type" => "text", "text" => "..."}]` format. Never return a bare string.

4. **Tool input schemas use JSON Schema.** The `"inputSchema"` field must be a valid JSON Schema object with `"type" => "object"`.

5. **Cursors for pagination.** List callbacks receive a cursor and must return `{:ok, items, next_cursor, state}`. Return `nil` for next_cursor when there are no more pages.

6. **Error tuples include state.** All error returns are `{:error, code, message, state}` — don't forget to return the handler state.

7. **Capability auto-detection.** The server only advertises capabilities for callbacks your handler implements. No need to configure capabilities manually.

8. **JSON-RPC 2.0 compliance.** All messages are valid JSON-RPC 2.0. IDs are unique per session, never null.

## Common Error Codes

| Code | Meaning |
|------|---------|
| `-32700` | Parse error |
| `-32600` | Invalid request |
| `-32601` | Method not found |
| `-32602` | Invalid params |
| `-32603` | Internal error |
| `-32002` | Resource not found (MCP-specific) |

## Module Reference

| Module | Purpose |
|--------|---------|
| `MCP.Client` | High-level client API |
| `MCP.Server` | High-level server API |
| `MCP.Server.Handler` | Server handler behaviour |
| `MCP.Server.ToolContext` | Async tool execution context |
| `MCP.Transport` | Transport behaviour |
| `MCP.Transport.Stdio` | Stdio transport |
| `MCP.Transport.StreamableHTTP.Client` | HTTP client transport |
| `MCP.Transport.StreamableHTTP.Plug` | HTTP server transport (Plug) |
| `MCP.Protocol` | JSON-RPC 2.0 framing and ID generation |
| `MCP.Protocol.Types.*` | MCP type structs (Tool, Resource, Prompt, Content, etc.) |
| `MCP.Protocol.Messages.*` | Request/response/notification structs |
| `MCP.Protocol.Capabilities.*` | Client and server capability structs |
