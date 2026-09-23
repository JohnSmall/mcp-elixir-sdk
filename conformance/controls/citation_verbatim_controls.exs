# Controls for G30 — the citation-verbatim guard (MES-112).
#
#     mix run conformance/controls/citation_verbatim_controls.exs positive
#     mix run conformance/controls/citation_verbatim_controls.exs reach
#     mix run conformance/controls/citation_verbatim_controls.exs mutations
#     mix run conformance/controls/citation_verbatim_controls.exs end-to-end
#     mix run conformance/controls/citation_verbatim_controls.exs all
#
# WHAT G30 CLAIMS. Every source-shaped backtick span in an edges record's
# `evidence` occurs VERBATIM and CONTIGUOUS inside a window the evidence itself
# ADDRESSES — the cited `file.exs:N[-M]` span, or a byte span the axis row for
# that edge's tag names in the harness build. Ruling 7 is "an address AND the
# bytes at it"; every sweep before MES-112 established only the address half.
#
# WHY THE MUTATIONS RUN IN MEMORY. They mutate RECORDS, never files in the
# clone. Seats share one checkout, and a seat death mid-run does not execute an
# `after` block — S8-14, measured on MES-88, where a killed VM left `lib/`
# mutated. The one mode that needs a file on disk (`end-to-end`) writes it to a
# TEMP path and passes it with `--edges`, so the guard is driven through the
# real task at the real OS exit status with nothing in the repository touched.
#
# THE PAIR THAT MATTERS IS M2 AND M3. Each is red under both limbs and GREEN
# under the other limb alone, which is the only way to show the two limbs are
# two properties rather than one property counted twice. A guard whose second
# limb is entailed by its first is as empty as one nobody calls.
#
# THE DECISION LOGIC is unit-tested in `test/conformance/citation_verbatim_test.exs`,
# so gate 5 covers the cases the real artefacts happen not to contain.

defmodule CitationVerbatimControls do
  alias MCP.Conformance.{CitationVerbatim, Crosswalk}

  @harness "/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js"

  @client_edges "conformance/data/crosswalk-edges-client.json"
  # MES-105 (C1c-i) opened the SERVER-leg edges file and wired it into
  # `crosswalk_controls.exs` and `crosswalk_falsification_controls.exs` — and not
  # into this one, which went on holding two paths. MEASURED at 3166dc7 before
  # the fix: this control visited 160 records and compared 131 quotes while the
  # generator's own G30 compared 210 over 106 of 245 records. Every server-leg
  # citation was OUTSIDE the control, and the `end-to-end` mode drove the task
  # over a SMALLER crosswalk than the committed one. That is not a red; it is a
  # quieter green, which is the harder thing to notice. Closed by MES-115
  # (C1c-ii), the ticket that does this leg's heavy citation-lifting.
  @server_edges "conformance/data/crosswalk-edges-server.json"
  @edges "conformance/data/crosswalk-edges.json"
  @c1_axes "conformance/data/oc-axes-c1.json"
  @a3_axes "docs/conformance/oc-axes-2026-07-28.json"
  @manifest "docs/conformance/in-scope-2026-07-28.json"
  @denominator "docs/conformance/bucket-0-2026-07-28.json"
  @register "docs/conformance/etcc-register.json"
  @attribution "docs/conformance/etcc-attribution.json"
  @sites "docs/conformance/oc-emitting-sites-2026-07-28.json"

  def run(["positive"]), do: positive()
  def run(["reach"]), do: reach()
  def run(["mutations"]), do: mutations()
  def run(["end-to-end"]), do: end_to_end()

  def run(["all"]) do
    positive()
    reach()
    mutations()
    end_to_end()
  end

  def run(_) do
    IO.puts("usage: positive | reach | mutations | end-to-end | all")
    System.halt(2)
  end

  # --- positive: the corrected tree passes -----------------------------------
  #
  # Without this, a guard that was red on EVERYTHING would "pass" every mutation
  # below vacuously, and the four reds would prove nothing at all.

  defp positive do
    header("POSITIVE — the committed edges files pass G30 with both limbs active")

    r = audit(records())

    IO.puts(
      "  #{r["records_visited"]} records visited, #{r["records_with_evidence"]} carrying evidence"
    )

    IO.puts(
      "  #{r["quotes_compared"]} source-shaped quotes placed at an address their evidence names"
    )

    for d <- r["defects"],
        do: IO.puts("    #{d["kind"]} — #{inspect(d["detail"])}  (#{d["row"]})")

    verdict("0 defects over all three edges files", r["defects"] == [])
    halt_unless(r["defects"] == [])

    IO.puts("""

      MES-112 corrected EIGHTEEN inherited defects to reach this green — 8 re-addressed,
      2 bare `:N` continuations written out in full by an author, 2 re-lifted from a
      paraphrase, 6 de-quoted because a described shape or an absent token is not a lift.
      Fix-then-guard: landing the guard over a subset would have forced the grandfather
      list the design forbids.
    """)
  end

  # --- reach: the control that protects the whole guard ----------------------

  defp reach do
    header("REACH — the sweep visited every record and compared every quote")

    records = records()
    r = audit(records)

    # An INDEPENDENT count, walking the span regex over the same records. Not a
    # literal: a hard-coded 135 is stale the next ticket, and a stale literal
    # does not make the guard wrong — it makes the control stop attesting it
    # while still looking green.
    counted =
      records
      |> Enum.map(&length(CitationVerbatim.source_quotes(&1["evidence"] || "")))
      |> Enum.sum()

    with_evidence = Enum.count(records, &((&1["evidence"] || "") != ""))

    IO.puts("  compared #{r["quotes_compared"]}   counted independently #{counted}")

    IO.puts(
      "  records with evidence: sweep says #{r["records_with_evidence"]}, recount says #{with_evidence}"
    )

    IO.puts("  visited #{r["records_visited"]} of #{length(records)} records in the three files")

    checks = [
      {"every quote the records carry was compared — #{r["quotes_compared"]} of #{counted}",
       r["quotes_compared"] == counted},
      {"the population is not empty — #{counted} quotes", counted > 0},
      {"every record was visited", r["records_visited"] == length(records)},
      {"every evidence-carrying record was reached", r["records_with_evidence"] == with_evidence}
    ]

    # A FIFTH CHECK WAS HERE AND IS DELIBERATELY GONE (MES-112, CR note i).
    # `r["quotes_counted"] == counted` reads as a second opinion and is not one:
    # both sides are `length` of the span regex walked over the same records, so
    # it is constant-vs-constant and cannot fail. A check that cannot fail in a
    # control whose whole job is to stop a claim that cannot fail is the same
    # defect one level down. Checks 1-4 carry the load: 1 compares the sweep's
    # figure against this walk (genuinely two producers), 2 refuses an empty
    # population, 3 and 4 quantify over records rather than quotes.

    for {label, ok?} <- checks, do: verdict(label, ok?)
    halt_unless(Enum.all?(checks, &elem(&1, 1)))

    IO.puts("""

      WHY THIS IS NOT REDUNDANT WITH `positive`. `defects == []` is also exactly what a
      sweep that read NOTHING returns — the S9-15 shape, a guard on a dead path. The
      comparison above is what distinguishes the two, and `counted > 0` is what stops it
      being satisfied by an empty population. Every figure is derived here and interpolated
      into the message; none is written down.
    """)
  end

  # --- the four mutations, and the limb isolation ----------------------------

  defp mutations do
    header("MUTATIONS — each defect class planted in memory and required to go red")

    m1()
    m2()
    m3()
    m4()

    IO.puts("""

      M2 AND M3 ARE THE PAIR. Each goes green under the other limb alone, so neither limb
      is doing the other's work: WINDOWING is what makes a right-bytes/wrong-line citation
      fail, CONTIGUITY is what makes a quote spliced from two real lines fail, and dropping
      either one lets its own defect through with the other fully intact.
    """)
  end

  # M1 — WRONG QUOTE. A module prefix dropped from a real assertion: CR-3's own
  # defect (MES-104). PLANTED IN A RECORD NOBODY'S FINDING POINTED AT — it is
  # one of MES-108's own rows, which the 18 never touched — because a mutation
  # that only ever edits the field a finding named cannot tell a guard that
  # quantifies over everything from one that quantifies over that field.
  defp m1 do
    plant(
      "M1 wrong-quote",
      "a module prefix dropped from a real assertion (CR-3's defect)",
      "HeaderMirror.decode_value(header)",
      "decode_value(header)",
      "not_verbatim_at_any_cited_address",
      "decode_value(header)"
    )
  end

  # M2 — WRONG LINE. The bytes are untouched and still in the file; the address
  # moves by ONE. A check that asked only "is this text anywhere in the file"
  # passes this, and it is the drift citations actually suffer.
  defp m2 do
    plant(
      "M2 wrong-line (limb 1, WINDOWING)",
      "one citation moved by a single line, the bytes untouched",
      "client_defects_test.exs:161",
      "client_defects_test.exs:162",
      "not_verbatim_at_any_cited_address",
      ~S|assert retry["params"]["requestState"] == "opaque-server-token"|
    )

    # LIMB ISOLATION. Drop WINDOWING — compare against the whole file instead of
    # the cited span — and the same mutation goes green, because the bytes never
    # moved. That is the measurement of what the limb is worth.
    loose =
      added(mutate("client_defects_test.exs:161", "client_defects_test.exs:162"),
        limbs: [:contiguity]
      )

    verdict(
      "and it is GREEN with WINDOWING dropped — the limb is load-bearing, not decorative",
      loose == []
    )

    halt_unless(loose == [])
  end

  # M3 — COMPOSED QUOTE. Spliced from two NON-ADJACENT lines of the SAME cited
  # span: the window is correct, every token is real and present, and the whole
  # is contiguous nowhere. MES-109's defect, which a careful read passed.
  defp m3 do
    composed = ~S|assert req["method"] == %{"message" => "hi"}|

    plant(
      "M3 composed-quote (limb 2, CONTIGUITY)",
      "a quote spliced from lines 193 and 195 of the cited 191-195 span",
      "client_test.exs:191-195",
      "client_test.exs:191-195 — composed: `#{composed}` —",
      "not_verbatim_at_any_cited_address",
      composed
    )

    # LIMB ISOLATION. Drop CONTIGUITY — ask only that every token occurs
    # somewhere in the window — and the composed quote goes green with the
    # window fully intact.
    loose =
      added(
        mutate("client_test.exs:191-195", "client_test.exs:191-195 — composed: `#{composed}` —"),
        limbs: [:windowing]
      )

    verdict(
      "and it is GREEN with CONTIGUITY dropped — the limb is load-bearing, not decorative",
      loose == []
    )

    halt_unless(loose == [])
  end

  # M4 — ELLIPSIS. One re-lifted quote re-elided. Ratified on MES-112 as a
  # REFUSAL rather than a fragment match: admitting `A … B` green-lights a quote
  # whose halves sit arbitrarily far apart, which IS the composed-quote hole,
  # and installs a weaker second predicate no mutation could tell from the
  # strong one.
  defp m4 do
    plant(
      "M4 ellipsis",
      "one re-lifted quote re-elided to `A … B`",
      "assert [] = Enum.at(MockTransport.sent_opts(transport), 1) |> Keyword.get(:headers, [])",
      "assert [] = … Keyword.get(:headers, [])",
      "elision_is_not_a_lift",
      "assert [] = … Keyword.get(:headers, [])"
    )
  end

  # Plant one substitution, require it to have CHANGED SOMETHING, and require
  # the guard to go red NAMING THE PLANT. "It raised" is not "the planted defect
  # was caught" — a control that only counts reds passes on an unrelated failure.
  defp plant(name, what, from, to, expected_kind, names) do
    before = audit(records())
    mutated = mutate(from, to)

    applied = Enum.count(mutated, &String.contains?(&1["evidence"] || "", to))

    if applied == 0 do
      IO.puts("  FAIL  #{name}: the plant changed NOTHING — #{inspect(from)} is not in the tree")
      IO.puts("        A no-op mutation is an UNCAUGHT mutation, not a caught one.")
      System.halt(1)
    end

    caught = audit(mutated)["defects"] -- before["defects"]

    IO.puts("\n  #{name} — #{what}")
    IO.puts("    planted in #{applied} record(s): #{inspect(from)} -> #{inspect(to)}")
    for d <- caught, do: IO.puts("    caught: #{d["kind"]} — #{inspect(d["detail"])}")

    # NAMING THE PLANT, not merely going red. A control that counts reds passes
    # on an unrelated failure, and the defect it was written for goes on living.
    named? =
      Enum.any?(caught, fn d ->
        d["kind"] == expected_kind and String.contains?(d["detail"], names)
      end)

    verdict("CAUGHT as #{expected_kind}, naming #{inspect(names)}", named?)
    halt_unless(named?)

    caught
  end

  # Defects a mutation ADDED, under the given limbs. The baseline is green, so
  # under both limbs this is the whole list — but taking the DIFFERENCE, and
  # taking it against a baseline run with the SAME limbs, is what makes the
  # isolation above mean "this defect went away" rather than "some defect did".
  defp added(mutated, opts),
    do: audit(mutated, opts)["defects"] -- audit(records(), opts)["defects"]

  # --- end-to-end: the guard REFUSES through the real task -------------------
  #
  # Everything above drives the predicate. This drives `mix conformance.crosswalk`
  # itself, at the OS exit status, over a mutated edges file written to a TEMP
  # path — so it establishes that the guard is WIRED, which no in-VM call can.
  # A guard that is correct, unit-tested and never called protects nothing
  # (S9-15).

  defp end_to_end do
    header("END-TO-END — a bad citation cannot be committed, at the OS exit status")

    require_harness!()

    # NEGATIVE CONTROL FIRST, in the same run and by the same code path: the
    # unmutated file through the same temp-file plumbing. Without it, a red
    # below could be the plumbing rather than the guard.
    clean = write_tmp("clean", read(@client_edges))
    {out, status} = run_task(clean)
    File.rm(clean)

    verdict("the UNMUTATED file through the same plumbing exits 0", status == 0)

    if status != 0 do
      IO.puts(out)
      System.halt(1)
    end

    doc = read(@client_edges)

    edges =
      Enum.map(doc["edges"], fn r ->
        Map.update(r, "evidence", nil, fn ev ->
          String.replace(ev, "capabilities_test.exs:98", "capabilities_test.exs:97")
        end)
      end)

    planted =
      Enum.count(edges, &String.contains?(&1["evidence"] || "", "capabilities_test.exs:97"))

    if planted == 0 do
      IO.puts("  FAIL  the plant changed nothing — a no-op mutation is an uncaught one")
      System.halt(1)
    end

    path = write_tmp("mutated", Map.put(doc, "edges", edges))
    {out, status} = run_task(path)
    File.rm(path)

    IO.puts(
      "\n  planted C1a's own off-by-one back into #{planted} record(s), then ran the real task:"
    )

    IO.puts("    exit status #{status}")

    for line <- out |> String.split("\n") |> Enum.take(6), do: IO.puts("    #{line}")

    checks = [
      {"the task REFUSES (nonzero exit), rather than writing the artefact", status != 0},
      {"and the refusal names G30", String.contains?(out, "G30")},
      {"and names the quote it could not place",
       String.contains?(out, inspect(~S|assert decoded["roots"]["listChanged"] == true|))}
    ]

    for {label, ok?} <- checks, do: verdict(label, ok?)
    halt_unless(Enum.all?(checks, &elem(&1, 1)))

    IO.puts("""

      NOTHING IN THE REPOSITORY WAS TOUCHED. The mutated file is written to the system
      temp directory and reached with `--edges`, which the task already accepts more than
      once. So this control cannot leave the shared clone dirty however it dies, and it
      still drives the shipped entry point rather than a re-implementation of it.
    """)
  end

  defp run_task(edges_path) do
    args = [
      "conformance.crosswalk",
      "--edges",
      edges_path,
      "--edges",
      @server_edges,
      "--edges",
      @edges,
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
      @c1_axes,
      "--emitting-sites",
      @sites,
      "--harness",
      @harness,
      "-o",
      tmp("crosswalk")
    ]

    {out, status} = System.cmd("mix", args, stderr_to_stdout: true)
    {out, status}
  end

  # --- the population and the predicate, as the generator builds them --------
  #
  # These call `Crosswalk.citation_windows/2` — the SHIPPED window builder the
  # task itself calls. A control that re-implemented it would attest a copy.

  defp records do
    for path <- [@client_edges, @server_edges, @edges],
        doc = read(path),
        {key, value} <- doc,
        is_list(value),
        value != [],
        Enum.all?(value, &is_map/1),
        record <- value,
        do: Map.merge(record, %{"__file" => Path.basename(path), "__collection" => key})
  end

  defp audit(records, opts \\ []) do
    require_harness!()
    build = File.read!(@harness)

    ctx = %{
      axes: read(@c1_axes)["checks"] ++ read(@a3_axes)["checks"],
      build: build,
      squashed_build: CitationVerbatim.squash(build)
    }

    CitationVerbatim.audit(records, &Crosswalk.citation_windows(&1, ctx), opts)
  end

  defp mutate(from, to) do
    Enum.map(records(), fn r ->
      case r["evidence"] do
        nil -> r
        ev -> Map.put(r, "evidence", String.replace(ev, from, to))
      end
    end)
  end

  # --- plumbing --------------------------------------------------------------

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
        These controls cannot run, and that is REPORTED rather than skipped: an unrun
        control and a null result are the same artefact (MES-56).
      """)

      System.halt(1)
    end
  end

  defp tmp(stem),
    do: Path.join(System.tmp_dir!(), "mes112-#{stem}-#{System.unique_integer([:positive])}.json")

  defp write_tmp(stem, doc) do
    path = tmp(stem)
    File.write!(path, Jason.encode!(doc))
    path
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

CitationVerbatimControls.run(System.argv())
