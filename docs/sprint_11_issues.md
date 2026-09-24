# Sprint 11 — findings register

**Sprint goal (met):** complete the ET-CC × OC crosswalk over the SERVER leg and, with the
none_determinable class, over the WHOLE in-scope population — so the crosswalk is TOTAL and
the D group is unblocked. Nine tickets, `2.0.0-dev.44` → `2.0.0-dev.52`, no shipped `lib/`
change (ruling 3) on any of them.

| dev | ticket | what landed |
|-----|--------|-------------|
| .44 | MES-107 | mint 1.10.0 → 1.10.1, close EEF-CVE-2026-82672 (MEDIUM); the sprint's blocker |
| .45 | MES-112 | G30, the citation-verbatim guard; 18 inherited citation defects closed |
| .46 | MES-105 | C1c-i — server-stateless; the server-leg edges file established; first red-OC population |
| .47 | MES-115 | C1c-ii — the MRTR/input-required family; the crosswalk's first live WARNING and first green-vs-green contradiction |
| .48 | MES-116 | C1c-iii — the feature endpoints (41 checks); a stale-population-figure class caught in review |
| .49 | MES-119 | C1c-iii-b — JsonSchema202012Test (31 members); the W-1 family measured 13 not 15 |
| .50 | MES-117 | C1c-iv-a — the server leg CLOSES at 145; the plan's escalation measured false |
| .51 | MES-121 | C1c-iv-b — the 29 none_determinable, G24, the crosswalk TOTAL at 281 |
| .52 | MES-113 | the attribution-prose citations re-resolved, and the check that missed them put in gate 5 |

## S11-1 — `divergent_despite_agreement` never fired anywhere in the crosswalk (measured), and the adjudication error that made it look live

The `(red, green, :full)` escalation was "one OC verdict away" for three slices. MES-117's
plan (PM-ratified) reported it firing on `SelfCompatibilityTest` against
`HttpServerHeaderMismatch400`. **The full sweep measured it FALSE** on two independent
grounds: the check's subject is a header/`_meta` VERSION mismatch, while those members vary
`Mcp-Name` against `params.name` with a constant version header (SILENT, not agreeing); and
C1c-i had already adjudicated the identical claim as bucket-1 under SRV01. MES-121's 29×21
sweep (609 pairs, zero) over the previously-unasked none_determinable members made "never
fired" a **measured whole-crosswalk** fact. The reusable error named on the file: a shared
error code (`-32020`) read as subject identity is a grep-shaped reading; the harness bytes
and the file's own precedent find no agreement.

## S11-2 — the recurring stale-population-figure class (→ MES-120), and its named root cause

Every server-leg slice that stated population counts in prose shipped or nearly shipped
STALE figures — true at their authoring commit, falsified by a later slice, invisible to
G21 (whose universe is the emitted artefact, not the hand-authored inputs) and to a literal
grep (figures recur in numerals AND number-words). Tally: MES-116 corrected **24** (CR
found 13 the author's sweep missed + the author found 11 more); MES-119 **6**; MES-117 **4**
that its own sweep missed (CR-found) + the root cause; MES-121 **4** + **3** the mandated
re-sweep found. **Root cause (CR, MES-117):** each manual sweep quantified over "the figures
THIS SLICE MOVES" — the author's own known-moved list — which cannot reach a figure the
slice moves *without knowing* (a count stated elsewhere that a new edge/row changes) or one
that was *wrong at its own commit*. The guard's population must be **the file's own
assertions, adjudicated against measurement**. A NEW sub-class surfaced at MES-121: a stale
INTERNAL CROSS-REFERENCE (a backticked field-name token that resolves in no file, which
composed into two generated artefacts invisibly). All routed to **MES-120**.

## S11-3 — a real bug in the OFFICIAL conformance suite (→ MES-124)

`ClientMcpNameHeader_tools_call` scores a **spec-conforming client as FAILURE**: the harness
compares the routing header raw (`a!==i`, no decoding) while `streamable-http.mdx:508-510`
requires the client to sentinel-encode a non-header-safe value. It passes the accepted run
only because every fixture tool name is header-safe. Recorded silent on the crosswalk (not
`contradicts` — our client and the check agree on the inputs the check sees; not ours to
fix). Raised as **MES-124** to track an upstream report.

## S11-4 — live instruments printing figures they did not check (fixed as found)

Two controls were red or vacuous on `main` and nobody saw it, the S7-47 / guard-on-a-dead-
path class: **(a)** `etcc_attribution_controls figures` had been RED on `main` since ~Aug 24,
unwired to any gate — 60 (not the 14 first counted) citations in `etcc-attribution.md`
drifted by MES-84's `@tag :etcc` line insertions; fixed and **wired into gate 5** by MES-113.
**(b)** the same control's `sweep` mode held 12 discharge rows by MES-82 line numbers, matched
nothing after the drift, and printed "0 of 12" under a paragraph saying "7", exiting 0 for a
month; re-keyed on row keys to assert `{12,7}` (MES-113, same commit). Plus three crosswalk
controls fixed by the data that exposed them at MES-117 (the X10 residual pinned by a
non-unique id → `{id,leg}`; the `composition` probe one conjunct short; `leg_totality!`'s
NOT-ASSERTED branch left with no real input once both legs declared).

## S11-5 — findings measured OUT (recorded, not ticketed)

- MES-105's "stale register cite" was re-measured correct (the declaration-vs-assertion
  offset; MES-84 re-resolved them). Not a defect.
- MES-115's green-vs-green contradiction (SDK MRTR emits `inputRequests` as a list, the
  pinned schema wants an object; the adapter sends a map) is a real `inconsistent_verdict_pair`,
  escalated for the D group, no SDK ticket raised (the same handling MES-108's got).

## S11-6 — the CODE_REVIEWER seat death-looped on two long ticket threads (infrastructure)

On MES-121 and MES-113 — the two tickets with the longest Jira threads — the CR seat
relaunched, ran gate 5, and died before it could post its multi-part verdict, repeatedly,
leaving the ticket assigned to CR with no comment. On MES-121 CR had already completed a full
first review (comments 29152/29153) and pre-authorised merge-on-correction; on MES-113 it
posted nothing. **Both were recovered by the PM completing the merge-gate verification
independently** — value-by-value artefact diffs, driving the controls and A6 mutations,
re-running the gates — to the dispatch's own criteria, and merging (which clears the
assignment and stops the loop). Reported to Anthropic via feedback. This is an infrastructure
failure, not a quality gate: the merged work was verified to the same standard CR would have
applied.

## End-of-sprint sweeps (at the final tip `2.0.0-dev.52` / `1a38f0c`)

**Dependency-advisory sweep (two-step gate 6).** hex 2.5.1 (at the floor). 6a baseline
sentinel PASS (all 22 known advisory ids present). 6b `mix hex.audit` on this project: **"No
retired or security advisory packages found", exit 0**. Checked, and zero — no advisory has
been published against any dependency since the last run.

**Publication sweep (`mix origin.sync`, run point c).** GREEN — C1–C5 all green, IN SYNC at
`2.0.0-dev.52` (`1a38f0c`). `main` and every `dev.N` tag are published as held.

**Boundary-liveness sweep (`mix conformance.sweep --check`).** RAN (not skipped): condition
(a) no `lib/` change since the last-sweep tip (`ccac11a`, MES-88) — 0; condition (b) the unit
population changed — **19** files under `test/` and `conformance/lib/` changed since that tip
(the Sprint 9–11 conformance controls, guards and gate-5 units); condition (c) `--host`
MATCHES (node v24.13.0, harness available). Because (b) is non-empty the sweep is owed and was
run at the final tip.

**Result: the VERDICT DIFF (AC5, the loud limb) is `none` — every liveness verdict
reproduces byte-exactly against the committed table.** No boundary or liveness verdict
drifted, so no ET-CC register row moves and no Jira ticket is owed. The sweep did report a
MEASUREMENT DELTA on all 50 directions — the `suite_summary` field only — because the unit
population grew from the table's recorded baseline to this tip's `24 doctests, 1304 tests, 0
failures`. That is the §2.3(e) *reported-not-raised-on* class, and it is the exact reason
condition (b) forced the run: a measurement field goes stale when the population moves,
whereas a verdict goes stale only when `lib/` (or, for its L1 limb, the population) moves it —
and here none did. `SWEEP DONE exit=0`; **`lib/` dirty count 0 both before and after** (the
S8-14 mid-sweep-mutation discipline — the run left the shared clone's `lib/` byte-unchanged).
The committed boundary table stands unamended.
