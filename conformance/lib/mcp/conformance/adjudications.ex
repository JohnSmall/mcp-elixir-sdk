defmodule MCP.Conformance.Adjudications do
  @moduledoc """
  **Guard 32**: every edge a bucket view projects is **adjudicated exactly
  once**, by a hand-authored adjudication record whose rows **equal** the view
  in both directions. Each row's disposition comes from a closed set, and each
  repository citation it makes still has the bytes it quotes at the address it
  gives.

  Established by MES-126 (D4a) for the D group. MES-127, 128, 129 and 130 reuse
  it. A new disposition is a reviewed change to this file: MES-127 (D4b) added
  `extend_test` and `accept_bound`, and the `bound_missing` refusal with them
  (PM ratification, MES-127 comment 29430, Q1 and Q2). MES-128 (D2b) added
  `extend_to_match` and `build_test`, and the `build_level_missing` refusal with
  them (PM ratification, MES-128 comment 29444, Q1). MES-129 (D2a-i) added
  `blocked_on_sdk_gap`, and the `sdk_gap_missing` refusal with it (PM
  ratification, MES-129 comment 29460, Q1). MES-138 (D1-nd+CU) added the D1
  family, `genuine_extra_coverage`, `redundant`, `not_a_conformance_claim` and
  `wrong_against_spec`, with the `protects_missing`, `counterpart_missing`,
  `routed_to_missing`, `spec_citation_missing` and `disposition_outside_view`
  refusals [authored 29691 | ratified 29693] (Q1 to Q3). MES-139
  (D1-client-i) added the `counterfactual_missing` refusal [authored 29729 |
  ratified 29731] (Q1). MES-145 (D5b-i) added the D5 family,
  `discriminating`, `vacuous_oc`, `vacuous_et`, `vacuous_both` and
  `not_established`, with the `oc_null_missing`, `oc_null_drift`,
  `null_outcome_not_entailed`, `discount_outside_set`, `discount_drift`,
  `et_null_missing`, `disposition_underivable` and
  `not_established_because_missing` refusals, and widened
  `disposition_outside_view` to it [authored 30074-30076 | ratified 30077]
  (Q1 to Q6).

  ## The dispositions

    * `fix_sdk`, `fix_conformance_adapter`, `keep_design_publish_bound`,
      `po_decision_required`, `suite_defect_upstream`: MES-126.
    * `extend_test`: the unit already drives the seam at which the omitted axis
      can be observed. The remedy is an added assertion on that axis in the same
      unit, not a new test. It is recorded by D and performed by remediation
      (ruling 3). Where the SDK currently fails the axis, the assertion lands in
      the same change as the named root cause's fix, so `main` never carries a
      red test.
    * `accept_bound`: the unit's seam cannot observe the omitted axis, so the
      edge's coverage is bounded to the axes the unit asserts. The row states
      that bound in `bound`, as one consumer-readable sentence: a non-empty
      string on a single line, or the row is refused (`bound_missing`). The
      guard holds the shape. Whether the sentence is honest is the reviewer's
      check.
    * `extend_to_match`: for a check with NO edge (bucket 2). An existing ET-CC
      unit already drives the seam and sends the check's stimulus, but asserts
      nothing the check requires. The remedy is an added assertion, or added
      loop cases, in that unit, which would give the crosswalk an edge. The row
      cites the unit in `extend_target`. It differs from `extend_test`, which
      presumes an existing edge with an omitted axis.
    * `build_test`: for a check with no edge that no existing unit drives at any
      level. The remedy is a new ET-CC unit.
    * `blocked_on_sdk_gap`: the check's behaviour is not implemented by the SDK,
      or it passes only through a path an SDK gap creates. So no ET-CC unit can
      honestly be built or extended until a named SDK change lands. The row's
      `build_level` and `remedy` name the unit to build once the gap is fixed,
      and that unit lands in the same change as the fix, so `main` never
      carries a red test (the `extend_test` precedent). The row also carries
      `sdk_gap`: the owning ticket (`owner`), one line naming the record that
      ticket carries (`owner_record`), and a repository citation of the gap in
      this tree (`record`). Otherwise the row is refused (`sdk_gap_missing`).
      Shape only: whether the owning ticket really carries the record is the
      reviewer's check.

  **The D1 family** [authored 29691 | ratified 29693]. For a member, or a
  claim, with NO OC counterpart (bucket 1 and the claim-unmatched view). Each
  row gets exactly one of these. The view row's `why_no_counterpart` and
  `the_search_that_found_none` are inputs to the verdict, not the verdict.
  Each refusal checks SHAPE only, as `bound_missing` does: whether the verdict
  is right is the reviewer's check.

    * `genuine_extra_coverage`: the unit asserts something no OC check
      requires, and it is worth holding. The row states what the unit protects
      that OC cannot, as one non-empty line in `protects`. Otherwise the row is
      refused (`protects_missing`).
    * `redundant`: an OC check covers the same ground, and the match rule (A3,
      `docs/conformance/match-relation.md`) did not see it. That is a finding
      against the crosswalk, and it is routed, not fixed. The row carries
      `oc_counterpart`: a `token` of the OC locator; a `site`, a harness
      citation whose `byte_span` overlaps a site the locator records for that
      token; and `why_a3_missed`, one line. Otherwise the row is refused
      (`counterpart_missing`). The tie shows that the token HAS that site, not
      that the counterpart is right (K1-R's lesson; 29693, Q2). The site sits
      under `oc_counterpart`, not under `check`, so `check_foreign`'s `oc:none/`
      premise (no harness span under `check`) still holds.
    * `not_a_conformance_claim`: the member is misclassified under A2. The
      register is not relabelled here; the reading is routed back to A2. This
      includes a unit that asserts one conforming choice among several, so a
      conforming SDK could choose otherwise and fail it: the behaviour has no
      normative anchor, an A2 gate-3 failure [authored 29707 N5 | ratified
      29708].
    * `wrong_against_spec`: the unit asserts something the specification
      forbids, or contradicts [amended from "does not require, or forbids":
      authored 29707 N5 | ratified 29708]. The row carries `spec`: an https
      `url` into the 2026-07-28 revision and a one-line verbatim `quote`.
      Otherwise the row is refused (`spec_citation_missing`). The
      specification is not in this repository, so gate 5 cannot hold the
      quote's bytes: the same split as harness citations, and a stated
      residual.

  One counterfactual separates these last two from `genuine_extra_coverage`,
  applied to every row: could a conforming SDK fail this unit? If one can,
  and the specification forbids nothing the unit asserts, the row is
  `not_a_conformance_claim`; if none can, a genuine row names the spec text
  that makes it so [authored 29707 N5 | ratified 29708]. The unit is the
  view's: on bucket 1 the member, on the claim-unmatched view the claim
  alone, so a member's other asserts are not part of it [authored 29721 B-A |
  ratified 29723].

  Every D1 row records that reading as `counterfactual`: a boolean
  `conforming_sdk_can_fail` and a one-line `reading`. A reading that fires
  names the test line a conforming SDK would fail, as `<name>_test.exs:N`;
  a reading that does not opens `None can: ` and cites the specification
  text that requires the asserted meaning (a `.mdx` or `.ts` file, or a §).
  Otherwise the row is refused (`counterfactual_missing`) [authored 29729 |
  ratified 29731]. Like the others, this refusal checks SHAPE only: which way
  a reading goes, and whether its citation says what it is cited for, is the
  reviewer's check.

  A `redundant` or `not_a_conformance_claim` row carries `routed_to`, in the
  `sdk_gap` shape: `to`, which must be the disposition's route (`A3` for
  `redundant`, `A2` for `not_a_conformance_claim`), a ticket-key `owner`, and
  a one-line `owner_record` naming the record that ticket carries. Otherwise
  the row is refused (`routed_to_missing`).

  The D1 family is admitted ONLY in a section bound to a D1 view (bucket 1 or
  the claim-unmatched view), and a D1 view admits nothing else. Either way the
  row is refused (`disposition_outside_view`), so a bucket-1 row carrying
  `fix_sdk` cannot audit clean (29693, Q3).

  **The D5 family** [authored 30074-30076 | ratified 30077]. For an edge
  green in BOTH suites (bucket 5a, server; 5b, client). Agreement is not the
  finding; the question is which of these greens would go red if the
  behaviour broke. So each row answers it on both sides, and the guard holds
  the OC side by RECOMPUTING it:

    * `oc_null`: one entry per committed null census of the row's leg
      (`@d5_legs`; exactly those, or `oc_null_missing`), each `census`,
      `scenario`, the census's `checks` and `failed_checks` for the scenario
      verbatim (else `oc_null_drift`), and the `raw_status` and `outcome` the
      counts ENTAIL (`null_outcome/3`; else `null_outcome_not_entailed`). A
      check absent from `failed_checks` has not thereby passed: a pass is
      claimed only where SUCCESS equals the number of the scenario's bucket-0
      names no failed entry matches, with nothing skipped and the total
      accounted for; a skip likewise; `not_emitted` where every emitted check
      failed; anything else is `undetermined`, never a pass. The outcome is
      reduced under the leg's own reducer, so on the client leg a WARNING is
      red; `raw_status` keeps what the census said.
    * `discounts`: an ATTRIBUTE, not a disposition. A list of `{type, grain,
      sources}`, one per type (`null`, `drive_policy`) and grain (`check`,
      `scenario`), never merged (MES-19); a malformed list is
      `discount_outside_set`. The guard recomputes the owed set
      (`owed_discounts/2`) and requires equality both ways (`discount_drift`):
      an owed discount missing, and a stated one that does not hold.
    * `et_null`: the ET side, the question mirrored back. Either
      `{measured: true, mutations}`, each mutation an `id`, a `kind`
      (`violation` or `null`), byte-exact `edits` (`{file, old, new}`), a
      `result` (`red` or `green`) and, when red, the `firing` line as
      `<name>_test.exs:N`, in the member's own test file and inside the
      member's own test; or `{measured: false, reading, why_not_measured,
      vacuous}`. Otherwise `et_null_missing`.

  The disposition is a FUNCTION of that evidence (`derive_disposition/3`;
  else `disposition_underivable`). OC is vacuous when some recomputed null
  outcome is `pass` or `skipped` (a null that is skipped loses nothing, Q2).
  ET is vacuous when a measured mutation stays green, or an unmeasured
  reading says so. OC vacuous: `vacuous_both` or `vacuous_oc`, by ET. OC able
  to go red: `vacuous_et` or `discriminating` by a MEASURED ET, and
  `not_established` on a reading alone. An `undetermined` outcome with no
  vacuous one leaves OC unknown, and the row `not_established`. A
  `not_established` row says why, in one line, `not_established_because`
  (else `not_established_because_missing`), so the honest disposition is
  never free.

  What the D5 checks do NOT establish: that a mutation is the strongest
  violating or do-nothing alternative (MES-143's lesson; the reviewer's, Q5);
  the premise the pass entailment rests on, which is NOT that bucket-0's
  vocabulary for a scenario is complete (the committed censuses emit names
  outside it, all of them FAILUREs) but that each N_S name is emitted at most
  once and every emission outside N_S appears in `failed_checks`. Counts alone
  cannot tell "target SUCCESS" from "target absent + one non-N_S SUCCESS", so
  on input breaking the premise `null_outcome/3` would promote an absence to a
  pass. `null_premise_defects/1` checks the premise's count-visible
  consequences over the committed censuses in gate 5: they hold on every
  client null, and break on the server null at `server-stateless`, where
  several N_S checks share a name (no row of D5b-i is on that leg); the
  invisible case (a
  non-N_S SUCCESS standing in for an absent N_S name) it cannot see, and the
  harness, which alone could, is not in this repository. A null-passable check is a defect in the INSTRUMENT, not in
  this SDK, and moves no figure of ours.

  The D5 family is admitted ONLY in a section bound to a D5 view, and a D5
  view admits nothing else (`disposition_outside_view`, as for D1).

  An `extend_to_match`, `build_test` or `blocked_on_sdk_gap` row carries `build_level` (one of
  `pure_unit`, `mock_transport`, `plug`, `live_http`) and a one-line `remedy`,
  and an `extend_to_match` row also carries an `extend_target` map. Otherwise
  the row is refused (`build_level_missing`). Like `bound_missing`, this checks
  SHAPE only: whether the level is the cheapest one that works, and whether the
  remedy would really give the check an edge, is the reviewer's check. The
  `extend_target` citation's bytes are held by `citation_drift` like any other.

  ## The record, and the unit it adjudicates

  A record is `docs/conformance/adjudications/*.json`, **one file per
  ticket**, and it carries `schema: "adjudication-record/1"` and
  `authored_by_hand: true`. It holds **sections**. A section is bound to ONE
  view by the view's repository path, and a view may have several sections bound
  to it, even from different tickets. That is what lets bucket 2a be split
  between MES-129 and MES-130, and lets D4a adjudicate the escalated view in the
  same record as bucket 4a (PM ratification, MES-126 comment 29406 (i)).

  A section's `closure` is `closed` or `open`. Per view, the guard takes the
  union of the rows of every section bound to it:

    * **phantom**: a row whose key the view does not project. Refused always.
    * **missing**: a view key that no row adjudicates. Refused when ANY section
      bound to the view is `closed`. When every bound section is `open`, a
      missing key is allowed, which is the state of a split view before its
      closing ticket lands. An `open` section must name an `owner`.
    * **duplicate**: one key adjudicated twice, including across records. It is
      reported against EVERY file holding the key.
    * **closure_not_exclusive**: more than one `closed` section bound to one
      view. A view is closed by ONE section; any other section binding it is
      `open`. Two closed sections over disjoint halves of a view pass
      `duplicate` (the halves are disjoint) and `missing` (the union is
      complete), so neither entails this (MES-135 K3).

  A `missing` edge is reported against the closing section's file, the section
  that owes it. Until MES-135 (F7) every set defect was reported against the
  view's FIRST section, so a row dropped from D2a-ii was named against D2a-i.

  ## The universe: which views are owed a record (MES-135 K2)

  The views owed a record are declared from an anchor that is NOT the records:
  the listing of `docs/conformance/buckets/*.json`, read by `anchor/1`. Every
  view there is owed a closing section except those `@not_owed` names, each with
  its reason (bucket-0, whose rows the triple cannot key, and the roll-up, which
  projects no rows). A universe derived from the records would be vacuous, since
  a record left out would take its view out with it.

  An owed view is either CLOSED (a closed section binds it) or PENDING: named in
  `@pending` with the ticket that closes it. Pending is reported, never refused
  and never silent. The closing ticket deletes its `@pending` line in the change
  that closes the view (PM ratification, MES-135 29663, Q2). Both catalogues
  live here, in the guard, and are pinned in gate 5.

    * **owed_unadjudicated**: an owed view that no closed section binds and that
      is not pending. Reported against the view. A dropped section (CR's W2 on
      MES-126) is refused here, and so is a narrowed walk that sees no records.
    * **pending_but_closed**: a pending view that a closed section closes; the
      catalogue is stale.
    * **catalogue_names_absent_view**: an `@not_owed` entry the listing lacks,
      or an `@pending` entry that is not owed.
    * **bound_to_excluded**: a section binding a view `@not_owed` names.
    * **bound_outside_anchor**: a section binding a view outside the listing.
    * **owner_mismatch**: an open section whose `owner` is not the ticket that
      closes its view (the `@pending` ticket while pending, the closing
      record's `ticket` once closed).
    * **empty_closure_unwarranted**: a closed section with no rows over a view
      that projects none, where the view does not state `count: 0` and an
      `emptiness_reason`. (Over a view that projects rows, `missing` fires.)
    * **emptiness_unechoed**: a closed section with no rows over a view that
      projects none, carrying no `emptiness` echo (below).
    * **emptiness_drift**: a section's `emptiness` echo is not the view's
      current `count`, `emptiness_reason` and `universe`, or it sits on a
      section that claims no zero (an open one, or one with rows).
    * **record_outside_walk**: a `*.json` that git would commit (tracked, or
      untracked and not ignored: `@scan_population`, run at the repository
      root) whose `schema` is the record schema, outside the walk root. A
      git-ignored file (`./tmp`, `doc/`, `cover/`) is not committed unless it
      is force-added (`git add -f`), so while it is only ignored it is not
      scanned (MES-135 B1). Once force-added it is tracked, so it IS scanned,
      and refused (CR 29679, probe iv).
      Fail-closed: when git cannot be run, or the root is not the top level of
      a git work tree, the scan is refused under this kind, never skipped.
    * **stray_in_walk_root**: an entry of the walk root that is not a regular
      `*.json` file (a subdirectory, a `.jsn`), which the walk would not read.

  `audit/2` takes the catalogues as `policy`, defaulting to the pinned ones, so
  a control can plant a stale catalogue without editing this file.

  ## An empty view, closed: the zero is echoed (MES-144)

  A closed section with `rows: []` claims the view projects nothing. Before
  MES-144 that claim was only implied, and `empty_closure_unwarranted` held
  the view's `emptiness_reason` for being non-empty, not for what it says: a
  view re-projected at zero rows over a different universe, or with a
  different measured premise, left the closure standing unseen. So such a
  section carries `emptiness`, a verbatim copy of the view's `count`,
  `emptiness_reason` and `universe` (`emptiness/1`), and the guard requires
  the copy to EQUAL the view [authored 30052 | ratified 30055, Q1].
  `projected_from` is not echoed (Q2): a crosswalk regenerated for an
  unrelated reason would otherwise force a re-echo, and a row the view gains
  is `missing`'s.

  A re-projection with a row fires `missing` AND `emptiness_drift` (the count
  moved). A premise that moves at zero rows fires `emptiness_drift` alone. A
  view that contradicts itself (`rows: []`, `count: 3`), echoed faithfully,
  passes the echo and is `empty_closure_unwarranted`'s. Neither kind entails
  the other; the controls show each on its own plant. What the echo does NOT
  establish: that the view's premise is TRUE. The view states it; the record
  that closes the view measures it.

  ## The key: the edge triple, derived by ONE function from both sides

  `key/1` is `[member, claim, tag]`. `member` is the member's `register_key`
  (a view row carries the member as a map, and a record row carries the string),
  and a component the row does not carry is `nil`. The same function is applied
  to the view's rows and to the record's rows, so the two sides cannot key
  differently. No shorter key works on the views the D group adjudicates,
  measured at `b1cd59e`. The member alone collides in `bucket-4b` (two members
  carry two rows each, differing by tag). `[member, tag]` still collides in
  `bucket-5a` and `bucket-5b`, where one member carries several rows on one
  check that differ only by claim. The mutation mode of
  `conformance/controls/adjudications_controls.exs` recompiles this guard with
  each shorter key and shows those real views refused. A view whose rows do not
  key uniquely under the triple is refused (`view_key_collision`) rather than
  adjudicated approximately. `bucket-0` is such a view at `b1cd59e`: its rows
  carry `token`, not `tag`, so they key alike.

  (MES-126's plan said the two T-CG1c rows of the escalated view share a
  `register_key`. They do not: each is its own test. The control plant that
  assumed they did found this out.)

  ## Echo: a regenerated view under an unchanged key is caught

  Each row copies its view row's `shape`, `verdicts`, `bucket`,
  `escalation_reason`, `escalation_cause`, `cg`, `search_id` and
  `the_search_that_found_none` (whichever the view row carries) into `echo`. The guard requires `echo` to EQUAL that projection. So a view
  re-projected with a different verdict under the same edge refuses
  (`echo_drift`), rather than leaving an adjudication standing over a fact
  that has changed.

  **Echo is vacuous on bucket-2 views.** A bucket-2 view row carries only
  `leg` and `tag`, both inside the key, so its echo is `{}` and `echo_drift`
  cannot fire there (CR K4 on MES-126): there is nothing a view row could
  change under an unchanged key. A bucket-1 view row carries `cg`, which
  MES-135 added to the echoed fields, so its echo is no longer vacuous.
  MES-138 added `search_id` and `the_search_that_found_none` (29693, Q4): the
  search a D1 verdict re-tests, so a search regenerated under an unchanged key
  refuses. They also make echo non-vacuous on claim-unmatched rows, which
  carry none of the other fields.

  ## Content ties (MES-135 K1)

  The key and the echo bind a row to its edge. They say nothing of the row's
  CONTENT: CR's W1 on MES-126 gave edge A's key and echo edge B's `et_test`,
  `check`, root cause and disposition, and it passed. Three ties now check the
  content, each against an anchor outside the record. They do NOT separate
  every pair of rows: the pairs whose content can be exchanged unseen are
  stated by predicate, and audited, under "What the ties do NOT hold" below.

    * **et_test_foreign**: a row with a `member` carries `et_test` as a
      repository citation whose window lies inside the member's OWN test, in a
      file defining the member's module (`et_test_owner/2`, moved here from the
      gate-5 check MES-127 added). A row with no member carries
      `et_test: null`.
    * **check_foreign**: a row whose tag is an OC token carries, somewhere
      under `check`, a harness citation whose `byte_span` overlaps a site that
      the OC locator (`docs/conformance/oc-emitting-sites-2026-07-28.json`) records for that token. A token is
      `oc:<leg>/<scenario>/<check id>/<name>`, plus `#<discriminator>` when the
      locator row has one. A row on no OC check (`oc:none/`, bucket-1 and
      claim-unmatched) cites no harness span under `check`, and that absence is
      its premise: there is no check to tie to.
    * **root_cause_foreign**: a root cause whose `id` is `R<n>` carries
      `stated_at`, a repository citation whose bytes contain `**R<n>**`: the
      report row stating it. A root cause that is not an `R<n>` (a suite slug,
      or a bucket-2 statement with no id) has no such anchor, and is not tied.

  Per shape, which ties apply. Member-keyed bucket-1 rows carry the `et_test`
  tie and the `oc:none/` form of the `check` tie. Edge-keyed bucket-5 rows
  carry all three. **Bucket-2 rows carry the `check` tie ALONE**: they have no
  member, so `et_test` is `null`; their echo is `{}` (above); and their root
  causes are not `R<n>`. Bucket-2 is the dominant shape: 93 of the 108
  committed rows at MES-135, and 93 of 138 at MES-138 (which adds 30
  `oc:none/` member rows, 21 bucket-1 and 9 claim-unmatched). An empty
  view has no rows, so the ties are vacuous there, and that is stated rather
  than claimed as coverage. Which ties apply
  to a row does not say which pairs of rows they separate; the next paragraph
  does.

  What the ties do NOT hold:

    * **Which of two rows' content is whose, for the pairs this predicate
      admits (MES-135 K1-R and K1-R2; CR 29672, 29680; amended at MES-138,
      R3-1).** Two rows' contents (every field but `member`, `claim`, `tag`
      and `echo`) can be exchanged and still audit CLEAN if and only if ALL THREE:
      (a) the `check` tie does not separate them: their ties are MUTUAL (each
      row's harness span overlaps a locator site of the OTHER row's token,
      which happens where the two tokens share a site), OR both rows are
      `oc:none/` (no span on either side, so nothing to tie); and (b) the
      `et_test` tie does not separate them: both rows are member-less, or
      each row's window is owned by the OTHER row's member (the tie asks only
      that the window lie in the row's own member's test, so the same member
      test, or two doctests of one `doctest` directive, which share its one
      line); and (c), since MES-145, the D5 recomputation does not separate
      them: neither row is on a D5 view, or both are and each row's tag
      entails the other's `oc_null` and `discounts` and derives the other's
      disposition from its `et_null`.
      `root_cause_foreign` separates no pair, because `stated_at` travels with
      the root cause. `check_foreign` accepts a span overlapping ANY locator
      site of the token, and sites are shared: measured at MES-135, 11 of the
      locator's 143 distinct sites are sites of more than one token, 82 of its
      173 tokens have ONLY shared sites, and 60 of the 108 committed rows tie
      their check only through a shared site (48 bucket-2, 12 member rows);
      still 60 of 138 at MES-138, and of 173 at MES-139, since an `oc:none/`
      row cites no site; 74 of 343 at MES-145 (48 bucket-2, 26 member rows),
      D5b-i's 14 being its 10 http-standard-headers, 2
      http-invalid-tool-headers and 2 `WireSchemaValid` rows.
      **The audited set.** At MES-135, CR exchanged every pair of the 108
      committed rows (5778 pairs) and ran each through `audit/2`: 481 pairs
      audited CLEAN, 477 bucket-2 and 4 member; of 551 pairs whose `check`
      ties were mutual, the `et_test` tie refused 70. **At MES-138 the
      controls' `swap-audit` mode exchanges every pair of the 138 committed
      rows (9453 pairs, 0 no-ops): 482 pairs audit CLEAN, 477 between
      bucket-2 rows and 5 between member rows.** Of the 986 pairs whose
      `check` tie does not separate them (551 mutual, plus 435 between the 30
      `oc:none/` rows), the `et_test` tie refuses 504. The 30 D1 rows add
      exactly ONE CLEAN pair: `ExtensionsTest`'s doctests `from_meta/1 (8)`
      and `(9)` in the bucket-1 section, both `genuine_extra_coverage`, which
      share the `doctest MCP.Protocol.Extensions` line as their one-line
      window (MES-138 S2a, [authored 29695 | ratified 29702]). **At MES-139
      the `swap-audit touching` mode exchanges every pair with a row in its
      record (5425 pairs of the 173 rows, 0 no-ops): none audits CLEAN, so
      the set stays 482.** Of the 2631 pairs the `check` tie now leaves
      unseparated (551 mutual, plus 2080 between the 65 `oc:none/` rows),
      the `et_test` tie refuses 2149. The 4 older member pairs are over 5 rows (1 in
      D4a, 4 in D4b) and 2 member tests. On `StreamableHTTPStatelessTest`
      "initialize is gone → -32022; ping/logging.setLevel → -32601": D4a's
      `initialize` row (`fix_sdk`) with D4b's `ping` row and with D4b's `logging-setlevel` row (both
      `extend_test`), which cross records and exchange disposition, check and
      root cause; and those two D4b rows with each other. On `DispatchTest`
      "ping and logging/setLevel are removed → method not found (-32601)":
      D4b's `ping` and `logging-setlevel` rows (both `accept_bound`). The 482
      pairs form 9 cliques, of 30, 9, 3, 3, 2, 2, 2, 2 and 2 rows; the 30 span
      D2a-i and D2a-ii (8 cliques and 481 pairs at MES-135). Gate 5 computes
      the set by (a), (b) and (c) over every committed row and asserts it EQUALS
      the audited set pair for pair, and pins two pairs CLEAN as known residuals: CR's bucket-2 plant (D2a-ii's
      `caching` and `tools-call-with-progress` `WireSchemaValid` rows, which
      differ on `check`, `disposition`, `extend_target`, `remedy`,
      `root_cause` and three more fields) and the cross-record member pair
      (D4a's `initialize`, D4b's `ping`). So a row, a tie, or this paragraph
      moving the set shows up red there. **At MES-145 the `swap-audit
      touching` mode exchanges every pair with a D5b-i row (10137 pairs of the
      343 rows, 0 no-ops): 7 audit CLEAN (537 -> 544), three cliques of 3, 3
      and 2 rows, each on one member test and one shared
      http-standard-headers site, whose recomputed D5 evidence is identical.**
      Of the 184 pairs it adds that the `check` tie leaves unseparated, the
      `et_test` tie refuses 176 and (c) alone refuses 1 (W6's two rows,
      whose null outcomes differ). For a token whose sites are all
      shared, the `check` tie cannot be narrowed: any site the row cites is a
      site of another token too.
    * That a slug root cause names the right cause.
    * That a harness citation's bytes are right (gate 5 cannot read the build;
      the control's `harness` mode checks both sha and bytes).

  ## Citations: an address AND the bytes at it (ruling 7)

  Anywhere in a record (in a row, a section, or at the top level: MES-135
  extended the walk from rows to the whole record), a map carrying `file`, `lines` (`[from, to]`, 1-based,
  inclusive) and `bytes` is a **repository citation**. The guard reads that
  line window at the tip and requires it to EQUAL `bytes` once whitespace runs
  are squashed. The test is equality, not containment, so a quote cannot hide a
  stale window or a spliced one. A map carrying `harness_sha256`, `byte_span`
  and `bytes` is a **harness citation**. The harness build is not in this
  repository, so gate 5 cannot read it. Those citations are counted in the
  report and verified by the control's `harness` mode against the pinned build.
  That split is a stated residual, not a pass.

  A repository citation can be right on its BYTES and wrong on its UNIT when
  those bytes recur in the file (MES-128: `capabilities_test.exs:8` and `:64`
  both read `test "from_map/1 parses full capabilities" do`). So when the
  squashed bytes EQUAL some other window of the same length in the same file,
  the citation must carry `occurrence: n`, and n must be the cited window's
  1-based index among the equal windows. A citation that carries `occurrence`
  is held to it even where the bytes are unique (n = 1). Otherwise it is
  refused as `citation_ambiguous` (MES-135, 29451).

  ## A citation of behaviour a later commit removed is anchored (MES-161)

  **The rule: a citation of behaviour that a later commit removed is anchored
  at the last commit that had it** [PM ruling, MES-161 30337 Q9]. Such a
  citation carries `at`, a full commit id, and is read from git objects at
  that commit, not from the tip. Its line window and bytes stay exactly as
  measured. Re-citing it at the tip with new bytes would make the record claim
  the removed behaviour still exists. The first use is MES-161: the server
  began rejecting a request missing a required `_meta` field, the tests that
  sent such requests were fixed, and 127 D-record citations of the old
  requests are anchored at `bd99a39`, the last `main` commit before the fix.

  A citation written in prose (`x_test.exs:N` inside a `rationale`) has no
  map to carry `at`. So the map holding the prose carries `prose_anchors`: one
  `{field, cite, file, lines, bytes, at}` per such citation, where `field` is
  the dotted path of the prose on that map and `cite` is the citation as the
  prose writes it. The entry is a repository citation like any other, so its
  bytes are held at `at` (`citation_drift`).

  The `et_test` tie and the D1 assert readings read an anchored `et_test` at
  its `at` too (`cited_source/2`), so a row whose member test was changed by
  the fix is ONE measurement at `at`: its other citations of that file keep
  their line numbers at `at`.

    * **anchor_invalid**: `at` is not a 40-hex commit id, names no commit, is
      not an ancestor of HEAD, or the file is absent at it. A branch-only sha
      does not survive a squash-merge, so it is refused here, before it can.
    * **anchor_unwarranted**: the cited bytes still occur in the file at the
      tip, at the same lines or moved. `at` is only for text that is gone, so
      it cannot hide ordinary drift.
    * **prose_anchor_foreign**: a prose anchor without `at`, or whose `cite`
      does not occur in the `field` it names.

  The report counts anchored citations (`repo_citations_anchored`, with
  `anchored_at`), and the task prints them apart from the tip's, so a
  historical citation is visible rather than silent.

  **What anchoring does NOT hold.** That the anchored text was removed ON
  PURPOSE: `anchor_unwarranted` checks that the text is gone, not why. That
  `at` is the LAST commit that had the text: any older ancestor still holding
  the bytes passes, so the rule's "the last commit that had it" is the
  author's word, not a check. Prose citations that nobody anchored are prose,
  held by no guard, as before.

  ## What is refused

  `unreadable`, `bad_record`, `bad_section`, `unknown_view`,
  `view_key_collision`, `open_without_owner`, `bad_row`,
  `disposition_outside_set`, `bound_missing`, `build_level_missing`, `sdk_gap_missing`,
  `disposition_outside_view`, `protects_missing`, `counterpart_missing`,
  `routed_to_missing`, `spec_citation_missing`, `counterfactual_missing`,
  `oc_null_missing`, `oc_null_drift`, `null_outcome_not_entailed`,
  `discount_outside_set`, `discount_drift`, `et_null_missing`,
  `disposition_underivable`, `not_established_because_missing`,
  `phantom`, `missing`,
  `duplicate`, `closure_not_exclusive`, `owed_unadjudicated`, `pending_but_closed`,
  `catalogue_names_absent_view`, `bound_to_excluded`, `bound_outside_anchor`,
  `owner_mismatch`, `empty_closure_unwarranted`, `emptiness_unechoed`,
  `emptiness_drift`, `record_outside_walk`,
  `stray_in_walk_root`, `et_test_foreign`, `check_foreign`, `root_cause_foreign`,
  `citation_ambiguous`, `echo_drift`, `citation_drift`, `anchor_invalid`,
  `anchor_unwarranted`, `prose_anchor_foreign`, and `reach`. Every refusal names the guard, the kind, the
  record file and the edge key.

  ## Reach, and what the guard reports over an empty directory

  The report states `records_visited`, `rows_visited`, `views_bound`, the
  universe (`owed`, `closed`, `pending`), and two citation counts:
  `repo_citations_found`, every repository citation the walk found, and
  `repo_citations_holding`, those whose bytes held. Neither count claims that
  anything was verified: a refused run verifies nothing, so the task prints a
  VERIFIED count only when the audit is clean (MES-135 K5; before it,
  `citations_verified` counted citations found, and a refusing run still
  printed "N repository citations verified").

  Over an EMPTY adjudications directory no view is closed, so every owed view
  that is not pending is refused (`owed_unadjudicated`). Before MES-135 that
  state audited clean, and only the gate-5 pin on the walk root caught a
  narrowed walk; the pin remains, as a backstop. Once any record is visited, a
  run that visited zero rows is refused (`reach`).

  ## What it does NOT establish

    * That a disposition is RIGHT. The guard holds the record's shape against
      the view. The judgement is the author's, and the reviewer's to check.
    * That `@pending` names the RIGHT ticket, or that `@not_owed`'s reasons are
      true. Both are reviewed changes to this file, pinned in gate 5.
    * That a record with a schema OTHER than `adjudication-record/1` outside
      the walk root is a record. The scan keys on the schema.
    * Harness bytes in gate 5 (see above).
  """

  @guard "G32"
  @source "conformance/lib/mcp/conformance/adjudications.ex"
  @walk_root "docs/conformance/adjudications"
  @walk_glob "*.json"
  @schema "adjudication-record/1"
  @view_schemas ~w(bucket-view/1 escalated-view/1 claim-unmatched-view/1)
  @closures ~w(closed open)

  # The dispositions are a CLOSED set here, in the guard, not in the data
  # (G31's @reasons precedent, PM ratification on MES-126 (ii)). Adding one is a
  # reviewed change to conformance/lib, proposed at the adding ticket's plan hop.
  @dispositions ~w(fix_sdk fix_conformance_adapter keep_design_publish_bound
                   po_decision_required suite_defect_upstream extend_test accept_bound
                   extend_to_match build_test blocked_on_sdk_gap
                   genuine_extra_coverage redundant not_a_conformance_claim wrong_against_spec
                   discriminating vacuous_oc vacuous_et vacuous_both not_established)

  # The D1 family (MES-138; authored 29691, ratified 29693): admitted ONLY in a
  # section bound to a D1 view, and a D1 view admits nothing else
  # (disposition_outside_view, both ways). A routed row's `routed_to.to` must
  # be its disposition's route.
  @d1_dispositions ~w(genuine_extra_coverage redundant not_a_conformance_claim wrong_against_spec)
  @d1_views ~w(docs/conformance/buckets/bucket-1-2026-07-28.json
               docs/conformance/buckets/claim-unmatched-2026-07-28.json)
  @routes %{"redundant" => "A3", "not_a_conformance_claim" => "A2"}
  @spec_url ~r{\Ahttps://modelcontextprotocol\.io/specification/2026-07-28(/|#|\z)}
  # A D1 row's counterfactual reading (MES-139; authored 29729, ratified 29731):
  # one that fires names a test file's line; one that does not opens "None can: "
  # and cites spec text. `_test.exs:N`, not `test:N` (MES-138 N7).
  @fires_cite ~r/\b[\w-]+_test\.exs:\d+\b/
  @none_can ~r/\ANone can: .*(\.mdx|\.ts|§)/u

  # The D5 family (MES-145; plan 30074-30076, ratified 30077): admitted ONLY in
  # a section bound to a D5 view, and a D5 view admits nothing else
  # (disposition_outside_view, both ways, as the D1 family). The disposition is
  # a checked FUNCTION of the row's evidence (disposition_underivable), and the
  # OC evidence is recomputed here from the committed censuses (`@d5_legs`).
  @d5_dispositions ~w(discriminating vacuous_oc vacuous_et vacuous_both not_established)
  @d5_views ~w(docs/conformance/buckets/bucket-5a-2026-07-28.json
               docs/conformance/buckets/bucket-5b-2026-07-28.json)
  # Each family: its dispositions and the views that admit them, both ways.
  @families [{"D1", @d1_dispositions, @d1_views}, {"D5", @d5_dispositions, @d5_views}]
  @null_outcomes ~w(pass fail skipped not_emitted undetermined)
  # A null whose outcome is one of these lost nothing on the check (Q2).
  @vacuous_outcomes ~w(pass skipped)
  # The discount is an ATTRIBUTE, never a disposition; null and drive_policy
  # are separate entries at each grain and never merged (MES-19; Q4).
  @discount_types ~w(null drive_policy)
  @discount_grains ~w(check scenario)
  @et_kinds ~w(violation null)
  @et_results ~w(red green)
  # The censuses each leg's D5 rows are recomputed from. `nulls` is every
  # committed null census of the leg (a row's `oc_null` covers exactly these);
  # `probe` is the strict-connect probe, whose scope is the adapter
  # catalogue's (`MCP.Conformance.Adapters.scope/2`), never "all".
  @d5_legs %{
    "client" => %{
      "reducer" => "client_summary",
      "measurement" => "docs/conformance/client-2026-07-28.json",
      "nulls" => ~w(docs/conformance/client-2026-07-28-null-connect.json
                    docs/conformance/client-2026-07-28-null-exit0.json
                    docs/conformance/client-2026-07-28-null-request.json),
      "probe" => "docs/conformance/client-2026-07-28-probe-strict-connect.json"
    },
    "server" => %{
      "reducer" => "server_summary",
      "measurement" => "docs/conformance/server-2026-07-28.json",
      "nulls" => ~w(docs/conformance/server-2026-07-28-null-control.json),
      "probe" => nil
    }
  }
  # N_S, a scenario's emission vocabulary, and each check's name and id.
  @bucket_zero "docs/conformance/bucket-0-2026-07-28.json"
  # A scenario passes as driven under this verdict (MCP.Conformance.Discounts).
  @scenario_verdict "server_summary_or_client_summary"

  # The build levels an extend_to_match, build_test or blocked_on_sdk_gap row may
  # name (MES-128, 29444; MES-129, 29460).
  @build_levels ~w(pure_unit mock_transport plug live_http)
  @build_dispositions ~w(extend_to_match build_test blocked_on_sdk_gap)
  @ticket_key ~r/\A[A-Z][A-Z0-9]+-[0-9]+\z/

  @row_fields ~w(member claim tag echo et_test check root_cause if_conformance_fixed
                 disposition rationale)
  @escalated_fields ~w(whose_defect cause_slug)
  @whose ~w(ours suite)
  @slug_verdicts ~w(confirmed corrected)
  # `cg` since MES-135: a bucket-1 view row carries none of the others, so its
  # echo was vacuous (CR K4 on MES-126). Only bucket-1 rows carry `cg`.
  # `search_id` and `the_search_that_found_none` since MES-138 (29693, Q4): the
  # search each D1 verdict re-tests. Only bucket-1 and claim-unmatched rows
  # carry them.
  @echo_fields ~w(shape verdicts bucket escalation_reason escalation_cause cg search_id
                  the_search_that_found_none)
  # A closed section over an empty view echoes these (MES-144; authored 30052,
  # ratified 30055, Q1 and Q2). Not `projected_from`.
  @emptiness_fields ~w(count emptiness_reason universe)

  # The OC locator: each OC token's emitting sites in the pinned harness build.
  # A row's `check` is tied to its tag through it (MES-135 K1).
  @locator "docs/conformance/oc-emitting-sites-2026-07-28.json"
  @no_oc_prefix "oc:none/"
  @r_id ~r/\AR[0-9]+\z/
  # An anchored citation's `at` (MES-161): a full commit id, never an abbreviation.
  @full_sha ~r/\A[0-9a-f]{40}\z/

  # --- the universe of views owed a record (MES-135 K2) ------------------------
  #
  # Declared from an anchor that is NOT the records: the listing of the bucket
  # views directory. Every view there is owed a closing section, except the
  # named exclusions below. A view owed and not yet closed must be named in
  # @pending with the ticket that closes it, and that ticket deletes its line
  # in the change that closes the view (PM ratification, MES-135 29663, Q2).
  @anchor_root "docs/conformance/buckets"
  @anchor_glob "*.json"

  @not_owed %{
    "docs/conformance/buckets/bucket-0-2026-07-28.json" =>
      "the skip-gate rows: keyed by `token`, not `tag`, so the edge triple cannot key them (view_key_collision); no D ticket adjudicates them",
    "docs/conformance/buckets/roll-up-2026-07-28.json" =>
      "the roll-up of the other views (schema bucket-roll-up/1): it projects no rows of its own"
  }

  @pending %{
    "docs/conformance/buckets/bucket-5a-2026-07-28.json" => "MES-148"
  }

  # A record is found OUTSIDE the walk by scanning the files git would commit
  # (tracked, plus untracked and not ignored) for a *.json carrying the record
  # schema. A git-ignored file is not committed unless force-added (`git add
  # -f`), and a force-added one is tracked, so it is in `--cached`, scanned and
  # refused (CR 29679, probe iv). Scanning a merely ignored file made gate 5 a
  # function of one seat's scratch state (MES-135 B1, CR 29671). Run at the
  # repository root.
  @scan_population ~w(ls-files -z --cached --others --exclude-standard)

  def guard, do: @guard
  def anchor, do: {@anchor_root, @anchor_glob}
  def not_owed, do: @not_owed
  def pending, do: @pending
  def scan_population, do: @scan_population
  def source_path, do: @source
  def policy, do: %{not_owed: @not_owed, pending: @pending}
  def walk_root, do: {@walk_root, @walk_glob}
  def dispositions, do: @dispositions
  def build_levels, do: @build_levels
  def d1_dispositions, do: @d1_dispositions
  def d1_views, do: @d1_views
  def routes, do: @routes
  def d5_dispositions, do: @d5_dispositions
  def d5_views, do: @d5_views
  def d5_legs, do: @d5_legs
  def null_outcomes, do: @null_outcomes
  def discount_types, do: @discount_types
  def discount_grains, do: @discount_grains
  def et_kinds, do: @et_kinds
  def bucket_zero_path, do: @bucket_zero
  def echo_fields, do: @echo_fields
  def emptiness_fields, do: @emptiness_fields
  def view_schemas, do: @view_schemas
  def schema, do: @schema
  def locator_path, do: @locator
  def no_oc_prefix, do: @no_oc_prefix
  def r_id, do: @r_id

  # --- the key -------------------------------------------------------------

  @doc """
  The edge triple `[member, claim, tag]`, the same function for a view row and a
  record row. `member` is a `register_key` string whether the row carries the
  member as a map (a view) or as a string (a record).
  """
  def key(row) when is_map(row), do: [member_key(row["member"]), row["claim"], row["tag"]]

  defp member_key(%{"register_key" => k}), do: k
  defp member_key(k) when is_binary(k), do: k
  defp member_key(_), do: nil

  @doc "The fields of a view row a record row must echo verbatim."
  def echo(view_row) when is_map(view_row), do: Map.take(view_row, @echo_fields)

  @doc "The fields of an empty view a closed empty section must echo verbatim, as `emptiness`."
  def emptiness(view) when is_map(view), do: Map.take(view, @emptiness_fields)

  # --- loading --------------------------------------------------------------

  @doc """
  Reads the records under the walk root, every view a section binds, and a
  `source_fun` for repository citations. Options: `:root` (default `.`).
  """
  def load(opts \\ []) do
    root = Keyword.get(opts, :root, ".")
    walk = walk(root)
    records = Map.new(walk, &{&1, read_json(Path.join(root, &1))})

    views =
      records
      |> Enum.flat_map(fn
        {_, {:ok, %{"sections" => s}}} when is_list(s) -> Enum.map(s, &(is_map(&1) && &1["view"]))
        _ -> []
      end)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Map.new(&{&1, read_json(Path.join(root, &1))})

    %{
      walk: walk,
      records: records,
      views: views,
      locator: read_locator(root),
      anchor: anchor(root),
      strays: strays(root),
      outside: outside(root),
      source_fun: &read_source(root, &1),
      d5: load_d5(root)
    }
  end

  @doc """
  The D5 inputs: `bucket_zero`, every census `@d5_legs` names (`censuses`,
  path => read result), and each leg's probe scope from the adapter catalogue.
  Read whether or not a D5 row exists; judged only when one does.
  """
  def load_d5(root) do
    paths =
      for {_, leg} <- @d5_legs,
          p <- [leg["measurement"], leg["probe"] | leg["nulls"]],
          p != nil,
          uniq: true,
          do: p

    %{
      bucket_zero: read_json(Path.join(root, @bucket_zero)),
      censuses: Map.new(paths, &{&1, read_json(Path.join(root, &1))}),
      probe_scope: %{"client" => MCP.Conformance.Adapters.scope(:client, "strict_connect") || []}
    }
  end

  @doc """
  The locator as `{:ok, %{token => [byte_span]}}`. A token is
  `oc:<leg>/<scenario>/<check id>/<name>`, with `#<discriminator>` when the row
  has one. A duplicate token makes the locator unusable.
  """
  def read_locator(root) do
    with {:ok, %{"rows" => rows}} when is_list(rows) <- read_json(Path.join(root, @locator)),
         tokens =
           Enum.map(rows, &{token(&1), Enum.map(&1["sites"] || [], fn s -> s["byte_span"] end)}),
         [] <- tokens |> Enum.frequencies_by(&elem(&1, 0)) |> Enum.filter(&(elem(&1, 1) > 1)) do
      {:ok, Map.new(tokens)}
    else
      {:error, why} ->
        {:error, why}

      {:ok, _} ->
        {:error, "has no `rows` list"}

      dups when is_list(dups) ->
        {:error, "tokens recur: #{inspect(Enum.map(dups, &elem(&1, 0)))}"}
    end
  end

  defp token(%{"key" => [leg, scenario, id, name, _description, disc]}),
    do: "oc:#{leg}/#{scenario}/#{id}/#{name}" <> if(disc in [nil, ""], do: "", else: "#" <> disc)

  defp token(other), do: {:malformed, other}

  @doc "The anchor listing: every `*.json` directly under the bucket views directory, sorted."
  def anchor(root) do
    root
    |> Path.join(@anchor_root)
    |> Path.join(@anchor_glob)
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.join(@anchor_root, Path.basename(&1)))
    |> Enum.sort()
  end

  @doc "Entries of the walk root the walk does not read: anything but a regular `*.json` file."
  def strays(root) do
    dir = Path.join(root, @walk_root)

    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.reject(&(String.ends_with?(&1, ".json") and File.regular?(Path.join(dir, &1))))
        |> Enum.map(&Path.join(@walk_root, &1))
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  @doc """
  `{:ok, paths}`: every `*.json` git would commit (`scan_population/0`, run at
  `root`), outside the walk root, whose top-level `schema` is the record
  schema. `{:error, why}` when that population cannot be established: git
  cannot be run, or `root` is not the top level of a git work tree. The caller
  refuses on an error; there is no fallback to a directory walk.
  """
  def outside(root) do
    with {:ok, files} <- committable(root) do
      {:ok,
       files
       |> Enum.filter(&String.ends_with?(&1, ".json"))
       |> Enum.reject(&(Path.dirname(&1) == @walk_root))
       |> Enum.filter(&record_file?(root, &1))
       |> Enum.sort()}
    end
  end

  defp record_file?(root, rel) do
    with {:ok, bin} <- File.read(Path.join(root, rel)),
         true <- String.contains?(bin, @schema),
         {:ok, %{"schema" => @schema}} <- Jason.decode(bin) do
      true
    else
      _ -> false
    end
  end

  # The files git would commit at `root`: tracked, plus untracked and not
  # ignored. `root` must be the work tree's top level (an empty
  # `--show-prefix`), so the paths are relative to the repository root.
  defp committable(root) do
    with {:ok, prefix} <- git(root, ~w(rev-parse --show-prefix)),
         :ok <- top_level(root, prefix),
         {:ok, out} <- git(root, @scan_population) do
      {:ok, out |> String.split(<<0>>, trim: true) |> Enum.uniq()}
    end
  end

  defp top_level(_root, prefix) when prefix in ["", "\n"], do: :ok

  defp top_level(root, prefix),
    do:
      {:error,
       "#{root} is not the top level of a git work tree (prefix #{inspect(String.trim(prefix))})"}

  defp git(root, args) do
    case System.cmd("git", ["-C", root | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, n} -> {:error, "git #{Enum.join(args, " ")} exited #{n}: #{String.trim(out)}"}
    end
  rescue
    e in ErlangError -> {:error, "git could not be run: #{Exception.message(e)}"}
  end

  @doc "The derived walk: every `*.json` directly under the walk root, relative to `root`, sorted."
  def walk(root) do
    root
    |> Path.join(@walk_root)
    |> Path.join(@walk_glob)
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.join(@walk_root, Path.basename(&1)))
    |> Enum.sort()
  end

  defp read_json(path) do
    with {:ok, bin} <- File.read(path),
         {:ok, doc} <- Jason.decode(bin) do
      {:ok, doc}
    else
      {:error, %Jason.DecodeError{} = e} -> {:error, "not JSON: " <> Exception.message(e)}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  # A citation may only name a relative path inside the repository. An anchored
  # one (`{:at, sha, file}`, MES-161) is read from git objects at `sha`, which
  # must be a full commit id that is an ancestor of HEAD. Each read is memoised
  # per process by `{root, sha, file}`, so a control planting a different sha is
  # read afresh.
  defp read_source(root, {:at, sha, file}) do
    key = {__MODULE__, :at, root, sha, file}

    case Process.get(key) do
      nil ->
        result = read_at(root, sha, file)
        Process.put(key, result)
        result

      result ->
        result
    end
  end

  defp read_source(root, file) do
    if in_repository?(file),
      do: File.read(Path.join(root, file)),
      else: {:error, :outside_repository}
  end

  defp in_repository?(file), do: Path.type(file) == :relative and ".." not in Path.split(file)

  defp read_at(root, sha, file) do
    cond do
      not (is_binary(sha) and sha =~ @full_sha) ->
        {:error, {:at_malformed, sha}}

      not in_repository?(file) ->
        {:error, :outside_repository}

      match?({:error, _}, git(root, ["cat-file", "-e", sha <> "^{commit}"])) ->
        {:error, {:at_unknown, sha}}

      match?({:error, _}, git(root, ["merge-base", "--is-ancestor", sha, "HEAD"])) ->
        {:error, {:at_not_ancestor, sha}}

      true ->
        case git(root, ["show", "#{sha}:#{file}"]) do
          {:ok, src} -> {:ok, src}
          {:error, _} -> {:error, {:at_absent, sha, file}}
        end
    end
  end

  @doc """
  The source a citation is read from: `file` at the tip, or, when the citation
  carries `at`, `file` as it stood at that commit (MES-161).
  """
  def cited_source(%{"file" => f, "at" => sha}, source_fun), do: source_fun.({:at, sha, f})
  def cited_source(%{"file" => f}, source_fun), do: source_fun.(f)

  # --- the audit --------------------------------------------------------------

  @doc """
  Runs the guard over `inputs` (from `load/1`, possibly mutated by a control).
  Returns `%{report: map, defects: [defect]}`. A defect is
  `%{kind, file, key, detail}`.
  """
  def audit(inputs, policy \\ policy()) do
    {sections, record_defects} = sections(inputs.records)
    {view_keys, view_defects} = view_index(sections, inputs.views)

    rows = for s <- sections, r <- s.rows, do: {s, r}

    {locator, locator_defects} =
      case inputs.locator do
        {:ok, loc} -> {loc, []}
        {:error, why} -> {%{}, [d(:unreadable, @locator, nil, why)]}
      end

    d5_rows? =
      Enum.any?(rows, fn {_, r} -> is_map(r) and r["disposition"] in @d5_dispositions end)

    {d5, d5_defects} = if d5_rows?, do: d5_context(Map.get(inputs, :d5)), else: {nil, []}
    ties = %{locator: locator, source_fun: inputs.source_fun, d5: d5}
    row_defects = Enum.flat_map(rows, fn {s, r} -> row_defects(s, r, view_keys, ties) end)
    {citations, citation_defects} = citations(rows, inputs.records, inputs.source_fun)

    set_defects =
      sections
      |> Enum.group_by(& &1.view)
      |> Enum.flat_map(fn {view, ss} -> set_defects(view, ss, view_keys[view]) end)

    {universe, universe_defects} = universe(inputs, sections, policy)

    report = %{
      "guard" => @guard,
      "owed" => universe.owed,
      "closed" => universe.closed,
      "pending" => universe.pending,
      "records_visited" => map_size(inputs.records),
      "sections" => length(sections),
      "rows_visited" => length(rows),
      "views_bound" => sections |> Enum.map(& &1.view) |> Enum.uniq() |> length(),
      "repo_citations_found" => citations.repo,
      "repo_citations_holding" => citations.repo - citations.drifted,
      "repo_citations_anchored" => citations.anchored,
      "anchored_at" => citations.anchored_at,
      "harness_citations_not_verified_in_gate_5" => citations.harness,
      "dispositions" => rows |> Enum.map(fn {_, r} -> r["disposition"] end) |> Enum.frequencies()
    }

    defects =
      record_defects ++
        locator_defects ++
        d5_defects ++
        view_defects ++
        row_defects ++ set_defects ++ citation_defects ++ universe_defects ++ reach(report)

    %{report: report, defects: defects}
  end

  # --- the universe (MES-135 K2) ---------------------------------------------------
  #
  # One function per refusal kind, each taking the same context, so the control's
  # mutation mode can neutralise each clause alone.

  defp universe(inputs, sections, %{not_owed: not_owed, pending: pending}) do
    owed = Enum.reject(inputs.anchor, &Map.has_key?(not_owed, &1))
    closing = sections |> Enum.filter(&(&1.closure == "closed")) |> Enum.group_by(& &1.view)

    ctx = %{
      inputs: inputs,
      sections: sections,
      anchor: inputs.anchor,
      owed: owed,
      closing: closing,
      not_owed: not_owed,
      pending: pending
    }

    defects =
      stray_defects(ctx) ++
        outside_defects(ctx) ++
        catalogue_defects(ctx) ++
        owed_defects(ctx) ++
        pending_closed_defects(ctx) ++
        excluded_defects(ctx) ++
        outside_anchor_defects(ctx) ++
        owner_defects(ctx) ++
        empty_closure_defects(ctx) ++
        emptiness_unechoed_defects(ctx) ++
        emptiness_drift_defects(ctx)

    pending_open =
      for v <- owed,
          not Map.has_key?(closing, v),
          Map.has_key?(pending, v),
          into: %{},
          do: {v, pending[v]}

    {%{
       owed: length(owed),
       closed: Enum.filter(owed, &Map.has_key?(closing, &1)),
       pending: pending_open
     }, defects}
  end

  defp stray_defects(ctx) do
    for f <- ctx.inputs.strays,
        do:
          d(
            :stray_in_walk_root,
            f,
            nil,
            "the walk reads only regular *.json files directly under #{@walk_root}, so this entry would escape G32"
          )
  end

  defp outside_defects(ctx) do
    case ctx.inputs.outside do
      {:ok, files} ->
        for f <- files,
            do:
              d(
                :record_outside_walk,
                f,
                nil,
                "carries schema #{inspect(@schema)} outside #{@walk_root}, where G32 does not walk"
              )

      {:error, why} ->
        [
          d(
            :record_outside_walk,
            ".",
            nil,
            "the files git would commit (git #{Enum.join(@scan_population, " ")}) cannot be listed, so no record outside #{@walk_root} can be ruled out; refused, not skipped: #{why}"
          )
        ]
    end
  end

  defp catalogue_defects(ctx) do
    for {catalogue, entries, universe, not_what} <- [
          {"@not_owed", ctx.not_owed, ctx.anchor, "in the anchor listing of #{@anchor_root}"},
          {"@pending", ctx.pending, ctx.owed,
           "owed (absent from the anchor listing of #{@anchor_root}, or excluded)"}
        ],
        v <- entries |> Map.keys() |> Enum.sort(),
        v not in universe,
        do:
          d(
            :catalogue_names_absent_view,
            v,
            nil,
            "#{catalogue} names a view that is not #{not_what}"
          )
  end

  defp owed_defects(ctx) do
    for v <- ctx.owed,
        not Map.has_key?(ctx.closing, v),
        not Map.has_key?(ctx.pending, v),
        do:
          d(
            :owed_unadjudicated,
            v,
            nil,
            "owed a record (in #{@anchor_root}, not excluded), no closed section binds it, and it is not pending on a named ticket. To fix: add the view to @pending (with the ticket that closes it) or to @not_owed (with a reason) in #{@source}"
          )
  end

  defp pending_closed_defects(ctx) do
    for v <- ctx.owed,
        Map.has_key?(ctx.pending, v),
        s <- Map.get(ctx.closing, v, []),
        do:
          d(
            :pending_but_closed,
            s.file,
            nil,
            "#{v} is closed here and still pending on #{ctx.pending[v]}: the closing ticket deletes its @pending line"
          )
  end

  defp excluded_defects(ctx) do
    for s <- ctx.sections,
        Map.has_key?(ctx.not_owed, s.view),
        do:
          d(
            :bound_to_excluded,
            s.file,
            nil,
            "a section binds #{s.view}, which is not owed a record: #{ctx.not_owed[s.view]}"
          )
  end

  defp outside_anchor_defects(ctx) do
    for s <- ctx.sections,
        s.view not in ctx.anchor,
        do:
          d(
            :bound_outside_anchor,
            s.file,
            nil,
            "a section binds #{s.view}, which is not in the anchor listing of #{@anchor_root}"
          )
  end

  # An open section's owner is the ticket that closes its view: the pending
  # ticket while the view is pending, the closing record's ticket once closed.
  # An unstated owner is open_without_owner's, and a view neither pending nor
  # closed is owed_unadjudicated's, so neither is judged here.
  defp owner_defects(ctx) do
    for %{closure: "open", owner: owner} = s <- ctx.sections,
        # A generator, not `want = …`: a binding filters on truthiness, and a
        # closing record with no `ticket` gives nil, which must be judged.
        want <- [owner_wanted(s.view, ctx)],
        want != :unjudged and stated?(owner) and owner != want,
        do:
          d(
            :owner_mismatch,
            s.file,
            nil,
            "the open section on #{s.view} names owner #{inspect(owner)}; the ticket that closes the view is #{inspect(want)}"
          )
  end

  defp owner_wanted(view, ctx) do
    case {ctx.pending[view], ctx.closing[view]} do
      {t, _} when is_binary(t) -> t
      {_, [c | _]} -> c.ticket
      _ -> :unjudged
    end
  end

  # A closed section with no rows closes only a view that projects none AND
  # says why. Over a view that projects rows, `missing` already fires, so that
  # case is not judged here.
  defp empty_closure_defects(ctx) do
    for %{closure: "closed", rows: []} = s <- ctx.sections,
        {:ok, %{"rows" => []} = v} <- [ctx.inputs.views[s.view]],
        not (v["count"] == 0 and stated_reason?(v["emptiness_reason"])),
        do:
          d(
            :empty_closure_unwarranted,
            s.file,
            nil,
            "a closed section with no rows over #{s.view}, which does not state `count: 0` and an `emptiness_reason`"
          )
  end

  # MES-144 (authored 30052, ratified 30055). The same domain as
  # empty_closure_defects: over a view that projects rows, `missing` fires, and
  # a closed empty section beside an open one with rows is a split view's
  # closing section, which claims no zero.
  defp emptiness_unechoed_defects(ctx) do
    for %{closure: "closed", rows: [], emptiness: :error} = s <- ctx.sections,
        {:ok, %{"rows" => []}} <- [ctx.inputs.views[s.view]],
        do:
          d(
            :emptiness_unechoed,
            s.file,
            nil,
            "a closed section with no rows over #{s.view} carries no `emptiness`, so the zero it claims is implied, not stated: copy the view's #{Enum.join(@emptiness_fields, ", ")} into it verbatim"
          )
  end

  defp emptiness_drift_defects(ctx) do
    for %{emptiness: {:ok, echo}} = s <- ctx.sections,
        why <- [emptiness_drift(s, echo, ctx.inputs.views[s.view])],
        is_binary(why),
        do: d(:emptiness_drift, s.file, nil, why)
  end

  defp emptiness_drift(%{closure: c, rows: rows} = s, _echo, _view)
       when c != "closed" or rows != [],
       do:
         "an `emptiness` echo on a section of #{s.view} that claims no zero (closure #{c}, #{length(rows)} rows): only a closed section with no rows carries one"

  defp emptiness_drift(s, echo, {:ok, v}) when is_map(v) do
    want = emptiness(v)
    echoed = if is_map(echo), do: echo, else: %{}

    moved =
      (Map.keys(echoed) ++ @emptiness_fields)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reject(&(is_map(echo) and Map.fetch(echoed, &1) == Map.fetch(want, &1)))

    if moved != [],
      do:
        "the `emptiness` echo is not #{s.view}'s current #{Enum.join(@emptiness_fields, ", ")}; it differs at #{inspect(moved)} (echoed #{inspect(Map.take(echoed, moved), limit: 4, printable_limit: 120)}, view #{inspect(Map.take(want, moved), limit: 4, printable_limit: 120)})"
  end

  # An unreadable view is unknown_view's.
  defp emptiness_drift(_s, _echo, _view), do: nil

  defp stated_reason?(r) when is_map(r), do: map_size(r) > 0
  defp stated_reason?(r), do: stated?(r)

  defp reach(%{"records_visited" => n, "rows_visited" => 0}) when n > 0,
    do: [
      d(
        :reach,
        "",
        nil,
        "#{n} record(s) visited and ZERO rows: a reader that sees nothing cannot pass"
      )
    ]

  defp reach(_), do: []

  defp sections(records) do
    records
    |> Enum.sort()
    |> Enum.map(fn {file, doc} -> record_sections(file, doc) end)
    |> Enum.reduce({[], []}, fn {ss, ds}, {acc, defects} -> {acc ++ ss, defects ++ ds} end)
  end

  defp record_sections(file, {:ok, %{"schema" => @schema, "authored_by_hand" => true} = doc})
       when is_list(:erlang.map_get("sections", doc)) do
    {ok, bad} = Enum.split_with(doc["sections"], &section?/1)

    bad_defects =
      Enum.map(bad, fn s ->
        d(
          :bad_section,
          file,
          nil,
          "a section needs a string `view`, a `closure` in #{inspect(@closures)} and a `rows` list: #{inspect(s, limit: 5)}"
        )
      end)

    owner_defects =
      for %{"closure" => "open"} = s <- ok, not stated?(s["owner"]) do
        d(
          :open_without_owner,
          file,
          nil,
          "the open section on #{s["view"]} names no `owner`, so nothing closes it"
        )
      end

    parsed =
      Enum.map(
        ok,
        &%{
          file: file,
          ticket: doc["ticket"],
          view: &1["view"],
          closure: &1["closure"],
          owner: &1["owner"],
          rows: &1["rows"],
          emptiness: Map.fetch(&1, "emptiness")
        }
      )

    {parsed, bad_defects ++ owner_defects}
  end

  defp record_sections(file, {:ok, _}) do
    {[],
     [
       d(
         :bad_record,
         file,
         nil,
         "needs schema #{inspect(@schema)}, `authored_by_hand: true` and a `sections` list"
       )
     ]}
  end

  defp record_sections(file, {:error, why}), do: {[], [d(:unreadable, file, nil, why)]}

  defp section?(%{"view" => v, "closure" => c, "rows" => r})
       when is_binary(v) and c in @closures and is_list(r),
       do: true

  defp section?(_), do: false

  # view path -> %{key => view_row}, or :unusable when the view cannot be keyed.
  defp view_index(sections, views) do
    sections
    |> Enum.map(& &1.view)
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn view, {idx, defects} ->
      file = sections |> Enum.find(&(&1.view == view)) |> Map.fetch!(:file)
      {index, ds} = index_view(view, views[view], file)
      {Map.put(idx, view, index), defects ++ ds}
    end)
  end

  defp index_view(view, {:ok, %{"schema" => s, "rows" => rows}}, file)
       when s in @view_schemas and is_list(rows) do
    case rows |> Enum.frequencies_by(&key/1) |> Enum.filter(fn {_, n} -> n > 1 end) do
      [] ->
        {Map.new(rows, &{key(&1), &1}), []}

      collisions ->
        {:unusable,
         Enum.map(collisions, fn {k, n} ->
           d(
             :view_key_collision,
             file,
             k,
             "#{view} projects #{n} rows under this key; the edge triple cannot adjudicate it"
           )
         end)}
    end
  end

  defp index_view(view, other, file) do
    {:unusable,
     [
       d(
         :unknown_view,
         file,
         nil,
         "#{view} is not a readable bucket or escalated view: #{inspect(other, limit: 3)}"
       )
     ]}
  end

  defp row_defects(section, row, view_keys, ties) when is_map(row) do
    k = key(row)
    view_row = view_row(view_keys[section.view], k)
    escalated? = is_map(view_row) and Map.has_key?(view_row, "escalation_reason")

    field_defects(section.file, k, row, escalated?) ++
      disposition_defects(section.file, k, row) ++
      bound_defects(section.file, k, row) ++
      build_defects(section.file, k, row) ++
      sdk_gap_defects(section.file, k, row) ++
      view_scope_defects(section.file, k, row, section.view) ++
      protects_defects(section.file, k, row) ++
      counterpart_defects(section.file, k, row, ties) ++
      routed_to_defects(section.file, k, row) ++
      spec_defects(section.file, k, row) ++
      counterfactual_defects(section.file, k, row) ++
      oc_null_defects(section.file, k, row, ties) ++
      oc_null_drift_defects(section.file, k, row, ties) ++
      null_entailed_defects(section.file, k, row, ties) ++
      discount_set_defects(section.file, k, row, ties) ++
      discount_drift_defects(section.file, k, row, ties) ++
      et_null_defects(section.file, k, row, ties) ++
      derivation_defects(section.file, k, row, ties) ++
      not_established_defects(section.file, k, row) ++
      echo_defects(section.file, k, row, view_row) ++
      et_test_defects(section.file, k, row, ties) ++
      check_defects(section.file, k, row, ties) ++
      root_cause_defects(section.file, k, row, ties) ++
      if(escalated?, do: escalation_defects(section.file, k, row, view_row), else: [])
  end

  defp row_defects(section, row, _, _),
    do: [d(:bad_row, section.file, nil, "a row must be an object: #{inspect(row, limit: 3)}")]

  # --- content tied to the key (MES-135 K1) ----------------------------------------
  #
  # The key and echo bind a row to its edge; these bind the row's CONTENT to the
  # key, each on an anchor outside the record: the member's own test, the OC
  # locator, and the report row that states a root cause. One function per
  # kind, taking the same arguments, so the control can neutralise each alone.

  # A member row's et_test is a repository citation whose window lies inside the
  # member's own test; a row with no member carries `et_test: null`.
  defp et_test_defects(file, k, %{"member" => member} = row, ties) when is_binary(member) do
    case et_test_owner(row, ties.source_fun) do
      :ok ->
        []

      {:error, why} ->
        [
          d(
            :et_test_foreign,
            file,
            k,
            "et_test is not inside #{member}'s own test: #{inspect(why)}"
          )
        ]
    end
  end

  defp et_test_defects(file, k, row, _ties) do
    if is_nil(row["et_test"]),
      do: [],
      else: [
        d(
          :et_test_foreign,
          file,
          k,
          "a row with no member carries `et_test: null`, not #{inspect(row["et_test"], limit: 3)}"
        )
      ]
  end

  # A row on an OC check cites, under `check`, a harness span overlapping a site
  # the locator records for the row's own token. A row on no OC check
  # (`oc:none/`) cites none: there is no check to tie to.
  defp check_defects(file, k, row, ties) do
    tag = row["tag"]
    spans = for c <- collect(row["check"]), Map.has_key?(c, "harness_sha256"), do: c["byte_span"]

    cond do
      is_binary(tag) and String.starts_with?(tag, @no_oc_prefix) ->
        if spans == [],
          do: [],
          else: [
            d(
              :check_foreign,
              file,
              k,
              "an #{@no_oc_prefix} row is on no OC check, so its `check` cites no harness span"
            )
          ]

      not Map.has_key?(ties.locator, tag) ->
        [
          d(
            :check_foreign,
            file,
            k,
            "the tag is not a token of #{@locator}, so `check` cannot be tied to it"
          )
        ]

      Enum.any?(spans, fn s -> Enum.any?(ties.locator[tag], &overlap?(s, &1)) end) ->
        []

      true ->
        [
          d(
            :check_foreign,
            file,
            k,
            "no harness span under `check` (#{inspect(spans)}) overlaps a site #{@locator} records for this tag (#{inspect(ties.locator[tag])})"
          )
        ]
    end
  end

  defp overlap?([a, b], [c, e])
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(e),
       do: max(a, c) < min(b, e)

  defp overlap?(_, _), do: false

  # A root cause named R<n> cites, in `stated_at`, a repository window whose
  # bytes carry **R<n>**: the report row that states it.
  defp root_cause_defects(file, k, %{"root_cause" => %{"id" => id} = rc}, _ties)
       when is_binary(id) do
    if id =~ @r_id, do: stated_at_defects(file, k, id, rc["stated_at"]), else: []
  end

  defp root_cause_defects(_file, _k, _row, _ties), do: []

  defp stated_at_defects(file, k, id, %{"file" => _, "lines" => [_, _], "bytes" => b})
       when is_binary(b) do
    if String.contains?(b, "**#{id}**"),
      do: [],
      else: [d(:root_cause_foreign, file, k, "stated_at's bytes do not carry **#{id}**")]
  end

  defp stated_at_defects(file, k, id, other),
    do: [
      d(
        :root_cause_foreign,
        file,
        k,
        "#{id} needs `stated_at`, a repository citation, not #{inspect(other, limit: 3)}"
      )
    ]

  # `doctest Target.fun/arity (n)` -> Target.
  @doctest_member ~r/\Adoctest ((?:[A-Z][A-Za-z0-9_]*\.)*[A-Z][A-Za-z0-9_]*)\.[^.\/]+\/[0-9]+ \([0-9]+\)\z/

  @test_line ~r/^(\s*)test "((?:[^"\\]|\\.)*)"/
  @one_line_test ~r/,\s*do:/
  @describe_line ~r/^  describe "((?:[^"\\]|\\.)*)"/

  @doc """
  `:ok` when `row["et_test"]` is a repository citation whose window lies inside
  the member's own test (moved here from gate 5 by MES-135 K1). The innermost
  `test "…"` at or above the window's first line owns the window. No other test
  line may start inside the window, and the owner's closing line must be at or
  after the window's last line: for a block test, the first later line equal to
  the test's indent followed by `end` (so a nested `describe`'s shallower `end`,
  and any deeper `end` in the body, are not taken for it); for a one-line
  `, do:` test, the test line itself, so a window reaching past it is refused
  (fail-closed, even for a `do:` body continued onto later lines). The owner
  must be the member's test (qualified by its `describe` when nested), in a
  file that defines the member's module.

  A GENERATED test (MES-141 Q-C, [authored 29813 | ratified 29816]) sits
  under `for {label, _} <- [LITERAL list] do` and its name interpolates the
  label: it is owned under each name the literal list expands to (qualified by
  the `describe` enclosing the `for`), and the window rules above are
  unchanged. Refused by name: `:generator_not_literal` (the list, or an
  element's label, is not a literal), `:name_does_not_interpolate_label`,
  `:name_interpolates_other_than_label`, `:generator_pattern_not_label_pair`,
  `:generator_not_found`; a label absent from the list is `{:names, expansion}`.

  A DOCTEST member (`Mod/doctest Target.fun/arity (n)`, MES-138 S2a,
  [authored 29695 | ratified 29702]) has no
  `test "…"` line: its body is the `@doc` of `Target`, in `lib/`. Its window
  is the ONE line of the `doctest Target` directive (options allowed after a
  comma), in a file that defines the member's module: the address the
  register itself gives a doctest. Every doctest of one directive therefore
  shares that window, so the tie does not separate two of them (stated with
  the content-exchange residual in the moduledoc).
  """
  def et_test_owner(%{"member" => member, "et_test" => et}, source_fun) when is_binary(member) do
    with %{"file" => file, "lines" => [from, to], "bytes" => b}
         when is_binary(file) and is_integer(from) and is_integer(to) and is_binary(b) <-
           et || :not_a_citation,
         [module, member_test] <- String.split(member, "/", parts: 2),
         {:ok, src} <- cited_source(et, source_fun) do
      case Regex.run(@doctest_member, member_test) do
        [_, target] -> doctest_owner(src, from, to, module, target)
        nil -> owner(src, from, to, module, member_test)
      end
    else
      {:error, why} -> {:error, {:unreadable, why}}
      other -> {:error, other}
    end
  end

  def et_test_owner(_row, _source_fun), do: {:error, :no_member}

  defp doctest_owner(src, from, to, module, target) do
    directive = ~r/\A\s*doctest\s+#{Regex.escape(target)}\s*(,.*)?\z/
    line = src |> String.split("\n") |> Enum.at(from - 1)

    with true <- from == to || :doctest_window_is_one_line,
         true <-
           (is_binary(line) and Regex.match?(directive, line)) || {:not_the_directive, target},
         true <- String.contains?(src, "defmodule #{module} do") || :module do
      :ok
    else
      other -> {:error, other}
    end
  end

  defp owner(src, from, to, module, member_test) do
    lines = src |> String.split("\n") |> Enum.with_index(1)
    tests = for {l, i} <- lines, m <- [Regex.run(@test_line, l)], m != nil, do: {i, m}

    with {i, [_, indent, name]} <-
           tests |> Enum.filter(&(elem(&1, 0) <= from)) |> List.last() || :no_test_above,
         true <- Enum.all?(tests, fn {j, _} -> j <= i or j > to end) || :window_crosses_a_test,
         last when is_integer(last) <- test_end(lines, i, indent) || :test_end_not_found,
         true <- to <= last || {:window_outside_test, last},
         {:ok, expected} <- test_names(lines, i, indent, name),
         true <- member_test in expected || {:names, names_reported(expected)},
         true <- String.contains?(src, "defmodule #{module} do") || :module do
      :ok
    else
      other -> {:error, other}
    end
  end

  # A literal test name names one test. A name that interpolates (`#{`) names
  # one test per element of the `for` generator enclosing it, admitted only in
  # the shape MES-141 Q-C ruled ([authored 29813 | ratified 29816]): the
  # nearest shallower line is `for {label, _} <- [LITERAL list] do` at two
  # spaces less indent, every element's first slot is a string literal, and
  # the name interpolates the label and nothing else. Each generated name is
  # resolved by expanding the literal list; anything else is refused by name.
  defp test_names(lines, i, indent, name) do
    if String.contains?(name, "\#{") or under_a_for?(lines, i, indent) do
      generated_names(lines, i, indent, name)
    else
      describe = describe_above(lines, i, indent)
      {:ok, [Enum.join(Enum.reject(["test", describe, unescape(name)], &is_nil/1), " ")]}
    end
  end

  defp generated_names(lines, i, indent, name) do
    for_indent = String.slice(indent, 2..-1//1)

    with true <- byte_size(indent) >= 4 || :generator_not_found,
         {_, f} <- enclosing_line(lines, i, indent) || :generator_not_found,
         {for_line, ^f} = Enum.at(lines, f - 1),
         true <- String.starts_with?(for_line, for_indent <> "for ") || :generator_not_found,
         e when is_integer(e) <- test_end(lines, f, for_indent) || :generator_not_found,
         block = lines |> Enum.slice((f - 1)..(e - 1)) |> Enum.map_join("\n", &elem(&1, 0)),
         {:ok, {:for, _, [{:<-, _, [pattern, list]}, [do: _]]}} <-
           Code.string_to_quoted(block),
         {:ok, var} <- label_var(pattern),
         {:ok, labels} <- literal_labels(list),
         {:ok, template} <- name_template(name, var) do
      describe = if for_indent == "  ", do: nil, else: describe_above(lines, f, for_indent)

      {:ok,
       for l <- labels do
         Enum.join(Enum.reject(["test", describe, template.(l)], &is_nil/1), " ")
       end}
    else
      {:ok, _other} -> :generator_not_a_for
      {:error, {_, _, _}} -> :generator_not_found
      other -> other
    end
  end

  defp under_a_for?(lines, i, indent) do
    case enclosing_line(lines, i, indent) do
      {l, _} -> String.starts_with?(String.trim_leading(l), "for ")
      nil -> false
    end
  end

  # The nearest non-blank line above `i` indented less than the test.
  defp enclosing_line(lines, i, indent) do
    lines
    |> Enum.take(i - 1)
    |> Enum.reverse()
    |> Enum.find(fn {l, _} ->
      String.trim(l) != "" and not String.starts_with?(l, indent)
    end)
  end

  defp label_var({{v, _, ctx}, _}) when is_atom(v) and is_atom(ctx), do: {:ok, v}
  defp label_var(_pattern), do: :generator_pattern_not_label_pair

  defp literal_labels(list) when is_list(list) do
    labels = for {l, _} <- list, is_binary(l), do: l

    if labels != [] and length(labels) == length(list),
      do: {:ok, labels},
      else: :generator_not_literal
  end

  defp literal_labels(_list), do: :generator_not_literal

  # `test "#{label} rest"` quoted is a `<<>>` of literal parts and one
  # interpolation of `label`; any other interpolation is refused.
  defp name_template(name, var) do
    case Code.string_to_quoted(~s(") <> name <> ~s(")) do
      {:ok, {:<<>>, _, parts}} ->
        mapped =
          Enum.map(parts, fn
            p when is_binary(p) ->
              p

            {:"::", _, [{{:., _, [Kernel, :to_string]}, _, [{^var, _, c}]}, _]} when is_atom(c) ->
              :label

            _ ->
              :other
          end)

        cond do
          :other in mapped -> :name_interpolates_other_than_label
          :label not in mapped -> :name_does_not_interpolate_label
          true -> {:ok, fn l -> mapped |> Enum.map_join(&if(&1 == :label, do: l, else: &1)) end}
        end

      _ ->
        :name_does_not_interpolate_label
    end
  end

  defp names_reported([one]), do: one
  defp names_reported(many), do: many

  defp test_end(lines, i, indent) do
    {head, _} = Enum.at(lines, i - 1)

    if Regex.match?(@one_line_test, head) do
      i
    else
      lines
      |> Enum.drop(i)
      |> Enum.find_value(fn {l, j} -> String.trim_trailing(l) == indent <> "end" && j end)
    end
  end

  defp describe_above(_lines, _i, "  "), do: nil

  defp describe_above(lines, i, "    ") do
    lines
    |> Enum.take(i - 1)
    |> Enum.reverse()
    |> Enum.find_value(fn {l, _} ->
      case Regex.run(@describe_line, l) do
        [_, d] -> unescape(d)
        nil -> nil
      end
    end)
  end

  defp describe_above(_lines, _i, _indent), do: :unsupported_nesting

  defp unescape(s), do: String.replace(s, ~S(\"), ~S("))

  defp view_row(index, k) when is_map(index), do: index[k]
  defp view_row(_unusable, _k), do: nil

  defp field_defects(file, k, row, escalated?) do
    required = if escalated?, do: @row_fields ++ @escalated_fields, else: @row_fields

    case Enum.reject(required, &Map.has_key?(row, &1)) do
      [] -> []
      fs -> [d(:bad_row, file, k, "missing #{Enum.join(fs, ", ")}")]
    end
  end

  defp disposition_defects(file, k, row) do
    if row["disposition"] in @dispositions do
      []
    else
      [
        d(
          :disposition_outside_set,
          file,
          k,
          "#{inspect(row["disposition"])} is not one of the guard's closed set #{Enum.join(@dispositions, " ")}"
        )
      ]
    end
  end

  # An accept_bound row must say what it accepts, in one line a consumer can read.
  defp bound_defects(file, k, %{"disposition" => "accept_bound"} = row) do
    b = row["bound"]

    if is_binary(b) and String.trim(b) != "" and not String.contains?(b, ["\n", "\r"]) do
      []
    else
      [
        d(
          :bound_missing,
          file,
          k,
          "an accept_bound row must state its bound as one non-empty line in `bound`, not #{inspect(b, limit: 3)}"
        )
      ]
    end
  end

  defp bound_defects(_file, _k, _row), do: []

  # A bucket-2 row says at what level the missing test would be built, and how,
  # in one line; an extend_to_match row also names the unit it would extend.
  defp build_defects(file, k, %{"disposition" => disp} = row) when disp in @build_dispositions do
    wrong =
      [
        {row["build_level"] in @build_levels,
         "`build_level` in #{inspect(@build_levels)}, not #{inspect(row["build_level"], limit: 3)}"},
        {one_line?(row["remedy"]),
         "a one-line, non-empty `remedy`, not #{inspect(row["remedy"], limit: 3)}"},
        {disp != "extend_to_match" or is_map(row["extend_target"]),
         "an `extend_target` map naming the unit it extends"}
      ]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    case wrong do
      [] -> []
      ws -> [d(:build_level_missing, file, k, "a #{disp} row needs " <> Enum.join(ws, "; "))]
    end
  end

  defp build_defects(_file, _k, _row), do: []

  # A blocked row names the gap that blocks it: the owning ticket, the record
  # that ticket carries, and a citation of the gap in this tree (whose bytes
  # citation_drift holds like any other).
  defp sdk_gap_defects(file, k, %{"disposition" => "blocked_on_sdk_gap"} = row) do
    gap = row["sdk_gap"]

    ok? =
      is_map(gap) and is_binary(gap["owner"]) and gap["owner"] =~ @ticket_key and
        one_line?(gap["owner_record"]) and repo_citation?(gap["record"])

    if ok? do
      []
    else
      [
        d(
          :sdk_gap_missing,
          file,
          k,
          "a blocked_on_sdk_gap row needs `sdk_gap` with a ticket-key `owner`, a one-line `owner_record` and a repository citation `record`, not #{inspect(gap, limit: 3)}"
        )
      ]
    end
  end

  defp sdk_gap_defects(_file, _k, _row), do: []

  # --- the D1 family (MES-138; authored 29691, ratified 29693) ----------------------
  #
  # Shape only, as bound_missing: whether a verdict is RIGHT is the reviewer's.

  # A family's disposition only in a section bound to one of the family's
  # views, and a family's view only the family's dispositions (D1: MES-138; D5:
  # MES-145). A code outside the closed set is disposition_outside_set's.
  defp view_scope_defects(file, k, %{"disposition" => disp}, view) when disp in @dispositions do
    by_disp = Enum.find(@families, fn {_, ds, _} -> disp in ds end)
    by_view = Enum.find(@families, fn {_, _, vs} -> view in vs end)

    case {by_disp, by_view} do
      {same, same} ->
        []

      {{family, _, views}, _} ->
        [
          d(
            :disposition_outside_view,
            file,
            k,
            "#{disp} is a #{family} disposition, admitted only in a section bound to #{Enum.join(views, " or ")}, not #{view}"
          )
        ]

      {nil, {family, ds, _}} ->
        [
          d(
            :disposition_outside_view,
            file,
            k,
            "#{view} admits only the #{family} dispositions #{Enum.join(ds, " ")}, not #{disp}"
          )
        ]
    end
  end

  defp view_scope_defects(_file, _k, _row, _view), do: []

  # A genuine_extra_coverage row says what it protects that OC cannot.
  defp protects_defects(file, k, %{"disposition" => "genuine_extra_coverage"} = row) do
    if one_line?(row["protects"]),
      do: [],
      else: [
        d(
          :protects_missing,
          file,
          k,
          "a genuine_extra_coverage row must state in `protects`, as one non-empty line, what it protects that OC cannot, not #{inspect(row["protects"], limit: 3)}"
        )
      ]
  end

  defp protects_defects(_file, _k, _row), do: []

  # A redundant row names its OC counterpart: a locator token, a harness site
  # overlapping a site the locator records for that token, and why A3 missed
  # it. The tie shows the token HAS that site, not that the counterpart is
  # right (K1-R's lesson; 29693, Q2).
  defp counterpart_defects(file, k, %{"disposition" => "redundant"} = row, ties) do
    oc = row["oc_counterpart"]
    token = is_map(oc) && oc["token"]
    site = is_map(oc) && oc["site"]

    wrong =
      [
        {is_map(oc), "an `oc_counterpart` map"},
        {is_binary(token) and Map.has_key?(ties.locator, token),
         "a `token` of #{@locator}, not #{inspect(token, limit: 3)}"},
        {harness_site?(site) and is_binary(token) and
           Enum.any?(Map.get(ties.locator, token, []), &overlap?(site["byte_span"], &1)),
         "a harness citation `site` whose byte_span overlaps a site the locator records for the token"},
        {is_map(oc) and one_line?(oc["why_a3_missed"]), "a one-line, non-empty `why_a3_missed`"}
      ]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    case wrong do
      [] -> []
      ws -> [d(:counterpart_missing, file, k, "a redundant row needs " <> Enum.join(ws, "; "))]
    end
  end

  defp counterpart_defects(_file, _k, _row, _ties), do: []

  defp harness_site?(%{"harness_sha256" => h, "byte_span" => [_, _], "bytes" => b})
       when is_binary(h) and is_binary(b),
       do: true

  defp harness_site?(_), do: false

  # A redundant or not_a_conformance_claim row is ROUTED, not fixed here: it
  # names where (A3 or A2, by disposition), the receiving ticket, and one line
  # naming the record that ticket carries (the sdk_gap shape).
  defp routed_to_defects(file, k, %{"disposition" => disp} = row)
       when is_map_key(@routes, disp) do
    to = @routes[disp]
    r = row["routed_to"]

    ok? =
      is_map(r) and r["to"] == to and is_binary(r["owner"]) and r["owner"] =~ @ticket_key and
        one_line?(r["owner_record"])

    if ok?,
      do: [],
      else: [
        d(
          :routed_to_missing,
          file,
          k,
          "a #{disp} row needs `routed_to` with `to: #{inspect(to)}`, a ticket-key `owner` and a one-line `owner_record`, not #{inspect(r, limit: 3)}"
        )
      ]
  end

  defp routed_to_defects(_file, _k, _row), do: []

  # A wrong_against_spec row cites the specification: a URL into the
  # 2026-07-28 revision and a one-line verbatim quote. The specification is not
  # in this repository, so the quote's bytes are not held (a stated residual).
  defp spec_defects(file, k, %{"disposition" => "wrong_against_spec"} = row) do
    spec = row["spec"]

    ok? =
      is_map(spec) and is_binary(spec["url"]) and spec["url"] =~ @spec_url and
        one_line?(spec["quote"])

    if ok?,
      do: [],
      else: [
        d(
          :spec_citation_missing,
          file,
          k,
          "a wrong_against_spec row needs `spec` with a `url` into https://modelcontextprotocol.io/specification/2026-07-28 and a one-line verbatim `quote`, not #{inspect(spec, limit: 3)}"
        )
      ]
  end

  defp spec_defects(_file, _k, _row), do: []

  # Every D1 row records one counterfactual reading: could a conforming SDK
  # fail this unit? A firing reading names the test line; a reading that does
  # not fire opens "None can: " and cites spec text. Shape only: which way it
  # goes is the reviewer's.
  defp counterfactual_defects(file, k, %{"disposition" => disp} = row)
       when disp in @d1_dispositions do
    cf = row["counterfactual"]
    fires = is_map(cf) && cf["conforming_sdk_can_fail"]
    reading = is_map(cf) && cf["reading"]

    ok? =
      is_boolean(fires) and one_line?(reading) and
        if(fires, do: reading =~ @fires_cite, else: reading =~ @none_can)

    if ok?,
      do: [],
      else: [
        d(
          :counterfactual_missing,
          file,
          k,
          "a #{disp} row needs `counterfactual` with a boolean `conforming_sdk_can_fail` and a one-line `reading` that, when it fires, names `<name>_test.exs:N`, and otherwise opens `None can: ` citing a `.mdx` or `.ts` file or a §, not #{inspect(cf, limit: 3)}"
        )
      ]
  end

  defp counterfactual_defects(_file, _k, _row), do: []

  # --- the D5 family (MES-145; plan 30074-30076, ratified 30077) --------------------
  #
  # A D5 row answers "would this green go red if the behaviour broke?" on both
  # sides. The OC side is RECOMPUTED here from the committed censuses, never
  # taken from the row: the row's `oc_null` and `discounts` are claims the guard
  # re-derives and requires equal. The ET side is the row's measurement,
  # checked for shape. The disposition is then a function of the two. One
  # function per refusal, taking the same arguments, so the control can
  # neutralise each alone; each skips what another refusal owns, so a plant is
  # refused by one kind.

  @doc """
  The D5 context from `load_d5/1`'s inputs: `{ctx, defects}`. `ctx` is `nil`
  when an input cannot be read, and every D5 recomputation is then skipped
  (each unreadable file is refused as `unreadable`, so nothing passes silently).
  """
  def d5_context(nil),
    do: {nil, [d(:unreadable, @bucket_zero, nil, "the D5 inputs were not loaded")]}

  def d5_context(%{bucket_zero: bz, censuses: censuses, probe_scope: scope}) do
    unreadable =
      for {p, r} <- [{@bucket_zero, bz} | Enum.sort(censuses)],
          not match?({:ok, %{}}, r),
          do: d(:unreadable, p, nil, "a D5 input: #{inspect(r, limit: 3)}")

    missing =
      for {_, leg} <- @d5_legs,
          p <- [leg["measurement"], leg["probe"] | leg["nulls"]],
          p != nil,
          not Map.has_key?(censuses, p),
          do: d(:unreadable, p, nil, "a D5 census @d5_legs names was not loaded")

    case unreadable ++ missing do
      [] ->
        {:ok, %{"checks" => checks}} = bz

        {%{
           checks: Map.new(checks, &{&1["token"], &1}),
           vocab: Enum.group_by(checks, &{&1["leg"], &1["scenario"]}),
           censuses: Map.new(censuses, fn {p, {:ok, doc}} -> {p, doc} end),
           probe_scope: scope
         }, []}

      ds ->
        {nil, ds}
    end
  end

  defp leg_nulls(tag) do
    case leg_scenario(tag) do
      {leg, _} -> get_in(@d5_legs, [leg, "nulls"]) || []
      nil -> []
    end
  end

  # "oc:<leg>/<scenario>/..." -> {leg, scenario}; anything else -> nil.
  defp leg_scenario("oc:" <> rest) do
    case String.split(rest, "/", parts: 3) do
      [leg, scenario, _] -> {leg, scenario}
      _ -> nil
    end
  end

  defp leg_scenario(_), do: nil

  @doc """
  The null outcome a census entails for the check `tag` names, under the
  counts-entail rule: `%{"raw_status" => s | nil, "outcome" => o}`.

  N_S is the scenario's checks in bucket-0. The rule assumes each N_S name is
  emitted at most once and every emission outside N_S appears in
  `failed_checks` (`null_premise_defects/1`), NOT that N_S is the scenario's
  whole emission vocabulary: it is not. A `failed_checks`
  entry matches the check by `name`, or by `id` where that id occurs once in
  N_S (the sep-2322 entries carry name == id). A matched entry gives the raw
  status. Otherwise, with R the N_S names no entry matches (the check among
  them) and F the entries: SUCCESS == |R|, SKIPPED == INFO == 0 and total ==
  SUCCESS + |F| entails raw SUCCESS; SUCCESS == INFO == 0, SKIPPED == |R| and
  total == SKIPPED + |F| entails raw SKIPPED; SUCCESS == SKIPPED == INFO == 0
  and total == |F| entails that the check was never emitted. Anything else,
  and a check or scenario the inputs lack, is `undetermined`: an absence from
  `failed_checks` is never read as a pass. The outcome is the raw status
  reduced under the leg's own reducer (`client_summary` on the client leg, so
  a WARNING is red; Q3), `ignored` reported as `skipped`.
  """
  def null_outcome(ctx, census_path, tag) do
    with {leg, scenario} <- leg_scenario(tag),
         %{"reducer" => reducer} <- @d5_legs[leg],
         %{"name" => name, "key" => [_, _, id | _]} <- ctx.checks[tag],
         %{} = census <- ctx.censuses[census_path],
         %{} = sc <- Enum.find(census["scenarios"] || [], &(&1["id"] == scenario)),
         vocab = Map.get(ctx.vocab, {leg, scenario}, []),
         {:ok, raw} <- raw_status(sc, vocab, name, id) do
      %{"raw_status" => raw, "outcome" => reduce(census, reducer, raw)}
    else
      _ -> %{"raw_status" => nil, "outcome" => "undetermined"}
    end
  end

  defp raw_status(%{"checks" => c, "failed_checks" => f}, vocab, name, id)
       when is_map(c) and is_list(f) do
    ids = Enum.frequencies_by(vocab, &Enum.at(&1["key"], 2))
    matches? = fn e, n, i -> e["name"] == n or (e["id"] == i and ids[i] == 1) end
    names = Enum.map(vocab, &{&1["name"], Enum.at(&1["key"], 2)})

    case f |> Enum.filter(&matches?.(&1, name, id)) |> Enum.map(& &1["status"]) |> Enum.uniq() do
      [status] when is_binary(status) ->
        {:ok, status}

      [] ->
        r = Enum.count(names, fn {n, i} -> not Enum.any?(f, &matches?.(&1, n, i)) end)
        if {name, id} in names, do: entailed_status(c, r, length(f)), else: :error

      _ ->
        :error
    end
  end

  defp raw_status(_sc, _vocab, _name, _id), do: :error

  @doc """
  The count-visible breaches of the premise `null_outcome/3` rests on, over
  every null census of every D5 leg and every scenario bucket-0 gives that
  leg: `{census, scenario, kind}`, empty when the premise holds as far as
  counts can show. `:emitted_twice` is an N_S check matched by more than one
  `failed_checks` entry (at most once, broken); `:unfailed_outside_n_s` is
  more non-failed emissions (`total - |F|`) than N_S checks no entry matches,
  so some emission outside N_S is missing from `failed_checks`;
  `:failed_checks_incomplete` is FAILURE + WARNING != |F|. What counts cannot
  show, a non-N_S SUCCESS standing in for an absent N_S name, is not here.
  """
  def null_premise_defects(ctx) do
    for {leg, %{"nulls" => nulls}} <- Enum.sort(@d5_legs),
        path <- nulls,
        %{} = census <- [ctx.censuses[path]],
        {{^leg, scenario}, vocab} <- Enum.sort(ctx.vocab),
        %{"checks" => c, "failed_checks" => f} <-
          [Enum.find(census["scenarios"] || [], &(&1["id"] == scenario))],
        kind <- premise_breaches(c, f, vocab),
        do: {path, scenario, kind}
  end

  defp premise_breaches(c, f, vocab) do
    ids = Enum.frequencies_by(vocab, &Enum.at(&1["key"], 2))
    hits = fn {n, i} -> Enum.count(f, &(&1["name"] == n or (&1["id"] == i and ids[i] == 1))) end
    hit_counts = Enum.map(vocab, &hits.({&1["name"], Enum.at(&1["key"], 2)}))
    r = Enum.count(hit_counts, &(&1 == 0))
    get = &Map.get(c, &1, 0)

    [
      {:emitted_twice, Enum.any?(hit_counts, &(&1 > 1))},
      {:unfailed_outside_n_s, get.("total") - length(f) > r},
      {:failed_checks_incomplete, get.("FAILURE") + get.("WARNING") != length(f)}
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  # With `r` the N_S names no failed entry matches and `f` the failed entries:
  # the status the counts entail for every one of the `r`, or :error.
  defp entailed_status(c, r, f) do
    counts = Enum.map(~w(SUCCESS SKIPPED INFO total), &Map.get(c, &1))

    case counts do
      [^r, 0, 0, total] when total == r + f -> {:ok, "SUCCESS"}
      [0, ^r, 0, total] when total == r + f -> {:ok, "SKIPPED"}
      [0, 0, 0, ^f] -> {:ok, nil}
      _ -> :error
    end
  end

  defp reduce(_census, _reducer, nil), do: "not_emitted"

  defp reduce(census, reducer, raw) do
    case get_in(census, ["reducers", reducer, "disposition", raw]) do
      "fail" -> "fail"
      "pass" -> "pass"
      "ignored" -> "skipped"
      _ -> "undetermined"
    end
  end

  @doc """
  The `oc_null` a D5 row on `tag` must carry: one entry per null census of the
  tag's leg, each echoing the census's `checks` and `failed_checks` for the
  scenario verbatim, with the entailed `raw_status` and `outcome`.
  """
  def oc_null_expected(ctx, tag) do
    with {leg, scenario} <- leg_scenario(tag), %{"nulls" => nulls} <- @d5_legs[leg] do
      for p <- nulls do
        sc = Enum.find(ctx.censuses[p]["scenarios"] || [], &(&1["id"] == scenario)) || %{}

        Map.merge(
          %{
            "census" => p,
            "scenario" => scenario,
            "checks" => sc["checks"],
            "failed_checks" => sc["failed_checks"]
          },
          null_outcome(ctx, p, tag)
        )
      end
    else
      _ -> []
    end
  end

  @doc """
  The discounts a D5 row on `tag` owes, recomputed from the censuses, sorted:
  each `%{"type", "grain", "sources"}`. `null`/`check`: a null of the leg whose
  outcome is vacuous (`pass` or `skipped`). `null`/`scenario`: the scenario
  passes as driven and some null passes it (`MCP.Conformance.Discounts`'
  null-passable predicate). `drive_policy`/`scenario`: in the probe's scope,
  passed as driven and not under the probe (Discounts' drive-policy
  predicate). `drive_policy`/`check`: in the probe's scope, and the probe's
  outcome for the check is not `pass`.
  """
  def owed_discounts(ctx, tag) do
    with {leg, scenario} <- leg_scenario(tag), %{} = cat <- @d5_legs[leg] do
      driven? = scenario_passes?(ctx.censuses[cat["measurement"]], scenario, true)

      null_check =
        Enum.filter(cat["nulls"], &(null_outcome(ctx, &1, tag)["outcome"] in @vacuous_outcomes))

      null_scenario =
        Enum.filter(cat["nulls"], &scenario_passes?(ctx.censuses[&1], scenario, false))

      probe = cat["probe"]
      in_probe? = probe != nil and scenario in Map.get(ctx.probe_scope, leg, [])

      [
        {"null", "check", null_check, null_check != []},
        {"null", "scenario", null_scenario, driven? and null_scenario != []},
        {"drive_policy", "scenario", [probe],
         in_probe? and driven? and not scenario_passes?(ctx.censuses[probe], scenario, false)},
        {"drive_policy", "check", [probe],
         in_probe? and null_outcome(ctx, probe, tag)["outcome"] != "pass"}
      ]
      |> Enum.filter(&elem(&1, 3))
      |> Enum.map(fn {t, g, src, _} ->
        %{"type" => t, "grain" => g, "sources" => Enum.sort(src)}
      end)
      |> Enum.sort_by(&{&1["type"], &1["grain"]})
    else
      _ -> []
    end
  end

  # As driven (`scored?` true): scored, outside `auth/`, and passing; the
  # predicate MCP.Conformance.Discounts applies to the measurement.
  defp scenario_passes?(census, scenario, scored?) do
    case Enum.find((is_map(census) && census["scenarios"]) || [], &(&1["id"] == scenario)) do
      nil ->
        false

      s ->
        (not scored? or (s["scored"] == true and not String.starts_with?(scenario, "auth/"))) and
          get_in(s, ["passes", @scenario_verdict]) == true
    end
  end

  @doc """
  The disposition a D5 row's evidence entails, or `:unshaped` when its
  `et_null` is not well formed (et_null_missing owns that). OC is vacuous when
  some recomputed null outcome is `pass` or `skipped`; unknown when none is
  and one is `undetermined`. ET is vacuous when a measured mutation stays
  green, or, unmeasured, when the stated reading says so. Then: OC vacuous
  gives `vacuous_both` or `vacuous_oc` by ET; OC able to go red gives
  `vacuous_et` or `discriminating` by a MEASURED ET, and `not_established` on
  a reading alone; OC unknown gives `not_established`.
  """
  def derive_disposition(ctx, tag, et_null) do
    case {et_shape(et_null), oc_side(ctx, tag)} do
      {:error, _} -> :unshaped
      {{_, true}, :vacuous} -> "vacuous_both"
      {{_, false}, :vacuous} -> "vacuous_oc"
      {{:measured, true}, :can_go_red} -> "vacuous_et"
      {{:measured, false}, :can_go_red} -> "discriminating"
      {{:reading, _}, :can_go_red} -> "not_established"
      {_, :unknown} -> "not_established"
    end
  end

  # :vacuous when some recomputed null outcome is vacuous; :unknown when none
  # is and one is undetermined (or the tag has no leg); else :can_go_red.
  defp oc_side(ctx, tag) do
    outcomes =
      with {leg, _} <- leg_scenario(tag), %{"nulls" => nulls} <- @d5_legs[leg] do
        Enum.map(nulls, &null_outcome(ctx, &1, tag)["outcome"])
      else
        _ -> ["undetermined"]
      end

    cond do
      Enum.any?(outcomes, &(&1 in @vacuous_outcomes)) -> :vacuous
      outcomes == [] or "undetermined" in outcomes -> :unknown
      true -> :can_go_red
    end
  end

  # {:measured | :reading, et_vacuous?} for a well-formed et_null, else :error.
  defp et_shape(%{"measured" => true, "mutations" => [_ | _] = ms}) do
    if Enum.all?(ms, &mutation?/1),
      do: {:measured, Enum.any?(ms, &(&1["result"] == "green"))},
      else: :error
  end

  defp et_shape(%{"measured" => false, "reading" => r, "why_not_measured" => w, "vacuous" => v})
       when is_boolean(v) do
    if one_line?(r) and one_line?(w), do: {:reading, v}, else: :error
  end

  defp et_shape(_), do: :error

  defp mutation?(%{"id" => id, "kind" => kind, "edits" => [_ | _] = edits, "result" => res} = m) do
    one_line?(id) and kind in @et_kinds and res in @et_results and Enum.all?(edits, &edit?/1) and
      if(res == "red",
        do: one_line?(m["firing"]) and m["firing"] =~ @fires_cite,
        else: is_nil(m["firing"])
      )
  end

  defp mutation?(_), do: false

  defp edit?(%{"file" => f, "old" => o, "new" => n})
       when is_binary(f) and is_binary(o) and is_binary(n),
       do: f != "" and o != n

  defp edit?(_), do: false

  # The D5 rows whose recomputation can run: a D5 disposition and a context.
  defguardp d5_row?(row, ties)
            when is_map_key(row, "disposition") and
                   :erlang.map_get("disposition", row) in @d5_dispositions and
                   is_map(:erlang.map_get(:d5, ties))

  # oc_null: one well-formed entry per null census of the leg, exactly.
  defp oc_null_defects(file, k, row, ties) when d5_row?(row, ties) do
    with {leg, _} <- leg_scenario(row["tag"]),
         %{"nulls" => nulls} <- @d5_legs[leg],
         entries when is_list(entries) <- row["oc_null"],
         true <- Enum.all?(entries, &null_entry?/1),
         true <- Enum.sort(Enum.map(entries, & &1["census"])) == Enum.sort(nulls) do
      []
    else
      _ ->
        leg = elem(leg_scenario(row["tag"]) || {nil, nil}, 0)

        [
          d(
            :oc_null_missing,
            file,
            k,
            "a D5 row needs `oc_null`: one entry per null census of its leg (#{inspect(get_in(@d5_legs, [leg, "nulls"]))}), each with `census`, `scenario`, `checks`, `failed_checks`, `raw_status` and an `outcome` in #{inspect(@null_outcomes)}, not #{inspect(row["oc_null"], limit: 3)}"
          )
        ]
    end
  end

  defp oc_null_defects(_file, _k, _row, _ties), do: []

  defp null_entry?(%{"census" => c, "scenario" => s, "checks" => ch, "outcome" => o} = e)
       when is_binary(c) and is_binary(s) and is_map(ch) and o in @null_outcomes,
       do: is_list(e["failed_checks"]) and Map.has_key?(e, "raw_status")

  defp null_entry?(_), do: false

  # Each well-formed entry echoes its census's scenario verbatim.
  defp oc_null_drift_defects(file, k, row, ties) when d5_row?(row, ties) do
    want = Map.new(oc_null_expected(ties.d5, row["tag"]), &{&1["census"], &1})

    for e <- List.wrap(row["oc_null"]),
        null_entry?(e),
        # A census outside the leg's catalogue is oc_null_missing's.
        w <- [want[e["census"]]],
        is_map(w),
        moved = for(f <- ~w(scenario checks failed_checks), e[f] != w[f], do: f),
        moved != [],
        do:
          d(
            :oc_null_drift,
            file,
            k,
            "oc_null's entry for #{e["census"]} is not the census's current #{Enum.join(moved, ", ")} (echoed #{inspect(Map.take(e, moved), limit: 4)}, census #{inspect(Map.take(w, moved), limit: 4)})"
          )
  end

  defp oc_null_drift_defects(_file, _k, _row, _ties), do: []

  # Each well-formed entry's outcome and raw status are the ones the census
  # entails (null_outcome/3), recomputed here: gate 5 holds every null claim.
  defp null_entailed_defects(file, k, row, ties) when d5_row?(row, ties) do
    nulls = leg_nulls(row["tag"])

    for e <- List.wrap(row["oc_null"]),
        null_entry?(e),
        # A census outside the leg's catalogue is oc_null_missing's.
        e["census"] in nulls,
        w <- [null_outcome(ties.d5, e["census"], row["tag"])],
        Map.take(e, ~w(raw_status outcome)) != w,
        do:
          d(
            :null_outcome_not_entailed,
            file,
            k,
            "oc_null claims #{inspect(Map.take(e, ~w(raw_status outcome)))} under #{e["census"]}; its counts entail #{inspect(w)}"
          )
  end

  defp null_entailed_defects(_file, _k, _row, _ties), do: []

  defp discount_set_defects(file, k, row, ties) when d5_row?(row, ties) do
    if discounts?(row["discounts"]),
      do: [],
      else: [
        d(
          :discount_outside_set,
          file,
          k,
          "a D5 row needs `discounts`, a list (possibly empty) of `{type in #{inspect(@discount_types)}, grain in #{inspect(@discount_grains)}, sources: [census path]}`, one per type and grain, not #{inspect(row["discounts"], limit: 3)}"
        )
      ]
  end

  defp discount_set_defects(_file, _k, _row, _ties), do: []

  defp discounts?(ds) when is_list(ds) do
    Enum.all?(ds, fn
      %{"type" => t, "grain" => g, "sources" => [_ | _] = src} ->
        t in @discount_types and g in @discount_grains and Enum.all?(src, &is_binary/1)

      _ ->
        false
    end) and ds |> Enum.map(&{&1["type"], &1["grain"]}) |> Enum.uniq() |> length() == length(ds)
  end

  defp discounts?(_), do: false

  # Both ways: an owed discount missing, and a stated one that does not hold.
  defp discount_drift_defects(file, k, row, ties) when d5_row?(row, ties) do
    stated =
      if discounts?(row["discounts"]),
        do:
          row["discounts"]
          |> Enum.map(&%{&1 | "sources" => Enum.sort(&1["sources"])})
          |> Enum.map(&Map.take(&1, ~w(type grain sources)))
          |> Enum.sort_by(&{&1["type"], &1["grain"]}),
        else: :unshaped

    owed = owed_discounts(ties.d5, row["tag"])

    if stated == :unshaped or stated == owed,
      do: [],
      else: [
        d(
          :discount_drift,
          file,
          k,
          "the discounts stated (#{inspect(stated -- owed)} not owed) are not the ones the censuses entail (#{inspect(owed -- stated)} owed and missing)"
        )
      ]
  end

  defp discount_drift_defects(_file, _k, _row, _ties), do: []

  # et_null: measured mutations with byte-exact edits, or a stated reading with
  # why it was not measured. A red mutation names its firing line in the
  # member's own test file, inside the member's own test (a doctest member's
  # body is in lib/, so there only the file is tied).
  defp et_null_defects(file, k, row, ties) when d5_row?(row, ties) do
    et = row["et_null"]

    why =
      case et_shape(et) do
        :error -> :shape
        {:reading, _} -> nil
        {:measured, _} -> firing_foreign(row, et["mutations"], ties.source_fun)
      end

    case why do
      nil ->
        []

      :shape ->
        [
          d(
            :et_null_missing,
            file,
            k,
            "a D5 row needs `et_null`: `{measured: true, mutations: [{id, kind in #{inspect(@et_kinds)}, edits: [{file, old, new}], result in #{inspect(@et_results)}, firing}]}`, a red one's `firing` naming `<name>_test.exs:N` and a green one's none; or `{measured: false, reading, why_not_measured, vacuous: boolean}`; not #{inspect(et, limit: 3)}"
          )
        ]

      other ->
        [
          d(
            :et_null_missing,
            file,
            k,
            "a red mutation's firing line is not the member's: #{other}"
          )
        ]
    end
  end

  defp et_null_defects(_file, _k, _row, _ties), do: []

  defp firing_foreign(row, mutations, source_fun) do
    et_file = get_in(row, ["et_test", "file"])
    doctest? = is_binary(row["member"]) and row["member"] =~ ~r{/doctest }

    Enum.find_value(mutations, fn
      %{"result" => "red", "firing" => f, "id" => id} ->
        [cite] = Regex.run(@fires_cite, f)
        [base, n] = String.split(cite, ":")
        line = String.to_integer(n)

        cond do
          not is_binary(et_file) or Path.basename(et_file) != base ->
            "#{id} fires at #{cite}, not in the member's test file #{inspect(et_file)}"

          doctest? ->
            nil

          et_test_owner(
            %{
              row
              | "et_test" => Map.merge(row["et_test"], %{"lines" => [line, line], "bytes" => ""})
            },
            source_fun
          ) != :ok ->
            "#{id} fires at #{cite}, which is not inside #{row["member"]}'s own test"

          true ->
            nil
        end

      _ ->
        nil
    end)
  end

  # The disposition is the one the evidence entails.
  defp derivation_defects(file, k, row, ties) when d5_row?(row, ties) do
    stated = row["disposition"]

    case derive_disposition(ties.d5, row["tag"], row["et_null"]) do
      :unshaped ->
        []

      ^stated ->
        []

      disp ->
        [
          d(
            :disposition_underivable,
            file,
            k,
            "#{row["disposition"]} does not follow from the row's evidence, which entails #{disp} (the null outcomes recomputed from the censuses, and et_null)"
          )
        ]
    end
  end

  defp derivation_defects(_file, _k, _row, _ties), do: []

  # The honest "not established" is never free: it says why, in one line.
  defp not_established_defects(file, k, %{"disposition" => "not_established"} = row) do
    if one_line?(row["not_established_because"]),
      do: [],
      else: [
        d(
          :not_established_because_missing,
          file,
          k,
          "a not_established row states why in one line, `not_established_because`, not #{inspect(row["not_established_because"], limit: 3)}"
        )
      ]
  end

  defp not_established_defects(_file, _k, _row), do: []

  defp repo_citation?(%{"file" => f, "lines" => [_, _], "bytes" => b})
       when is_binary(f) and is_binary(b),
       do: true

  defp repo_citation?(_), do: false

  defp one_line?(t),
    do: is_binary(t) and String.trim(t) != "" and not String.contains?(t, ["\n", "\r"])

  defp echo_defects(file, k, row, view_row) do
    if is_map(view_row) and row["echo"] != echo(view_row) do
      [
        d(
          :echo_drift,
          file,
          k,
          "echo #{inspect(row["echo"])} is not the view's #{inspect(echo(view_row))}"
        )
      ]
    else
      []
    end
  end

  defp escalation_defects(file, k, row, view_row) do
    whose =
      if row["whose_defect"] in @whose,
        do: [],
        else: [d(:bad_row, file, k, "whose_defect must be one of #{inspect(@whose)}")]

    slug =
      case row["cause_slug"] do
        %{"view" => v, "verdict" => verdict} when verdict in @slug_verdicts ->
          cond do
            v != view_row["escalation_cause"] ->
              [
                d(
                  :echo_drift,
                  file,
                  k,
                  "cause_slug.view #{inspect(v)} is not the view's #{inspect(view_row["escalation_cause"])}"
                )
              ]

            verdict == "corrected" and not stated?(row["cause_slug"]["to"]) ->
              [d(:bad_row, file, k, "a corrected cause_slug must name what it is corrected `to`")]

            true ->
              []
          end

        _ ->
          [
            d(
              :bad_row,
              file,
              k,
              "cause_slug must be {view, verdict in #{inspect(@slug_verdicts)}}"
            )
          ]
      end

    whose ++ slug
  end

  defp set_defects(view, sections, keys) when is_map(keys) do
    adjudicated = for s <- sections, r <- s.rows, is_map(r), do: {s.file, key(r)}
    counts = Enum.frequencies_by(adjudicated, &elem(&1, 1))
    closed = for %{closure: "closed", file: f} <- sections, do: f

    phantom =
      for {f, k} <- adjudicated,
          not Map.has_key?(keys, k),
          do:
            d(
              :phantom,
              f,
              k,
              "adjudicated in a section bound to #{view}, which projects no such edge"
            )

    # Attributed to EVERY file holding the key, not to the view's first section
    # (MES-135 F7).
    duplicate =
      for {k, n} <- counts,
          n > 1,
          f <-
            adjudicated
            |> Enum.filter(&(elem(&1, 1) == k))
            |> Enum.map(&elem(&1, 0))
            |> Enum.uniq(),
          do: d(:duplicate, f, k, "adjudicated #{n} times across the sections bound to #{view}")

    # Attributed to the closing section's file: the section that owes the edge.
    missing =
      case closed do
        [] ->
          []

        [f | _] ->
          for k <- Map.keys(keys),
              not Map.has_key?(counts, k),
              do:
                d(
                  :missing,
                  f,
                  k,
                  "#{view} projects this edge and a closed section bound to it does not adjudicate it"
                )
      end

    closure_not_exclusive(view, closed) ++ phantom ++ duplicate ++ Enum.sort_by(missing, & &1.key)
  end

  defp set_defects(view, sections, _unusable),
    do: closure_not_exclusive(view, for(%{closure: "closed", file: f} <- sections, do: f))

  # A view is closed by ONE section (MES-135 K3). Two closed sections over
  # disjoint halves of a view each pass duplicate and, jointly, missing, so
  # neither of those entails this.
  defp closure_not_exclusive(_view, [_]), do: []
  defp closure_not_exclusive(_view, []), do: []

  defp closure_not_exclusive(view, closed) do
    for f <- closed do
      d(
        :closure_not_exclusive,
        f,
        nil,
        "#{view} is closed by #{length(closed)} sections (#{Enum.join(closed, ", ")}); a view is closed by one section, and any other binding it must be open"
      )
    end
  end

  # --- citations ---------------------------------------------------------------

  # Every citation in the WHOLE record: a row's, attributed to its key, and
  # every other (top-level, or a section's outside its rows) with no key
  # (MES-135, 29433(a); PM 29663 Q4).
  defp citations(rows, records, source_fun) do
    found =
      for({s, r} <- rows, is_map(r), c <- collect(r), do: {s.file, key(r), c}) ++
        for {file, {:ok, doc}} <- Enum.sort(records),
            c <- collect(outside_rows(doc)),
            do: {file, nil, c}

    forms = Enum.frequencies_by(found, fn {_, _, c} -> citation_form(c) end)

    failed =
      for {f, k, c} <- found,
          {:error, why} <- [verify(c, source_fun)],
          do: {c, d(drift_kind(c, source_fun), f, k, "#{cite_label(c)} #{why}")}

    anchored = for {_, _, c} <- found, citation_form(c) == :repo, Map.has_key?(c, "at"), do: c

    counts = %{
      repo: Map.get(forms, :repo, 0),
      harness: Map.get(forms, :harness, 0),
      drifted: Enum.count(failed, fn {c, _} -> citation_form(c) == :repo end),
      anchored: length(anchored),
      anchored_at: anchored |> Enum.map(& &1["at"]) |> Enum.uniq() |> Enum.sort()
    }

    held =
      for {_, _, c} = x <- found, citation_form(c) == :repo, verify(c, source_fun) == :ok, do: x

    {counts,
     Enum.map(failed, &elem(&1, 1)) ++
       ambiguous_defects(held, source_fun) ++
       unwarranted_defects(held, source_fun) ++
       prose_anchor_defects(rows, records)}
  end

  defp cite_label(%{"at" => at} = c), do: "#{c["file"]}:#{inspect(c["lines"])} @#{at}"
  defp cite_label(c), do: "#{c["file"]}:#{inspect(c["lines"])}"

  # An `at` that cannot be read as an ancestor commit is the anchor's defect,
  # not the bytes': a malformed or unknown sha, one that is not an ancestor of
  # HEAD, or a file absent at it.
  defp drift_kind(%{"file" => f, "at" => sha}, source_fun) do
    case source_fun.({:at, sha, f}) do
      {:ok, _} -> :citation_drift
      {:error, _} -> :anchor_invalid
    end
  end

  defp drift_kind(_c, _source_fun), do: :citation_drift

  # An anchored citation is admitted ONLY for text a later commit removed: its
  # squashed bytes may occur nowhere in the file at the tip. Text still there,
  # at the same lines or moved, is cited at the tip, so `at` cannot hide
  # ordinary drift (PM ruling, MES-161 30337 Q9 (b)).
  defp unwarranted_defects(held, source_fun) do
    for {f, k, %{"at" => at} = c} <- held,
        tip = Map.delete(c, "at"),
        {:ok, _} <- [source_fun.(c["file"])],
        [_ | _] = starts <- [occurrences(tip, source_fun)],
        do:
          d(
            :anchor_unwarranted,
            f,
            k,
            "#{cite_label(c)} — its bytes still occur at the tip, at lines #{inspect(starts, charlists: :as_lists)}; `at` is only for text a later commit removed, so cite it at the tip (#{short_sha(at)} is not needed)"
          )
  end

  defp short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)

  # A prose anchor (`prose_anchors`, MES-161) holds a citation written in prose
  # (`x_test.exs:N`) at the commit it was measured at. It must carry `at`, and
  # its `cite` must occur in the text of the `field` it names on the map that
  # holds it.
  defp prose_anchor_defects(rows, records) do
    in_rows = for {s, r} <- rows, is_map(r), x <- prose_holders(r), do: {s.file, key(r), x}

    outside =
      for {file, {:ok, doc}} <- Enum.sort(records),
          x <- prose_holders(outside_rows(doc)),
          do: {file, nil, x}

    for {f, k, {holder, entry}} <- in_rows ++ outside,
        why <- [prose_anchor_why(holder, entry)],
        why != nil,
        do: d(:prose_anchor_foreign, f, k, why)
  end

  defp prose_holders(%{"prose_anchors" => pa} = m) when is_list(pa),
    do: Enum.map(pa, &{m, &1}) ++ prose_holders(Map.delete(m, "prose_anchors"))

  defp prose_holders(m) when is_map(m), do: m |> Map.values() |> Enum.flat_map(&prose_holders/1)
  defp prose_holders(l) when is_list(l), do: Enum.flat_map(l, &prose_holders/1)
  defp prose_holders(_), do: []

  defp prose_anchor_why(holder, %{"field" => field, "cite" => cite} = e)
       when is_binary(field) and is_binary(cite) do
    text = get_in(holder, String.split(field, "."))

    cond do
      not is_binary(e["at"]) -> "a prose anchor for #{inspect(cite)} carries no `at`"
      not is_binary(text) -> "a prose anchor names #{inspect(field)}, which holds no text here"
      not String.contains?(text, cite) -> "#{inspect(cite)} does not occur in #{field}"
      true -> nil
    end
  end

  defp prose_anchor_why(_holder, e),
    do: "a prose anchor needs `field` and `cite`: #{inspect(Map.drop(e, ["bytes"]))}"

  # A citation whose bytes recur, at an equal window elsewhere in the file, is
  # right on its bytes and may be wrong on its unit (MES-128's capabilities_test
  # :8 and :64). It must say WHICH occurrence it means, and G32 checks that the
  # n-th equal window is the one cited (MES-135, 29451; PM 29663 Q3).
  defp ambiguous_defects(held, source_fun) do
    # Each cited file is read and squashed once per audit.
    squashed =
      held
      |> Enum.map(fn {_, _, c} -> source_key(c) end)
      |> Enum.uniq()
      |> Map.new(fn sk -> {sk, squashed_lines(sk, source_fun)} end)

    for {f, k, %{"lines" => [from, _]} = c} <- held,
        starts <- [occurrences_in(c, squashed[source_key(c)])],
        n <- [Enum.find_index(starts, &(&1 == from)) + 1],
        (length(starts) > 1 or Map.has_key?(c, "occurrence")) and c["occurrence"] != n,
        do:
          d(
            :citation_ambiguous,
            f,
            k,
            "#{c["file"]}:#{inspect(c["lines"], charlists: :as_lists)} — its bytes recur at lines #{inspect(starts, charlists: :as_lists)}; it is occurrence #{n}, and carries `occurrence: #{inspect(c["occurrence"])}`"
          )
  end

  @doc """
  The first lines of every window of `c`'s length in `c`'s file whose squashed
  text equals the squashed `bytes`, in order. A held citation's own `from` is
  among them.
  """
  def occurrences(c, source_fun),
    do: occurrences_in(c, squashed_lines(source_key(c), source_fun))

  # Which source a citation is read from: its file, at `at` when it has one.
  defp source_key(c), do: Map.take(c, ["file", "at"])

  defp squashed_lines(sk, source_fun) do
    {:ok, src} = cited_source(sk, source_fun)
    src |> String.split("\n") |> Enum.map(&squash/1) |> List.to_tuple()
  end

  defp occurrences_in(%{"lines" => [from, to], "bytes" => b}, lines) do
    len = to - from + 1
    want = squash(b)

    # A window equal to `want` starts on a blank line or on a line `want`
    # starts with; only those are joined and compared.
    for i <- 0..(tuple_size(lines) - len)//1,
        head <- [elem(lines, i)],
        head == "" or String.starts_with?(want, head),
        window(lines, i, len) == want,
        do: i + 1
  end

  defp window(lines, i, len) do
    i..(i + len - 1)
    |> Enum.map(&elem(lines, &1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp outside_rows(%{"sections" => ss} = doc) when is_list(ss),
    do: %{doc | "sections" => Enum.map(ss, &if(is_map(&1), do: Map.delete(&1, "rows"), else: &1))}

  defp outside_rows(doc), do: doc

  defp citation_form(%{"file" => _, "lines" => _}), do: :repo
  defp citation_form(%{"harness_sha256" => _, "byte_span" => _}), do: :harness
  defp citation_form(_), do: :malformed

  @doc false
  def collect(%{"bytes" => b} = m) when is_binary(b), do: [m]
  def collect(m) when is_map(m), do: m |> Map.values() |> Enum.flat_map(&collect/1)
  def collect(l) when is_list(l), do: Enum.flat_map(l, &collect/1)
  def collect(_), do: []

  @doc """
  `:ok` when the cited line window of `file`, whitespace-squashed, EQUALS the
  squashed `bytes`. A `bytes` map that is neither a repository nor a harness
  citation is an error, so a malformed citation cannot slip past as uncounted.
  """
  def verify(%{"file" => f, "lines" => [from, to], "bytes" => b} = c, source_fun)
      when is_binary(f) and is_integer(from) and is_integer(to) and from >= 1 and to >= from do
    case cited_source(c, source_fun) do
      {:ok, src} -> compare(String.split(src, "\n"), from, to, b)
      {:error, why} -> {:error, "cannot be read: #{inspect(why)}"}
    end
  end

  def verify(%{"harness_sha256" => _, "byte_span" => [_, _]}, _source_fun), do: :ok

  def verify(other, _source_fun),
    do: {:error, "is not a citation of either form: #{inspect(Map.drop(other, ["bytes"]))}"}

  defp compare(lines, _from, to, _b) when to > length(lines),
    do: {:error, "is past the end of the file (#{length(lines)} lines)"}

  defp compare(lines, from, to, b) do
    window = lines |> Enum.slice((from - 1)..(to - 1)) |> Enum.join("\n") |> squash()

    if window == squash(b),
      do: :ok,
      else: {:error, "holds #{inspect(window)}, not the cited #{inspect(squash(b))}"}
  end

  @doc "Whitespace runs collapsed to one space, trimmed."
  def squash(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp stated?(t), do: is_binary(t) and t != ""

  defp d(kind, file, key, detail), do: %{kind: kind, file: file, key: key, detail: detail}

  @doc "One line per defect, naming the guard, the kind, the record file and the edge key."
  def format_defect(%{kind: k, file: f, key: key, detail: det}),
    do: "#{@guard} #{k} — #{f}#{if key, do: " @ " <> inspect(key), else: ""}: #{det}"
end
