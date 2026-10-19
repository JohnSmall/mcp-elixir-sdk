# Sprint 16 — findings register

**Sprint goal, as set by the PO on 2026-10-14.** Sprint 16 is Jira sprint 1950 on board 267. Its
master page is Confluence 332464129. The PO ruling that scoped it is MES-192 32571
("yes to questions 1, 2, 3, 4 and 5"). The goal:

> Land a guard that fails the build on stale file:N citations, then fix the client and Plug
> error-reply paths: malformed and dual-member replies fail fast, 4xx JSON-RPC errors reach the
> caller, and Plug error data is wire-safe.

The planned order was MES-176, 192, 191, 188, 198, 197, 199, 189. On 2026-10-16 the PO ruled
MES-191 first while MES-192 was parked in review, so the merge order was 176, 191, 192, 188, 198,
197, 199, 189. Eight tickets merged, `2.0.0-dev.93` → `2.0.0-dev.100`. Every turn was started
through acm. CODE_CREATOR ran on claude throughout. CODE_REVIEWER ran on codex, except on MES-192
from its fourth review round on, where the PO switched it to claude (S16-3).

| dev | ticket | what landed |
|-----|--------|-------------|
| .93 | MES-176 | Guard 21 locates each ET-CC unit by its runtime ExUnit name and scans its whole executable test block, refusing what it cannot establish (was: a stale captured line, and a body slice that could be empty) |
| .94 | MES-191 | Client tests wait on a MockTransport send event with a server-owned deadline, not a wall-clock deadline; 67 gate-7 declarations deferred to MES-203 (disclosed D10 exception) |
| .95 | MES-192 | G33: string-form `file:N` citations in the conformance data and docs are verified by pinned window bytes in gate 5, with a mechanical re-resolver and a schema-validated ledger |
| .96 | MES-188 | Recorded mutation M10 retired in adjudication-D1-server-ii and -iii: a no-op since 58cb0c0 (MES-155) |
| .97 | MES-198 | The Plug's error `data` is a plain rule string, never `inspect()` of an Elixir term; adapter read failures are tagged; invalid UTF-8 is replaced on the wire |
| .98 | MES-197 | A reply with a malformed JSON-RPC `error` member fails the pending caller at once with `:malformed_response`, instead of after its full timeout |
| .99 | MES-199 | A response carrying both `result` and a non-null `error` is refused (-32600) |
| .100 | MES-189 | The HTTP client delivers a JSON-RPC error carried on a 4xx/5xx reply to the caller when its id matches the posted request, so the -32022 retry and -32020 refresh work over HTTP |

**`lib/` changed in four files** (`git diff --stat 65f9d75 ae4b978 -- lib/`: 186 insertions, 11
deletions): `client.ex`, `protocol.ex`, `transport/streamable_http/client.ex` and
`transport/streamable_http/plug.ex`. The suite grew from 1891 to 2023 tests.

**Official conformance moved only where a ticket said it would.** No close-out or review reported
a server check moving. The one client-side move was MES-189's: the strict_connect probe's
`ClientRetrySupportedVersion` went WARNING → SUCCESS, with 0 changes on the sdk client leg
(128 rows). The recorded probe figures stay as of f4be9eb; re-recording them is MES-205. G32 stayed
CLEAN all sprint at 820 verified (663 at the tip, 157 anchored). G33 landed on MES-192 and stayed
CLEAN.

## S16-1 — review rounds kept finding the next silent accept (MES-176, MES-192)

The two instrument tickets took 3 and 8 review rounds. Every round found a new path by which the
guard *accepted* something it could not establish:

- **MES-176:** the body slice was empty for one-line tests (F1), only the `do:` clause was scanned
  so `after`/`rescue`/`catch`/`else` bodies went unchecked (F2), and a non-literal test name
  matched a singleton wildcard and was accepted without identity (F3).
- **MES-192:** a token-only model missed explicit-path evidence (F1); "held" states were judged by
  field shape, not by what the holder reads (F2); a holder's read domain was inferred from its
  source text (R1); a null window hash skipped the checks (S1); a snapshot was admitted by key
  name anywhere (S2); a null or integer `at` crashed the audit (T1); a JSON object in a row value
  raised (U1); and the type-matrix control passed on any refusal of the right kind (V1).

**Lessons, applied from the round they were learnt:**

- A locator that "matches" must prove identity, not just uniqueness.
- A "held" or "delegated" state must call the holder's own code, never infer its reader from
  source text. When a round finds a parser-shaped silent accept, remove the inference instead of
  patching it (the MES-192 R2 ruling dropped `held:g5_asserts_read` entirely).
- Plant by a type matrix across every JSON type, not by examples. Four rounds each found one
  instance until the matrix control did.
- A refusal control must assert its own cause (the planted row's key and detail), not just the
  refusal kind. The older controls C1–C23 and C25 do not yet: filed as **MES-202**.

**What the PM brief should have demanded at the plan hop:** for any locator, delimiter or
admission change, the full shape table and an adversarial admission table *before* the build.
The MES-176 round-2 handoff began asking for this; it should be standard.

## S16-2 — MES-191 first: the client wall-clock flakes, and gate 7's file-level reach

MES-192's binding CR gate 5 went 19/22 on client wall-clock tests (D-1, D-2, D-3, W5, W6,
`client_test:208`), four of them outside MES-191's named three, under host load. The PO ruled
MES-191 first (2026-10-16). It was re-scoped to the whole class: 60 `wait_for_sent` sites and 37
`Task.await`.

- **Citation neutrality.** CC's plan said "no record change". The PM measured 30 G32
  `citation_drift` rows on a scratch copy, because the records quote whole test bodies. Ruling
  33039: byte-neutral inside every cited window; cited sites went to **MES-203**. Lesson: a
  same-line edit is not citation-neutral; check cited windows with the guard's own reader before
  ratifying a test-file edit plan.
- **Gate 7's file-level reach.** Editing a file-level `defp` makes every test in the file
  `[changed: file]`, and each needs an `@tag oc:` line that would move 415 cited windows. The PO
  ruled a disclosed D10 exception: the 67 declarations are deferred to MES-203. Lesson: check gate
  7's reach at the plan hop for any shared-helper edit.
- **CR findings.** F1: MockTransport never removed timed-out waiters. F2: the ticket's own new
  controls used short waits. A flake-fix ticket's new tests are part of its census.

After MES-191, no client wall-clock red appeared in any later gate 5 run this sprint.

## S16-3 — codex CR: the content filter, and a fresh-session gap in acm

On MES-192's fourth review, the resumed codex CR thread was refused twice by OpenAI's
`cyber_policy` filter (exit 1, no comment). The thread carried three rounds of plant, attack and
credential wording, and acm always resumes the same thread for a ticket and seat, so rewording the
brief could not help. acm has no fresh-session primitive (reported on ACM-38 32848). The user
switched MES-192's CR to claude; codex stayed CR for every later ticket.

**Practice adopted.** Keep briefs free of attack, exploit and credential wording from round 1 of a
long adversarial review. On a `cyber_policy` exit, ask the user to switch engine; don't retry.

On 2026-10-18 codex credits ran out briefly; the user ruled CR on claude until told otherwise and
lifted it before any CR dispatch was affected.

## S16-4 — the acm Erlang cookie appeared in seat and PM output

The acm release passes its Erlang distribution cookie on its command line (Mix release scripts
always do, from `releases/COOKIE` or `RELEASE_COOKIE`). Full-argument process listings therefore
print it:

- MES-192's codex CR printed it via a full `ps` listing (ACM-38 32826).
- MES-197's CR and a PM check did the same (ACM-38 33616; the PM's ask 2 there was wrong and was
  corrected in 33669).

The operator rotated the cookie; the PM verified the rotation by hash comparison only, without
printing either value. The asks open on ACM-38 are to run the release with
`RELEASE_DISTRIBUTION=none` and to make `COOKIE` mode 600. That is the acm owner's call.

**Rule adopted for every seat and the PM:** process checks use pid and comm only
(`ps -o pid,comm`, `pgrep -c`). Never read another process's argv or environment. Every CR
handoff since MES-197 says so.

## S16-5 — PM brief and ruling errors this sprint

Recorded because each one cost a round or a correction.

- **MES-191 33039's premise.** The PM's first reading accepted CC's "no record change"; the
  measurement showed 30 drifts (S16-2). Caught before the build.
- **MES-192 32833's premise** said pinning all 533 `g5_asserts_read` heads at the tip was
  equivalent. 15 of them are anchored at bd99a39, where the tip lines differ. CC stopped correctly
  (32834); ruled in 32835.
- **MES-188 33328** said "22 seeds" without listing them, so CC ran seeds 0–21. CR's own gate 5
  on the canonical seeds became the DoD evidence. Every gate-5 brief now lists the seed values.
- **MES-198.** The PM's spot-check traced the decoder census only, not the adapter path. CR F1
  found that `read_body` can return any `{:error, term}`. Lesson: a `with`-chain `else` census
  must include foreign error terms.
- **The `2.0.0-dev.95` tag message** used the parent epic's summary (MES-118), because the PM
  grepped the first `summary` in the `jira_get_issue` output. Re-tagged with the PO's yes
  (MES-192 33327). Read the summary from the top-level field.
- **The MES-189 plan handoff** named the wrong worktree path (MES-199's). Corrected inline in the
  same comment.

## S16-6 — the JSON-RPC-over-HTTP ruling and the peer SDKs

Two PO questions during MES-199 and MES-189 compared our behaviour with the reference SDKs
(TypeScript, Python, Go and Ruby, all at their checked-out heads).

- **`{result, error: null}`.** Python (run), Go and Ruby (read) treat it as success. TypeScript
  refuses it (`.strict()`, read). MES-199 keeps it a success, per MES-190's ruling.
- **Both members present.** Python lets `error` win (run), Go keeps both, Ruby lets `result` win,
  TypeScript refuses. MES-199 refuses.
- **A 4xx/5xx reply with a JSON-RPC error body.** All four lose the JSON-RPC code: they stop at
  the HTTP status. None retries on -32022 or reacts to -32020. All four predate 2026-07-28.

**PO ruling (2026-10-18).** MCP over HTTP is JSON-RPC carried over HTTP. On a non-2xx reply the
client reads the body and passes the JSON-RPC error to the caller; the peers that drop it are
wrong. MES-189 does this when the error's id matches the request; the `id: null` case is
**MES-206**.

**The conformance harness on these paths** (pinned 0.2.0-alpha.11). Only one client check grades a
non-2xx JSON-RPC error: `ClientRetrySupportedVersion`, whose worst outcome is WARNING and which
cannot tell a real retry from any later request. No client check grades the reaction to -32020.

Side finding, not ours: the Python SDK's synthetic 404 error uses code `32600`, not `-32600`
(`streamable_http.py:413-416`).

## S16-7 — smaller findings, filed

| ticket | what | from |
|---|---|---|
| MES-202 | G33 controls C1–C23 and C25 should assert their own cause, as C27a does | MES-192 R6 |
| MES-203 | cited client wait sites, the 67 deferred gate-7 declarations, server-side waits, sync `GenServer.call` sites | MES-191 |
| MES-204 | HTTP client: a 200 `application/json` body that is a JSON array, number or null crashes the transport with `FunctionClauseError` and kills the client | MES-197 Q7 |
| MES-205 | re-record the strict_connect probe and Discount 1, now lapsed | MES-189 plan |
| MES-206 | an `id: null` JSON-RPC error on a non-2xx reply stays a transport error | PO, 2026-10-18 |
| MES-207 | `mix hex.audit` exits 1: two new bandit 1.12.5 advisories | end-of-sprint sweep |
| MES-208 | Boundary sweep drops failures numbered 100+, capping `reddened_total` at 99 | end-of-sprint sweep |

**Not ticketed, for the PO at planning:**

- **MES-198 O1:** over stdio, the server sends no -32700/-32600 reply to an unparseable or invalid
  message.
- **MES-197 O1:** `decode_message`'s `@spec` understates its input.
- **MES-197 O2, stdio half:** an `id: null` error leaves pending callers to time out. MES-206
  covers only HTTP, where the POST correlates it; stdio has no such correlation.
- **The `client.ex` moduledoc** does not describe the new caller-facing error shapes from MES-197
  and MES-189 (`:malformed_response`, protocol errors from a 4xx). The moduledoc's lines are
  cited by pinned windows, so adding a paragraph moves every one of them.
- **A stale OC census row:** `HttpServerHeaderMismatch400` has been FAILURE since MES-155.

## S16-8 — acm observations

- An acm restart forgets turn handles; `seat_status` returned unknown for an exited handle
  overnight. The transcript under `runs/` is the fallback.
- `seat_status` needs the full handle `SEAT/TICKET/id`.
- An emfa-wrapper outage during the MES-191 build turn was invisible to `seat_status`; nothing
  could be posted until the operator restarted the wrapper (ACM-38 33073).
- An engine timeout's SIGTERM left `dispatch.ex` mutated in MES-176's worktree; CC disclosed and
  restored it. Mutation runs must restore in `finally` and assert a clean tree after.

## S16-9 — PO decisions this sprint

- Scope, epics MES-201, MES-133 Done, MES-154 folded into MES-200 (planning, 32571).
- MES-192's guard runs under gate 5, not gate 8.
- MES-192 CR switched to claude after the codex `cyber_policy` refusals (2026-10-15).
- MES-191 before MES-192's merge (2026-10-16), with the disclosed D10 exception for its 67
  declarations.
- `2.0.0-dev.95` re-tagged (2026-10-17).
- MES-199 and MES-189 run back to back, no pause (2026-10-18).
- MES-189 Q1–Q8 (33719), and the JSON-RPC-over-HTTP ruling with MES-206 (2026-10-18).

## S16-10 — behaviour changes shipped (for the next release notes)

- **Client, malformed error reply:** the caller fails at once with `:malformed_response`
  instead of waiting out its timeout.
- **Protocol:** a response carrying both `result` and a non-null `error` is refused as -32600.
  `{result, error: null}` is still a success.
- **Client over HTTP:** a JSON-RPC error on a 4xx/5xx reply whose id matches the request reaches
  the caller as `%MCP.Error{}`. The -32022 unsupported-version retry and the -32020 tool-list
  refresh now work over HTTP as they do over stdio. Other non-2xx replies still return
  `{:http_error, status, body}`.
- **Plug:** error `data` is a plain rule string, never `inspect()` of an Elixir term; adapter
  read failures are classified; invalid UTF-8 never reaches the wire.
- **No dependency change** (but see MES-207).

## End-of-sprint sweeps (at the final tip `2.0.0-dev.100` / `ae4b978`)

**Dependency-advisory sweep (the two-step gate 6).** hex 2.5.1 (`mix hex`: `Hex v2.5.1`). The
script is `docs/procedure/gate-6.md`, run on main at ae4b978 with a clean tree. Log:
`/tmp/s16close/gate6.log`.

- **6a:** 22 of 22 known advisory ids present in the baseline audit. The cache is intact.
- **6b:** `mix hex.audit` exits **1**:

```text
bandit 1.12.5 - EEF-CVE-2026-105659 (HIGH)
  HTTP/2 blocked-send deadlines reset on every WINDOW_UPDATE, letting a trickle pin stream processes indefinitely in Bandit
bandit 1.12.5 - EEF-CVE-2026-105660 (MEDIUM)
  Unvalidated HTTP/1 request-target authority lets a client choose conn.host and conn.port in Bandit
```

- **RED. Ticketed as MES-207** (backlog), not fixed in place, per step 3.

**Publication sweep (`mix origin.sync`, run point c).** GREEN at `2.0.0-dev.100`. Log:
`/tmp/s16close/origin_sync.log`.

```text
  GREEN C4  that tag is on origin, as the same object
        2.0.0-dev.100 on origin = 8800b7f9771a, the same object
  GREEN C5  the tag peels to an ancestor-or-equal of local main
        2.0.0-dev.100 peels to a commit main contains
  IN SYNC — main and the version's tag are both published as held.
```

**Boundary-liveness sweep (`mix conformance.sweep --check`).** The last sweep tip was 32b468a
(Sprint 15). The three skip conditions (log `/tmp/s16close/skip_conditions.log`):

- (a) `git diff --name-only 32b468a...ae4b978 -- lib/` lists 4 files: `client.ex`, `protocol.ex`,
  `transport/streamable_http/client.ex` and `transport/streamable_http/plug.ex`.
- (b) `git diff --name-only 32b468a...ae4b978 -- test/ test/support/ conformance/lib/` lists 26
  files: 7 under `conformance/lib/` and 19 under `test/`.
- (c) `mix conformance.sweep --host`: `node=v24.13.0 harness=available` both in the committed
  table and on this host; HOST MATCHES, exit 0.

Conditions (a) and (b) are non-empty, so the sweep is owed and was run.

The run:

- Command: `mix conformance.sweep --check --out /tmp/s16sweep/full.json`.
- Where: a dedicated worktree at ae4b978, started detached.
- When: 05:31:03 to 07:39:24 UTC, so 128 min 21 s.
- Result: **exit 0**. Afterwards the worktree was clean, so `lib/` was restored. The worktree was then
  removed.

```text
== BASELINE PROBE (reported not raised on) ==
  unchanged — the probe's baseline fingerprint matches control.probe.
== L2 CARRIED FORWARD (reported not raised on) ==
  3 LIVE verdict(s) decided by L2 stand over a probe that moved NOTHING this run —
  carried forward from the record, not re-measured:
    MCP.Server.Connection
    MCP.Server.NotificationCollector
    MCP.Transport.Stdio
== VERDICT DIFF (AC5 — this is the loud one) ==
  none — every verdict field reproduces byte-exactly.
```

The run also printed: guards 23–27 scanned at 29 / 19 / 19 / 194 / 194, the same as Sprint 15, and
the baseline `24 doctests, 2023 tests, 0 failures`.

**What was actually re-measured.**

- **L1:** all 50 directions.
- **L2:** fired on 29 directions. The probe's baseline is sighted, not uniform: the run reports
  `distinct: 15, scenarios: 15`. 26 of those 29 verdicts were measured this run.
- **Carried forward:** the other 3 L2 verdicts were not re-measured (MES-178).

Verdicts at ae4b978: 31 live (21 by L1, 10 by L2) and 19 dead (by L2). This is the same split as at
32b468a and 44d1cbe.

**The measurement delta.** All 50 directions differ on measurement fields only. The committed table
still holds the 1790-test measurements: Sprint 15 did not refresh it. So the delta runs from
`24 doctests, 1790 tests` to `24 doctests, 2023 tests` and covers the test additions of both
Sprints 15 and 16.

- **25 directions gained exactly one reddened test, `MCP.Conformance.StringCitationsTest`.** This
  is the MES-192 citation guard, which is new since the committed table. A `lib/` mutation moves
  bytes under a cited line, so the guard goes red. It is outside the live column, so no
  `live_units` moved because of it.
- Apart from that test, 12 live directions moved their L1 counts (committed → this run):

| Direction | `reddened_total` | `live_units` |
|---|---|---|
| `MCP.Client` | 34 → 55 | 12 → 32 |
| `MCP.Protocol.Error (decode)` | 20 → 32 | 18 → 30 |
| `MCP.Protocol.HeaderMirror (decode)` | 7 → 8 | 4 → 5 |
| `MCP.Protocol.HeaderMirror (encode)` | 55 → 56 | 38 → 39 |
| `MCP.Protocol.Messages.Discover (decode)` | 33 → 35 | 32 → 33 |
| `MCP.Protocol.Messages.Discover (encode)` | 21 → 23 | 20 → 21 |
| `MCP.Protocol.Messages.Request` | 37 → 58 | 34 → 54 |
| `MCP.Protocol.Meta` | 99 → 99 (capped, see below) | 98 → 97 |
| `MCP.Protocol.decode_message/1` | 86 → 99 (capped) | 80 → 93 |
| `MCP.Server.Dispatch` | 99 → 99 (capped) | 78 → 76 |
| `MCP.Transport.SSE (decode)` | 53 → 77 | 42 → 66 |
| `MCP.Transport.StreamableHTTP.Plug` | 63 → 99 (capped) | 36 → 71 |

All 12 were live before and are live now. The large gains (`MCP.Client`, `Request`, `Plug`,
`Error (decode)`) are consistent with the MES-189/197/198/199 tests landing on the paths they fixed.
As at Sprint 15, units are keyed by `file:line`, so the unit lists were not reconciled test by test.

**Drift found: the sweep caps at 99 failures. Ticketed as MES-208** (backlog), not fixed in place.
Four directions report `reddened_total` 99 exactly, while their own `suite_summary` reports more:

| Direction | `suite_summary` failures | `reddened_total` |
|---|---|---|
| `MCP.Protocol.Meta` | 176 | 99 |
| `MCP.Server.Dispatch` | 146 | 99 |
| `MCP.Protocol.decode_message/1` | 106 | 99 |
| `MCP.Transport.StreamableHTTP.Plug` | 101 | 99 |

All four have `unlocated_failures` 0. The cause, read from source:

- ExUnit's `with_counter/2` (`ex_unit/formatter.ex:719–729`) pads a failure counter with two
  spaces below 10, one below 100, and **none from 100 on**.
- `failure_module/1` in `boundary_sweep.ex` matches headers only by `\A\s+\d+\) `, which needs at
  least one leading space.

So failures 100 and above are dropped silently: they are neither keyed nor counted as unlocated. The
committed table already carries the cap (Meta at 139 failures and Dispatch at 124, both recorded as
99). No verdict is wrong as a result: all four are live by L1, and dropped units can only lower a
live count. But their `reddened_*` and `live_units` fields understate the measurement.

The table refresh is left, as at Sprints 14 and 15, to the ticket that regenerates the table. It
should follow MES-208, so that it does not commit capped figures again.

## Open at close

- **Seat-file edits, still owed by the operator** (from S14-1). The PM does not write seat files.
- **The WON'T Do unassign rule** is to be confirmed at the next WON'T Do of an assigned ticket.
- **ACM-38:** `RELEASE_DISTRIBUTION=none` and `COOKIE` mode 600 (S16-4); a fresh-session primitive
  (S16-3).
- **Backlog for Sprint 17 planning:** MES-202–208 and the unticketed items in S16-7, plus the
  chains named at Sprint 16 planning: MES-173 → 179 → 150 → 178, and MES-194 → 195, 193, 196, 200.
