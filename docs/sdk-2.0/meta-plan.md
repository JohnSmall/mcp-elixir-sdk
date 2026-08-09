# MCP Elixir SDK 2.0 Meta-plan and Progress Ledger

**Status:** Active
**Last updated:** 2026-08-08
**Target release:** `2.0.0`
**Baseline commit:** `2b34b324b390f7368e5c2bb10918ceabdea75b93`
(`2.0.0-dev.1`)

This is the single progress tracker for the six-slice 2.0 effort. It records
work that can be proven from the repository or a named command. Requirements
live in [specifications.md](specifications.md); this file does not redefine
them.

## Status vocabulary

| Status | Meaning |
| --- | --- |
| Not started | No accepted failing test or production work exists |
| Test-red | A focused test demonstrates the missing behavior |
| Implementing | Production changes exist but one or more exit gates are open |
| Verified | Focused/full tests and applicable conformance checks pass locally |
| Release-closed | Merged evidence and all slice exit gates are complete |
| Blocked | A named external decision or dependency prevents progress |

“Verified” is not synonymous with committed, pushed, merged, or released.

## Current dashboard

| Slice | Status | Accepted evidence | Depends on | Next gate |
| --- | --- | --- | --- | --- |
| S1 Routing and parameter headers | Verified | 247 full tests; strict Credo and Dialyzer clean; pinned header conformance 9/9; committed and pushed as `332235c` | S4a complete | Review and merge the feature branch |
| S2 Subscriptions | Implementing | S2a codecs, S2b client worker, and S2c server publication pushed as `256f22c`; adversarial remediation locally green in a 295-test full suite | — | Wire `listen_subscriptions` through stdio and HTTP |
| S3 Extensions negotiation | Not started | None | — | Write capability round-trip and invalid-key tests |
| S4 JSON Schema 2020-12 | Implementing | S4a committed and pushed as `332235c` | — | Write absent/null and all-six-JSON-value structured-content tests |
| S5 Client/server wiring + conformance | Not started | None | S1-S4 | Write lifecycle tests for pre-send deadlines, callback isolation, immutable handler configuration, and complete scenario ledger |
| S6 Release hardening | Not started | None | S1-S5 | Resolve dependency/toolchain findings and rewrite public docs |

Overall core progress is **one verified whole slice (S1), one committed
sub-slice (S4a), and three locally green S2 sub-slices (S2a/S2b/S2c) within six
slices**. Nothing is release-closed. This ledger uses completed gates and
immutable evidence, never subjective percentages.

## S1a retrospective ledger — standard routing headers

### Intent

Close client gap CG1: emit `Mcp-Method` and method-appropriate `Mcp-Name` on
Streamable HTTP POST requests.

### Test-first sequence

1. Added a real request-capture Plug and four integration tests.
2. The operator recorded a focused pre-change run as **0/4 passed** because
   routing headers were nil. No immutable commit or captured log preserves this
   red state, so it is historical context rather than reproducible release
   evidence.
3. Updated `MCP.Transport.StreamableHTTP.Client` to derive headers from the
   JSON-RPC method and params.
4. Reran focused tests: **4/4 passed**.
5. Added the official harness adapter scenario.
6. Ran the full verification sequence.

### Changed surfaces

| File | Purpose |
| --- | --- |
| `lib/mcp/transport/streamable_http/client.ex` | Derives outgoing routing headers |
| `test/support/request_capture_plug.ex` | Captures real received HTTP headers and body |
| `test/mcp/transport/streamable_http_client_test.exs` | Four routing-header regression tests |
| `conformance/client_adapter.exs` | Executes `http-standard-headers` scenario |

### Evidence captured 2026-08-08

| Gate | Command/evidence | Result |
| --- | --- | --- |
| Format | `mix format --check-formatted` | Pass |
| Full tests | `mix test` | **215 passed**, seed `468389` |
| Focused static analysis | `mix credo --strict` on four changed files | 39 functions, no issues |
| Official conformance | `@modelcontextprotocol/conformance@0.2.0-alpha.11`, client `http-standard-headers`, spec `2026-07-28` | **9/9 passed**, 0 failed, 0 warnings; scenario-owned skips: `initialize` response and `notifications/initialized` |
| Patch hygiene | `git diff --check` | Pass |
| Commit/push | Git/GitHub | Included in `332235c`, pushed to `origin/codex/mcp-routing-headers` |

## S1b.1 retrospective ledger — safe standard routing headers

### Intent

Complete the standard-header portion of C2 without depending on tool-schema
preservation: safe `Mcp-Name` transport, collision protection, and strict
server validation.

### Test-first sequence

1. Added a non-ASCII `Mcp-Name` test and observed Req reject the raw value as an
   invalid HTTP field value.
2. Added unsafe-ASCII and sentinel-ambiguity cases; observed the client send
   them without the required encoding.
3. Added case-insensitive reserved-header collision cases and observed every
   conflicting client start successfully.
4. Added server tests for missing standard headers, mismatches, Base64-sentinel
   decoding, malformed values, and unsupported versions. The pre-change run was
   **21 tests, 5 failures**.
5. Implemented the smallest client/server changes for each red case, then added
   regression checks for allowed custom headers, response routing-header
   omission, authenticated HTTP callers, and body-authoritative protocol
   headers.
6. An edge review found that responses also carry an `id`; a focused red test
   exposed request-only validation being applied to them. The Plug now accepts
   routing-header-free responses with HTTP 202, matching the stateless stdio
   behavior.

### Changed surfaces

| File | Purpose |
| --- | --- |
| `lib/mcp/transport/streamable_http/client.ex` | Encodes unsafe names, derives the protocol header from the body, and rejects reserved extra-header collisions |
| `lib/mcp/transport/streamable_http/plug.ex` | Requires and compares standard routing headers, decodes names, and maps unsupported versions to HTTP 400 |
| `test/mcp/transport/streamable_http_client_test.exs` | Real-Bandit client emission, encoding, collision, and response tests |
| `test/mcp/transport/streamable_http_stateless_test.exs` | Plug validation and error-semantics tests |
| `test/mcp/transport/streamable_http_ac_test.exs` | Authenticated HTTP regressions with body-derived standard headers |

### Evidence captured 2026-08-08

| Gate | Command/evidence | Result |
| --- | --- | --- |
| Focused tests | `mix test --seed 0` on the three Streamable HTTP files | **50 passed** |
| Full tests | `mix test --seed 0` | **228 passed** |
| Focused static analysis | `mix credo --strict` on six changed implementation/test files | 105 modules/functions, no issues |
| Type analysis | `mix dialyzer` | 0 errors, 0 skipped, 0 unnecessary skips |
| Official conformance | `@modelcontextprotocol/conformance@0.2.0-alpha.11`, client `http-standard-headers`, spec `2026-07-28` | **9/9 passed**, 0 failed, 0 warnings; scenario-owned skips: `initialize` response and `notifications/initialized` |
| Format | `mix format --check-formatted` | Pass |
| Patch hygiene | `git diff --check` | Pass |
| Commit/push | Git/GitHub | Included in `332235c`, pushed to `origin/codex/mcp-routing-headers` |

## S1b.2 retrospective ledger — schema-driven parameter headers

### Intent

Complete C2 after S4a made tool schemas lossless: validate `x-mcp-header`,
mirror selected arguments, bound catalog state, enforce recognized headers on
the server, and recover once from a stale schema.

### Test-first sequence

1. Invalid annotation location, token name, case-insensitive duplicate, and
   primitive type tests each failed before client filtering was added.
2. The optional transport descriptor handoff failed first with undefined
   `send_message/3`; the high-level client then failed to supply descriptors
   until the bounded index was implemented.
3. A one-entry limit test retained both tools until LRU eviction was added.
4. Real Bandit request-capture tests exposed absent custom emission and a
   crashing invalid-value path; shared descriptor/value logic now handles
   nested strings, booleans, null omission, and JavaScript-safe integers.
5. The server initially returned HTTP 200 when a recognized header was absent.
   Static and identity-aware tool-schema configuration now rejects missing,
   malformed, unexpected, or mismatched recognized values before dispatch.
6. A stale-schema test stopped after the first `HeaderMismatch`; the client now
   refreshes `tools/list`, retries once with the replacement descriptors, and
   surfaces a second mismatch without looping. The retry budget survives MRTR.
7. An explicit per-call schema test initially observed an empty descriptor
   handoff; `call_tool/4` now accepts `input_schema:` independently of the LRU.

### Changed surfaces

| File | Purpose |
| --- | --- |
| `lib/mcp/protocol/tool_routing.ex` | Shared annotation compilation and type-safe argument conversion |
| `lib/mcp/client.ex` | Invalid-tool filtering, bounded LRU, explicit schemas, and one-shot refresh/retry |
| `lib/mcp/transport.ex` | Optional descriptor-bearing `send_message/3` callback |
| `lib/mcp/transport/streamable_http/client.ex` | Deterministic `Mcp-Param-*` wire emission and clean invalid-value errors |
| `lib/mcp/transport/streamable_http/plug.ex` | Static/identity-aware schema resolution and recognized-header enforcement |
| `test/mcp/client_test.exs` | Catalog validation, LRU, explicit schema, and retry-loop coverage |
| `test/mcp/transport/streamable_http_client_test.exs` | Real HTTP custom-header encoding and value-boundary coverage |
| `test/mcp/transport/streamable_http_stateless_test.exs` | Server required/mismatch/numeric/identity-aware coverage |

### Evidence captured 2026-08-08

| Gate | Command/evidence | Result |
| --- | --- | --- |
| Focused tests | Client, Streamable HTTP client, and stateless server files | **29**, **13**, and **28** passed respectively |
| Full tests | `mix test --seed 0` | **247 passed**, 0 failures |
| Full static analysis | `mix credo --strict` | 97 files, 802 modules/functions, no issues |
| Type analysis | `mix dialyzer` | 0 errors, 0 skipped, 0 unnecessary skips |
| Official conformance | `@modelcontextprotocol/conformance@0.2.0-alpha.11`, client `http-standard-headers`, spec `2026-07-28` | **9/9 passed**, 0 failed, 0 warnings; two scenario-owned skips |
| Format | `mix format --check-formatted` | Pass |
| Documentation | `mix docs` with SDK 2.0 and ADR extras | Built without missing-file warnings |
| Package | `mix hex.build` | Pass; full `docs/` tree included |
| Patch hygiene | `git diff --check` | Pass |
| Commit/push | Git/GitHub | Included in `332235c`, pushed to `origin/codex/mcp-routing-headers` |

## Slice execution plans

### S2 — Subscriptions

**Entry:** fixed client/server worker ownership, handle API, queue, overflow,
keepalive, resumption, and transport-cancellation contracts reviewed.
**First red tests:** type round trip, acknowledgment-first ordering, filter
subset enforcement, notification correlation, and cancellation.
**Implementation:** types/handle → consumer-supplied supervisor/registry →
server worker → client worker → HTTP path → stdio multiplexing → client API.
**Exit:** focused and full tests; official client/server subscription scenarios;
no sleep-based tests; no legacy GET/subscribe path in 2.0 behavior.

#### S2a/S2b/S2c evidence captured 2026-08-08

S2a adds final-schema `SubscriptionFilter`, listen params, acknowledgment
params, graceful listen result, and method constants. The codecs use the
published-final `2026-07-28` schema names, require subscription correlation on
acknowledgments/results, reject malformed closed filters, and preserve resource
URI order and duplicates.

S2b adds the client-side worker beneath a consumer-supplied
`DynamicSupervisor` and the opaque `SubscriptionHandle`. The worker monitors
its owner, delivers FIFO events, defaults to a 256-event bound, rejects invalid
bounds, reports local overflow, terminates temporarily, and isolates siblings.
`close/1` is idempotent. Transport open/cancel wiring remains S2 work.

S2c adds a distinct server worker and filtered publisher. The worker queues the
correlated acknowledgment before becoming visible to publication, accepts a
consumer-supplied duplicate Registry by name or pid, stamps subscription IDs
without discarding existing metadata, enforces exact resource-URI filters, and
removes its registration before exit. Overflow and owner loss remain local;
the overflow test passed 30 consecutive focused repetitions after its mailbox
assertion was given an explicit load-tolerant timeout.

| Gate | Command/evidence | Result |
| --- | --- | --- |
| Accepted RED | Protocol files, client worker file, then server worker file | Missing S2 modules/methods; 5/5 client-worker and 5/5 server-worker tests failed on missing implementations |
| Focused tests | Protocol, client-worker, and server-worker files | **22 passed**, 0 failures; server worker repeated 30 times cleanly |
| Full tests | `mix test --max-cases 1 --seed 0` | **295 passed**, 0 failures after adversarial remediation |
| Full static analysis | `mix credo --strict` | 110 files, 913 modules/functions, no issues |
| Type analysis | `mix dialyzer` | 0 errors, 0 skipped, 0 unnecessary skips |
| Format/patch hygiene | `mix format --check-formatted`; `git diff --check` | Pass |
| Commit/push | Repository status | S2a-S2c checkpoint committed and pushed as `256f22c`; closure remediation follows in the next commit |

### S3 — Extensions negotiation

**Entry:** extension key grammar captured in tests.
**First red tests:** valid unknown settings round trip; invalid unprefixed key;
non-object value; separation from `experimental`.
**Implementation:** type validation → capability codecs → client per-request
metadata → discovery response.
**Exit:** focused/full tests and extension-negotiation conformance scenarios.

S2 and S3 may be implemented independently, but both must be complete before
S5's final client suite.

### S4 — JSON Schema 2020-12

**Entry:** `:absent` represents an omitted `structuredContent`; `nil` represents
present JSON null.
**First red tests:** `$defs`/`$ref`, composition, output scalar schema, and all
six JSON value categories for structured content.
**Implementation:** S4a makes tool schemas lossless and unlocks S1b; then
presence-aware result codecs; optional validation only after pass-through
behavior is correct.
**Exit:** no keyword loss, no valid-JSON-value loss, official schema scenarios
pass.

#### S4a evidence captured 2026-08-08

The first characterization tests proved the existing map-backed codecs already
preserved nested `$defs`, `$ref`, composition, conditionals, unknown keywords,
and `x-mcp-header`, and already allowed boolean output schemas. The accepted
RED case showed that `Tool.from_map/1` did not enforce the required object root
for `inputSchema`; the implementation now rejects boolean, missing-type,
non-object, and union roots with a stable `ArgumentError`.

| Gate | Command/evidence | Result |
| --- | --- | --- |
| Focused tests | Tool type and tools-message test files | **21 passed** |
| Full tests | `mix test --seed 0` | **231 passed** |
| Focused static analysis | `mix credo --strict` on Tool implementation/test | 10 modules/functions, no issues |
| Type analysis | `mix dialyzer` | 0 errors, 0 skipped, 0 unnecessary skips |
| Commit/push | Git/GitHub | Included in `332235c`, pushed to `origin/codex/mcp-routing-headers` |

### S5 — Client wiring and conformance

**Entry:** S1-S4 verified.
**Work:** public APIs; register deadlines before asynchronous transport I/O;
supervise callback functions; migrate handler state to immutable launch
configuration; verify the fixed no-result-cache policy; trace-context and open-field
preservation; adapter coverage; CI scenario ledger.
**Exit:** every official `2026-07-28` core scenario is pass or an enumerated
out-of-scope skip; both client and server suites run from a clean checkout.

### S6 — Release hardening

**Entry:** S1-S5 verified.
**Work:** dependency advisory remediation, Credo/Elixir compatibility, Dialyzer,
README/HexDocs/examples rewrite, package metadata and contents, changelog, CI,
release candidate artifact.
**Exit:** all checks green on supported runtimes; built tarball inspected;
release claim matches evidence; owner approves publish/tag.

## Standard slice workflow

Every slice follows this sequence:

1. Re-read the relevant specification, contract, types, and runtime model.
2. Inspect current code and official schema/harness version.
3. Write the smallest failing test for one behavior.
4. Confirm failure is for the intended missing behavior.
5. Implement the minimum production change.
6. Run focused tests, then the related suite, then the full suite.
7. Run formatter, Credo, Dialyzer where relevant, and official conformance.
8. Update this ledger with exact commands, totals, commit, and remaining risks.
9. Commit/push/PR only when authorized.

A test written after production code may add coverage, but it does not satisfy
the test-first gate for that behavior.

## Verification commands

Until the repository pins project runtimes, use mise without machine-specific
installation paths:

```bash
mise exec erlang@29.0.5 elixir@1.20.3-otp-29 -- mix test
```

Release-gate commands, after the toolchain issue is resolved:

```bash
mix format --check-formatted
mix test
mix credo --strict
mix dialyzer
mix hex.build
git diff --check
```

The conformance command must always pin a version and `--spec-version
2026-07-28`; never use an unqualified `latest` in evidence.

## Known risks and decisions needed

| ID | Risk/decision | Impact | Owner slice | State |
| --- | --- | --- | --- | --- |
| R1 | Conflicting extra HTTP headers may override generated routing values | Header/body mismatch or authorization bypass | S1 | Closed locally: all standard and `mcp-param-*` names are reserved case-insensitively |
| R1a | Unsafe `Mcp-Name` values are not Base64-sentinel encoded | Invalid HTTP or routing mismatch | S1 | Closed, committed, and pushed in `332235c` |
| R1b | `x-mcp-header` argument mirroring and schema refresh/retry are absent | Incomplete SEP-2243 client behavior | S1 | Closed in `332235c`; cursor/deadline hardening is in the closure remediation |
| R1c | Server currently accepts missing required standard routing headers | Non-conforming request reaches dispatch | S1 | Closed, committed, and pushed in `332235c` |
| R1d | Invalid `x-mcp-header` annotations are not rejected per tool | Injection/non-conforming catalog | S1b/S4a | Shared descriptor validation committed in `332235c`; boundary hardening is in the closure remediation |
| R2 | Long-lived subscription work inside current transport GenServer could block other sends | Deadlock/availability | S2 | Ownership fixed; implementation/test open |
| R2a | Pending state and timeout begin after synchronous HTTP I/O | Configured timeout does not bound calls | S5 | Contract fixed; implementation/test open |
| R2b | Function callbacks run inside the client GenServer | Slow/raising host code blocks or crashes client | S5 | Contract fixed; implementation/test open |
| R3 | Subscription broadcast without back-pressure can grow memory | VM instability | S2 | 256 default bound fixed; implementation/test open |
| R4 | `structuredContent` currently narrows to maps and uses truthy encoder checks | Data loss for valid JSON | S4 | Open |
| R4a | Current typed decoders discard unknown members at open schema boundaries | Forward-compatibility loss | S4/S5 | `raw`/`extra` contract fixed; implementation open |
| R5 | Cache hints without a declared client policy can imply behavior that does not exist | Stale/security-sensitive results | S5 | No-result-cache policy fixed; implementation test open |
| R5a | Current callback results return replacement state that transport owners discard | False public contract and lost consumer updates | S5 | Immutable launch-config contract fixed; migration open |
| R6 | Full Credo crashes under Elixir 1.20.3 with Credo 1.7.16 on existing sigils | Release gate unavailable | S6 | Open toolchain issue |
| R7 | Locked HTTP dependencies report security advisories | Release/security exposure | S6 | Remediate before release |
| R8 | README, PRD, package links, and examples still describe 1.x/2025 behavior | Misleading published package | S6 | Open |

## Durable architecture decisions

- [ADR-004](../adr/0004-immutable-handler-launch-configuration.md) — handler
  launch configuration is immutable; mutable consumer data has explicit OTP
  ownership.
- [ADR-005](../adr/0005-consumer-owned-subscription-supervision.md) — consumers
  own subscription supervision and server publication registries.
- [ADR-006](../adr/0006-no-client-result-cache-in-2.0.md) — the 2.0 client
  preserves cache hints but performs no result caching.

## Progress update template

When a slice changes state, update the dashboard and add an evidence block:

```markdown
### YYYY-MM-DD — Sx short outcome

- Baseline/commit:
- Tests written red first:
- Focused result:
- Full-suite result:
- Conformance harness/version/scenarios:
- Static analysis:
- Files changed:
- Remaining gates:
- Commit/PR/release state:
```

Do not replace exact counts with “tests pass,” and do not mark a slice
release-closed from an uncommitted working tree.

Historical red/green claims require either immutable commits for both states or
captured logs with command, timestamp, and tree hash. Unpreserved observations
may remain labeled as context but do not count as release evidence.

## Adversarial review closure

The 2026-08-08 document review produced ten findings. Their document-level
resolution is tracked here; production gaps remain in the risk table until code
and tests land.

| Finding | Resolution |
| --- | --- |
| Handler state falsely described as threaded | C5/M4/M6 now make launch configuration immutable; S5 owns API migration |
| Timeout lifecycle contradicted synchronous I/O | M1/M2 define pre-send pending registration, one deadline, async workers |
| Host callbacks blocked the client GenServer | M1 and S5 require supervised, bounded callback tasks |
| `x-mcp-header` validation incomplete | S1/C2 now contain the complete constraints, conversions, filtering, and retry policy |
| Notification routing headers overclaimed | S1/C2 scope standard headers to requests and state notification POSTs are undefined core behavior |
| S2 deferred final HTTP behavior | S2/C7 fix SSE cancellation, buffering, keepalive, comment, and resumption behavior |
| Unknown-field invariant was impossible | Invariant and types now limit preservation to explicit open boundaries with `raw`/`extra` |
| Slice graph was circular | S4a explicitly precedes S1b; S5 now depends on S1-S4 |
| Normative documents contained open alternatives | Presence, worker ownership, handle API, queues, overflow, and cancellation are fixed |
| Progress evidence was not reproducible | Percentages removed; historical red run labeled non-reproducible; skip names enumerated |

The subsequent eight-role code closure review produced nine unique actionable
findings after deduplication. All were addressed test-first:

| Finding | Resolution evidence |
| --- | --- |
| Timed-out reads consumed later subscription events | Worker-owned deadline tokens; client/server regressions |
| Malformed envelopes, params, arguments, and tool catalogs crashed processes | Structural Plug validation, typed routing errors, result-container validation |
| HTTP errors and transport send failures did not reach callers reliably | Correlated non-2xx JSON-RPC/SSE error delivery and immediate send-error replies |
| Stale schemas could not self-heal through eviction or pagination | Selected-tool reacquisition, cursor cycle/page/deadline bounds, one retry |
| Registry conflicts and invalid registries reported success asynchronously | Synchronous validation and registration during worker init |
| Subscription IDs accepted floats | String-or-integer validation in both final codecs |
| Malformed publication metadata killed subscribers | Pre-fanout validation plus worker-side defense |
| Routing annotations below arrays were accepted | Object-only property descent |
| Descriptor collection was quadratic | Linear descriptor-group accumulation; 8,000-property regression |
| Malformed response error objects reached a partial decoder | Total response-error validation across protocol, client, and Plug tests |
| Array guard rejected valid untyped/nullable object paths | Explicitly incompatible types rejected; omitted/object-union types accepted |

One proposed default-SSE incompatibility did not reproduce: the SDK Plug emits
JSON-RPC errors as JSON even when successful responses use SSE. A real
default-option Plug/client regression was added, and the client was also made
content-type aware for non-2xx SSE error bodies.

## Current evidence anchors

- S1 implementation:
  [`client.ex:191`](../../lib/mcp/transport/streamable_http/client.ex#L191)
- S1 integration tests:
  [`streamable_http_client_test.exs:1`](../../test/mcp/transport/streamable_http_client_test.exs#L1)
- Request capture support:
  [`request_capture_plug.ex:1`](../../test/support/request_capture_plug.ex#L1)
- Official scenario adapter:
  [`client_adapter.exs:35`](../../conformance/client_adapter.exs#L35)

## Document maintenance contract

- Requirement changes update `specifications.md` first.
- Boundary or failure changes update `contracts.md`.
- Wire/public shape changes update `types.md`.
- Process ownership/lifecycle changes update `runtime-models.md`.
- Implementation status and evidence update only this file.
- Accepted architectural decisions that outlive this release get an ADR; the
  meta-plan links the ADR instead of copying it.
