# Sprint 17 — findings register

**Sprint goal, as set at planning on 2026-10-19.** Sprint 17 is Jira sprint 2148 on board 267.
Its planning page is Confluence 339017730. The PO ruling that scoped it is MES-207 33839 (Q1–Q8,
all YES). The goal:

> Clear the bandit advisories; make the boundary sweep count every failure and refuse unsafe
> repairs (emit-spec, --verify); then close the HTTP client's remaining error-body gaps, re-record
> the strict_connect probe and tighten the G33 controls.

The planned order was MES-207, 208, 173, 179, 204, 206, 205, 202, with MES-210 as the stretch
item. On 2026-10-24 the PO ruled MES-215 (a gate-5 flake that reddened MES-179's binding review)
in and first, ahead of the parked MES-179. On 2026-10-25 the PO moved the sprint end from 11:00Z
to 13:00Z, which brought MES-210 in. Ten tickets merged, `2.0.0-dev.101` → `2.0.0-dev.110`, plus
MES-213 (a sub-task landed inside MES-207's squash). Every turn was started through acm.
CODE_CREATOR ran on claude and CODE_REVIEWER on codex throughout.

| dev | ticket | what landed |
|-----|--------|-------------|
| .101 | MES-207 (+213) | bandit 1.12.5 → 1.13.0 and the mix.exs floor raised to `~> 1.13` (clears EEF-CVE-2026-105659 HIGH, -105660 MEDIUM). MES-213: the Plug's `with` else-paths sent on the pre-read conn, which bandit 1.13's stale-conn guard turns into a 500 |
| .102 | MES-208 (+150) | The boundary sweep records every test through its own ExUnit formatter (MCP.Conformance.ExUnitRows) instead of parsing failure headers, so failures numbered 100+ are counted; GUARD 34 refuses a run whose census does not balance |
| .103 | MES-173 | `--emit-spec` keeps existing entries verbatim and refuses to re-count GUARD 26; `occurrences` 0 is refused everywhere (widened GUARD 27) |
| .104 | MES-215 | Test listeners bind port 0 and read the port back, so no check-then-bind race (`:eaddrinuse`); 35 gate-7 declarations added |
| .105 | MES-179 | A control drives the real `mix conformance.sweep --verify`: exit 0 if and only if the PASS line prints, each red names its guard, and a short or empty population is refused |
| .106 | MES-204 | A 200 `application/json` body that is an array, number or null fails the request with a transport error instead of crashing the client; decode_message's `@spec` corrected (MES-197 O1) |
| .107 | MES-206 | A non-2xx reply carrying a JSON-RPC error with id null reaches the posting caller as `%MCP.Error{}`, correlated by the POST |
| .108 | MES-205 | Client strict_connect probe and discounts re-recorded after MES-189; D5b-i drive_policy lapses on 10 rows, dispositions stand |
| .109 | MES-202 | G33 controls C1–C23, C25a and C25b each hold their own cause (row key and detail), not just the refusal kind |
| .110 | MES-210 | A stdio server answers a line that is not JSON with -32700 and JSON that is not a request with -32600 (readable id or null), one framed line each, instead of only logging it |

**`lib/` changed in five files** (`git diff --stat a50d3ac f2d780a -- lib/`: 154 insertions, 17
deletions): `protocol.ex`, `server/connection.ex`, `transport/stdio.ex`,
`transport/streamable_http/client.ex` and `transport/streamable_http/plug.ex`. **Dependencies
changed once**, on MES-207: bandit 1.13.0, hpax 1.0.4 → 1.1.0, thousand_island 1.5.0 → 1.6.0. The
suite grew from 2023 to 2068 tests (`24 doctests, 2068 tests, 0 failures` at the tip, on every
seed).

**Gate 5 was 22 seeds on every ticket**, 0 and 1000001–1000021, run strictly serially and alone,
on both the CC and the binding CR run. Two red seeds were recorded red (S17-2); none was re-run to
green as evidence.

## S17-1 — bandit 1.13 exposed a Plug bug, and three recorded mutations that had stopped biting (MES-207)

- **The bump was not a lock-only change.** Seed 0 went red with 5 failures. bandit 1.13.0's
  stale-conn guard (adapter.ex:397, bandit #668) raises because `plug.ex`'s `handle_post/2` sent
  error replies on the conn from *before* the body read. On bandit ≥ 1.13, every Plug error path
  except body_too_large would have become a bare 500. The PM measured it: 1 raise on the branch, 0
  on main. The PO ruled it a sub-task of the ticket: MES-213, landed in the same squash.
- **The fix moved a byte anchor**, so the PM ordered the recorded red sets of all 11 plug.ex
  mutations re-run at main and at the tip. 0 were lost. But **M9h, M9f and M10's recorded reddens hit
  0 of N already at main**: stale, probably since MES-161 (bb68d9f). Filed **MES-214**. On
  2026-10-24 the PO placed it in the next sprint.
- Lesson: a dependency bump can change the semantics our code relies on. The gate-5 sweep caught
  it, but only because the bump ran the whole suite against the new adapter.

## S17-2 — the `free_port` flake reddened a binding review (MES-215)

- `:eaddrinuse` at `client_conformance_test.exs:134`. Tests picked a free port and bound it later,
  so a concurrent async test could take it first.
- **Seen twice.** On MES-173, CC recorded 21/22 seeds and re-ran the red seed to green. The re-run
  was disclosed and not counted as evidence; the PM filed MES-215. On MES-179, the CR's binding run
  went red on seed 1000001. Recorded red, not re-run; MES-179 was parked in IN CODE REVIEW.
- The PO ruled MES-215 first (2026-10-24). It replaced 13 pick sites with port-0 listeners. Its
  gate-7 declarations could not be added line-neutrally, because `mix format` re-wraps long tags.
  So the ticket stopped three times (r0, r1, r2) on moved G32/G33 windows and controls literals.
  CR then rejected it once (F1: two tags whose crosswalk axis is `contradicts`; F2: a missed bare
  continuation). The class sweep ordered for F2 found **20 more stale continuations** that the
  earlier rounds had missed.
- Filed along the way: **MES-217** (G33 `--resolve` defect) and **MES-218** (an attribution
  capture read the pre-fix tree).
- MES-179 was then re-reviewed at the new main, and its binding 22 seeds were green.

## S17-3 — MES-208: the PO chose "record every test"

- The plan offered a tighter header regex plus a census guard. The PO ruled (2026-10-21): *"We have
  to record every test, therefore we have to accept option 2"*. That meant our own ExUnit formatter
  in place of transcript parsing. The existing MES-83 formatter was reused.
- CR F1: an ANSI-coloured forged summary line bypassed `summary_count`, because `parse_summary`
  stripped ANSI and `summary_count` did not. Fixed in r1.

## S17-4 — review rounds on MES-179 and MES-210

- **MES-179**, CR REJECT 34244–52:
  - F1: an `exit` or `throw` escaped the rescue.
  - F2: no equality control for guard 27.
  - F3: the positive-integer, 5-key predicate was not implemented.
  - F4: a GUARD 999 mislabel.
  All four were accepted (ruling 34253) and closed in r1.
- **MES-210**, CR REJECT 34564–65:
  - **F1:** `response_shaped?/1`'s method-present limb was untested. Mutant X1 survived the
    *whole* suite. Fixed test-only in r1: rows 77, 78 and 79, each shown to bite on its own.
  - **F2:** the unreadable-id error reply carries `id: null`, which JSON-RPC 2.0 §5 requires. But
    the pinned MCP 2026-07-28 schema has `JSONRPCErrorResponse.id?: RequestId`, where `RequestId`
    is `string | number`, so null does not validate. CR showed the TS SDK 1.32.1 schema rejecting
    it. Neither the TS nor the Python reference SDK sends null; Python uses the placeholder
    `"server-error"`.
  - **PM ruling 34566:** keep null in MES-210. It is the briefed contract and keeps parity with
    the Plug, which has sent null since MES-157. Filed **MES-226** for both transports, with a PO
    yes/no question.
- **MES-210 census correction**, CC-measured: a lone `\r` line arrives empty (the io server reads
  `\r\n` as a line end) and gets no reply. The plan had listed it under -32700.

## S17-5 — PM brief and dispatch errors this sprint

- **MES-179:** the dispatch named an `all` mode that the controls script does not have.
- **MES-205:** the plan brief omitted the 22-seed list. It was corrected at ratification (34515).
- **MES-205:** the close-out misstated its diffstat (387/420; actual 386/418). CR F1, non-blocking,
  corrected in the merge record.
- **MES-210:** the first close-out's timing looked impossible against the seed mtimes. The PM
  settled it from the transcript (every command in the foreground, one at a time), not from the
  mtimes alone.

## S17-6 — environment: `node` missing from the `env -i` PATH

- On MES-210, both CC's first gate-5 seeds and CR's first gate-7 run used an `env -i` PATH
  without node's directory:
  - gate 5 reported `2065 tests, 0 failures (3 excluded)`;
  - gate 7 reported `OC-GATE REFUSE (61)` with `harness_unavailable`.
- Both instruments refused loudly, as designed (MES-56, gate 7's fail-closed rule). Neither run was
  counted. The full set was re-run from seed 0 with node on PATH.
- Practice from here: put node's bin directory on the `env -i` PATH before the first command. The
  PM briefs now say so.

## S17-7 — smaller findings, filed (all backlog)

| ticket | type | epic | finding |
|---|---|---|---|
| MES-211 | Bug | 201 | Client (stdio): a JSON-RPC error with id null leaves every pending caller to time out (MES-197 O2, stdio half) |
| MES-212 | Task | 201 | client.ex moduledoc: the caller-facing error shapes from MES-197 and MES-189 (rides with the next client.ex re-pin: 710 G33 cites) |
| MES-214 | Task | 118 | M9h, M9f, M10 recorded reddens hit 0 of N at main |
| MES-216 | Task | 118 | Reconcile the worktree procedure with GWP v3 as amended |
| MES-217 | Bug | 118 | G33 `--resolve` rewrites a refused address's ledger key to a moved window's (MES-215 r1) |
| MES-218 | Task | 118 | ET-CC attribution citations for client_conformance and routing_headers still read at the 584e115 capture (MES-215 D1) |
| MES-219 | Bug | 201 | Client (SSE and stdio): a non-object JSON message is dropped and the caller waits out its timeout (MES-204) |
| MES-220 | Bug | 201 | Client (HTTP): a 200 JSON body that is a JSON string containing a JSON-RPC response (MES-204) |
| MES-221 | Bug | 201 | Client: a tools/call reply with result null kills MCP.Client (`input_required?/1` BadMapError, MES-206 F3) |
| MES-222 | Bug | 201 | Client (HTTP): a null-id JSON-RPC error on a 200 JSON or SSE reply is dropped (MES-206 F1) |
| MES-223 | Task | 201 | Client (stdio): a null-id JSON-RPC error is dropped and every caller waits out its timeout (MES-206 F2) |
| MES-224 | Bug | 201 | stdin EOF before an in-flight reply → Connection `noproc` crash (MES-210 O1) |
| MES-225 | Task | 201 | The default Logger writes to stdout in stdio server mode (MES-210 O2) |
| MES-226 | Bug | 201 | `id: null` error replies do not validate against the pinned MCP schema (MES-210 F2); PO yes/no open |
| MES-227 | Bug | 209 | plug_crypto 2.1.1 advisory EEF-CVE-2026-105963 (this close's gate 6) |
| MES-228 | Bug | 118 | Boundary sweep refused at direction 6/50: the ExUnitRows formatter wrote no rows (this close's step 4) |

**MES-211 and MES-223 overlap**: both are the client over stdio dropping a null-id error. Merge
them, or rule one a duplicate, at Sprint 18 planning. MES-226's answer decides both, since it
settles whether a server sends null at all.

## S17-8 — PO decisions this sprint

- Scope Q1–Q8, all YES (2026-10-19, 33839). Among them: bandit floor `~> 1.13`, MES-150 folded into
  MES-208, MES-210 as the stretch item, and MES-178, MES-203 and the 194 chain deferred to
  Sprint 18.
- MES-213 as a sub-task of MES-207 (2026-10-19).
- MES-208 option 2, "record every test" (2026-10-21).
- 2026-10-24:
  - MES-215 first, then MES-179 re-reviewed at the new main.
  - Remove each merged worktree at every merge (`git worktree remove`, no `--force`, then
    `git branch -D`).
  - File the procedure Task (MES-216).
  - MES-214 goes to the next sprint.
- Sprint end moved from 2026-10-25 11:00Z to 13:00Z (2026-10-25).

## S17-9 — behaviour changes shipped (for the next release notes)

- **Dependency:** bandit (optional) now requires `~> 1.13`.
- **Plug:** error replies are sent on the conn returned by the body read, so they reach the wire as
  their JSON-RPC error on bandit ≥ 1.13, instead of a bare 500.
- **Client over HTTP:**
  - A 200 JSON body that is an array, number or null fails that request with a transport error;
    the client no longer crashes.
  - A non-2xx JSON-RPC error with id null reaches the posting caller as `%MCP.Error{}`.
- **Server over stdio:**
  - A line that is not JSON gets `{"jsonrpc":"2.0","id":null,"error":{"code":-32700,…}}`.
  - JSON that is not a request or notification gets -32600, carrying its readable id or null.
  - A malformed reply is still dropped.
  - Before this sprint, all of these got silence. MES-226 may change null to an omitted id.

## End-of-sprint sweeps (at the final tip `2.0.0-dev.110` / `f2d780a`)

**Dependency-advisory sweep (the two-step gate 6).** hex 2.5.1 (`mix hex.info`: `Hex: 2.5.1`,
Elixir 1.19.5, OTP 28.5.0.3). Ran the `docs/procedure/gate-6.md` script on main at f2d780a with a
clean tree, 11:41:08–11:41:11Z. Log: `/tmp/s17close/gate6.log`.

- **6a:** 22 of 22 known advisory ids present in the baseline audit. The cache is intact.
- **6b:** `mix hex.audit` exits **1**:

```text
Advisories:
  plug_crypto 2.1.1 - EEF-CVE-2026-105963 (MEDIUM)
    aka: CVE-2026-105963, GHSA-ffw9-w85g-f2vh
    Secret key base exposed in stack trace arguments on wrong-typed Plug.Crypto arguments
    https://osv.dev/vulnerability/EEF-CVE-2026-105963

Found packages with security advisories
```

- **RED. Ticketed as MES-227** (backlog, epic MES-209), not fixed in place, per step 3.
  plug_crypto is transitive, via `plug ~> 1.16`, and is one of the 21 packages in 6a's
  unvalidated residual.

**Publication sweep (`mix origin.sync`, run point c).** GREEN at `2.0.0-dev.110`. Log:
`/tmp/s17close/origin_sync.log`.

```text
  GREEN C4  that tag is on origin, as the same object
        2.0.0-dev.110 on origin = 738edd12a9d3, the same object
  GREEN C5  the tag peels to an ancestor-or-equal of local main
        2.0.0-dev.110 peels to a commit main contains

  IN SYNC — main and the version's tag are both published as held.
```

**Boundary-liveness sweep (`mix conformance.sweep --check`).** The last sweep tip was ae4b978
(Sprint 16). The three skip conditions (log `/tmp/s17close/skip_conditions.log`):

- (a) `git diff --name-only ae4b978...f2d780a -- lib/` lists 5 files: `protocol.ex`,
  `server/connection.ex`, `transport/stdio.ex`, `transport/streamable_http/client.ex` and
  `transport/streamable_http/plug.ex`.
- (b) `git diff --name-only ae4b978...f2d780a -- test/ test/support/ conformance/lib/` lists 23
  files.
- (c) `mix conformance.sweep --host`: `node=v24.13.0 harness=available` both in the committed
  table and on this host; HOST MATCHES, exit 0.

Conditions (a) and (b) are non-empty, so the sweep is owed and was run.

The run:

- Command: `mix conformance.sweep --check --out /tmp/s17sweep/full.json`.
- Where: a dedicated worktree detached at f2d780a, started with `setsid nohup` from `env -i`,
  with node on PATH and decoy credentials only.
- When: 11:41:59 to 11:57:54 UTC, so 15 min 55 s.
- Result: **exit 1, REFUSED by GUARD 34 at direction 6 of 50**. Afterwards the worktree was
  clean, so `lib/` was restored. The worktree was then removed.
- Logs: `/tmp/s17sweep/run.log`, persisted with the refused run's transcript to
  `~/sprint_artifacts/s17/s17sweep/`.

```text
  guards 23-27 scanned %{guard_23_scanned: 29, guard_24_scanned: 19, guard_25_scanned: 19, guard_26_scanned: 194, guard_27_scanned: 194}
  baseline probe: sighted %{not_a_response: 3, distinct: 15, scenarios: 15, results: 11, expected_errors: 1}
  baseline: 24 doctests, 2068 tests, 0 failures
  [1/50] MCP.Client                                     ... live 44 | live (L1)
  [2/50] MCP.Protocol.Capabilities.ClientCapabilities (decode) ... live 0 | dead (L2)
  [3/50] ... ClientCapabilities (encode)                ... live 5 | live (L1)
  [4/50] ... ServerCapabilities (decode)                ... live 6 | live (L1)
  [5/50] ... ServerCapabilities (encode)                ... live 9 | live (L1)
  [6/50] MCP.Protocol.Error (decode)
** (RuntimeError) GUARD 34: no_artefact — the formatter wrote no readable rows file
REFUSING this run: its rows do not account for every test (MES-208).
```

**What happened at direction 6.**

- The mutated `mix test --seed 0` itself completed: `24 doctests, 2068 tests, 35 failures`.
- But the ExUnitRows formatter wrote no rows file, and its transcript has **neither** the
  `[etcc-rows] wrote …` line nor the `[etcc-rows] FAILED to write …` line. Earlier runs print
  the `wrote` line. So the formatter never reached its own success or rescue path.
- GUARD 34 refused, as MES-208 designed it to: no false census was taken. But the instrument
  cannot measure this direction, which the pre-MES-208 header parser measured every sprint.
- **Ticketed as MES-228** (Bug, epic MES-118), not fixed in place, per step 4.

**What this leaves unmeasured.**

- No verdict at f2d780a was re-measured past direction 5, and the table was not diffed. The
  five directions measured give live, dead, live, live, live, the same verdicts as the committed
  table in the same order. Only the verdict field was compared; the measurement fields were not
  diffed.
- The last completed sweep tip therefore **stays ae4b978**. The "one sprint" bound in step 4 is
  broken until MES-228 lands and a full sweep completes.
- Gate 8 (`--verify`) re-measures nothing, so it is unaffected.
- **MES-228 has to go before the regeneration chain** (MES-194 → 195, 193, 196, 200), which
  regenerates tables through this sweep.

## Open at close

- **Seat-file edits, still owed by the operator** (from S14-1). The PM does not write seat files.
- **The WON'T Do unassign rule** is still unconfirmed. MES-150 was already unassigned when it went
  WON'T Do.
- **ACM-38:** `RELEASE_DISTRIBUTION=none`, `COOKIE` mode 600, and a fresh-session primitive.
- **PO questions open:** MES-226 (omit the id, or keep null?).
- **The Sprint 17 boundary sweep is not complete** (MES-228). Its last completed tip stays ae4b978.
- **Backlog for Sprint 18 planning:**
  - **MES-228 first**: the sweep instrument cannot complete, and the regeneration chain depends on
    it.
  - The Sprint 18 theme named at Sprint 17 planning: the regeneration chain MES-194 → 195, 193,
    196, 200, plus MES-178 and MES-203.
  - MES-214, at the PO's 2026-10-24 ruling.
  - MES-211, 212, 216–227.
