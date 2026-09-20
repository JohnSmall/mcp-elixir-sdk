# C3 (MES-99) — the falsification control on C1a's crosswalk and its generator.
#
#     mix run conformance/controls/crosswalk_falsification_controls.exs refusals
#     mix run conformance/controls/crosswalk_falsification_controls.exs drift
#     mix run conformance/controls/crosswalk_falsification_controls.exs second_source
#     mix run conformance/controls/crosswalk_falsification_controls.exs exit_status
#     mix run conformance/controls/crosswalk_falsification_controls.exs all
#
# and one mode that is EXPECTED TO EXIT 1, driven as a subprocess by `refusals`
# rather than left for a reader to find:
#
#     mix run conformance/controls/crosswalk_falsification_controls.exs wrong_reason
#
# WHY THIS FILE EXISTS. Ruling 5: six bucket reports derived from an unfalsified
# crosswalk are assertions. C1a shipped thirteen generator refusals; this ticket
# began by running the brief's four falsification classes against the real
# generator rather than reasoning about them, and THREE OF THE FOUR BUILT
# CLEANLY:
#
#   A  unmutated (positive control)   built — 21 members, 23 edges, {4a:2,4b:2,5:15}
#   B  an edge duplicated verbatim    BUILT CLEANLY — edges 23->24, bucket 5 15->16
#   C  an edge dropped                BUILT CLEANLY — members 21->20, edges 22
#   D  a declared_unmatched dropped   BUILT CLEANLY — members 21->20, unmatched 5->4
#
# One cause, and it is the reason this control's shape is what it is: C1a
# DERIVED the declared population by unioning the register_keys the edges file
# itself carries. A dropped row therefore did not violate the universe, it
# SHRANK it, and every downstream reconciliation still held — the edge equation,
# the member equation, both set_compare directions. The artefact stayed
# internally perfect while being about less than it claimed.
#
# THE THREE DISCIPLINES THIS FILE IS HELD TO
#
#   * A control never seen red is a claim (S8-3/S8-4). Every refusal below is
#     shown FIRING on a real mutation, with the unmutated input as the negative
#     control in the same run — a checker that always fired would print the same
#     "refused" line. And a refusal is only evidence for the class it was planted
#     to cause, so each one asserts what the generator's message must SAY; the
#     `wrong_reason` mode is that matcher's own control, shown exiting 1 on a
#     real refusal that names a different guard.
#   * Every zero gets TWO controls. The positive control shows the check reached
#     the population; the mutation shows the predicate CAN fire. Neither
#     substitutes for the other.
#   * Provenance vs consistency (ruling 9). `second_source` re-derives the
#     artefact from a different file, a different schema and a different
#     generator to the same digest. Both descend from the SAME accepted harness
#     run, so it witnesses that nobody edited one without regenerating the other
#     and NOT that either is correct. The mode is named `second_source`, its
#     output says CONSISTENCY, and residual X6 says it in the artefact.
#
# WHAT IS MUTATED, AND WHERE. Inputs are mutated as temp copies; nothing is
# written into the repo. The one mechanism mutation is an in-VM
# `Code.compile_string` restored in an `after`, so a seat death mid-run cannot
# leave the shared clone mutated (S8-14).
#
# ORDER IS PART OF THE DESIGN. Each mode runs its positive control FIRST, its
# mutations, and then the unmutated build AGAIN — C1a's `guards` mode runs its
# positive control only before, so "restored green" was never established for
# it. `refusals` ends by re-running C1a's thirteen as a subprocess so the whole
# set, not only this ticket's, is covered by an after-restoration.

defmodule CrosswalkFalsificationControls do
  @harness "/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js"

  @edges "conformance/data/crosswalk-edges.json"
  @c1_axes "conformance/data/oc-axes-c1.json"
  @a3_axes "docs/conformance/oc-axes-2026-07-28.json"
  @manifest "docs/conformance/in-scope-2026-07-28.json"
  @denominator "docs/conformance/bucket-0-2026-07-28.json"
  @register "docs/conformance/etcc-register.json"
  @attribution "docs/conformance/etcc-attribution.json"
  @crosswalk_out "docs/conformance/crosswalk-2026-07-28.json"

  @c1a_controls "conformance/controls/crosswalk_controls.exs"

  def run(["refusals"]), do: refusals()
  def run(["wrong_reason"]), do: wrong_reason()
  def run(["drift"]), do: drift()
  def run(["second_source"]), do: second_source()
  def run(["exit_status"]), do: exit_status()

  def run(["all"]) do
    refusals()
    drift()
    second_source()
    exit_status()
    IO.puts("\n== ALL FOUR MODES GREEN ==\n")
  end

  def run(_) do
    IO.puts("usage: refusals | drift | second_source | exit_status | wrong_reason | all")
    System.halt(2)
  end

  # === refusals — AC1 =======================================================
  #
  # Each entry is {label, fn -> a build that must refuse}. The count is PRINTED
  # rather than written into any artefact: a hard-coded "sixteen refusals" in a
  # committed file is the S9-11 hazard, a figure nothing re-derives.

  defp refusals do
    header("REFUSALS — every falsification class, mutated and shown to refuse (AC1)")

    require_harness!()
    edges = read(@edges)
    first = hd(edges["edges"])

    positive("the unmutated edges build cleanly")

    n =
      count_refusals([
        {"G14  an edge duplicated VERBATIM — the (member, claim, tag) triple twice",
         ["G14 — repeated (member, claim, tag) triples (1)"],
         fn -> build(update_in(edges["edges"], &[first | &1])) end},
        {"G14  a member declared unmatched twice",
         ["G14 — members declared unmatched more than once (1)"],
         fn ->
           d = hd(edges["declared_unmatched"])
           build(update_in(edges["declared_unmatched"], &[d | &1]))
         end},
        {"G15  one edge DROPPED — the population shrinks instead of breaking",
         ["is not the set its own selector denotes", "absent from this file (1)"],
         fn -> build(dropped_edge(edges)) end},
        {"G15  one declared_unmatched member DROPPED",
         ["is not the set its own selector denotes", "absent from this file (1)"],
         fn -> build(update_in(edges["declared_unmatched"], &tl/1)) end},
        {"G15  the selector denotes FEWER rows than the file derives (the `extra` direction)",
         ["is not the set its own selector denotes", "not denoted by the selector (2)"],
         fn ->
           build(
             put_in(
               edges,
               ["the_population_this_file_declares", "selector", "any_of"],
               [%{"field" => "tokens", "test" => "non_empty_list"}]
             )
           )
         end},
        {"G15  the declared COUNTS lie while every SET still agrees",
         ["disagrees with what the generator derives", "members: declared 22, derived 21"],
         fn ->
           build(put_in(edges, ["the_population_this_file_declares", "members"], 22))
         end},
        {"G15  no selector at all — prose with no executable half", ["carries no `selector`"],
         fn ->
           build(
             update_in(edges["the_population_this_file_declares"], &Map.delete(&1, "selector"))
           )
         end},
        {"G15  a selector `test` the evaluator does not implement (fail-closed)",
         [":unknown_selector_test"],
         fn ->
           build(
             put_in(
               edges,
               ["the_population_this_file_declares", "selector", "any_of"],
               [%{"field" => "tokens", "test" => "looks_about_right"}]
             )
           )
         end},
        {"G15  the selector's `source` is not the anchor this run was given",
         ["as its source, but this run was", "etcc-register.json"],
         fn ->
           build(
             put_in(
               edges,
               ["the_population_this_file_declares", "selector", "source"],
               "docs/conformance/etcc-register.json"
             )
           )
         end},
        {"G15  the ANCHOR itself carries a duplicated key — a silent merge in the universe",
         [":selector_source_has_duplicate_keys"], fn -> duplicated_anchor(edges) end},
        {"G16  a manifest whose verdicts have DRIFTED from A5's, still totalling 175",
         ["carry a DIFFERENT status", "G16 — 1 checks"], fn -> drifted_manifest_status() end},
        {"G16  a manifest whose 175 keys are not bucket-0's 175",
         ["do not carry the same check keys", "absent from bucket-0: 1"],
         fn -> drifted_manifest_key() end},
        {"     a manifest that is not the frozen 175", ["the manifest is not the frozen 175"],
         fn -> short_manifest() end},
        {"     --verdicts-from naming neither source",
         ["--verdicts-from must be `manifest` or `bucket-0`"],
         fn -> crosswalk(tmp("vf"), verdicts_from: "whatever-is-lying-around") end},
        {"     --harness at a build that is not the one the axes were read from",
         ["not the build the axes were read from"], fn -> other_harness() end}
      ])

    IO.puts("""

      #{n} refusals, each on the cheapest input that could carry that particular lie,
      against ONE unmutated positive control in the same run. Classes B, C and D at the
      head of this file are the first four entries: they built cleanly at 559eda8.
    """)

    positive("RESTORED — the unmutated edges build cleanly again, after all #{n} mutations")

    matcher_control()

    # C1a's thirteen, re-run with an after-restoration they never had. A
    # subprocess rather than a copy: duplicating the mutations here would make
    # two places to keep true, and the copy would be the one that rotted.
    header("C1a's THIRTEEN — re-run, with the after-restoration `guards` never had")

    {out, status} =
      System.cmd("mix", ["run", @c1a_controls, "guards"], stderr_to_stdout: true)

    IO.puts(
      out
      |> String.split("\n")
      |> Enum.filter(&(&1 =~ ~r/refused|POSITIVE|DID NOT|RESTORED/))
      |> Enum.join("\n")
    )

    verdict("C1a's guards mode exits 0", status == 0)
    halt_unless(status == 0)

    positive("RESTORED — the unmutated edges still build cleanly after C1a's thirteen too")
  end

  # The `wrong_reason` mode is run HERE rather than being a mode a reader has to
  # know to invoke: an unrun control and a null result are the same artefact.
  defp matcher_control do
    header("THE MATCHER'S OWN CONTROL — a refusal naming the wrong guard must FAIL")

    {out, status} =
      System.cmd("mix", ["run", __ENV__.file, "wrong_reason"], stderr_to_stdout: true)

    IO.puts(
      out
      |> String.split("\n")
      |> Enum.filter(&(&1 =~ ~r/refused|WRONG REASON|expected the message|DID NOT HALT/))
      |> Enum.join("\n")
    )

    verdict("the control exits NONZERO on a refusal that names a different guard", status == 1)
    halt_unless(status == 1)

    IO.puts("""
      Fifteen `refused` lines are only evidence if a wrong one could have gone red. This
      is the limb that makes them so, and it is shown firing rather than asserted.
    """)
  end

  defp count_refusals(cases) do
    Enum.each(cases, fn {label, expected, fun} -> refuses(label, expected, fun) end)
    length(cases)
  end

  # THE MATCHER'S OWN CONTROL. `refuses/3` halts when a mutation refuses for a
  # reason other than the one it was planted to cause — without that, a control
  # of fifteen "refused" lines would pass on a generator that refused everything
  # for one unrelated reason, which is the S9-18 shape (a search that stops on
  # "a hit" cannot fail). This mode asserts a deliberately WRONG expectation on a
  # mutation that really does refuse, and is expected to EXIT 1. `refusals`
  # drives it as a subprocess, because the limb being demonstrated is the halt
  # itself and a halt cannot be observed from inside the run it ends.
  defp wrong_reason do
    header("WRONG REASON — the expectation matcher, shown refusing a real refusal")

    edges = read(@edges)

    IO.puts("""
      The mutation below (a verbatim duplicate edge) DOES refuse — `refusals` shows it
      refusing, at G14. Here it is asserted to refuse at G16 instead. A matcher that only
      checked "something was raised" would print `refused` and move on.
    """)

    refuses(
      "G16  <- deliberately wrong: this mutation refuses at G14",
      ["G16 — A1's manifest and A5's bucket-0 artefact"],
      fn -> build(update_in(edges["edges"], &[hd(edges["edges"]) | &1])) end
    )

    IO.puts("  DID NOT HALT — the matcher accepted a refusal naming a different guard.")
    System.halt(1)
  end

  # === drift — AC2 ==========================================================
  #
  # AC1 cannot reach this class and that is the point of having both. An axis
  # verdict is a JUDGEMENT: `contradicts` and `agrees` are each a legal token on
  # a well-formed edge, so no refusal can decide between them. Only a pinned
  # per-row assignment can, and the pin IS the committed crosswalk — there is no
  # second copy to drift (D4, one fact one home).

  defp drift do
    header("DRIFT — a wrong crosswalk moves a bucket, and is caught naming the row (AC2)")

    require_harness!()
    edges = read(@edges)
    committed = assignments(read(@crosswalk_out))

    # POSITIVE CONTROL: the unmutated regeneration compares every row and moves
    # none. Without it, "0 moved" could mean the comparison reached no rows.
    {n, moved} = compare(committed, edges)
    IO.puts("  POSITIVE  #{n} of #{map_size(committed)} rows compared, #{length(moved)} moved")

    verdict(
      "the diff reached the whole population and found no drift",
      n == map_size(committed) and moved == []
    )

    halt_unless(n == map_size(committed) and moved == [])

    IO.puts("""

      MUTATION 1 — the `:83` initialize edge over HTTP. Its axes are
      jsonrpc_error_code: contradicts and http_status: silent. ONE token,
      `contradicts` -> `agrees`, makes the shape :partial and moves the row 4a -> 4b.

      4a and 4b SHARE the verdict pair (red OC / green ET) and differ only in
      mechanism — contradiction versus incompleteness. It is the hardest boundary in
      the ratified table and the one MatchKey's axis-precedence rule was written for;
      its own moduledoc names this exact edge as one that "could be filed either way
      depending on which axis an implementation happened to test first".
    """)

    drifted = put_in(edges, ["edges", Access.at(20), "axes", Access.at(0), "verdict"], "agrees")
    {n1, moved1} = compare(committed, drifted)

    show_moves("MUTATION 1", n1, moved1)
    verdict("exactly one row moved, 4a -> 4b", match?([%{from: "4a", to: "4b"}], moved1))
    halt_unless(match?([%{from: "4a", to: "4b"}], moved1))

    invisible_to_arithmetic(edges, drifted)

    IO.puts("""

      MUTATION 2 — an ET verdict on a bucket-5 row, green -> red. That lands it in
      bucket 3, which this artefact declares EMPTY BY CONSTRUCTION. The detector is
      shown catching an entry into a declared-empty cell as well as a move between
      two populated ones.
    """)

    reddened = put_in(edges, ["edges", Access.at(0), "et_verdict"], "red")
    {n2, moved2} = compare(committed, reddened)

    show_moves("MUTATION 2", n2, moved2)
    verdict("exactly one row moved, 5 -> 3", match?([%{from: "5", to: "3"}], moved2))
    halt_unless(match?([%{from: "5", to: "3"}], moved2))

    # RESTORED: the same comparison that just caught two drifts finds none again.
    {n3, moved3} = compare(committed, edges)

    verdict(
      "RESTORED — #{n3} rows compared, #{length(moved3)} moved",
      n3 == map_size(committed) and moved3 == []
    )

    halt_unless(moved3 == [])

    IO.puts("""

      The pin is the committed artefact itself. A second copy of the assignments would
      be a second thing to keep true, and the copy is always the one that rots (D4).
    """)
  end

  # The property that makes a per-ROW pin necessary rather than decorative.
  defp invisible_to_arithmetic(edges, drifted) do
    a = regenerate(edges)
    b = regenerate(drifted)

    rows =
      for {label, f} <- [
            {"edges", & &1["arithmetic"]["edges"]},
            {"bucketed", & &1["arithmetic"]["bucketed"]},
            {"escalated", & &1["arithmetic"]["escalated"]},
            {"members", & &1["arithmetic"]["members"]},
            {"members_with_edges", & &1["arithmetic"]["members_with_edges"]},
            {"bucket 4a + 4b",
             &((&1["buckets"]["from_edges"]["4a"] || 0) + (&1["buckets"]["from_edges"]["4b"] || 0))},
            {"bucket 5", &(&1["buckets"]["from_edges"]["5"] || 0)},
            {"bucket 1", & &1["buckets"]["bucket_1"]["count"]},
            {"bucket 2", & &1["buckets"]["bucket_2"]["count"]},
            {"escalation rows", & &1["escalations"]["count"]},
            {"member set equal", & &1["totality"]["every_declared_member_appears"]["equal"]},
            {"check set equal", & &1["totality"]["every_declared_check_appears"]["equal"]}
          ] do
        {label, f.(a), f.(b)}
      end

    IO.puts("\n  every aggregate a totals-based check would look at, before and after:\n")

    for {label, x, y} <- rows do
      flag = if x == y, do: "unchanged", else: "MOVED"

      IO.puts(
        "    #{String.pad_trailing(label, 22)} #{String.pad_leading(inspect(x), 6)} -> #{String.pad_leading(inspect(y), 6)}   #{flag}"
      )
    end

    same = Enum.all?(rows, fn {_, x, y} -> x == y end)

    IO.puts("")

    verdict(
      "NOT ONE aggregate moves — a totals-based check passes over this crosswalk",
      same
    )

    halt_unless(same)

    IO.puts("""
      And what moved underneath them is the reading with the most different consequence
      in the matrix: "the SDK CONTRADICTS the check" became "our test is merely
      INCOMPLETE". 4a + 4b = 4 either way. Only a per-row comparison sees it.
    """)
  end

  defp assignments(artefact) do
    Map.new(artefact["cells"], fn c ->
      {{c["member"]["register_key"], c["claim"], c["tag"]}, c["bucket"] || "escalated"}
    end)
  end

  defp compare(committed, edges_doc) do
    regenerated = assignments(regenerate(edges_doc))

    shared =
      committed
      |> Map.keys()
      |> Enum.filter(&Map.has_key?(regenerated, &1))

    moved =
      shared
      |> Enum.filter(&(Map.fetch!(committed, &1) != Map.fetch!(regenerated, &1)))
      |> Enum.map(fn {_m, claim, tag} = k ->
        %{from: Map.fetch!(committed, k), to: Map.fetch!(regenerated, k), claim: claim, tag: tag}
      end)

    {length(shared), moved}
  end

  defp show_moves(label, n, moved) do
    IO.puts("  #{label}  #{n} rows compared, #{length(moved)} moved")

    for m <- moved do
      IO.puts("    MOVED  #{m.from} -> #{m.to}   #{m.claim}")
      IO.puts("           #{m.tag}")
    end
  end

  # === second_source — AC3 ==================================================

  defp second_source do
    header("SECOND SOURCE — the same artefact from a different file, schema and generator")

    require_harness!()

    IO.puts("""
      A1's manifest (docs/conformance/in-scope-2026-07-28.json) carries 44 scenarios of
      checks, each with A1's six-field `key` and a `status`. A5's bucket-0 artefact
      (docs/conformance/bucket-0-2026-07-28.json) carries a flat list of 175 checks with
      the same six-field `key`, its own `status` and its own `token` — a different file,
      a different schema, written by a different generator at MES-70.

      `--verdicts-from` reads the row set and the per-check verdicts from either. The
      output must be BYTE-IDENTICAL, and it must equal the committed artefact.
    """)

    committed = File.read!(@crosswalk_out)

    digests =
      for source <- ["manifest", "bucket-0"] do
        out = tmp("second-source-#{source}")
        crosswalk(out, verdicts_from: source)
        bytes = File.read!(out)
        File.rm(out)

        IO.puts(
          "    --verdicts-from #{String.pad_trailing(source, 10)} sha256 #{sha(bytes)}  (#{byte_size(bytes)} bytes)"
        )

        bytes
      end

    IO.puts(
      "    committed artefact           sha256 #{sha(committed)}  (#{byte_size(committed)} bytes)"
    )

    [a, b] = digests
    IO.puts("")
    verdict("the two source paths agree BYTE-FOR-BYTE", a == b)
    verdict("and both equal the committed artefact", a == committed)
    halt_unless(a == b and a == committed)

    IO.puts("""

      THIS IS A CONSISTENCY PIN, NOT A CORRECTNESS ONE (ruling 9, residual X6). Both
      artefacts descend from the SAME accepted harness run. Agreement witnesses that
      nobody edited one without regenerating the other. A wrong run would be wrong in
      both, and this pin would agree just as firmly. Nothing in the mode name, the
      output or the artefact field says otherwise.
    """)

    IO.puts("  and the generator REFUSES when pointed at a different source:\n")

    refuses(
      "     --harness at a build that is not the axes' build (C1a's sha256 guard, never before shown firing)",
      ["not the build the axes were read from"],
      fn -> other_harness() end
    )

    refuses(
      "     --manifest that is not the frozen 175",
      ["the manifest is not the frozen 175"],
      fn -> short_manifest() end
    )

    refuses(
      "G16  --manifest whose statuses have drifted from A5's, still totalling 175",
      ["carry a DIFFERENT status"],
      fn -> drifted_manifest_status() end
    )

    # POSITIVE CONTROL, AFTER: the mode's own refusals did not break the tree.
    out = tmp("second-source-restored")
    crosswalk(out)

    verdict(
      "RESTORED — the default run still reproduces the committed artefact",
      File.read!(out) == committed
    )

    halt_unless(File.read!(out) == committed)
    File.rm(out)
  end

  # === exit_status ==========================================================
  #
  # AC1 says the generator REFUSES — nonzero. C1a's control `rescue`s an in-VM
  # raise, which establishes "raises". That is a different claim from the one the
  # AC makes, and the difference is not academic: `Mix.raise` inside
  # `Mix.Task.rerun` is caught by the caller, while the exit code is what a
  # human, a script or a merge gate actually sees. So this mode runs the real
  # binary and reads the real status.

  defp exit_status do
    header("EXIT STATUS — the OS-level claim AC1 makes, measured rather than inferred")

    require_harness!()
    edges = read(@edges)
    committed = File.read!(@crosswalk_out)

    out = tmp("exit-positive")
    {_, code} = os_run(out, [])

    IO.puts(
      "  POSITIVE  unmutated: exit #{code}, output #{if File.exists?(out), do: "written", else: "ABSENT"}"
    )

    ok = code == 0 and File.exists?(out) and File.read!(out) == committed
    verdict("exit 0, and the bytes equal the committed artefact", ok)
    File.rm(out)
    halt_unless(ok)

    IO.puts("")

    for {label, expected, doc} <- [
          {"G14  an edge duplicated verbatim", "G14 — repeated (member, claim, tag) triples",
           update_in(edges["edges"], &[hd(&1) | &1])},
          {"G15  one edge dropped", "G15 — the population this file derives",
           dropped_edge(edges)},
          {"G15  one declared_unmatched member dropped", "G15 — the population this file derives",
           update_in(edges["declared_unmatched"], &tl/1)},
          {"G15  the declared counts lie", "G15 — `the_population_this_file_declares`",
           put_in(edges, ["the_population_this_file_declares", "members"], 22)}
        ] do
      path = write_tmp("edges", doc)
      o = tmp("exit-mutated")
      {output, c} = os_run(o, ["--edges", path])
      File.rm(path)

      cause =
        output
        |> String.split("\n")
        |> Enum.find("", &String.contains?(&1, "** (Mix) " <> expected))

      wrote = File.exists?(o)
      File.rm(o)

      IO.puts("  #{label}")
      IO.puts("           exit #{c}, output file #{if wrote, do: "WRITTEN", else: "not written"}")
      IO.puts("           #{String.slice(cause, 0, 96)}")

      good = c == 1 and not wrote and cause != ""
      verdict("nonzero, naming #{String.slice(expected, 0, 3)}, and nothing written", good)
      halt_unless(good)
    end

    # RESTORED, at the OS level too.
    back = tmp("exit-restored")
    {_, c} = os_run(back, [])
    same = c == 0 and File.read!(back) == committed
    File.rm(back)
    verdict("RESTORED — exit 0 and byte-identical again", same)
    halt_unless(same)

    IO.puts("""

      Measured, not asserted: ~1 s per run, which is why this is done per falsification
      class rather than once. A refusal that raises in-VM but exits 0 would pass C1a's
      control and fail the AC.
    """)
  end

  # === the falsified inputs, shared by the modes =============================

  defp dropped_edge(edges) do
    # Drop an edge whose member has NO other edge, so the member set really
    # shrinks. Dropping one of a member's several edges would leave the
    # population intact and test something else.
    keys = Enum.map(edges["edges"], & &1["member"]["register_key"])

    once =
      Enum.find(
        edges["edges"],
        &(Enum.count(keys, fn k -> k == &1["member"]["register_key"] end) == 1)
      )

    update_in(edges["edges"], fn es -> Enum.reject(es, &(&1 == once)) end)
  end

  defp duplicated_anchor(edges) do
    attribution = read(@attribution)
    dupe = Enum.find(attribution["rows"], &((&1["tokens"] || []) != []))
    doctored = update_in(attribution["rows"], &[dupe | &1])
    path = write_tmp("attribution", doctored)
    doc = put_in(edges, ["the_population_this_file_declares", "selector", "source"], path)

    try do
      build(doc, attribution: path)
    after
      File.rm(path)
    end
  end

  defp drifted_manifest_status do
    manifest = read(@manifest)

    doctored =
      update_in(manifest["scenarios"], fn [s | rest] ->
        [update_in(s["checks"], fn [c | cs] -> [Map.put(c, "status", "FAILURE") | cs] end) | rest]
      end)

    with_manifest(doctored)
  end

  defp drifted_manifest_key do
    manifest = read(@manifest)

    doctored =
      update_in(manifest["scenarios"], fn [s | rest] ->
        [
          update_in(s["checks"], fn [c | cs] ->
            [put_in(c, ["key", Access.at(3)], c["name"] <> "X") | cs]
          end)
          | rest
        ]
      end)

    with_manifest(doctored)
  end

  defp short_manifest do
    manifest = read(@manifest)
    with_manifest(put_in(manifest, ["arithmetic", "total"], 174))
  end

  defp with_manifest(doc) do
    path = write_tmp("manifest", doc)

    try do
      crosswalk(tmp("manifest-mutated"), manifest: path)
    after
      File.rm(path)
    end
  end

  defp other_harness do
    # A real build, not a fabricated path: the same dist with one byte appended,
    # so the file reads and the sha256 differs. Pointing at a nonexistent path
    # would exercise File.read!, not the provenance guard.
    path = Path.join(System.tmp_dir!(), "mes99-harness-#{System.unique_integer([:positive])}.js")
    File.write!(path, File.read!(@harness) <> "\n")

    try do
      crosswalk(tmp("harness-mutated"), harness: path)
    after
      File.rm(path)
    end
  end

  # === plumbing =============================================================

  defp build(doc, overrides \\ []) do
    path = write_tmp("edges", doc)
    out = tmp("mutated")

    try do
      crosswalk(out, Keyword.put(overrides, :edges, path))
    after
      File.rm(path)
      File.rm(out)
    end
  end

  defp regenerate(edges_doc) do
    path = write_tmp("edges", edges_doc)
    out = tmp("regenerated")

    try do
      crosswalk(out, edges: path)
      read(out)
    after
      File.rm(path)
      File.rm(out)
    end
  end

  defp args(out, o) do
    base = [
      "--edges",
      Keyword.get(o, :edges, @edges),
      "--manifest",
      Keyword.get(o, :manifest, @manifest),
      "--denominator",
      @denominator,
      "--register",
      @register,
      "--attribution",
      Keyword.get(o, :attribution, @attribution),
      "--a3-axes",
      @a3_axes,
      "--c1-axes",
      @c1_axes,
      "--harness",
      Keyword.get(o, :harness, @harness),
      "-o",
      out
    ]

    case Keyword.get(o, :verdicts_from) do
      nil -> base
      v -> base ++ ["--verdicts-from", v]
    end
  end

  defp crosswalk(out, o \\ []), do: Mix.Task.rerun("conformance.crosswalk", args(out, o))

  defp os_run(out, extra) do
    o = Keyword.new(Enum.chunk_every(extra, 2), fn ["--" <> k, v] -> {String.to_atom(k), v} end)

    System.cmd("mix", ["conformance.crosswalk" | args(out, o)], stderr_to_stdout: true)
  end

  defp positive(label) do
    out = tmp("positive")
    crosswalk(out)
    bytes = byte_size(File.read!(out))
    File.rm(out)
    IO.puts("  POSITIVE  #{label} (#{bytes} bytes)")
  end

  defp refusal_message(fun) do
    fun.()
    :did_not_refuse
  rescue
    e -> Exception.message(e)
  end

  # A refusal is only evidence for the class it was planted to cause. `expected`
  # is the fragment (or fragments) the generator's own message must carry, so a
  # mutation that refuses for an unrelated reason FAILS here rather than printing
  # a green `refused` line.
  defp refuses(label, expected, fun) do
    case refusal_message(fun) do
      :did_not_refuse ->
        IO.puts("  DID NOT REFUSE  #{label}")
        System.halt(1)

      msg ->
        IO.puts("  refused  #{label}")
        IO.puts("           #{first_line(msg)}")

        case Enum.reject(expected, &String.contains?(msg, &1)) do
          [] ->
            :ok

          missing ->
            IO.puts("           REFUSED FOR THE WRONG REASON")
            IO.puts("           expected the message to carry: #{inspect(missing)}")
            System.halt(1)
        end
    end
  end

  defp verdict(label, true), do: IO.puts("  ok    #{label}")

  defp verdict(label, false) do
    IO.puts("  FAIL  #{label}")
  end

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
    do: Path.join(System.tmp_dir!(), "mes99-#{stem}-#{System.unique_integer([:positive])}.json")

  defp write_tmp(stem, doc) do
    path = tmp(stem)
    File.write!(path, Jason.encode!(doc))
    path
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp sha(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
  defp first_line(msg), do: msg |> String.split("\n") |> Enum.reject(&(&1 == "")) |> hd()
  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

CrosswalkFalsificationControls.run(System.argv())
