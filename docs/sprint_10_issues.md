# Sprint 10 — procedure defects

Procedure defects found while working Sprint 10 (epic MES-96, the ET-CC × OC
crosswalk — the client leg C1b-i / ii / iii). Things wrong with **how we work** —
the planning step, the board/page/goal surfaces, the gate and control wiring.

Ticket substance does not go here. Findings about the MCP SDK itself, about
conformance results, or about a specific ticket's deliverable belong in comments
on that ticket. This file is for defects a *future* sprint would otherwise hit
again.

Each entry states the **mechanism**, because the mechanism is the transferable
part.

---

## S10-1 — A sprint's tickets were sized by epic structure, not measured, so the split landed after the board was already built

**Found:** Sprint 10 planning → close, 2026-09-21, by the PM. Not a ticket; a
planning-process defect. The lesson is recorded and applied going forward.

**The defect.** At planning I scoped Sprint 10 as C1b (MES-104) + C1c (MES-105) —
one ticket per epic leg — and you populated the Jira board from that list. Only at
the *dispatch* hop did CC's survey measure the client leg (C1b) at ~89 unadjudicated
members / 42 checks / ~130 edges = **5.1× C1a's members**, forcing the split into
C1b-i/ii/iii (MES-104/108/109) and the deferral of C1c to Sprint 11. The split
therefore landed *after* the board was built.

**The mechanism, and it is the transferable part.** The measurement that forced the
split was **knowable at planning**: the member/check/CG counts are a query over
artefacts that already existed (the ET-CC register, A4's attribution, the OC
manifest), and C1a (MES-97) had *just* overrun its own plan ~3× — a standing
precedent that structural sizing under-counts this crosswalk work. Only the exact
edge count and per-check axis cost are read at the build (ruling 7); they refine the
estimate, they do not erase the gross 3–5× signal. Sizing a ticket by its *position
in the epic* rather than by *measuring the population it names* is the error, and it
is distinct from the reactive "split when it turns out too big" lesson: the survey
must be the **opening move of planning**, before the ticket list exists, compared to
a calibrated done ticket.

**Consequence.** The whole of S10-2 — the desynced board — follows from this one:
because the split came after the board was populated, the board described a plan
already abandoned.

---

## S10-2 — A mid-planning re-scope updated the Confluence page but not the Jira board or the sprint-goal field

**Found:** Sprint 10 close, 2026-09-23, by the PM (raised by the PO: "I can't close
the sprint because MES-105 has not been done").

**The defect.** When C1b was split and Sprint 10 re-scoped to "the client leg", I
revised the master page (303988960) to v2 — new title, new three-ticket table, an
explicit "Not this sprint: MES-105 → Sprint 11" section, and a board note directing
exactly the membership change. But the **Jira board** was left on the pre-split list
(MES-104 + MES-105), the two tickets that did the work (MES-108, MES-109) were in
**no sprint at all** (`customfield_10020: null`), and the **Jira sprint-goal field**
still held the pre-revision "full crosswalk" goal. MES-105 (C1c, server leg, really
Sprint 11) sat in the sprint blocking closure.

**The mechanism, and it is the transferable part.** A sprint has **three surfaces** —
the Confluence master page, the Jira board membership (`customfield_10020`), and the
Jira sprint-goal field. A re-scope that touches only the page leaves the other two
describing the abandoned plan, and the one that blocks closure (board membership) is
the one a page edit does not touch. Reconcile **all three** on any re-scope. Board
membership is API-settable from the PM seat (`editJiraIssue customfield_10020 =
<sprint id>`; `null` to remove) once the sprint id is known — read the id off a ticket
already correctly in the sprint (here MES-104 → sprint 1323), never guess it.

**Fixed at close:** MES-108 and MES-109 set to sprint 1323, MES-105 cleared to
backlog; the sprint then held exactly {MES-104, MES-108, MES-109}, all Done.

---

## S10-3 — A control was red on `main` for a month, unseen, because nothing runs it

**Found:** MES-109's review (CC found it, CR confirmed at `d5cac00` and `main`);
**verified first-hand by the PM** at the end-of-sprint sweep, 2026-09-23. **Ticketed
as MES-113.**

**The defect.** `mix run conformance/controls/etcc_attribution_controls.exs figures`
exits **1** at `main` (`120e7d6`): `ENUMERATION INCOMPLETE` — 9 `cg: CG7` addresses
(`header_mirror_test.exs` 330/336/345/354/382/389/422/472/479) and 5
`leg: none_determinable` addresses (`extensions_test.exs` 387/393/408/427/440) are
counted in the attribution artefact but not cited at their address in the attribution
markdown. The control script and every input it reads were unchanged in Sprint 10 and
last changed **2026-08-24** (`18df3a6`), so it has been red since **before Sprint 9**.

**The mechanism, and it is the transferable part.** `etcc_attribution_controls.exs` is
a `mix run` control — **not wired into gate 5** (so `mix test` is green over it) and
**not in the end-of-sprint sweep set** (dependency / boundary-liveness / publication).
A control nothing runs is a control whose red nobody sees: the guard-on-a-dead-path /
S7-47 shape at the level of a whole control script. It surfaced this sprint only
because a ticket's review happened to run the control surface by hand. The systemic
half — decide whether the control surface is driven by a gate or a sweep so a red
cannot rot unseen — is MES-113's, and matters more than the 14 addresses.

---

## S10-4 — The "generated banner pinned by a constant-vs-itself unit" shape (guard-19) recurred twice in one sprint

**Found:** MES-104 (CR-1) and MES-108 (CR-5), both blocking, both corrected in-ticket.

**The defect.** Twice in one sprint, a regenerated bucket/crosswalk artefact carried a
**stale population banner** — MES-104's 12 bucket views still declared C1a's 21/14
population; MES-108's crosswalk generator still declared a hard-coded
`trust_status` — each **pinned green by a unit comparing the view against the module's
own constant** (`banner() == banner()`), which cannot fail. It is guard-19's shape: a
guard that stays green while the thing under it rots.

**The mechanism, and it is the transferable part.** The MES-104 fix (interpolate every
figure from the derived population; a `:population_statement` guard) did **not** prevent
MES-108's recurrence, because MES-108 emitted a *different* banner in a *different*
file that the MES-104 guard did not enumerate. A guard that lists the statements it
checks cannot cover a statement a later ticket adds. The durable fix, landed in
MES-108, is **G21 — a guard whose universe is the emitted artefact itself** (a string is
generator-authored iff it occurs in no input document), so a banner a future ticket
adds is guarded without being listed. Transferable rule: any ticket that emits a
population figure into a generated artefact must interpolate it from the derived
population **and** be covered by a guard scoped to the artefact, not to a hand-list of
known banners. Re-render against sentinels (catches a literal) **plus** a phrase pin
(catches the wrong figure in the right slot); a constant-vs-itself unit is not evidence.

---

## Sprint 10 close-out — the end-of-sprint sweeps

Run against `main` at the sprint's final tip **`120e7d6` / `2.0.0-dev.43`**, 2026-09-23,
PM-owned. The sprint's three tickets (MES-104 dev.41, MES-108 dev.42, MES-109 dev.43)
are all Done; the client leg is closed by refusal (107 members, 54 checks).

### Dependency-advisory sweep (two-step gate 6) — one advisory, already ticketed

- **Not skippable** (cadence sweep; the gate-6 applicability rule does not apply here).
  Hex **v2.5.1** (meets the ≥2.5.1 floor).
- **Gate 6a PASS** — all 22 known baseline advisory ids present, so local advisory data
  is intact and a 6b green would mean something.
- **Gate 6b — exit 1, one advisory:** `mint 1.10.0 — EEF-CVE-2026-82672 (MEDIUM)`
  (HTTP/1 response smuggling via an unvalidated chunk-size line tail; `mint` is a
  runtime transitive dep on the transport path). This is the **same advisory Sprint 9
  raised as MES-107**, still open and **not remediated in Sprint 10** — the PO scoped
  the sprint to the three client-leg tickets and did not slot in the optional MES-107
  bump the master page offered. **No new ticket; tracked by MES-107.** The question was
  printed, not just the answer: checked, and one, and it is the one we already hold.

### Boundary-liveness sweep (`mix conformance.sweep --check`) — OWED, ran

- **Not skippable.** The three-condition skip requires all three clean; only (a) is:
  - **(a)** `git diff <ccac11a>...HEAD -- lib/` → **empty** (no `lib/` change since the
    MES-88 sweep tip).
  - **(b)** `git diff <ccac11a>...HEAD -- test/ test/support/ conformance/lib/` →
    **NON-EMPTY** (14 files: the Sprint 10 crosswalk/bucket/citation/locator/origin-sync
    libs and their tests). The unit population moved and the liveness proxy L1 quantifies
    over the suite, so a verdict can move — the sweep is owed.
  - **(c)** `mix conformance.sweep --host` → **host matches** (`node v24.13.0 /
    harness=available`), exit 0.
- Baseline at the delivered tip: `24 doctests, 1259 tests, 0 failures`, node present.
- **Result — VERDICT DIFF: none.** Every verdict field reproduces byte-exactly across
  all 50 directions at the new 1259-unit population; the register's boundary and
  liveness verdicts still hold, so **no ticket**. A **measurement delta** was reported
  (not raised on, §2.3(e)) — all 50 directions differ on `suite_summary`, and
  `MCP.Server.Dispatch` additionally on `reddened_by_module` / `live_units` — whose
  cause the sweep names as the unit population moving, not `lib/`. The committed table's
  measurement fields are therefore informationally stale (as they have been since MES-88,
  by design — §2.3(e) tolerates a measurement delta and re-baselining is explicit, not
  per-sprint); the guarded verdict fields are clean. Ran in a dedicated worktree; the
  S8-14 check confirms `lib/` was restored after the run.

### Publication sweep (`mix origin.sync`) — IN SYNC

- C1–C5 green at `120e7d6`: `main` and the `2.0.0-dev.43` annotated tag
  (`2064533b6ba6`) are both on origin as the same objects. Every Sprint 10 merge was
  published as held. Never skipped, no applicability rule.

### Findings routed and tickets

- **New this sweep:** **MES-113** — `etcc_attribution_controls figures` red on `main`
  and unwired to any gate (S10-3).
- **Persisting advisory:** **MES-107** (mint EEF-CVE-2026-82672 MEDIUM), unremediated.
- **Routed during the sprint (ticket substance, on their tickets):** MES-110 (A3 §6
  claim-level state), MES-111 (tested-but-untagged ClientRejectsInvalidTool_* classes),
  MES-112 (the general citation-verbatim guard + C1a's off-by-one citations). MES-108
  surfaced the epic's first **live ET-CC × OC contradiction** (the official harness fails
  a conformant client on three `ClientMcpNameHeader_*` edges) — escalated on the
  crosswalk as inconsistent_verdict_pairs, the D group inherits it.
- **CR's non-blocking MES-109 findings** (recorded on the ticket, for C1c's brief / the
  last-leg closer): the `[^|]` field boundary is not measurably load-bearing; nothing
  compares `@searched_fields` against each entry's declared `population.fields`; the
  derived guard-8 probe will RAISE when C1c closes the last leg; a close-out
  search-spread figure ("eight cover exactly 1" — really 9×1 over 19 / 7×1 over 17) that
  reconciles to no committed artefact.

**Sprint 10 closed clean but for one carried dependency advisory (MES-107) and one
pre-existing control failure now ticketed (MES-113).** No boundary verdict on `main`
regressed (VERDICT DIFF none), and every merge is published.
