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

  def run(["all"]) do
    noop()
    keying()
    locator()
    pins()
    guards()
    vacuum()
    selectors()
    composition()
  end

  def run(_) do
    IO.puts(
      "usage: noop | keying | locator | pins | guards | vacuum | selectors | composition | all"
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
    refuses("8  a member in the population that its own selector does not denote", "G15a", fn ->
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

    expectations = [
      {"the client file's members", client["the_population_this_file_declares"]["selector"], src,
       rows
       |> Enum.filter(&(&1["leg"] == "client" and (&1["cg"] == "CG7" or tagged?.(&1))))
       |> Enum.map(& &1["key"])},
      {"the residual file's members", resid["the_population_this_file_declares"]["selector"], src,
       rows
       |> Enum.filter(&(tagged?.(&1) and &1["leg"] != "client"))
       |> Enum.map(& &1["key"])},
      {"the client file's CHECKS", client["the_check_population_this_file_declares"]["selector"],
       sites,
       sites["rows"]
       |> Enum.filter(&(&1["scenario"] in ["http-custom-headers", "http-invalid-tool-headers"]))
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

    IO.puts("""

      The generator catches all three — a population that is not the set its selector
      denotes is G15a, in both directions. What this shows is the SIZE of the mistake
      each one makes on the anchor this project actually ships, which is the thing a
      five-row unit cannot say.
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
          @attribution,
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
