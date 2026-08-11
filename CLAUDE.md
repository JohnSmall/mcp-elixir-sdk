# MCP Elixir SDK - Claude CLI Instructions

## Project Overview

Elixir SDK for the [Model Context Protocol](https://modelcontextprotocol.io/) (MCP). Standalone library providing both MCP **client** and **server** with pluggable transports. Protocol version: **2026-07-28** (stateless core — no handshake, no session).

**Hex package name:** `mcp_elixir_sdk` — published as v1.0.0.
**GitHub repo:** `mcp-elixir-sdk` (matches `mcp-go-sdk`, `mcp-python-sdk` naming).
**Local directory:** still `/workspace/elixir_code/mcp_ex/` (not renamed).
**Public modules:** `MCP.*` namespace (unchanged).

MCP is an open protocol that enables standardized integration between LLM applications and external data sources and tools. It uses JSON-RPC 2.0 over pluggable transports (stdio, Streamable HTTP).

**Related packages**:
- `adk_ex` at `/workspace/elixir_code/adk_ex/` — Elixir ADK (Agent Development Kit). Will use `mcp_elixir_sdk` client via an `ADK.Tool.McpToolset` adapter.
- `adk_ex_ecto` at `/workspace/elixir_code/adk_ex_ecto/` — Ecto-backed sessions for ADK.

## Quick Start

```bash
cd /workspace/elixir_code/mcp_ex
mix deps.get
mix test
mix credo
mix dialyzer
```

## Definition-of-Done Gates

Every ticket's Definition of Done runs **six** gates, each individually, all green:

1. `mix format --check-formatted`
2. `mix compile --warnings-as-errors`
3. `mix credo`
4. `mix dialyzer`
5. `mix test`
6. `mix hex.audit` — the dependency-advisory gate (added by MES-27 under advisory policy A11; took the set from five to six)

`mix deps.get` is setup, not a gate.

**These are DoD gates, not automation.** There is no CI in this repository — no
`.github/workflows`, no `mix` gate alias. Every one of the six is run per ticket and
checked on the reviewer's merge-gate checklist. **Do not assume CI enforces any of
them.**

**Gate 6 (`mix hex.audit`) — reproducibility and behaviour.**

- **Toolchain minimum (not a pin).** The hex archive is a Mix archive, not an
  asdf/mise tool, so no `.tool-versions`/declarative mechanism binds its version.
  The documented **minimum is hex ≥ 2.5.1** (the version whose advisory results and
  branch-(b) ignore mechanism are verified). Install an exact version with
  `mix local.hex 2.5.1 --force` (`mix local.hex [version]` is documented). The DoD
  check is `mix hex --version` meeting the minimum. This guarantees nobody runs the
  gate *below* the floor without noticing; it does **not** prevent drift *above* it,
  and a future hex could change the gate's behaviour.
- **Data source / staleness.** `mix hex.audit` reads advisory & retirement data from
  the **local registry cache** (`Registry.open`/`Registry.prefetch`), refreshed by
  `mix deps.get`/`deps.update` (subject to Hex's cooldown). It has **no staleness
  warning** — a stale local snapshot audits silently. Run `mix deps.get` before the
  gate so the registry is current.
- **Offline.** The gate **runs offline** (verified: `HEX_OFFLINE=1 mix hex.audit`
  exits 0) against local data — it does not fail closed, so an offline run audits
  against whatever the last refresh cached.

## Key Documentation

- **PRD**: `docs/prd.md` — Requirements, protocol features, design decisions
- **Architecture**: `docs/architecture.md` — Module map, data flow, transport design
- **Implementation Plan**: `docs/implementation-plan.md` — Phased tasks with detailed breakdown
- **Onboarding**: `docs/onboarding.md` — Full context for new agents (patterns, gotchas)
- **MCP Spec**: https://modelcontextprotocol.io/specification/2025-11-25

## Reference Codebases (download locally for coding)

| SDK | Location | Notes |
|-----|----------|-------|
| **Go SDK (PRIMARY)** | `/workspace/samples/mcp-go-sdk/` | Official Go SDK, most complete, well-structured |
| **Python SDK** | `/workspace/samples/mcp-python-sdk/` | Official Python SDK, decorator-based API |
| **Ruby SDK** | `/workspace/samples/mcp-ruby-sdk/` | Official Ruby SDK (Shopify), good OOP patterns |
| **TypeScript SDK** | `/workspace/samples/mcp-typescript-sdk/` | Reference implementation |

**GitHub repos to clone:**
```bash
git clone https://github.com/modelcontextprotocol/go-sdk /workspace/samples/mcp-go-sdk
git clone https://github.com/modelcontextprotocol/python-sdk /workspace/samples/mcp-python-sdk
git clone https://github.com/modelcontextprotocol/ruby-sdk /workspace/samples/mcp-ruby-sdk
git clone https://github.com/modelcontextprotocol/typescript-sdk /workspace/samples/mcp-typescript-sdk
git clone https://github.com/modelcontextprotocol/conformance /workspace/samples/mcp-conformance
```

## Protocol Version

Target: **2025-11-25** (latest stable). The TypeScript schema is the source of truth:
https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-11-25/schema.ts

## Module Map (Planned)

### Core Protocol
- `MCP.Protocol` — JSON-RPC 2.0 message types, framing, ID generation
- `MCP.Protocol.Types` — All MCP types (Tool, Resource, Prompt, Content, etc.)
- `MCP.Protocol.Messages` — Request/response/notification structs for all MCP methods
- `MCP.Protocol.Capabilities` — Client and server capability structs

### Transport Layer
- `MCP.Transport` — Transport behaviour (send, receive, close)
- `MCP.Transport.Stdio` — stdin/stdout transport (newline-delimited JSON-RPC)
- `MCP.Transport.StreamableHTTP` — HTTP POST + SSE transport with session management

### Client
- `MCP.Client` — High-level client API (connect, list_tools, call_tool, etc.)
- `MCP.Client.Session` — Manages single client-server connection lifecycle

### Server
- `MCP.Server` — High-level server API (register tools/resources/prompts, run)
- `MCP.Server.Handler` — Behaviour for implementing server feature handlers
- `MCP.Server.Router` — Routes incoming JSON-RPC methods to handlers

## Conformance Testing

MCP has an official conformance test suite: https://github.com/modelcontextprotocol/conformance

### SDK Tiers
- **Tier 1**: 100% conformance pass rate (target)
- **Tier 2**: 80% conformance pass rate (initial goal)
- **Tier 3**: No minimum

### Integration
The conformance framework tests via:
- **Server mode**: Framework connects as MCP client to our server
- **Client mode**: Framework starts a test server, runs our client against it

Requires building conformance adapter scripts (see `docs/implementation-plan.md`).

## Critical Rules

1. **JSON-RPC 2.0**: All messages must be valid JSON-RPC 2.0. IDs must be unique per request, never null.
2. **Stateless core (2026-07-28)**: No `initialize` handshake and no session (SEP-2575/2567). Every request is self-contained and carries the protocol version, client info, and client capabilities in per-request `_meta` under `io.modelcontextprotocol/*` keys. Capability discovery is via `server/discover`. Any request is serviceable by any instance behind a round-robin balancer.
3. **Stdio framing**: Messages are newline-delimited. Must NOT contain embedded newlines.
4. **Streamable HTTP**: POST for request/response (JSON or SSE per `Accept`); **no `Mcp-Session-Id`**. `Mcp-Method`/`Mcp-Name` routing headers (SEP-2243) enable gateway routing without body inspection.
5. **Protocol version**: carried per request in `_meta["io.modelcontextprotocol/protocolVersion"]` (`2026-07-28`); a missing/unsupported version fails fast with `-32022`.
6. **Identity**: the caller principal comes from the authenticated transport pipeline (HTTP: per request from `conn` via the `handler_opts` factory; stdio: launch-static) into `ToolContext.identity` — **never** from model-controlled `params`/`arguments`.
7. **Tool annotations are untrusted**: Unless from a trusted server.
8. **Server→client input via MRTR (SEP-2322)**: a handler returns `InputRequiredResult` (+`requestState`); the client fulfils inputs and retries. There is no held-open server→client request path.

## Architecture Quick Reference

```
Host Application
  |
  +--> MCP.Client ----[Transport]----> MCP Server (external)
  |       |
  |       +--> initialize / capability negotiation
  |       +--> tools/list, tools/call
  |       +--> resources/list, resources/read
  |       +--> prompts/list, prompts/get
  |
  +--> MCP.Server <---[Transport]---- MCP Client (external)
          |
          +--> register tools, resources, prompts
          +--> handle incoming requests
          +--> sampling/createMessage (request to client)
          +--> elicitation/create (request to client)
```

### Server Features (server provides to client)
- **Tools**: Functions the LLM can call (model-controlled)
- **Resources**: Data/context for the LLM (application-controlled)
- **Prompts**: Templates for user interactions (user-controlled)

### Client Features (client provides to server)
- **Sampling**: Server requests LLM completions via client
- **Roots**: Server queries filesystem boundaries
- **Elicitation**: Server requests user input via client

## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
