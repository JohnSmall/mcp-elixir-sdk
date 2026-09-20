# C2 (MES-98) — the controls on the bucket projections and their generator.
#
#     mix run conformance/controls/bucket_projection_controls.exs noop
#     mix run conformance/controls/bucket_projection_controls.exs movement
#     mix run conformance/controls/bucket_projection_controls.exs refusals
#     mix run conformance/controls/bucket_projection_controls.exs all
#     mix run conformance/controls/bucket_projection_controls.exs guard-mutation
#
# WHY THIS FILE EXISTS. C2's whole claim is that the ten views are PROJECTIONS
# of one matrix and not a second enumeration of it. That claim is unfalsifiable
# from the output alone: a hand-built view and a projected view of the same
# crosswalk are byte-identical. What distinguishes them is what happens when the
# MATRIX MOVES — so every mode below mutates the crosswalk and re-runs the real
# generator.
#
# THE DISCIPLINES
#
#   * A control never seen red is a claim (S8-3/S8-4). `noop` runs --check green
#     AND red, on a planted byte, a missing file and an extra file.
#   * Every movement asserts that EXACTLY ONE row moved, and that it moved to
#     the SPECIFIC correct view. Without the first clause a renderer that
#     reshuffled everything would pass (S9-18); without the second, any move
#     would do.
#   * Every refusal asserts the fragment the generator's own message carries.
#     "It raised" is not "the planted defect was caught" — six green `refused`
#     lines would pass on a generator that refused everything for one unrelated
#     reason.
#   * Every zero gets two controls: the unmutated build is the negative control
#     in the same run, and it is re-run AFTER the mutations as well as before.
#   * `guard-mutation` removes each guard in turn from `@guards` and re-runs the
#     input that guard catches, so each guard is shown ABLE to fail rather than
#     merely observed passing.
#
# NOTHING IS WRITTEN INTO THE REPO. Mutated crosswalks and projected output go
# to temp paths; the one mechanism mutation is an in-VM `Code.compile_string`
# restored in an `after`, so a seat death mid-run cannot leave the shared clone
# mutated (S8-14).

defmodule BucketProjectionControls do
  alias MCP.Conformance.BucketProjection

  @crosswalk "docs/conformance/crosswalk-2026-07-28.json"
  @bucket_zero "docs/conformance/bucket-0-2026-07-28.json"
  @committed "docs/conformance/buckets"
  @module_src "conformance/lib/mcp/conformance/bucket_projection.ex"

  @rev "2026-07-28"

  def run(["noop"]), do: noop()
  def run(["movement"]), do: movement()
  def run(["refusals"]), do: refusals()
  def run(["guard-mutation"]), do: guard_mutation()

  def run(["all"]) do
    noop()
    movement()
    refusals()
    guard_mutation()
    IO.puts("\n== ALL FOUR MODES GREEN ==\n")
  end

  def run(_) do
    IO.puts("usage: noop | movement | refusals | guard-mutation | all")
    System.halt(2)
  end

  # === noop — AC3, and it runs FIRST =======================================
  #
  # A byte-comparable regeneration is what makes every later diff mean
  # something. It is also the check most likely to be quietly vacuous, so it is
  # shown red three ways: a planted byte, a deleted file and an added one.

  defp noop do
    header("NO-OP — byte-comparable regeneration, green and then RED three ways (AC3)")

    {out, status} = os_check(@committed)
    IO.puts("  POSITIVE  --check against #{@committed}: exit #{status}")
    IO.puts("            #{first_line(out)}")
    verdict("the committed views regenerate byte-identically, at the OS exit status", status == 0)
    halt_unless(status == 0)

    scratch = copy_committed()

    try do
      planted = Path.join(scratch, "bucket-5a-#{@rev}.json")
      File.write!(planted, File.read!(planted) <> "\n")

      red("a planted byte in bucket-5a", scratch, [
        "differ from a fresh projection (1)",
        "bucket-5a"
      ])

      File.write!(planted, String.trim_trailing(File.read!(planted)) <> "\n")
      verdict("restored — the planted byte is gone", elem(os_check(scratch), 1) == 0)

      File.rm!(Path.join(scratch, "bucket-6-#{@rev}.json"))
      red("a DELETED view", scratch, ["expected and absent (1)", "bucket-6"])

      File.write!(Path.join(scratch, "bucket-7-#{@rev}.json"), "{}\n")
      red("an EXTRA view nobody projected", scratch, ["present and not expected (1)", "bucket-7"])
    after
      File.rm_rf!(scratch)
    end

    {_, status2} = os_check(@committed)
    verdict("RESTORED — --check is green again against the committed directory", status2 == 0)
    halt_unless(status2 == 0)
  end

  defp red(label, dir, expected) do
    {out, status} = os_check(dir)

    IO.puts("  RED       #{label}: exit #{status}")

    case Enum.reject(expected, &String.contains?(out, &1)) do
      [] when status == 1 ->
        IO.puts(
          "            #{String.trim(Enum.find(String.split(out, "\n"), "", &String.contains?(&1, hd(expected))))}"
        )

      missing ->
        IO.puts("            FAILED — exit #{status}, message missing #{inspect(missing)}")
        IO.puts(out)
        System.halt(1)
    end
  end

  defp copy_committed do
    dir = tmp_dir("noop")
    File.mkdir_p!(dir)
    File.cp_r!(@committed, dir)
    dir
  end

  # === movement — AC1 ======================================================
  #
  # The projection is a function of the matrix. Move a row in the crosswalk and
  # the row moves in the views — to the specific view its stored fields send it
  # to, and nothing else moves with it.

  defp movement do
    header("MOVEMENT — mutate the CROSSWALK, and the projection follows it (AC1)")

    doc = read(@crosswalk)
    base = placements(doc)

    # The expected row total is DERIVED from the crosswalk and A5's artefact, not
    # written down here: a hard-coded figure in a positive control is a figure
    # nothing re-derives (S9-11), and it would go stale the moment C1b lands.
    expect = expected_rows(doc)

    IO.puts("  POSITIVE  the unmutated crosswalk projects #{map_size(base)} rows across 11 views")
    IO.puts("            #{summary(base)}")

    verdict(
      "the baseline places every row of all four universes (#{expect} derived from the inputs)",
      map_size(base) == expect
    )

    halt_unless(map_size(base) == expect)

    five = index_of(doc, &(&1["bucket"] == "5"))
    four_a = index_of(doc, &(&1["bucket"] == "4a"))

    moved(
      "M1  a bucket-5 cell's oc_key[0]: client -> server",
      base,
      put_in(doc, ["cells", Access.at(five), "oc_key", Access.at(0)], "server"),
      [{key_at(doc, five), "5b", "5a"}],
      "The leg refinement is the half most at risk of being re-derived: 5a/5b are not in " <>
        "the ratified bucket function at all. Here the split follows a STORED field."
    )

    m2 = put_in(doc, ["cells", Access.at(five), "bucket"], "3")

    moved(
      "M2  a bucket-5 cell's stored bucket: \"5\" -> \"3\"",
      base,
      m2,
      [{key_at(doc, five), "5b", "3"}],
      "AC4's real content: bucket 3 renders empty because the DATA is empty, not because " <>
        "the renderer hard-codes it. Under this mutation it renders one row and its " <>
        "emptiness_reason disappears."
    )

    empties = emptiness_codes(m2)
    IO.puts("            bucket 3 emptiness_reason after M2: #{inspect(empties["3"])}")
    verdict("bucket 3 stops declaring itself empty", empties["3"] == nil)
    halt_unless(empties["3"] == nil)

    moved(
      "M3  a 4a cell's shape: contradicting -> partial, stored bucket LEFT at \"4a\"",
      base,
      put_in(doc, ["cells", Access.at(four_a), "shape"], "partial"),
      [],
      "A DEFERENCE control, and the ruling is deliberate. `bucket = f(verdicts, shape)` " <>
        "would send this row to 4b; C2 renders it on the STORED bucket and it does not " <>
        "move. Detecting the disagreement would mean a second copy of MatchKey.bucket/1 " <>
        "here — the two-records-that-can-disagree drift the single matrix exists to " <>
        "remove. Matrix consistency is C1's reconcile! and C3's guards."
    )

    m4(doc, base)
    m5(doc, base)

    after_base = placements(doc)
    verdict("RESTORED — the unmutated crosswalk projects the baseline again", after_base == base)
    halt_unless(after_base == base)
  end

  # M4 — give a bucket-1 member an edge. The coherent form of the mutation: a
  # member that acquires an edge is no longer declared unmatched, so its
  # declared_unmatched record goes too. Leaving it would be a crosswalk that
  # contradicts itself, which the member-partition guard refuses (and `refusals`
  # shows it doing).
  defp m4(doc, base) do
    member = doc["buckets"]["bucket_1"]["members"] |> Enum.sort() |> hd()
    template = Enum.find(doc["cells"], &(&1["bucket"] == "5"))

    cell =
      template
      |> put_in(["member", "register_key"], member)
      |> put_in(["claim"], template["claim"] <> " (M4)")

    mutated =
      doc
      |> update_in(["cells"], &(&1 ++ [cell]))
      |> update_in(["declared_unmatched"], fn rows ->
        Enum.reject(rows, &(&1["member"]["register_key"] == member))
      end)

    after_ = placements(mutated)
    {moved, added, removed} = diff(base, after_)

    show("M4  a bucket-1 member acquires an edge (and its declared_unmatched record goes)")
    print_diff(moved, added, removed)

    ok =
      moved == [] and
        added == [{[member, cell["claim"], cell["tag"]], "5b"}] and
        removed == [{member, "1"}]

    verdict("bucket 1 loses exactly that member, and exactly one new edge lands in 5b", ok)
    halt_unless(ok)

    eq = equations(mutated)
    IO.puts("            #{eq["declared_members"]}")
    holds = String.contains?(eq["declared_members"], "1(4) + members_with_edges(17)")
    verdict("the member equation re-balances at 21 = 4 + 17", holds)
    halt_unless(holds)
  end

  # M5 — the check-side leg split, which M1 does not reach. Drop every edge of
  # one CLIENT check and it must enter 2b, not 2a.
  defp m5(doc, base) do
    tag = sole_edge_check(doc)
    mutated = update_in(doc["cells"], fn cs -> Enum.reject(cs, &(&1["tag"] == tag)) end)
    dropped = Enum.find(doc["cells"], &(&1["tag"] == tag))

    after_ = placements(mutated)
    {moved, added, removed} = diff(base, after_)

    show("M5  every edge of one CLIENT check dropped: #{short(tag)}")
    print_diff(moved, added, removed)

    ok =
      moved == [] and added == [{tag, "2b"}] and
        removed == [{edge_key(dropped), "5b"}]

    verdict("the check enters 2b and NOT 2a, and only its own edge leaves", ok)
    halt_unless(ok)

    empties = emptiness_codes(mutated)
    IO.puts("            2a: #{inspect(empties["2a"])}   2b: #{inspect(empties["2b"])}")

    verdict(
      "2a still declares itself empty; 2b no longer does",
      empties["2a"] != nil and empties["2b"] == nil
    )

    halt_unless(empties["2a"] != nil and empties["2b"] == nil)
  end

  defp moved(label, base, mutated, expected, why) do
    after_ = placements(mutated)
    {moved, added, removed} = diff(base, after_)

    show(label)
    print_diff(moved, added, removed)

    ok = moved == expected and added == [] and removed == []
    verdict("exactly #{length(expected)} row(s) moved, to the specific expected view", ok)
    IO.puts("            #{indent(why)}")
    halt_unless(ok)
  end

  defp print_diff(moved, added, removed) do
    for {k, from, to} <- moved, do: IO.puts("            MOVED    #{from} -> #{to}   #{short(k)}")
    for {k, v} <- added, do: IO.puts("            ADDED    -> #{v}   #{short(k)}")
    for {k, v} <- removed, do: IO.puts("            REMOVED  #{v} ->   #{short(k)}")

    if moved == [] and added == [] and removed == [],
      do: IO.puts("            (no row moved, was added or was removed)")
  end

  defp diff(base, after_) do
    shared = base |> Map.keys() |> Enum.filter(&Map.has_key?(after_, &1))

    moved =
      shared
      |> Enum.filter(&(Map.fetch!(base, &1) != Map.fetch!(after_, &1)))
      |> Enum.map(&{&1, Map.fetch!(base, &1), Map.fetch!(after_, &1)})
      |> Enum.sort()

    added =
      after_ |> Map.drop(Map.keys(base)) |> Enum.sort()

    removed = base |> Map.drop(Map.keys(after_)) |> Enum.sort()

    {moved, added, removed}
  end

  # === refusals ============================================================

  defp refusals do
    header("REFUSALS — every guard, planted and shown to refuse, naming its own guard")

    doc = read(@crosswalk)

    positive("the unmutated crosswalk projects cleanly")

    cases = refusal_cases(doc)
    Enum.each(cases, fn {label, expected, mutated} -> refuses(label, expected, mutated) end)

    IO.puts("""

      #{length(cases)} refusals, each on the cheapest input that could carry that lie, against
      ONE unmutated positive control in the same run. Each asserts the fragment the
      generator's own message carries — #{length(cases)} green `refused` lines would otherwise pass on a
      generator that refused everything for one unrelated reason (S9-18).
    """)

    positive("RESTORED — the unmutated crosswalk still projects cleanly")
    matcher_control()
  end

  defp refusal_cases(doc) do
    five = index_of(doc, &(&1["bucket"] == "5"))

    [
      {"vacuum          an EMPTY matrix: no cells, every declared member unmatched",
       ["[vacuum]", "VACUUM — the crosswalk carries no cells"], empty_matrix(doc)},
      {"leg             a cell's oc_key[0] is `gateway`",
       ["[leg]", "LEG GUARD", "1 cells and 0 declared checks"],
       put_in(doc, ["cells", Access.at(five), "oc_key", Access.at(0)], "gateway")},
      {"leg             a DECLARED CHECK's token carries an unknown leg",
       ["[leg]", "LEG GUARD", "0 cells and 1 declared checks"],
       update_in(doc, ["population", "checks"], fn [c | rest] -> [retag(c) | rest] end)},
      {"edge_partition  a cell's stored bucket is `7` — a view nobody renders",
       ["[edge_partition]", "EDGE PARTITION", "cells that reach no view (1)"],
       put_in(doc, ["cells", Access.at(five), "bucket"], "7")},
      {"member_partition a cell names a member outside the declared population",
       ["[member_partition]", "MEMBER PARTITION", "outside the declared population (1)"],
       put_in(
         doc,
         ["cells", Access.at(five), "member", "register_key"],
         "MCP.NotDeclaredTest/test x"
       )},
      {"member_partition a declared_unmatched record dropped — bucket 1 without a record",
       ["[member_partition]", "MEMBER PARTITION", "no declared_unmatched record (1)"],
       update_in(doc["declared_unmatched"], &tl/1)},
      {"check_partition  a cell's tag names a check outside the declared population",
       ["[check_partition]", "CHECK PARTITION", "outside the declared population (1)"],
       put_in(doc, ["cells", Access.at(five), "tag"], "oc:client/request-metadata/no-such/NoSuch")},
      {"(reused)        an EMPTY declared population — C1's own refusal-without-a-universe",
       [":empty_population"], put_in(doc, ["population", "members"], [])}
    ]
  end

  # A crosswalk with no edges satisfies every partition check here PERFECTLY:
  # all 21 members fall into bucket 1, all 14 checks into 2a/2b, every set
  # comparison is equal and all three equations reconcile. That is S9-15's
  # vacuum in this artefact's own shape, and it is what `:vacuum` fires on.
  defp empty_matrix(doc) do
    unmatched =
      Enum.map(doc["population"]["members"], &%{"member" => %{"register_key" => &1}})

    doc |> Map.put("cells", []) |> Map.put("declared_unmatched", unmatched)
  end

  defp retag(tag) do
    case String.split(tag, "/") do
      ["oc:" <> _leg | rest] -> Enum.join(["oc:gateway" | rest], "/")
      _ -> tag
    end
  end

  # The matcher's own control, driven as a subprocess because the limb being
  # demonstrated is the halt itself and a halt cannot be observed from inside
  # the run it ends.
  defp matcher_control do
    header("THE MATCHER'S OWN CONTROL — a refusal naming the WRONG guard must fail")

    {out, status} =
      System.cmd("mix", ["run", __ENV__.file, "wrong_reason"], stderr_to_stdout: true)

    IO.puts(filter(out, ~r/refused|WRONG|expected the message|DID NOT/))
    verdict("the control exits NONZERO when a refusal names a different guard", status == 1)
    halt_unless(status == 1)
  end

  def wrong_reason do
    header("WRONG REASON — the expectation matcher, shown refusing a real refusal")

    doc = read(@crosswalk)

    IO.puts("""
      The mutation below (an empty matrix) DOES refuse — `refusals` shows it refusing at
      [vacuum]. Here it is asserted to refuse at [check_partition] instead. A matcher that
      only checked "something was raised" would print `refused` and move on.
    """)

    refuses(
      "[check_partition] <- deliberately wrong: this input refuses at [vacuum]",
      ["[check_partition]"],
      empty_matrix(doc)
    )

    IO.puts("  DID NOT HALT — the matcher accepted a refusal naming a different guard.")
    System.halt(1)
  end

  # === guard-mutation ======================================================
  #
  # Five guards that all end in "no refusal" are equally consistent with five
  # guards that CANNOT refuse. So each one is removed from `@guards` in turn —
  # a single-line edit to the module source, recompiled in-VM — and the input it
  # catches is re-run. The refusal must stop naming it. What happens instead is
  # printed rather than assumed: some of these guards are layered, and one of
  # them is the only thing standing between this generator and a clean-looking
  # projection of an empty matrix.

  defp guard_mutation do
    header("GUARD MUTATION — each guard removed in turn, and shown to have been load-bearing")

    doc = read(@crosswalk)
    source = File.read!(@module_src)

    # Captured BEFORE the first recompile: after one, `BucketProjection.guards/0`
    # answers for the MUTATED module, and the anchor for the next removal would
    # be built from a list that no longer matches the source on disk.
    all = BucketProjection.guards()

    # EVERY refusal case that names a guard, not one per guard — `:leg` and
    # `:member_partition` each have two limbs, and a mode that picked one of
    # each would leave the other limb observed passing and never shown able to
    # fail.
    cases =
      Enum.filter(doc |> refusal_cases(), fn {_l, expected, _m} ->
        Enum.any?(all, &(hd(expected) == "[#{&1}]"))
      end)

    try do
      Enum.each(cases, &one_guard_removed(&1, source, all))
    after
      recompile!(source)
    end

    positive("RESTORED — the module is back and the unmutated crosswalk projects cleanly")
  end

  defp one_guard_removed({label, expected, mutated}, source, all) do
    guard = expected |> hd() |> String.trim_leading("[") |> String.trim_trailing("]")
    recompile!(without_guard(source, String.to_existing_atom(guard), all))

    outcome = outcome(mutated)

    IO.puts("  #{String.pad_trailing(to_string(guard), 17)}#{label}")
    IO.puts("      -> #{describe(outcome)}")

    still_named? = match?({:refused, m} when is_binary(m), outcome) and named?(outcome, guard)

    verdict(
      "removing :#{guard} stops the refusal naming it — the guard is what caught it",
      not still_named?
    )

    halt_unless(not still_named?)
  end

  defp named?({:refused, msg}, guard), do: String.contains?(msg, "[#{guard}]")
  defp named?(_, _), do: false

  defp describe(:projected),
    do: "PROJECTED CLEANLY — nothing else catches this. The guard is the only line of defence."

  defp describe({:refused, msg}),
    do: "still refuses, at a LATER guard: #{first_line(msg)}"

  defp without_guard(source, guard, all) do
    old = "  @guards " <> inspect(all)
    new = "  @guards " <> inspect(all -- [guard])

    if String.contains?(source, old),
      do: String.replace(source, old, new),
      else: halt("the @guards anchor is not in #{@module_src} as #{inspect(old)}")
  end

  defp recompile!(source) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source, @module_src)
  after
    Code.put_compiler_option(:ignore_module_conflict, false)
  end

  # === plumbing ============================================================

  # Read the projection back out of the files the real generator wrote: one map
  # from a row's own key to the view it landed in. Nothing here re-derives a
  # bucket — it reads where the generator PUT each row.
  defp placements(doc) do
    dir = project_to(doc)

    try do
      for name <- File.ls!(dir), reduce: %{} do
        acc ->
          view = Jason.decode!(File.read!(Path.join(dir, name)))
          id = view["bucket"] || view_id(name)

          if id == "roll-up",
            do: acc,
            else: Enum.reduce(view["rows"], acc, &Map.put(&2, row_key(id, &1), id))
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp view_id("escalated-" <> _), do: "escalated"
  defp view_id("roll-up-" <> _), do: "roll-up"

  defp row_key("0", row), do: row["key"]
  defp row_key("1", row), do: get_in(row, ["member", "register_key"])
  defp row_key(id, row) when id in ["2a", "2b"], do: row["tag"]
  defp row_key(_id, row), do: edge_key(row)

  defp edge_key(cell), do: [cell["member"]["register_key"], cell["claim"], cell["tag"]]

  defp emptiness_codes(doc) do
    dir = project_to(doc)

    try do
      Map.new(BucketProjection.bucket_ids(), fn id ->
        view = Jason.decode!(File.read!(Path.join(dir, "bucket-#{id}-#{@rev}.json")))
        {id, get_in(view, ["emptiness_reason", "code"])}
      end)
    after
      File.rm_rf!(dir)
    end
  end

  defp equations(doc) do
    dir = project_to(doc)

    try do
      dir
      |> Path.join("roll-up-#{@rev}.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("equations")
      |> Map.new(fn e ->
        terms = Enum.map_join(e["terms"], " + ", &"#{&1["term"]}(#{&1["count"]})")
        {e["universe"], "#{e["universe"]}: #{e["total"]} = #{terms} [#{e["holds"]}]"}
      end)
    after
      File.rm_rf!(dir)
    end
  end

  defp project_to(doc) do
    path = write_tmp(doc)
    dir = tmp_dir("out")

    try do
      buckets(["--crosswalk", path, "-o", dir])
      dir
    after
      File.rm(path)
    end
  end

  defp outcome(doc) do
    dir = project_to(doc)
    File.rm_rf!(dir)
    :projected
  rescue
    e -> {:refused, Exception.message(e)}
  end

  defp refuses(label, expected, mutated) do
    case outcome(mutated) do
      :projected ->
        IO.puts("  DID NOT REFUSE  #{label}")
        System.halt(1)

      {:refused, msg} ->
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

  defp positive(label) do
    dir = project_to(read(@crosswalk))
    n = dir |> File.ls!() |> length()
    File.rm_rf!(dir)
    IO.puts("  POSITIVE  #{label} (#{n} files)")
  end

  defp os_check(dir) do
    System.cmd("mix", ["conformance.buckets", "--check", "-o", dir], stderr_to_stdout: true)
  end

  defp buckets(args) do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)

    try do
      Mix.Task.rerun("conformance.buckets", ["--bucket-zero", @bucket_zero | args])
    after
      Mix.shell(shell)
    end
  end

  # edges + (declared members with no edge) + (declared checks with no edge) +
  # A5's out-of-denominator checks. Every term read off an input file.
  defp expected_rows(doc) do
    members = length(doc["population"]["members"])
    checks = length(doc["population"]["checks"])
    with_edges = doc["cells"] |> Enum.map(&get_in(&1, ["member", "register_key"])) |> Enum.uniq()
    tagged = doc["cells"] |> Enum.map(& &1["tag"]) |> Enum.uniq()

    bucket_0 =
      @bucket_zero |> read() |> Map.fetch!("checks") |> Enum.count(&(not &1["matchable"]))

    length(doc["cells"]) + (members - length(with_edges)) + (checks - length(tagged)) + bucket_0
  end

  defp index_of(doc, pred), do: Enum.find_index(doc["cells"], pred)
  defp key_at(doc, i), do: doc["cells"] |> Enum.at(i) |> edge_key()

  # A check with exactly ONE edge, on the client leg, whose member carries other
  # edges — so dropping it moves the CHECK and leaves the member universe alone.
  defp sole_edge_check(doc) do
    tags = Enum.frequencies_by(doc["cells"], & &1["tag"])
    members = Enum.frequencies_by(doc["cells"], &get_in(&1, ["member", "register_key"]))

    doc["cells"]
    |> Enum.filter(fn c ->
      tags[c["tag"]] == 1 and Enum.at(c["oc_key"], 0) == "client" and c["bucket"] == "5" and
        members[get_in(c, ["member", "register_key"])] > 1
    end)
    |> hd()
    |> Map.fetch!("tag")
  end

  defp summary(base) do
    base
    |> Enum.frequencies_by(fn {_k, v} -> v end)
    |> Enum.sort()
    |> Enum.map_join("  ", fn {v, n} -> "#{v}:#{n}" end)
  end

  defp short(key) when is_list(key), do: key |> List.last() |> short()
  defp short(key) when is_binary(key), do: String.slice(key, 0, 92)

  defp show(label), do: IO.puts("\n  #{label}")
  defp verdict(label, true), do: IO.puts("  ok    #{label}")
  defp verdict(label, false), do: IO.puts("  FAIL  #{label}")
  defp halt_unless(true), do: :ok
  defp halt_unless(false), do: System.halt(1)

  defp halt(why) do
    IO.puts("  FAIL  " <> why)
    System.halt(1)
  end

  defp tmp_dir(stem),
    do: Path.join(System.tmp_dir!(), "mes98-#{stem}-#{System.unique_integer([:positive])}")

  defp write_tmp(doc) do
    path =
      Path.join(System.tmp_dir!(), "mes98-crosswalk-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(doc))
    path
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp first_line(msg), do: msg |> String.split("\n") |> Enum.reject(&(&1 == "")) |> List.first()

  defp filter(out, re),
    do: out |> String.split("\n") |> Enum.filter(&(&1 =~ re)) |> Enum.join("\n")

  defp indent(text), do: text |> String.split("\n") |> Enum.join("\n            ")
  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

case System.argv() do
  ["wrong_reason"] -> BucketProjectionControls.wrong_reason()
  argv -> BucketProjectionControls.run(argv)
end
