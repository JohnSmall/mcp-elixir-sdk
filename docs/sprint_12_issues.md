# Sprint 12 — findings register

**Sprint goal (met):** the remediation half of the D group (epic MES-96). The goal was to
adjudicate every check in buckets 4a, 4b, 2b and 2a, which are the lists that remediation (E3)
works from. The escalations that A3 could not place were to be resolved in the same sprint.
Ten tickets, `2.0.0-dev.53` → `2.0.0-dev.61`, plus one PM Task. No ticket shipped a `lib/`
change (ruling 3).

| dev | ticket | what landed |
|-----|--------|-------------|
| .53 | MES-120 | G31: every population figure stated in the conformance inputs is measured, dated or refused |
| .54 | MES-110 | A3 amendment: every crosswalk edge has a home. All-silent means no match; unmatched is a claim-level state; each escalation has an owner |
| .55 | MES-111 | The nine ClientRejectsInvalidTool_* units are ET-ADJ and correctly untagged. The counterfactual is committed as a control |
| .56 | MES-126 | D4a: bucket 4a and the escalated view adjudicated. G32, the D-group adjudication guard. R1/R3/R6 put to the PO |
| .57 | MES-127 | D4b: bucket 4b adjudicated (2 extend_test, 4 accept_bound). Each row's et_test is tied to its member's own test |
| .58 | MES-128 | D2b: bucket 2b, the client build list (12 extend_to_match, 3 build_test) |
| .59 | MES-129 | D2a-i: bucket 2a's MRTR slice (30) in an OPEN section. blocked_on_sdk_gap added; landing conditions pinned |
| .60 | MES-130 | D2a-ii: bucket 2a's other 48 checks, which CLOSE the view. The two slices partition it |
| .61 | MES-136 | The PO's R1/R3/R6 ruling (all YES) written into the D4a and D2a-ii records |
| —   | MES-114 | PM Task: overrides page D9 (the PM polls for the baton) and the A12 transition-row correction |

## S12-1 — MES-129 took four correction rounds (B1–B6), and MES-130 took one because the lessons were written into its brief in advance

The defects were all one class. A record field **derived** from other fields disagreed with
the rule it was derived by:
- B1: depends_on_fix did not match its own criterion.
- B2/B3: remedies understated their SDK gaps.
- B4: remedies overstated their SDK gaps.
- B5: a self-declaring condition catalogue.
- B6: citation windows off by one line. The line numbers were the reviewer's own.

Each round closed exactly one instance. The class closed only when the PM stated closure
rules **in advance** (29472): hold every derived set to its criterion both ways; keep a pinned
catalogue; check each citation window with `cat -n`. MES-130's brief carried these as
rules, and its single round (B1, why_green windows) was the same class, caught by the same
discipline. **Carry forward:** Sprint 13's D tickets (buckets 1/5a/5b/3/6) inherit these
rules in their briefs.

## S12-2 — the PO decision request had no yes/no form (the PO caught it)

MES-126's acceptance required "the PO question is posted on this ticket in yes/no form". The
questions were spread across two prose comments (29407, and 29420, which superseded 29407's
Q1), with nowhere to record an answer. The ticket merged and closed with the gap open. The
PO flagged it at sprint close. Fixed: a single form, 29508, answered in session and recorded
as ruling 29509, all YES. The SDK scope went to MES-43 (29510) and the record update became
MES-136, which the PO pulled into this sprint. **Rule adopted (PM memory):** a PO question is
always ONE table with an answer column. When a question is superseded, the whole form is
re-posted.

## S12-3 — sprint-board statuses lagged because the A12 table was stale (the PO caught it)

MES-129 and MES-130 sat in To Do through planning and execution. The cause: A12 still
assigned the early transitions to CODE_CREATOR, but since D5, `jira_transition` is PM-only.
The PM made the moves only at review hops. Fixed in the same sprint: A12's row was corrected
on the overrides page (v16, with MES-114's ratification), and the PM moves the status at
dispatch and at ratification.

## S12-4 — MES-43 did not carry the SDK gaps routed to it; now it does

The Sprint 4 escalation table routes eight gaps to MES-43, but its body carried two. Every
blocked_on_sdk_gap row needs an owning record the ticket actually carries (ruling 29460), so
the missing gaps were added as comments:
- 29410: R2, the status mapping
- 29459: the continuation drop and the resultType overwrite
- 29464: InputResponseRequestParams validation
- 29490: the error data slot
- 29494: logLevel and the resource_not_found data shape
- 29510: the PO's four rulings

**Numbering hazard (F2):** "gap N" means different things on MES-43's body and in the
Sprint 4 table. Cite by address and bytes only, and renumber when MES-43 is scheduled.

## S12-4a — the PO's R1/R3/R6 ruling closed the sprint's open decisions

All four questions were answered YES (29509). MES-136, which the PO pulled into the sprint,
wrote the ruling into the records:
- D4a's four rows become fix_sdk.
- D2a-ii's seven rows become blocked_on_sdk_gap, owned by MES-43 29510, one landing
  condition per ruled bullet.
- No po_decision_required row remains. The disposition itself stays in G32's closed set.

CR found the class again (B1): the new ruling clause let an owner_record derive nothing. It
was fixed by requiring every catalogued phrase an owner_record names to derive a condition,
checked over all five records.

## S12-5 — findings held for the backlog (no owner yet)

- **F4 (MES-130):** nothing in `lib/` validates tool names against SEP-986. The SDK passes the
  handler's names through. No ticket owns this. → raise at Sprint 13 planning.
- **N3 (MES-130 review):** the Confluence mirror 275972334's slice-i table does not render
  lands_when, but slice ii's does. A layout gap in MES-129's mirror.
- **N5 (a)–(d) (MES-130 review):** four why_green clauses are true but uncited, or broader than
  their window. Not a correctness defect, because the SDK-earning bytes are cited.
- **G31 blind to "conditions" (MES-136 F8):** the phrase "shared by four conditions" is a
  count that G31 does not see, because "conditions" is not in its noun list
  (`input_figures.ex:124`). This is the documented "noun not in the list" limitation, and
  MES-131 is the owner.
- **The every-record unit's record list is hand-held (MES-136 review N3):** the list is
  `[@d4a, @d4b, @d2b, @d2ai, @d2aii]`. It equals the directory today, but a sixth
  adjudication record, as Sprint 13 will add, would not be walked. → the first Sprint 13
  D ticket derives the list from the directory.
- **G32 reporting (MES-130 F7 → MES-135):** a missing or duplicate row is attributed to the
  first section's file.
- **Published report staleness (→ MES-74):** R4 "UNOWNED" (29497), R1 "gap 5" (29501), and the
  R3/R6 decision row now ruled (29533).

## S12-6 — an overnight stall of ~8 h (infrastructure / PM procedure)

On MES-110, the PM re-handed the ticket to CODE_CREATOR before that seat's engine had exited.
`seat_loop.sh`'s edge marker read the same ticket for the same seat as already handled, and
no PICKUP followed until 04:38. **Rule adopted (PM memory):** confirm a PICKUP newer than
each handoff, and record the handoff timestamp before handing off. No stall recurred after
it.

## End-of-sprint sweeps (at the final tip ``2.0.0-dev.61` / `5047a0e``)

**Dependency-advisory sweep (the two-step gate 6).** hex 2.5.1, at the floor. The 6a
baseline sentinel PASSES: all 22 known advisory ids are present. 6b, `mix hex.audit` on this
project, reports **"No retired or security advisory packages found", exit 0**. Checked, and
zero: no advisory has been published against any dependency since the Sprint 11 run.

**Publication sweep (`mix origin.sync`, run point c).** GREEN: C1–C5 all green and IN SYNC at
`2.0.0-dev.61` (`5047a0e`). The tag a536c3709c59 is the same object on origin.

**Boundary-liveness sweep (`mix conformance.sweep --check`).** RAN, not skipped. The last
sweep tip is `1a38f0c` (the Sprint 11 close). The three skip conditions:
- (a) `git diff --name-only 1a38f0c...HEAD -- lib/` gives **0** files.
- (b) `git diff --name-only 1a38f0c...HEAD -- test/ test/support/ conformance/lib/` gives
  **12** files: the G31/G32 guards and their gate-5 units, the crosswalk and bucket-projection
  changes, and one fixture.
- (c) `mix conformance.sweep --host` MATCHES: node=v24.13.0, harness=available, recorded and
  current.

(b) is non-empty, so the sweep was owed and was run at the final tip. The baseline was
`24 doctests, 1466 tests, 0 failures`. `lib/` was dirty 0 before the run and 0 after.

**Result: `SWEEP DONE exit=1`. ONE VERDICT DRIFTED (AC5, the loud limb):**

```
DRIFTED  MCP.Protocol.Error (encode)
   verdict: "dead" -> "live"
   established_by: "L2" -> "L1"
   would move 0 ET-CC row(s)
```

The committed row (`etcc-register.md:1097`) reads reddened 3, outside 1, live **0**, DEAD.
This tip measures reddened 4, outside 2, live **1**. `lib/` did not move. A unit added to the
suite since `1a38f0c` reddens under the Error-encode mutation, which is the §2.3(e)
**test-only** move that MES-88 predicted. No ET-CC row names this direction, so no register
row moves. The figure "50 boundary-directions, 19 dead" does move, to 18, unless the new unit
is ruled into the exclusion set. **→ MES-137**, per the procedure: not fixed in place.

Every other direction reported only the `suite_summary` MEASUREMENT DELTA, because the
population grew from 1304 to 1466 tests. That delta is reported, not raised on.
MCP.Server.Dispatch also moved its `reddened_by_module` and `live_units` fields, but its
verdict did not change.
