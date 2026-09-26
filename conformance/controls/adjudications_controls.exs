# Controls for G32, the D-group adjudication guard (MES-126; MES-127 added the
# D4b plants, the removed-code mutations and the bound_missing mutation; MES-128
# added the D2b plants, its two codes' removal and the build_level_missing
# mutation; MES-129 added the D2a-i plants on an OPEN section, the selector
# refusal, blocked_on_sdk_gap's removal and the sdk_gap_missing mutation; MES-130
# added D2a-ii's CLOSED section on the same view, which turns D2a-i's two
# admitted plants into refusals, and the D2a-ii plants).
#
#     mix run conformance/controls/adjudications_controls.exs positive
#     mix run conformance/controls/adjudications_controls.exs refusals
#     mix run conformance/controls/adjudications_controls.exs mutation
#     mix run conformance/controls/adjudications_controls.exs harness
#     mix run conformance/controls/adjudications_controls.exs all
#     mix run conformance/controls/adjudications_controls.exs swap-audit
#
# `swap-audit` (MES-138, R3-1) is NOT part of `all`: it exchanges the contents
# of every pair of committed rows through A.audit (9453 pairs, about 14 minutes
# at 32-way at MES-138). It is the source of gate 5's @k1r_clean_cliques
# fixture, which is pasted from its printed literal and never from the unit's
# computed set, and it prints the difference both ways against that fixture.
#
# WHAT G32 CLAIMS. Every edge a bound view projects is adjudicated exactly once
# by a record row with a disposition from the closed set, and every repository
# citation in a row holds the bytes it quotes. `positive` shows the committed
# tree green. `refusals` plants each defect into the REAL record or view, and
# requires the refusal it is about and nothing else. Each refusal must NAME G32,
# because a red for an unrelated reason would otherwise pass the control.
#
# `refusals` covers ALL FIVE records: the D4a plants below; on D4b's record a
# phantom 4b row, a dropped 4b row, and an accept_bound row with its `bound`
# removed (bound_missing); and on D2b's record a phantom 2b row, a dropped 2b
# row, and extend_to_match / build_test rows with their `build_level`,
# `remedy` or `extend_target` removed (build_level_missing); and on D2a-i's
# OPEN section on bucket-2a a phantom row, a shifted status window
# (citation_drift), a blocked_on_sdk_gap row with its `sdk_gap` or its
# `build_level` removed, and two plants that G32 ADMITTED while the section was
# the view's only binding (a dropped MRTR row, and a real 2a row from outside the
# slice). Since MES-130 bound bucket-2a with D2a-ii's CLOSED section, G32 refuses
# them itself (missing and duplicate), and the selector still names each. On
# D2a-ii's record: a phantom row, a view row in NEITHER slice (missing), a row
# in BOTH slices (duplicate), and a blocked row with its sdk_gap removed.
#
# `mutation` recompiles the guard inside this VM. (1) THE KEY. It binds
# complete synthetic sections to the REAL views `bucket-4b` and `bucket-5a`,
# with D4b's own section on `bucket-4b` removed IN MEMORY first, since a second
# closed section over the same view would otherwise refuse as duplicate
# whatever the key. The real guard keys both and is clean.
# With `key/1` cut to the member alone, `bucket-4b` is refused
# (view_key_collision). With `key/1` cut to `[member, tag]`, `bucket-4b` passes
# and `bucket-5a` is refused, because 5a carries rows that differ only by claim.
# So each component of the triple is load-bearing on a real view, and neither
# shorter key can adjudicate the D group. (2) THE WALK. With the walk glob
# narrowed, the committed tree audits clean over ZERO records. That is the
# silent pass the gate-5 pin on `walk_root/0` exists to catch, and the control
# shows the pin failing under that mutant. (3) THE NEW CODES. With
# `extend_test`, `accept_bound`, `extend_to_match`, `build_test` or
# `blocked_on_sdk_gap` removed from the closed set, the committed tree is
# refused as disposition_outside_set on exactly the rows carrying that code. (4) BOUND_MISSING. With the bound check
# cut out of the guard, the missing-bound plant audits CLEAN, so the refusal in
# `refusals` is the check's. (5) BUILD_LEVEL_MISSING. Likewise with the build
# check cut out: the missing-level plant audits CLEAN. (6) SDK_GAP_MISSING.
# Likewise with the sdk_gap check cut out: the missing-gap plant audits CLEAN.
#
# MES-135 hardened G32 before its reuse by the D block. `refusals` gains W3
# (K3, exclusive closure); the F7 attribution checks; a table of plants, one
# per new kind (`plants/1`), for the universe of owed views (K2), the ties of a
# row's content to its key (K1: W6, an unnamed-position plant on D2a-ii's last
# row, and bucket-5a- and bucket-1-shaped rows built from the real views),
# recurring citation bytes (Q3) and top-level citations (Q4); and W1 and W5
# as planted on 4a's initialize row (W1 with RequestMetaInvalid's content),
# which more than one tie refuses. That is a claim about those two plants, not
# about member rows. Two rows' contents exchange unseen iff their check ties
# are mutual and the et_test tie does not separate them (both member-less, or
# the same member test): 481 of the 5778 pairs of committed rows at MES-135,
# 477 bucket-2 and 4 member (the moduledoc names them). At MES-138 the
# predicate is amended (check: mutual, OR both `oc:none/`; et_test: each
# window owned by the other's member) and `swap-audit` measures it over every
# pair: 482 of 9453, 477 bucket-2 and 5 member. Two of the MES-135 pairs are
# shown CLEAN as KNOWN RESIDUALS: CR's bucket-2 plant (K1-R, CR 29672) and
# the cross-record D4a initialize / D4b ping member pair (K1-R2, CR 29680).
# `mutation` gains (7) closure_not_exclusive cut; (8) each new kind's clause
# neutralised alone, with its plant then CLEAN; (9) W1 and W5 on the member
# row still refused under any one neutralisation and CLEAN only under all of
# theirs; (10) the walk narrowed back to rows. A narrowed
# walk (2) is no longer a silent pass: G32 refuses it as owed_unadjudicated.
# Plants that need files (outside the walk, a stray) use a tree copy under
# the system tmp dir, never the clone, made a git work tree of its own because
# the outside-the-walk scan lists the files git would commit (MES-135 B1).
#
# `harness` verifies every harness citation in EVERY record against the pinned
# conformance build: sha256 first, then each byte span. Gate 5 cannot do this,
# because the build is not in this repository. It FAILS CLOSED when the build
# is absent or its sha differs. Set MES_HARNESS_DIST to point at it; the default
# is where the accepted runs installed it.
#
# MES-138 added the D1 family (authored 29691, ratified 29693). `refusals`
# gains `d1_plants/2`: with positive controls first (a bucket-1 row, in an
# open section over the REAL bucket-1 view, as each well-formed D1 code:
# CLEAN), one plant per D1 refusal (protects_missing, counterpart_missing,
# routed_to_missing, spec_citation_missing) and disposition_outside_view both
# ways (fix_sdk in bucket-1; genuine_extra_coverage on D4a's 4a row). They join
# the plants table, so `mutation` (8) neutralises each clause alone and
# requires its plant CLEAN.
#
# WHY IN MEMORY. Every plant mutates decoded data inside this VM. Nothing in the
# clone is written, because seats share one checkout.

defmodule AdjudicationsControls do
  alias MCP.Conformance.Adjudications, as: A

  @record "docs/conformance/adjudications/adjudication-D4a-2026-07-28.json"
  @d4b "docs/conformance/adjudications/adjudication-D4b-2026-07-28.json"
  @v4a "docs/conformance/buckets/bucket-4a-2026-07-28.json"
  @ves "docs/conformance/buckets/escalated-2026-07-28.json"
  @v0 "docs/conformance/buckets/bucket-0-2026-07-28.json"
  @v4b "docs/conformance/buckets/bucket-4b-2026-07-28.json"
  @d2b "docs/conformance/adjudications/adjudication-D2b-2026-07-28.json"
  @v2b "docs/conformance/buckets/bucket-2b-2026-07-28.json"
  @v5a "docs/conformance/buckets/bucket-5a-2026-07-28.json"
  @d2ai "docs/conformance/adjudications/adjudication-D2a-i-2026-07-28.json"
  @v2a "docs/conformance/buckets/bucket-2a-2026-07-28.json"
  @d2aii "docs/conformance/adjudications/adjudication-D2a-ii-2026-07-28.json"
  @w3 "docs/conformance/adjudications/adjudication-W3-plant.json"
  @v1 "docs/conformance/buckets/bucket-1-2026-07-28.json"
  @vcu "docs/conformance/buckets/claim-unmatched-2026-07-28.json"
  @d1 "docs/conformance/adjudications/adjudication-D1-nd-CU-2026-07-28.json"
  # The arity of each clause `mutation` neutralises (MES-135).
  @arity %{
    "owed_defects" => 1,
    "pending_closed_defects" => 1,
    "catalogue_defects" => 1,
    "excluded_defects" => 1,
    "outside_anchor_defects" => 1,
    "owner_defects" => 1,
    "empty_closure_defects" => 1,
    "outside_defects" => 1,
    "stray_defects" => 1,
    "et_test_defects" => 4,
    "check_defects" => 4,
    "root_cause_defects" => 4,
    "echo_defects" => 4,
    "view_scope_defects" => 4,
    "protects_defects" => 3,
    "counterpart_defects" => 4,
    "routed_to_defects" => 3,
    "spec_defects" => 3,
    "ambiguous_defects" => 2
  }
  @source "conformance/lib/mcp/conformance/adjudications.ex"
  @default_dist "/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js"
  @tcg1c_ascii "a non-ASCII tool name rides `mcp-name` as the Base64 sentinel and decodes back to the body value"
  @tcg1c_crlf "a CRLF-bearing tool name is neutralised — it rides `mcp-name` encoded, carries no raw CR, and injects no header"

  def run(["swap-audit"]) do
    swap_audit()
    IO.puts("\nPASS swap-audit")
  end

  def run([mode]) when mode in ~w(positive refusals mutation harness) do
    apply(__MODULE__, String.to_existing_atom(mode), [])
    IO.puts("\nPASS #{mode}")
  end

  def run(["all"]) do
    for m <- ~w(positive refusals mutation harness)a, do: apply(__MODULE__, m, [])
    IO.puts("\nPASS all")
  end

  def run(_) do
    IO.puts(
      "usage: mix run #{__ENV__.file |> Path.relative_to_cwd()} positive|refusals|mutation|harness|swap-audit|all"
    )

    System.halt(2)
  end

  # --- positive ------------------------------------------------------------------

  def positive do
    header("positive — the committed tree")
    %{report: r, defects: defects} = A.audit(A.load())

    check("clean", defects == [], Enum.map(defects, &A.format_defect/1))
    check("the D4a record is visited", @record in A.load().walk)
    check("the D4b record is visited", @d4b in A.load().walk)
    check("the D2b record is visited", @d2b in A.load().walk)
    check("the D2a-i record is visited", @d2ai in A.load().walk)
    check("the D2a-ii record is visited", @d2aii in A.load().walk)
    check("the D1-nd+CU record is visited", @d1 in A.load().walk)

    check(
      "reach: #{r["rows_visited"]} rows over #{r["views_bound"]} views",
      r["rows_visited"] > 0
    )

    IO.puts("        #{inspect(r)}")
  end

  # --- refusals ------------------------------------------------------------------

  def refusals do
    header("refusals — each planted into the real record or view")
    base = A.load()

    first_4a = rows(base, @v4a) |> hd()

    expect(
      "(a) missing: a 4a row dropped",
      [:missing],
      A.key(first_4a),
      update_rows(base, @v4a, &tl/1)
    )

    phantom = Map.put(first_4a, "tag", "oc:server/no-such-scenario/no-such-check/NoSuchCheck")

    # Since MES-135 K1 a planted tag also unties the check: check_foreign co-fires.
    expect(
      "(b) phantom: a row keyed to an edge the view does not project",
      [:check_foreign, :phantom],
      A.key(phantom),
      update_rows(base, @v4a, &(&1 ++ [phantom]))
    )

    expect(
      "(c) disposition_outside_set",
      [:disposition_outside_set],
      A.key(first_4a),
      update_rows(base, @v4a, fn [r | rest] -> [Map.put(r, "disposition", "wontfix") | rest] end)
    )

    expect(
      "duplicate: one edge adjudicated twice",
      [:duplicate],
      A.key(first_4a),
      update_rows(base, @v4a, &(&1 ++ [first_4a]))
    )

    expect(
      "echo_drift: the view's OC verdict moves under an unchanged key",
      [:echo_drift],
      A.key(first_4a),
      update_view_row(base, @v4a, A.key(first_4a), &put_in(&1, ["verdicts", "oc"], "green"))
    )

    stale = update_in(first_4a, ["et_test", "lines"], fn [a, b] -> [a + 1, b + 1] end)

    expect(
      "citation_drift: an et_test window shifted by one line",
      [:citation_drift],
      A.key(first_4a),
      update_rows(base, @v4a, fn [_ | rest] -> [stale | rest] end)
    )

    # K5 (MES-135): the refused run above must not print a verified count.
    %{report: sr, defects: sd} =
      A.audit(update_rows(base, @v4a, fn [_ | rest] -> [stale | rest] end))

    out = Mix.Tasks.Conformance.Adjudications.render(sr, sd)

    check(
      "  … K5: the task's report for that refused run makes no verified-count claim " <>
        "(#{sr["repo_citations_found"]} found, #{sr["repo_citations_found"] - sr["repo_citations_holding"]} drifted)",
      not String.contains?(out, "verified") and
        sr["repo_citations_found"] - sr["repo_citations_holding"] == 1,
      String.split(out, "\n")
    )

    %{report: cr, defects: []} = A.audit(base)

    check(
      "  … K5: and the clean tree's report does: #{cr["repo_citations_holding"]} verified",
      Mix.Tasks.Conformance.Adjudications.render(cr, []) =~
        "#{cr["repo_citations_holding"]} repository citations verified" and
        cr["repo_citations_holding"] == cr["repo_citations_found"]
    )

    # On D2a-i's open section, whose view D2a-ii closes. (Opening D4a's 4a
    # section, the plant before MES-135, now also leaves 4a owed_unadjudicated.)
    expect(
      "open_without_owner: D2a-i's open section with its owner removed",
      [:open_without_owner],
      nil,
      update_section(base, @v2a, &Map.delete(&1, "owner"), @d2ai)
    )

    expect_kinds(
      "  … and D4a's 4a section opened without an owner: open_without_owner AND owed_unadjudicated",
      [:open_without_owner, :owed_unadjudicated],
      update_section(base, @v4a, &(&1 |> Map.put("closure", "open") |> Map.delete("owner")))
    )

    # Overwrite one T-CG1c row's claim with its sibling's. Each is its own
    # member, so the overwritten row keys to no edge (phantom) and its own edge is
    # left unadjudicated (missing). Both fire. Neither masks the other.
    ascii = Enum.find(rows(base, @ves), &(&1["claim"] == @tcg1c_ascii))

    swapped =
      update_rows(base, @ves, fn rs ->
        Enum.map(
          rs,
          &if(&1["claim"] == @tcg1c_ascii, do: Map.put(&1, "claim", @tcg1c_crlf), else: &1)
        )
      end)

    expect_kinds(
      "claim overwrite on a T-CG1c row: phantom AND missing",
      [:missing, :phantom],
      swapped
    )

    check(
      "  … and the missing key is the overwritten row's own",
      Enum.any?(A.audit(swapped).defects, &(&1.kind == :missing and &1.key == A.key(ascii)))
    )

    # --- D4b's record ---
    first_4b = rows(base, @v4b, @d4b) |> hd()

    phantom_4b =
      Map.put(first_4b, "claim", "a removed `ping` over HTTP yields HTTP 404 (no such claim)")

    expect(
      "(D4b) phantom: a 4b row keyed to an edge bucket-4b does not project",
      [:phantom],
      A.key(phantom_4b),
      update_rows(base, @v4b, &(&1 ++ [phantom_4b]), @d4b)
    )

    expect(
      "(D4b) missing: a 4b row dropped",
      [:missing],
      A.key(first_4b),
      update_rows(base, @v4b, &tl/1, @d4b)
    )

    bounded = Enum.find(rows(base, @v4b, @d4b), &(&1["disposition"] == "accept_bound"))

    expect(
      "(D4b) bound_missing: an accept_bound row with its bound removed",
      [:bound_missing],
      A.key(bounded),
      drop_bound(base, bounded)
    )

    expect(
      "(D4b) bound_missing: an accept_bound row whose bound runs to two lines",
      [:bound_missing],
      A.key(bounded),
      update_rows(
        base,
        @v4b,
        &Enum.map(&1, fn r ->
          if r == bounded, do: Map.update!(r, "bound", fn b -> b <> "\nand more" end), else: r
        end),
        @d4b
      )
    )

    # --- D2b's record ---
    first_2b = rows(base, @v2b, @d2b) |> hd()

    phantom_2b =
      Map.put(first_2b, "tag", "oc:client/http-invalid-tool-headers/no-such-check/NoSuchCheck")

    expect(
      "(D2b) phantom: a 2b row keyed to a check bucket-2b does not project",
      [:check_foreign, :phantom],
      A.key(phantom_2b),
      update_rows(base, @v2b, &(&1 ++ [phantom_2b]), @d2b)
    )

    expect(
      "(D2b) missing: a 2b row dropped",
      [:missing],
      A.key(first_2b),
      update_rows(base, @v2b, &tl/1, @d2b)
    )

    extend_row = Enum.find(rows(base, @v2b, @d2b), &(&1["disposition"] == "extend_to_match"))
    build_row = Enum.find(rows(base, @v2b, @d2b), &(&1["disposition"] == "build_test"))

    for {row, field} <- [
          {extend_row, "build_level"},
          {extend_row, "remedy"},
          {extend_row, "extend_target"},
          {build_row, "build_level"},
          {build_row, "remedy"}
        ] do
      expect(
        "(D2b) build_level_missing: the #{row["disposition"]} row with its #{field} removed",
        [:build_level_missing],
        A.key(row),
        drop_field(base, row, field)
      )
    end

    expect(
      "(D2b) build_level_missing: a build_level outside the set",
      [:build_level_missing],
      A.key(build_row),
      update_rows(
        base,
        @v2b,
        &Enum.map(&1, fn r ->
          if r == build_row, do: Map.put(r, "build_level", "unit"), else: r
        end),
        @d2b
      )
    )

    # --- D2a-i's record: an OPEN section on bucket-2a, owner MES-130 ---
    d2ai = rows(base, @v2a, @d2ai)
    first_2a = hd(d2ai)

    phantom_2a =
      Map.put(
        first_2a,
        "tag",
        "oc:server/input-required-result-no-such/no-such-check/NoSuchCheck"
      )

    expect(
      "(D2a-i) phantom: a row keyed to a check bucket-2a does not project, in an OPEN section",
      [:check_foreign, :phantom],
      A.key(phantom_2a),
      update_rows(base, @v2a, &(&1 ++ [phantom_2a]), @d2ai)
    )

    shifted =
      update_in(first_2a, ["oc_status_at_accepted_run", "lines"], fn [a, b] -> [a + 1, b + 1] end)

    expect(
      "(D2a-i) citation_drift: a status window shifted by one line",
      [:citation_drift],
      A.key(first_2a),
      update_rows(base, @v2a, fn [_ | rest] -> [shifted | rest] end, @d2ai)
    )

    blocked_row = Enum.find(d2ai, &(&1["disposition"] == "blocked_on_sdk_gap"))

    for {field, kind} <- [{"sdk_gap", :sdk_gap_missing}, {"build_level", :build_level_missing}] do
      expect(
        "(D2a-i) #{kind}: the blocked_on_sdk_gap row with its #{field} removed",
        [kind],
        A.key(blocked_row),
        drop_field(base, blocked_row, field, @v2a, @d2ai)
      )
    end

    # D2a-i's section is still OPEN, but since MES-130 the view is also bound by
    # D2a-ii's CLOSED section, so G32 refuses both of these itself. The
    # selector still names each, and gate 5 holds the selector.
    view_rows = File.read!(@v2a) |> Jason.decode!() |> Map.fetch!("rows")
    {:ok, rec} = base.records[@d2ai]
    in_slice = selected(view_rows, rec["selector"])
    [outside | _] = view_rows -- in_slice
    foreign = %{first_2a | "tag" => outside["tag"]}
    planted = update_rows(base, @v2a, &(&1 ++ [foreign]), @d2ai)

    expect(
      "(D2a-i) a real 2a row from OUTSIDE the slice: duplicate, D2a-ii adjudicates it (and its check ties to another token)",
      [:check_foreign, :duplicate, :duplicate],
      A.key(foreign),
      planted
    )

    check(
      "  … F7: the duplicate is attributed to BOTH files holding the key",
      for(%{kind: :duplicate, file: f} <- A.audit(planted).defects, do: f) == [@d2ai, @d2aii]
    )

    check(
      "  … and refused by the record's selector, naming it: #{outside["tag"]}",
      selector_diff(planted, view_rows) == {[A.key(foreign)], []}
    )

    dropped = update_rows(base, @v2a, &tl/1, @d2ai)

    expect(
      "(D2a-i) a dropped MRTR row: missing, because a CLOSED section binds the view",
      [:missing],
      A.key(first_2a),
      dropped
    )

    check(
      "  … and refused by the record's selector, naming it",
      selector_diff(dropped, view_rows) == {[], [A.key(first_2a)]}
    )

    check(
      "  … and the committed record meets its selector exactly",
      selector_diff(base, view_rows) == {[], []}
    )

    # The catalogue as it stood before MES-130 closed the view: 2a pending on it.
    pre_mes130 = %{A.policy() | pending: Map.put(A.pending(), @v2a, "MES-130")}

    check(
      "  … and with D2a-ii's section removed (2a pending on MES-130 again), no duplicate or missing remains: those refusals are the closure's (the foreign row's check_foreign is K1's, and stays)",
      Enum.map(A.audit(drop_record(planted, @d2aii), pre_mes130).defects, & &1.kind) ==
        [:check_foreign] and
        A.audit(drop_record(dropped, @d2aii), pre_mes130).defects == []
    )

    # --- D2a-ii's record: a CLOSED section on bucket-2a ---
    d2aii = rows(base, @v2a, @d2aii)
    first_ii = hd(d2aii)

    phantom_ii =
      Map.put(first_ii, "tag", "oc:server/server-stateless/no-such-check/NoSuchCheck")

    expect(
      "(D2a-ii) phantom: a row keyed to a check bucket-2a does not project",
      [:check_foreign, :phantom],
      A.key(phantom_ii),
      update_rows(base, @v2a, &(&1 ++ [phantom_ii]), @d2aii)
    )

    gap = update_rows(base, @v2a, &tl/1, @d2aii)

    expect(
      "(D2a-ii) a GAP, one view row in neither slice: missing",
      [:missing],
      A.key(first_ii),
      gap
    )

    check(
      "  … F7: the missing row is reported against D2a-ii, the closing record (was D2a-i, the view's first section)",
      Enum.map(A.audit(gap).defects, & &1.file) == [@d2aii]
    )

    overlap = update_rows(base, @v2a, &(&1 ++ [first_ii]), @d2ai)

    expect(
      "(D2a-ii) an OVERLAP, one D2a-ii row planted into D2a-i too: duplicate, in both files",
      [:duplicate, :duplicate],
      A.key(first_ii),
      overlap
    )

    check(
      "  … F7: attributed to D2a-i and D2a-ii",
      Enum.map(A.audit(overlap).defects, & &1.file) == [@d2ai, @d2aii]
    )

    # --- K3 (MES-135): W3, exclusive closure ---
    w3 = split_closed(base, @v4a, @record, 2)

    expect_kinds(
      "(K3) W3: 4a's rows split across two CLOSED sections in two records",
      [:closure_not_exclusive],
      w3
    )

    check(
      "  … one refusal per closing file, each naming both",
      Enum.map(A.audit(w3).defects, & &1.file) == [@record, @w3] and
        Enum.all?(A.audit(w3).defects, &(&1.detail =~ @record and &1.detail =~ @w3))
    )

    check(
      "  … and with the second half's section OPEN (owned), the split is admitted: the refusal is the closure's",
      A.audit(split_closed(base, @v4a, @record, 2, "open")).defects == []
    )

    blocked_ii = Enum.find(d2aii, &(&1["disposition"] == "blocked_on_sdk_gap"))

    expect(
      "(D2a-ii) sdk_gap_missing: a blocked_on_sdk_gap row with its sdk_gap removed",
      [:sdk_gap_missing],
      A.key(blocked_ii),
      drop_field(base, blocked_ii, "sdk_gap", @v2a, @d2aii)
    )

    bound0 = bind(base, @v0)

    expect_kinds(
      "view_key_collision: bucket-0 cannot be keyed by the triple (and, since MES-135, is not owed a record)",
      [:bound_to_excluded, :view_key_collision],
      bound0
    )

    # --- K1 (MES-135): W1 and W5 as planted on 4a's initialize row, each
    # refused by more than one tie. Not every pair of rows is refused: the
    # K1-R and K1-R2 residuals below exchange CLEAN. ---
    {w1, w5} = {w1(base), w5(base)}

    expect_kinds(
      "(K1) W1: 4a's initialize row keeps its key and echo, and carries RequestMetaInvalid's et_test, check, root cause and disposition",
      [:check_foreign, :et_test_foreign],
      w1
    )

    expect_kinds(
      "(K1) W5: every citation in 4a's initialize row replaced by prose",
      [:check_foreign, :et_test_foreign, :root_cause_foreign],
      w5
    )

    # K1-R (MES-135, CR 29672): a KNOWN RESIDUAL, shown rather than claimed away.
    check(
      "(K1-R) KNOWN RESIDUAL: D2a-ii's caching and tools-call-with-progress WireSchemaValid rows exchange every field but the key and echo, and audit CLEAN (bucket-2: the check tie is the only tie, and it accepts a shared site)",
      A.audit(k1r_swap(base)).defects == []
    )

    # K1-R2 (MES-135, CR 29680): the member half. One member test carries both
    # rows, and their check ties are mutual, so the et_test tie cannot tell them
    # apart. The no-op guard: the two rows differ on disposition, and the plant
    # changes both records.
    {k1r2, {da, db}} = k1r2_swap(base)

    check(
      "(K1-R2) KNOWN RESIDUAL: D4a's initialize row and D4b's ping row, on one member test (StreamableHTTPStatelessTest), exchange every field but the key and echo across records, and audit CLEAN",
      {da, db} == {"fix_sdk", "extend_test"} and k1r2.records[@record] != base.records[@record] and
        k1r2.records[@d4b] != base.records[@d4b] and A.audit(k1r2).defects == []
    )

    # --- Q4 (MES-135, 29433(a)): top-level citations are walked by G32 ---
    for {label, inputs} <- q4_plants(base) do
      expect("(Q4) #{label}", [:citation_drift], nil, inputs)
    end

    # --- the table of plants for each new kind (MES-135), shared with `mutation` ---
    for {kind, label, inputs, policy} <- plants(base) do
      %{defects: ds} = A.audit(inputs, policy)
      lines = Enum.map(ds, &A.format_defect/1)

      check(
        "(#{kind}) #{label}",
        ds != [] and Enum.all?(ds, &(&1.kind == kind)),
        lines
      )

      named(lines)
    end

    # --- B2 (MES-135, CR 29672): the owed_unadjudicated refusal names the fix ---
    b7 = "docs/conformance/buckets/bucket-7-2026-07-28.json"
    %{defects: owed} = A.audit(Map.update!(base, :anchor, &Enum.sort([b7 | &1])))

    check(
      "(B2) a bucket-7 view added to the anchor: owed_unadjudicated names @pending, @not_owed and the file to edit",
      match?([%{kind: :owed_unadjudicated, file: ^b7}], owed) and
        hd(owed).detail =~
          "To fix: add the view to @pending (with the ticket that closes it) or to @not_owed (with a reason) in conformance/lib/mcp/conformance/adjudications.ex" and
        File.regular?(A.source_path()),
      Enum.map(owed, &A.format_defect/1)
    )
  end

  # {kind, label, inputs, policy}: each plant is on the REAL records and views,
  # and is refused by exactly `kind` (every defect it yields is of that kind).
  # `mutation` neutralises each kind's clause and requires the plant to pass.
  def plants(base) do
    policy = A.policy()
    {:ok, d4a} = base.records[@record]
    esc_rows = rows(base, @ves)

    copy_view = "docs/conformance/escalated-copy-2026-07-28.json"

    copy_record =
      {:ok,
       %{
         "schema" => A.schema(),
         "authored_by_hand" => true,
         "ticket" => "MES-126",
         "sections" => [%{"view" => copy_view, "closure" => "closed", "rows" => esc_rows}]
       }}

    v3 = "docs/conformance/buckets/bucket-3-2026-07-28.json"
    {:ok, v3_doc} = v3 |> File.read!() |> Jason.decode()

    empty_record =
      {:ok,
       %{
         "schema" => A.schema(),
         "authored_by_hand" => true,
         "ticket" => "MES-144",
         "sections" => [%{"view" => v3, "closure" => "closed", "rows" => []}]
       }}

    closes_3 =
      base
      |> add_record(@w3, empty_record)
      |> put_in([:views, v3], {:ok, Map.delete(v3_doc, "emptiness_reason")})

    check(
      "  (positive) bucket-3 closed empty over its committed view, which states count 0 and why: CLEAN",
      A.audit(put_in(closes_3, [:views, v3], {:ok, v3_doc}), %{
        policy
        | pending: Map.delete(policy.pending, v3)
      }).defects == []
    )

    tmp = tree_copy()

    outside =
      tree_load(tmp, fn root ->
        File.cp!(
          Path.join(root, @record),
          Path.join(root, "docs/conformance/adjudication-copy.json")
        )
      end)

    stray =
      tree_load(tmp, fn root ->
        File.cp!(
          Path.join(root, @record),
          Path.join(root, "docs/conformance/adjudications/adjudication-copy.jsn")
        )
      end)

    check(
      "  (positive) the unplanted tree copy audits CLEAN",
      A.audit(tree_load(tmp, fn _ -> :ok end)).defects == []
    )

    File.rm_rf!(tmp)

    [
      {:owed_unadjudicated, "W2: D4a's escalated section dropped",
       update_in(base, [:records, @record], fn _ ->
         {:ok, Map.update!(d4a, "sections", &Enum.reject(&1, fn s -> s["view"] == @ves end))}
       end), policy},
      {:owed_unadjudicated, "UNNAMED POSITION: a bucket-7 view file added to the anchor",
       Map.update!(
         base,
         :anchor,
         &Enum.sort(["docs/conformance/buckets/bucket-7-2026-07-28.json" | &1])
       ), policy},
      {:pending_but_closed, "@pending still names bucket-4a, which D4a closes", base,
       %{policy | pending: Map.put(policy.pending, @v4a, "MES-126")}},
      {:catalogue_names_absent_view,
       "bucket-5a's view file removed from the anchor while @pending names it",
       Map.update!(base, :anchor, &List.delete(&1, @v5a)), policy},
      {:catalogue_names_absent_view,
       "roll-up's view file removed from the anchor while @not_owed names it",
       Map.update!(
         base,
         :anchor,
         &List.delete(&1, "docs/conformance/buckets/roll-up-2026-07-28.json")
       ), policy},
      {:bound_to_excluded, "@not_owed widened to exclude bucket-4b, which D4b's record binds",
       base, %{policy | not_owed: Map.put(policy.not_owed, @v4b, "control")}},
      {:bound_outside_anchor,
       "the escalated rows closed again over a copy of the view outside the buckets directory",
       base |> add_record(@w3, copy_record) |> put_in([:views, copy_view], base.views[@ves]),
       policy},
      {:owner_mismatch,
       "D2a-i's open section on bucket-2a owned by MES-129, not MES-130 (D2a-ii's ticket)",
       update_section(base, @v2a, &Map.put(&1, "owner", "MES-129"), @d2ai), policy},
      {:empty_closure_unwarranted,
       "bucket-3 closed empty (as MES-144 would) over a view stripped of its emptiness_reason",
       closes_3, %{policy | pending: Map.delete(policy.pending, v3)}},
      {:record_outside_walk,
       "a copy of D4a's record under docs/conformance/ (in a tree copy outside the clone)",
       outside, policy},
      {:stray_in_walk_root, "a copy of D4a's record as .jsn in the walk root (tree copy)", stray,
       policy}
    ] ++ k1_plants(base, policy) ++ q3_plants(base, policy) ++ d1_plants(base, policy)
  end

  # MES-138 (authored 29691, ratified 29693): one plant per D1 refusal, on a
  # bucket-1-shaped row in an open section over the REAL bucket-1 view (its
  # first row, a client-leg member no committed record adjudicates), and a
  # D1 code planted on D4a's first row, outside a D1 view.
  def d1_plants(base, policy) do
    b1 = open_over(base, @v1, "MES-143", 1)
    [r1] = rows(b1, @v1, @w3)
    {:ok, loc} = A.read_locator(".")
    {token, [span | _]} = loc |> Enum.sort() |> Enum.find(fn {_, ss} -> ss != [] end)

    routed = fn to ->
      %{"to" => to, "owner" => "MES-152", "owner_record" => "control"}
    end

    redundant =
      Map.merge(r1, %{
        "disposition" => "redundant",
        "oc_counterpart" => %{
          "token" => token,
          "site" => %{"harness_sha256" => "control", "byte_span" => span, "bytes" => "control"},
          "why_a3_missed" => "control"
        },
        "routed_to" => routed.("A3")
      })

    as = fn r -> update_rows(b1, @v1, fn _ -> [r] end, @w3) end

    for {label, r} <- [
          {"redundant, its counterpart tied to #{token}", redundant},
          {"not_a_conformance_claim, routed to A2",
           Map.merge(r1, %{
             "disposition" => "not_a_conformance_claim",
             "routed_to" => routed.("A2")
           })},
          {"wrong_against_spec, with a 2026-07-28 URL and a quote",
           Map.merge(r1, %{
             "disposition" => "wrong_against_spec",
             "spec" => %{
               "url" => "https://modelcontextprotocol.io/specification/2026-07-28",
               "quote" => "control"
             }
           })}
        ] do
      ds = A.audit(as.(r), policy).defects

      check(
        "  (positive) a bucket-1 row, #{label}: CLEAN",
        ds == [],
        Enum.map(ds, &A.format_defect/1)
      )
    end

    [a | _] = rows(base, @v4a)

    [
      {:protects_missing, "bucket-1 row, genuine_extra_coverage, its `protects` removed",
       as.(Map.delete(r1, "protects")), policy},
      {:counterpart_missing, "bucket-1 row, redundant, its counterpart's site moved off #{token}",
       as.(put_in(redundant, ["oc_counterpart", "site", "byte_span"], [0, 1])), policy},
      {:routed_to_missing, "bucket-1 row, redundant, routed to A2 instead of A3",
       as.(Map.put(redundant, "routed_to", routed.("A2"))), policy},
      {:spec_citation_missing, "bucket-1 row, wrong_against_spec, with no `spec`",
       as.(Map.put(r1, "disposition", "wrong_against_spec")), policy},
      {:disposition_outside_view, "bucket-1 row carrying fix_sdk",
       as.(Map.put(r1, "disposition", "fix_sdk")), policy},
      {:disposition_outside_view,
       "D4a's first 4a row carrying genuine_extra_coverage (with protects)",
       update_rows(base, @v4a, fn [_ | rest] ->
         [
           Map.merge(a, %{"disposition" => "genuine_extra_coverage", "protects" => "control"})
           | rest
         ]
       end), policy}
    ]
  end

  # Q4: the first repository citation outside the sections of D4a (its
  # decision_row) and of D4b (its a3_ruling), shifted by one line.
  def q4_plants(base) do
    for record <- [@record, @d4b] do
      {:ok, doc} = base.records[record]

      [c | _] =
        doc |> Map.delete("sections") |> A.collect() |> Enum.filter(&Map.has_key?(&1, "lines"))

      at = {c["file"], c["lines"]}

      {"#{Path.basename(record)}'s top-level #{c["file"]}:#{inspect(c["lines"])} shifted by one line",
       map_citation(
         base,
         record,
         elem(at, 0),
         elem(at, 1),
         &Map.update!(&1, "lines", fn [a, b] -> [a + 1, b + 1] end)
       )}
    end
  end

  # Q3 (MES-135, 29451): recurring bytes need a verified occurrence.
  defp q3_plants(base, policy) do
    [
      {:citation_ambiguous,
       "D2b's capabilities_test.exs:64 citation (recurs at :8) with its occurrence removed",
       map_citation(
         base,
         @d2b,
         "test/mcp/protocol/capabilities_test.exs",
         [64, 64],
         &Map.delete(&1, "occurrence")
       ), policy},
      {:citation_ambiguous,
       "D4b's subscriptions_dispatch_test.exs:389 citation claiming occurrence 2 (it is 1)",
       map_citation(
         base,
         @d4b,
         "test/mcp/server/subscriptions_dispatch_test.exs",
         [389, 389],
         &Map.put(&1, "occurrence", 2)
       ), policy}
    ]
  end

  # Applies `fun` to the repository citation of `file` at `lines` inside `record`.
  defp map_citation(inputs, record, file, lines, fun) do
    update_in(inputs, [:records, record], fn {:ok, doc} ->
      {:ok, map_cites(doc, {file, lines}, fun)}
    end)
  end

  defp map_cites(%{"file" => f, "lines" => l, "bytes" => b} = c, {f, l}, fun) when is_binary(b),
    do: fun.(c)

  defp map_cites(m, at, fun) when is_map(m),
    do: Map.new(m, fn {k, v} -> {k, map_cites(v, at, fun)} end)

  defp map_cites(l, at, fun) when is_list(l), do: Enum.map(l, &map_cites(&1, at, fun))
  defp map_cites(x, _at, _fun), do: x

  # --- K1 (MES-135): content tied to the key, on the real records ------------------

  # CR 29672's plant: in D2a-ii's section, two bucket-2 rows exchange every
  # field except member, claim, tag and echo.
  # {inputs, {disposition_a, disposition_b}}: D4a's initialize row and D4b's
  # ping row on the same member test, each carrying the other's content.
  def k1r2_swap(base) do
    member =
      "MCP.Transport.StreamableHTTPStatelessTest/test initialize is gone → -32022; ping/logging.setLevel → -32601"

    nf = "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-"
    keep = ~w(member claim tag echo)

    find = fn file, tag ->
      {:ok, doc} = base.records[file]

      [r] =
        for s <- doc["sections"], r <- s["rows"], r["member"] == member, r["tag"] == tag, do: r

      r
    end

    a = find.(@record, nf <> "initialize/HttpServerMethodNotFound404initialize")
    b = find.(@d4b, nf <> "ping/HttpServerMethodNotFound404ping")
    swap = fn x, y -> Map.merge(y, Map.take(x, keep)) end

    put = fn inputs, file, from, to ->
      update_in(inputs, [:records, file], fn {:ok, doc} ->
        sections =
          Enum.map(doc["sections"], fn s ->
            %{s | "rows" => Enum.map(s["rows"], &if(&1 == from, do: to, else: &1))}
          end)

        {:ok, %{doc | "sections" => sections}}
      end)
    end

    {base |> put.(@record, a, swap.(a, b)) |> put.(@d4b, b, swap.(b, a)),
     {a["disposition"], b["disposition"]}}
  end

  def k1r_swap(base) do
    file = "docs/conformance/adjudications/adjudication-D2a-ii-2026-07-28.json"
    tags = ~w(oc:server/caching/wire-schema-valid/WireSchemaValid
              oc:server/tools-call-with-progress/wire-schema-valid/WireSchemaValid)
    keep = ~w(member claim tag echo)

    update_in(base, [:records, file], fn {:ok, doc} ->
      [section | rest] = doc["sections"]
      [a, b] = Enum.map(tags, fn t -> Enum.find(section["rows"], &(&1["tag"] == t)) end)
      swap = fn x, y -> Map.merge(y, Map.take(x, keep)) end

      rows =
        Enum.map(section["rows"], fn
          ^a -> swap.(a, b)
          ^b -> swap.(b, a)
          r -> r
        end)

      {:ok, %{doc | "sections" => [%{section | "rows" => rows} | rest]}}
    end)
  end

  # Edge A (4a's first row) keeps its key and echo; the rest is edge B's (the
  # first 4a row on another check).
  def w1(base) do
    [a | _] = rs = rows(base, @v4a)
    b = Enum.find(rs, &(&1["tag"] != a["tag"]))
    swapped = Map.merge(a, Map.take(b, ~w(et_test check root_cause disposition rationale)))
    update_rows(base, @v4a, fn [_ | rest] -> [swapped | rest] end)
  end

  def w5(base) do
    [a | rest] = rows(base, @v4a)
    update_rows(base, @v4a, fn _ -> [prose(a) | rest] end)
  end

  defp prose(%{"bytes" => b}) when is_binary(b), do: "prose: " <> String.slice(b, 0, 40)
  defp prose(m) when is_map(m), do: Map.new(m, fn {k, v} -> {k, prose(v)} end)
  defp prose(l) when is_list(l), do: Enum.map(l, &prose/1)
  defp prose(x), do: x

  defp k1_plants(base, policy) do
    [a | _] = rows(base, @v4a)
    r6 = Enum.find(rows(base, @v4a), &(get_in(&1, ["root_cause", "id"]) == "R6"))
    [prev, last] = rows(base, @v2a, @d2aii) |> Enum.take(-2)

    b5 = open_over(base, @v5a, "MES-148", 12)
    b1 = open_over(base, @v1, "MES-143", 1)
    [r5 | rest5] = rows(b5, @v5a, @w3)
    other5 = Enum.find(rest5, &(&1["tag"] != r5["tag"] and &1["et_test"] != r5["et_test"]))
    [r1] = rows(b1, @v1, @w3)

    check(
      "  (positive) twelve bucket-5a rows, tied, in an open section owned by MES-148: CLEAN",
      A.audit(b5, policy).defects == [],
      Enum.map(A.audit(b5, policy).defects, &A.format_defect/1)
    )

    check(
      "  (positive) a bucket-1 row, tied, in an open section owned by MES-143: CLEAN",
      A.audit(b1, policy).defects == [],
      Enum.map(A.audit(b1, policy).defects, &A.format_defect/1)
    )

    check(
      "  … a second 5a row on another check and another test is found: #{other5 && other5["tag"]}",
      other5 != nil
    )

    [
      {:root_cause_foreign, "W6: 4a's R6 root cause relabelled R1, stated_at unchanged",
       update_rows(
         base,
         @v4a,
         &Enum.map(&1, fn r ->
           if r == r6, do: put_in(r, ["root_cause", "id"], "R1"), else: r
         end)
       ), policy},
      {:check_foreign, "UNNAMED POSITION: D2a-ii's LAST row carries the row before it's check",
       update_rows(
         base,
         @v2a,
         &Enum.map(&1, fn r ->
           if r == last, do: Map.put(r, "check", prev["check"]), else: r
         end),
         @d2aii
       ), policy},
      {:check_foreign, "bucket-5a-shaped (edge-keyed) row whose check is another 5a check's site",
       update_rows(
         b5,
         @v5a,
         fn [_ | rest] -> [Map.put(r5, "check", other5["check"]) | rest] end,
         @w3
       ), policy},
      {:et_test_foreign, "bucket-5a-shaped (edge-keyed) row whose et_test is its sibling's test",
       update_rows(
         b5,
         @v5a,
         fn [_ | rest] -> [Map.put(r5, "et_test", other5["et_test"]) | rest] end,
         @w3
       ), policy},
      {:check_foreign, "bucket-1-shaped (oc:none/) row that cites a harness span under check",
       update_rows(
         b1,
         @v1,
         fn _ -> [put_in(r1, ["check", "predicate"], a["check"]["predicate"])] end,
         @w3
       ), policy},
      {:echo_drift, "bucket-1-shaped row whose view re-projects its cg under an unchanged key",
       update_view_row(b1, @v1, A.key(r1), &Map.put(&1, "cg", "CG-moved")), policy}
    ]
  end

  # An OPEN section, owned by the view's pending ticket, over the first `n` rows
  # of a real view, each row complete and tied: the member's own test line as
  # et_test, and (for an OC tag) the locator's first site as check.
  defp open_over(base, view, owner, n) do
    {:ok, v} = view |> File.read!() |> Jason.decode()

    record =
      {:ok,
       %{
         "schema" => A.schema(),
         "authored_by_hand" => true,
         "ticket" => owner,
         "sections" => [
           %{
             "view" => view,
             "closure" => "open",
             "owner" => owner,
             "rows" => tied_rows(Enum.take(v["rows"], n), view)
           }
         ]
       }}

    base |> add_record(@w3, record) |> put_in([:views, view], {:ok, v})
  end

  # Complete rows for real view rows, each tied (K1): the member's own test
  # line as et_test, and for an OC tag the locator's first site under check.
  # Over a D1 view the disposition is a D1 one, since MES-138 scopes the family
  # to the D1 views both ways (disposition_outside_view).
  defp tied_rows(view_rows, view \\ nil) do
    {:ok, loc} = A.read_locator(".")
    source_fun = A.load().source_fun
    index = test_line_index()

    for vr <- view_rows do
      member = vr["member"]["register_key"]

      check =
        case loc[vr["tag"]] do
          [span | _] ->
            %{
              "requires" => "control",
              "emitted_at" => %{
                "harness_sha256" => "control",
                "byte_span" => span,
                "bytes" => "control"
              }
            }

          nil ->
            %{"requires" => "control"}
        end

      %{
        "member" => member,
        "claim" => vr["claim"],
        "tag" => vr["tag"],
        "echo" => A.echo(vr),
        "et_test" => own_test_line(member, index, source_fun),
        "check" => check,
        "root_cause" => %{"statement" => "control"},
        "if_conformance_fixed" => [],
        "rationale" => "control"
      }
      |> Map.merge(
        if view in A.d1_views(),
          do: %{"disposition" => "genuine_extra_coverage", "protects" => "control"},
          else: %{"disposition" => "extend_test"}
      )
    end
  end

  # module => [candidate et_test citation], over every test file, read once.
  defp test_line_index do
    for file <- Path.wildcard("test/**/*_test.exs"),
        src = File.read!(file),
        [_, module] <- Regex.scan(~r/^defmodule (\S+) do/m, src),
        reduce: %{} do
      acc ->
        lines =
          for {l, i} <- src |> String.split("\n") |> Enum.with_index(1),
              l =~ ~r/^\s*test "/,
              do: %{"file" => file, "lines" => [i, i], "bytes" => l}

        Map.update(acc, module, lines, &(&1 ++ lines))
    end
  end

  # The member's own test line: the candidate in its module's file that G32's
  # own ownership check accepts.
  defp own_test_line(member, index, source_fun) do
    [module, _] = String.split(member, "/", parts: 2)

    index
    |> Map.get(module, [])
    |> Enum.find(&(A.et_test_owner(%{"member" => member, "et_test" => &1}, source_fun) == :ok))
    |> with_occurrence(source_fun)
  end

  # A test line that recurs in its file carries its measured occurrence, as a
  # committed record must (citation_ambiguous).
  defp with_occurrence(nil, _source_fun), do: nil

  defp with_occurrence(%{"lines" => [from, _]} = c, source_fun) do
    case A.occurrences(c, source_fun) do
      [_] -> c
      starts -> Map.put(c, "occurrence", Enum.find_index(starts, &(&1 == from)) + 1)
    end
  end

  # --- mutation --------------------------------------------------------------------

  def mutation do
    header("mutation — the guard recompiled in this VM")
    src = File.read!(@source)

    # D4b's section on bucket-4b is removed in memory, and the control shows
    # that without the removal the plant is refused as duplicate: it is the
    # removal, not the key, that the unmodified plant would trip on.
    unremoved = A.load() |> bind_complete(@v4b) |> bind_complete(@v5a)

    # bucket-5a is pending on MES-148 (MES-135): a closed synthetic section over
    # it is the state MES-148 lands in, with its @pending line deleted.
    key_policy = %{A.policy() | pending: Map.delete(A.pending(), @v5a)}

    check(
      "(1) without removing D4b's section, the synthetic 4b section is a duplicate (and a second closure)",
      A.audit(unremoved, key_policy).defects |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort() ==
        [:closure_not_exclusive, :duplicate],
      A.audit(unremoved, key_policy).defects
      |> Enum.map(&A.format_defect/1)
      |> Enum.reject(&(&1 =~ ~r/G32 (duplicate|closure_not_exclusive)/))
    )

    real =
      A.load()
      |> update_in([:records, @d4b], fn {:ok, r} ->
        {:ok, Map.update!(r, "sections", &Enum.reject(&1, fn s -> s["view"] == @v4b end))}
      end)
      |> bind_complete(@v4b)
      |> bind_complete(@v5a)

    %{defects: ds, report: r} = A.audit(real, key_policy)

    check(
      "(1) the real guard keys the real 4b and 5a views: clean over #{r["rows_visited"]} rows",
      ds == [],
      Enum.map(ds, &A.format_defect/1)
    )

    key_def =
      ~s|def key(row) when is_map(row), do: [member_key(row["member"]), row["claim"], row["tag"]]|

    for {label, cut, refused, admitted} <- [
          {"member alone", ~s|def key(row) when is_map(row), do: [member_key(row["member"])]|,
           @v4b, nil},
          {"[member, tag]",
           ~s|def key(row) when is_map(row), do: [member_key(row["member"]), row["tag"]]|, @v5a,
           @v4b}
        ] do
      mutant = String.replace(src, key_def, cut)
      check("(1) the #{label} mutant differs from the source", mutant != src)

      with_module(mutant, fn ->
        %{defects: ds} = A.audit(real, key_policy)

        collided =
          for %{kind: :view_key_collision, detail: det} <- ds,
              v <- [@v4b, @v5a],
              String.starts_with?(det, v),
              uniq: true,
              do: v

        check(
          "(1) keyed on #{label}, #{Path.basename(refused)} is refused (view_key_collision)",
          refused in collided,
          Enum.map(ds, &A.format_defect/1)
        )

        if admitted,
          do:
            check(
              "(1) … while #{Path.basename(admitted)} still keys, so the refusal is the claim's",
              admitted not in collided
            )
      end)
    end

    narrowed = String.replace(src, ~s|@walk_glob "*.json"|, ~s|@walk_glob "*.jsn"|)
    check("(2) the narrowed-walk mutant differs from the source", narrowed != src)

    with_module(narrowed, fn ->
      %{report: r, defects: ds} = A.audit(A.load())

      # Before MES-135 this audited CLEAN over zero records, the silent pass the
      # gate-5 walk-root pin existed to catch. The universe (K2) now refuses it
      # itself: every view the unseen records closed is owed and unadjudicated.
      check(
        "(2) a narrowed walk sees zero records and is REFUSED: owed_unadjudicated on the 6 closed views",
        r["records_visited"] == 0 and
          Enum.sort(for(%{kind: :owed_unadjudicated, file: f} <- ds, do: f)) ==
            Enum.sort([@v2a, @v2b, @v4a, @v4b, @vcu, @ves]) and
          Enum.all?(ds, &(&1.kind == :owed_unadjudicated)),
        Enum.map(ds, &A.format_defect/1)
      )

      check(
        "(2) … and the gate-5 pin on walk_root/0, now a backstop, refuses it too",
        A.walk_root() != {"docs/conformance/adjudications", "*.json"}
      )
    end)

    base = A.load()
    d4b_rows = rows(base, @v4b, @d4b)

    all_rows =
      d4b_rows ++
        rows(base, @v2b, @d2b) ++
        rows(base, @v2a, @d2ai) ++
        rows(base, @v2a, @d2aii) ++ rows(base, @v1, @d1) ++ rows(base, @vcu, @d1)

    set_def =
      ~s|suite_defect_upstream extend_test accept_bound\n                   extend_to_match build_test blocked_on_sdk_gap\n                   genuine_extra_coverage redundant not_a_conformance_claim wrong_against_spec)|

    check("(3) the closed-set definition is found in the source", String.contains?(src, set_def))

    # MES-138's D1 codes on its committed rows. `redundant` and
    # `wrong_against_spec` are in the set but no committed row carries either
    # (no redundant row was found, and under the N5 ruling no row asserts what
    # the spec forbids or contradicts), so neither has rows to refuse; their
    # admission is shown by d1_plants' positive controls instead ("redundant,
    # its counterpart tied to ..." and "wrong_against_spec, with a 2026-07-28
    # URL and a quote").
    for code <-
          ~w(extend_test accept_bound extend_to_match build_test blocked_on_sdk_gap genuine_extra_coverage not_a_conformance_claim) do
      cut = String.replace(set_def, ~r/(?<=\s)#{code}(?=[\s)])\s?/, "")
      mutant = String.replace(src, set_def, cut)
      check("(3) the no-#{code} mutant differs from the source", mutant != src)

      with_module(mutant, fn ->
        %{defects: ds} = A.audit(base)

        expected =
          for r <- all_rows, r["disposition"] == code, do: {:disposition_outside_set, A.key(r)}

        check(
          "(3) without #{code}, exactly its #{length(expected)} rows are refused as disposition_outside_set",
          expected != [] and Enum.sort(for(d <- ds, do: {d.kind, d.key})) == Enum.sort(expected),
          Enum.map(ds, &A.format_defect/1)
        )
      end)
    end

    bounded = Enum.find(d4b_rows, &(&1["disposition"] == "accept_bound"))
    call = "      bound_defects(section.file, k, row) ++\n"
    unbound = String.replace(src, call, "")
    check("(4) the no-bound-check mutant differs from the source", unbound != src)

    with_module(unbound, fn ->
      check(
        "(4) with the bound check cut, the missing-bound plant audits CLEAN — the refusal is the check's",
        A.audit(drop_bound(base, bounded)).defects == []
      )
    end)

    levelled = Enum.find(rows(base, @v2b, @d2b), &(&1["disposition"] == "build_test"))
    call = "      build_defects(section.file, k, row) ++\n"
    unlevelled = String.replace(src, call, "")
    check("(5) the no-build-check mutant differs from the source", unlevelled != src)

    with_module(unlevelled, fn ->
      check(
        "(5) with the build check cut, the missing-level plant audits CLEAN — the refusal is the check's",
        A.audit(drop_field(base, levelled, "build_level")).defects == []
      )
    end)

    gapped = Enum.find(rows(base, @v2a, @d2ai), &(&1["disposition"] == "blocked_on_sdk_gap"))
    call = "      sdk_gap_defects(section.file, k, row) ++\n"
    ungapped = String.replace(src, call, "")
    check("(6) the no-sdk_gap-check mutant differs from the source", ungapped != src)

    with_module(ungapped, fn ->
      check(
        "(6) with the sdk_gap check cut, the missing-gap plant audits CLEAN — the refusal is the check's",
        A.audit(drop_field(base, gapped, "sdk_gap", @v2a, @d2ai)).defects == []
      )
    end)

    call = "    closure_not_exclusive(view, closed) ++ phantom ++"
    unexclusive = String.replace(src, call, "    phantom ++")
    check("(7) the no-closure_not_exclusive mutant differs from the source", unexclusive != src)

    with_module(unexclusive, fn ->
      check(
        "(7) with closure_not_exclusive cut, W3 (4a split over two closed sections) audits CLEAN — the refusal is the check's",
        A.audit(split_closed(base, @v4a, @record, 2)).defects == []
      )
    end)

    # (8) MES-135's universe clauses: each neutralised alone, its plant passes.
    clauses = %{
      owed_unadjudicated: "owed_defects",
      pending_but_closed: "pending_closed_defects",
      catalogue_names_absent_view: "catalogue_defects",
      bound_to_excluded: "excluded_defects",
      bound_outside_anchor: "outside_anchor_defects",
      owner_mismatch: "owner_defects",
      empty_closure_unwarranted: "empty_closure_defects",
      record_outside_walk: "outside_defects",
      stray_in_walk_root: "stray_defects",
      et_test_foreign: "et_test_defects",
      check_foreign: "check_defects",
      root_cause_foreign: "root_cause_defects",
      echo_drift: "echo_defects",
      citation_ambiguous: "ambiguous_defects",
      disposition_outside_view: "view_scope_defects",
      protects_missing: "protects_defects",
      counterpart_missing: "counterpart_defects",
      routed_to_missing: "routed_to_defects",
      spec_citation_missing: "spec_defects"
    }

    for {kind, label, inputs, policy} <- plants(base) do
      fun = Map.fetch!(clauses, kind)
      mutant = neutralise(src, [fun])
      check("(8) the no-#{fun} mutant differs from the source", mutant != src)

      with_module(mutant, fn ->
        %{defects: ds} = A.audit(inputs, policy)

        check(
          "(8) with #{kind} neutralised, \"#{label}\" audits CLEAN — the refusal is the clause's",
          ds == [],
          Enum.map(ds, &A.format_defect/1)
        )
      end)
    end

    # (10) Q4: with the walk narrowed back to rows, the top-level plants pass.
    rows_only = String.replace(src, "c <- collect(outside_rows(doc))", "c <- []")
    check("(10) the rows-only-walk mutant differs from the source", rows_only != src)

    with_module(rows_only, fn ->
      for {label, inputs} <- q4_plants(base) do
        check(
          "(10) with the walk narrowed to rows, \"#{label}\" audits CLEAN",
          A.audit(inputs).defects == []
        )
      end
    end)

    # (9) W1 and W5 on the member row are refused by more than one tie: each tie
    # alone still refuses, and only with every named tie neutralised do they
    # pass. On the 482 pairs the K1-R/K1-R2 predicate admits (481 at MES-135), a W1-shaped
    # exchange passes with nothing neutralised.
    for {label, inputs, funs} <- [
          {"W1", w1(base), ~w(et_test_defects check_defects)},
          {"W5", w5(base), ~w(et_test_defects check_defects root_cause_defects)}
        ] do
      for f <- funs do
        with_module(neutralise(src, [f]), fn ->
          check(
            "(9) #{label} with only #{f} neutralised is still refused",
            A.audit(inputs).defects != []
          )
        end)
      end

      with_module(neutralise(src, funs), fn ->
        ds = A.audit(inputs).defects

        check(
          "(9) #{label} with #{Enum.join(funs, " + ")} neutralised audits CLEAN",
          ds == [],
          Enum.map(ds, &A.format_defect/1)
        )
      end)
    end

    %{defects: ds} = A.audit(A.load())
    check("restored: the real guard is back and the tree is clean", ds == [])
  end

  # Each named clause answers []: a catch-all first clause of the same arity is
  # inserted before the function's first clause, which it then shadows.
  defp neutralise(src, funs) do
    Enum.reduce(funs, src, fn fun, acc ->
      stub = "  defp #{fun}(#{List.duplicate("_", @arity[fun]) |> Enum.join(", ")}), do: []\n\n"
      String.replace(acc, "\n  defp #{fun}(", "\n" <> stub <> "  defp #{fun}(", global: false)
    end)
  end

  defp with_module(source, fun) do
    Code.compiler_options(ignore_module_conflict: true)
    # A shadowed clause warns; the warning is the mutation, not news.
    Code.with_diagnostics(fn -> Code.compile_string(source, @source) end)
    fun.()
  after
    Code.compile_string(File.read!(@source), @source)
  end

  # --- swap-audit (MES-138, R3-1; adapted from CR's /tmp/cr135sweep/sweep.exs) -----
  #
  # The AUDITED set of row pairs whose contents (every field but member, claim,
  # tag and echo) exchange and still audit CLEAN, over EVERY pair of committed
  # rows, each exchange run through A.audit. Gate 5's K1-R/K1-R2 unit pins the
  # set by equality to @k1r_clean_cliques; this mode is where that fixture comes
  # from, never from the unit's own computed set, which would make the pin a
  # tautology. It prints the cliques as the literal to paste, and the
  # difference both ways against the fixture as committed.
  @k1r_test "test/conformance/adjudications_test.exs"
  @k1r_keep ~w(member claim tag echo)

  def swap_audit do
    header("swap-audit — every pair of committed rows, contents exchanged, through A.audit")
    base = A.load()
    check("the committed tree is clean before any exchange", A.audit(base).defects == [])

    rows =
      for {file, {:ok, doc}} <- Enum.sort(base.records),
          {s, si} <- Enum.with_index(doc["sections"]),
          {r, ri} <- Enum.with_index(s["rows"]),
          do: %{
            file: file,
            si: si,
            ri: ri,
            row: r,
            id: {Path.basename(file), r["member"], r["tag"]}
          }

    ids = Enum.map(rows, & &1.id)

    check(
      "#{length(rows)} rows, each with a unique stable id",
      length(Enum.uniq(ids)) == length(ids)
    )

    put = fn inputs, %{file: f, si: si, ri: ri}, new ->
      update_in(inputs, [:records, f], fn {:ok, doc} ->
        {:ok, put_in(doc, ["sections", Access.at(si), "rows", Access.at(ri)], new)}
      end)
    end

    swap = fn x, y -> Map.merge(y, Map.take(x, @k1r_keep)) end
    indexed = Enum.with_index(rows)
    pairs = for {x, i} <- indexed, {y, j} <- indexed, i < j, do: {x, y}

    results =
      pairs
      |> Task.async_stream(
        fn {x, y} ->
          {nx, ny} = {swap.(x.row, y.row), swap.(y.row, x.row)}
          noop = nx == x.row and ny == y.row
          {x.id, y.id, noop, A.audit(base |> put.(x, nx) |> put.(y, ny)).defects == []}
        end,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn {:ok, r} -> r end)

    noops = for {i, j, true, _} <- results, do: {i, j}

    check(
      "#{length(results)} pairs exchanged, 0 of them no-ops",
      noops == [],
      Enum.map(noops, &inspect/1)
    )

    clean = for {i, j, _, true} <- results, into: MapSet.new(), do: MapSet.new([i, j])
    cliques = cliques(clean)

    check(
      "the CLEAN set is a union of cliques: every pair within each component is CLEAN",
      Enum.all?(cliques, fn c ->
        for(i <- c, j <- c, i < j, do: MapSet.new([i, j])) |> Enum.all?(&(&1 in clean))
      end)
    )

    IO.puts(
      "        CLEAN pairs: #{MapSet.size(clean)}; cliques by size: #{inspect(Enum.map(cliques, &length/1))}"
    )

    fixture = k1r_fixture()
    missing = MapSet.difference(clean, fixture)
    extra = MapSet.difference(fixture, clean)

    IO.puts(
      "        audited − fixture (#{MapSet.size(missing)}): #{inspect(MapSet.to_list(missing), limit: :infinity)}"
    )

    IO.puts(
      "        fixture − audited (#{MapSet.size(extra)}): #{inspect(MapSet.to_list(extra), limit: :infinity)}"
    )

    IO.puts("\n        -- the audited cliques, as the fixture literal --")

    IO.puts(
      inspect(cliques, limit: :infinity, printable_limit: :infinity, pretty: true, width: 98)
    )

    check(
      "the committed fixture @k1r_clean_cliques EQUALS the audited set",
      MapSet.size(missing) == 0 and MapSet.size(extra) == 0
    )
  end

  # Connected components of the CLEAN graph, each sorted; sorted by size, then id.
  defp cliques(pairs) do
    edges = Enum.map(pairs, &MapSet.to_list/1)
    nodes = edges |> List.flatten() |> Enum.uniq()

    adj =
      Enum.reduce(edges, %{}, fn [a, b], acc ->
        acc |> Map.update(a, [b], &[b | &1]) |> Map.update(b, [a], &[a | &1])
      end)

    {comps, _} =
      Enum.reduce(Enum.sort(nodes), {[], MapSet.new()}, fn n, {acc, seen} ->
        if n in seen do
          {acc, seen}
        else
          comp = reach([n], adj, MapSet.new([n]))
          {[Enum.sort(MapSet.to_list(comp)) | acc], MapSet.union(seen, comp)}
        end
      end)

    Enum.sort_by(comps, &{-length(&1), &1})
  end

  defp reach([], _adj, seen), do: seen

  defp reach([n | rest], adj, seen) do
    new = Enum.reject(Map.get(adj, n, []), &(&1 in seen))
    reach(new ++ rest, adj, Enum.reduce(new, seen, &MapSet.put(&2, &1)))
  end

  # The fixture as COMMITTED in the gate-5 test, read out of its source: the
  # three attributes it is written with, evaluated, and expanded to pairs.
  defp k1r_fixture do
    src = File.read!(@k1r_test)

    attrs =
      for name <- ~w(k1r_stateless k1r_dispatch k1r_clean_cliques) do
        [_, body] = Regex.run(~r/^  @#{name} (.*?)\n(?=  @|\n)/ms, src)
        "#{name} = " <> String.replace(body, "@k1r_", "k1r_")
      end

    {cliques, _} = Code.eval_string(Enum.join(attrs, "\n") <> "\nk1r_clean_cliques")
    for c <- cliques, i <- c, j <- c, i < j, into: MapSet.new(), do: MapSet.new([i, j])
  end

  # --- harness -----------------------------------------------------------------------

  def harness do
    header("harness — every harness citation against the pinned build")
    dist = System.get_env("MES_HARNESS_DIST", @default_dist)
    records = A.load().records

    check(
      "every record is read: #{inspect(Map.keys(records))}",
      @record in Map.keys(records) and @d4b in Map.keys(records) and
        @d2b in Map.keys(records) and @d2ai in Map.keys(records) and @d2aii in Map.keys(records)
    )

    cites =
      for {_, {:ok, record}} <- records,
          c <- A.collect(record),
          Map.has_key?(c, "harness_sha256"),
          do: c

    # Every record the walk finds, not a hand-held list (MES-135 N3).
    for f <- A.load().walk do
      {:ok, rec} = records[f]
      n = rec |> A.collect() |> Enum.count(&Map.has_key?(&1, "harness_sha256"))
      check("  … #{Path.basename(f)} carries #{n} harness citations", n > 0)
    end

    shas = cites |> Enum.map(& &1["harness_sha256"]) |> Enum.uniq()

    case File.read(dist) do
      {:ok, bin} ->
        sha = :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)

        check("the build at #{dist} is the pinned one (#{sha})", shas == [sha], [
          "record names #{inspect(shas)}"
        ])

        check(
          "#{length(cites)} harness citations, each span holding its bytes",
          cites != [] and mismatched(bin, cites) == [],
          mismatched(bin, cites)
        )

        [first | rest] = cites
        planted = [Map.update!(first, "bytes", &(&1 <> " ")) | rest]

        check(
          "negative: one citation with one byte appended is caught",
          mismatched(bin, planted) == [
            "#{Enum.at(first["byte_span"], 0)}..#{Enum.at(first["byte_span"], 1)}"
          ]
        )

      {:error, why} ->
        check(
          "the pinned build is readable at #{dist} (#{inspect(why)}) — FAILS CLOSED, set MES_HARNESS_DIST",
          false
        )
    end
  end

  defp mismatched(bin, cites) do
    for %{"byte_span" => [s, e], "bytes" => b} <- cites,
        binary_part(bin, s, e - s) != b,
        do: "#{s}..#{e}"
  end

  # --- plumbing ------------------------------------------------------------------------

  defp rows(inputs, view, record \\ @record) do
    {:ok, r} = inputs.records[record]
    r["sections"] |> Enum.find(&(&1["view"] == view)) |> Map.fetch!("rows")
  end

  defp update_section(inputs, view, fun, record \\ @record) do
    update_in(inputs, [:records, record], fn {:ok, r} ->
      {:ok,
       Map.update!(
         r,
         "sections",
         &Enum.map(&1, fn s -> if s["view"] == view, do: fun.(s), else: s end)
       )}
    end)
  end

  defp update_rows(inputs, view, fun, record \\ @record),
    do: update_section(inputs, view, &Map.update!(&1, "rows", fun), record)

  defp drop_bound(inputs, row) do
    update_rows(
      inputs,
      @v4b,
      &Enum.map(&1, fn r -> if r == row, do: Map.delete(r, "bound"), else: r end),
      @d4b
    )
  end

  defp drop_field(inputs, row, field, view \\ @v2b, record \\ @d2b) do
    update_rows(
      inputs,
      view,
      &Enum.map(&1, fn r -> if r == row, do: Map.delete(r, field), else: r end),
      record
    )
  end

  # The view rows a record's selector admits (MES-129: the tag segment's prefix).
  defp selected(view_rows, %{"field" => f, "segment" => i, "starts_with" => p}) do
    Enum.filter(view_rows, fn r ->
      r[f] |> String.split("/") |> Enum.at(i) |> Kernel.||("") |> String.starts_with?(p)
    end)
  end

  # {section keys the selector does not admit, admitted keys the section lacks}.
  defp selector_diff(inputs, view_rows) do
    {:ok, rec} = inputs.records[@d2ai]
    got = rows(inputs, @v2a, @d2ai) |> Enum.map(&A.key/1) |> Enum.sort()
    want = view_rows |> selected(rec["selector"]) |> Enum.map(&A.key/1) |> Enum.sort()
    {got -- want, want -- got}
  end

  # Moves all but the first `keep` rows of `record`'s section on `view` into a
  # new record, @w3, whose section on the same view has `closure`.
  defp split_closed(inputs, view, record, keep, closure \\ "closed") do
    moved = rows(inputs, view, record) |> Enum.drop(keep)

    section =
      %{"view" => view, "closure" => closure, "rows" => moved}
      |> then(&if closure == "open", do: Map.put(&1, "owner", "MES-126"), else: &1)

    inputs
    |> update_rows(view, &Enum.take(&1, keep), record)
    |> Map.update!(:walk, &Enum.sort([@w3 | &1]))
    |> put_in(
      [:records, @w3],
      {:ok, %{"schema" => A.schema(), "authored_by_hand" => true, "sections" => [section]}}
    )
  end

  defp add_record(inputs, file, record) do
    inputs
    |> Map.update!(:walk, &Enum.sort([file | &1]))
    |> put_in([:records, file], record)
  end

  # A copy of the adjudications and buckets directories, the locator and the
  # .gitignore, OUTSIDE the clone (seats share one checkout), loaded with the
  # real source reader.
  defp tree_copy do
    tmp = Path.join(System.tmp_dir!(), "mes135-g32-ctl-#{System.unique_integer([:positive])}")

    for d <- ["docs/conformance/adjudications", "docs/conformance/buckets"] do
      File.mkdir_p!(Path.join(tmp, d))
      File.cp_r!(d, Path.join(tmp, d))
    end

    File.cp!(A.locator_path(), Path.join(tmp, A.locator_path()))
    # A git work tree of its own (MES-135 B1): the outside-the-walk scan lists
    # the files git would commit, and refuses a root git cannot list.
    File.cp!(".gitignore", Path.join(tmp, ".gitignore"))
    {_, 0} = System.cmd("git", ["init", "-q", tmp])
    tmp
  end

  # Loads a FRESH copy of `tmp`, with `plant` applied to it, then removes it.
  defp tree_load(tmp, plant) do
    root = tmp <> "-#{System.unique_integer([:positive])}"
    File.cp_r!(tmp, root)
    plant.(root)
    inputs = %{A.load(root: root) | source_fun: A.load().source_fun}
    File.rm_rf!(root)
    inputs
  end

  defp drop_record(inputs, record) do
    %{inputs | walk: inputs.walk -- [record], records: Map.delete(inputs.records, record)}
  end

  defp update_view_row(inputs, view, key, fun) do
    update_in(inputs, [:views, view], fn {:ok, v} ->
      {:ok,
       Map.update!(v, "rows", &Enum.map(&1, fn r -> if A.key(r) == key, do: fun.(r), else: r end))}
    end)
  end

  defp bind(inputs, view) do
    {:ok, v} = File.read!(view) |> Jason.decode() |> then(&{:ok, elem(&1, 1)})

    inputs
    |> update_in([:records, @record], fn {:ok, r} ->
      {:ok,
       Map.update!(
         r,
         "sections",
         &(&1 ++ [%{"view" => view, "closure" => "closed", "rows" => []}])
       )}
    end)
    |> put_in([:views, view], {:ok, v})
  end

  # A complete closed section over `view`, built from the view's own rows: every
  # required field present and every K1 tie held, so only the KEY can refuse it.
  defp bind_complete(inputs, view) do
    {:ok, v} = view |> File.read!() |> Jason.decode()
    rows = tied_rows(v["rows"])

    inputs
    |> update_in([:records, @record], fn {:ok, r} ->
      {:ok,
       Map.update!(
         r,
         "sections",
         &(&1 ++ [%{"view" => view, "closure" => "closed", "rows" => rows}])
       )}
    end)
    |> put_in([:views, view], {:ok, v})
  end

  defp expect(label, kinds, key, inputs) do
    %{defects: ds} = A.audit(inputs)
    lines = Enum.map(ds, &A.format_defect/1)
    check(label, Enum.map(ds, & &1.kind) == kinds and Enum.all?(ds, &(&1.key == key)), lines)
    named(lines)
  end

  defp expect_kinds(label, kinds, inputs) do
    %{defects: ds} = A.audit(inputs)
    lines = Enum.map(ds, &A.format_defect/1)

    check(
      label,
      ds |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort() == Enum.sort(kinds),
      lines
    )

    named(lines)
  end

  defp named(lines) do
    for l <- lines do
      check("  … names G32: #{String.slice(l, 0, 150)}", String.starts_with?(l, "G32 "))
    end
  end

  defp check(label, ok?, detail \\ []) do
    if ok? do
      IO.puts("  ok    #{label}")
    else
      IO.puts("  FAIL  #{label}")
      for l <- Enum.take(detail, 10), do: IO.puts("        #{l}")
      System.halt(1)
    end
  end

  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

AdjudicationsControls.run(System.argv())
