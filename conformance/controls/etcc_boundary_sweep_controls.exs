# Controls for the boundary-liveness sweep (MES-88).
#
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs guards
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs prose
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs harness
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs host
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs drift
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs register
#
# WHY A SCRIPT AND NOT AN ExUnit TEST. Same reason as `etcc_register_controls.exs`: a
# test file added here lands in the very suite the sweep measures. Under `test/mcp/` it
# would join the ET-CC population it validates; under `test/conformance/` it would still
# move the unit count every L1 measurement is taken against. An instrument that changes
# its own denominator by existing is a perturbation, not a test.
#
# EVERY ZERO HERE CARRIES TWO CONTROLS, and they are not interchangeable:
#
#   * a POSITIVE control proves the sweep reached the population — each guard prints the
#     number of rows or entries it actually scanned, and `harness` proves the sweep can
#     reach the TREE by requiring a known-LIVE direction to come back LIVE;
#   * a MUTATION proves the predicate CAN fire — `guards` breaks each condition on a copy
#     and shows the refusal.
#
# Neither substitutes for the other. A guard reporting "0 violations" is otherwise
# indistinguishable between "the predicate fired and nothing matched" and "the sweep
# never reached the population" (S8-3). The mutations are COMMITTED here rather than run
# once in /tmp, because evidence that lived only in a run tree is not re-runnable
# evidence.

defmodule ETCCBoundarySweepControls do
  alias MCP.Conformance.BoundarySweep, as: Sweep

  @paths Sweep.paths()

  def run(["guards"]), do: guards()
  def run(["prose"]), do: prose()
  def run(["harness"]), do: harness()
  def run(["host"]), do: host()
  def run(["drift"]), do: drift()
  def run(["register"]), do: register()

  def run(_) do
    IO.puts("usage: guards | prose | harness | host | drift | register")
    System.halt(2)
  end

  # --- guards 23-27, each shown FIRING ---

  defp guards do
    header("GUARDS 23-27 — each condition mutated on a copy and shown to refuse")

    doc = read(@paths.boundaries)
    rows = doc["boundaries"]

    # Subjects found by PREDICATE, never by id, so a later re-measurement that moves a
    # verdict does not silently leave a control pointing at the wrong row.
    dead = Enum.find(rows, &(&1["verdict"] == "dead"))

    # Guard 23's distinguishing subject: live count ZERO but verdict LIVE. Guard 20 in
    # etcc_register.ex comprehends over `verdict: "dead"` only, so it cannot see this row
    # at all — 10 of the 50 directions are this shape.
    zero_live_but_live =
      Enum.find(rows, &(Sweep.live_count(&1) == 0 and &1["verdict"] == "live"))

    ambiguous =
      Enum.find(rows, fn b -> Enum.any?(Sweep.derive_spec(b), &(&1["occurrences"] > 1)) end)

    cases = [
      {23,
       "a direction with live count 0 and NO l2 record, whose verdict is LIVE — the 10-row hole in guard 20",
       fn rs -> put(rs, zero_live_but_live, %{"l2" => nil}) end},
      {23, "a direction with live count 0 and NO l2 record, whose verdict is DEAD",
       fn rs -> put(rs, dead, %{"l2" => nil}) end},
      {23, "a direction with live count 0 whose l2 record says it was never run",
       fn rs -> put(rs, dead, %{"l2" => Map.put(dead["l2"], "ran", false)}) end},
      {23, "a direction with live count 0 whose l2 record carries no verdict",
       fn rs -> put(rs, dead, %{"l2" => Map.put(dead["l2"], "verdict", nil)}) end},
      {24, "a DEAD direction whose mutation reddened NONE of its own units (impotent)",
       fn rs -> put(rs, dead, %{"reddened_outside_own" => dead["reddened_total"]}) end},
      {25, "a DEAD direction whose l2 has no byte_probe",
       fn rs -> put(rs, dead, %{"l2" => Map.put(dead["l2"], "byte_probe", nil)}) end},
      {25,
       "a DEAD direction whose l2 has no call_site_enumeration — the probe ALONE cannot establish DEAD",
       fn rs -> put(rs, dead, %{"l2" => Map.put(dead["l2"], "call_site_enumeration", "")}) end},
      {26, "a mutation_spec entry whose recorded occurrence count is not what the tree holds",
       fn rs -> put(rs, ambiguous, %{"mutation_spec" => bump(ambiguous, "occurrences", 99)}) end},
      {26, "a mutation_spec entry whose FROM no longer occurs at all",
       fn rs ->
         put(rs, ambiguous, %{"mutation_spec" => bump(ambiguous, "from", "ZZ_NOT_IN_TREE")})
       end},
      {27, "a mutation_spec entry that does not render back to its committed prose",
       fn rs -> put(rs, dead, %{"mutation_spec" => bump(dead, "to", "ZZ_DRIFTED")}) end},
      {27, "a mutation_spec with FEWER entries than the prose it is a reading of",
       fn rs -> put(rs, dead, %{"mutation_spec" => tl(dead["mutation_spec"])}) end},
      {27, "a mutation_spec with MORE entries than the prose it is a reading of",
       fn rs ->
         put(rs, dead, %{"mutation_spec" => [hd(dead["mutation_spec"]) | dead["mutation_spec"]]})
       end}
    ]

    results =
      for {n, name, mutate} <- cases do
        outcome =
          try do
            Sweep.check_table!(mutate.(rows))
            :ACCEPTED
          rescue
            e in RuntimeError -> {:REFUSED, first_line(Exception.message(e))}
          end

        case outcome do
          {:REFUSED, why} ->
            IO.puts("  REFUSED  [#{n}] #{name}\n           -> #{why}")
            :ok

          :ACCEPTED ->
            IO.puts("  ACCEPTED [#{n}] #{name}   <-- THE GUARD DID NOT FIRE")
            :error
        end
      end

    IO.puts("\n  #{Enum.count(results, &(&1 == :ok))}/#{length(results)} guard mutations fired.")

    # POSITIVE CONTROL 1 — the unmutated table passes, so the guards above are
    # DISCRIMINATING rather than refusing everything.
    scanned = Sweep.check_table!(rows)
    IO.puts("\n  CONTROL (discrimination): the unmutated table passes all five guards.")

    # POSITIVE CONTROL 2 — the population each guard actually reached. Without this a
    # clean pass is indistinguishable from a guard that scanned nothing.
    IO.puts("  CONTROL (reach): rows in the table #{length(rows)}")

    for {k, v} <- Enum.sort(scanned), do: IO.puts("                   #{k} = #{v}")

    IO.puts("""

      Guard 23's reach is the point of the first case above: #{Enum.count(rows, &(Sweep.live_count(&1) == 0))} \
    directions have a live
      count of zero, of which #{Enum.count(rows, &(Sweep.live_count(&1) == 0 and &1["verdict"] == "live"))} are recorded LIVE. \
    Guard 20 comprehends over
      `verdict: "dead"` and cannot see those; §2.3(d) states the trigger on the COUNT.
    """)

    if Enum.any?(results, &(&1 == :error)), do: System.halt(1)
  end

  # --- prose: the round trip, over every committed mutation line ---

  defp prose do
    header("PROSE ROUND TRIP — mutation_spec renders back to the committed `mutation`")
    rows = read(@paths.boundaries)["boundaries"]

    pairs =
      Enum.flat_map(rows, fn b ->
        Enum.zip(b["mutation_spec"] || [], b["mutation"] || [])
      end)

    bad = Enum.reject(pairs, fn {e, line} -> Sweep.render_prose(e) == line end)

    IO.puts("  entries compared: #{length(pairs)}   (POSITIVE CONTROL — the population reached)")
    IO.puts("  differing:        #{length(bad)}")

    # MUTATION — the predicate must be able to fire on this very population.
    {e, line} = hd(pairs)
    drifted = Map.put(e, "to", e["to"] <> "ZZ")

    IO.puts(
      "  mutation control: a drifted TO is detected: #{Sweep.render_prose(drifted) != line}"
    )

    if bad != [] do
      for {e2, line2} <- Enum.take(bad, 3) do
        IO.puts("    prose    #{inspect(line2)}")
        IO.puts("    rendered #{inspect(Sweep.render_prose(e2))}")
      end

      System.halt(1)
    end

    IO.puts("""

      This is what makes the duplication safe. `mutation_spec` is an ADDITION — the
      authored prose stays byte-identical, so AC1's byte-comparison is about the bytes
      MES-81 committed and not about a re-serialisation authored this week. The two
      cannot drift because guard 27 requires this round trip on every entry.
    """)
  end

  # --- harness: the sweep's own positive control ---

  defp harness do
    header("HARNESS — a known-LIVE direction must come back LIVE")

    rows = read(@paths.boundaries)["boundaries"]

    subject =
      rows
      |> Enum.filter(&(&1["verdict"] == "live" and &1["established_by"] == "L1"))
      |> Enum.max_by(&Sweep.live_count/1)

    IO.puts("  subject: #{subject["id"]} (recorded live count #{Sweep.live_count(subject)})")
    IO.puts("  running one mutation cycle...\n")

    out = Sweep.sweep(only: [subject["id"]], log: &IO.puts("    " <> &1))
    got = Enum.find(out["boundaries"], &(&1["id"] == subject["id"]))

    IO.puts("\n  verdict: #{got["verdict"]}  (live count #{Sweep.live_count(got)})")

    IO.puts("""

      WHY THIS IS THE CONTROL THE GUARDS CANNOT BE. Guards 23-27 read the TABLE. They
      would all pass over a harness that never applied a mutation, never ran the suite,
      and reported zero redness everywhere — which is also what a genuinely dead tree
      looks like. Requiring a known-LIVE direction to come back LIVE is what proves the
      harness reached the tree at all. A DEAD result here would be the alarm.
    """)

    unless got["verdict"] == "live", do: System.halt(1)
  end

  # --- host: skip condition (c), shown to fire on a REAL host difference ---

  # S8-11's closure. Conditions (a) and (b) of the end-of-sprint skip are git diffs, and
  # a git diff cannot see the host; `test_helper.exs` excludes three
  # `:requires_live_harness` conformance tests where `node` or the pinned harness is
  # absent, so the SAME TREE has two populations. The mutation below is not a fabricated
  # fingerprint string — it takes `node` off PATH and re-measures, which is the actual
  # difference the condition exists to catch, and then SHOWS THE SUITE SHRINK that makes
  # it matter. A control that only mutated the recorded string would prove the comparison
  # works and leave the thing being compared unestablished.
  defp host do
    header("HOST — skip condition (c): the input to L1 that no git diff can see")

    control = read(@paths.boundaries)["control"]
    recorded = control["host"]
    current = Sweep.host()

    # POSITIVE CONTROL (reach) — both sides were actually read, and printed.
    IO.puts("  recorded with the table: #{inspect(recorded && recorded["fingerprint"])}")
    IO.puts("  this host:               #{inspect(current["fingerprint"])}")

    # NEGATIVE CONTROL — an identical host must NOT fire. Without it, a checker that
    # always reports "differ" would print the same PASS as a discriminating one.
    same = Sweep.host_check(control, current)
    IO.puts("\n  NEGATIVE CONTROL  identical host -> #{elem(same, 0)}")

    stripped = without_node()

    # MUTATION — the predicate must be able to fire, on a real host and not a string.
    mutated = if stripped, do: measure_without_node(stripped), else: nil
    differs = mutated && Sweep.host_check(control, mutated)

    if mutated do
      IO.puts("  MUTATION          node off PATH -> #{inspect(mutated["fingerprint"])}")
      IO.puts("                    host_check -> #{elem(differs, 0)}")
    else
      IO.puts("  MUTATION          SKIPPED — no `node` on PATH to remove on this host")
    end

    # FAIL-CLOSED — both "not recorded" and "could not tell" must refuse a skip.
    unrecorded = Sweep.host_check(%{}, current)
    unknown = Sweep.host_check(control, Map.put(current, "harness", "unknown"))
    IO.puts("  FAIL-CLOSED       no host recorded  -> #{elem(unrecorded, 0)}")
    IO.puts("  FAIL-CLOSED       host unreadable   -> #{elem(unknown, 0)}")

    parses = summary_shapes()
    refuses = record_host_refuses?()

    ok =
      elem(same, 0) == :match and
        elem(unrecorded, 0) == :unrecorded and
        elem(unknown, 0) == :differ and
        parses and refuses and
        (is_nil(mutated) or elem(differs, 0) == :differ)

    IO.puts("\n  discriminating: #{ok}")

    IO.puts("""

      WHY THE MUTATION RUNS THE SUITE. The fingerprint is only worth comparing if the
      thing it fingerprints moves, so the run above is taken WITH `node` removed and its
      summary printed beside the committed `suite_total` (#{control["suite_total"]}).
      Same tree, same commit, both git skip conditions empty — and a different
      population. That is S8-11, and condition (c) is what it costs to close it.
    """)

    unless ok, do: System.halt(1)
  end

  # PATH with node's directory removed, or nil when there is nothing to remove.
  defp without_node do
    case System.find_executable("node") do
      nil ->
        nil

      exe ->
        dir = Path.dirname(exe)

        System.get_env("PATH", "")
        |> String.split(":")
        |> Enum.reject(&(&1 == dir))
        |> Enum.join(":")
    end
  end

  # Re-measure the host AND the population under the stripped PATH, then put it back.
  # `System.put_env/2` changes the VM's own environment, which is what both
  # `System.find_executable/1` and every child `System.cmd/3` inherits — so this is the
  # same absence a host without node has, not a simulation of it.
  defp measure_without_node(stripped) do
    original = System.get_env("PATH", "")

    try do
      System.put_env("PATH", stripped)
      host = Sweep.host()
      IO.puts("\n  re-running the suite with node off PATH (this is the point) ...")
      run = Sweep.run_suite()
      IO.puts("  suite with node:    #{committed_total()} tests (the committed control block)")
      IO.puts("  suite without node: #{run.summary}")
      host
    after
      System.put_env("PATH", original)
    end
  end

  defp committed_total, do: read(@paths.boundaries)["control"]["suite_total"]

  # The recorded side is only worth comparing if it cannot be attached to a population the
  # table was never taken at. `record_host!/1` claims to refuse that; a claim about a
  # precondition is shown by MUTATION, not by reading the source — so the committed
  # `suite_total` is falsified in a COPY and the recorder must refuse over it. It runs the
  # suite to find out, which is the point: the refusal is a comparison against a real
  # measurement, not against the number already in the file.
  defp record_host_refuses? do
    doc = read(@paths.boundaries)
    bad = put_in(doc, ["control", "suite_total"], 999_999)
    path = write_tmp(bad)

    IO.puts("\n  re-measuring against a FALSIFIED committed suite_total (999999) ...")

    outcome =
      try do
        Sweep.record_host!(boundaries: path, log: fn _ -> :ok end)
        :ACCEPTED
      rescue
        e in RuntimeError -> {:REFUSED, first_line(Exception.message(e))}
      after
        File.rm(path)
      end

    case outcome do
      {:REFUSED, why} ->
        IO.puts("  RECORD REFUSED    #{why}")
        true

      :ACCEPTED ->
        IO.puts("  RECORD ACCEPTED   <-- THE PRECONDITION DID NOT FIRE")
        false
    end
  end

  # S8-18. The summary regex had to widen to see an `(N excluded)` line at all — which is
  # the ONE transcript shape the host axis produces, and the shape it could not read. A
  # parser widened for one shape and not re-checked on the other is how a transcript
  # change goes wrong, so BOTH are asserted, with a line that must NOT be read as a
  # summary as the negative control.
  defp summary_shapes do
    cases = [
      {"complete host", "13 doctests, 1021 tests, 0 failures",
       "13 doctests, 1021 tests, 0 failures"},
      {"host with exclusions", "13 doctests, 1018 tests, 0 failures (3 excluded)",
       "13 doctests, 1018 tests, 0 failures (3 excluded)"},
      {"NEGATIVE: not a summary", "Finished in 20.1 seconds (0.8s async, 19.2s sync)", nil}
    ]

    results =
      for {name, line, expected} <- cases do
        got = Sweep.parse_run("...\n#{line}\n").summary
        IO.puts("  SUMMARY SHAPE     #{String.pad_trailing(name, 22)} -> #{inspect(got)}")
        got == expected
      end

    Enum.all?(results)
  end

  # --- drift: AC4's table-side demonstration, with the unmutated table as control ---

  defp drift do
    header("DRIFT — a flipped verdict is caught, and the rows it would move are NAMED")

    doc = read(@paths.boundaries)
    rows = doc["boundaries"]

    # A member-bearing DEAD direction, so the "rows it would move" list is non-empty.
    register = read(@paths.register)["rows"]

    subject =
      rows
      |> Enum.filter(&(&1["verdict"] == "dead"))
      |> Enum.max_by(fn b -> Enum.count(register, &member_of?(&1, b["id"])) end)

    drifted = %{doc | "boundaries" => put(rows, subject, %{"verdict" => "live"})}

    # CONTROL FIRST — the unmutated table against itself must report NOTHING. Without
    # this, the detection below is also what a checker that always fires would print.
    control = Sweep.check(doc, doc)

    IO.puts(
      "  CONTROL: committed table vs itself -> #{length(control.verdict_diffs)} verdict diff(s), " <>
        "#{length(control.measurement_deltas)} measurement delta(s)"
    )

    result = Sweep.check(doc, drifted)

    IO.puts("\n  DRIFTED: one verdict flipped in the committed copy ->")

    for d <- result.verdict_diffs do
      IO.puts("    #{d["id"]}")

      for f <- d["fields"],
          do: IO.puts("      #{f["field"]}: #{inspect(f["was"])} -> #{inspect(f["now"])}")

      IO.puts("      would move #{length(d["et_cc_rows"])} ET-CC row(s):")
      for k <- Enum.take(d["et_cc_rows"], 5), do: IO.puts("        #{k}")

      if length(d["et_cc_rows"]) > 5,
        do: IO.puts("        ... and #{length(d["et_cc_rows"]) - 5} more")
    end

    ok = control.verdict_diffs == [] and result.verdict_diffs != []
    IO.puts("\n  discriminating: #{ok}")
    unless ok, do: System.halt(1)
  end

  # --- register: the guards are WIRED, not merely present ---

  # `ETCCRegister.build/1` calls `BoundarySweep.check_table!/2`, so guards 23, 24, 25 and
  # 27 fail the register build closed the way guard 20 already did. That is a claim about
  # a call site, and a call site that is present is not the same as one that fires — so it
  # is shown by MUTATION here rather than asserted from reading the source.
  #
  # Guard 26 is deliberately NOT wired in: it is the only one that is a function of the
  # TREE rather than the table, and the ratified cadence puts lib/-drift detection at the
  # sprint boundary (CLAUDE.md, End-of-Sprint Procedure step 4). The last case below is
  # the NEGATIVE control for exactly that — a guard-26 violation must NOT refuse a
  # register build, and a control that only shows things failing cannot show a boundary.
  defp register do
    header("REGISTER WIRING — guards 23/24/25/27 fail the register build closed; 26 does not")

    doc = read(@paths.boundaries)
    rows = doc["boundaries"]
    dead = Enum.find(rows, &(&1["verdict"] == "dead"))
    zero_live_but_live = Enum.find(rows, &(Sweep.live_count(&1) == 0 and &1["verdict"] == "live"))

    cases = [
      {23, :refuse, "strip the l2 off a zero-live direction recorded LIVE",
       fn rs -> put(rs, zero_live_but_live, %{"l2" => nil}) end},
      {24, :refuse, "make a DEAD direction's mutation impotent",
       fn rs -> put(rs, dead, %{"reddened_outside_own" => dead["reddened_total"]}) end},
      {25, :refuse, "drop a DEAD direction's call_site_enumeration",
       fn rs -> put(rs, dead, %{"l2" => Map.put(dead["l2"], "call_site_enumeration", "")}) end},
      {27, :refuse, "drift a mutation_spec entry away from its prose",
       fn rs -> put(rs, dead, %{"mutation_spec" => bump(dead, "to", "ZZ_DRIFTED")}) end},
      {26, :accept, "break a mutation_spec's resolution against lib/ (NEGATIVE control)",
       fn rs -> put(rs, dead, %{"mutation_spec" => bump(dead, "occurrences", 99)}) end}
    ]

    results =
      for {n, expected, name, mutate} <- cases do
        path = write_tmp(%{doc | "boundaries" => mutate.(rows)})

        actual =
          try do
            MCP.Conformance.ETCCRegister.build(boundaries: path)
            :accept
          rescue
            e in RuntimeError -> {:refuse, first_line(Exception.message(e))}
          after
            File.rm(path)
          end

        case {expected, actual} do
          {:refuse, {:refuse, why}} ->
            IO.puts("  REFUSED  [#{n}] #{name}\n           -> #{why}")
            :ok

          {:accept, :accept} ->
            IO.puts("  ACCEPTED [#{n}] #{name}   <-- as intended: 26 is a sprint-boundary check")
            :ok

          {:refuse, :accept} ->
            IO.puts("  ACCEPTED [#{n}] #{name}   <-- THE GUARD IS NOT WIRED IN")
            :error

          {:accept, {:refuse, why}} ->
            IO.puts(
              "  REFUSED  [#{n}] #{name}   <-- GUARD 26 IS WIRED IN AND MUST NOT BE\n           -> #{why}"
            )

            :error
        end
      end

    IO.puts("\n  #{Enum.count(results, &(&1 == :ok))}/#{length(results)} as expected.")

    # POSITIVE CONTROL — the unmutated table still builds the register.
    MCP.Conformance.ETCCRegister.build()
    IO.puts("  CONTROL: the unmutated boundaries file builds the register cleanly.")

    if Enum.any?(results, &(&1 == :error)), do: System.halt(1)
  end

  # --- helpers ---

  defp write_tmp(doc) do
    path =
      Path.join(
        System.tmp_dir!(),
        "etcc-boundaries-mutant-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(doc))
    path
  end

  defp member_of?(row, id),
    do: row["label"] == "ET-CC" and is_list(row["boundary"]) and id in row["boundary"]

  defp read(path), do: path |> File.read!() |> Jason.decode!()

  defp put(rows, target, changes),
    do: Enum.map(rows, &if(&1["id"] == target["id"], do: Map.merge(&1, changes), else: &1))

  defp bump(row, field, value) do
    [first | rest] = row["mutation_spec"]
    [Map.put(first, field, value) | rest]
  end

  defp first_line(msg), do: msg |> String.split("\n") |> hd()

  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

ETCCBoundarySweepControls.run(System.argv())
