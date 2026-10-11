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

**Work-item lanes (D7).** The lane is the **Jira issue type**. A **PM Task** (issue type id
`10484`) is worked **PM-alone** behind a fail-closed merge guard; **every other level-0 type
keeps the full `PM→CC→PM→CR→PM` cycle**, and when in doubt it is a Task, not a PM Task.
A PM Task may change no reviewable path (`lib/`, `test/`, `conformance/lib/`, `conformance/controls/`, `docs/conformance/*`), and no `CLAUDE.md` **or `docs/procedure/`** text that alters a DoD gate or ships an instrument.
The full boundary, the guard block, the reviewer's **Lane check** item and the guard's two
measured properties (S9-22, S9-23) are in `docs/procedure/lanes.md`. **Canonical
statement: D7 on 250052681.**

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
**Gates 1-5 always. Gate 6 only when the ticket changes `mix.exs` or `mix.lock`. Gate 7
only when the ticket changes a path under `test/`, `lib/` or `conformance/`** — see each
gate's applicability rule below:

1. `mix format --check-formatted`
2. `mix compile --warnings-as-errors`
3. `mix credo`
4. `mix dialyzer`
5. `mix test`
6. `mix hex.audit` **run as the two-step self-validating procedure below** (positive control + audit) — the dependency-advisory gate (added by MES-27 under advisory policy A11; took the set from five to six). **A bare `mix hex.audit` is not sufficient — see the named limitation below.**
7. `mix conformance.oc_gate {TICKET_KEY}` — the **official-conformance cross-check**
   (added by MES-160 under the PO ruling of 2026-09-27; took the set from six to seven):
   no test merges green while the OC check it corresponds to is red. **Run it with the
   branch checked out and the tree clean**, and needs `node` and the pinned harness
   build (checked by its `dist/index.js` sha256) — see *Gate 7* below.

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

## Where the procedure lives

This file is the core. The procedure detail is in `docs/procedure/`, moved verbatim by
MES-177, and it binds exactly as it did here. **Read a page before the task it governs:**

- `docs/procedure/lanes.md` — D7 lanes, the PM-alone guard and the **Lane check** item.
  Read it when choosing, routing or checking a lane, at a PM-alone merge, and in every review.
- `docs/procedure/gate-6.md` — gate 6's cost, known limitations and the 6a/6b script. Read
  it whenever gate 6 runs: when the applicability rule above matches, and at the sprint sweep.
- `docs/procedure/gate-7.md` — gate 7's declarations, measurement, fail-closed conditions,
  residuals, checklist item and evidence. Read it when the branch touches `test/`, `lib/` or
  `conformance/`, and in every review.
- `docs/procedure/publication.md` — D8: push `main` and the tag, `mix origin.sync`, the
  **Publication check** item. The PM at every merge; CODE_REVIEWER in every review.
- `docs/procedure/end-of-sprint.md` — the PM, at a sprint boundary.

Key documents, reference codebases and the module map are in `docs/architecture.md`
(appendix); the conformance suite's tiers and integration are in `docs/conformance-testing.md`.

## Critical Rules

1. **JSON-RPC 2.0**: All messages must be valid JSON-RPC 2.0. IDs must be unique per request, never null.
2. **Stateless core (2026-07-28)**: No `initialize` handshake and no session (SEP-2575/2567). Every request is self-contained and carries the protocol version, client info, and client capabilities in per-request `_meta` under `io.modelcontextprotocol/*` keys. Capability discovery is via `server/discover`. Any request is serviceable by any instance behind a round-robin balancer.
3. **Stdio framing**: Messages are newline-delimited. Must NOT contain embedded newlines.
4. **Streamable HTTP**: POST for request/response (JSON or SSE per `Accept`); **no `Mcp-Session-Id`**. `Mcp-Method`/`Mcp-Name` routing headers (SEP-2243) enable gateway routing without body inspection.
5. **Protocol version**: carried per request in `_meta["io.modelcontextprotocol/protocolVersion"]` (`2026-07-28`); a missing/unsupported version fails fast with `-32022`.
6. **Identity**: the caller principal comes from the authenticated transport pipeline (HTTP: per request from `conn` via the `handler_opts` factory; stdio: launch-static) into `ToolContext.identity` — **never** from model-controlled `params`/`arguments`.
7. **Tool annotations are untrusted**: Unless from a trusted server.
8. **Server→client input via MRTR (SEP-2322)**: a handler returns `InputRequiredResult` (+`requestState`); the client fulfils inputs and retries. There is no held-open server→client request path.

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
