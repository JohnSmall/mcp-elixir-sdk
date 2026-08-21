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

## Working Procedure — seat-based (in force from the MES-27 cutover, 2026-08-16)

This project is worked by three **Claude Code CLI seats** — `PM`, `CODE_CREATOR`, `CODE_REVIEWER`
— running in one container, **sharing this clone** but holding **separate contexts**, executing
**strict-sequentially** (one ticket in flight). Flow is mediated **PM→CC→PM→CR→PM**; a seat acts on
a ticket only when the **assignee is its own service account**.

**The canonical procedure lives on Confluence, not here — link, never paraphrase.
One page, and it is the only one this file cites:**
- [Working Procedure Overrides — MCP_Elixir_SDK (MES) 250052681](https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/250052681)
  — binding for this project. Seat mechanics, baton, channel model (**D5**), comment splitting
  (**A13**), commit identity and merge authorship (**D6**), and the pointer to the wrapper's
  **tool API contract**. Its *citation register* names every outward reference it makes.

**All ticket information is on the Jira ticket — no Confluence in-flight pages** (Global Rule #10
superseded locally by MES **D5**):
- **Brief** → the ticket **body** (`jira_set_description`, PM-only).
- **Plan, close-out, review, findings** → ticket **comments**, split per MES **A13** (**~6k bytes
  per call — measured on MES-18, not the 15k target**; each part valid standalone ADF, opening with
  a back-link to its predecessor; **the baton rides the final part only**).
- **Turn + baton** → `jira_handoff` (posts the comment **and** sets the assignee in one call).
  **The assignee is the baton** — never resolve a turn by scanning comment mentions.
- **Queue** → `jira_my_queue` (`project: "MES"`). **Transitions** → `jira_transition` (PM-only,
  server-enforced); discover moves with `jira_transitions`, never copy ids. **Terminal unassign**
  → Rovo, PM-only (no wrapper primitive).
- Wrapper tools are surfaced under short names via tool-search — search for the name and use the
  fully-qualified result; never construct it.

**Commits (D6).** Each seat commits under its **own** service-account identity
(`../wp_scripts/seat_identity.sh` derives `GIT_AUTHOR_*`/`GIT_COMMITTER_*` from `EMFA_${SEAT}_EMAIL`; read a
commit's author off the commit object, never off `.git/config`). The **PM authors the squash-merge**
as `Project-Manager` after the merge gate — writing the `mix.exs` version in that commit and
collecting `Co-authored-by:` trailers for other contributing seats
(`emfa_coauthor_trailers main..{TICKET_KEY}`). Branches are bare `{TICKET_KEY}` (no slug),
local-only. Versioning is **D4** (`2.0.0-dev.N`, one flat counter, one bump per merge) —
semver-by-content increments are **not** used here.

**The `EMFA_*` env vars and `emfa_*` shell functions below are literal identifiers in a
cross-project contract, not references to another project's procedure — do not rename them.**

**Wrapper wiring.** The wrapper is reached as an MCP server declared in `.mcp.json` (HTTP,
`${EMFA_WRAPPER_URL}/mcp`, per-seat `Bearer ${EMFA_SEAT_INBOUND}`). Seats are launched by the shared
harness in the **sibling `../wp_scripts/` repo** (a separate, version-pinned, project-agnostic
checkout — not vendored here): `../wp_scripts/startup_claude.sh <SEAT>` or the polling
`../wp_scripts/seat_loop.sh MES <SEAT> claude`. The harness reads no repo files and is consumed
read-only; pin it by tag (`git -C ../wp_scripts checkout <ver>`; the on-disk version is in
`../wp_scripts/VERSION`), never edit it in place.

## Quick Start

```bash
cd /workspace/elixir_code/mcp_ex
mix deps.get
mix test
mix credo
mix dialyzer
```

## Definition-of-Done Gates

Every ticket's Definition of Done runs these gates, each individually, all green.
**Gates 1-5 always. Gate 6 only when the ticket changes `mix.exs` or `mix.lock`** —
see the applicability rule below:

1. `mix format --check-formatted`
2. `mix compile --warnings-as-errors`
3. `mix credo`
4. `mix dialyzer`
5. `mix test`
6. `mix hex.audit` **run as the two-step self-validating procedure below** (positive control + audit) — the dependency-advisory gate (added by MES-27 under advisory policy A11; took the set from five to six). **A bare `mix hex.audit` is not sufficient — see the named limitation below.**

`mix deps.get` is setup, not a gate.

**These are DoD gates, not automation.** There is no CI in this repository — no
`.github/workflows`, no `mix` gate alias. Every applicable gate is run per ticket and
checked on the reviewer's merge-gate checklist. **Do not assume CI enforces any of
them.**

**Gate 6 applicability — the standing rule (PO-ratified 2026-08-21).**

**Gate 6 runs when, and only when, the ticket's branch changes `mix.exs` or
`mix.lock`.** Establish it, do not assume it:

```bash
git diff --name-only main...{TICKET_KEY} | grep -E '^(mix\.exs|mix\.lock)$'
```

**Three dots, not two, and this is not a style preference.** `git diff A..B` compares
the two tips, so once `main` has moved it reports *main's own* changes as the branch's.
`A...B` diffs from the merge-base and answers the question actually being asked: what
did this branch change? Measured 2026-08-21 on `MES-57` — two-dot listed `CLAUDE.md`,
which only `main` had touched; three-dot did not. Left as two-dot, a `mix.lock` change
landing on `main` would make every unrebased branch fire gate 6 for someone else's
edit.

A match means run gate 6 (both halves). No match means **skip gate 6 and say so in
the close-out** — a gate table with two rows quietly missing reads as an omission,
whereas "gate 6 not applicable, no dependency change" is a stated result. Gates 1-5
still run in full: those are functions of the tree, and the ticket changes the tree.
If a ticket touches no repo files at all (a pure-Confluence reporting ticket), gates
1-5 have nothing to run against either — state that, with the same reasoning.

**Why, and what it costs.** Gate 6 is a *dependency-advisory* gate. A ticket that
changes no dependency cannot fail it for anything that ticket caused, so running it
yields no information about the work under review. It is also the most expensive gate
and the only side-effecting one: 6a materialises a separate tree at `d697093`, runs
`mix deps.get` inside it, and audits 22 advisory ids. **Measured on MES-57:** the
cleanup form in the 6a snippet below was *rejected by CODE_REVIEWER's command guard*
and ran clean twice under CODE_CREATOR's — so the behaviour is **per-seat, not
universal**, and a run that could not have found anything relevant also left a temp
directory behind on the seat that refused it. The distinction decides the remedy: if
the guards merely differ, rewriting the snippet fixes the wrong thing. Recorded as
S5-27; not acted on here.

**What this rule gives up, and where it is picked up.** Gate 6's verdict is a function
of *(lock, wall-clock)* — every other gate's is a function of the tree alone. A
universal gate 6 would therefore catch advisories published *since the last run*,
against dependencies no ticket touched. **Per-ticket, this rule gives that up**: a run
of ticket-shaped work that never touches `mix.lock` never re-audits. That coverage is
not abandoned — it moves to a cadence where it can actually be acted on, the
**end-of-sprint sweep** below (PO-ratified 2026-08-21, settling the cadence half of
PA-9). Per-ticket is the wrong cadence for it in any case: an advisory found mid-sprint
against an untouched dependency is not the reviewing seat's to fix, and blocking a
merge on it would be the one thing nobody wants.

**Gate 6 (`mix hex.audit`) — reproducibility and behaviour.**

- **Toolchain minimum (not a pin).** The hex archive is a Mix archive, not an
  asdf/mise tool, so no `.tool-versions`/declarative mechanism binds its version.
  The documented **minimum is hex ≥ 2.5.1** (the version whose advisory results and
  branch-(b) ignore mechanism are verified). Install an exact version with
  `mix local.hex 2.5.1 --force` (`mix local.hex [version]` is documented). The DoD
  check is `mix hex --version` meeting the minimum. This guarantees nobody runs the
  gate *below* the floor without noticing; it does **not** prevent drift *above* it,
  and a future hex could change the gate's behaviour.
- **Known limitation 1 — false-green on ABSENT/CORRUPT advisory data.** `mix hex.audit`
  reads advisory & retirement data from the **local registry cache**
  (`Registry.open`/`Registry.prefetch`). Confirmed from hex 2.5.1 source: the advisory
  lookup returns `nil` for a missing key (no error, no refetch), and offline `prefetch`
  checks only package **presence**, not advisory-data **completeness** — and it is
  **per-package**, so one package's advisory rows can be absent while another's are
  intact. So an incomplete/corrupt snapshot makes `mix hex.audit` **exit 0 while
  advisories are outstanding**, with no warning; it **runs offline** (`HEX_OFFLINE=1`
  exits 0) and **no native flag forces a refresh** (`HEX_NO_CACHE=1` does not — verified).
  A bare `mix hex.audit` green is not trustworthy by itself. The baseline-lock
  sentinel (6a) **narrows** this limitation to the five advisory-bearing packages —
  it does **not** compensate for it; **21 of 26 packages remain unvalidated** (see
  the residual under 6a). The freshness-independent compensating control is the live
  whole-tree OSV cross-check, owned by MES-19.

- **Known limitation 2 — the gate detects ABSENCE/CORRUPTION, NOT STALENESS, and no
  local mechanism can fix that.** A **complete-but-old** registry that still contains the
  sentinel data passes 6a and 6b while missing every advisory published since the
  snapshot — and staleness is likelier than absence. hex offers no freshness/refresh
  guarantee, so **do not add one here** (claiming a bound that does not hold would be
  worse). **This obligation is discharged elsewhere:** a release must not treat a green
  `mix hex.audit` as publish-blocking evidence on its own — it runs the
  **freshness-independent** whole-tree OSV cross-check with a positive control (this
  ticket's AC4), which queries an external feed live and cannot be stale-green. Owned by
  **MES-19** (release conformance/gating).

- **Compensating control (6a) — a baseline-lock sentinel INSIDE the gate.** Run gate 6
  as two steps; it passes only if 6a passes **and** 6b exits 0 (A7c applied to the gate).
  6a audits the **pre-remediation baseline lock at `d697093`** (sourced from git) and
  requires **all 22 known advisory ids** to be reported — validating advisory rows for
  **every package that has ever carried an advisory in this tree** (`bandit`, `plug`,
  `req`, `mint`, `hpax`), not a single-package sentinel. It asserts a **superset** ("all
  22 present"), never "exactly 22", so a *new* advisory against a baseline version does
  not false-red the gate.

  **What 6a does NOT cover — the residual, stated by enumeration (A2d).** 6a
  validates advisory rows only for the **five** packages that carry the 22 baseline
  ids (`bandit`, `hpax`, `mint`, `plug`, `req`). For every **other** package in the
  tree, limitation 1 is untouched: if that package acquires an advisory and its local
  cache rows are absent, 6a passes and 6b exits 0 over an outstanding advisory
  (demonstrated on `thousand_island` 1.5.0). The residual is therefore **21 of the 26
  locked packages**, not three: `bunt`, `credo`, `dialyxir`, `earmark_parser`,
  `elixir_uuid`, `erlex`, `ex_doc`, `file_system`, **`finch`**, `jason`, `makeup`,
  `makeup_elixir`, `makeup_erlang`, `mime`, `nimble_options`, `nimble_parsec`,
  `nimble_pool`, `plug_crypto`, `telemetry`, **`thousand_island`**, `websock`.
  **`finch` and `thousand_island` are runtime deps on the transport path this SDK
  uses** — the residual is not confined to dev/build tooling.

  This is **irreducible for the sentinel**: a package that has never carried an
  advisory has nothing whose absence is detectable, so no sentinel can validate it
  (attempting to would be the AC7 error — claiming a bound that does not hold). The
  compensating control that *does* cover the remainder is the **live whole-tree OSV
  cross-check** (this ticket's AC4), which queries an external feed and so is not
  limited to what the local cache happens to hold. It is **owned by MES-19** for
  release. **PA-9, restated 2026-08-21 — what remains open is narrower than it was.**
  The question used to be whether the OSV check should join the *per-ticket* gate 6,
  and the standing objection was that this would make a per-ticket gate
  network-dependent, against the offline finding above. The end-of-sprint sweep
  changes that: **at a sprint boundary, network dependence costs nothing** — no work
  is in flight, no merge is blocked, and the run is PM-owned rather than on a seat's
  critical path. So the live question is now whether the OSV cross-check should also
  run at the sprint boundary, giving two independent checks per sprint instead of
  one at release. **Still the PO's, still not decided here** — but decide it against
  the boundary, not against the gate.

  ```bash
  # Gate 6a — baseline-lock sentinel: require ALL 22 known advisory ids (superset).
  # Capture output BEFORE matching (pipefail-safe — no `grep -q` in a pipe); `|| true`
  # because the baseline audit exits 1 by design (it HAS advisories) and that expected
  # nonzero must not abort a `set -e` run. Verified positive+negative under normal AND
  # `set -euo pipefail`.
  KNOWN_IDS="EEF-CVE-2026-8468 EEF-CVE-2026-39803 EEF-CVE-2026-39804 EEF-CVE-2026-39805 EEF-CVE-2026-39806 EEF-CVE-2026-39807 EEF-CVE-2026-42786 EEF-CVE-2026-42788 EEF-CVE-2026-48861 EEF-CVE-2026-48862 EEF-CVE-2026-49753 EEF-CVE-2026-49754 EEF-CVE-2026-49755 EEF-CVE-2026-49756 EEF-CVE-2026-54892 EEF-CVE-2026-56810 EEF-CVE-2026-56813 EEF-CVE-2026-56814 EEF-CVE-2026-58226 EEF-CVE-2026-58229 EEF-CVE-2026-59246 EEF-CVE-2026-59249"
  pc=$(mktemp -d)
  git show d697093:mix.exs  > "$pc/mix.exs"
  git show d697093:mix.lock > "$pc/mix.lock"
  audit_out=$( cd "$pc" && { mix deps.get >/dev/null 2>&1 || true; mix hex.audit 2>&1 || true; } )
  rm -rf "$pc"
  missing=""
  for id in $KNOWN_IDS; do case "$audit_out" in *"$id"*) : ;; *) missing="$missing $id" ;; esac; done
  if [ -n "$missing" ]; then
    echo "GATE 6 FAILS: baseline sentinel missing $(echo $missing | wc -w) of 22 known advisory ids:$missing"
    echo "  Verify each missing id at https://osv.dev BEFORE assuming local cache corruption:"
    echo "   many/all missing together => local advisory data broken/absent (run 'mix deps.get' or rebuild ~/.hex)"
    echo "   exactly one missing alone  => advisory likely withdrawn/renumbered upstream (update KNOWN_IDS, not the cache)"
    exit 1
  fi

  # Gate 6b — the real audit on THIS project. Must exit 0.
  mix hex.audit
  ```

  Verified 2026-08-12: 6a PASSes on the current registry and FAILs (naming the missing
  ids) when a package's advisory rows are stripped from a synthesised cache — shown for
  `bandit` (7 missing) and `plug` (4 missing) — under both ordinary and
  `set -euo pipefail` shells. If a future hex adds a fail-closed freshness mode, gate 6
  can simplify toward a bare invocation.

## End-of-Sprint Procedure

**Runs in the gap between sprints — after the last ticket is Done, before the next
sprint's first dispatch. PM-owned.** Seats run strict-sequentially, so at a sprint
boundary there is by construction no work in flight; that is what makes this the one
moment an advisory can be acted on without disrupting anything.

1. **Write up `docs/sprint_{N}_issues.md`** — the sprint's findings register.

2. **Dependency-advisory sweep.** Run the **two-step gate 6** (6a baseline sentinel,
   then 6b) against `main` at the sprint's final tip.

   - **The gate-6 applicability rule above does NOT apply here.** That rule is about
     *tickets*; this is a cadence sweep and it runs every sprint regardless of what
     changed. Do not skip it because no ticket touched `mix.lock` — the whole point
     is to catch advisories published against dependencies nobody touched.
   - **Two-step, never bare.** Known limitation 1 still holds: a bare `mix hex.audit`
     exits 0 over an outstanding advisory when the local cache is incomplete. 6a is
     what makes a green mean something.
   - **Record the result in `docs/sprint_{N}_issues.md`, including a clean one.**
     "Checked, and zero" and "never asked" read identically when only the answer is
     printed — so print the question.

3. **Any advisory becomes a Jira ticket. Do not fix it in place.** Raising it on the
   board is the reason this sits between sprints rather than inside one: it gets
   scoped, prioritised and scheduled like any other work, instead of being absorbed
   silently into whatever ticket happened to notice it.

**Relationship to release.** A release only ever follows a completed sprint — never
mid-sprint. So this sweep is always upstream of any release, and no release can ship
on advisory data older than the last sprint boundary. It does **not** replace MES-19's
whole-tree OSV cross-check at release: `hex.audit` reads the **local registry cache**
and OSV queries a **live external feed**, so the two fail differently and neither
subsumes the other. Both, in that order.


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
