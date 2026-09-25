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
# `harness` verifies every harness citation in EVERY record against the pinned
# conformance build: sha256 first, then each byte span. Gate 5 cannot do this,
# because the build is not in this repository. It FAILS CLOSED when the build
# is absent or its sha differs. Set MES_HARNESS_DIST to point at it; the default
# is where the accepted runs installed it.
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
  @source "conformance/lib/mcp/conformance/adjudications.ex"
  @default_dist "/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js"
  @tcg1c_ascii "a non-ASCII tool name rides `mcp-name` as the Base64 sentinel and decodes back to the body value"
  @tcg1c_crlf "a CRLF-bearing tool name is neutralised — it rides `mcp-name` encoded, carries no raw CR, and injects no header"

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
      "usage: mix run #{__ENV__.file |> Path.relative_to_cwd()} positive|refusals|mutation|harness|all"
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

    expect(
      "(b) phantom: a row keyed to an edge the view does not project",
      [:phantom],
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

    expect(
      "open_without_owner",
      [:open_without_owner],
      nil,
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
      [:phantom],
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
      [:phantom],
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
      "(D2a-i) a real 2a row from OUTSIDE the slice: duplicate, D2a-ii adjudicates it",
      [:duplicate],
      A.key(foreign),
      planted
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

    check(
      "  … and with D2a-ii's section removed, G32 admits both again: the refusals are the closure's",
      A.audit(drop_record(planted, @d2aii)).defects == [] and
        A.audit(drop_record(dropped, @d2aii)).defects == []
    )

    # --- D2a-ii's record: a CLOSED section on bucket-2a ---
    d2aii = rows(base, @v2a, @d2aii)
    first_ii = hd(d2aii)

    phantom_ii =
      Map.put(first_ii, "tag", "oc:server/server-stateless/no-such-check/NoSuchCheck")

    expect(
      "(D2a-ii) phantom: a row keyed to a check bucket-2a does not project",
      [:phantom],
      A.key(phantom_ii),
      update_rows(base, @v2a, &(&1 ++ [phantom_ii]), @d2aii)
    )

    expect(
      "(D2a-ii) a GAP, one view row in neither slice: missing",
      [:missing],
      A.key(first_ii),
      update_rows(base, @v2a, &tl/1, @d2aii)
    )

    expect(
      "(D2a-ii) an OVERLAP, one D2a-ii row planted into D2a-i too: duplicate",
      [:duplicate],
      A.key(first_ii),
      update_rows(base, @v2a, &(&1 ++ [first_ii]), @d2ai)
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
      "view_key_collision: bucket-0 cannot be keyed by the triple",
      [:view_key_collision],
      bound0
    )
  end

  # --- mutation --------------------------------------------------------------------

  def mutation do
    header("mutation — the guard recompiled in this VM")
    src = File.read!(@source)

    # D4b's section on bucket-4b is removed in memory, and the control shows
    # that without the removal the plant is refused as duplicate: it is the
    # removal, not the key, that the unmodified plant would trip on.
    unremoved = A.load() |> bind_complete(@v4b) |> bind_complete(@v5a)

    check(
      "(1) without removing D4b's section, the synthetic 4b section is a duplicate",
      A.audit(unremoved).defects |> Enum.map(& &1.kind) |> Enum.uniq() == [:duplicate]
    )

    real =
      A.load()
      |> update_in([:records, @d4b], fn {:ok, r} ->
        {:ok, Map.update!(r, "sections", &Enum.reject(&1, fn s -> s["view"] == @v4b end))}
      end)
      |> bind_complete(@v4b)
      |> bind_complete(@v5a)

    %{defects: ds, report: r} = A.audit(real)

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
        %{defects: ds} = A.audit(real)

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

      check(
        "(2) a narrowed walk audits CLEAN over zero records — the silent pass",
        ds == [] and r["records_visited"] == 0
      )

      check(
        "(2) … and the gate-5 pin refuses it",
        A.walk_root() != {"docs/conformance/adjudications", "*.json"}
      )
    end)

    base = A.load()
    d4b_rows = rows(base, @v4b, @d4b)

    all_rows =
      d4b_rows ++ rows(base, @v2b, @d2b) ++ rows(base, @v2a, @d2ai) ++ rows(base, @v2a, @d2aii)

    set_def =
      ~s|suite_defect_upstream extend_test accept_bound\n                   extend_to_match build_test blocked_on_sdk_gap)|

    check("(3) the closed-set definition is found in the source", String.contains?(src, set_def))

    for code <- ~w(extend_test accept_bound extend_to_match build_test blocked_on_sdk_gap) do
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

    %{defects: ds} = A.audit(A.load())
    check("restored: the real guard is back and the tree is clean", ds == [])
  end

  defp with_module(source, fun) do
    Code.compiler_options(ignore_module_conflict: true)
    Code.compile_string(source, @source)
    fun.()
  after
    Code.compile_string(File.read!(@source), @source)
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

    for f <- [@record, @d4b, @d2b, @d2ai, @d2aii] do
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

  # A complete, citation-free closed section over `view`, built from the view's
  # own rows: every required field present, so only the KEY can refuse it.
  defp bind_complete(inputs, view) do
    {:ok, v} = view |> File.read!() |> Jason.decode()

    rows =
      for vr <- v["rows"] do
        %{
          "member" => get_in(vr, ["member", "register_key"]),
          "claim" => vr["claim"],
          "tag" => vr["tag"],
          "echo" => A.echo(vr),
          "et_test" => %{},
          "check" => %{},
          "root_cause" => %{},
          "if_conformance_fixed" => [],
          "disposition" => "fix_sdk",
          "rationale" => "control"
        }
      end

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
