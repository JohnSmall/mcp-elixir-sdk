# Controls for C1a's two instruments — the locator and the crosswalk (MES-97).
#
#     mix run conformance/controls/crosswalk_controls.exs noop
#     mix run conformance/controls/crosswalk_controls.exs keying
#     mix run conformance/controls/crosswalk_controls.exs locator
#     mix run conformance/controls/crosswalk_controls.exs pins
#     mix run conformance/controls/crosswalk_controls.exs guards
#     mix run conformance/controls/crosswalk_controls.exs vacuum
#     mix run conformance/controls/crosswalk_controls.exs all
#
# ORDER IS PART OF THE DESIGN. `noop` runs FIRST and on its own, because a
# regeneration diff means nothing until an unchanged regeneration is known to
# produce an identical file (S8-4). Everything after it rests on that.
#
# WHY A SCRIPT AND NOT AN ExUnit TEST — the same reason B2a and B2b give: these
# mutate authored source files and re-run whole builds, and a file under
# `test/` would move the very unit population MES-88's boundary sweep measures.
# The DECISION LOGIC is unit-tested in `test/conformance/crosswalk_test.exs` and
# `test/conformance/locator_test.exs`, so gate 5 covers it; what lives here is
# the part that needs a mutated tree.
#
# EACH GUARD GETS A POSITIVE CONTROL AND A MUTATION. The positive control shows
# the sweep reached the population at all; only the mutation shows the predicate
# CAN fire. A guard that has never been seen to fire is a promise.

defmodule CrosswalkControls do
  alias MCP.Conformance.{Crosswalk, Locator, MatchKey}

  @harness "/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js"

  @edges "conformance/data/crosswalk-edges.json"
  @c1_axes "conformance/data/oc-axes-c1.json"
  @a3_axes "docs/conformance/oc-axes-2026-07-28.json"
  @manifest "docs/conformance/in-scope-2026-07-28.json"
  @denominator "docs/conformance/bucket-0-2026-07-28.json"
  @register "docs/conformance/etcc-register.json"
  @attribution "docs/conformance/etcc-attribution.json"
  @crosswalk_out "docs/conformance/crosswalk-2026-07-28.json"
  @locator_out "docs/conformance/oc-emitting-sites-2026-07-28.json"

  def run(["noop"]), do: noop()
  def run(["keying"]), do: keying()
  def run(["locator"]), do: locator()
  def run(["pins"]), do: pins()
  def run(["guards"]), do: guards()
  def run(["vacuum"]), do: vacuum()

  def run(["all"]) do
    noop()
    keying()
    locator()
    pins()
    guards()
    vacuum()
  end

  def run(_) do
    IO.puts("usage: noop | keying | locator | pins | guards | vacuum | all")
    System.halt(2)
  end

  # --- noop: the control that makes every later diff mean something (S8-4) ---

  defp noop do
    header("NO-OP REGENERATION — unchanged inputs must produce a BYTE-IDENTICAL file")

    require_harness!()

    for {label, committed, regen} <- [
          {"locator", @locator_out, fn out -> run_locator(out) end},
          {"crosswalk", @crosswalk_out, fn out -> run_crosswalk(out) end}
        ] do
      out = tmp("#{label}-noop")
      regen.(out)
      a = File.read!(committed)
      b = File.read!(out)
      File.rm(out)

      if a == b do
        IO.puts("  identical  #{label}  md5 #{md5(a)}  (#{byte_size(a)} bytes)")
      else
        IO.puts("  DIFFERS    #{label}  committed #{md5(a)} vs regenerated #{md5(b)}")
        IO.puts("             The committed artefact is not what its own generator produces.")
        System.halt(1)
      end
    end

    IO.puts("""

      Without this, a later diff could be read either way — as a real change or as
      generator nondeterminism. With it, a diff is a change.
    """)
  end

  # --- keying: BOTH directions, measured on the real 173 ---------------------

  defp keying do
    header("KEYING — the obvious fields MERGE rows; A1's six-field key merges none")

    rows =
      @denominator
      |> read()
      |> Map.fetch!("checks")
      |> Enum.filter(& &1["matchable"])
      |> Enum.map(& &1["key"])

    k = Crosswalk.keying_control(rows)

    IO.puts(
      "  population: the #{k["rows"]} in-denominator rows.  Measure: ROWS LOST (A1's measure).\n"
    )

    for {label, field} <- [
          {"check_id alone", "by_check_id_alone"},
          {"name alone", "by_name_alone"},
          {"description alone", "by_description_alone"},
          {"check_id + name", "by_check_id_and_name"},
          {"the token's five fields", "by_the_token_five"},
          {"A1's six-field key", "by_a1s_six_field_key"}
        ] do
      IO.puts(
        "    #{String.pad_trailing(label, 26)} #{String.pad_leading(to_string(k[field]), 3)} rows lost"
      )
    end

    positive =
      k["by_check_id_alone"] > 0 and k["by_name_alone"] > 0 and k["by_description_alone"] > 0

    negative = k["by_a1s_six_field_key"] == 0

    IO.puts("")

    verdict(
      "POSITIVE — the hazard is real ON THIS POPULATION, not merely quoted from A1",
      positive
    )

    verdict("NEGATIVE — A1's six-field key loses nothing", negative)

    IO.puts("""

      Either direction alone is vacuous. A control that ran only the negative would pass
      over a crosswalk keyed on `id`; one that ran only the positive would not show the
      key in use is sound. A merged row is a match nobody made.
    """)

    halt_unless(positive and negative)

    # And the join actually in use must not merge: two cells may never share a
    # (member, claim, tag) triple.
    cells = @crosswalk_out |> read() |> Map.fetch!("cells")

    triples = Enum.map(cells, &{&1["member"]["register_key"], &1["claim"], &1["tag"]})
    dupes = triples -- Enum.uniq(triples)

    IO.puts(
      "  the crosswalk's own join: #{length(cells)} cells, #{length(Enum.uniq(triples))} distinct (member, claim, tag) triples"
    )

    verdict("no two cells share a triple", dupes == [])
    halt_unless(dupes == [])
  end

  # --- locator: the positive control, and the same control MUTATED ----------

  defp locator do
    header("LOCATOR — A3's 13 hand-cut rows, re-derived mechanically")

    require_harness!()
    {:ok, h} = Locator.load(@harness)
    axes = read(@a3_axes)

    case Locator.positive_control(h, axes) do
      {:ok, n} -> IO.puts("  POSITIVE  all #{n} of A3's excerpts re-derived BYTE-IDENTICAL")
      {:error, m} -> IO.puts("  FAILED    #{inspect(m)}") && System.halt(1)
    end

    # MUTATION 1 — move one committed span. The control must notice.
    moved =
      update_in(axes, ["checks"], fn cs ->
        List.update_at(cs, 0, fn c ->
          [from, to] = c["emitting_site"]["dist_byte_span"]
          put_in(c, ["emitting_site", "dist_byte_span"], [from + 16, to])
        end)
      end)

    shows_failure("MUTATION  one span moved 16 bytes", Locator.positive_control(h, moved))

    # MUTATION 2 — corrupt one committed excerpt's BYTES, leaving the span.
    # This is the one a span-only comparison would miss.
    retyped =
      update_in(axes, ["checks"], fn cs ->
        List.update_at(cs, 0, fn c ->
          Map.put(c, "evaluator_excerpt", c["evaluator_excerpt"] <> " ")
        end)
      end)

    shows_failure(
      "MUTATION  one excerpt's bytes changed, span left alone",
      Locator.positive_control(h, retyped)
    )

    # The rungs, and what each one PINS. A ladder whose rungs all claimed the
    # same thing would not need to be a ladder.
    loc = read(@locator_out)
    IO.puts("\n  ladder over the 173:")

    for {rung, n} <- Enum.sort_by(loc["ladder"]["per_rung"], &(-elem(&1, 1))) do
      IO.puts("    #{String.pad_trailing(rung, 22)} #{String.pad_leading(to_string(n), 3)}")
    end

    IO.puts("""

      The two rungs MES-76 does not name — id_bound_variable (generalising its CONSTANT
      case past a bare literal) and id_table_value — carry #{loc["ladder"]["per_rung"]["id_bound_variable"]} and #{loc["ladder"]["per_rung"]["id_table_value"]} rows.
      Without them those #{loc["ladder"]["per_rung"]["id_bound_variable"] + loc["ladder"]["per_rung"]["id_table_value"]} rows are unresolved, and an artefact that resolved 163 of 173
      while reading as total is the failure this ticket exists to avoid.
    """)

    # The structural test on the prefix rung, shown to matter rather than argued.
    parts = String.split("sep-2243-x-mcp-header-not-empty", "-")

    naive =
      Enum.find(length(parts)..1//-1, fn n ->
        p = parts |> Enum.take(n) |> Enum.join("-")
        Locator.count(h, "`" <> p <> "-${") > 0
      end)

    naive_prefix = parts |> Enum.take(naive) |> Enum.join("-")

    IO.puts(
      "  prefix rung WITHOUT the emitting-position test, on sep-2243-x-mcp-header-not-empty:"
    )

    IO.puts(
      "    resolves on the prefix #{inspect(naive_prefix)} — the harness's own `sep-${e}-todo` scaffolding."
    )

    verdict("the naive prefix search does resolve, and resolves WRONGLY", naive_prefix == "sep")

    row = Enum.find(loc["rows"], &(&1["check_id"] == "sep-2243-x-mcp-header-not-empty"))

    IO.puts(
      "    with the test: rung #{row["rung"]} — #{row["rung_detail"]["table"]}[#{row["rung_detail"]["table_key"]}]"
    )

    verdict(
      "the guarded ladder does NOT take the prefix rung for this row",
      row["rung"] == "id_table_value"
    )

    halt_unless(naive_prefix == "sep" and row["rung"] == "id_table_value")
  end

  # --- pins: the guard on what a resolution CLAIMS to address ---------------
  #
  # MES-97 CR finding. `rung_pins` said "the ROW" for six rows whose own
  # `row_key_matches` said the address that resolved them names a SIBLING. The
  # value was computed and nothing acted on it — which is S9-15's shape exactly,
  # so the control here drives the WHOLE generator rather than the predicate.
  #
  # The mutation is applied to the MECHANISM, not to an input file, because no
  # input can produce the state: it is a disagreement between two fields the
  # generator computes. Nothing on disk is touched — the module is recompiled in
  # this VM and restored in an `after`, so a death mid-run cannot leave the
  # clone mutated (S8-14).

  @locator_src "conformance/lib/mcp/conformance/locator.ex"

  defp pins do
    header("PIN LEVELS — a row may record a coarser pin than it wants, never a finer one")

    require_harness!()

    loc = read(@locator_out)

    IO.puts("  levels over the 173:")

    for {level, n} <- Enum.sort_by(loc["ladder"]["per_pin_level"], &(-elem(&1, 1))) do
      IO.puts("    #{String.pad_trailing(level, 8)} #{String.pad_leading(to_string(n), 3)}")
    end

    by_rung = Enum.count(loc["rows"], &(&1["rung"] in ["id_literal_pair", "id_table_value"]))
    by_level = Enum.count(loc["rows"], &(&1["rung_pin_level"] == "row"))

    IO.puts(
      "\n  counted BY RUNG, row-level would be #{by_rung}; by rung AND metadata it is #{by_level}."
    )

    verdict("the rung alone over-states row-level pinning by exactly 6", by_rung - by_level == 6)
    halt_unless(by_rung - by_level == 6)

    # The six, named, with the bytes that refute the row-level claim.
    six =
      Enum.filter(
        loc["rows"],
        &(&1["rung"] == "id_table_value" and &1["rung_pin_level"] == "loop")
      )

    IO.puts("\n  the six CR measured, now recorded at LOOP:")

    for r <- six do
      suffix = r["name"] |> String.split("_", parts: 2) |> List.last()
      in_site = Enum.any?(r["sites"], &String.contains?(&1["bytes"], suffix))

      IO.puts(
        "    #{String.pad_trailing(r["name"], 46)} key=#{String.pad_trailing(r["rung_detail"]["table_key"], 28)} own suffix in site bytes: #{in_site}"
      )
    end

    verdict(
      "none of the six has its own suffix in the bytes at its site",
      Enum.all?(six, fn r ->
        suffix = r["name"] |> String.split("_", parts: 2) |> List.last()
        not Enum.any?(r["sites"], &String.contains?(&1["bytes"], suffix))
      end)
    )

    # And the four that DO pin the row rest on the ENTRY, whose bytes name them.
    four =
      Enum.filter(
        loc["rows"],
        &(&1["rung"] == "id_table_value" and &1["rung_pin_level"] == "row")
      )

    verdict(
      "each of the four row-level table rows carries an ENTRY whose bytes name it",
      length(four) == 4 and
        Enum.all?(four, fn r ->
          String.contains?(
            r["rung_detail"]["table_entry"]["bytes"],
            r["rung_detail"]["table_key"]
          )
        end)
    )

    halt_unless(length(four) == 4)

    # POSITIVE CONTROL FIRST: the unmutated generator emits. Without it, the
    # refusal below could be a broken harness rather than the mutation.
    out = tmp("pins-positive")
    run_locator(out)
    IO.puts("\n  POSITIVE  the unmutated generator emits (#{byte_size(File.read!(out))} bytes)")
    File.rm(out)

    # MUTATION — make `pin_level/2` claim ROW for every id_table_value row, the
    # exact state CR found, and require the generator to REFUSE it.
    src = File.read!(@locator_src)

    mutated =
      String.replace(
        src,
        "def pin_level(:id_table_value, _meta), do: :loop",
        "def pin_level(:id_table_value, _meta), do: :row"
      )

    if mutated == src do
      IO.puts("  MUTATION COULD NOT BE APPLIED — the clause the control edits has moved.")
      IO.puts("  A mutation that does not mutate is a green that means nothing.")
      System.halt(1)
    end

    refused = tmp("pins-mutated")

    try do
      recompile!(mutated)

      refuses("MUTATION  pin_level/2 claims ROW for every id_table_value row", fn ->
        run_locator(refused)
      end)

      verdict(
        "and nothing was written — the guard runs before the file",
        not File.exists?(refused)
      )

      halt_unless(not File.exists?(refused))
    after
      recompile!(src)
      File.rm(refused)
    end

    # Restored: the same run that just refused now succeeds again.
    back = tmp("pins-restored")
    run_locator(back)
    verdict("the mechanism is restored — the generator emits again", File.exists?(back))
    File.rm(back)

    IO.puts("""

      The guard's predicate is stated independently of `pin_level/2` — it asks whether a
      ROW claim is backed by a row-naming address, whatever computed the claim. So it
      cross-checks that function instead of restating it, and the mutation above is the
      cheapest way the artefact could carry the defect CR found.
    """)
  end

  defp recompile!(source) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source, @locator_src)
  after
    Code.put_compiler_option(:ignore_module_conflict, false)
  end

  # --- guards: every refusal in the crosswalk generator, shown FIRING -------

  defp guards do
    header("GUARDS — each fail-closed condition, mutated and shown to refuse")

    require_harness!()
    edges = read(@edges)
    first = hd(edges["edges"])

    # POSITIVE CONTROL FIRST: the unmutated build succeeds, so a refusal below
    # is the mutation's doing and not a broken harness.
    out = tmp("guard-positive")
    run_crosswalk(out, edges: @edges)
    IO.puts("  POSITIVE  the unmutated edges build cleanly (#{byte_size(File.read!(out))} bytes)")
    File.rm(out)

    refuses("1  a tag that does not resolve in A1's manifest (A3 §6 state 2)", fn ->
      build_edges(put_first(edges, Map.put(first, "tag", first["tag"] <> "zzz")))
    end)

    refuses("2  a well-formed tag naming a check that does not exist", fn ->
      build_edges(
        put_first(
          edges,
          Map.put(first, "tag", "oc:client/request-metadata/no-such-check/NoSuchCheck")
        )
      )
    end)

    refuses("3  an `oc:none` tag used as an EDGE tag", fn ->
      build_edges(
        put_first(edges, Map.put(first, "tag", "oc:none/no-oc-scenario/CG2-outbound-meta"))
      )
    end)

    refuses("4  an axis name the check's decomposition does not contain", fn ->
      build_edges(
        put_first(
          edges,
          Map.put(first, "axes", [%{"axis" => "invented_axis", "verdict" => "agrees"}])
        )
      )
    end)

    refuses("5  an axis set that is not the decomposition's WHOLE set", fn ->
      two = Enum.find(edges["edges"], &(length(&1["axes"]) > 1))
      build_edges(replace(edges, two, Map.put(two, "axes", [hd(two["axes"])])))
    end)

    refuses("6  one axis named twice", fn ->
      a = hd(first["axes"])
      build_edges(put_first(edges, Map.put(first, "axes", [a, a])))
    end)

    refuses("7  a member that is not ET-CC in the register", fn ->
      build_edges(
        put_first(edges, put_in(first, ["member", "register_key"], "MCP.NoSuchTest/test nope"))
      )
    end)

    refuses("8  a member in the population carrying NEITHER token kind (A3 §6 state 4)", fn ->
      untagged = %{
        "member" => %{
          "module" => "MCP.ClientTest",
          "test" => "test requests list_tools returns tools",
          "register_key" => "MCP.ClientTest/test requests list_tools returns tools"
        },
        "tag" => "oc:none/fabricated/MES97-state-4-probe"
      }

      build_edges(update_in(edges, ["declared_unmatched"], &[untagged | &1]))
    end)

    refuses("9  an `oc:` token in declared_unmatched — state 1 masquerading as state 3", fn ->
      d = hd(edges["declared_unmatched"])

      build_edges(
        update_in(edges, ["declared_unmatched"], fn [_ | t] ->
          [Map.put(d, "tag", first["tag"]) | t]
        end)
      )
    end)

    refuses("10  an edge with no tag at all", fn ->
      build_edges(put_first(edges, Map.delete(first, "tag")))
    end)

    refuses("11  an ET verdict outside {green, red}", fn ->
      build_edges(put_first(edges, Map.put(first, "et_verdict", "amber")))
    end)

    # The axis artefacts must not both claim a check — D4, one fact one home.
    refuses("12  A3's axes and C1's axes decomposing the SAME check (D4)", fn ->
      a3 = read(@a3_axes)
      c1 = read(@c1_axes)
      clash = update_in(c1, ["checks"], &[hd(a3["checks"]) | &1])
      path = write_tmp("c1-axes", clash)

      try do
        run_crosswalk(tmp("d4"), c1_axes: path)
      after
        File.rm(path)
      end
    end)

    # The committed axis spans are addresses into /tmp. Move the bytes.
    refuses("13  a committed axis expr that is not verbatim at its committed span", fn ->
      c1 = read(@c1_axes)

      broken =
        update_in(c1, ["checks"], fn cs ->
          List.update_at(cs, 0, fn c ->
            update_in(c, ["axes"], fn ax ->
              List.update_at(ax, 0, &Map.put(&1, "expr", "o===void 1"))
            end)
          end)
        end)

      path = write_tmp("c1-axes", broken)

      try do
        run_crosswalk(tmp("spans"), c1_axes: path)
      after
        File.rm(path)
      end
    end)

    # POSITIVE CONTROL, AFTER — added by MES-99 (C3). This mode ran its positive
    # control only BEFORE its thirteen mutations, so "restored green" was never
    # established for it: every mutation here is a temp copy and none should
    # touch the tree, but that is the claim, and an unrun check and a null result
    # are the same artefact.
    back = tmp("guard-restored")
    run_crosswalk(back, edges: @edges)
    restored = File.read!(back) == File.read!(@crosswalk_out)
    File.rm(back)

    verdict(
      "RESTORED — the unmutated edges rebuild the committed artefact byte-for-byte",
      restored
    )

    halt_unless(restored)

    IO.puts("""

      Thirteen guards, thirteen refusals, and a positive control on BOTH sides of them.
      Each mutation is the cheapest way the artefact could be wrong in that particular
      way.
    """)
  end

  # --- vacuum: the AC that a wrong artefact satisfied (S9-15 / D3) ----------

  defp vacuum do
    header("VACUUM — the empty crosswalk, which the ORIGINAL AC3 satisfied perfectly")

    require_harness!()
    edges = read(@edges)

    IO.puts("""
      MES-97's AC3 read: 'every one of the 173 appears exactly once as a match target;
      every ET-CC member appears; the unmatched sets are enumerated'. A crosswalk with
      ZERO edges satisfies it perfectly — all 173 fall into bucket 2, all 281 into
      bucket 1, every set enumerated, the arithmetic exact.
    """)

    empty = %{edges | "edges" => [], "declared_unmatched" => []}

    refuses("the empty crosswalk", fn -> build_edges(empty) end)

    IO.puts("""
      It refuses because an empty population is a population with nothing to be total
      OVER, and `project/2` will not take a complement without a universe. Emptiness is
      what the guard fires on, which is what makes AC3 an AC (ruling 8).
    """)

    # And the projections themselves refuse, at the function level.
    for {label, arg} <- [
          {"no declared population", %{population: nil, with_edges: []}},
          {"an empty declared population", %{population: [], with_edges: []}}
        ] do
      r1 = Crosswalk.project(:bucket_1, arg)
      r2 = Crosswalk.project(:bucket_2, arg)

      verdict(
        "project/2 refuses bucket 1 and 2 with #{label}",
        match?({:error, _}, r1) and match?({:error, _}, r2)
      )

      halt_unless(match?({:error, _}, r1) and match?({:error, _}, r2))
    end

    # The other half of the vacuum: a set comparison that PASSES on counts.
    a = Crosswalk.set_compare(["a", "b"], ["a", "c"])

    verdict(
      "set_compare catches equal COUNTS over unequal SETS",
      a.equal == false and a.missing == ["b"] and a.extra == ["c"]
    )

    halt_unless(a.equal == false)

    # And the escalation that keeps an all-silent claim out of bucket 5.
    {:ok, e} =
      MatchKey.new_edge(%{
        member: %{module: "M", test: "t"},
        claim: "c",
        oc_key: [
          "client",
          "request-metadata",
          "sep-2575-client-populates-meta",
          "ClientPopulatesMeta",
          "d",
          ""
        ],
        verdicts: %{oc: :green, et: :green},
        axes: [%{axis: "a1", verdict: :silent}, %{axis: "a2", verdict: :silent}]
      })

    {bucket, _attrs, escalation} = Crosswalk.assign(e)
    {:ok, naive, _} = MatchKey.bucket(e)

    IO.puts("\n  an all-silent edge:")
    IO.puts("    MatchKey.bucket/1 alone would file it as bucket #{naive} (shape #{e.shape})")
    IO.puts("    Crosswalk.assign/1 escalates instead: #{String.slice(escalation || "", 0, 60)}…")
    verdict("the all-silent edge is NOT bucketed", is_nil(bucket) and naive == "5")
    halt_unless(is_nil(bucket))
  end

  # --- plumbing -------------------------------------------------------------

  defp run_locator(out) do
    Mix.Task.rerun("conformance.locator", [
      "--harness",
      @harness,
      "--denominator",
      @denominator,
      "--axes",
      @a3_axes,
      "-o",
      out
    ])
  end

  defp run_crosswalk(out, overrides \\ []) do
    Mix.Task.rerun("conformance.crosswalk", [
      "--edges",
      Keyword.get(overrides, :edges, @edges),
      "--manifest",
      @manifest,
      "--denominator",
      @denominator,
      "--register",
      @register,
      "--attribution",
      @attribution,
      "--a3-axes",
      @a3_axes,
      "--c1-axes",
      Keyword.get(overrides, :c1_axes, @c1_axes),
      "--harness",
      @harness,
      "-o",
      out
    ])
  end

  defp build_edges(doc) do
    path = write_tmp("edges", doc)
    out = tmp("mutated")

    try do
      run_crosswalk(out, edges: path)
    after
      File.rm(path)
      File.rm(out)
    end
  end

  defp put_first(doc, edge), do: update_in(doc, ["edges"], fn [_ | t] -> [edge | t] end)

  defp replace(doc, old, new),
    do: update_in(doc, ["edges"], fn es -> Enum.map(es, &if(&1 == old, do: new, else: &1)) end)

  defp refuses(label, fun) do
    fun.()
    IO.puts("  DID NOT REFUSE  #{label}")
    System.halt(1)
  rescue
    e -> IO.puts("  refused  #{label}\n           #{first_line(Exception.message(e))}")
  end

  defp shows_failure(label, {:error, detail}) do
    IO.puts("  #{label}\n           control failed, as it must: #{first_line(inspect(detail))}")
  end

  defp shows_failure(label, {:ok, n}) do
    IO.puts(
      "  #{label}\n           DID NOT FAIL — the control returned {:ok, #{n}} over a mutated artefact."
    )

    System.halt(1)
  end

  defp verdict(label, true), do: IO.puts("  ok    #{label}")
  defp verdict(label, false), do: IO.puts("  FAIL  #{label}")

  defp halt_unless(true), do: :ok
  defp halt_unless(false), do: System.halt(1)

  defp require_harness! do
    if File.exists?(@harness) do
      :ok
    else
      IO.puts("""
        HARNESS ABSENT at #{@harness}.
        These controls cannot run, and that is reported rather than skipped: an unrun
        control and a null result are the same artefact (MES-56).
      """)

      System.halt(1)
    end
  end

  defp tmp(stem),
    do: Path.join(System.tmp_dir!(), "mes97-#{stem}-#{System.unique_integer([:positive])}.json")

  defp write_tmp(stem, doc) do
    path = tmp(stem)
    File.write!(path, Jason.encode!(doc))
    path
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp md5(bin), do: :crypto.hash(:md5, bin) |> Base.encode16(case: :lower)
  defp first_line(msg), do: msg |> String.split("\n") |> hd()
  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

CrosswalkControls.run(System.argv())
