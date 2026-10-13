# Sprint 15 — findings register

**Sprint goal, as set by the PO on 2026-10-12 and reworded on 2026-10-13.** Sprint 15 is Jira sprint
1884 on board 267. Its master page is Confluence 330694657. The PO ruling that scoped it is MES-96
32057. The goal, as reworded (page v4; the user copied it into Jira):

> Close the server's known conformance gaps (the discover version gate, `_meta` type checks, HTTP
> 404 for unknown methods, and controlled answers instead of uncontrolled 500s and crashes on
> malformed input) and the SSE dispatch rules, each held to a widened gate 8; then refresh the
> stale `file:N` citations in the conformance artefacts.

Ticket order: MES-180 first, then the six `lib/` fixes, then MES-167 last. MES-190 joined
mid-sprint by PO ruling (2026-10-12) and ran before MES-167. Nine tickets merged,
`2.0.0-dev.84` → `2.0.0-dev.92`. Every turn was started through acm. CODE_CREATOR ran on claude
throughout. CODE_REVIEWER ran on codex throughout, after its trial passed on MES-180.

| dev | ticket | what landed |
|-----|--------|-------------|
| .84 | MES-180 | Gate 8's trigger widened beyond `lib/` to the ET-CC boundary table and the two guard sources, with `--no-renames` |
| .85 | MES-163 | `server/discover` is behind the -32022 unsupported-version gate; -32022 data is `{supported, requested}`; -32022 leaves the Plug as HTTP 400 |
| .86 | MES-165 | Removed and unknown methods get -32601 on every transport and HTTP 404 from the Plug; `initialize` is no longer -32022 |
| .87 | MES-168 | A client-sent JSON-RPC response is refused 400 / -32600 by the Plug before dispatch (was an uncontrolled 500) |
| .88 | MES-169 | A POST body over `:max_body_length` (default 8,000,000) is refused 413 / -32600 with id null (was a `WithClauseError` 500) |
| .89 | MES-164 | A wrong-typed required `_meta` value is -32602 (HTTP 400) with `data.invalid`; the Plug's -32602 carries the readable id |
| .90 | MES-170 | The SSE parser follows the WHATWG dispatch rules: bare fields, no-data events dropped, last id persisted, NUL id and signed retry ignored |
| .91 | MES-190 | A malformed JSON-RPC `error` member decodes to -32600: no `FunctionClauseError`, no stdio Connection or client exit, no HTTP 500 |
| .92 | MES-167 | 677 stale string-form `file:N` citations re-resolved in 12 authored conformance sources; the register copy follows by a 6951-field join |

**`lib/` changed in six files** (`git diff --stat 44d1cbe 32b468a -- lib/`: 246 insertions, 65
deletions): `protocol.ex`, `protocol/error.ex`, `protocol/meta.ex`, `server/dispatch.ex`,
`transport/sse.ex` and `transport/streamable_http/plug.ex`. The suite grew from 1800 to 1891 tests.

**Official conformance moved only where a ticket said it would.** MES-163 flipped exactly 2 server
checks FAILURE → SUCCESS and MES-165 flipped 6. Every other ticket showed no movement on either
leg (server 194 rows, client 128 rows). G32 stayed CLEAN all sprint. Its anchored count went
137 → 157 on MES-165, and since then it has been 820 verified (663 at the tip, 157 anchored).

## S15-1 — codex as CODE_REVIEWER: trial passed, then one lapse in gate-5 isolation

**Trial (MES-180, ACM-38 32192).** It passed. The session was fresh, all 17 commands ran as
`bash -c` (not `-lc`), node v24.13.0 was on PATH, and the 17,394 B CLAUDE.md core loaded whole.
Both Sprint 14 codex defects (truncated instructions, no node) are therefore gone at the CR seat.
Codex then reviewed all nine tickets. Its reviews were thorough: it re-ran every gate, sampled
edits independently, and found real defects on MES-163 (F2, F3), MES-164 (F1) and MES-167 (F1–F5).

**The lapse (MES-170 F1).** CR reported seed 0 red at the tip (three MockTransport timeouts) while
base was green. The cause was CR's own codex session. It ran G32, probes and a calibration
concurrently with the gate-5 loop, which the file mtimes show. The PM then ran a controlled seed 0
three times at the tip and three times at base, serially and alone, and all six were green
(disposition 32336). CR re-ran gate 5 alone and approved.

**Practice adopted.** Every CR handoff since then has said: gate 5 is the 22 seeds (0 and
1000001–1000021), strictly serial and alone; take a ps snapshot first; start no mix, BEAM, probe or
codex sub-task during the loop; record per-seed UTC timestamps; do not retry. Every later review
followed it and reported its isolation evidence.

**Gotcha.** A codex seat runs `pwd` and reads CLAUDE.md before it reads the brief, so a brief that
asks for a specific "first command" is not followed literally.

## S15-2 — gate-5 flakes are load-sensitive client deadlines (MES-191)

Three times this sprint, client tests with wall-clock deadlines went red under load and green
alone:

- **MES-180:** seed 13 failed 2 of 6 runs in `client_defects_test` D-1 (a 1000 ms deadline). The
  new test was made `async: false`, after which it passed 6 of 6.
- **MES-168:** a second mutation run added three out-of-slice client reds (D-1, W6, `connect/1`).
  Run in isolation, the three client files were green 6 of 6.
- **MES-170:** the CR concurrency case in S15-1.

These are filed as **MES-191** (backlog, epic MES-118): `wait_for_sent` at 1000 ms and
`Task.await` deadlines fail under full-suite load. Until it is fixed, a red client deadline test is
first re-run alone and compared with base, and is never retried to green inside the gate.

## S15-3 — gate 8 widened, then held on every `lib/` ticket

MES-180 widened gate 8's trigger (PO ruling 32057 Q5) to `lib/`, `conformance/data/etcc-boundaries.json`,
`boundary_sweep.ex` and `conformance.sweep.ex`, using the three-dot `--no-renames` form. All eight
later tickets matched the trigger: seven through `lib/`, and MES-167 through the boundary table.
Every run was `GUARDS 23-27 — no violation` at 29 / 19 / 19 / 194 / 194, with guards 26 and 27
equal to the independently counted `mutation_spec` total. That is gate 8's first real use, and no
anchor moved under it. MES-179 (the instrument refusing a vacuous population itself) is still in
the backlog.

## S15-4 — MES-167: the citation drift class, and what it turned up

**Scope.** Ratified in 32390 as part (a) only: re-resolve the stale string-form `file:N`
citations. The census found 7000 string citations, 1465 of them stale (966 authored, 499 derived),
and 92% were unguarded. Four parts were split to the backlog (epic MES-118):

- MES-192: the guard (PO yes, 2026-10-13);
- MES-193: oc tags, plus crosswalk and bucket regeneration;
- MES-194: re-capturing the rows and rebuilding the register;
- MES-195: re-keying.

**Two instruments were already broken on main** (stop 32392):

- **The ET-CC register generator has refused since MES-161.** Guard 21 trips on stale Q14 rows. The
  register is therefore hand-maintained, and 103 of its rows had diverged from the decisions file.
  Ruling R1: substitute bytes in the register and require a full 6951-field join. It went
  103 → 0. The generator's repair is MES-194.
- **The crosswalk refuses at base.** G30 counts 112 stale quotes. After the edits, 14 quotes in 8
  edges still cite test code that MES-161 and MES-165 removed. Those 8 edges, and the crosswalk and
  bucket regeneration, went to MES-193 (Q-A).

**E1: 27 false-stale edits** were caught by `adjudications_test` and reverted (stop 32396/32397).
The mechanism: rows anchored by `et_test.at` cite a commit, not the tip, and the census parser
also missed array elements. The PM's first hypothesis (a pickaxe hit on an earlier same-text
citation) was refuted. A sweep of all 678 edits then found 4 more wrong (0.6%), and all were
corrected.

**CR found five more classes that green gates did not show** (32454–32457, 32496):

| # | class | example |
|---|---|---|
| F1 | head line moved onto a blank line | `self_compatibility_test.exs:113` → the assertion is :114 |
| F2 | dated prose ("at 5047a0e") moved to tip coordinates | three addresses restored to their 5047a0e lines |
| F3 | sentence's first address fixed, later bare continuations not | `plug.ex:1008/:1010` → :1060/:1062 |
| F4 | byte-equal move preserves an authored-wrong claim | cg-reconciliation cited a log warning as "emitting" cache hints |
| F5 | evidence log held a placeholder, not literal text | `edit_log.json` replay failed on 1 of 12 files |

**F3's sweep found a new class: bare `:N` continuations.** These are line citations with no file
name, which takes its file from the sentence or row. The census never tokenised them. There are 472
stale ones in the strings MES-167 edited, and 2663 bare tokens across the artefacts. That exceeded
the stop limit, so it was split to **MES-196**.

**What MES-167 certifies** (residuals, merge record 32502):

1. Byte movement for the mechanical edits (523 windows identical between their introduction and
   the tip), not the correctness of the authored claim they support.
2. E1's "no edit in an anchored row" is target-scoped. 59 rationale fields in anchored rows did
   change, but only in an unrelated `dispatch.ex:372→380` citation, and their anchors are intact.
3. The bare `:N` class is open (MES-196).
4. The crosswalk and buckets are unregenerated (MES-193); the register generator is deferred
   (MES-194).

**Lessons carried into MES-192 and MES-196** (the review's own words): byte agreement certifies
movement, not intent. Check that a head line is not blank or a closing delimiter. Dated prose
keeps its own addresses.

## S15-5 — PM ruling and finding errors this sprint

These are recorded because each one cost a round.

- **MES-163 32209** demanded map data for `initialize`. CR F1 showed the demand was wrong. It was
  withdrawn, and the data-shape item moved into MES-165's brief.
- **MES-164 32281** accepted "byte-identity" for the Q6 missing-only reply without a test that pins
  those bytes. CR F1 showed an in-VM decoy passing all 29 tests. Commit 3 added whole-error literal
  tests, which redden under the decoy. From MES-170 on, the plan handoff requires each "unchanged"
  claim to name its pinning test.
- **MES-168 32245** set a stop rule ("any other red") broad enough that load flakes outside the
  slice fired it (S15-2). Q8 replaced it with an isolation check.
- **MES-167 32458** said the cg-reconciliation census ("every `ttl_ms` / `cache_scope` site in
  `lib/`") omits `config.ex`. `config.ex` names those terms only in its moduledoc, so the census
  was right. The claim was withdrawn in 32503, after it had already reached a close-out and the
  merge record.
- **D11 register row (2026-10-13).** The PM put "should D11 get a citation-register row?" to the
  PO before reading D11's own text (child page 330989570), which says it adds no row. The register
  lists only external origins. The PO chose to leave it (option 2), and the correction is on
  MES-192.

## S15-6 — a reported figure that read half a nested file

MES-190's close-out (32344/32345) gave the client conformance leg as 65 rows. CC's `rows.py` read
`checks.json` non-recursively, and the client leg's file is nested. The PM's recursive re-compare
gave 128/128 client and 194/194 server rows, with 0 differing (correction 32346). This is the
known "client-leg `checks.json` is nested" trap. It has now been seen at a seat as well as at the
PM.

## S15-7 — tag messages dev.80–84 use the wrong form

CR F3 on MES-163 found that tags `2.0.0-dev.80` to `2.0.0-dev.84` carry `2.0.0-dev.N (MES-x)`
instead of D1's `2.0.0-dev.N — [MES-x] title`. From dev.85 on, every tag uses the D1 form. The five
old tags are published. They are left as they are rather than rewritten, because re-tagging a
published tag is the C3/C4 damage `origin.sync` exists to catch.

## S15-8 — smaller findings, filed

| ticket | what | from |
|---|---|---|
| MES-187 | gates 6/7 applicability greps miss renames; an unresolvable key reads as "not applicable" | MES-180 |
| MES-188 | recorded mutation M10 (D1-server-iii) no longer reddens anything | MES-163 CR F2 |
| MES-189 | HTTP client turns a 4xx JSON-RPC error into a transport error | MES-165 plan |
| MES-191 | client wall-clock deadline flakes (S15-2) | MES-168 |
| MES-196 | stale bare `:N` citations (S15-4) | MES-167 CR F3 |
| MES-197 | client: a malformed error reply makes the caller wait out its timeout | MES-190 Q6 |
| MES-198 | Plug's -32600 `data` is `inspect()` of an Elixir struct (`plug.ex:371`) | MES-190 O1 |
| MES-199 | a response carrying both `result` and `error` is accepted | MES-190 O2 |
| MES-200 | re-disposition D2a-ii rows 31/40 and later Sprint 15 remedies; ET-CC membership of the new tests | MES-163 Q3/Q5 |

Not ticketed: CR's MES-169 note that `validate_max_body_length!` sits under
`method_not_allowed`'s comment in `plug.ex`.

## S15-9 — PO decisions this sprint

- MES-190 joined the sprint (2026-10-12).
- Codex allowed for build turns, with CR on codex (page 330694657 v3).
- The sprint goal was reworded (2026-10-13, page v4, copied into Jira by the user).
- MES-192's guard: yes, in the D2 form, as its own Task. Whether it runs under gate 5 or gate 8 is
  still open.
- D11's citation-register row: no row (option 2).

## S15-10 — behaviour changes shipped (for the next release notes)

- `server/discover` now enforces the protocol version: an unsupported version is -32022 with
  `data: {supported, requested}`, and over HTTP every -32022 is status 400.
- Removed and unknown methods (including `initialize`) return -32601 on every transport, and HTTP
  404 from the Plug.
- The Plug refuses, instead of crashing with 500:
  - a client-sent JSON-RPC response: 400 / -32600;
  - an over-length body: 413 / -32600, id null, under the new `:max_body_length` init option
    (default 8,000,000 bytes);
  - a malformed `error` member: 400 / -32600.
- A wrong-typed required `_meta` value (`clientCapabilities` not an object, `protocolVersion` not
  a string) is -32602 / HTTP 400 with `data.invalid`.
- The SSE parser follows the WHATWG event-stream dispatch rules.
- A malformed `error` member in a reply no longer kills the stdio Connection or the client. The
  client drops it, and the caller waits out its timeout (MES-197).
- No dependency change.

## End-of-sprint sweeps (at the final tip `2.0.0-dev.92` / `32b468a`)

**Dependency-advisory sweep (the two-step gate 6).** hex 2.5.1 (`mix hex --version`: `Hex
v2.5.1`). The script is `docs/procedure/gate-6.md`, run on main at 32b468a with a clean tree.

- **6a:** no `GATE 6 FAILS` line, so all 22 known advisory ids were present in the baseline audit.
- **6b:** `No retired or security advisory packages found`.
- Script exit 0. **Clean; no advisory, so no ticket.**

**Publication sweep (`mix origin.sync`, run point c).** GREEN at `2.0.0-dev.92`:

```text
  GREEN C1  origin is reachable and readable
  GREEN C2  live refs/heads/main on origin == local main          (both at 32b468ab3a74)
  GREEN C3  the version's tag exists locally and is annotated     (dbc0554a4e64 -> 32b468ab3a74)
  GREEN C4  that tag is on origin, as the same object
  GREEN C5  the tag peels to an ancestor-or-equal of local main
  IN SYNC — main and the version's tag are both published as held.
```

**Boundary-liveness sweep (`mix conformance.sweep --check`).** The sweep was **owed**, and it was
**run**. The last sweep tip was 44d1cbe (Sprint 14). The three skip conditions came out as
follows:

- (a) `git diff --name-only 44d1cbe...32b468a -- lib/` lists 6 files: `protocol.ex`,
  `protocol/error.ex`, `protocol/meta.ex`, `server/dispatch.ex`, `transport/sse.ex` and
  `transport/streamable_http/plug.ex`.
- (b) `git diff --name-only 44d1cbe...32b468a -- test/ test/support/ conformance/lib/` lists 16
  files: the three guard/register sources (`boundary_sweep.ex`, `etcc_register.ex`,
  `conformance.sweep.ex`) and 13 test files.
- (c) The host fingerprint is `node=v24.13.0 harness=available`, both in the committed table's
  `control.host` and in this run's.

Conditions (a) and (b) are non-empty, so the sweep runs. The run:

- Command: `mix conformance.sweep --check --out /tmp/s15sweep/full.json`.
- Where: a dedicated worktree at 32b468a, started detached.
- When: 11:40:02 to 13:51:07 UTC, so 131 min 5 s.
- Result: **exit 0**. Afterwards the worktree was clean, so `lib/` was restored.

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

**What was actually re-measured.**

- **L1:** all 50 directions.
- **L2:** fired on 29 directions. The probe's baseline is sighted, not uniform: the run reports
  `distinct: 15, scenarios: 15`. 26 of those 29 verdicts were measured this run.
- **Carried forward:** the other 3 L2 verdicts were not re-measured (MES-178).

Verdicts at 32b468a: 31 live (21 by L1, 10 by L2) and 19 dead (by L2). This is the same split as
at 44d1cbe.

**The measurement delta.** All 50 directions differ on measurement fields only. Every
`suite_summary` went from `24 doctests, 1790 tests` to `24 doctests, 1891 tests`, which is the
Sprint 15 test additions. Ten live directions also moved their L1 counts (committed → this run):

| Direction | `reddened_total` | `live_units` |
|---|---|---|
| `MCP.Client` | 34 → 35 | 12 → 13 |
| `MCP.Protocol.Error (decode)` | 20 → 24 | 18 → 22 |
| `MCP.Protocol.Messages.Discover (decode)` | 33 → 34 | 32 → 33 |
| `MCP.Protocol.Messages.Discover (encode)` | 21 → 22 | 20 → 21 |
| `MCP.Protocol.Messages.Request` | 37 → 38 | 34 → 35 |
| `MCP.Protocol.Meta` | unchanged | 98 → 98 (unit list changed) |
| `MCP.Protocol.decode_message/1` | 86 → 99 | 80 → 93 |
| `MCP.Server.Dispatch` | unchanged | 78 → 77 |
| `MCP.Transport.SSE (decode)` | 53 → 76 | 42 → 65 |
| `MCP.Transport.StreamableHTTP.Plug` | 63 → 78 | 36 → 51 |

Every one of the ten was live before and is live now. Eight gained live units, consistent with the
Sprint 15 tests landing on the paths they fixed. `MCP.Protocol.Meta` kept 98, and
`MCP.Server.Dispatch` went 78 → 77 (`reddened_outside_own` 86 → 85). Units are keyed by
`file:line`, so a test that only moved inside an edited test file shows as one unit removed and one
added. The unit lists of these two directions were not reconciled test by test.

**No drift, so no ticket.** The committed table still records the 1790-unit measurements. As at
Sprint 14, refreshing those fields is a data change under `conformance/`. It is left to the next
ticket that regenerates the table, and is not made in this register.

## Open at close

- **Seat-file edits, still owed by the operator** (from S14-1). The PM does not write seat files.
- **MES-192:** gate 5 or gate 8 for the new guard (PO).
- **The WON'T Do unassign rule** is to be confirmed at the next WON'T Do transition.
- **Backlog for Sprint 16 planning:** MES-192–200, plus MES-173, 176, 178, 179, 187–189, 191.
