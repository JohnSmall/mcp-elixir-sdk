# Sprint 3 — Issues and Decisions

Project: MCP_Elixir_SDK (Jira key MES) · Working Procedure pin: Global v2 · Methodology pin: Global v1

This file is the local issue log (WP rules #3, #8). At sprint close it is copied to Confluence as
`Sprint 3 Issues and Decisions`, a child of the Sprint 3 page (WP rule #7 precondition).

**Sprint goal (met):** migrate the SDK to the MCP **2026-07-28 stateless core** — no `initialize`
handshake, no session, per-request identity — across four tickets under epic **MES-12**.

**Tickets (all Done):** MES-7 (identity-threading design spec) · MES-8 (stateless protocol core) ·
MES-9 (stateless Streamable-HTTP transport) · MES-10 (identity seam v2 — acceptance + hardening).
**MES-11** is closed **Won't Do** (duplicate epic — see below).

> **Provenance / back-fill note (I14).** This file was **back-filled on 2026-07-31**. It was not
> maintained per-ticket during the sprint — rules #3, #8, and #12(9–10) require a per-ticket issues
> record that was missed on all four tickets (the process gap logged as **I14 / P8**). **No content is
> reconstructed from memory:** every entry below traces to a published Confluence page (id cited), a
> review finding, or a PM ruling. The single source of truth is the **Sprint 3 retrospective evidence
> log** (page `247431169`), whose entries are cited as `I1`–`I14`, `P1`–`P8`. Where the evidence log
> is silent on a detail, the entry **flags** it rather than inventing content.
>
> **Entry format (rule #8):** Source Ticket / Type (Bug|Gap|Improvement|Question) / Description /
> Recommendation / Priority Hint / Blocking? / Suggested Jira Ticket?.

---

## Cross-ticket root causes and process (rule #8 consolidation)

The two root causes below recurred across tickets and are consolidated here with per-ticket
back-pointers, per rule #8. The remaining sprint-level entries are genuinely cross-cutting (they do
not attach to a single ticket).

### Issue: Claim-vs-artefact divergence (recurring root cause)

- **Source Ticket:** Sprint 3 — recurred in MES-8, MES-9, MES-10 (prior surfacings in Sprint 2)
- **Type:** Improvement
- **Description:** Completion reports repeatedly claimed "X removed / asserted / verified" against a
  working copy or a *description* of a check rather than the committed branch or published artefact.
  Instances: Sprint 2 HexDocs packaged-contents; the D2 v2 lost-MC-1-block; MES-8 F2/F4 (":ready gone"
  and "prompts/get spoof asserted" claims vs committed source); MES-9 F3 (a moduledoc still described
  a fallback deleted in MES-8 — docs are claims too); MES-10 I13 (a security clear that read a `nil`
  key would have *appeared* to close a leak it left open). Codified as **Note C / P2**, with extensions
  **P2a** (removal greps must include docs, not just code) and **P2b** (the cited check must be a
  literally reproducible command, not a description of one).
- **Recommendation:** Keep Note C in force; route P2b items to the reviewer; carry P2/P2a/P2b into the
  Working Procedure global v3 codification batch.
- **Priority Hint:** High (the sprint's most frequent defect class)
- **Blocking?:** No (mitigated in-sprint; no open instance)
- **Suggested Jira Ticket?:** WP global v3 codification (Proposal protocol) — not a code ticket
- **Per-ticket back-pointers:** MES-8 (F2, F4, and the positive instance I5) · MES-9 (F3 / I8) ·
  MES-10 (I13). Source: `247431169` §1 P2/P2a/P2b, §3 I5/I8/I13.

### Issue: Schema-vs-narrative verification for wire-shape items (recurring root cause)

- **Source Ticket:** Sprint 3 — decisive instance MES-8
- **Type:** Improvement
- **Description:** Narrative surfaces (spec changelogs, derived classifications) do not settle a
  wire-shape question where a normative schema exists. MES-8 F5: D1's URL-mode-elicitation
  classification **survived two changelog-level reviews** and failed only at schema level against the
  pinned draft commit `7634684…`. Codified as **P4** and placed in the DoD by MES-8 Ruling 5.
- **Recommendation:** Keep schema-level verification in the DoD for all wire-shape items (applies to
  the Sprint 4 conformance work); verify against the pinned schema commit, not the changelog.
- **Priority Hint:** High (spec fidelity)
- **Blocking?:** No (in the DoD since MES-8 Ruling 5)
- **Suggested Jira Ticket?:** No — standing DoD item; Sprint 4 conformance ticket inherits it
- **Per-ticket back-pointer:** MES-8 (F5 / I3). Source: `247431169` §1 P4, §3 I3; MES-8 ratification
  `240550008` Ruling 5.

### Issue: Repo-side process obligations lacked a gate (the reason for this back-fill)

- **Source Ticket:** Sprint 3 — all four tickets (MES-7, MES-8, MES-9, MES-10)
- **Type:** Gap
- **Description:** Rules #3 / #8 / #12(9–10) require a per-ticket `docs/sprint_3_issues.md` entry.
  Nothing in any kickoff, DoD, or review checklist verified it, so it silently went unmet for four
  consecutive tickets **while every page-based obligation held**. Shared ownership, PM-weighted: CC
  missed the per-ticket obligation, but the PM authored every kickoff without rules #3/#8/#12(9–10),
  never verified it at a merge gate, and named it in no DoD. **The asymmetry is the lesson:** the
  obligations that held were the ones with gates; the one that lapsed had only a rule. No information
  was lost (material preserved in `247431169` and the published artefacts), so this is a back-fill, not
  a reconstruction. Codified as **P8**.
- **Recommendation:** Per **P8**, repo-side procedural artefacts (the issues file) must appear in the
  ticket DoD and the reviewer's checklist, exactly as gates and ledger arithmetic do. This file is the
  back-fill; the Confluence copy is the rule #7 precondition.
- **Priority Hint:** High
- **Blocking?:** **YES** — rule #7 precondition for sprint close (the back-filled file must be current
  and copied to Confluence as `Sprint 3 Issues and Decisions` before close).
- **Suggested Jira Ticket?:** WP global v3 codification (P8); no code ticket
- **Source:** `247431169` §3 I14, §1 P8.

### Issue: Escalate-and-wait convention adopted

- **Source Ticket:** Sprint 3 — surfaced MES-7 (/plan R1), MES-8 (/plan §4 ×2; WB-4 exemplar), MES-9
  (F2)
- **Type:** Improvement
- **Description:** When CC or Codex hits a problem needing a PM decision, they hand the ticket back
  (question stated in full on the in-flight page, one-line Jira pointer), and work on the blocked scope
  stops until the PM rules; fork-independent parallel work may be explicitly greenlit. A convention
  inside the existing 7-state lifecycle, not a new state. PO-directed 2026-07-26. Codified as **P1**.
- **Recommendation:** Carry P1 into the WP global v3 codification batch.
- **Priority Hint:** Medium
- **Blocking?:** No (in force)
- **Suggested Jira Ticket?:** WP global v3 codification (P1)
- **Source:** `247431169` §1 P1; MES-8 ratification `240550008` (Ruling 3 / WB-4 exemplar).

### Issue: Verify from the published artefact, not the working copy

- **Source Ticket:** Sprint 3 — in force since MES-7
- **Type:** Improvement
- **Description:** A discipline distinct from (but adjacent to) claim-evidence: check the *published*
  page / committed tree, not the local working copy that may diverge. Origin in Sprint 2 (HexDocs;
  D2 v2 lost block); **no recurrence** in Sprint 3. Codified as **P3**.
- **Recommendation:** Keep in force; fold into the WP v3 batch.
- **Priority Hint:** Low (matured; no open instance)
- **Blocking?:** No
- **Suggested Jira Ticket?:** WP global v3 codification (P3)
- **Source:** `247431169` §1 P3.

### Issue: PM self-accounting log (process self-correction)

- **Source Ticket:** Sprint 3 — cross-ticket
- **Type:** Improvement
- **Description:** Recorded PM misfires and their corrections, for the retro: (a) I1 initially
  misdiagnosed as the PM's own duplicate tool call — asserted as fact rather than hypothesis; (b) the
  MES-8 brief said "Logging … behaviour retained", written from ADR-002's summary before the spec
  pass, refined by Ruling 1; (c) the stale 24/30 conformance baseline hypothesised as client-mode was
  actually server-mode — **CC corrected the PM**; (d) the MES-10 brief scoped AC3/AC6′ while the later
  kickoff silently expanded it — **CC caught the discrepancy and forced a conscious ruling** (the
  scope-expansion confirmation on `246906881`); (e) a review-page title carried the wrong date from a
  stale kickoff template; (f) the largest — the I14 process gap.
- **Recommendation:** Keep the PM self-accounting habit; note that in (c) and (d) the Executor's
  independent check caught PM error — evidence for the value of the review/challenge loop.
- **Priority Hint:** Low
- **Blocking?:** No
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I11 (a–f).

### Issue: Checkpoint tag / commit-subject convention differs from rule #5/#20

- **Source Ticket:** Sprint 3 — all tickets
- **Type:** Question
- **Description:** Rule #5/#20 specifies annotated tags as semver patch increments, no leading `v`,
  message `[{TICKET_KEY}] <title>`, and commit subject `[{TICKET_KEY}] <title>`. Sprint 3 used
  descriptive checkpoint tags (`mes-7-stateless-identity-spec`, `mes-8-stateless-protocol-core`,
  `mes-9-stateless-transport`, `mes-10-identity-seam`) and `MES-N: <title>` commit subjects. Either a
  project Workflow Overrides entry sanctions this, or it is an undocumented divergence.
- **Recommendation:** PM to check the MES Workflow Overrides page before sprint close and record the
  answer (sanctioned override vs divergence to correct going forward). This is a PM action, not a code
  change.
- **Priority Hint:** Medium
- **Blocking?:** **Flag** — PM to resolve before sprint close (per the evidence log's convention check)
- **Suggested Jira Ticket?:** No — PM records the answer in the evidence log / overrides page
- **Source:** `247431169` §4 "Convention check outstanding".

---

## MES-7 — Identity-threading design spec

Done 2026-07-26 · merge `5ae503d` · tag `mes-7-stateless-identity-spec` · review:
approve-with-corrections (F1–F3) + 2 confirmations (`247431169` §4).

### Issue: SEP-index read discrepancy (instrument divergence)

- **Source Ticket:** MES-7 (underpins design deliverables D1/D3)
- **Type:** Question
- **Description:** On 2026-07-25 the PM's Confluence/SEP fetches (×3, one after the review) showed
  Final 32 / Draft 4 / Accepted 4 / In-review 1, while Codex reported "Final: 41". Hypothesis (never a
  finding): 41 = the total SEP count and the four "newly Final" were the entire Draft bucket —
  consistent with a flattened-page parse. Parked as **attributed, not asserted** (D1 FLAG 2 / D3 Part A
  hold the attribute-not-assert framing). Operationally moot since the 2026-07-28 final publication.
- **Recommendation:** Retain as an instrument-divergence record; no action. If SEP counts are cited in
  future, apply P5 (timestamp + verbatim quote of the decisive text).
- **Priority Hint:** Low
- **Blocking?:** No
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I2.

### Issue: External-surface claims should carry a timestamp + verbatim quote

- **Source Ticket:** MES-7 (SEP-index reads); prior surfacing RS-A
- **Type:** Improvement
- **Description:** Claims about external/volatile surfaces (spec pages, SEP index) should carry a
  fetch timestamp and a verbatim quote of the decisive text, so divergent reads (see I2) are
  adjudicable. Codified as **P5**; largely mooted by the pinned-commit provenance mechanism.
- **Recommendation:** Prefer pinned-commit provenance where one exists; otherwise timestamp + quote.
- **Priority Hint:** Low
- **Blocking?:** No
- **Suggested Jira Ticket?:** WP global v3 codification (P5)
- **Source:** `247431169` §1 P5.

### Issue: MES-7 review finding specifics (F1–F3) not present in the evidence log

- **Source Ticket:** MES-7
- **Type:** Question
- **Description:** The evidence log records the MES-7 review outcome as "approve-with-corrections
  (F1–F3) + 2 confirmations" (`247431169` §4) but does **not** carry the content of F1–F3. This
  back-fill will not invent them (rule #4). They are recoverable from the MES-7 review page if a full
  per-finding record is required.
- **Recommendation:** If the PM wants F1–F3 enumerated here, link the MES-7 review page and I will
  fold the verbatim findings in; otherwise this pointer suffices for the rule #7 section check.
- **Priority Hint:** Low
- **Blocking?:** No
- **Suggested Jira Ticket?:** No — flag for PM (escalate-and-wait)
- **Source:** `247431169` §4 (MES-7 row).

---

## MES-8 — Stateless protocol core

Done 2026-07-27 · merge `9a6150a` · tag `mes-8-stateless-protocol-core` · review: **REJECT** (5
findings F1–F5) → corrections → strict-condition bounce → MERGE-CLEAR. Rulings 1–5, Notes A–C
(`240550008`).

### Issue: F1 — `server/discover` result wire shape incomplete (spec-fidelity)

- **Source Ticket:** MES-8
- **Type:** Bug
- **Description:** The Discover result was missing schema-required fields (`supportedVersions`,
  `resultType`, `ttlMs`, `cacheScope` via `CacheableResult`, server identity in
  `_meta["io.modelcontextprotocol/serverInfo"]`). Structural schema requirement.
- **Recommendation:** Add the fields in MES-8 (done, Ruling 5 F1); caching semantics/policy deferred to
  MES-9. Verify against the pinned schema commit (see the schema-vs-narrative consolidation).
- **Priority Hint:** High (spec fidelity)
- **Blocking?:** No (fixed in the correction cycle)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I3; `240550008` Ruling 5 F1.

### Issue: F2 — readiness/handshake state (`:ready`) survived the de-session

- **Source Ticket:** MES-8
- **Type:** Gap
- **Description:** A ratified requirement was that no readiness/handshake lifecycle state survive
  anywhere; the review found `:ready` still present in the retained shell (its `get_status` exposure
  and `%{status: :ready}` gates). Contradicts Ruling 2's rider and Ruling 3 item 2.
- **Recommendation:** Remove the `:ready` state and all its gates (done; Ruling 4 declined the offered
  PM-relaxation — the ratified wording stood).
- **Priority Hint:** High
- **Blocking?:** No (fixed)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I3; `240550008` Ruling 4 (F2).

### Issue: F3 — MC-1 legacy no-context callback fallback still present

- **Source Ticket:** MES-8
- **Type:** Gap
- **Description:** `call/6` retained a legacy no-context-arity fallback, contradicting MC-1 (strict:
  context-bearing arity required for all eight identity-capable families) and PO ruling 2 (no dual-era
  support). A handler lacking the context arity is a contract error, not a fallback case.
- **Recommendation:** Remove the fallback; add context-threading depth tests for all eight callbacks
  (done; Ruling 4).
- **Priority Hint:** High (invariant-adjacent)
- **Blocking?:** No (fixed)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I3; `240550008` Ruling 4 (F3).

### Issue: F4 — missing `prompts/get` spoof test (claimed-but-absent)

- **Source Ticket:** MES-8
- **Type:** Gap
- **Description:** A `prompts/get` identity-spoof assertion was claimed but not present in committed
  source (a claim-vs-artefact instance — see the consolidation). The non-tool invariant surface was
  under-tested at MES-8.
- **Recommendation:** Add the assertion; the non-tool invariant test (AC3′) later landed as a
  first-class acceptance test in MES-10.
- **Priority Hint:** Medium
- **Blocking?:** No (fixed; superseded by MES-10 AC3′)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I3; `240550008` Note C (F4).

### Issue: F5 — URL-mode elicitation classification wrong at schema level

- **Source Ticket:** MES-8
- **Type:** Bug
- **Description:** D1 classified URL-mode elicitation as removed; the pinned draft schema
  (`7634684…`, `schema/draft/schema.ts`) retains `mode`/`url` request params and the `elicitation.url`
  capability. The removal narrows to exactly `elicitationId`, `notifications/elicitation/complete`, and
  the `-32042` helper. Survived two changelog-level reviews; failed at schema level → P4.
- **Recommendation:** Restore URL-mode; add the D1 v5 correction entry with schema provenance (done,
  Ruling 5). Schema-level verification joins the DoD for wire-shape items.
- **Priority Hint:** High (spec fidelity)
- **Blocking?:** No (fixed)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I3, §1 P4; `240550008` Ruling 5 (F5).

### Issue: Strict-condition merge-gate bounce = successful control activation

- **Source Ticket:** MES-8
- **Type:** Improvement
- **Description:** An unsanctioned `test_helper.exs` change failed a mechanically checkable merge-gate
  condition and **bounced without adjudication** — the pre-granted gate's strict conditions worked as
  designed. Resolved by revert + relocating the process note to the ledger ("the ledger note belongs in
  the ledger" — CC).
- **Recommendation:** Keep the pre-granted-gate-with-strict-mechanical-conditions pattern; a failed
  condition bounces automatically rather than forcing an unauthorised judgement call.
- **Priority Hint:** Low (positive control evidence)
- **Blocking?:** No
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I4, §2 (matured controls).

### Issue: Note C's first full outing made the re-review cheap

- **Source Ticket:** MES-8
- **Type:** Improvement
- **Description:** The MES-8 correction cycle was the first full application of Note C; re-executable
  evidence made the re-review cheap and caught the single residual. A positive instance of the
  claim-vs-artefact discipline (see consolidation).
- **Recommendation:** Keep Note C evidence tables in completion reports.
- **Priority Hint:** Low
- **Blocking?:** No
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I5.

---

## MES-9 — Stateless Streamable-HTTP transport

Done 2026-07-28 · merge `982f147` · tag `mes-9-stateless-transport` · review: **REJECT** (3 findings)
→ sanctioned corrections → MERGE-CLEAR. Ruling 6 (`242155522`).

### Issue: F1 — SEP-2243 `Mcp-Name` not validated against the method-appropriate target

- **Source Ticket:** MES-9
- **Type:** Bug
- **Description:** `Mcp-Name` was validated only against `params.name`; SEP-2243 maps it to the
  method-appropriate field — `params.name` for `tools/call`/`prompts/get`, `params.uri` for
  `resources/read`. `resources/read` mismatches sailed through. Caught by an executable repro
  (mismatch must return `-32020`).
- **Recommendation:** Validate the method-appropriate target; add the failing-then-passing repro (done).
- **Priority Hint:** High (routing correctness / gateway trust)
- **Blocking?:** No (fixed)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I6; `242155522` (F1).

### Issue: F2 / Ruling 6 — inherited format debt on untouched `mix.exs` lines

- **Source Ticket:** MES-9
- **Type:** Gap
- **Description:** `mix format --check-formatted` was red on `mix.exs:19/:45` — inherited baseline
  predating MES-8, invisible because `format --check-formatted` was not in the declared gate set. Not
  an MES-9 regression.
- **Recommendation:** Fix via one **sanctioned isolated** formatting-only commit touching `mix.exs`
  alone (done, `66fb0ba`); add `format --check-formatted` to the standard gate set for MES-9/MES-10 and
  all Sprint 4 tickets (done, Ruling 6).
- **Priority Hint:** Medium
- **Blocking?:** No (fixed; gate set extended)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I7; `242155522` Ruling 6.

### Issue: F3 — doc drift from MES-8's own correction cycle

- **Source Ticket:** MES-9
- **Type:** Bug
- **Description:** The `MCP.Server.Dispatch` moduledoc still described the legacy-arity fallback that
  MES-8's F3 correction had deleted — surviving two subsequent verification passes because they
  grepped code, not docs. → **P2a** (doc statements about removed behaviour are claims too).
- **Recommendation:** Rewrite the moduledoc to the enforced no-fallback contract with a provenance note
  (done); removal greps must include docs.
- **Priority Hint:** Medium
- **Blocking?:** No (fixed)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I8, §1 P2a.

### Issue: C2 — test-ledger completeness blind spot (un-tagged file)

- **Source Ticket:** MES-9
- **Type:** Gap
- **Description:** `streamable_http_ac_test.exs` was **un-tagged** and should have been ledgered in
  MES-8; tag-based ledger verification cannot see un-tagged files. The durable check is grepping for
  references to deleted symbols, not tags.
- **Recommendation:** Ledger by the D-C mechanism (grep for deleted-symbol references), not by tag; the
  file joined the ledger and its AC1–6/8 lines were closed by MES-10.
- **Priority Hint:** Medium
- **Blocking?:** No (fixed; ledger closed in MES-10)
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I9; MES-9 ratification `242155522` C1/C2.

---

## MES-10 — Identity seam v2 (acceptance + hardening)

Done 2026-07-31 · merge `2c9a71a` · tag `mes-10-identity-seam` (landing record: in-flight index
`238288897` v9) · review: **REJECT** (1 blocking — I10) → Ruling 7 correction → MERGE-CLEAR. Ruling 7
(`246906881`); Codex review `246120452`. Ledger closed to **zero excluded** (EMPTY).

### Issue: Ruling 7 / I10 — cross-request identity leak via notification residue (blocking)

- **Source Ticket:** MES-10 (defect introduced MES-9, latent on `main`)
- **Type:** Bug
- **Description:** `ToolContext.log/4` writes notifications to the **process dictionary** via the
  `reply_sink` collector; cleanup ran only on the normal `{:reply,…}` branch, with **no `try/after`**.
  A handler emitting an identity-bearing notification and then **raising** left residue that the next
  same-process request flushed into another principal's SSE response. Codex reproduced end-to-end.
  Provenance: introduced in MES-9 (`982f147`); **no released artefact affected** (1.1.0 predates the
  stateless transport). Bandit masked it (500 + `connection: close`), but the Plug is public and must
  not depend on adapter behaviour for an invariant.
- **Recommendation:** Clear the collector key at request **start** and in a `try/after` around
  dispatch (belt and braces); regression test over SSE shaping. Fixed forward at `8f35504`
  (isolated commit), collapsed into merge `2c9a71a`; MES-9 not reopened. **Sprint 4:** replace the
  process-dict collector with an explicit request-local collector threaded through the context —
  *cannot survive an exception by construction* (Ruling 7 item 6).
- **Priority Hint:** High (identity invariant)
- **Blocking?:** Yes at review time (blocking REJECT); resolved before merge
- **Suggested Jira Ticket?:** Sprint 4 hardening — request-local notification collector
- **Source:** `247431169` §3 I10; `246906881` Ruling 7; `246120452`.

### Issue: I13 — the security fix that would have silently done nothing

- **Source Ticket:** MES-10
- **Type:** Bug
- **Description:** In the Ruling 7 fix, `@notifications_key` was referenced **above its own
  definition**; an undefined module attribute reads as `nil`, so both clears would have operated on a
  `nil` key — the leak would have remained open while the code appeared to close it. Caught pre-ship by
  **two independent mechanisms**: the fail-then-pass regression (P7) and `--warnings-as-errors`.
  Self-caught and self-reported by CC.
- **Recommendation:** Keep P7 (a regression must be demonstrated failing at the pre-fix SHA — a fix
  that cannot be shown to fail before it lands may be a no-op) and `--warnings-as-errors` in the gate
  set; both earned their keep here.
- **Priority Hint:** High (near-miss on a security boundary)
- **Blocking?:** No (caught and fixed pre-ship)
- **Suggested Jira Ticket?:** WP global v3 codification (P7)
- **Source:** `247431169` §3 I13, §1 P7.

### Issue: The adversarial enumeration in a security-review brief is itself a control

- **Source Ticket:** MES-10
- **Type:** Improvement
- **Description:** The MES-10 review kickoff explicitly directed Codex beyond D2 §4.2's enumeration and
  named "the notification/reply_sink path" and "Process-dict residue" — **exactly where the blocking
  leak (I10) was found**. Both the reviewer's independence and the brief's specificity mattered.
  Codified as **P6**.
- **Recommendation:** For security-critical tickets, require the review kickoff to name candidate
  attack paths beyond the spec's enumeration; carry P6 into the WP v3 batch.
- **Priority Hint:** Medium
- **Blocking?:** No
- **Suggested Jira Ticket?:** WP global v3 codification (P6)
- **Source:** `247431169` §1 P6.

### Issue: A regression test must be demonstrated failing at the pre-fix SHA

- **Source Ticket:** MES-10 (also MES-9 F1 repro)
- **Type:** Improvement
- **Description:** A fix that cannot be shown to fail before it lands may be a silent no-op — and a
  silent no-op on a security boundary manufactures false assurance. Demonstrated twice: MES-9 F1 repro,
  and MES-10 I13 (a genuine silent no-op caught exactly this way). Already required by Ruling 7 item 4.
  Codified as **P7**.
- **Recommendation:** Require fail-then-pass regression evidence for fixes to invariant/security code;
  carry P7 into the WP v3 batch.
- **Priority Hint:** Medium
- **Blocking?:** No
- **Suggested Jira Ticket?:** WP global v3 codification (P7)
- **Source:** `247431169` §1 P7, §2 (matured controls).

### Issue: I12 — Confluence page-creation tooling failures

- **Source Ticket:** MES-10
- **Type:** Bug
- **Description:** Confluence page creation failed (idle-timeout / "No approval received") during the
  MES-10 cycle and succeeded on retry; Jira writes were unaffected. An infrastructure/tooling flake,
  not a product defect. (Recovery discipline used: check for an orphan page before re-creating, to
  avoid duplicates.)
- **Recommendation:** On a create timeout, verify server-side landing (list descendants) before
  retrying; no product action.
- **Priority Hint:** Low
- **Blocking?:** No
- **Suggested Jira Ticket?:** No
- **Source:** `247431169` §3 I12.

---

## MES-11 — Duplicate epic (Won't Do)

### Issue: MES-11 duplicate epic closed Won't Do

- **Source Ticket:** MES-11
- **Type:** Gap
- **Description:** MES-11 was a duplicate epic half-created by an interrupted conversation; closed
  **Won't Do** by the PO on 2026-07-24. **MES-12 is the epic of record** for Sprint 3/4.
- **Recommendation:** None — closed. Retained here so every Sprint 3 ticket key has a section (rule #7).
- **Priority Hint:** Low
- **Blocking?:** No
- **Suggested Jira Ticket?:** No — MES-12 is the epic of record
- **Source:** `247431169` §3 I1.

---

## Carried forward to Sprint 4 (from `247431169` §5)

- **Config-time cache-scope warning** (MES-10 C1) — warn once at config time, never per request.
- **Replace the process-dictionary notification collector** with an explicit request-local collector
  (Ruling 7 item 6); I13 strengthens this — the approach proved fragile at the attribute level too.
- **Client header-provider** for rotating bearer credentials → Sprint 4 client-acceptance ticket.
- **Final-schema re-pin** → Sprint 4 conformance ticket. Draft pin `7634684…` stands.
- **Codification batch P1–P8** → file against Working Procedure global v3 via the Proposal protocol.
- **2.0.0 release** (PO-gated `hex.publish`; artefacts verified from the **packaged** contents).
