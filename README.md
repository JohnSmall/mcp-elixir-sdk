# MCP Elixir SDK

An OTP-native Elixir client and server SDK for the Model Context Protocol. The
2.0 line targets the stateless `2026-07-28` protocol revision and supports
stdio/in-process and Streamable HTTP transports.

> `2.0.0-dev.1` is a prerelease. It is a breaking cutover from the stateful
> 1.x API and does not negotiate older protocol revisions.

## What 2.0 provides

- Stateless requests: `server/discover` replaces the initialize/session
  handshake and required client metadata accompanies every request.
- OTP ownership: clients and stdio connections are GenServers; long-lived
  subscription workers run under consumer-supplied supervisors.
- Tools, resources, prompts, completions, extensions, and MRTR input-required
  round trips.
- Streamable HTTP routing headers, including schema-directed `Mcp-Param-*`
  headers and a bounded schema index.
- Lossless JSON Schema 2020-12 maps and full JSON structured-content values.
- Bounded request deadlines, isolated resolver/notification callbacks, and no
  client-side result cache.

The authoritative design package is in [`docs/sdk-2.0`](docs/sdk-2.0). The
implementation tracks the pinned official schema revision documented in
[`docs/adr/0003-2.0.0-conformance-scope.md`](docs/adr/0003-2.0.0-conformance-scope.md).

## Installation

Until 2.0 is released, pin an immutable Git commit. The development branch is
mutable and is not suitable for reproducible builds:

```elixir
def deps do
  [
    {:mcp_elixir_sdk,
     github: "jmagar/mcp-elixir-sdk",
     ref: "6dcbfed2e2b0a6a1efa667d2e2e6f0a0b362966e"}
  ]
end
```

Streamable HTTP uses the optional `Req`, `Plug`, and `Bandit` dependencies.

## Client

```elixir
{:ok, client} =
  MCP.Client.start_link(
    transport:
      {MCP.Transport.StreamableHTTP.Client,
       url: "http://127.0.0.1:4000/mcp"},
    client_info: %{name: "my_client", version: "1.0.0"},
    client_capabilities: %{"elicitation" => %{}},
    on_input_required: fn requests ->
      Map.new(requests, fn {id, _request} ->
        {id, %{"action" => "accept", "content" => %{"approved" => true}}}
      end)
    end
  )

{:ok, discovery} = MCP.Client.connect(client)
{:ok, %{"tools" => tools}} = MCP.Client.list_tools(client)
{:ok, result} = MCP.Client.call_tool(client, "add", %{"a" => 20, "b" => 22})
:ok = MCP.Client.close(client)
```

`connect/2` performs `server/discover`; it does not create a protocol session.
Each operation has one end-to-end deadline covering transport work, schema
refresh, and any MRTR resolver invocation. Cache hints are returned to the
caller but results are never cached by the SDK.

### Client subscriptions

Subscriptions are explicit processes, not lazy enumerables:

```elixir
{:ok, subscription_supervisor} =
  DynamicSupervisor.start_link(strategy: :one_for_one)

{:ok, client} =
  MCP.Client.start_link(
    transport: {MyTransport, []},
    subscription_supervisor: subscription_supervisor
  )

filter = %MCP.Protocol.Types.SubscriptionFilter{tools_list_changed: true}
{:ok, handle} = MCP.Client.listen_subscriptions(client, filter)
{:ok, acknowledgment} = MCP.Client.SubscriptionHandle.next(handle, 5_000)
:ok = MCP.Client.SubscriptionHandle.close(handle)
```

Each worker has a bounded FIFO queue (256 by default). Overflow, owner death,
or transport loss closes only that subscription.

## Server handler

Handler configuration is immutable after `init/1`. Put mutable state behind a
supervised process and store its pid or registered name in the launch config.
Every request callback receives `MCP.Server.ToolContext` before that config.

```elixir
defmodule MyApp.MCPHandler do
  @behaviour MCP.Server.Handler

  alias MCP.Server.ToolContext

  @impl true
  def init(opts), do: {:ok, %{store: Keyword.fetch!(opts, :store)}}

  @impl true
  def handle_list_tools(_cursor, %ToolContext{}, _config) do
    {:ok,
     [
       %{
         "name" => "add",
         "description" => "Adds two numbers",
         "inputSchema" => %{
           "$schema" => "https://json-schema.org/draft/2020-12/schema",
           "type" => "object",
           "properties" => %{
             "a" => %{"type" => "number"},
             "b" => %{"type" => "number"}
           },
           "required" => ["a", "b"]
         }
       }
     ], nil}
  end

  @impl true
  def handle_call_tool("add", %{"a" => a, "b" => b}, %ToolContext{}, _config) do
    {:ok, [%{"type" => "text", "text" => to_string(a + b)}]}
  end

  def handle_call_tool(name, _arguments, %ToolContext{}, _config) do
    {:error, -32_601, "Unknown tool: #{name}"}
  end
end
```

The callback forms are documented in `MCP.Server.Handler`. A handler may
return `{:input_required, requests_map, request_state}` from `handle_call_tool/4`;
the client resolves the requests and retries with a new JSON-RPC id.

### Stdio or in-process connection

```elixir
{:ok, connection} =
  MCP.Server.Connection.start_link(
    transport: {MCP.Transport.Stdio, []},
    handler: {MyApp.MCPHandler, store: MyApp.Store},
    server_info: %{name: "my_server", version: "1.0.0"}
  )
```

### Streamable HTTP

```elixir
plug =
  MCP.Transport.StreamableHTTP.Plug.new(
    server_mod: MyApp.MCPHandler,
    handler_opts: [store: MyApp.Store],
    server_opts: [
      server_info: %{name: "my_server", version: "1.0.0"},
      extensions: %{"com.example/audit" => %{"version" => 1}}
    ],
    enable_json_response: false,
    tool_schemas: %{
      "add" => %{"type" => "object", "properties" => %{}}
    }
  )

{:ok, _bandit} = Bandit.start_link(plug: plug, port: 4000)
```

Place authentication Plugs before the MCP Plug. A dynamic `handler_opts`
factory may read authenticated `conn.assigns` and return an `:identity`; never
derive identity from raw headers or tool arguments.

HTTP server subscriptions additionally require a duplicate `Registry` and a
`DynamicSupervisor`. Pass both as `subscription_registry:` and
`subscription_supervisor:` and publish filtered events with
`MCP.Server.SubscriptionPublisher.publish/4`.

## Development and verification

```text
mix format --check-formatted
mix test
mix credo --strict
mix dialyzer
mix docs
mix hex.build
```

The pinned official harness adapters and scenario ledger live in
[`conformance/README.md`](conformance/README.md). See
[`docs/dev-tooling.md`](docs/dev-tooling.md)
for the complete local and CI workflow.

## License

MIT — see [`LICENSE`](LICENSE).
