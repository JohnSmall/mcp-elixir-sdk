# Sprint 0 — Issues and Decisions

Project: MCP_Elixir_SDK (Jira key MES) · Working Procedure pin: Global v2 · Methodology pin: Global v1

This file is the local issue log (WP rule #3, #8). At sprint close it is copied to Confluence as
`Sprint 0 Issues and Decisions`, a child of the Sprint 0 page (WP rule #7 precondition).

---

## Cross-ticket / sprint-level decisions (rollup — WP rule #18)

Sprint 0 delivered two tickets: **MES-1** (analysis-only appraisal) and **MES-2** (spec-only
`handler_opts` seam). Both are **Done**. Key decisions carried out of the sprint:

- **ADR-001 — target MCP 2025-11-25 only.** All appraisal and spec work is pinned to the 2025-11-25
  revision. The 2026-07-28 stateless-core revision is logged as forward notes only, not actioned.
  Governs both MES-1 and MES-2.
- **Spec-vs-fix rescope (MES-2).** MES-1's appraisal surfaced the client-OAuth gap (gap #1 / CAND-A)
  as the headline authentication finding. MES-2 was deliberately **rescoped away from that fix**: it
  is a **distinct, server-side** request-identity seam (`handler_opts` on `StreamableHTTP.Plug`), and
  it was scoped **spec-only** this pass. Client OAuth 2.1 (CAND-A) stays a separate epic for a later
  sprint; MES-2 implementation is deferred to **MES-3**.
- **CC never files Jira tickets (WP rule #8).** All gaps below are recorded as issue-log entries with
  "Suggested Jira Ticket?" hints; ticket creation is the PM's.
- **Residual risks routed to MES-3** (from the MES-2 Reviewer, non-blocking): (a) define + test
  behaviour when a `handler_opts` factory **raises** or **returns a non-keyword**; (b) test matrix —
  default parity (`handler_opts: []`), factory evaluated **exactly once** at `initialize`, reuse across
  later same-session requests, and unchanged behaviour for direct `MCP.Server.start_link(handler: {mod, opts})`.
  **MES-3 also carries the 1.1.0 version bump + Hex publish.**
- **Sprint numbering** (`MES Sprint 1` in Jira vs `Sprint 0` in Confluence/labels) remains for the PM
  to reconcile; this log uses `sprint_0` per the Confluence Sprint 0 page + ticket label.

---

## MES-2 — Spec: `handler_opts` request-identity seam for StreamableHTTP.Plug

**Type:** Story · **Scope:** spec-only (implementation → MES-3) · **Spec'd against:** v1.0.2 ·
**Change class:** additive · backward-compatible · **1.1.0 candidate** · **Status:** Done
(squash-merged to `main` = commit `b9d5c6b`; spec-checkpoint tag `mes-2-handler-opts-spec`).

Repo artefact: `docs/handler-opts-identity-seam-spec.md` (new, +188) + `docs/architecture.md`
cross-ref (+4). No SDK code changed; `mix.exs` unchanged at 1.0.2.

Decisions settled against source (all 5 design questions):

1. **Thread path** — add `handler_opts` to the `%Plug{}` config; resolve it in `handle_initialize`
   (where `conn` is in scope) and substitute for the hardcoded `[]` at `plug.ex:332`. `MCP.Server`
   already forwards `{mod, opts}` to `Handler.init/1` verbatim — no change needed below the Plug.
2. **Binding/timing** — the per-session `MCP.Server` (and `Handler.init/1`) starts **once per session
   at the `initialize` POST**; the factory is evaluated then, and identity is **bound once** for the
   session's life. Per-request (vs per-session) identity is **out of scope** (correct vehicle would be
   `ToolContext`, not this seam).
3. **Start-path coverage** — factory form = Plug/request-scoped path only; `PreStarted` unchanged;
   conn-less paths (stdio, user-managed servers) support **static `handler_opts` only**.
4. **Merge semantics** — **factory-wins** precedence when a static base and a factory result both apply.
5. **Transport-agnostic handler** — identity arrives via `init/1` opts, **not** by leaking `Plug.Conn`
   into `handle_call_tool` (would couple every handler to Plug and break stdio/in-process transports).

**Observed-vs-source correction:** EMFA's vendored `~> 1.0` notes described a `handler: {mod, opts}`
public option; against source v1.0.2 the Plug's public options are **`server_mod`** (required) +
**`server_opts`** (mined only for `:server_info`/`:capabilities`/`:instructions`). The new seam is a
new public option **`handler_opts`**, distinct from `server_opts`.

**Security rationale:** `handler_opts` is THE supported request-context → handler-identity mechanism;
it replaces the model-spoofable "identity as a tool parameter" anti-pattern by binding identity
server-side at the authenticated `initialize` trust boundary.

**Backward-compat:** default `handler_opts: []` = byte-for-byte identical to today's hardcoded `[]`.

---

## MES-1 — Baseline re-appraisal of the February build against MCP 2025-11-25

Empirical results captured on toolchain **Erlang/OTP 28 (erts-16.2) · Elixir 1.19.5** (note: docs
assumed OTP 26 / Elixir 1.17), conformance suite **@modelcontextprotocol/conformance v0.1.16**,
spec filter **2025-11-25** (ADR-001).

Verified (all real captured output; see the MES-1 in-flight exchange child pages):

- `mix compile --warnings-as-errors` (fresh, 60 files): **clean**.
- `mix test`: **262 tests, 0 failures** — the docs' "262 tests" claim is CONFIRMED and all pass.
- `mix credo --strict`: **no issues** (82 files, 69 checks).
- `mix dialyzer`: **0 errors, passed**.
- Conformance **server / active suite (30 scenarios)**: **40/40 checks, 100%** — matches the docs' "30/30, 40/40, Tier 1" claim on the active suite.
- `protocolVersion` advertised = **"2025-11-25"**, matches upstream `LATEST_PROTOCOL_VERSION`.
- `mix hex.build`: **succeeds** → `mcp_elixir_sdk-1.0.2.tar` (MIT, metadata complete).

### Issue: "100% conformance / Tier 1" headline is stale against the current suite

**Source Ticket:** MES-1
**Type:** Gap
**Description:** On suite v0.1.16 `--suite all` (2025-11-25), server mode is **40 passed / 1 failed**.
The failing scenario `json-schema-2020-12` (SEP-1613) fails because the Feb-era conformance *handler*
does not advertise the `json_schema_2020_12_tool` the scenario expects — a test-harness gap. Whether
the library preserves 2020-12 keywords (`$schema`/`$defs`/`additionalProperties`) in a tool round-trip
is therefore **UNVERIFIED**, not proven broken.
**Recommendation:** Add `json_schema_2020_12_tool` to the conformance handler; verify/ensure the library
preserves arbitrary JSON Schema keywords in `tools/list`. Qualify the docs' conformance claim with the
suite version + active-suite scope.
**Priority Hint:** Medium · **Blocking?:** No · **Suggested Jira Ticket?:** Yes

### Issue: Client-side OAuth 2.1 authorization is entirely absent

**Source Ticket:** MES-1
**Type:** Gap
**Description:** Conformance **client / all suite (18 scenarios)** = **1 passed / 42 failed**. Only
`initialize` passes. The 10 `auth/*` scenarios (~30 checks) fail because there is **no OAuth/authorization
surface anywhere in `lib/`** (grep for oauth/authorization/Bearer/WWW-Authenticate = empty). Authorization
was an explicit non-goal in the Feb PRD. This is the dogfooding authentication issue behind MES-2.
**Recommendation:** Implement OAuth 2.1 client authorization (protected-resource metadata discovery,
`WWW-Authenticate` scope handling, token-endpoint auth basic/post/none, CIMD, scope step-up, pre-registration).
**Priority Hint:** High · **Blocking?:** No (blocks auth-required servers) · **Suggested Jira Ticket?:** Yes (MES-2)

### Issue: Conformance client adapter has drifted from suite v0.1.16

**Source Ticket:** MES-1
**Type:** Bug
**Description:** `conformance/client_adapter.exs` routes only `initialize` and the OLD `tools-call` name.
The suite renamed it `tools_call` and added `elicitation-sep1034-client-defaults` and `sse-retry`; the
adapter hits its default clause ("Unknown scenario: tools_call") and halts, so those checks fail even
though the library implements tools/call and elicitation (both pass server-side). `conformance/expected_failures.yml`
is also stale (says "24/30 (80%) Tier 2", contradicting the achieved active-suite 100%). Client-side
conformance therefore cannot currently be demonstrated beyond the handshake.
**Recommendation:** Update `client_adapter.exs` scenario routing to suite v0.1.16; regenerate the
expected-failures baseline; wire both modes into CI.
**Priority Hint:** Medium · **Blocking?:** No · **Suggested Jira Ticket?:** Yes

### Issue: Docs claim a SimpleHandler that does not exist

**Source Ticket:** MES-1
**Type:** Gap
**Description:** `architecture.md` §5 states "The `SimpleHandler` convenience module covers simple use
cases", but `grep SimpleHandler lib/` is empty — it was deferred (implementation-plan §4.6) and never
built. Blocking `run/2` on `MCP.Server` is likewise absent (§4.7, deferred). The docs present both as
present.
**Recommendation:** Either implement `SimpleHandler`/`run/2` or correct the docs to mark them as
not-yet-implemented.
**Priority Hint:** Low · **Blocking?:** No · **Suggested Jira Ticket?:** Yes

### Issue: Hex "Examples" link points at a possibly-renamed repo

**Source Ticket:** MES-1
**Type:** Improvement
**Description:** `mix.exs` package links "Examples" → `https://github.com/JohnSmall/mcp_ex_examples`
(old `mcp_ex` naming); the SDK repo itself was renamed to `mcp-elixir-sdk`. Confirm the examples repo
name and fix the link before the next Hex publish.
**Priority Hint:** Low · **Blocking?:** No · **Suggested Jira Ticket?:** No (fold into a docs pass)

### Process observation: Jira sprint named "MES Sprint 1" vs Confluence "Sprint 0"

**Source Ticket:** MES-1
**Type:** Question
**Description:** The active Jira board sprint is "MES Sprint 1"; the Confluence sprint page and the
`sprint-0` label call it Sprint 0. Numbering mismatch to reconcile so `docs/sprint_{N}_issues.md` and the
rollup page name line up. This log uses `sprint_0` per the Confluence Sprint 0 page + ticket label.
**Priority Hint:** Low · **Blocking?:** No · **Suggested Jira Ticket?:** No (PM to reconcile)

### Forward notes (not actioned this sprint — ADR-001)

- MCP **2026-07-28** stateless-core revision observations are parked as a future epic, per ADR-001.
- The ranked gap register (MES-1 in-flight child page) seeds the next, longer conformance sprint.
