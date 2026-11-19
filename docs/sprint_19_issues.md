# Sprint 19 — findings register

**Sprint goal, as set at planning on 2026-11-15.** Sprint 19 is Jira sprint 2289 on board 267.
Its planning page is Confluence 362676245. The PO completed Sprint 18 (2280) on 2026-11-15 and
moved MES-214 into this sprint. The PO approved the plan in session the same day (Q1–Q3, all YES):

- MES-239 runs as its own ticket before MES-231, linked "MES-239 blocks MES-231".
- The list, all in epic MES-118: MES-239, 231, 234, 236, 240, 241, with MES-214 as the stretch item.
- acm problems go on a new ACM ticket, now that ACM-38 is closed: **ACM-49**.

> Rebuild the ET-CC register so keysets and reproduce are green at main; make G30 green again; run
> gate 7 on mix.lock-only changes; add a sprint-end re-capture and a per-ticket reproduce check.

**Start state.** main = origin/main = `c7979b3`, `2.0.0-dev.118`.
- The `keysets` and `reproduce` controls in `conformance/controls/etcc_register_controls.exs` are
  red at main until MES-231 ("state B", PO-approved at the MES-230 merge).
- G30 (`crosswalk_controls.exs statements`) is red at main until MES-234.
- No DoD gate is red.

## Size survey at `c7979b3` (before the list was drafted)

| ticket | measured |
|--------|----------|
| MES-239 | 17 decisions with an `MCP.Transport.SSE (decode)` boundary carry no MES-230 hop-2 adjudication: SSETest 11, SSEDispatchTest 2, SSELineEndingsTest 3, SubscriptionsStreamTest 1. Excluding the MES-230 G2 units is part of the plan hop |
| MES-231 | A trial rebuild via `ETCCRegister.write/1` gives 579 → 811 rows: the 232 MES-230 rows, with 0 existing rows changed (sorted-row diff 232 lines). The G33 ledger holds **21** `held` (attribution_citations) cites in `etcc-attribution.md`, against the brief's "87", which comes from MES-194 comment 32781; to be reconciled at the plan hop. It also holds 7 `stale` cites owned by MES-194 |
| MES-234 | `crosswalk_controls.exs statements` still refuses: G30, 14 quoted byte-strings |
| MES-236 | The gate 7 applicability text in `CLAUDE.md` and `docs/procedure/gate-7.md`, and the `oc_gate` task's own path match |
| MES-214 | 38 mutation records carry a `reddens` field: D1-server-i 9, D1-server-ii 13, D1-server-iii 16 |

## Outcome

All seven planned tickets merged, stretch item included: `2.0.0-dev.119` → `2.0.0-dev.125`, final
tip `329e9ff`. Every turn was started through acm. CODE_CREATOR ran on claude throughout.
CODE_REVIEWER ran on codex until the PO switched it to claude on 2026-11-18 (S19-6).

| dev | ticket | what landed |
|-----|--------|-------------|
| .119 | MES-239 | The MES-230 hop-2 §9 ruling (WHATWG browser-only dispatch is SDK policy) applied to the 12 pre-existing `SSE (decode)` ET-CC decisions; P12 admitted under conditions |
| .120 | MES-231 | ET-CC register rebuilt from MES-230's re-capture (579 → 811 rows, ET-CC 281 → 479); the dated consumers decoupled onto one pinned register blob (b5b0fbc, md5 0bf1ff3b); G33 held 21 → 0, stale 7 → 0. `keysets` and `reproduce` green at main |
| .121 | MES-234 | G30 dated limb: the 8 MES-193 crosswalk edges become a dated measurement at bd99a39 (pinned set, ceiling 8). **G30 green at main**; `buckets --check` green |
| .122 | MES-236 | Gate 7 applies to a root `mix.lock` change, renames included (PO ruling 2026-11-12); a forced leg passes only on an accepted run |
| .123 | MES-240 | End-of-sprint step 6: `mix conformance.rows_drift`, a fresh capture compared with the committed rows file, guards RD1–RD9, never writes the committed file |
| .124 | MES-241 | **DoD gate 9**, `mix conformance.register_drift` (PO ruling 2026-11-17), guards RT1–RT5; Confluence D12 |
| .125 | MES-214 | The 37 D1-server recorded mutations re-measured at 84c8431 and marked: 7 retired (cause MES-161, bb68d9f), M10 ×2 re-measured zero, 23 FULL, 5 unverifiable |

**No `lib/` change this sprint** (`git diff --stat c7979b3 329e9ff -- lib/` is empty). `mix.exs`
changed only by the version bumps; `mix.lock` did not change. The suite grew from 2096 to 2179
tests (`24 doctests, 2179 tests, 0 failures` at the tip). Gate 5 was 22 serial seeds on every
merged ticket, on both the CC and the binding CR run.

## S19-1 — a size survey that diffed the artefact and missed its consumers (MES-231)

- Planning sized MES-231 as "mechanical": a trial rebuild gave 232 rows added, 0 changed. At the
  plan hop, swapping it in gave **9 gate-5 failures** (attribution, crosswalk G24, two dated
  adjudications, G33 440 cites), and `etcc-attribution.md` has no generator.
- The PO ruled DECOUPLE (consumers pinned to the b5b0fbc blob). Follow-ups MES-243, 244, 245.
- The "87 held" cites in the brief were a restated figure; the ledger held 21.
- **Lesson:** a size survey of a regenerated artefact runs its consumers, not just a diff.

## S19-2 — pre-existing reds found at main during the sprint

- `oc_gate_controls` N3a/N3b red at main (34/36; counts hard-coded at MES-160). Fixed in MES-236.
- R-A: the attribution controls `mutation` mode is a BROKEN CONTROL at main → **MES-246**.
- R-B: crosswalk `noop`/`g24` were refused by the same 14 G30 defects. Fixed by MES-234.
- `buckets --check` had been red (13 views) since e782cc7. Green after MES-234.
- The committed crosswalk lacks MES-167's leaves, and MES-193's body never recorded the 32398
  Q-A escalation (noted on MES-193, 35495).

## S19-3 — the test-rows file had drifted, and was found by its own new instrument (MES-240)

- MES-240's first live run at dec37c2: +31 added, 294 relined, 6 refielded. **MES-247** owns the
  re-capture. At this sprint's final tip the drift is +83 / 294 / 6 (below, step 6).
- MES-240 took two correction rounds over write-safety (a symlinked parent, a `--json` swapped
  during the capture, lexical real paths). The residual is stated in `end-of-sprint.md` step 6.
- `rows_drift` has the same `--fresh`/`--keep` replay weakness that MES-241 fixed for gate 9
  → **MES-249**.

## S19-4 — MES-241 ran to eight correction rounds; the stopping rule came late

- Rounds 1–3 fixed real defects (R1–R4: replay of another commit, lost suite_rc, mix.exs
  missing from the trigger, an instrument crash read as drift).
- R5 then descended a level every round: line regex → AST scanner → capture names → load origin →
  sampling time, each answering the last counterexample, each aimed at deliberate tampering by
  test code. The PM applied the 2026-08-21 stopping rule only at round 5; the hardening went to
  **MES-248**.
- Rounds 5–8 were prose: each corrected an overclaim, and two of the corrections introduced a new
  universal claim that the next review found false.
- **Lessons:** impose the stopping rule at the second same-shape round; correct a false claim to
  the minimum true statement, never to a new universal one.
- Gate 9's trigger does not cover a hook under `test/conformance/` (residual 8, MES-248).

## S19-5 — MES-214: the recorded M9-family reddens went stale at MES-161

- Pair runs put the cause at bb68d9f for all 7 ZERO records (parent n/n, merge 0, tip 0).
  The CR re-ran 9 of 9 sampled runs exactly.
- The population was 37, not the 38 counted at planning (M16's nested measurement).
- Backlog: **MES-253** (guard :6631 does not pin `reddens`); stale `also_reddens_in_slice` lists
  and live-named M9 row fields noted on **MES-250**; the re-run prototype noted on **MES-252**.
  Also filed: **MES-251** (213 D5b et_null mutations).

## S19-6 — codex outages; CODE_REVIEWER moved to claude

- Codex ran out of credits **four times in this sprint** (MES-240 once, MES-241 three times; the
  fifth since S18-8 on MES-230), each cutting a review short before its verdict. Once it used 99% of its 5-hour window
  in about 40 minutes.
- One `cyber_policy` refusal on adversarial review wording (MES-241, turn 4cc598325ab7), fixed by
  re-briefing in neutral wording.
- **PO 2026-11-18:** run CODE_REVIEWER on claude. The last two MES-241 reviews and the MES-214 review
  ran on claude; MES-214 approved in one round.
- CC and CR are now the same model family, so independent re-measurement in reviews matters more.

## S19-7 — procedure and documentation findings, not ticketed

- `CLAUDE.md` is 16274 B against the 16384 B cap: **110 B headroom**. The next gate change will
  not fit without moving text to `docs/procedure/`.
- `lanes.md`: the PM-alone guard regex omits `conformance/data/`, which gate 8 treats as
  reviewable (the ET-CC table). Whether a PM Task may touch it is unruled.
- `etcc-register.md` §14's doctest-directive note is stale against gate 9.
- `etcc_register.ex:525-534`: a G33 pin trap (an edit there moves pinned citations).
- Confluence: parent 250052681 v22 is not in the version-history page 330956801, which also lacks
  v16 and v20; the parent's v20 panel note says "v1–v19".
- Jira sprint 2289 stayed "future" until 2026-11-18 although the PO approved the start on 11-16.

## End-of-sprint sweeps, at the final tip `329e9ff`

### Gate 6 (dependency advisories), two-step — **RED**

```
$ bash g6run.sh        # 6a then 6b, verbatim from docs/procedure/gate-6.md, env -i --norc
Hex:    2.5.1
EMFA_names=0
329e9ff
Advisories:
  plug 1.19.5 - EEF-CVE-2026-120287 (MEDIUM)
    aka: CVE-2026-120287, GHSA-qj4r-jh2r-rw3f
    Multipart `:length` limit not charged for part and header framing in Plug.Parsers.MULTIPART
    https://osv.dev/vulnerability/EEF-CVE-2026-120287

Found packages with security advisories
gate6 exit=1
```

6a printed no `GATE 6 FAILS` line, so all 22 baseline ids were reported and the advisory data is
complete. 6b exit 1 on a new advisory published since the Sprint 18 close against a dependency no
ticket touched. Per step 3, not fixed in place: **MES-254** (High).

### Publication (`mix origin.sync`)

`IN SYNC`: main = origin/main at `329e9ff`; `2.0.0-dev.125` (`a86a5a027210`) is annotated, on
origin as the same object, and peels into main.

### Test-rows drift (`mix conformance.rows_drift`), exit 1

```
EMFA_names=0
329e9ff
rows-drift: DRIFT - 83 added, 0 removed, 0 moved, 294 relined, 6 refielded, 0 restatus (2120 committed rows, 2203 fresh; committed md5 7d4a2d36b67723c4c7107adf7747dd9d, fresh md5 3d26773b153060a120b9edf3e63c06f0)
```

Drift, not a refusal. Owned by **MES-247** (measurement posted there, 36125); not re-captured in
place.

### Boundary-liveness sweep

The last completed sweep tip is `cb757bf` (Sprint 18). The three skip conditions:

```
(a) git diff --name-only cb757bf...HEAD -- lib/
    (empty)
(b) git diff --name-only cb757bf...HEAD -- test/ test/support/ conformance/lib/
    21 paths: 13 under conformance/lib/ (register, attribution, crosswalk, oc_gate, pinned
    register, rows_drift and register_drift instruments and tasks), 7 under test/conformance/,
    and the G33 ledger (test/fixtures/conformance/string-citations-ledger.json)
(c) mix conformance.sweep --host
    recorded with the table: node=v24.13.0 harness=available
    this host:               node=v24.13.0 harness=available
    HOST MATCHES — condition (c) is satisfied.  (exit 0)
```

(b) is non-empty, so the sweep ran: `mix conformance.sweep --check --out full.json`, in a detached
worktree at `329e9ff`, under `env -i … --norc --noprofile`, started with `setsid nohup`.

```
EMFA_names=0
HEAD 329e9ff start 2026-11-18T23:26:16Z
== MEASUREMENT DELTA (§2.3(e), reported not raised on) ==
  50 direction(s) differ on measurement fields only
  CAUSE: the unit population, not lib/.
== BASELINE PROBE (reported not raised on) ==
  unchanged — the probe's baseline fingerprint matches control.probe.
== L2 CARRIED FORWARD (reported not raised on) ==
  0 LIVE verdict(s) decided by L2 stand over a probe that moved NOTHING this run
== VERDICT DIFF (AC5 — this is the loud one) ==
  none — every verdict field reproduces byte-exactly.
SWEEP EXIT=0 end 2026-11-19T01:49:53Z
```

**50/50 directions, 0 verdicts moved, 2 h 23 m. The last completed sweep tip is now `329e9ff`.**
Every direction's `suite_summary` moved, because the suite grew. As at the Sprint 18 close, only
`MCP.Protocol.Error (decode)` and `MCP.Transport.SSE (decode)` also moved their reddened counts
and `live_units`. No verdict field moved, nothing was refused, and no ticket was opened.

## Carried into Sprint 20

- **MES-254** (High): gate 6 red at main, plug EEF-CVE-2026-120287. Gate 6 applies only to tickets
  that change `mix.exs` or `mix.lock`, so it blocks no other ticket, but it is red until this lands.
- **MES-247**: re-capture `etcc-exunit-rows.json` (drift +83 / 294 / 6).
- Backlog filed this sprint, all under MES-118: MES-243, 244, 245, 246, 248, 249, 250, 251, 252, 253.
