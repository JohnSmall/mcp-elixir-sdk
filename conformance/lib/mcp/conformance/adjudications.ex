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
  ratified 29731] (Q1).

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
      and `echo`) can be exchanged and still audit CLEAN if and only if BOTH:
      (a) the `check` tie does not separate them: their ties are MUTUAL (each
      row's harness span overlaps a locator site of the OTHER row's token,
      which happens where the two tokens share a site), OR both rows are
      `oc:none/` (no span on either side, so nothing to tie); and (b) the
      `et_test` tie does not separate them: both rows are member-less, or
      each row's window is owned by the OTHER row's member (the tie asks only
      that the window lie in the row's own member's test, so the same member
      test, or two doctests of one `doctest` directive, which share its one
      line).
      `root_cause_foreign` separates no pair, because `stated_at` travels with
      the root cause. `check_foreign` accepts a span overlapping ANY locator
      site of the token, and sites are shared: measured at MES-135, 11 of the
      locator's 143 distinct sites are sites of more than one token, 82 of its
      173 tokens have ONLY shared sites, and 60 of the 108 committed rows tie
      their check only through a shared site (48 bucket-2, 12 member rows);
      still 60 of 138 at MES-138, and of 173 at MES-139, since an `oc:none/`
      row cites no site.
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
      the set by (a) and (b) over every committed row and asserts it EQUALS
      the audited set pair for pair, and pins two pairs CLEAN as known residuals: CR's bucket-2 plant (D2a-ii's
      `caching` and `tools-call-with-progress` `WireSchemaValid` rows, which
      differ on `check`, `disposition`, `extend_target`, `remedy`,
      `root_cause` and three more fields) and the cross-record member pair
      (D4a's `initialize`, D4b's `ping`). So a row, a tie, or this paragraph
      moving the set shows up red there. For a token whose sites are all
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

  ## What is refused

  `unreadable`, `bad_record`, `bad_section`, `unknown_view`,
  `view_key_collision`, `open_without_owner`, `bad_row`,
  `disposition_outside_set`, `bound_missing`, `build_level_missing`, `sdk_gap_missing`,
  `disposition_outside_view`, `protects_missing`, `counterpart_missing`,
  `routed_to_missing`, `spec_citation_missing`, `counterfactual_missing`,
  `phantom`, `missing`,
  `duplicate`, `closure_not_exclusive`, `owed_unadjudicated`, `pending_but_closed`,
  `catalogue_names_absent_view`, `bound_to_excluded`, `bound_outside_anchor`,
  `owner_mismatch`, `empty_closure_unwarranted`, `record_outside_walk`,
  `stray_in_walk_root`, `et_test_foreign`, `check_foreign`, `root_cause_foreign`,
  `citation_ambiguous`, `echo_drift`, `citation_drift`, and `reach`. Every refusal names the guard, the kind, the
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
                   genuine_extra_coverage redundant not_a_conformance_claim wrong_against_spec)

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

  # The OC locator: each OC token's emitting sites in the pinned harness build.
  # A row's `check` is tied to its tag through it (MES-135 K1).
  @locator "docs/conformance/oc-emitting-sites-2026-07-28.json"
  @no_oc_prefix "oc:none/"
  @r_id ~r/\AR[0-9]+\z/

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
    "docs/conformance/buckets/bucket-1-2026-07-28.json" => "MES-143",
    "docs/conformance/buckets/bucket-3-2026-07-28.json" => "MES-144",
    "docs/conformance/buckets/bucket-5a-2026-07-28.json" => "MES-148",
    "docs/conformance/buckets/bucket-5b-2026-07-28.json" => "MES-146",
    "docs/conformance/buckets/bucket-6-2026-07-28.json" => "MES-144"
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
  def echo_fields, do: @echo_fields
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
      source_fun: &read_source(root, &1)
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

  # A citation may only name a relative path inside the repository.
  defp read_source(root, file) do
    if Path.type(file) == :relative and ".." not in Path.split(file),
      do: File.read(Path.join(root, file)),
      else: {:error, :outside_repository}
  end

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

    ties = %{locator: locator, source_fun: inputs.source_fun}
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
      "harness_citations_not_verified_in_gate_5" => citations.harness,
      "dispositions" => rows |> Enum.map(fn {_, r} -> r["disposition"] end) |> Enum.frequencies()
    }

    defects =
      record_defects ++
        locator_defects ++
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
        empty_closure_defects(ctx)

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
          rows: &1["rows"]
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
         {:ok, src} <- source_fun.(file) do
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

  # A D1 disposition only in a section bound to a D1 view, and a D1 view only
  # D1 dispositions. A code outside the closed set is disposition_outside_set's.
  defp view_scope_defects(file, k, %{"disposition" => disp}, view) when disp in @dispositions do
    case {disp in @d1_dispositions, view in @d1_views} do
      {same, same} ->
        []

      {true, false} ->
        [
          d(
            :disposition_outside_view,
            file,
            k,
            "#{disp} is a D1 disposition, admitted only in a section bound to #{Enum.join(@d1_views, " or ")}, not #{view}"
          )
        ]

      {false, true} ->
        [
          d(
            :disposition_outside_view,
            file,
            k,
            "#{view} admits only the D1 dispositions #{Enum.join(@d1_dispositions, " ")}, not #{disp}"
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
          do: {c, d(:citation_drift, f, k, "#{c["file"]}:#{inspect(c["lines"])} #{why}")}

    counts = %{
      repo: Map.get(forms, :repo, 0),
      harness: Map.get(forms, :harness, 0),
      drifted: Enum.count(failed, fn {c, _} -> citation_form(c) == :repo end)
    }

    held =
      for {_, _, c} = x <- found, citation_form(c) == :repo, verify(c, source_fun) == :ok, do: x

    {counts, Enum.map(failed, &elem(&1, 1)) ++ ambiguous_defects(held, source_fun)}
  end

  # A citation whose bytes recur, at an equal window elsewhere in the file, is
  # right on its bytes and may be wrong on its unit (MES-128's capabilities_test
  # :8 and :64). It must say WHICH occurrence it means, and G32 checks that the
  # n-th equal window is the one cited (MES-135, 29451; PM 29663 Q3).
  defp ambiguous_defects(held, source_fun) do
    # Each cited file is read and squashed once per audit.
    squashed =
      held
      |> Enum.map(fn {_, _, c} -> c["file"] end)
      |> Enum.uniq()
      |> Map.new(fn f -> {f, squashed_lines(f, source_fun)} end)

    for {f, k, %{"lines" => [from, _]} = c} <- held,
        starts <- [occurrences_in(c, squashed[c["file"]])],
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
  def occurrences(%{"file" => f} = c, source_fun),
    do: occurrences_in(c, squashed_lines(f, source_fun))

  defp squashed_lines(f, source_fun) do
    {:ok, src} = source_fun.(f)
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
  def verify(%{"file" => f, "lines" => [from, to], "bytes" => b}, source_fun)
      when is_binary(f) and is_integer(from) and is_integer(to) and from >= 1 and to >= from do
    case source_fun.(f) do
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
