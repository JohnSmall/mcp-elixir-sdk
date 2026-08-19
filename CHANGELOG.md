# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — 2.0.0 (the 2026-07-28 stateless core)

The 2.0.0 line is a rewrite against MCP **2026-07-28**: no `initialize` handshake, no
session, every request self-contained. The entries below cover `subscriptions/listen`
(MES-15) and the extensions negotiation surface (MES-16); the rest of the 2.0.0 changes
are logged per ticket in `docs/sprint_4_issues.md` and will be consolidated here at
release. Public API additions are recorded here as they land rather than deferred to
release — a consumer scans a CHANGELOG for exactly that.

### Added
- **Extensions negotiation (SEP-2133)** — `MCP.Protocol.Extensions`, and an `extensions`
  field on both `ClientCapabilities` (schema.ts:785) and `ServerCapabilities`
  (schema.ts:882), parsed inbound and emitted outbound. **This SDK implements no
  extension**, and that is the behaviour: the negotiation surface is handled correctly
  while supporting zero, so a peer offering extensions we do not support is serviced
  normally and is never an error. Declare an extension you have implemented yourself with
  the new `MCP.Server.Config.build/2` option **`:extensions`** (launch-static, reaches the
  wire via `server/discover`) or with **`:client_capabilities`**' `:extensions` field on
  `MCP.Client.start_link/1` (stamped into every request's `_meta`, per schema.ts:91-98).
  Both are validated where they are declared — an identifier that violates the `_meta`
  naming rules, or settings that do not encode *to a JSON object* (`%Date{}` encodes to a
  JSON string, and is not one), are dropped and named in a `Logger.warning` rather than
  reaching the wire or failing later. `:client_capabilities` accepts a
  `%ClientCapabilities{}` and nothing else: unlike `:client_info`, a plain map is not
  converted, it is discarded whole with a warning naming what was lost. Undeclared, the
  field is **absent** from the wire, not `{}`. `MCP.Protocol.Extensions.from_meta/1` reads
  a peer's declaration off `ctx.meta`; those declarations are self-asserted and must never
  gate access — identity comes from `ctx.identity` alone.
- **`subscriptions/listen`** — the long-lived notification stream that replaces *both* the
  removed GET SSE endpoint and the removed `resources/subscribe` / `resources/unsubscribe`
  pair. A POST is answered with an SSE stream held open: the
  `notifications/subscriptions/acknowledged` frame first, then the notification types the
  client opted in to. **Server-side, HTTP transport only** — stdio is a separate ticket, and
  `MCP.Transport.StreamableHTTP.Client` cannot yet consume a held-open stream.
- Handler callbacks `handle_listen/3`, `handle_listen_closed/3` and the static
  `supported_subscriptions/0` capability declaration (all optional).
- `MCP.Server.ToolContext.stream/3` and the `:stream_sink` field, for emitting onto a
  subscription stream from any process.
- Plug options `:max_stream_lifetime` (default 1 hour) and `:keepalive_interval`
  (default 15 s).
- `MCP.Transport.SSE.comment/0` — the bare SSE comment line used as a keep-alive.

### Changed
- **Driver contract (breaking for custom transport drivers).** `MCP.Server.Dispatch.dispatch/3`
  gained **two** new return shapes: `{:stream, %MCP.Server.Subscription{}, state}` and
  `{:listen_refused, response, state}`. Both are returned **only** when the dispatch config
  carries `streaming: true`, which a driver sets to declare it can hold a response open — so an
  existing driver that does not set it can never receive either and needs no change. If you *do*
  opt in, handle both: for `{:stream, …}` write `subscription.ack`, then frames via
  `MCP.Server.Subscription.frame/3`, then either the graceful close response or, after a peer
  close, nothing at all; `{:listen_refused, …}` carries an ordinary error response to send. The
  second shape exists because of what a driver owes on it: `handle_listen/3` *ran* and was handed
  a live `stream_sink`, so the driver must tear the subscription down and call
  `handle_listen_closed/3`, exactly as it does when a stream it opened ends. **Whatever your
  driver does, do it on every exit** — and establish it **around the whole lifecycle, including
  the `dispatch/3` call itself**, not per branch. A `handle_listen/3` that raises never returns a
  value for you to branch on, and it has already been handed a live sink; so has a listen whose
  stream-start raises rather than returning an error. Enumerating branches misses both. The exits
  are refusal, a raising `handle_listen/3`, stream-start failure, a raising stream start, graceful
  close, peer close, and an exception in the stream loop — but the count is the check, not the
  mechanism.
- `MCP.Server.Config.detect_capabilities/1` is now `/2`, taking `streaming:`. The arity-1 form
  still works and assumes `streaming: false`.
- Notification `params` given to `MCP.Server.ToolContext.stream/3` may use **string or atom**
  keys, uniformly: the URI check on `notifications/resources/updated` reads either, so nothing is
  dropped on account of key style.

### Fixed
- **A server no longer advertises `listChanged` capabilities it cannot deliver.** Previously
  `tools`, `resources` and `prompts` were advertised with `listChanged: true` whenever the
  corresponding list callback existed, even though no mechanism to send such a notification had
  existed since the standing GET stream was removed. The claim now requires a channel: a
  streaming driver *and* a handler implementing `handle_listen/3`. `resources.subscribe`
  additionally requires an explicit `supported_subscriptions/0` declaration.

### Removed
- `GET` on the MCP endpoint. It returned `200` with an empty `text/event-stream`; it is now
  `405`, and the `allow` header names `POST` only. No backward-compatibility accommodations for
  pre-2026-07-28 clients are implemented: no `Mcp-Session-Id`, no `Last-Event-ID` resumption.
- `MCP.Protocol.Methods.resources_subscribe/0` and `resources_unsubscribe/0`,
  `MCP.Protocol.Messages.Resources.SubscribeParams` and `UnsubscribeParams`, and the
  `handle_subscribe/2` / `handle_unsubscribe/2` handler callbacks. Use `subscriptions/listen`
  with a `resourceSubscriptions` filter. `ServerCapabilities.resources.subscribe` is **kept** —
  it is how a server advertises that it honours that filter field.

### Known limitations
- A subscription stream is **per node**. Notifications reach a client only when the handler
  emits them on the instance holding that client's stream; distributing change events across
  instances is the consumer's responsibility. A deliberate deferral, not a gap to be filled by
  a future patch release.
- **Identity is resolved once, at stream open**, and stays bound for the stream's life. A
  principal revoked mid-stream keeps learning *that* a subscribed URI changed — never its
  content — until the stream closes. Bounded by `:max_stream_lifetime`.
- A client that TCP half-closes without fully closing is indistinguishable from a healthy quiet
  client; its stream is reclaimed by `:max_stream_lifetime` rather than by close detection.
- **`handle_listen_closed/3` over-tells rather than under-tells.** The teardown obligation is
  armed for any `subscriptions/listen` request before anything that can fail has run, so a
  request that raises inside the SDK's dispatch *above* the `handle_listen/3` call calls the
  callback for a subscription that never opened. Deliberate: the alternative is arming after the
  call that can fail, which loses the exits that matter. Treat an unrecognised `subscription_id`
  as a no-op.
- **Subscription teardown does not survive process kill.** `handle_listen_closed/3` runs when the
  request unwinds — a `raise`, a `throw`, a self-initiated `exit` — and **not** when the
  connection process is terminated by a signal (`Process.exit(pid, :kill)`, or a supervisor
  shutdown). Measured on the Bandit driver, not inferred. Closing it needs a monitoring process
  the SDK does not have; if a handler's registrations must survive that, hold them somewhere that
  outlives the request and reaps them itself.

## [1.1.0] - 2026-07-12

### Added
- **`handler_opts` request-identity seam** on `MCP.Transport.StreamableHTTP.Plug`. A new public
  Plug option threads request-scoped options into each session's handler `init/1`, so an
  authenticated Streamable-HTTP MCP server can bind a pipeline-established identity into handler
  state **without forking the Plug**. Two forms:
  - **Static** — `handler_opts: keyword()`, passed verbatim to `Handler.init/1`.
  - **Factory** — `handler_opts: (Plug.Conn.t() -> keyword())`, evaluated **once per session at
    the `initialize` request** against that request's `conn` (e.g. reading `conn.assigns` set by an
    upstream auth Plug), then bound for the session's lifetime.
- Validated against EMFA's consumer acceptance criteria (AC1–AC8) in the test suite, and by an
  external consumer running the seam in production against real Jira.

### Security
- Identity is established **server-side** by the authenticated Plug pipeline and bound at the
  `initialize` trust boundary — it is delivered to the handler via `init/1` opts and read from
  handler **state**, never supplied by the model as a tool-call argument (which is model-controlled
  and spoofable). The `conn` is never leaked into `handle_call_tool/3,4`, keeping handlers
  transport-agnostic. A factory that raises or returns a non-keyword fails the session cleanly at
  `initialize` (HTTP 500 / JSON-RPC -32603) with no session started and no server-side detail
  leaked to the client.

### Changed
- **Backward-compatible**: with no `handler_opts` (the default `[]`), behaviour is identical to
  prior releases — existing consumers are unaffected.
- **Docs**: clarified that the public Plug option is `server_mod:` (not the internal `MCP.Server`
  `handler:` key); documented the required client handshake ordering
  (`initialize → notifications/initialized → tools/call`; the per-session server stays `:waiting`
  until `notifications/initialized`); fixed the stale Examples link.

## [1.0.2] - 2026-07-07

### Changed
- Documentation only — no code changes. Updated `docs/prd.md`, `docs/architecture.md`, `docs/implementation-plan.md`, and `docs/onboarding.md` headers to reflect the `mcp_elixir_sdk` package name and current version (they still referred to the pre-rename `MCP Ex` / v0.2.1). Directory paths (`/workspace/elixir_code/mcp_ex/`) are intentionally left unchanged.

## [1.0.1] - 2026-04-16

### Changed
- **Renamed package** from `mcp_ex` to `mcp_elixir_sdk` (the `mcp_ex` hex name was previously taken by another client-only library). The new name follows the official MCP SDK naming convention (`mcp-go-sdk`, `mcp-python-sdk`, `mcp-ruby-sdk`, `mcp-typescript-sdk`).
- Top-level OTP application module renamed from `McpEx.Application` to `MCPElixirSDK.Application` (internal, not part of the public API).
- Default `client_info`/`server_info` name updated to `mcp_elixir_sdk`.

### Note
Public module names under the `MCP.*` namespace (e.g. `MCP.Client`, `MCP.Server`, `MCP.Server.Handler`, `MCP.Transport.*`) are unchanged, so existing code using these modules continues to work — only the dependency declaration needs updating.

## [1.0.0] - 2026-04-16

### Added
- First stable release (never published to hex — superseded by 1.0.1 due to package rename)
- 100% MCP conformance (Tier 1, 30/30 scenarios, 40/40 checks)
- Full hex package metadata, documentation, and usage rules for AI agents

## [0.2.3] - 2025-02-17

### Changed
- Updated documentation paths after workspace reorganization

## [0.2.2] - 2025-02-11

### Added
- Documented sampling timeout behavior over HTTP transport
- Added link to mcp_ex_examples repo in README

## [0.2.1] - 2025-02-11

### Changed
- Rewrote README with accurate usage examples

## [0.2.0] - 2025-02-09

### Added
- 100% MCP conformance (Tier 1) — 30/30 scenarios, 40/40 checks
- Async tool execution with `handle_call_tool/4` and `ToolContext`
- SSE streaming for intermediate messages during tool execution
- Client features: sampling, roots, elicitation callbacks
- Integration tests covering full client-server workflows

### Changed
- Phase 7 completion: conformance suite integration

## [0.1.0] - 2025-02-08

### Added
- Initial release
- MCP Client GenServer with full protocol API
- MCP Server GenServer with Handler behaviour
- Stdio transport (newline-delimited JSON-RPC)
- Streamable HTTP transport (POST + SSE) with Plug and Bandit
- Core protocol types, JSON-RPC 2.0 messages, capability negotiation
- Initialization handshake and capability auto-detection
- Pagination support for list operations
- Tools, resources, prompts, completions, and logging features

[1.0.1]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.2.3...v1.0.0
[0.2.3]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/JohnSmall/mcp-elixir-sdk/releases/tag/v0.1.0
