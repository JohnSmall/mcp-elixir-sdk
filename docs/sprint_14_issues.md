# Sprint 14 — findings register

**Sprint goal, as set by the PO on 2026-10-10.** Sprint 14 is Jira sprint 1851 on board 267. It was opened
to trial the acm seat launcher (ACM-38) on real MES tickets: MES-166 on claude, then MES-171. The
trial's master page is Confluence 329842696. The PO approved two conditions for it: per-ticket
worktrees are mandatory, and tickets run strictly one at a time. Four tickets then joined the
sprint by PO ruling:

- MES-172, an advisory fix, under the rule that a must-fix-now advisory may join an active sprint;
- MES-174, the blind L2 probe that CR found on MES-171;
- MES-177, the CLAUDE.md restructure;
- MES-175, gate 8.

Six tickets merged, `2.0.0-dev.78` → `2.0.0-dev.83`. Every turn was started through acm 0.15.1.

| dev | ticket | what landed |
|-----|--------|-------------|
| .78 | MES-166 | `etcc_tags --check` reads tags from the AST: a tag inside a string or sigil is no longer a stray; an unparseable or non-UTF-8 test file is refused by name |
| .79 | MES-172 | mint 1.10.1 → 1.10.2: clears EEF-CVE-2026-94194, -91043 (HIGH) and -92103; `mix.lock` only |
| .80 | MES-171 | The two GUARD 26 `mutation_spec` entries (Meta, Plug) re-anchored to the behaviour each mutated at 5047a0e; `--verify` green |
| .81 | MES-174 | The L2 byte probe sends the required `_meta` again (15/15 distinct); the sweep refuses a blind or unreached probe baseline |
| .82 | MES-177 | CLAUDE.md cut from 57,816 B to a 13.6 KB core under a 16 KiB cap (enforced under gate 5); the procedure moved verbatim into `docs/procedure/` |
| .83 | MES-175 | **DoD gate 8**: `mix conformance.sweep --verify` on every branch that changes `lib/` |

**No `lib/` file changed this sprint.** `git diff --stat 0fcdbbc 44d1cbe -- lib/` is empty. The
only shipped change is the mint bump.

## S14-1 — the acm trial: claude met, codex failed on two acm defects

**Claude.** acm's AC2 is met for claude (ACM-38 31959). The evidence covers 12 transcripts in 5
sessions, on MES-166, MES-171 and MES-172:

- every cwd was the seat's own directory under `/workspace/acm-seats/MES/`;
- each session loaded exactly two instruction files, MES's CLAUDE.md and the seat file;
- the ancestor `/workspace/CLAUDE.md` was excluded;
- every turn exited 0 with effect true;
- every seat comment was authored by the seat's own account;
- every seat handed back to the PM.

The turns that followed (MES-174, MES-177, MES-175: plan, build, correction and review turns) all
behaved the same way.

**Codex.** One plan-only turn was run, on MES-173 (31964, handle
`CODE_CREATOR/MES-173/a3ca97330f16`, codex-cli 0.162.1). It passed on engine, cwd, identity and the
hand-back. It **failed** the instruction-file check (ACM-38 31967, verdict 31976), on two defects:

1. **Truncated instructions.** Codex's `project_doc_max_bytes` (32 KiB) cut MES's 57,816 B
   CLAUDE.md at byte 32,768, so the seat file never loaded.
2. **No node.** Codex runs each command as `bash -lc`. The login shell rebuilds PATH, so nvm's node
   is gone and gate 7 cannot run at that seat.

MES did not work around either defect. There will be no codex build turn on MES until acm fixes
both. MES-177 still removed MES's own contribution to defect 1: the CLAUDE.md core is 14,442 B
at dev.83.

**acm defects found and fixed during the trial:**

| defect | found | fixed in |
|---|---|---|
| `seat_start` refused over IPv6 | 31859 | ACM-39, 0.14.2 |
| node missing from a claude seat's PATH | 31915 | ACM-41, 0.15.1; confirmed in 31955 |

The feedback rounds on MES-166 are 31859, 31915, 31955 and 31968.

**Observations, not failures** (31959):

- The seats root is inside the `/workspace` git repository, which is contrary to acm's moduledoc.
  As a result, seats find that repository and share claude's `-workspace` auto-memory directory.
- An `erl_crash.dump` (5.4 MB) was left in `MES/CODE_CREATOR` by a BEAM run from the seat
  directory.

**Open at close.** The ACM PM has a suggestion for the codex/node defect. It is to be posted as a
reply on ACM-38 under 31967. At 2026-10-11 22:15 UTC, ACM-38 had no comment after 31976.

**Two seat-file edits are owed by the operator** (the PM does not write seat files):

- `CODE_CREATOR/CLAUDE.md`: "gates 1-7" should read "gates 1-8", and it should name the
  `docs/procedure/` pages that MES's index lists.
- `CODE_REVIEWER/CLAUDE.md`: the checklist items are in the `docs/procedure/` pages.

## S14-2 — a sweep with no verdict diff hid a blind probe (MES-171 → MES-174)

MES-171's full sweep reported "VERDICT DIFF none" (31960). CR then showed (31962) that the L2 byte
probe had been blind since MES-161. The probe sent only `protocolVersion`, so every dispatch
scenario returned the same -32602 bytes.

Two things kept this out of sight:

- The sweep never lets a silent probe override a recorded live verdict, so those verdicts were
  carried forward rather than re-measured.
- `scenarios_moved` is not a reported field, so its collapse printed nowhere.

**MES-174** fixed the probe (15/15 distinct) and made the sweep refuse two kinds of baseline. A
*blind* baseline has fewer distinct responses than scenarios. An *unreached* baseline has a
dispatch scenario that never reached dispatch. CR's F1 rejected the first version of the
unreached check, because it exempted the non-reply scenarios as a class. The fix declares the
three non-dispatch scenarios by name.

**Carried forward, not fixed:** three LIVE verdicts that rest only on L2 records — Connection,
NotificationCollector and Stdio. That, plus a byte_probe coherence guard, is **MES-178**.

**Practice adopted (PM memory):** before reporting any sweep result, check that the unmutated
baseline is not uniform, and say which limbs were actually re-measured.

## S14-3 — CLAUDE.md outgrew one engine's load budget (MES-177)

At 57,816 B, CLAUDE.md was past codex's 32 KiB budget on its own (S14-1). The PO approved the
layout and the 16 KiB cap. MES-177 then:

- moved the procedure text verbatim into six flat pages under `docs/procedure/`;
- left a core in CLAUDE.md with a "Where the procedure lives" index;
- added `test/conformance/claude_md_cap_test.exs` under gate 5, which checks four things: the cap,
  that the index exists, that no index entry dangles, and that the directory holds no orphan or
  non-page entries.

CR's F1 found that the orphan check missed subdirectories and non-`.md` entries. The fix makes the
layout flat by rule (the `non_page_entry` reason).

**Consequence for D7.** The gate text is now in `docs/procedure/`, so D7's prose boundary
("no `CLAUDE.md` text that alters a DoD gate") would have stopped covering it. The core and the
`lanes.md` preamble now say "`CLAUDE.md` **or `docs/procedure/`**". The canonical D7 on 250052681
still says only CLAUDE.md, and amending it is a PO question (below). The guard regex is unchanged:
it protects code paths, and prose has never been inside it.

## S14-4 — gate 8, and the vacuous pass it can still give (MES-175 → MES-179)

**Gate 8 (PO ruling 2026-10-11).** `mix conformance.sweep --verify` runs on any branch whose
three-dot diff touches `lib/`. A `lib/` edit that moves a `mutation_spec` anchor now goes red on
the ticket that made it. Before gate 8, it went red at the next sprint boundary (S13-9 was that
case). Liveness stays a sprint-boundary measurement.

**CR's F2 on MES-175.** An emptied boundary table gives a green `--verify` with every count at 0.
`gate-8.md` now defines a pass to require all of the following:

- every scanned count is non-zero;
- guard 26 equals the `mutation_spec` total (194 at dev.83);
- guard 27 equals the same total.

That check is procedural and is done by hand. **MES-179** makes the task itself refuse a vacuous or
short population, and adds a control on its exit status.

Gate 8 has not yet run on a real ticket: no ticket this sprint after MES-175 changed `lib/`.

**Open:** widen gate 8's trigger beyond `lib/`, to the boundary table and the guard sources (PO
question below).

## S14-5 — gate-6 runs before 2026-10-11 were probably on hex 2.5.0

The container's shared hex was 2.5.0, below the floor `gate-6.md` requires. It was upgraded to
2.5.1 with PO approval during MES-172. Gate-6 results recorded before 2026-10-11 should therefore
be read as taken on 2.5.0, unless their record names the version. That includes the Sprint 13
end-of-sprint sweep, which says "hex 2.5.1, at the floor" without showing how that was measured.
Every gate-6 run this sprint after MES-172, and the end-of-sprint sweep below, was on 2.5.1.

## S14-6 — two seats misread the harness path the same way

On MES-175, CC reported the pinned harness absent: it looked for `/tmp/conf11/dist/index.js`. On
MES-173, codex made the same mistake. The harness is at
`/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js`. The PM verified its
sha256 as `a10085d0…`.

Two different engines made the same misreading, so the cause was the wording and not the seat.
`gate-7.md` now spells out the full path (MES-175).

## S14-7 — smaller findings (backlog or noted)

- **MES-176** (backlog): the register control [26] dies on guard 21 when an `oc_reason` spans
  several lines. This was already true on main. Found by CR on MES-174 (F3).
- **MES-173** (backlog, parked): the `--emit-spec` re-count trap. It holds codex's plan, which was
  written from a truncated CLAUDE.md and has to be re-checked against the full procedure before use.
- **CR's MES-166 item** (optional hardening, not ticketed): the R cases could assert the total
  stray count, not just the named strays.
- **CR's MES-174 F2:** two elided quotes. No edit was made; they are carried into MES-178.
- **The sweep cost figure in the end-of-sprint step was stale** (it said 25–30 min). MES-177 AC7
  replaced it with the figure measured on MES-174: 119 min 26 s at 1790 tests. This sprint's sweep
  took 119 min 40 s at 1800 tests (below).
- **acm reported as a defect, not worked around:** see S14-1.

## S14-8 — behaviour changes shipped (for the next release notes)

- Dependency: mint 1.10.1 → 1.10.2 (security: EEF-CVE-2026-94194, -91043, -92103).
- No `lib/` behaviour change.

## End-of-sprint sweeps (at the final tip `2.0.0-dev.83` / `44d1cbe`)

**Dependency-advisory sweep (the two-step gate 6).** hex 2.5.1 (`mix hex --version`: `Hex
v2.5.1`). The script is `docs/procedure/gate-6.md`, run on main at 44d1cbe with a clean tree.

- **6a:** no `GATE 6 FAILS` line, so all 22 known advisory ids were present in the baseline audit.
- **6b:** `No retired or security advisory packages found`.
- Script exit 0. **Clean; no advisory, so no ticket.**

**Publication sweep (`mix origin.sync`, run point c).** GREEN at `2.0.0-dev.83`:

```text
  GREEN C1  origin is reachable and readable
  GREEN C2  live refs/heads/main on origin == local main          (both at 44d1cbe4bc5a)
  GREEN C3  the version's tag exists locally and is annotated     (4b9c081761e6 -> 44d1cbe4bc5a)
  GREEN C4  that tag is on origin, as the same object
  GREEN C5  the tag peels to an ancestor-or-equal of local main
  IN SYNC — main and the version's tag are both published as held.
```

**Boundary-liveness sweep (`mix conformance.sweep --check`).** The sweep was **owed**, and it was
**run**. The last sweep tip was e74bf3f, where the table was regenerated by MES-174. The three
skip conditions came out as follows:

- (a) `git diff --name-only e74bf3f...44d1cbe -- lib/` is empty.
- (b) `git diff --name-only e74bf3f...44d1cbe -- test/ test/support/ conformance/lib/` lists 5
  files: `boundary_sweep.ex`, `claude_md_cap.ex`, `etcc_register.ex`, `conformance.sweep.ex` and
  `test/conformance/claude_md_cap_test.exs`.
- (c) The host fingerprint is `node=v24.13.0 harness=available`, both in the committed table's
  `control.host` and in this run's.

Condition (b) is non-empty, so the sweep runs. The run:

- Command: `mix conformance.sweep --check --out /tmp/s14sweep/full.json`.
- Where: a dedicated worktree at 44d1cbe, started detached.
- When: 20:09:52 to 22:09:32 UTC, so 119 min 40 s.
- Result: **exit 0**. Afterwards the worktree was clean, so `lib/` was restored.

```text
== VERDICT DIFF (AC5 — this is the loud one) ==
  none — every verdict field reproduces byte-exactly.
== BASELINE PROBE (reported not raised on) ==
  unchanged — the probe's baseline fingerprint matches control.probe.
== L2 CARRIED FORWARD (reported not raised on) ==
  3 LIVE verdict(s) decided by L2 stand over a probe that moved NOTHING this run —
  carried forward from the record, not re-measured:
    MCP.Server.Connection
    MCP.Server.NotificationCollector
    MCP.Transport.Stdio
== MEASUREMENT DELTA (§2.3(e), reported not raised on) ==
  50 direction(s) differ on measurement fields only: suite_summary (all 50)
```

**What was actually re-measured.**

- **L1:** all 50 directions.
- **L2:** fired on 29 directions. The probe's baseline is sighted: `control.probe` records distinct
  15 of scenarios 15. 26 of those 29 verdicts were measured this run.
- **Carried forward:** the other 3 L2 verdicts were not re-measured (MES-178).

Verdicts at 44d1cbe: 31 live (21 by L1, 10 by L2) and 19 dead (by L2).

**The measurement delta is the unit population, and nothing else.** Every direction's
`suite_summary` went from `24 doctests, 1790 tests` to `24 doctests, 1800 tests`. The 10 new units
are the 10 tests in `test/conformance/claude_md_cap_test.exs` (MES-177). None of them moved a
verdict.

**No drift, so no ticket.** The committed table still records 1790 in its `suite_summary` fields.
Refreshing those fields is a data change under `conformance/`, and is left to the next ticket that
regenerates the table. It is not made in this register.

## Open for the PO at this boundary

1. **Gate 8 trigger.** Widen it from `lib/` to also cover `conformance/data/etcc-boundaries.json`
   and the guard sources (`boundary_sweep.ex`, `conformance.sweep.ex`)? Yes or no.
2. **Amend Confluence 250052681?** The amendment would:
   - make D7 and D10 say "`CLAUDE.md` or `docs/procedure/`";
   - make the stale gate counts count-free: D6's "six-gate set", A9's standard gate set, D8 item 6,
     and "every one of the six";
   - add a D11 entry recording gate 8.

   Yes or no.
3. **PO form 30524 on MES-96** is still unanswered. It decides what Sprint 15 holds.
