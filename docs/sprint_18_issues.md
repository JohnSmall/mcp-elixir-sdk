# Sprint 18 — findings register

**Sprint goal, as set at planning on 2026-11-08.** Sprint 18 is Jira sprint 2280 on board 267.
Its planning page is Confluence 355434522. The PO approved the list on 2026-11-08 (Q1–Q4, all
YES): the bandit floor goes to 1.14.1 (MES-227); MES-223 is closed as a duplicate of MES-211;
MES-194 is split into MES-229 (generator), MES-230 (re-capture) and MES-231 (rebuild, Sprint 19).
The planned order was MES-227, 228, 178, 226, 211, 229, 230, with MES-214 as the stretch item.

The intended end, 2026-11-09, passed with MES-228 parked behind a gate-7 red from main (S18-2). The
PO moved the end to 2026-11-13. Eight tickets merged, `2.0.0-dev.111` → `2.0.0-dev.117`, the seven
planned ones that finished plus MES-232, which the PO ruled in on 2026-11-11. **MES-230 carried
past the end date** and merged on 2026-11-14 as `2.0.0-dev.118` (S18-7); MES-214 was not started. Every turn was started through acm. CODE_CREATOR ran on
claude and CODE_REVIEWER on codex throughout, until codex ran out of credits on 2026-11-12 (S18-8).

| dev | ticket | what landed |
|-----|--------|-------------|
| .111 | MES-227 | bandit 1.13.0 → 1.14.1 (floor `~> 1.14 and >= 1.14.1`) and plug_crypto 2.1.1 → 2.2.1 in the lock: clears the 13 hex.audit advisories that turned gate 6 red at the Sprint 17 close |
| .112 | MES-232 | The Plug trims OWS (SP/HTAB) from routing-header values before the -32020 comparison, independently of the adapter; the stale pending `http-header-validation` classification is retired, behind a pinned `@retired` set |
| .113 | MES-228 | ExUnitRows survives a linked-process death (`{:EXIT, pid}` failure kind); a handler fault refuses the run as incomplete instead of killing the formatter silently (the Sprint 17 close's GUARD 34 refusal) |
| .114 | MES-178 | The ET-CC L2 probe reaches Connection, NotificationCollector and Stdio; the sweep re-measures every `byte_probe` block, isolates each scenario and refuses a blind notification baseline |
| .115 | MES-226 | ADR-004: an error reply whose request id cannot be read carries `"id": null` (JSON-RPC 2.0 §5), on the PO's 2026-11-08 ruling; docs only. Confluence mirror 359170077 |
| .116 | MES-211 | A JSON-RPC error with a null id answers the one pending request; with none or several pending it is logged and every caller keeps its timeout (PO ruling (b), 35079) |
| .117 | MES-229 | `ETCCRegister.build/1` emits each test row's located line and reproduces the committed register byte for byte; refuses a row whose test identity cannot be established; f4, identity and `all` controls |

**`lib/` changed in three files** (`git diff --stat 74883c6 dea3afe -- lib/`: 59 insertions, 4
deletions): `client.ex`, `protocol/messages/response.ex` and `transport/streamable_http/plug.ex`.
**Dependencies changed once**, on MES-227. The suite grew from 2068 to 2096 tests
(`24 doctests, 2096 tests, 0 failures` at the tip).

**Gate 5 was 22 seeds on every merged ticket**, 0 and 1000001–1000021, run serially, on both the
CC and the binding CR run.

## S18-1 — gate 6 green again, and a sentence of the PM's own read as a PO ruling (MES-227)

- The Sprint 17 close left gate 6 red (plug_crypto 2.1.1). MES-227 cleared it; 6a 22/22, 6b exit 0.
- PM comment 34786 said the 6a sentinel "covers all 13" new advisories. It was the PM's own
  wording, and false: two of the ids are not reachable at `d697093`. The PO withdrew it on
  2026-11-09 (Q2 NO) and `gate-6.md` stayed untouched. **Lesson:** do not fold PM description into
  a record of a PO ruling.
- The container rebuild had restored hex 2.5.0, below the 2.5.1 floor; re-upgraded with PO approval.

## S18-2 — a dependency-only merge turned main's gate 7 red (MES-227 → MES-232)

- MES-227 changed `mix.lock` only, so gate 7 did not apply to it. Under bandit 1.14.1 the
  official census for `http-header-validation` went 13/1 → 14/14, because bandit 1.14 trims
  trailing OWS on HTTP/1 and our code did not. Gate 7 then refused MES-228 with
  CLASSIFICATION_STALE, for a change no ticket on the branch had made.
- The PO ruled a fix ticket first (MES-232) and, on 2026-11-12, that **gate 7 runs on
  `mix.lock`-only changes** → **MES-236** (backlog; `mix.exs`-only is not in the ruling).
- MES-232 also found that `classification_test.exs` refused committed dated censuses naming the
  retired id; PM ruling (B) pinned a `@retired` set byte-exact with two controls.

## S18-3 — MES-228 fixed the Sprint 17 sweep refusal

- Root cause (H1): `to_string({:EXIT, pid})` raised inside the formatter's `handle_cast`, so the
  formatter died and wrote nothing. Fix and control: main RED, fix GREEN, M1/M2 RED.
- Full sweep on the branch: 50/50 directions, 0 verdicts moved (2 h 23 m).
- CR finding: the crosswalk controls' 14 statements are refused by G30 on main → **MES-234**
  (backlog). **G30 is red at main** and was skipped by every ticket this sprint on that basis.

## S18-4 — MES-178: carried-forward verdicts proved by probe, and a coherence guard split out

- The three LIVE-by-L2 carried-forward directions were proved by probe scenarios X1–X3, with no
  verdict move. CR finding F1: the X1–X3 baseline accepted an empty or timed-out read as
  "sighted"; fixed sweep-side with no re-sweep. Full sweep EXIT 0, verdict diff none.
- The byte_probe coherence guard changes gate 8, so it was split to **MES-235**; the PO ruled
  option A (the guard goes in `--verify`).

## S18-5 — MES-226 and MES-211: the null id, recorded and then consumed

- ADR-004 records the PO's ruling to keep `"id": null` (JSON-RPC 2.0 governs, even though the TS
  SDK 1.32.1 schema rejects it). The PM applied the ruling's reason to -32020, -32602 and -32603
  as well, and reported that to the PO. Follow-up **MES-237** (backlog).
- MES-211 measured the peers before the PO ruled: Python, TypeScript and Ruby drop such an error
  (c); Go dies on it (a in effect); none ties it (b). The PO chose (b). Residual, sanctioned in the
  merge record 35126: an *unrelated* null-id error answers the single pending request.
- MES-211 also changed `response.ex:15` (`id` may be nil) outside its plan, for a dialyzer
  pattern-match refusal; sanctioned at merge.

## S18-6 — MES-229: the register had been hand-maintained since MES-161

- `bb68d9f` (MES-161) hand re-resolved the joined `line` field, and later commits edited
  decisions without a rebuild, so the `reproduce` control was red at main when MES-229 started.
- **PM ruling (a): `build()` emits each test's located line**, not the captured one. It changes no
  DoD gate (CR-verified), so it stayed a PM ruling.
- CR round 1 found two defects: a test named indirectly (`@name`) was accepted with an arbitrary
  line, and a doctest residual claimed coverage the `reproduce` control does not give. Both fixed:
  UnitLocator now returns `{:unnamed, …}` and build refuses it.

## S18-7 — MES-230 ran past the end date, merged as dev.118

- Measured with the instrument at `dea3afe`: **232 new in-scope units in 20 files** (survey: ~210
  in 18), and 262 of 994 old test rows whose captured line had drifted (the survey's heuristic
  said 309, MES-176 said 225). A fresh capture has 0 drifted.
- PM rulings 35180: merge in "state B", where the re-capture and all 232 decisions land and the
  register is not rebuilt. **Controls `keysets` and `reproduce` will be red at main until
  MES-231**; no DoD gate is. One branch, three review hops (G1 52, G2 53, G3 127), a single merge.
- Hop 1 is built and corrected (tip `20cc8c8`): G1 = ET-CC 41, ET-CTRL 5, ET-ADJ 3, ET-OUT 3. CR
  F1 moved 8 client rows from ET-OUT to ET-CC (mixed) on Part A §6, and CC applied the same rule
  to 4 more; F2 removed an unexecuted producer from a boundary list. **The CR approved hop 1 at
  `20cc8c8` on 2026-11-13** (35222/35223, 22/22 seeds); hop 2 was dispatched the same day (35224).
- PM §9 ruling: a removed method sent without `_meta` falls under index.mdx:380-382's -32602
  MUST, so the SDK's -32601 test is ET-OUT at gate 3. Whether the SDK is wrong → **MES-238**
  (Bug, backlog, blocked by MES-230), opened at the PO's request.
- Hop 2 (G2 = ET-CC 50, ET-OUT 3): the CR's F1 led to the PM §9 ruling 35229. WHATWG §9.2.6's
  "For web browsers" dispatch steps are SDK policy, sorted by P/B mutants on `sse.ex`. 44 units
  were escalated and adjudicated. Applying the same ruling to the pre-existing SSE rows → **MES-239**.
  The CR approved hop 2 at `55f046e` (35233/35234).
- Hop 3 (G3 = ET-CC 107, ET-CTRL 2, ET-ADJ 6, ET-OUT 12). PM rulings 35238: E1 YES, a notification's
  null id is ADR-004 policy, so mixed; E2 NO, no Streamable HTTP client-transport boundary, so ET-OUT.
  The CR's F1/F2 (one missing `inherited_from`, the rulings not yet recorded) were corrected at
  `d8e82f1`. **The CR approved at `d8e82f1` (35246)**: 22/22 seeds, all gates green, state B.
- **Merged on 2026-11-14 as `2.0.0-dev.118` (`b439347`)**, after the moved end date, while sprint
  2280 was still open in Jira. The PO approved the state-B merge in session the same day. Totals over
  the 232: ET-CC 198, ET-CTRL 7, ET-ADJ 9, ET-OUT 18; mixed 156; 47 escalated, all adjudicated.
- The PO said YES in session on 2026-11-14 to three backlog tickets, all blocked by MES-231:
  **MES-240** (fresh capture at the sprint boundary), **MES-241** (`reproduce` on tickets that touch
  `test/mcp/`) and **MES-242** (whether to add a Streamable HTTP client-transport boundary).

## S18-8 — the reviewer engine ran out of credits mid-review

- MES-230 hop-1 review turn `b0b61866a74a` exited 1 with
  `usage_limit_exceeded` / `workspace_owner_credits_depleted`, after posting parts 1 and 2 but
  before its verdict part and its 22-seed run. acm's `seat_status` reported the engine's own error.
- The PM routed the findings already stated (part 2 says REQUEST CHANGES); the seed record moved to
  CC's correction run. **The PO ruled not to switch the CR engine and topped up codex** on
  2026-11-13; the hop-1 re-review then ran on codex.
- Separately: `seat_status` on a later CC handle (`d42ceb1692b0`) returned "unknown handle" after
  the turn ended, though the turn had posted its close-out. Effect was read from the ticket.

## S18-9 — F-6-1: every seat's credentials load into an `env -i` bash

- `/home/dev/.bashrc` sources `/dev/shm/ssm_env.sh`, which exports all three seats' EMFA_*
  values; `env -i … bash -c` still reads it. The PO ruled to ignore it unless it puts
  credentials into a git commit. Every evidence run since uses `--norc --noprofile` and aborts on
  any EMFA_* name (names only).

## End-of-sprint sweeps, at `dea3afe`

### Gate 6 (dependency advisories), two-step

```
$ bash gate6.sh        # 6a then 6b, verbatim from docs/procedure/gate-6.md, env -i --norc
EMFA_names=0
dea3afe
No retired or security advisory packages found
gate6 exit=0
```

6a printed no `GATE 6 FAILS` line, so all 22 baseline ids were reported. 6b exit 0. **Clean.**

### Publication (`mix origin.sync`)

```
GREEN C1  origin is reachable and readable
GREEN C2  live refs/heads/main on origin == local main      both at dea3afe39f46
GREEN C3  the version's tag exists locally and is annotated   2.0.0-dev.117 = 1d8858ef1b41
GREEN C4  that tag is on origin, as the same object
GREEN C5  the tag peels to an ancestor-or-equal of local main
IN SYNC — main and the version's tag are both published as held.
```

### Boundary-liveness sweep

The last completed sweep tip is `d270313` (MES-178's table). The three skip conditions:

```
(a) git diff --name-only d270313...HEAD -- lib/
    lib/mcp/client.ex
    lib/mcp/protocol/messages/response.ex
(b) git diff --name-only d270313...HEAD -- test/ test/support/ conformance/lib/
    conformance/lib/mcp/conformance/etcc_register.ex
    conformance/lib/mcp/conformance/unit_locator.ex
    test/fixtures/conformance/string-citations-ledger.json
    test/mcp/client_null_id_error_test.exs
(c) mix conformance.sweep --host
    recorded with the table: node=v24.13.0 harness=available
    this host:               node=v24.13.0 harness=available
    HOST MATCHES — condition (c) is satisfied.  (exit 0)
```

(a) and (b) are non-empty, so the sweep ran: `mix conformance.sweep --check --out full.json`,
in a detached worktree at `dea3afe`, under `env -i … --norc --noprofile` (EMFA_names=0).

```
EMFA_names=0
HEAD dea3afe start 2026-11-13T04:43:22Z
  [50/50] MCP.Transport.StreamableHTTP.Plug ... live (L1)
== MEASUREMENT DELTA (§2.3(e), reported not raised on) ==
  50 direction(s) differ on measurement fields only
== BASELINE PROBE (reported not raised on) ==
  unchanged — the probe's baseline fingerprint matches control.probe.
== L2 CARRIED FORWARD (reported not raised on) ==
  0 LIVE verdict(s) decided by L2 stand over a probe that moved NOTHING this run
== VERDICT DIFF (AC5 — this is the loud one) ==
  none — every verdict field reproduces byte-exactly.
SWEEP EXIT=0 end 2026-11-13T07:06:43Z
```

**50/50 directions, 0 verdicts moved, 2 h 23 m. The last completed sweep tip is now `dea3afe`.**
The measurement delta comes from the unit population, not from `lib/`. Every direction's
`suite_summary` moved, because the suite grew from 2068 to 2096 tests. Two directions also
moved their reddened counts and `live_units`: `MCP.Protocol.Error (decode)` and
`MCP.Transport.SSE (decode)`, as the test population under each mutation changed. The sweep
reports this delta but does not raise on it; no verdict field moved. The probe baseline
is unchanged, so the L2 verdicts were not decided over a blind probe. Nothing was refused, and
no ticket was opened.

## Carried into Sprint 19

- **MES-231** (register rebuild; `keysets`/`reproduce` red at main until it lands). MES-230 merged
  as `2.0.0-dev.118` on 2026-11-14 (S18-7).
- **MES-214** (stale M9h/M9f/M10 reddens), not started.
- Backlog raised this sprint: MES-233, 234, 235 (PO: option A), 236, 237, 238, 239, 240, 241, 242.
