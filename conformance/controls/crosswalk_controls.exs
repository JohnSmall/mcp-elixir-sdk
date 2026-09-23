# Controls for C1a's two instruments — the locator and the crosswalk (MES-97).
#
#     mix run conformance/controls/crosswalk_controls.exs noop
#     mix run conformance/controls/crosswalk_controls.exs keying
#     mix run conformance/controls/crosswalk_controls.exs locator
#     mix run conformance/controls/crosswalk_controls.exs pins
#     mix run conformance/controls/crosswalk_controls.exs guards
#     mix run conformance/controls/crosswalk_controls.exs vacuum
#     mix run conformance/controls/crosswalk_controls.exs selectors
#     mix run conformance/controls/crosswalk_controls.exs composition
#     mix run conformance/controls/crosswalk_controls.exs absence
#     mix run conformance/controls/crosswalk_controls.exs totality
#     mix run conformance/controls/crosswalk_controls.exs citations
#     mix run conformance/controls/crosswalk_controls.exs statements
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

  @client_edges "conformance/data/crosswalk-edges-client.json"
  @edges "conformance/data/crosswalk-edges.json"
  @c1_axes "conformance/data/oc-axes-c1.json"
  @a3_axes "docs/conformance/oc-axes-2026-07-28.json"
  @manifest "docs/conformance/in-scope-2026-07-28.json"
  @denominator "docs/conformance/bucket-0-2026-07-28.json"
  @register "docs/conformance/etcc-register.json"
  @attribution "docs/conformance/etcc-attribution.json"
  @crosswalk_out "docs/conformance/crosswalk-2026-07-28.json"
  @locator_out "docs/conformance/oc-emitting-sites-2026-07-28.json"
  @sites @locator_out

  def run(["noop"]), do: noop()
  def run(["keying"]), do: keying()
  def run(["locator"]), do: locator()
  def run(["pins"]), do: pins()
  def run(["guards"]), do: guards()
  def run(["vacuum"]), do: vacuum()
  def run(["selectors"]), do: selectors()
  def run(["composition"]), do: composition()
  def run(["absence"]), do: absence()
  def run(["totality"]), do: totality()
  def run(["citations"]), do: citations()
  def run(["statements"]), do: statements()

  def run(["all"]) do
    noop()
    keying()
    locator()
    pins()
    guards()
    vacuum()
    selectors()
    composition()
    absence()
    totality()
    citations()
    statements()
  end

  def run(_) do
    IO.puts(
      "usage: noop | keying | locator | pins | guards | vacuum | selectors | composition | absence | totality | citations | statements | all"
    )

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

      refuses(
        "MUTATION  pin_level/2 claims ROW for every id_table_value row",
        "rows claim a ROW-LEVEL pin while their own rung_detail says",
        fn ->
          run_locator(refused)
        end
      )

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

  defp recompile!(source), do: recompile!(source, @locator_src)

  defp recompile!(source, path) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source, path)
  after
    Code.put_compiler_option(:ignore_module_conflict, false)
  end

  # --- guards: every refusal in the crosswalk generator, shown FIRING -------

  defp guards do
    header("GUARDS — each fail-closed condition, mutated and shown to refuse")

    require_harness!()
    # The mutations are applied to the CLIENT file, which is where MES-104's
    # composition ruling put every interesting row; the residual file rides
    # along unmutated on every run, so each refusal below is a refusal over a
    # REAL two-file crosswalk rather than over a single-file one.
    edges = read(@client_edges)
    first = hd(edges["edges"])

    # POSITIVE CONTROL FIRST: the unmutated build succeeds, so a refusal below
    # is the mutation's doing and not a broken harness.
    out = tmp("guard-positive")
    run_crosswalk(out)
    IO.puts("  POSITIVE  the unmutated edges build cleanly (#{byte_size(File.read!(out))} bytes)")
    File.rm(out)

    refuses(
      "1  a tag that does not resolve in A1's manifest (A3 §6 state 2)",
      "did not survive re-derivation",
      fn ->
        build_edges(put_first(edges, Map.put(first, "tag", first["tag"] <> "zzz")))
      end
    )

    refuses(
      "2  a well-formed tag naming a check that does not exist",
      "did not survive re-derivation",
      fn ->
        build_edges(
          put_first(
            edges,
            Map.put(first, "tag", "oc:client/request-metadata/no-such-check/NoSuchCheck")
          )
        )
      end
    )

    refuses("3  an `oc:none` tag used as an EDGE tag", "oc_none_tag_on_an_edge", fn ->
      build_edges(
        put_first(edges, Map.put(first, "tag", "oc:none/no-oc-scenario/CG2-outbound-meta"))
      )
    end)

    refuses(
      "4  an axis name the check's decomposition does not contain",
      "axis_not_in_decomposition",
      fn ->
        build_edges(
          put_first(
            edges,
            Map.put(first, "axes", [%{"axis" => "invented_axis", "verdict" => "agrees"}])
          )
        )
      end
    )

    refuses("5  an axis set that is not the decomposition's WHOLE set", "axes_not_total", fn ->
      two = Enum.find(edges["edges"], &(length(&1["axes"]) > 1))
      build_edges(replace(edges, two, Map.put(two, "axes", [hd(two["axes"])])))
    end)

    refuses("6  one axis named twice", "axis_named_twice", fn ->
      a = hd(first["axes"])
      build_edges(put_first(edges, Map.put(first, "axes", [a, a])))
    end)

    refuses("7  a member that is not ET-CC in the register", "not ET-CC in the register", fn ->
      build_edges(
        put_first(edges, put_in(first, ["member", "register_key"], "MCP.NoSuchTest/test nope"))
      )
    end)

    # MES-104 re-measured this one. The label used to say A3 §6 state 4, and
    # the state-4 guard is what it was written for — but that guard is ENTAILED
    # by G15a (residual X7) and cannot fire. What actually refuses an untagged
    # member is G15a's `extra` limb: the member is in the file and not in the
    # set its selector denotes. The mutation is unchanged and still caught; the
    # label now names the guard that catches it.
    # MES-109 re-cut the PROBE, not the guard. It used to name a specific
    # client member, and C1b-iii homed that member — so the mutation started
    # tripping G14 (declared unmatched twice) and the control reported the
    # wrong guard. That is the failure mode `refuses/3` exists for, and it is
    # worth recording that it worked: a probe naming a row the file did not
    # have when it was written is a probe with an expiry date. The probe is now
    # DERIVED — the first ET-CC member the register holds that no edges file
    # carries — so homing any particular member cannot stale it again.
    refuses("8  a member in the population that its own selector does not denote", "G15a", fn ->
      carried =
        MapSet.new(
          Enum.map(edges["edges"] ++ edges["declared_unmatched"], & &1["member"]["register_key"]) ++
            Enum.map(
              read(@edges)["edges"] ++ read(@edges)["declared_unmatched"],
              & &1["member"]["register_key"]
            )
        )

      key =
        read(@register)["rows"]
        |> Enum.filter(&(&1["label"] == "ET-CC"))
        |> Enum.map(& &1["key"])
        |> Enum.reject(&MapSet.member?(carried, &1))
        |> Enum.sort()
        |> hd()

      [module, test] = String.split(key, "/", parts: 2)

      untagged = %{
        "member" => %{"module" => module, "test" => test, "register_key" => key},
        "tag" => "oc:none/fabricated/MES97-state-4-probe",
        "the_search_that_found_none" => "none — a probe, not an adjudication"
      }

      build_edges(update_in(edges, ["declared_unmatched"], &[untagged | &1]))
    end)

    refuses(
      "9  an `oc:` token in declared_unmatched — state 1 masquerading as state 3",
      "state 3",
      fn ->
        d = hd(edges["declared_unmatched"])

        build_edges(
          update_in(edges, ["declared_unmatched"], fn [_ | t] ->
            [Map.put(d, "tag", first["tag"]) | t]
          end)
        )
      end
    )

    refuses("10  an edge with no tag at all", "edge_has_no_tag", fn ->
      build_edges(put_first(edges, Map.delete(first, "tag")))
    end)

    refuses("11  an ET verdict outside {green, red}", "bad_et_verdict", fn ->
      build_edges(put_first(edges, Map.put(first, "et_verdict", "amber")))
    end)

    # The axis artefacts must not both claim a check — D4, one fact one home.
    refuses(
      "12  A3's axes and C1's axes decomposing the SAME check (D4)",
      "one fact, two homes",
      fn ->
        a3 = read(@a3_axes)
        c1 = read(@c1_axes)
        clash = update_in(c1, ["checks"], &[hd(a3["checks"]) | &1])
        path = write_tmp("c1-axes", clash)

        try do
          run_crosswalk(tmp("d4"), c1_axes: path)
        after
          File.rm(path)
        end
      end
    )

    # The committed axis spans are addresses into /tmp. Move the bytes.
    refuses(
      "13  a committed axis expr that is not verbatim at its committed span",
      "not verbatim at their committed spans",
      fn ->
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
      end
    )

    # POSITIVE CONTROL, AFTER — added by MES-99 (C3). This mode ran its positive
    # control only BEFORE its thirteen mutations, so "restored green" was never
    # established for it: every mutation here is a temp copy and none should
    # touch the tree, but that is the claim, and an unrun check and a null result
    # are the same artefact.
    back = tmp("guard-restored")
    run_crosswalk(back)
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

    refuses("the empty crosswalk", "declares an EMPTY population", fn -> build_edges(empty) end)

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

  # --- selectors: the new language, driven against the REAL anchor ----------
  #
  # `test/conformance/crosswalk_test.exs` unit-tests `select/2` on a five-row
  # synthetic source, which is where the decision logic belongs. What that
  # CANNOT show is that the selectors the committed files actually carry denote
  # the populations they claim, over B2b's real 281 rows — a unit passing on
  # five rows says nothing about the anchor this project ships. Both, because
  # neither subsumes the other.

  defp selectors do
    header("SELECTORS — the committed selectors, evaluated against B2b's real 281 rows")

    src = read(@attribution)
    client = read(@client_edges)
    resid = read(@edges)
    sites = read(@sites)

    rows = src["rows"]
    IO.puts("  anchor: #{@attribution} — #{length(rows)} rows\n")

    # POSITIVE, and compared against a set computed a DIFFERENT way: the
    # selector is evaluated by `select/2`, the expectation by `Enum.filter` over
    # the same rows. A selector checked against itself proves nothing.
    tagged? = fn r -> (r["tokens"] || []) != [] or r["contradicts_oc"] != nil end

    # `no_cg?` is written the way the LEAF is written, not the way the data
    # happens to be: `has_key? and == nil`, so that this independently computed
    # expectation would ALSO be empty on a source that dropped the field. An
    # expectation written as `&1["cg"] == nil` would agree with the weaker leaf
    # and the pair below could not separate them.
    no_cg? = fn r -> Map.has_key?(r, "cg") and Map.get(r, "cg") == nil end

    expectations = [
      {"the client file's members", client["the_population_this_file_declares"]["selector"], src,
       rows
       |> Enum.filter(
         &(&1["leg"] == "client" and
             (&1["cg"] in ~w(CG7 CG1 CG2 CG4) or no_cg?.(&1) or tagged?.(&1)))
       )
       |> Enum.map(& &1["key"])},
      {"the residual file's members", resid["the_population_this_file_declares"]["selector"], src,
       rows
       |> Enum.filter(&(tagged?.(&1) and &1["leg"] != "client"))
       |> Enum.map(& &1["key"])},
      {"the client file's CHECKS", client["the_check_population_this_file_declares"]["selector"],
       sites,
       sites["rows"]
       |> Enum.filter(
         &(&1["scenario"] in [
             "http-custom-headers",
             "http-invalid-tool-headers",
             "http-standard-headers",
             "json-schema-ref-no-deref",
             "request-metadata",
             "sep-2322-client-request-state",
             "tools_call"
           ])
       )
       |> Enum.map(& &1["token"])}
    ]

    for {label, selector, source, expected} <- expectations do
      {:ok, got} = Crosswalk.select(selector, source)
      c = Crosswalk.set_compare(expected, got)

      IO.puts(
        "    #{String.pad_trailing(label, 30)} #{String.pad_leading(to_string(length(got)), 3)} denoted"
      )

      verdict(
        "POSITIVE — #{label}: set-equal to an independently computed set, both directions",
        c.equal
      )

      halt_unless(c.equal)
    end

    # THE MUTATION THAT MATTERS, measured on the real anchor rather than argued:
    # `all_of` silently behaving as `any_of` does not error, does not change the
    # selector's shape, and changes the population.
    member_sel = client["the_population_this_file_declares"]["selector"]
    as_any = member_sel |> Map.delete("all_of") |> Map.put("any_of", member_sel["all_of"])

    {:ok, conj} = Crosswalk.select(member_sel, src)
    {:ok, disj} = Crosswalk.select(as_any, src)

    IO.puts("\n  MUTATION  the client file's `all_of` read as `any_of`:")

    IO.puts(
      "    #{length(conj)} members -> #{length(disj)}  (#{length(disj) - length(conj)} more)"
    )

    verdict(
      "the two combinators denote DIFFERENT populations on this anchor",
      length(disj) != length(conj)
    )

    halt_unless(length(disj) != length(conj))

    # And the `equals` value, which is the whole content of the leg conjunct.
    typo =
      update_in(member_sel, ["all_of"], fn [leg | rest] ->
        [Map.put(leg, "value", "cleint") | rest]
      end)

    {:ok, none} = Crosswalk.select(typo, src)

    IO.puts(
      "  MUTATION  one character wrong in the `equals` value: #{length(conj)} -> #{length(none)}"
    )

    verdict("a mistyped value denotes the EMPTY set rather than erroring", none == [])
    halt_unless(none == [])

    # MES-108 (C1b-ii). The two mutations C1b-i's pair could not make, because
    # its `any_of` held ONE `cg` leaf and a dropped leaf is indistinguishable
    # from a renamed one when there is only one. With four leaves both are
    # distinguishable and both change the population by a DIFFERENT amount, so
    # each says something the other does not.
    #
    # A dropped leaf and a mistyped leaf fail the SAME guard (G15a) but they are
    # not the same mistake: a drop silently narrows the declared population and
    # the file's own counts move with it, whereas a typo leaves the counts
    # standing and empties the leaf. Only measuring both on the real anchor says
    # which one a given red is.
    for cg <- ~w(CG1 CG2 CG4 CG7) do
      dropped =
        update_in(member_sel, ["all_of"], fn [leg, %{"any_of" => leaves}] ->
          [leg, %{"any_of" => Enum.reject(leaves, &(&1["value"] == cg))}]
        end)

      {:ok, fewer} = Crosswalk.select(dropped, src)

      IO.puts(
        "  MUTATION  the `#{cg}` leaf dropped from the member `any_of`: " <>
          "#{length(conj)} -> #{length(fewer)}"
      )

      verdict(
        "dropping `#{cg}` denotes a STRICTLY SMALLER population",
        length(fewer) < length(conj)
      )

      halt_unless(length(fewer) < length(conj))
    end

    # And a leaf that is PRESENT but names a CG that does not exist. This is the
    # one a count alone cannot catch in the other direction: the selector still
    # has four leaves and still parses, and the population is exactly the one a
    # dropped leaf gives — so the FILE's declared counts are what tell the two
    # apart, which is why G15a compares the set and not the shape.
    renamed =
      update_in(member_sel, ["all_of"], fn [leg, %{"any_of" => leaves}] ->
        [
          leg,
          %{
            "any_of" =>
              Enum.map(leaves, &if(&1["value"] == "CG1", do: %{&1 | "value" => "CG11"}, else: &1))
          }
        ]
      end)

    {:ok, wrong} = Crosswalk.select(renamed, src)

    IO.puts(
      "  MUTATION  the `CG1` leaf RENAMED to a CG that does not exist: " <>
        "#{length(conj)} -> #{length(wrong)}"
    )

    verdict(
      "a leaf naming an absent `cg` contributes NOTHING rather than erroring",
      length(wrong) < length(conj)
    )

    halt_unless(length(wrong) < length(conj))

    # The CHECK selector gets the same treatment, and its drop is the one that
    # would be invisible without it: remove `http-standard-headers` and the file
    # declares 30 checks instead of 39, bucket 2's universe shrinks with it, and
    # every bucket-2 figure stays internally consistent over the smaller set.
    check_sel = client["the_check_population_this_file_declares"]["selector"]
    {:ok, all_checks} = Crosswalk.select(check_sel, sites)

    without =
      update_in(check_sel, ["any_of"], fn leaves ->
        Enum.reject(leaves, &(&1["value"] == "http-standard-headers"))
      end)

    {:ok, fewer_checks} = Crosswalk.select(without, sites)

    IO.puts(
      "  MUTATION  `http-standard-headers` dropped from the CHECK `any_of`: " <>
        "#{length(all_checks)} -> #{length(fewer_checks)}"
    )

    verdict(
      "dropping a scenario removes exactly its checks from the declared population",
      length(all_checks) - length(fewer_checks) == 9
    )

    halt_unless(length(all_checks) - length(fewer_checks) == 9)

    # --- MES-109 (C1b-iii): the `is_null` leaf, and the ONE decision in it ----
    #
    # The leaf is `has_key?(row, f) and get(row, f) == nil`. The weaker reading
    # `get(row, f) == nil` is indistinguishable from it on the anchor this
    # project ships — all 281 rows carry `cg` — so live data cannot separate
    # them and only this pair can. The second half is what makes the first half
    # a measurement rather than a coincidence.
    is_null_leaf = %{
      "source" => @attribution,
      "rows_at" => "rows",
      "key_field" => "key",
      "all_of" => [
        %{"field" => "leg", "test" => "equals", "value" => "client"},
        %{"field" => "cg", "test" => "is_null"}
      ]
    }

    {:ok, nulls} = Crosswalk.select(is_null_leaf, src)

    expected_nulls =
      rows |> Enum.filter(&(&1["leg"] == "client" and no_cg?.(&1))) |> Enum.map(& &1["key"])

    cn = Crosswalk.set_compare(expected_nulls, nulls)

    IO.puts(
      "\n  IS_NULL  `leg = client AND cg is_null` on the real anchor: #{length(nulls)} denoted"
    )

    verdict(
      "POSITIVE — set-equal to an independently computed set, both directions",
      cn.equal
    )

    halt_unless(cn.equal)

    # THE LOAD-BEARING HALF. Strip the `cg` KEY from every row — not set it to
    # null, REMOVE it — and re-run the same selector against the same machinery.
    # Under the implemented leaf the denotation collapses to nothing and G15a
    # would red naming every member of the file as `extra`. Under
    # `get(row,f) == nil` it would denote ALL of them and the population would
    # be silently re-declared, reconciling perfectly over a universe nobody
    # chose. The two readings differ by 107 rows on this anchor and by 0 on the
    # live data, which is the whole reason this control exists.
    keyless = %{"rows" => Enum.map(rows, &Map.delete(&1, "cg"))}
    {:ok, on_keyless} = Crosswalk.select(is_null_leaf, keyless)

    weaker = fn r -> Map.get(r, "cg") == nil end

    would_be =
      keyless["rows"] |> Enum.filter(&(&1["leg"] == "client" and weaker.(&1))) |> length()

    IO.puts(
      "  MUTATION  the `cg` KEY removed from all #{length(rows)} rows: " <>
        "#{length(nulls)} -> #{length(on_keyless)}   (the weaker `get == nil` reading would give #{would_be})"
    )

    verdict(
      "an ABSENT field denotes NOTHING — fail-closed, so a dropped field reds at G15a " <>
        "instead of re-declaring the population",
      on_keyless == []
    )

    halt_unless(on_keyless == [])

    verdict(
      "and the two readings really are separable — the weaker one denotes #{would_be} here, " <>
        "not 0, so this is a measured difference and not a restatement",
      would_be > 0
    )

    halt_unless(would_be > 0)

    # And the leaf dropped from the file's OWN selector, which measures C1b-iii's
    # "42 new homes, not 55" from the other side — the same route the CG drops
    # above took for C1b-ii's 20.
    without_null =
      update_in(member_sel, ["all_of"], fn [leg, %{"any_of" => leaves}] ->
        [leg, %{"any_of" => Enum.reject(leaves, &(&1["test"] == "is_null"))}]
      end)

    {:ok, no_null} = Crosswalk.select(without_null, src)

    IO.puts(
      "  MUTATION  the `cg is_null` leaf dropped from the member `any_of`: " <>
        "#{length(conj)} -> #{length(no_null)}  (-#{length(conj) - length(no_null)})"
    )

    verdict(
      "dropping it removes 42 members and not 55 — the 13 no-CG rows carrying C1a tokens " <>
        "are still held by the `tokens` limb, which is C1b-iii's new-homes figure derived " <>
        "without counting homes",
      length(conj) - length(no_null) == 42
    )

    halt_unless(length(conj) - length(no_null) == 42)

    IO.puts("""

      The generator catches every one of them — a population that is not the set its
      selector denotes is G15a, in both directions. What this shows is the SIZE of the
      mistake each one makes on the anchor this project actually ships, which is the
      thing a five-row unit cannot say.

      AND THE DROP FIGURES CONFIRM C1b-ii's OVERLAP MEASUREMENT FROM THE OTHER SIDE.
      B2b attributes 23 rows to CG1 + CG2 + CG4 on the client leg, but C1b-ii homes only
      20 of them, because 3 CG2 rows carry C1a `oc:none` tokens and were already inside
      C1b-i's 45 through the `tokens non_empty_list` limb. Dropping the leaves one at a
      time measures exactly that: CG1 -9, CG2 -10 (not -13 — the three are still held by
      the tokens limb), CG4 -1. 9 + 10 + 1 = 20, the number of new homes, arrived at
      without counting homes. A figure that two independent routes agree on is a figure;
      one route's arithmetic is a claim.

      C1b-iii's figure comes out the same way and the arithmetic closes over the whole
      leg. Dropping `cg is_null` removes 42, not the 55 B2b attributes: the other 13
      carry C1a tokens and the `tokens` limb still holds them. CG7 -27, CG1 -9, CG2 -10,
      CG4 -1, is_null -42 is 89, and the remaining 18 are the C1a rows the `tokens` and
      `contradicts_oc` limbs hold. Read that last step carefully rather than as an
      addition: every one of those 18 ALSO falls in some CG slice (13 no-CG, 3 CG2, 2
      CG7), which is precisely why each contributes nothing to that slice's marginal
      drop and why the marginals sum to 89 and not to 107. The 18 are the overlap the
      generator derives independently at G22a, arrived at here from the other side.
      Every one of these drop figures is measured on the shipped anchor by the same
      machinery that evaluates the committed selector.
    """)
  end

  # --- composition: what MES-104's multi-file crosswalk made possible -------
  #
  # G17, G18, G19 and G20 are refusals that could not exist before `--edges`
  # became repeatable and a file could declare its CHECK population. Each gets
  # a positive control — the unmutated two-file build — and a mutation.

  defp composition do
    header("COMPOSITION — the four refusals the two-file crosswalk needs, each shown firing")

    require_harness!()
    client = read(@client_edges)
    resid = read(@edges)
    sites = read(@sites)
    axes = read(@c1_axes)

    out = tmp("composition-positive")
    run_crosswalk(out)
    a = read(out)
    File.rm(out)

    IO.puts("  POSITIVE  the unmutated two-file build succeeds")

    IO.puts(
      "            #{length(a["population"]["files"])} files, #{a["population"]["member_count"]} members, " <>
        "#{a["population"]["declared_check_count"]} declared checks, #{length(a["cells"])} edges"
    )

    # --- G17: one member, one home -----------------------------------------
    #
    # The probe has to get PAST two earlier guards to reach G17, and that is
    # worth stating rather than discovering. Copying a declared_unmatched row
    # into the second file is caught by G14 (a member declared unmatched
    # twice); adding any row to a file its selector does not denote is caught
    # by G15a. So the second file below denotes exactly the one member it
    # carries — `key equals <that member>` — and gives it a DIFFERENT claim, so
    # neither earlier guard has anything to say and the overlap is the only
    # defect left.
    shared = hd(client["edges"])

    probe = %{
      "schema" => "crosswalk-edges/1",
      "the_population_this_file_declares" => %{
        "members" => 1,
        "members_with_edges" => 1,
        "members_declared_unmatched" => 0,
        "checks_addressed" => 1,
        "rule" => "one member, named — a G17 probe",
        "selector" => %{
          "source" => @attribution,
          "rows_at" => "rows",
          "key_field" => "key",
          "all_of" => [
            %{
              "field" => "key",
              "test" => "equals",
              "value" => shared["member"]["register_key"]
            }
          ]
        }
      },
      "edges" => [Map.put(shared, "claim", "a second claim, so G14 has nothing to say")],
      "declared_unmatched" => []
    }

    refuses(
      "G17  the same member declared by BOTH files",
      "G17 — two edges files declare the SAME member",
      fn -> run_two(client, probe) end
    )

    refuses(
      "G14 gets there first when the overlap is a REPEATED declared_unmatched row",
      "G14 — members declared unmatched more than once",
      fn ->
        dup = Map.put(probe, "declared_unmatched", [hd(client["declared_unmatched"])])
        run_two(client, dup)
      end
    )

    # And the same file given twice, which is the cheapest way to double a
    # population without editing anything at all.
    refuses(
      "G17  the same edges FILE given to --edges twice",
      "the same edges file was given twice",
      fn ->
        path = write_tmp("same", client)

        try do
          run_crosswalk(tmp("same-twice"), edges: [path, path])
        after
          File.rm(path)
        end
      end
    )

    # --- G18: the emitting span's provenance --------------------------------
    accepted = Enum.find(axes["checks"], &(&1["emitting_span_provenance"] == "locator_row"))

    rejected =
      Enum.find(axes["checks"], &(&1["emitting_span_provenance"] == "locator_row_rejected"))

    verdict(
      "G18 has BOTH kinds of row on real data — an acceptance and a rejection",
      accepted != nil and rejected != nil
    )

    halt_unless(accepted != nil and rejected != nil)

    IO.puts(
      "            rejected: #{Enum.at(rejected["key"], 3)} — locator rung " <>
        "#{Enum.find(sites["rows"], &(&1["key"] == rejected["key"]))["rung"]} at pin level " <>
        "#{Enum.find(sites["rows"], &(&1["key"] == rejected["key"]))["rung_pin_level"]}"
    )

    refuses(
      "G18  an accepted row whose span the locator does not name",
      "span_is_not_one_the_locator_names",
      fn ->
        run_axes(mutate_axis(axes, accepted["key"], &Map.put(&1, "emitting_byte_span", [0, 10])))
      end
    )

    refuses(
      "G18  a row claiming a provenance that is not one of the two",
      "unknown_emitting_span_provenance",
      fn ->
        run_axes(
          mutate_axis(axes, accepted["key"], &Map.put(&1, "emitting_span_provenance", "trust me"))
        )
      end
    )

    refuses(
      "G18  a rejection of a span the locator DOES pin to the row",
      "rejected_a_row_level_pin",
      fn ->
        run_axes(
          mutate_axis(axes, accepted["key"], fn c ->
            c
            |> Map.put("emitting_span_provenance", "locator_row_rejected")
            |> Map.put("emitting_span_provenance_why", "because")
            |> Map.put("emitting_byte_span", [0, 10])
          end)
        )
      end
    )

    refuses(
      "G18  a rejection that gives no reason",
      "rejection_gives_no_reason",
      fn ->
        run_axes(
          mutate_axis(axes, rejected["key"], &Map.delete(&1, "emitting_span_provenance_why"))
        )
      end
    )

    refuses(
      "G18  a rejection that then uses the very span it rejected",
      "rejection_uses_the_span_it_rejected",
      fn ->
        row = Enum.find(sites["rows"], &(&1["key"] == rejected["key"]))
        span = hd(row["sites"])["byte_span"]
        run_axes(mutate_axis(axes, rejected["key"], &Map.put(&1, "emitting_byte_span", span)))
      end
    )

    # --- G19: a declared check nobody decomposed ----------------------------
    refuses(
      "G19  a DECLARED check with no axis decomposition",
      "DECLARED check population have no axis",
      fn ->
        # It has to be a BUCKET-2 check. Dropping the decomposition of a check
        # that CARRIES an edge is caught earlier, by `cells!` — an edge cannot
        # re-derive without one — so G19's content is exactly the checks with
        # NO edge, which is the set bucket 2 reports. The check stays DECLARED
        # by the client file's selector, so reporting it in bucket 2 would be
        # saying 'we looked and found no ET counterpart' about a check nobody
        # read.
        name =
          a["buckets"]["bucket_2"]["checks"]
          |> Enum.sort()
          |> hd()
          |> String.split("/")
          |> List.last()

        dropped = Enum.find(axes["checks"], &(Enum.at(&1["key"], 3) == name))

        run_axes(
          update_in(axes, ["checks"], fn cs -> Enum.reject(cs, &(&1["key"] == dropped["key"])) end)
        )
      end
    )

    refuses(
      "G19  cells! gets there first when the undecomposed check CARRIES an edge",
      "check_has_no_axis_decomposition",
      fn ->
        edged =
          Enum.find(axes["checks"], fn c ->
            Enum.any?(a["cells"], &(&1["oc_key"] == c["key"]))
          end)

        run_axes(
          update_in(axes, ["checks"], fn cs -> Enum.reject(cs, &(&1["key"] == edged["key"])) end)
        )
      end
    )

    # --- G20: an inherited token lost in transit ----------------------------
    inherited =
      Enum.find(client["declared_unmatched"], fn u ->
        String.starts_with?(u["tag"], "oc:none/no-oc-fixture-case/CG7-static-reachability")
      end)

    verdict("G20 has a live subject — a B2b token carried by a MOVED row", inherited != nil)
    halt_unless(inherited != nil)

    refuses(
      "G20  a moved row whose inherited B2b token has been re-slugged",
      "G20 —",
      fn ->
        reslugged =
          update_in(client, ["declared_unmatched"], fn us ->
            Enum.map(us, fn u ->
              if u == inherited,
                do: Map.put(u, "tag", "oc:none/no-oc-fixture-case/CG7-static-reachability-x"),
                else: u
            end)
          end)

        run_two(reslugged, resid)
      end
    )

    # --- bucket 2: the thing all of this was for ----------------------------
    b2 = a["buckets"]["bucket_2"]

    IO.puts("\n  BUCKET 2 — non-empty for the first time in this project:")

    IO.puts(
      "    #{b2["count"]} of the #{a["population"]["declared_check_count"]} declared checks carry no edge"
    )

    for tag <- b2["checks"], do: IO.puts("      #{tag}")

    verdict("bucket 2 is DECLARED and non-empty", b2["declared"] and b2["count"] > 0)
    halt_unless(b2["declared"] and b2["count"] > 0)

    # THE MUTATION THAT SHOWS IT IS NOT VACUOUS: take the check population away
    # and the same edges report bucket 2 as NOT ASKED, not as zero. That is the
    # difference between C1a's answer and this one.
    without = tmp("composition-no-checks")
    run_two_to(Map.delete(client, "the_check_population_this_file_declares"), resid, without)
    w = read(without)
    File.rm(without)

    IO.puts("\n  the SAME edges with no declared check population:")
    IO.puts("    bucket 2: #{w["buckets"]["bucket_2"]["result"]}")

    verdict(
      "without a declared universe bucket 2 is NOT REPORTED, never zero",
      w["buckets"]["bucket_2"]["declared"] == false
    )

    halt_unless(w["buckets"]["bucket_2"]["declared"] == false)

    # And the counter-mutation: declaring the checks but dropping the edges that
    # cover them grows bucket 2 rather than shrinking the universe. This is the
    # C1a defect restated — under the old derived universe, dropping an edge
    # made the universe smaller and bucket 2 stayed at zero.
    fewer = tmp("composition-fewer-edges")

    # The target has to be a DECLARED check every one of whose edge-bearing
    # members also edges elsewhere — otherwise dropping its edges drops a member
    # out of the population and G15a refuses the mutated file before bucket 2
    # is ever computed. Chosen by that property rather than hard-coded, so a
    # later ticket's edges cannot silently re-aim it (the Access.at(20) lesson).
    edges_per_member = Enum.frequencies_by(a["cells"], & &1["member"]["register_key"])

    dropped_tag =
      Enum.find(Enum.sort(a["population"]["declared_checks"]), fn tag ->
        cells = Enum.filter(a["cells"], &(&1["tag"] == tag))

        cells != [] and
          Enum.all?(cells, fn c ->
            Map.fetch!(edges_per_member, c["member"]["register_key"]) >
              Enum.count(cells, &(&1["member"]["register_key"] == c["member"]["register_key"]))
          end)
      end)

    verdict(
      "a droppable declared check exists — every member of it edges elsewhere too",
      dropped_tag != nil
    )

    halt_unless(dropped_tag != nil)
    IO.puts("            target: #{dropped_tag}")

    run_two_to(
      update_in(client, ["edges"], fn es -> Enum.reject(es, &(&1["tag"] == dropped_tag)) end)
      |> recount(),
      resid,
      fewer
    )

    f = read(fewer)
    File.rm(fewer)

    IO.puts("\n  dropping every edge on ONE declared check:")
    IO.puts("    bucket 2: #{b2["count"]} -> #{f["buckets"]["bucket_2"]["count"]}")

    verdict(
      "a declared check losing its edges GROWS bucket 2 — the universe does not shrink with it",
      f["buckets"]["bucket_2"]["count"] == b2["count"] + 1
    )

    halt_unless(f["buckets"]["bucket_2"]["count"] == b2["count"] + 1)

    IO.puts("""

      C1a's bucket 2 could not have been anything but zero: its universe was the set of
      tags its own edges carried, so the complement was taken inside the set it was taken
      from. The check above is the difference — the same edges, one declaration apart.
    """)
  end

  # The counts block is the file's statement about itself and G15b checks it,
  # so a mutation that changes the rows has to restate them or it is caught by
  # the wrong guard.
  defp recount(doc) do
    members =
      Enum.uniq(
        Enum.map(doc["edges"], & &1["member"]["register_key"]) ++
          Enum.map(doc["declared_unmatched"], & &1["member"]["register_key"])
      )

    update_in(doc, ["the_population_this_file_declares"], fn d ->
      %{
        d
        | "members" => length(members),
          "members_with_edges" =>
            doc["edges"] |> Enum.map(& &1["member"]["register_key"]) |> Enum.uniq() |> length(),
          "members_declared_unmatched" => length(doc["declared_unmatched"]),
          "checks_addressed" => doc["edges"] |> Enum.map(& &1["tag"]) |> Enum.uniq() |> length()
      }
    end)
  end

  defp mutate_axis(axes, key, fun) do
    update_in(axes, ["checks"], fn cs ->
      Enum.map(cs, fn c -> if c["key"] == key, do: fun.(c), else: c end)
    end)
  end

  defp run_axes(axes) do
    path = write_tmp("c1-axes", axes)

    try do
      run_crosswalk(tmp("axes-mutated"), c1_axes: path)
    after
      File.rm(path)
    end
  end

  defp run_two(client, resid), do: run_two_to(client, resid, tmp("two-mutated"))

  defp run_two_to(client, resid, out) do
    a = write_tmp("client", client)
    b = write_tmp("resid", resid)

    try do
      run_crosswalk(out, edges: [a, b])
    after
      File.rm(a)
      File.rm(b)
    end
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
    edges =
      case Keyword.get(overrides, :edges) do
        nil -> [@client_edges, @edges]
        one when is_binary(one) -> [one]
        many when is_list(many) -> many
      end

    Mix.Task.rerun(
      "conformance.crosswalk",
      Enum.flat_map(edges, &["--edges", &1]) ++
        [
          "--manifest",
          @manifest,
          "--denominator",
          @denominator,
          "--register",
          @register,
          "--attribution",
          Keyword.get(overrides, :attribution, @attribution),
          "--a3-axes",
          @a3_axes,
          "--c1-axes",
          Keyword.get(overrides, :c1_axes, @c1_axes),
          "--emitting-sites",
          Keyword.get(overrides, :sites, @sites),
          "--harness",
          @harness,
          "-o",
          out
        ]
    )
  end

  # The mutated CLIENT file plus the untouched residual one — the real shape.
  defp build_edges(doc) do
    path = write_tmp("edges", doc)
    out = tmp("mutated")

    try do
      run_crosswalk(out, edges: [path, @edges])
    after
      File.rm(path)
      File.rm(out)
    end
  end

  defp put_first(doc, edge), do: update_in(doc, ["edges"], fn [_ | t] -> [edge | t] end)

  defp replace(doc, old, new),
    do: update_in(doc, ["edges"], fn es -> Enum.map(es, &if(&1 == old, do: new, else: &1)) end)

  # `refuses/3` takes the FRAGMENT the refusal must contain. "It raised" is not
  # "the planted defect was caught": a mutation can trip an unrelated guard, or
  # a typo in the control itself, and a bare rescue reads both as success.
  defp refuses(label, expect, fun) do
    fun.()
    IO.puts("  DID NOT REFUSE  #{label}")
    System.halt(1)
  rescue
    e ->
      msg = Exception.message(e)

      if String.contains?(msg, expect) do
        IO.puts("  refused  #{label}\n           #{first_line(msg)}")
      else
        IO.puts("  WRONG GUARD  #{label}")
        IO.puts("           expected the refusal to name: #{inspect(expect)}")
        IO.puts("           got: #{first_line(msg)}")
        System.halt(1)
      end
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

  # --- absence: the two ZEROS C1b-ii's bucket-1 records rest on ---------------
  #
  # MES-108. Two `declared_unmatched` records assert that a search over A1's
  # manifest returned NOTHING, and a zero is the one result that looks identical
  # whether the search ran or not. So each gets both halves (A6):
  #
  #   POSITIVE CONTROL  the same predicate machinery over the same 175 rows
  #                     returns a non-zero for terms known to be present, so the
  #                     sweep demonstrably REACHED the population.
  #   MUTATION          the predicate itself is replaced by one that MUST match,
  #                     and is required to go non-zero. Without this, a sweep
  #                     that silently read an empty row set would pass the
  #                     positive control too — `Enum.filter` over `[]` is `[]`
  #                     for every predicate, including the ones that "work".
  #
  # The mutation is the limb that matters and it is the easy one to leave out:
  # a positive control run on DIFFERENT terms shares the row set but not the
  # predicate path, so it cannot distinguish "this term is absent" from "this
  # matcher cannot fire".

  # THE SEARCHED TEXT IS A1's SIX-FIELD KEY, joined with " | " — leg, scenario,
  # check_id, name, description, discriminator. Not a four-field subset: the
  # registry's `population.fields` says six, and MES-109 measured the two apart
  # the hard way. `(?i)capabilit` returns 12 over the six and 11 over the four,
  # so a pattern calibrated on one field set and re-run over the other silently
  # changes its own population — which is why the control compares the RECORDED
  # control figures against the measured ones rather than only checking they are
  # non-zero. That comparison is what caught it.
  #
  # The separator is load-bearing too: several registry patterns use
  # `[^|]{0,40}` to mean "within this row's own field", and that only means
  # anything if the fields are actually delimited.
  @searched_fields ~w(leg scenario check_id name description discriminator)

  defp absence do
    header("ABSENCE — every registered search re-run over its own named population")

    # MES-109 (C1b-iii) rewrote this from a HAND-LISTED PAIR to a sweep over the
    # registry itself. The old form named two patterns in the control and drove
    # them; a third record added to an edges file would have been outside it
    # without anyone noticing, which is the self-declaring-population defect.
    # The universe is now the `absence_searches` block of every edges file
    # given, and the id resolution in both directions is the generator's (G23c),
    # so an entry the control does not reach is an entry no row names.
    rows = manifest_rows()
    halt_unless(length(rows) == 175)

    entries =
      Enum.flat_map([@client_edges, @edges], fn path ->
        Enum.map(read(path)["absence_searches"] || [], &{path, &1})
      end)

    IO.puts(
      "  #{length(entries)} registered searches across #{length([@client_edges, @edges])} edges files"
    )

    IO.puts("  manifest population: #{@manifest} — #{length(rows)} check rows\n")

    halt_unless(entries != [])

    for {path, e} <- entries do
      {population_label, hits, total} = run_search(e, rows)

      IO.puts("  #{e["id"]}  #{e["kind"]}  — #{population_label}")
      IO.puts("    #{e["pattern"]} -> #{hits}")

      verdict("#{e["id"]}: THE ZERO, re-measured here and not read off the file", hits == 0)
      halt_unless(hits == 0)

      verdict(
        "#{e["id"]}: and the file RECORDS that zero — a registry entry is a search that found none",
        e["hits"] == 0
      )

      halt_unless(e["hits"] == 0)

      # POSITIVE CONTROL — the entry's OWN controls, re-run here. The entry
      # names them, so a search whose controls were chosen to be vacuous is
      # visible in the file rather than hidden in this script.
      pcs =
        for c <- e["positive_controls"], do: {c["term"], elem(run_pattern(e, c["term"], rows), 0)}

      IO.puts(
        "    positive control, same population same machinery: " <>
          Enum.map_join(pcs, ", ", fn {t, n} -> "#{t} -> #{n}" end)
      )

      verdict(
        "#{e["id"]}: the sweep REACHED the population — the zero is the content's, not the sweep's",
        pcs != [] and Enum.all?(pcs, fn {_t, n} -> n > 0 end)
      )

      halt_unless(pcs != [] and Enum.all?(pcs, fn {_t, n} -> n > 0 end))

      # AND the file's recorded control figures must be the ones measured here.
      # A positive control whose number was typed rather than measured is the
      # same defect one level down.
      recorded = Enum.map(e["positive_controls"], &{&1["term"], &1["hits"]})

      verdict(
        "#{e["id"]}: the recorded control figures ARE the measured ones",
        recorded == pcs
      )

      halt_unless(recorded == pcs)

      # MUTATION — a predicate that cannot fail to match.
      {_l, all, _t} = run_search(%{e | "pattern" => "(?s)."}, rows)

      IO.puts("    mutation, a predicate that must match everything: (?s). -> #{all}")

      verdict(
        "#{e["id"]}: the matcher CAN fire, over the whole population (#{total})",
        all == total
      )

      halt_unless(all == total)

      verdict("#{e["id"]}: names a near miss", is_binary(e["near_miss"]) and e["near_miss"] != "")
      halt_unless(is_binary(e["near_miss"]) and e["near_miss"] != "")
      IO.puts("    (#{path})\n")
    end

    fixture = Enum.count(entries, fn {_p, e} -> e["kind"] == "no-oc-fixture-case" end)

    verdict(
      "BOTH `oc:none` slugs are exercised — #{fixture} fixture-case searches and " <>
        "#{length(entries) - fixture} scenario searches, so the two are kept apart by use " <>
        "and not only by convention",
      fixture > 0 and fixture < length(entries)
    )

    halt_unless(fixture > 0 and fixture < length(entries))

    near_miss_census()
  end

  # A registry entry names its own population, and there are two kinds. A
  # `no-oc-scenario` search runs over A1's 175 manifest rows; a
  # `no-oc-fixture-case` search runs over a BYTE SPAN of the pinned harness
  # build, because the question is what a fixture contains and the fixture is
  # code. Both go through one function so a kind the control does not handle is
  # a crash rather than a silent skip.
  defp run_search(e, rows), do: run_pattern_labelled(e, e["pattern"], rows)

  defp run_pattern(e, pattern, rows) do
    {_l, n, t} = run_pattern_labelled(e, pattern, rows)
    {n, t}
  end

  defp run_pattern_labelled(e, pattern, rows) do
    re = Regex.compile!(pattern)

    case e["population"] do
      %{"kind" => "manifest_rows"} ->
        {"#{length(rows)} manifest rows", length(sweep(rows, re)), length(rows)}

      %{"kind" => "harness_bytes", "byte_span" => [from, to]} ->
        text = harness_bytes(from, to)
        # `byte_size`, not `String.length`. `Regex.compile!/1` without the `u`
        # modifier matches in BYTE mode, so the `(?s).` mutation returns one hit
        # per BYTE and a grapheme count would be 6 short over this span's
        # non-ASCII (measured: 5104 graphemes, 5110 bytes). Comparing the
        # mutation against the wrong unit would have made the one limb that
        # proves the matcher can fire fail on a correct search.
        {"harness bytes [#{from},#{to}]", length(Regex.scan(re, text)), byte_size(text)}

      other ->
        IO.puts("  UNKNOWN POPULATION KIND in #{e["id"]}: #{inspect(other)}")
        System.halt(1)
    end
  end

  defp harness_bytes(from, to) do
    require_harness!()
    {:ok, h} = Locator.load(@harness)
    Locator.bytes(h, {from, to})
  end

  # The near miss C1b-ii records against the CG2 zero, MEASURED rather than
  # quoted — and it is the figure cg-reconciliation.md §2 states as "seven".
  #
  # ONE FACT, READ ONCE. The two censuses' `expected` blocks are the SAME
  # frozen set and that is asserted here rather than assumed: reading the
  # figure out of both and printing two agreeing lines would look like two
  # measurements corroborating each other, when it is one datum shown twice.
  # The agreement is worth pinning, but as an identity, not as corroboration.
  defp near_miss_census do
    client_expected = read("docs/conformance/client-2026-07-28.json")["expected"]
    server_expected = read("docs/conformance/server-2026-07-28.json")["expected"]

    verdict(
      "the two censuses carry the SAME frozen `expected` block — so this is one fact, not two",
      client_expected == server_expected
    )

    halt_unless(client_expected == server_expected)

    ns = client_expected["not_scored"]
    ext = Enum.filter(ns, &(&1["reason"] == "extension"))
    on_client = Enum.filter(ns, &(&1["leg"] == "client"))
    ext_on_client = Enum.filter(on_client, &(&1["reason"] == "extension"))

    IO.puts(
      "  near miss: #{length(ns)} not_scored entries, #{length(ext)} carry `extension` " <>
        "(#{length(on_client)} entries sit on the client leg, #{length(ext_on_client)} of them `extension`)"
    )

    verdict(
      "the `extension` count is 16, NOT the 7 cg-reconciliation.md §2 states",
      length(ext) == 16
    )

    halt_unless(length(ext) == 16)

    # WHERE THE 7 CAME FROM — named, because a wrong figure with no account of
    # its origin gets re-derived the same way by the next reader.
    verdict(
      "7 is the CLIENT LEG's not_scored ENTRY count, and only 6 of those 7 carry `extension`",
      length(on_client) == 7 and length(ext_on_client) == 6
    )

    halt_unless(length(on_client) == 7 and length(ext_on_client) == 6)

    IO.puts("""

      Every zero stands, and every one is now a zero with a reach shown and a matcher
      shown able to fire. The near-miss figure does NOT stand as written elsewhere:
      cg-reconciliation.md §2 says `"reason": "extension"` sits on "seven" not_scored
      scenarios, and it sits on SIXTEEN — 6 on the client leg (`auth/*`) and 10 on the
      server leg (`tasks-*`). Seven is the client leg's not_scored ENTRY count, of which
      only 6 carry that reason; the seventh is `added-after-release`. The censuses have
      not moved since MES-57 (3e487f8), so this is not drift and re-measuring will not
      fix it. The ZEROS the CG2 records rest on are untouched — what was wrong is the
      near miss named beside them, which is why this control measures the near miss too.
      Reported as a finding against a change-controlled document, not edited from here.

      WHAT THIS CONTROL DOES NOT ESTABLISH. That a search was well-chosen. It re-runs
      the pattern each entry names over the population that entry names, and requires
      a zero, a reached population and a matcher that can fire. Whether the population
      was the right place to look, and whether a given member's claim is really what
      the search looked for, are judgements — the second is written out per row in
      `why_this_search_is_this_claims_search` so a reader can disagree with it, and no
      control here can reach either.
    """)
  end

  defp manifest_rows do
    for s <- read(@manifest)["scenarios"], c <- s["checks"] || [] do
      [leg, scenario, check_id, name, description, discriminator] = c["key"]

      Map.merge(c, %{
        "leg" => leg,
        "scenario" => scenario,
        "check_id" => check_id,
        "name" => name,
        "description" => description,
        "discriminator" => discriminator || ""
      })
    end
  end

  defp sweep(rows, pattern) do
    Enum.filter(rows, &Regex.match?(pattern, row_text(&1)))
  end

  defp row_text(r), do: @searched_fields |> Enum.map_join(" | ", &(r[&1] || ""))

  # --- totality: the client leg is CLOSED, and the closure can go red -------
  #
  # MES-109 (C1b-iii). Two guards land here and neither is worth anything
  # without the other's failure mode being visible, so this mode is built round
  # ONE measurement: the CG9 separation. It is what says G22b is not entailed by
  # G15a — the X7 shape — and it is run on the same mutated input, in the same
  # run, as the unmutated build.
  #
  # WHAT THIS MODE CANNOT SHOW, and it is stated here rather than discovered:
  # G22b does NOT fire on a dropped row. G15a gets there first, because a
  # dropped row shrinks the file's members below its own selector's denotation.
  # That is not a weakness — it is the division of labour — but "G22b refuses a
  # missing member" would be a false description of it, so the control drives
  # the dropped-row case too and ASSERTS WHICH GUARD FIRES. G22b's unique reach
  # is exactly one shape: a B2b row on the declared leg that the file's
  # union-shaped selector does not denote. That is what CG9 is.
  defp totality do
    header("TOTALITY — the client leg closed by refusal, and each refusal shown firing")

    require_harness!()
    client = read(@client_edges)
    src = read(@attribution)

    out = tmp("totality-positive")
    {os_out, status} = os_crosswalk(out, [])
    a = read(out)
    File.rm(out)

    lt = Enum.find(a["population"]["files"], & &1["leg_totality"]["declared"])["leg_totality"]

    IO.puts("  POSITIVE  the unmutated build succeeds at the OS exit status: #{status}")

    IO.puts(
      "            #{lt["leg"]} leg total at #{lt["members"]} members, " <>
        "#{length(lt["slices"])} slices, #{lt["cover_not_partition"]["in_more_than_one_slice"]} in two"
    )

    verdict("the unmutated build exits 0", status == 0)
    halt_unless(status == 0)
    halt_unless(String.contains?(os_out, "CROSSWALK"))

    verdict(
      "and it asserts a leg at all — a run asserting none would pass every case below vacuously",
      lt["declared"] == true and lt["members"] > 0
    )

    halt_unless(lt["declared"] == true and lt["members"] > 0)

    # --- THE CG9 SEPARATION -------------------------------------------------
    #
    # A new B2b row on the client leg carrying a `cg` no limb of the file's
    # union-shaped selector names. G15a asks "is the population what MY
    # selector denotes?" and the answer is still yes. G22b asks "is my selector
    # the leg?" and the answer is now no. One input, two questions, two
    # verdicts — which is the whole argument for not simplifying the top-level
    # selector to a bare `leg equals client`.
    cg9 = %{
      "key" => "MCP.CG9ProbeTest/test a client member B2b knows about and no limb denotes",
      "leg" => "client",
      "leg_reason" => "a CG9 probe planted by crosswalk_controls.exs totality",
      "cg" => "CG9",
      "cg_basis" => "planted",
      "tokens" => [],
      "contradicts_oc" => nil
    }

    mutated = update_in(src, ["rows"], &(&1 ++ [cg9]))

    member_sel = client["the_population_this_file_declares"]["selector"]
    {:ok, still} = Crosswalk.select(member_sel, mutated)
    file_members = lt["members"]

    IO.puts("\n  CG9  a client row carrying a `cg` no limb of the union names:")

    IO.puts(
      "       G15a — the file's OWN selector over the mutated anchor: " <>
        "#{length(still)} denoted vs #{file_members} rows in the file"
    )

    verdict(
      "G15a is GREEN on the mutation — #{file_members} against #{file_members}, set-equal both ways",
      length(still) == file_members
    )

    halt_unless(length(still) == file_members)

    {:ok, leg_only} =
      Crosswalk.select(
        %{
          "source" => @attribution,
          "rows_at" => "rows",
          "key_field" => "key",
          "all_of" => [%{"field" => "leg", "test" => "equals", "value" => "client"}]
        },
        mutated
      )

    IO.puts(
      "       G22b — `leg equals client` over the same mutated anchor: " <>
        "#{length(leg_only)} denoted vs #{file_members} rows in the file"
    )

    verdict(
      "G22b's question has a DIFFERENT answer on the same input — #{length(leg_only)} against #{file_members}",
      length(leg_only) == file_members + 1
    )

    halt_unless(length(leg_only) == file_members + 1)

    # And the generator itself, at the OS exit status, on that same input.
    #
    # THE ANCHOR IS SUBSTITUTED BY RETARGETING, NOT BY EDITING THE REPO.
    # `selected!/4` refuses a run whose `--attribution` is not the path the
    # selector NAMES — that is G15's own anti-substitution limb and it fires
    # before anything here could — so the mutated anchor is written to a temp
    # file and every `source` in a temp COPY of the edges file is retargeted at
    # it. Nothing under the repo is written, which is deliberate: a seat that
    # died mid-run would otherwise leave a mutated register behind (S8-14).
    # The only semantic difference between this pair and the committed one is
    # the single planted row.
    attr_path = write_tmp("attribution-cg9", mutated)
    edges_path = write_tmp("edges-cg9", retarget(client, attr_path))

    try do
      os_refuses(
        "G22b  a client member B2b has and no edges file carries",
        ["G22b", "is NOT total over it", cg9["key"]],
        fn out ->
          os_crosswalk(out, attribution: attr_path, edges: [edges_path, @edges])
        end
      )
    after
      File.rm(attr_path)
      File.rm(edges_path)
    end

    verdict(
      "SO G22b IS NOT ENTAILED BY G15a — one input, G15a green and G22b red, measured in this run",
      length(still) == file_members and length(leg_only) != file_members
    )

    halt_unless(length(still) == file_members and length(leg_only) != file_members)

    # --- the cover ----------------------------------------------------------
    refuses(
      "G22a  a slice dropped from the cover, leaving members no declared rule reaches",
      "G22a — the UNION of",
      fn ->
        build_edges(
          update_in(client, ["the_sub_populations_this_file_records", "entries"], fn es ->
            Enum.reject(es, &String.contains?(&1["ticket"], "C1b-iii"))
          end)
        )
      end
    )

    refuses(
      "G22  the leg declared with the sub-populations removed — half a claim is refused",
      "half-declares a leg totality",
      fn -> build_edges(Map.delete(client, "the_sub_populations_this_file_records")) end
    )

    # --- and the case G22b does NOT catch, named rather than implied --------
    dropped = update_in(client, ["declared_unmatched"], &Enum.drop(&1, -1))

    refuses(
      "G15a  a member ROW dropped — and it is G15a that fires, NOT G22b",
      "G15a — the population",
      fn -> build_edges(recount(dropped)) end
    )

    IO.puts(
      "           G22b never sees it: a dropped row shrinks the file below its own selector's\n" <>
        "           denotation, so the earlier guard answers first. G22b's unique reach is the\n" <>
        "           CG9 shape above — a row on the leg that the union does not denote."
    )

    # --- G23, the absence-search guard --------------------------------------
    with_search =
      Enum.find_index(client["declared_unmatched"], & &1["the_search_that_found_none"])

    refuses(
      "G23a  a bucket-1 row with its search removed — leg-wide, no exception list",
      "G23a —",
      fn ->
        build_edges(
          update_in(client, ["declared_unmatched"], fn rows ->
            List.update_at(rows, with_search, &Map.delete(&1, "the_search_that_found_none"))
          end)
        )
      end
    )

    registered = Enum.find_index(client["declared_unmatched"], & &1["search_id"])

    refuses(
      "G23b  a `search_id` that resolves to no registry entry",
      "search_id_resolves_to_nothing",
      fn ->
        build_edges(
          update_in(client, ["declared_unmatched"], fn rows ->
            List.update_at(rows, registered, &Map.put(&1, "search_id", "S99"))
          end)
        )
      end
    )

    refuses(
      "G23b  a registry entry recording a NON-zero — an entry IS a search that found none",
      "entry_does_not_record_zero",
      fn ->
        build_edges(
          update_in(client, ["absence_searches"], fn [e | rest] -> [%{e | "hits" => 1} | rest] end)
        )
      end
    )

    refuses(
      "G23b  a registry entry with its near miss removed — a bare zero is a grep",
      "entry_names_no_near_miss",
      fn ->
        build_edges(
          update_in(client, ["absence_searches"], fn [e | rest] ->
            [Map.delete(e, "near_miss") | rest]
          end)
        )
      end
    )

    refuses(
      "G23b  a registry entry with no positive control — a zero whose sweep was never shown to run",
      "entry_has_no_positive_control",
      fn ->
        build_edges(
          update_in(client, ["absence_searches"], fn [e | rest] ->
            [%{e | "positive_controls" => []} | rest]
          end)
        )
      end
    )

    refuses(
      "G23d  an entry whose KIND is not the reason slug its row's own tag carries",
      "entry_kind_is_not_the_rows_reason_slug",
      fn ->
        build_edges(
          update_in(client, ["absence_searches"], fn [e | rest] ->
            [%{e | "kind" => "no-oc-fixture-case"} | rest]
          end)
        )
      end
    )

    refuses(
      "G23b  a row whose prose COPY of the near miss has drifted from its entry (D4)",
      "row_copy_has_drifted_from_the_entry",
      fn ->
        build_edges(
          update_in(client, ["declared_unmatched"], fn rows ->
            List.update_at(
              rows,
              registered,
              &Map.put(&1, "the_near_miss_that_is_not_a_counterpart", "a different near miss")
            )
          end)
        )
      end
    )

    refuses(
      "G23c  a registry entry no row names — a measurement in search of a claim",
      "G23c —",
      fn ->
        orphan = client["absence_searches"] |> hd() |> Map.put("id", "S00")

        build_edges(update_in(client, ["absence_searches"], &(&1 ++ [orphan])))
      end
    )

    # --- and the tree is as it was ------------------------------------------
    after_out = tmp("totality-after")
    {_o, after_status} = os_crosswalk(after_out, [])
    same = File.read!(after_out) == File.read!(@crosswalk_out)
    File.rm(after_out)

    verdict("after every mutation the unmutated build still exits 0", after_status == 0)
    halt_unless(after_status == 0)

    verdict(
      "and reproduces the COMMITTED artefact byte for byte — nothing on disk was mutated",
      same
    )

    halt_unless(same)

    IO.puts("""

      The client leg is closed by a refusal rather than by a sentence. Every ET-CC
      member B2b puts on it carries a row, and a member that does not REFUSES THE
      BUILD — checked against B2b afresh, by set, in both directions.

      THE CG9 CASE IS THE LOAD-BEARING ONE. Had the top-level selector been
      simplified to a bare `leg equals client` once the four slices happened to
      cover the leg, G22b would ask G15a's question in G15a's words and could never
      fire on anything: the X7 shape, a guard as empty as one nobody calls. The
      measurement above is what rules that out, and it is a measurement rather than
      an argument — one anchor, two selectors, two answers, in this run.

      WHAT A GREEN HERE IS NOT. Evidence that any adjudication is right. A leg every
      member of which was adjudicated wrongly passes G22b exactly as firmly, and the
      A3 §6 state-4 guard over this population stays entailed by G15a and unable to
      fire (X7). What is new is that the population it cannot fire over is provably
      the whole leg and not a slice somebody chose.
    """)
  end

  # Point every selector in `doc` that names the committed attribution register
  # at `path` instead. Recursive over the whole document rather than over the
  # two blocks that happen to carry one today: the sub-population cover holds
  # one selector per entry, and a new entry whose source this missed would be
  # refused by G15's anti-substitution limb rather than silently retargeted —
  # but the failure would read as a defect in the guard under test.
  defp retarget(%{} = m, path) do
    m
    |> Enum.map(fn
      {"source", @attribution} -> {"source", path}
      {k, v} -> {k, retarget(v, path)}
    end)
    |> Map.new()
  end

  defp retarget(l, path) when is_list(l), do: Enum.map(l, &retarget(&1, path))
  defp retarget(other, _path), do: other

  defp os_crosswalk(out, overrides) do
    edges =
      Enum.flat_map(Keyword.get(overrides, :edges, [@client_edges, @edges]), &["--edges", &1])

    System.cmd(
      "mix",
      ["conformance.crosswalk"] ++
        edges ++
        [
          "--manifest",
          @manifest,
          "--denominator",
          @denominator,
          "--register",
          @register,
          "--attribution",
          Keyword.get(overrides, :attribution, @attribution),
          "--a3-axes",
          @a3_axes,
          "--c1-axes",
          @c1_axes,
          "--emitting-sites",
          @sites,
          "--harness",
          @harness,
          "-o",
          out
        ],
      stderr_to_stdout: true
    )
  end

  # The OS-level twin of `refuses/3`. An in-VM rescue shows the message; only a
  # child process shows that the GENERATOR ITSELF exits non-zero, which is what
  # a caller in a shell would see. Both limbs are required: a non-zero status
  # with the wrong message is a mutation that tripped some other guard.
  defp os_refuses(label, expected, fun) do
    out = tmp("os-refuse")
    {text, status} = fun.(out)
    File.rm(out)

    if status == 0 do
      IO.puts("  DID NOT REFUSE  #{label} — exited 0")
      System.halt(1)
    end

    case Enum.reject(expected, &String.contains?(text, &1)) do
      [] ->
        IO.puts("  refused  #{label}  (OS exit #{status})")

      missing ->
        IO.puts("  WRONG GUARD  #{label}")
        IO.puts("           expected the message to carry: #{inspect(missing)}")
        System.halt(1)
    end
  end

  # --- citations: every evidence quote, lifted live and compared ------------
  #
  # MES-108. Ruling 7 says an address is not evidence, the bytes at it are. CR-3
  # then caught two quotes in C1b-i that were not the bytes at their address (a
  # dropped module prefix), and the general byte-at-address guard is MES-112 and
  # is not built. So until it is, this runs the comparison MECHANICALLY rather
  # than leaving it to a seat's eye.
  #
  # TWO SIDES, TWO ANCHORS, and a quote must be verbatim at an address the
  # evidence ITSELF names — not merely present somewhere:
  #
  #   ET side  against the cited `file.exs:N` / `:N-M` span in the repo.
  #   OC side  against the live harness build, restricted to the byte spans the
  #            axis row FOR THIS EDGE'S TAG addresses. Not "somewhere in 800KB":
  #            a quote that is only findable by searching the whole build is a
  #            quote with no address, which is the thing ruling 7 forbids.
  #
  # A BARE `:N` CONTINUATION IS A FAILURE, not a lookup. `:262` after a full
  # citation earlier in the same string has no syntactic referent — S9's
  # bare-continuation finding — and resolving it against the nearest preceding
  # file name is guessing. Two of C1b-ii's own drafts carried one; both were
  # rewritten in full rather than resolved by proximity.
  #
  # WHAT IT DOES NOT COVER, stated rather than implied. It compares after
  # collapsing runs of whitespace, so it accepts a quote the formatter has
  # line-wrapped at a different point than the author did; that is deliberate
  # (the alternative reddens on `mix format`) and it means the check is on the
  # BYTES modulo layout, not on the layout. It only looks at backtick-delimited
  # spans containing `=`, `(`, `[`, `!==` or `===` — a prose phrase in backticks
  # is not treated as a quote, so an inaccurate paraphrase passes. And it says
  # nothing about whether the quote SUPPORTS the verdict it is filed under.

  @quote_re ~r/`((?:[^`]|`[^`]*`(?=[^`]*`))+?)`(?!`)/
  @cite_re ~r/([a-z0-9_]+\.exs?):(\d+)(?:-(\d+))?/
  @bare_cite_re ~r/(?<![\w.])(?<!\.exs)(?<!\.ex):(\d+)\b/

  defp citations do
    header("CITATIONS — every evidence quote lifted live and compared by == (ruling 7)")

    require_harness!()
    client = read(@client_edges)
    axes = read(@c1_axes)["checks"] ++ read(@a3_axes)["checks"]
    build = File.read!(@harness)

    records =
      client["edges"] ++ client["declared_unmatched"] ++ client["claims_without_an_edge"]

    mine = Enum.filter(records, &authored_here?/1)

    IO.puts(
      "  #{length(records)} records in #{Path.basename(@client_edges)}, " <>
        "#{length(mine)} authored by C1b-ii or C1b-iii\n"
    )

    halt_unless(mine != [])

    {et, oc, problems} = audit(mine, axes, build)

    IO.puts("  ET side  #{et} quotes verbatim at their cited test-file line spans")
    IO.puts("  OC side  #{oc} quotes verbatim inside the axis row's own addressed harness spans")

    verdict(
      "all #{et + oc} quotes C1b-ii and C1b-iii authored are verbatim at an address the evidence names",
      problems == []
    )

    for p <- problems, do: IO.puts("    #{inspect(p)}")
    halt_unless(problems == [])

    # POSITIVE CONTROL. `problems == []` is also what an audit that read nothing
    # returns, so the sweep is shown to have reached the quotes: every one of
    # MES-108's edges must have contributed at least one, and the total must be
    # the number counted independently by walking the regex over the same rows.
    counted =
      mine
      |> Enum.map(&length(source_quotes(&1["evidence"] || "")))
      |> Enum.sum()

    IO.puts("\n  POSITIVE  #{counted} source-shaped quotes found by an independent count")

    verdict(
      "the audit compared every quote the records carry — #{et + oc} of #{counted}",
      et + oc == counted and counted > 0
    )

    halt_unless(et + oc == counted and counted > 0)

    # MUTATION 1 — a quote that is not the bytes at its address. This is CR-3's
    # exact defect, planted: the module prefix dropped from a real assertion.
    mutated =
      Enum.map(mine, fn r ->
        Map.update(r, "evidence", nil, fn ev ->
          String.replace(ev, "HeaderMirror.decode_value(header)", "decode_value(header)")
        end)
      end)

    {_, _, caught} = audit(mutated, axes, build)

    IO.puts("\n  MUTATION  a module prefix dropped from one quote (CR-3's own defect):")
    for p <- caught, do: IO.puts("    #{inspect(p)}")

    verdict("the dropped prefix is CAUGHT, and named", caught != [])
    halt_unless(caught != [])

    # MUTATION 2 — the address moved by one line, the bytes untouched. A check
    # that only asked "is this text anywhere in the file" would pass this, and
    # it is the drift line citations actually suffer (a commit inserting a line
    # above them). This is why the comparison is against the CITED SPAN.
    shifted =
      Enum.map(mine, fn r ->
        Map.update(
          r,
          "evidence",
          nil,
          &String.replace(&1, "routing_headers_test.exs:244", "routing_headers_test.exs:245")
        )
      end)

    {_, _, drifted} = audit(shifted, axes, build)

    IO.puts("\n  MUTATION  one citation moved by a single line, the bytes unchanged:")
    for p <- drifted, do: IO.puts("    #{inspect(p)}")

    verdict(
      "an off-by-one ADDRESS is caught even though the bytes are still in the file",
      drifted != []
    )

    halt_unless(drifted != [])

    # MUTATION 3 — a bare `:N` continuation, which is not a wrong address but an
    # unresolvable one. It must be a failure and not a silent skip.
    bared =
      Enum.map(mine, fn r ->
        Map.update(
          r,
          "evidence",
          nil,
          &String.replace(&1, "and routing_headers_test.exs:223 asserts", "and :223 asserts")
        )
      end)

    {_, _, unresolvable} = audit(bared, axes, build)

    IO.puts("\n  MUTATION  a citation reduced to a bare `:N` with no file:")
    for p <- unresolvable, do: IO.puts("    #{inspect(p)}")

    verdict("a bare continuation is a FAILURE, not a lookup by proximity", unresolvable != [])
    halt_unless(unresolvable != [])

    IO.puts("""

      WHAT THIS IS AND IS NOT. It is the mechanical half of ruling 7, run at this seat
      over the rows THIS TICKET authored — MES-108 ran it before committing, and it
      caught two defects in its own drafts (a harness quote checked against a test file,
      and two bare `:N` continuations) which were fixed rather than argued. MES-109 ran
      it and it caught two more, both in its own five new edges: a COMPOSED quote —
      `Protocol.encode(Request.new(1, "tools/list", %{"cursor" => "abc"}))`, which reads
      exactly like source and appears nowhere in the file, because the call and the
      argument are on two different lines — and a nested-backtick span that made the
      quote regex report a fragment neither the author nor the file ever wrote. Both are
      ruling 7 defects that a careful read would have passed: the first is a plausible
      paraphrase of two real lines, and that is the kind a human eye is worst at.

      It is NOT MES-112, AND MES-112 HAS SINCE LANDED. MES-112 is G30, the guard INSIDE
      the generator, over every row of every edges file, where a bad citation cannot be
      committed at all — `MCP.Conformance.CitationVerbatim`, with its own controls in
      `conformance/controls/citation_verbatim_controls.exs`.

      WHAT THIS PARAGRAPH USED TO SAY, and why it no longer does. It reported that over
      the inherited C1a and C1b-i rows this same audit found 18 quotes it could not
      place — 8 stale addresses, 5 ellipsis paraphrases, 3 prose descriptions quoted as
      if source, 2 bare continuations — and that re-addressing them was not MES-108's to
      do, so they were REPORTED and left. MES-112 fixed all 18 (8 re-addressed, 2 bares
      written out in full, 2 re-lifted, 6 de-quoted; the classification moved because
      G30 separates an elision from a wrong address, and because one `prose` case turned
      out to be real bytes OUTSIDE the row's addressed spans). So the number is now zero
      and the sentence is kept as history rather than as a live count.

      THIS MODE STILL SCOPES ITSELF TO MES-108'S AND MES-109'S ROWS, and that is no
      longer a way of not going red on other people's work — G30 now quantifies over
      every row, so nothing is left unadjudicated by scope. What it remains is a SECOND,
      INDEPENDENT implementation of the same comparison over the rows those tickets
      authored: written before G30 and not sharing its code, so it corroborates rather
      than restates. If the two ever disagree, one of them is wrong and that is worth
      knowing.
    """)
  end

  # WHO WROTE THIS ROW, and MES-109 had to change how the question is asked.
  #
  # C1b-ii answered it by GUESSING from the tag, and the guess held only
  # because its rows happened to carry tags no earlier ticket used. C1b-iii's
  # do not: its `a non-32022 error is never retried` edge carries the SAME
  # `ClientRetrySupportedVersion` tag as four inherited C1a rows, so no tag
  # predicate can separate the row this ticket wrote from the rows it did not —
  # and a predicate that pulled the inherited ones in would red the audit over
  # work it is not adjudicating, while one that left them out would silently
  # drop the new row. So C1b-iii's records carry `authored_by`, written by the
  # author, and the tag heuristic stays only for C1b-ii's rows, which predate
  # the field.
  defp authored_here?(r), do: mes_108_row?(r) or mes_109_row?(r)

  defp mes_109_row?(r), do: String.contains?(r["authored_by"] || "", "MES-109")

  defp mes_108_row?(r) do
    tag = r["tag"] || ""

    (String.contains?(tag, "http-standard-headers") or
       String.contains?(tag, "json-schema-ref-no-deref") or
       String.contains?(tag, "/CG2-") or String.contains?(tag, "/CG1-") or
       String.contains?(r["owner"] || "", "C1b-ii")) and not mes_109_row?(r)
  end

  defp audit(records, axes, build) do
    Enum.reduce(records, {0, 0, []}, fn r, {et, oc, bad} ->
      ev = r["evidence"] || ""
      label = String.slice(r["claim"] || r["tag"] || "?", 0, 50)

      bare =
        for [_, n] <- Regex.scan(@bare_cite_re, ev),
            do: {:bare_citation_has_no_file, label, ":" <> n}

      et_window = cited_window(ev)
      oc_window = axis_window(r["tag"], axes, build)

      {e, o, q_bad} =
        Enum.reduce(source_quotes(ev), {0, 0, []}, fn q, {e, o, acc} ->
          sq = squash(q)

          cond do
            String.contains?(et_window, sq) -> {e + 1, o, acc}
            String.contains?(oc_window, sq) -> {e, o + 1, acc}
            true -> {e, o, [{:not_verbatim_at_any_cited_address, label, q} | acc]}
          end
        end)

      {et + e, oc + o, bad ++ bare ++ Enum.reverse(q_bad)}
    end)
  end

  defp source_quotes(ev) do
    for [_, q] <- Regex.scan(@quote_re, ev),
        Regex.match?(~r/[=(\[]|!==|===/, q),
        do: q
  end

  defp cited_window(ev) do
    for [_, file, from, to] <- Regex.scan(@cite_re, ev, capture: :all) |> pad_captures() do
      case find_source(file) do
        nil ->
          ""

        path ->
          lines = path |> File.read!() |> String.split("\n")
          a = String.to_integer(from)
          b = if to == "", do: a, else: String.to_integer(to)
          lines |> Enum.slice((a - 1)..(b - 1)//1) |> Enum.join("\n") |> squash()
      end
    end
    |> Enum.join(" || ")
  end

  defp pad_captures(scans),
    do: Enum.map(scans, fn c -> c ++ List.duplicate("", 4 - length(c)) end)

  defp find_source(basename) do
    ["test", "lib", "conformance"]
    |> Enum.flat_map(&Path.wildcard(Path.join([&1, "**", basename])))
    |> List.first()
  end

  defp axis_window(nil, _axes, _build), do: ""

  defp axis_window(tag, axes, build) do
    name = tag |> String.split("/") |> List.last()

    for c <- axes, Enum.at(c["key"], 3) == name, reduce: "" do
      acc ->
        spans =
          [c["emitting_byte_span"], get_in(c, ["emitting_site", "dist_byte_span"])] ++
            Enum.map(c["context_excerpts"] || [], & &1["byte_span"])

        bytes =
          spans
          |> Enum.reject(&is_nil/1)
          |> Enum.map_join(" || ", fn [a, b] -> binary_part(build, a, b - a) end)

        acc <> " || " <> bytes <> " || " <> (c["evaluator_excerpt"] || "")
    end
    |> squash()
  end

  defp squash(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()

  # --- statements: G21, the population figures this generator's own prose states
  #
  # CR-5 on MES-108. `trust_status` shipped `48-member / 29-declared-check` into
  # the committed artefact over a 68/39 population, and `crosswalk_test.exs`
  # asserted that literal against itself, so nothing went red. It is CR-1 on
  # MES-104 recurring one ticket later in the one file CR-1's remedy did not
  # reach: the projector's `:population_statement` guards the twelve VIEWS, and
  # the generator's own statements were guarded by nobody.
  #
  # THE MUTATIONS ARE APPLIED TO THE MECHANISM, not to an input file, for the
  # reason `pins` gives: no input can produce the state. A stale literal is a
  # disagreement between prose the generator authors and figures the generator
  # derives, and both sides are in the module. Nothing on disk is touched — the
  # module is recompiled in this VM and restored in an `after`, so a death
  # mid-run cannot leave the shared clone mutated (S8-14).

  @crosswalk_src "conformance/lib/mix/tasks/conformance.crosswalk.ex"
  @crosswalk_lib "conformance/lib/mcp/conformance/crosswalk.ex"

  defp statements do
    header("G21 — every population figure this generator's own prose states, against the tree")

    require_harness!()

    a = read(@crosswalk_out)

    inputs =
      Crosswalk.string_set(
        Enum.map(
          [
            @client_edges,
            @edges,
            @c1_axes,
            @a3_axes,
            @manifest,
            @denominator,
            @register,
            @attribution,
            @sites
          ],
          &read/1
        )
      )

    authored = Crosswalk.authored_statements(a, inputs)

    all_claims =
      Enum.filter(Crosswalk.strings_at(a), &(Crosswalk.population_claims(elem(&1, 1)) != []))

    data = length(all_claims) - length(authored)

    IO.puts("  claim-bearing strings in the committed artefact: #{length(all_claims)}")
    IO.puts("    AUTHORED by the generator (in no input document):  #{length(authored)}")
    IO.puts("    carried through from an input document:            #{data}")

    for {path, _t, claims} <- Enum.take(Enum.sort(authored), 20) do
      IO.puts("      #{String.pad_trailing(path, 46)} #{inspect(Enum.map(claims, &elem(&1, 1)))}")
    end

    # POSITIVE CONTROL for the scan's REACH. A scan that read nothing reports the
    # same clean zero as a scan that found nothing wrong, and the statement CR-5
    # was raised about is the one it must be able to see.
    verdict(
      "the scan reaches `trust_status` — the statement CR-5 was raised about",
      Enum.any?(authored, fn {p, _t, _c} -> p == "trust_status" end)
    )

    halt_unless(Enum.any?(authored, fn {p, _t, _c} -> p == "trust_status" end))

    # POSITIVE CONTROL for the EXCLUSION, the other direction. The data rows do
    # carry population figures — `175 manifest checks` in the bucket-1 records'
    # own searches — so "0 stale figures" is not an artefact of a scan that
    # excluded everything. Both directions, or neither means anything.
    verdict(
      "and claim-bearing DATA strings exist and are excluded as their file's claim",
      data > 0
    )

    halt_unless(data > 0)

    IO.puts(
      "\n  the guard's report as committed:\n    #{squash(a["population_statement_guard"])}"
    )

    verdict(
      "the report makes no population claim of its own — it is not part of what it attests",
      Crosswalk.population_claims(a["population_statement_guard"]) == []
    )

    # POSITIVE CONTROL: the unmutated generator emits, so a refusal below is the
    # mutation's doing and not a broken build.
    out = tmp("statements-positive")
    run_crosswalk(out)
    IO.puts("\n  POSITIVE  the unmutated generator emits (#{byte_size(File.read!(out))} bytes)")
    File.rm(out)

    task_src = File.read!(@crosswalk_src)
    lib_src = File.read!(@crosswalk_lib)

    # MUTATION 1 — CR-5's DEFECT, PLANTED. The interpolated pair goes back to the
    # literal the committed artefact actually shipped. This is the one that must
    # go red at C1b-iii and C1c instead of shipping a third time.
    mutate!(
      task_src,
      @crosswalk_src,
      ~S|"#{f.declared_members}-member / #{f.declared_checks}-declared-check slice and no " <>|,
      ~S|"48-member / 29-declared-check slice and no " <>|,
      "1  the stale literal CR-5 found, put back into trust_status",
      "are not figures"
    )

    # MUTATION 2 — a figure the run DOES hold, in the WRONG PLACE. The member
    # count becomes the check count: 39 is a figure this crosswalk holds, so the
    # against-the-tree limb cannot see it, and only the phrase pin can. Without
    # this, limb 3 would be decoration.
    mutate!(
      task_src,
      @crosswalk_src,
      ~S|"#{f.declared_members}-member / #{f.declared_checks}-declared-check slice and no " <>|,
      ~S|"#{f.declared_checks}-member / #{f.declared_checks}-declared-check slice and no " <>|,
      "2  a HELD figure interpolated into the wrong slot (39-member, not 68)",
      "do not state the figure this run holds"
    )

    # MUTATION 3 — the scan itself made blind. A regex edit that stops matching
    # leaves every limb green over an artefact nobody read, which is precisely
    # the shape a guard cannot be allowed to fail in. L1 is fail-closed on it.
    mutate!(
      lib_src,
      @crosswalk_lib,
      ~S|@population_claim ~r/(?<![\w-])(\d+)|,
      ~S|@population_claim ~r/zzzz(?<![\w-])(\d+)|,
      "3  the claim regex stops matching — the scan reads an EMPTY population",
      "found NOTHING to read"
    )

    IO.puts("""

      WHAT THESE DO NOT SHOW. That every figure is interpolated: a literal that coincides
      with some OTHER held figure passes limb 2 until the population next moves — and
      `addressed_not_declared` was 14 here, so a stale `14 checks` would have. That is the
      residual, and it is bounded by when it fires (the next move of the population, which
      is when the recurrence lands anyway) rather than argued away. Nor do they reach prose
      the generator does not EMIT: the moduledoc and a branch not taken are outside the
      universe by construction, because the universe is the artefact's own bytes.
    """)
  end

  # Apply a single-line edit to `path`'s source in-VM, require the generator to
  # refuse naming `expect`, and restore. A mutation that does not mutate is a
  # green that means nothing, so a no-op replacement halts rather than passes.
  defp mutate!(src, path, from, to, label, expect) do
    mutated = String.replace(src, from, to)

    if mutated == src do
      IO.puts("  MUTATION COULD NOT BE APPLIED — the line the control edits has moved:")
      IO.puts("    #{inspect(from)}")
      System.halt(1)
    end

    out = tmp("statements-mutated")

    try do
      recompile!(mutated, path)
      refuses("MUTATION #{label}", expect, fn -> run_crosswalk(out) end)

      verdict(
        "         and nothing was written — the guard runs before the file",
        not File.exists?(out)
      )

      halt_unless(not File.exists?(out))
    after
      recompile!(src, path)
      File.rm(out)
    end

    back = tmp("statements-restored")
    run_crosswalk(back)
    verdict("         restored — the same run emits again", File.exists?(back))
    halt_unless(File.exists?(back))
    File.rm(back)
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
