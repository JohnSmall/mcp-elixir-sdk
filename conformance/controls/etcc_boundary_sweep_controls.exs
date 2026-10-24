# Controls for the boundary-liveness sweep (MES-88).
#
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs guards
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs prose
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs harness
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs host
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs drift
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs register
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs prefix
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs probe
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs probe-mutation
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs census
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs census-real
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs census-plant
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs emit
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs emit-mutation
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs verify
#     mix run conformance/controls/etcc_boundary_sweep_controls.exs verify-mutation
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
  alias MCP.Conformance.ExUnitRows

  @paths Sweep.paths()

  def run(["guards"]), do: guards()
  def run(["prose"]), do: prose()
  def run(["harness"]), do: harness()
  def run(["host"]), do: host()
  def run(["drift"]), do: drift()
  def run(["register"]), do: register()
  def run(["prefix"]), do: prefix()
  def run(["probe"]), do: probe()
  def run(["probe-mutation"]), do: probe_mutation()
  def run(["census"]), do: census()
  def run(["census-real"]), do: census_real()
  def run(["census-plant"]), do: census_plant()
  def run(["emit"]), do: emit()
  def run(["emit-mutation"]), do: emit_mutation()
  def run(["verify"]), do: verify_mode()
  def run(["verify-mutation"]), do: verify_mutation()

  def run(_) do
    IO.puts(
      "usage: guards | prose | harness | host | drift | register | prefix | probe | " <>
        "probe-mutation | census | census-real | census-plant | emit | emit-mutation | " <>
        "verify | verify-mutation"
    )

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
    live = Enum.find(rows, &(&1["verdict"] == "live"))

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
       end},
      {27,
       "a LIVE direction recording occurrences 0 for a FROM that occurs nowhere — no guard saw it before MES-173",
       fn rs -> put(rs, live, zero_site()) end},
      {27, "a DEAD direction recording occurrences 0 for a FROM that occurs nowhere",
       fn rs -> put(rs, dead, zero_site()) end}
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
        got = Sweep.summary_line(["...", line])
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
  # TREE rather than the table, and anchor drift is DoD gate 8 (`mix conformance.sweep
  # --verify`, docs/procedure/gate-8.md). The last case below is the NEGATIVE control for
  # exactly that — a guard-26 violation must NOT refuse a register build, and a control
  # that only shows things failing cannot show a boundary. Its second limb (MES-176) runs
  # the SAME mutation through the gate-8 path and requires GUARD 26 to refuse it, so the
  # build's acceptance is shown to be of a real guard-26 violation rather than a no-op.
  defp register do
    header("REGISTER WIRING — guards 23/24/25/27 fail the register build closed; 26 does not")

    doc = read(@paths.boundaries)
    rows = doc["boundaries"]
    dead = Enum.find(rows, &(&1["verdict"] == "dead"))
    live = Enum.find(rows, &(&1["verdict"] == "live"))
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
      {27, :refuse, "record occurrences 0 on a LIVE direction (MES-173)",
       fn rs -> put(rs, live, zero_site()) end},
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
            IO.puts("  ACCEPTED [#{n}] #{name}   <-- as intended: 26 is gate 8's check")
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

    # [26], second limb: the same mutated table through `check_table!/2` with the tree
    # check ON — what gate 8 runs. It must refuse, and for guard 26's own reason.
    {26, :accept, _, mutate26} = List.last(cases)

    g26 =
      try do
        Sweep.check_table!(mutate26.(rows))

        IO.puts(
          "  ACCEPTED [26] the same mutation through gate 8's path   <-- GUARD 26 DID NOT FIRE"
        )

        :error
      rescue
        e in RuntimeError ->
          why = first_line(Exception.message(e))

          if String.starts_with?(why, "GUARD 26:") do
            IO.puts(
              "  REFUSED  [26] the same mutation through gate 8's path\n           -> #{why}"
            )

            :ok
          else
            IO.puts(
              "  REFUSED  [26] the same mutation through gate 8's path   <-- NOT BY GUARD 26\n           -> #{why}"
            )

            :error
          end
      end

    results = results ++ [g26]

    IO.puts("\n  #{Enum.count(results, &(&1 == :ok))}/#{length(results)} as expected.")

    # POSITIVE CONTROL — the unmutated table still builds the register.
    MCP.Conformance.ETCCRegister.build()
    IO.puts("  CONTROL: the unmutated boundaries file builds the register cleanly.")

    if Enum.any?(results, &(&1 == :error)), do: System.halt(1)
  end

  # --- prefix: the directory exclusion, end to end, both ways (MES-137) ---

  # §2.3(d) as amended on MES-137 (`[authored 29618 | ratified 29619]`) keeps every unit
  # under `test/conformance/` out of the live count. The units in
  # `test/conformance/boundary_sweep_prefix_test.exs` hold the predicate; this holds the
  # WIRING, which only a real mutation cycle can show.
  #
  #   * POSITIVE — the committed table, unmutated. `Error (encode)` must come back DEAD by
  #     L2 while a `test/conformance/` unit is among what reddened (so the exclusion did
  #     work, rather than having nothing to exclude), and Dispatch must stay LIVE with its
  #     `test/conformance/` units reddened and none of them in `live_units`.
  #   * MUTATION — the same table with the prefix REMOVED. `--check` must report the
  #     Sprint 12 drift again, `Error (encode)` dead -> live, by name. Without this limb
  #     the positive is also what a sweep that never read the prefix would print.
  @prefix_subject "MCP.Protocol.Error (encode)"
  @prefix_neighbour "MCP.Server.Dispatch"
  @instrument_module "MCP.Conformance.AdjudicationsTest"

  defp prefix do
    header(
      "PREFIX — test/conformance/ is out of every live count, and removing it brings the drift back"
    )

    doc = read(@paths.boundaries)
    IO.puts("  committed prefixes: #{inspect(doc["live_column_excluded_prefixes"])}\n")

    IO.puts("  POSITIVE — the committed table, #{@prefix_subject} and #{@prefix_neighbour}:")
    out = Sweep.sweep(only: [@prefix_subject, @prefix_neighbour], log: &IO.puts("    " <> &1))
    pos = Sweep.check(out, doc)
    subject = row(out, @prefix_subject)
    neighbour = row(out, @prefix_neighbour)

    positive = [
      {"#{@prefix_subject} reads DEAD by L2",
       subject["verdict"] == "dead" and subject["established_by"] == "L2"},
      {"#{@prefix_subject}: #{@instrument_module} reddened (#{instrument(subject)})",
       instrument(subject) >= 1},
      {"#{@prefix_neighbour} stays LIVE (live count #{Sweep.live_count(neighbour)})",
       neighbour["verdict"] == "live" and Sweep.live_count(neighbour) > 0},
      {"#{@prefix_neighbour}: #{@instrument_module} reddened (#{instrument(neighbour)})",
       instrument(neighbour) >= 1},
      {"no test/conformance/ unit in either live_units",
       Enum.all?([subject, neighbour], &(conformance_units(&1) == []))},
      {"--check against the committed table: #{length(pos.verdict_diffs)} verdict diff(s)",
       pos.verdict_diffs == []}
    ]

    IO.puts("")
    Enum.each(positive, &report_limb/1)

    IO.puts("\n  MUTATION — the prefix removed from a copy of the table:")
    path = write_tmp(Map.delete(doc, "live_column_excluded_prefixes"))

    mut =
      try do
        Sweep.sweep(boundaries: path, only: [@prefix_subject], log: &IO.puts("    " <> &1))
      after
        File.rm(path)
      end

    diffs = Sweep.check(mut, doc).verdict_diffs
    drifted = Enum.find(diffs, &(&1["id"] == @prefix_subject))
    verdict = drifted && Enum.find(drifted["fields"], &(&1["field"] == "verdict"))

    for d <- diffs,
        f <- d["fields"],
        do:
          IO.puts(
            "    DRIFTED  #{d["id"]}  #{f["field"]}: #{inspect(f["was"])} -> #{inspect(f["now"])}"
          )

    IO.puts("")

    mutation = [
      {"--check names #{@prefix_subject} as drifted, dead -> live",
       verdict != nil and verdict["was"] == "dead" and verdict["now"] == "live"},
      {"the drift is carried by a test/conformance/ unit (#{inspect(conformance_units(row(mut, @prefix_subject)))})",
       conformance_units(row(mut, @prefix_subject)) != []}
    ]

    Enum.each(mutation, &report_limb/1)

    if Enum.any?(positive ++ mutation, fn {_, ok} -> not ok end), do: System.halt(1)
  end

  # --- probe: the blind-baseline refusal (MES-174), each conjunct shown FIRING ---

  # The probe went blind at MES-161 and nothing said so: 12 dispatch scenarios returned
  # one shared `-32602`, so every L2 silence on those paths was vacuous, and the MES-171
  # sweep printed it in neither section. The red case below is NOT fabricated — it is the
  # probe exactly as it was committed at the last tip where it was blind, read from git.
  @blind_probe_rev "5e5d18e"

  defp probe do
    header("PROBE — a blind baseline is refused, each conjunct independently")

    dir =
      Path.join(System.tmp_dir!(), "etcc-probe-controls-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    try do
      blind = Path.join(dir, "blind_probe.exs")
      {src, 0} = System.cmd("git", ["show", "#{@blind_probe_rev}:#{@paths.probe}"])
      File.write!(blind, src)

      sighted = Sweep.probe(Path.join(dir, "p1.txt"))

      results = [
        p1(sighted),
        r1(blind, dir),
        r2(sighted),
        r3(sighted),
        r4(sighted),
        r5(sighted),
        w1(blind, dir)
      ]

      IO.puts("")
      Enum.each(results, &report_limb/1)
      if Enum.any?(results, fn {_, ok} -> not ok end), do: System.halt(1)
    after
      File.rm_rf!(dir)
    end
  end

  # P1 — the positive control. The real probe at this tip passes, and every scenario is
  # accounted for by its class, so a pass is not "the predicate saw nothing".
  defp p1(sighted) do
    IO.puts("  P1  the committed probe at this tip")

    for {k, v} <- Enum.sort(sighted),
        do:
          IO.puts("      #{String.pad_trailing(k, 34)} #{inspect(Sweep.classify_probe_value(v))}")

    ok =
      try do
        IO.puts("      passes: #{inspect(Sweep.check_probe_baseline!(sighted))}")
        map_size(sighted) == 15
      rescue
        e in RuntimeError ->
          IO.puts("      REFUSED (unexpected): #{first_line(e.message)}")
          false
      end

    {"P1 committed probe passes, all 15 scenarios classified", ok}
  end

  # R1 — the natural red case: the probe as committed at the blind tip, RUN, not mocked.
  defp r1(blind, dir) do
    IO.puts("\n  R1  the blind probe from git (#{@blind_probe_rev})")
    base = Sweep.probe(Path.join(dir, "r1.txt"), blind)
    msg = refusal(base)
    print_refusal(msg)

    ok =
      msg != nil and msg =~ "[distinct] 1 group(s)" and msg =~ "    12 x " and
        msg =~ "[reached] 12 scenario(s)"

    {"R1 blind probe refused on BOTH conjuncts, 12 collided and 12 unreached", ok}
  end

  # R2 — one scenario errors, with bytes of its own: only :reached can see it.
  defp r2(sighted) do
    IO.puts("\n  R2  one dispatched scenario turned into a distinct JSON-RPC error")

    err =
      inspect(~s({"error":{"code":-32602,"message":"Invalid params"},"id":1,"jsonrpc":"2.0"}))

    msg = refusal(Map.put(sighted, "prompts/get", err))
    print_refusal(msg)
    ok = msg != nil and msg =~ "[reached]" and not (msg =~ "[distinct]") and msg =~ "prompts/get"
    {"R2 a single unreached scenario refused by [reached] alone", ok}
  end

  # R3 — two RESULTS share bytes: only :distinct can see it.
  defp r3(sighted) do
    IO.puts("\n  R3  two result scenarios given the same bytes")
    msg = refusal(Map.put(sighted, "tools/call text", sighted["tools/call image"]))
    print_refusal(msg)
    ok = msg != nil and msg =~ "[distinct]" and not (msg =~ "[reached]")
    {"R3 two colliding results refused by [distinct] alone", ok}
  end

  # R4 — a dispatched scenario that produced NO reply (CR F1, `31987`). `dispatched/2`
  # writes `inspect(other)` for any non-`{:reply, ...}` outcome and the script stores
  # `inspect/1` of that, so both the literal `inspect({:noreply, %{}})` the ruling names
  # and the doubly-inspected form the real probe file would hold are checked. Each must
  # be refused by `[reached]` ALONE, naming the scenario — before correction round 1 the
  # class exemption let both through.
  defp r4(sighted) do
    IO.puts("\n  R4  one dispatched scenario turned into a {:noreply, %{}} non-reply")

    forms = %{
      "inspect({:noreply, %{}})" => inspect({:noreply, %{}}),
      "as the probe file holds it" => inspect(inspect({:noreply, %{}}))
    }

    ok =
      Enum.all?(forms, fn {label, v} ->
        msg = refusal(Map.put(sighted, "prompts/get", v))
        IO.puts("      form: #{label}")
        print_refusal(msg)

        msg != nil and msg =~ "[reached] 1 scenario(s)" and not (msg =~ "[distinct]") and
          msg =~ "prompts/get: got :not_a_response, want :result"
      end)

    {"R4 a dispatched {:noreply, %{}} refused by [reached] alone, both forms", ok}
  end

  # R5 — a DECLARED non-reply that comes back as a reply: the declaration has gone stale,
  # and that is refused rather than silently tolerated.
  defp r5(sighted) do
    IO.puts("\n  R5  a declared not-a-response scenario turned into a JSON-RPC result")
    reply = inspect(~s({"id":1,"jsonrpc":"2.0","result":{"stale":true}}))
    msg = refusal(Map.put(sighted, "SSE frame of a notification", reply))
    print_refusal(msg)

    ok =
      msg != nil and not (msg =~ "[distinct]") and
        msg =~ "SSE frame of a notification: got :result, want :not_a_response"

    {"R5 a stale not-a-response declaration refused by [reached] alone", ok}
  end

  # --- probe-mutation: R4 is shown able to FAIL, and it is the fix that makes it pass ---

  # Recompiles `MCP.Conformance.BoundarySweep` IN MEMORY with correction round 1's fix
  # reverted — the class exemption put back into `:reached` — and requires R4 to go RED
  # under it, then recompiles the committed source and requires R4 green again. Nothing
  # is written to disk; the module is restored before the script exits.
  @sweep_src "conformance/lib/mcp/conformance/boundary_sweep.ex"
  @fix_anchor "          want = expected_class(k),\n          got != want,"
  @reverted "          want = expected_class(k),\n" <>
              "          got != :not_a_response or want != :result,\n" <>
              "          got != want,"

  defp probe_mutation do
    header("PROBE-MUTATION — R4 goes red when the F1 fix is reverted")

    src = File.read!(@sweep_src)
    n = src |> String.split(@fix_anchor) |> length() |> Kernel.-(1)
    IO.puts("  fix anchor occurrences in #{@sweep_src}: #{n} (must be 1)")
    if n != 1, do: System.halt(1)

    dir = Path.join(System.tmp_dir!(), "etcc-probe-mut-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      sighted = Sweep.probe(Path.join(dir, "base.txt"))

      Code.compile_string(String.replace(src, @fix_anchor, @reverted), @sweep_src)
      IO.puts("\n  MUTANT (class exemption restored):")
      {_, mutant_ok} = r4(sighted)

      Code.compile_string(src, @sweep_src)
      IO.puts("\n  RESTORED (committed source):")
      {_, restored_ok} = r4(sighted)

      results = [
        {"R4 goes RED under the reverted fix", not mutant_ok},
        {"R4 is green again on the committed source", restored_ok}
      ]

      IO.puts("")
      Enum.each(results, &report_limb/1)
      if Enum.any?(results, fn {_, ok} -> not ok end), do: System.halt(1)
    after
      Code.compile_string(src, @sweep_src)
      File.rm_rf!(dir)
    end
  end

  # W1 — the refusal is WIRED: the sweep, driven with the blind probe, refuses before it
  # runs the baseline suite or applies a single mutation.
  defp w1(blind, dir) do
    IO.puts("\n  W1  Sweep.sweep/1 driven with the blind probe")
    {:ok, lines} = Agent.start_link(fn -> [] end)
    log = fn l -> Agent.update(lines, &[l | &1]) end

    msg =
      try do
        Sweep.sweep(only: ["MCP.Server.Connection"], probe: blind, tmp: dir, log: log)
        nil
      rescue
        e in RuntimeError -> e.message
      end

    logged = Agent.get(lines, &Enum.reverse/1)
    Agent.stop(lines)
    print_refusal(msg)
    ran_suite = Enum.any?(logged, &(&1 =~ "mix test"))
    mutated = Enum.any?(logged, &(&1 =~ "[1/"))
    IO.puts("      ran the baseline suite: #{ran_suite}; reached a mutation cycle: #{mutated}")
    ok = msg != nil and msg =~ "[distinct]" and not ran_suite and not mutated
    {"W1 sweep refuses the blind probe before any suite run or mutation", ok}
  end

  defp refusal(baseline) do
    Sweep.check_probe_baseline!(baseline)
    nil
  rescue
    e in RuntimeError -> e.message
  end

  defp print_refusal(nil), do: IO.puts("      NOT refused")

  defp print_refusal(msg) do
    for l <- msg |> String.split("\n") |> Enum.take(8), do: IO.puts("      | " <> l)
  end

  defp row(doc, id), do: Enum.find(doc["boundaries"], &(&1["id"] == id))
  defp instrument(b), do: Map.get(b["reddened_by_module"] || %{}, @instrument_module, 0)

  defp conformance_units(b),
    do: Enum.filter(b["live_units"] || [], &String.starts_with?(&1, "test/conformance/"))

  defp report_limb({name, true}), do: IO.puts("  HOLDS   #{name}")
  defp report_limb({name, false}), do: IO.puts("  FAILS   #{name}   <-- ")

  # --- census: GUARD 34, every kind shown FIRING (MES-208, MES-150 folded in) ---

  # Until MES-208 the sweep parsed ExUnit's CLI transcript for failure headers, and
  # silently dropped every failure numbered 100 or above and every setup_all-invalidated
  # test. The PO ruled (`34141`) that every test is recorded, so the units now come off
  # `MCP.Conformance.ExUnitRows`' rows and GUARD 34 refuses any run whose rows do not
  # account for every test. Three sections, split so each fits a 10-minute run:
  #
  #   * `census` — seconds, pure: a synthetic run of 120 failures (past the old cap),
  #     16 invalid and 30 passes; the POSITIVE, then one plant per refusal kind, each
  #     required to refuse with a line starting `GUARD 34: <kind>`. `units` has no pure
  #     plant (a plant on the artefact cannot make the derivation miscount); M1 in the
  #     MES-208 close-out is its mutation.
  #   * `census-real` — POSITIVE on a real run: an ordinary located failure, the Plug
  #     direction unplanted through `Sweep.sweep/1`; then the same plants on that
  #     captured pair, so the refusals are shown on real bytes as well.
  #   * `census-plant` — the real setup_all plant: Plug's `init/1` made to raise on a
  #     /tmp copy of the table, which invalidates ACTest. Every failure AND every invalid
  #     test must be keyed.
  @census_subject "MCP.Transport.StreamableHTTP.Plug"
  @census_invalid_module "MCP.Transport.StreamableHTTP.ACTest"
  @census_plant "lib/mcp/transport/streamable_http/plug.ex: def init(opts) do  ->  " <>
                  "def init(opts) do\n    if opts != :never, do: raise(\"MES-208 plant: " <>
                  "setup_all invalidation\")"

  defp census do
    header("CENSUS — GUARD 34, each kind shown refusing, on a synthetic run")
    {out, artefact} = synthetic_run()
    run = Sweep.read_run(out, artefact)
    IO.puts("  synthetic: #{run.summary} | keyed #{length(run.units)} | rows #{run.rows_total}\n")

    positive = [{"120 failures + 16 invalid all keyed (136)", length(run.units) == 136}]
    Enum.each(positive, &report_limb/1)
    ok = census_limbs(out, artefact, run.rows_total)
    if not ok or Enum.any?(positive, fn {_, v} -> not v end), do: System.halt(1)
  end

  defp census_real do
    header("CENSUS-REAL — POSITIVE: an ordinary located failure through the real sweep")
    tmp = census_tmp("real")
    out_doc = Sweep.sweep(only: [@census_subject], tmp: tmp, log: &IO.puts("    " <> &1))
    got = row(out_doc, @census_subject)
    {out, artefact} = captured(tmp)
    {:ok, s} = ExUnitRows.parse_summary(got["suite_summary"])

    positive = [
      {"the run passed GUARD 34 (the sweep returned)", true},
      {"keyed #{got["reddened_total"]} = summary #{s["failures"]} failures + #{s["invalid"]} invalid",
       got["reddened_total"] == s["failures"] + s["invalid"]},
      {"unlocated_failures is 0", got["unlocated_failures"] == 0},
      {"live count #{Sweep.live_count(got)} > 0, verdict #{got["verdict"]}",
       Sweep.live_count(got) > 0 and got["verdict"] == "live"}
    ]

    IO.puts("")
    Enum.each(positive, &report_limb/1)
    IO.puts("\n  the plants again, on the captured real run:")
    ok = census_limbs(out, artefact, length(artefact["rows"]))
    if not ok or Enum.any?(positive, fn {_, v} -> not v end), do: System.halt(1)
  end

  defp census_plant do
    header("CENSUS-PLANT — setup_all invalidation: every failure AND every invalid test keyed")
    doc = read(@paths.boundaries)

    rows =
      Enum.map(doc["boundaries"], fn b ->
        if b["id"] == @census_subject do
          b = Map.put(b, "mutation", [@census_plant])
          Map.put(b, "mutation_spec", Sweep.derive_spec(b))
        else
          b
        end
      end)

    path = write_tmp(Map.put(doc, "boundaries", rows))
    tmp = census_tmp("plant")

    out_doc =
      try do
        Sweep.sweep(
          boundaries: path,
          only: [@census_subject],
          tmp: tmp,
          log: &IO.puts("    " <> &1)
        )
      after
        File.rm(path)
      end

    got = row(out_doc, @census_subject)
    {_out, artefact} = captured(tmp)
    {:ok, s} = ExUnitRows.parse_summary(got["suite_summary"])
    invalid = Enum.filter(artefact["rows"], &(&1["status"] == "invalid"))
    by_module = got["reddened_by_module"] || %{}

    limbs = [
      {"the plant invalidated tests (summary: #{s["invalid"]} invalid)", s["invalid"] > 0},
      {"keyed #{got["reddened_total"]} = #{s["failures"]} failures + #{s["invalid"]} invalid",
       got["reddened_total"] == s["failures"] + s["invalid"]},
      {"more than 99 keyed (#{got["reddened_total"]}) — the old cap is gone",
       got["reddened_total"] > 99},
      {"all #{length(invalid)} invalid rows are #{@census_invalid_module}, each with file and line",
       invalid != [] and
         Enum.all?(invalid, &(&1["module"] == @census_invalid_module and is_integer(&1["line"])))},
      {"#{@census_invalid_module} carries #{Map.get(by_module, @census_invalid_module, 0)} red " <>
         "unit(s), at least its #{length(invalid)} invalid",
       Map.get(by_module, @census_invalid_module, 0) >= length(invalid)},
      {"unlocated_failures is 0", got["unlocated_failures"] == 0}
    ]

    IO.puts("")
    Enum.each(limbs, &report_limb/1)
    if Enum.any?(limbs, fn {_, v} -> not v end), do: System.halt(1)
  end

  # One plant per refusal kind, over a given (transcript, artefact). The POSITIVE is the
  # pair as given, which must pass. A header-shaped line printed by a test must key
  # nothing and pass, since stdout is never parsed for units any more.
  defp census_limbs(out, artefact, population) do
    rows = artefact["rows"]
    red = Enum.find(rows, &(&1["status"] in ["failed", "invalid"]))
    passed = Enum.find(rows, &(&1["status"] == "passed"))
    [first, second | _] = rows
    with_run = fn changes -> Map.update!(artefact, "run", &Map.merge(&1, changes)) end
    with_rows = fn rs -> Map.put(artefact, "rows", rs) end
    forged_header = "101) test printed by a test (Fake.Mod)"
    coloured_forgery = IO.ANSI.red() <> "1 doctest, 1 test, 0 failures" <> IO.ANSI.reset()
    genuine = Sweep.read_run(out, artefact).summary
    units = length(Sweep.read_run(out, artefact).units)

    plants = [
      {:no_artefact, "the formatter wrote no rows file", {out, :missing, population}},
      {:summary, "a passed row dropped", {out, with_rows.(List.delete(rows, passed)), nil}},
      {:summary_count, "a second summary-shaped line printed by a test",
       {String.replace(out, "\nFinished in", "\n1 doctest, 1 test, 0 failures\nFinished in",
          global: false
        ), artefact, population}},
      {:summary_count, "a COLOURED summary printed by a test before the genuine one (CR F1)",
       {String.replace(out, "\nFinished in", "\n#{coloured_forgery}\nFinished in", global: false),
        artefact, population}},
      {:summary_count, "a COLOURED summary printed after the genuine one (CR F1)",
       {out <> coloured_forgery <> "\n", artefact, population}},
      {:incomplete, "run.complete false", {out, with_run.(%{"complete" => false}), population}},
      {:cross_check, "a module_finished disagreement",
       {out,
        with_run.(%{
          "module_cross_check" => %{"disagreements" => [%{"module" => first["module"]}]}
        }), population}},
      {:collision, "two rows on one key",
       {out, with_rows.([first, Map.put(second, "key", first["key"]) | Enum.drop(rows, 2)]),
        population}},
      {:unlocated, "a red row's line set to nil",
       {out, with_rows.(Enum.map(rows, &if(&1 == red, do: Map.put(&1, "line", nil), else: &1))),
        population}},
      {:population, "a row total off the baseline", {out, artefact, population + 1}}
    ]

    positive =
      [
        {"POSITIVE: the run as given passes GUARD 34",
         Sweep.census(out, artefact, population) == []},
        {"a genuine summary that is itself COLOURED passes, and is recorded plain",
         (fn ->
            o = String.replace(out, genuine, IO.ANSI.red() <> genuine <> IO.ANSI.reset())

            Sweep.census(o, artefact, population) == [] and
              Sweep.read_run(o, artefact).summary == genuine
          end).()},
        {"a header-shaped line printed by a test keys nothing and passes",
         (fn ->
            o =
              String.replace(out, "\nFinished in", "\n#{forged_header}\nFinished in",
                global: false
              )

            Sweep.census(o, artefact, population) == [] and
              length(Sweep.read_run(o, artefact).units) == units
          end).()}
      ]

    Enum.each(positive, &report_limb/1)

    refusals =
      for {kind, name, {o, a, pop}} <- plants do
        msg =
          try do
            Sweep.census!(o, a, pop)
            nil
          rescue
            e in RuntimeError -> e.message
          end

        line =
          msg && Enum.find(String.split(msg, "\n"), &String.starts_with?(&1, "GUARD 34: #{kind}"))

        if line do
          IO.puts("  REFUSED  [#{kind}] #{name}\n           -> #{line}")
          true
        else
          IO.puts(
            "  ACCEPTED [#{kind}] #{name}   <-- GUARD 34 DID NOT NAME THIS KIND #{inspect(msg)}"
          )

          false
        end
      end

    IO.puts("  (units: no pure plant — M1, the derivation narrowed to `failed`, is its mutation)")
    Enum.all?(refusals) and Enum.all?(positive, fn {_, v} -> v end)
  end

  defp synthetic_run do
    mk = fn module, name, line, status ->
      %{
        "key" => module <> "/" <> name,
        "module" => module,
        "name" => name,
        "test_type" => "test",
        "file" => "test/fake/" <> Macro.underscore(module) <> ".exs",
        "line" => line,
        "status" => status
      }
    end

    rows =
      for(i <- 1..120, do: mk.("Fake.FailTest", "test fails #{i}", 100 + i, "failed")) ++
        for(i <- 1..16, do: mk.("Fake.InvalidTest", "test invalid #{i}", 20 + i, "invalid")) ++
        for(i <- 1..30, do: mk.("Fake.PassTest", "test passes #{i}", 10 + i, "passed"))

    run = %{
      "complete" => true,
      "key_collisions" => [],
      "module_cross_check" => %{"disagreements" => []}
    }

    out =
      "Running ExUnit with seed: 0, max_cases: 64\n\nFinished in 1.0 seconds\n" <>
        "0 doctests, 166 tests, 120 failures, 16 invalid\n"

    {out, ExUnitRows.artefact(rows, run)}
  end

  defp census_tmp(stem) do
    dir =
      Path.join(System.tmp_dir!(), "etcc-census-#{stem}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  # The sweep's last run in `tmp` is the mutated one; its rows and transcript are kept.
  defp captured(tmp) do
    rows = Path.join(tmp, "rows.json")
    {File.read!(rows <> ".log"), Sweep.read_artefact(rows)}
  end

  # --- emit: --emit-spec never re-counts, and no caller accepts a zero-site entry ---

  # MES-173. `--emit-spec` used to re-derive EVERY entry from the prose and then check the
  # result against the very tree it was counted from, so guard 26 was tautological over
  # its output: on a drifted tree it wrote Meta widened to 2 sites and Plug's error entry
  # as a 0-site no-op, and `--verify` then passed. And a 0 on a LIVE row was seen by no
  # guard at all (24 is DEAD-only; 26 passes a 0 whose FROM is indeed absent).
  #
  #   * P1-P4 POSITIVE — the committed table emits unchanged; a new row and an appended
  #     line still derive; a planted `replace: "first"` survives.
  #   * E1-E3 — an existing entry is never re-counted, in either direction, and an edited
  #     existing slot is not quietly treated as new.
  #   * Z1-Z5 — guard 27's positivity, through every caller: `check_table!/2` with the
  #     tree check on and off (gate 8 and the register build), `emit_spec/1` and
  #     `apply!/1`.
  #   * W1-W2 — the TASK, in process, so the wiring is shown and not just the helper. W2
  #     plants a duplicate anchor in the real `lib/mcp/protocol/meta.ex` (PM ruling 34227,
  #     Q3): it refuses to start unless `lib/` is clean, restores the bytes in `after`,
  #     and halts non-zero if the restore does not compare equal.
  #
  # At a tip without `Sweep.emit_spec/1` (main before MES-173) the limbs that call it
  # report UNDEFINED; that is a red, but not a discriminating one (ruling 34227, Q4). The
  # discriminating evidence for them is `emit-mutation`.
  @nowhere "ZZ_MES173_OCCURS_NOWHERE"
  @w2_file "lib/mcp/protocol/meta.ex"

  defp emit do
    header("EMIT — --emit-spec never re-counts; a zero-site entry is refused by every caller")
    results = Enum.map(emit_limbs(), fn {_key, limb} -> limb.() end)
    IO.puts("")
    Enum.each(results, &report_limb/1)
    IO.puts("\n  #{Enum.count(results, &elem(&1, 1))}/#{length(results)} limbs hold.")
    if Enum.any?(results, fn {_, ok} -> not ok end), do: System.halt(1)
  end

  defp emit_limbs do
    [
      p1: &p1_committed/0,
      p2: &p2_new_row/0,
      p3: &p3_appended/0,
      p4: &p4_replace_first/0,
      e1: fn -> e_recount("E1 an existing entry widened 1 -> 2 is refused, not re-counted", 2) end,
      e2: fn ->
        e_recount("E2 an existing entry narrowed 1 -> 0 is refused, not re-counted", 0)
      end,
      e3: &e3_changed_slot/0,
      z1: fn -> z_table("Z1", "live") end,
      z2: fn -> z_table("Z2", "dead") end,
      z3: &z3_new_slot_zero/0,
      z4: &z4_apply/0,
      z5: &z5_non_positive/0,
      w1: &w1_task_committed/0,
      w2: &w2_task_drift/0
    ]
  end

  defp p1_committed do
    doc = read(@paths.boundaries)

    guarded("P1 the committed table emits unchanged", fn ->
      out = Sweep.emit_spec(doc)
      n = Enum.sum(Enum.map(doc["boundaries"], &length(&1["mutation_spec"] || [])))
      IO.puts("  P1  reach: #{length(doc["boundaries"])} rows, #{n} entries kept as recorded")
      out == doc and n > 0
    end)
  end

  defp p2_new_row do
    in_fixture("ANCHOR_A\n", fn f ->
      guarded("P2 a new row (no mutation_spec) derives its count, replace all", fn ->
        row = fixture_row("live", [prose(f, "ANCHOR_A", "X")], nil)
        [b] = Sweep.emit_spec(%{"boundaries" => [row]})["boundaries"]
        b["mutation_spec"] == [entry(f, "ANCHOR_A", "X", 1)]
      end)
    end)
  end

  defp p3_appended do
    in_fixture("ANCHOR_A ANCHOR_B ANCHOR_B\n", fn f ->
      guarded("P3 an appended prose line derives; the existing prefix is untouched", fn ->
        kept = entry(f, "ANCHOR_A", "X", 1)
        row = fixture_row("live", [prose(f, "ANCHOR_A", "X"), prose(f, "ANCHOR_B", "Y")], [kept])
        [b] = Sweep.emit_spec(%{"boundaries" => [row]})["boundaries"]
        b["mutation_spec"] == [kept, entry(f, "ANCHOR_B", "Y", 2)]
      end)
    end)
  end

  defp p4_replace_first do
    in_fixture("ANCHOR_A ANCHOR_A\n", fn f ->
      guarded("P4 a planted replace \"first\" survives emission", fn ->
        kept = entry(f, "ANCHOR_A", "X", 2, "first")
        row = fixture_row("dead", [prose(f, "ANCHOR_A", "X")], [kept])
        [b] = Sweep.emit_spec(%{"boundaries" => [row]})["boundaries"]
        b["mutation_spec"] == [kept]
      end)
    end)
  end

  defp e_recount(name, now) do
    in_fixture(String.duplicate("ANCHOR_A\n", now), fn f ->
      guarded(name, fn ->
        row = fixture_row("live", [prose(f, "ANCHOR_A", "X")], [entry(f, "ANCHOR_A", "X", 1)])
        msg = refusal_of(fn -> Sweep.emit_spec(%{"boundaries" => [row]}) end)
        show(name, msg)

        msg != nil and String.starts_with?(msg, "GUARD 26: --emit-spec refuses to re-count") and
          msg =~ "#{row["id"]} entry 1, #{f}: recorded 1, tree has #{now}" and
          msg =~ "mix conformance.sweep --check --only #{inspect(row["id"])}"
      end)
    end)
  end

  defp e3_changed_slot do
    in_fixture("ANCHOR_A ANCHOR_B\n", fn f ->
      name = "E3 prose edited at an existing slot is refused by guard 27, not treated as new"

      guarded(name, fn ->
        row = fixture_row("live", [prose(f, "ANCHOR_B", "X")], [entry(f, "ANCHOR_A", "X", 1)])
        msg = refusal_of(fn -> Sweep.emit_spec(%{"boundaries" => [row]}) end)
        show(name, msg)
        msg != nil and msg =~ "GUARD 27: 1 mutation_spec entry/ies do not render back"
      end)
    end)
  end

  # Z1/Z2 — the committed table with one row's mutation made zero-site. Guard 26 ALONE
  # must accept it (the FROM really is absent), so the refusal is shown to be positivity's
  # and not a by-product of resolution.
  defp z_table(tag, verdict) do
    rows = read(@paths.boundaries)["boundaries"]
    subject = Enum.find(rows, &(&1["verdict"] == verdict))
    planted = put(rows, subject, zero_site())
    name = "#{tag} a #{String.upcase(verdict)} row recording occurrences 0 is refused by guard 27"

    guarded(name, fn ->
      g26_alone = refusal_of(fn -> Sweep.check_spec_resolves!(planted) end)
      gate8 = refusal_of(fn -> Sweep.check_table!(planted) end)
      register = refusal_of(fn -> Sweep.check_table!(planted, check_tree: false) end)
      emit = refusal_of(fn -> Sweep.emit_spec(%{"boundaries" => planted}) end)

      IO.puts("  #{tag}  on #{subject["id"]}")
      IO.puts("      guard 26 alone:           #{verdict_of(g26_alone)}")
      IO.puts("      check_table! (gate 8):    #{verdict_of(gate8)}")
      IO.puts("      check_table! (register):  #{verdict_of(register)}")
      IO.puts("      emit_spec/1:              #{verdict_of(emit)}")

      g26_alone == nil and Enum.all?([gate8, register, emit], &siteless?/1)
    end)
  end

  defp z3_new_slot_zero do
    in_fixture("ANCHOR_A\n", fn f ->
      name = "Z3 a NEW slot that derives occurrences 0 is refused at emission"

      guarded(name, fn ->
        row = fixture_row("live", [prose(f, @nowhere, "X")], nil)
        msg = refusal_of(fn -> Sweep.emit_spec(%{"boundaries" => [row]}) end)
        show(name, msg)
        siteless?(msg)
      end)
    end)
  end

  defp z4_apply do
    in_fixture("ANCHOR_A\n", fn f ->
      name = "Z4 apply! refuses a zero-site entry before writing anything"

      guarded(name, fn ->
        spec = [entry(f, "ANCHOR_A", "X", 1), entry(f, @nowhere, "Y", 0)]
        msg = refusal_of(fn -> Sweep.apply!(spec) end)
        show(name, msg)
        intact = File.read!(f) == "ANCHOR_A\n"
        IO.puts("      fixture bytes intact: #{intact}")
        msg != nil and String.starts_with?(msg, "GUARD 27: mutation_spec entry 2,") and intact
      end)
    end)
  end

  defp z5_non_positive do
    in_fixture("ANCHOR_A\n", fn f ->
      name = "Z5 occurrences -1, nil and \"1\" are each refused by guard 27 and by apply!"

      guarded(name, fn ->
        Enum.all?([-1, nil, "1"], fn n ->
          e = entry(f, "ANCHOR_A", "X", n)
          row = fixture_row("live", [prose(f, "ANCHOR_A", "X")], [e])
          table = refusal_of(fn -> Sweep.check_spec_prose!([row]) end)
          applied = refusal_of(fn -> Sweep.apply!([e]) end)

          IO.puts(
            "  Z5  occurrences #{inspect(n)}: guard 27 #{verdict_of(table)}; apply! #{verdict_of(applied)}"
          )

          siteless?(table) and applied != nil and String.starts_with?(applied, "GUARD 27:")
        end)
      end)
    end)
  end

  defp w1_task_committed do
    out = tmp_path("w1.json")

    guarded("W1 the task emits the committed table byte-identically", fn ->
      Mix.Tasks.Conformance.Sweep.run(["--emit-spec", out])
      File.read!(out) == File.read!(@paths.boundaries)
    end)
  after
    File.rm(tmp_path("w1.json"))
  end

  # W2 — the real tree, drifted. Guarded per ruling 34227 Q3.
  defp w2_task_drift do
    name = "W2 the task refuses a drifted real anchor and leaves its output untouched"

    unless lib_clean?() do
      IO.puts("  W2  REFUSING TO START: `git status --porcelain -- lib/` is not empty")
      System.halt(1)
    end

    target =
      read(@paths.boundaries)["boundaries"]
      |> Enum.flat_map(&(&1["mutation_spec"] || []))
      |> Enum.find(
        &(&1["file"] == @w2_file and &1["occurrences"] == 1 and not (&1["from"] =~ "\n"))
      )

    original = File.read!(@w2_file)
    out = tmp_path("w2.json")
    File.write!(out, "SENTINEL\n")

    try do
      File.write!(@w2_file, original <> "\n# MES-173 control plant: " <> target["from"] <> "\n")

      guarded(name, fn ->
        msg = refusal_of(fn -> Mix.Tasks.Conformance.Sweep.run(["--emit-spec", out]) end)
        show(name, msg)
        untouched = File.read!(out) == "SENTINEL\n"
        IO.puts("      output untouched: #{untouched}")

        msg != nil and String.starts_with?(msg, "GUARD 26: --emit-spec refuses to re-count") and
          msg =~ "#{@w2_file}: recorded 1, tree has 2" and untouched
      end)
    after
      File.write!(@w2_file, original)
      File.rm(out)

      unless File.read!(@w2_file) == original and lib_clean?() do
        IO.puts("  W2  RESTORE FAILED: #{@w2_file} does not match its saved bytes")
        System.halt(1)
      end
    end
  end

  # --- emit-mutation: each new refusal shown able to FAIL, in memory ---

  # Recompiles the instrument IN MEMORY with one refusal undone, requires the limbs that
  # hold it to go RED, then recompiles the committed source and requires them green
  # again. Nothing is written to disk. Each anchor is required at exactly one occurrence
  # before it is mutated, so a moved anchor fails loud rather than mutating nothing.
  #
  #   * M1 — `emit_spec/1` re-derives every entry again (the pre-MES-173 behaviour).
  #   * M2 — guard 27's positivity predicate accepts everything.
  #   * M3 — the TASK's `--emit-spec` reverted to its pre-MES-173 body, so W2 shows the
  #     wiring and not just the helper.
  @task_src "conformance/lib/mix/tasks/conformance.sweep.ex"

  defp emit_mutants do
    [
      {"M1 emit_spec/1 re-counts existing entries", @sweep_src,
       "    refuse_recount!(rows)\n\n    emitted =\n      Enum.map(rows, fn b ->\n        spec = spec_of(b)\n" <>
         "        new = derive_spec(%{\"mutation\" => Enum.drop(b[\"mutation\"] || [], length(spec))})\n" <>
         "        Map.put(b, \"mutation_spec\", spec ++ new)\n",
       "    emitted =\n      Enum.map(rows, fn b ->\n" <>
         "        ov = spec_of(b) |> Enum.with_index() |> Map.new(fn {e, i} -> {i, e[\"replace\"] || \"all\"} end)\n" <>
         "        Map.put(b, \"mutation_spec\", derive_spec(b, ov))\n", [:e1, :e2]},
      {"M2 guard 27's positivity predicate accepts everything", @sweep_src,
       "  def positive_occurrences?(entry),\n    do: is_integer(entry[\"occurrences\"]) and entry[\"occurrences\"] > 0\n",
       "  def positive_occurrences?(_entry), do: true\n", [:z1, :z2, :z3, :z4, :z5]},
      {"M3 the task's --emit-spec reverted to re-deriving", @task_src,
       "    emitted = Sweep.emit_spec(doc)\n",
       "    rows =\n      Enum.map(doc[\"boundaries\"], fn b ->\n" <>
         "        ov = (b[\"mutation_spec\"] || []) |> Enum.with_index() |> Map.new(fn {e, i} -> {i, e[\"replace\"] || \"all\"} end)\n" <>
         "        Map.put(b, \"mutation_spec\", Sweep.derive_spec(b, ov))\n      end)\n\n" <>
         "    Sweep.check_spec_prose!(rows)\n    Sweep.check_spec_resolves!(rows)\n" <>
         "    emitted = %{doc | \"boundaries\" => rows}\n", [:w2]}
    ]
  end

  defp emit_mutation do
    header("EMIT-MUTATION — each MES-173 refusal goes RED when undone, green when restored")
    limbs = emit_limbs()
    Code.put_compiler_option(:ignore_module_conflict, true)

    results =
      Enum.flat_map(emit_mutants(), fn {name, path, anchor, mutant, keys} ->
        src = File.read!(path)
        n = src |> String.split(anchor) |> length() |> Kernel.-(1)
        IO.puts("\n  #{name}\n    anchor occurrences in #{path}: #{n} (must be 1)")
        if n != 1, do: System.halt(1)

        try do
          Code.compile_string(String.replace(src, anchor, mutant), path)
          IO.puts("    MUTANT:")
          red = Enum.map(keys, fn k -> limbs[k].() end)

          Code.compile_string(src, path)
          IO.puts("    RESTORED:")
          green = Enum.map(keys, fn k -> limbs[k].() end)

          Enum.map(red, fn {l, ok} -> {"#{name}: #{l} goes RED", not ok} end) ++
            Enum.map(green, fn {l, ok} -> {"restored: #{l} green again", ok} end)
        after
          Code.compile_string(src, path)
        end
      end)

    IO.puts("")
    Enum.each(results, &report_limb/1)
    IO.puts("\n  #{Enum.count(results, &elem(&1, 1))}/#{length(results)} as expected.")
    if Enum.any?(results, fn {_, ok} -> not ok end), do: System.halt(1)
  end

  # --- emit helpers ---

  # A row's mutation made zero-site: a real file, a FROM that occurs nowhere in it, and a
  # recorded count of 0 — so guard 26 is satisfied and only positivity can refuse it.
  defp zero_site do
    %{
      "mutation" => [prose(@w2_file, @nowhere, "X")],
      "mutation_spec" => [entry(@w2_file, @nowhere, "X", 0)]
    }
  end

  defp fixture_row(verdict, mutation, spec) do
    base = Enum.find(read(@paths.boundaries)["boundaries"], &(&1["verdict"] == verdict))
    Map.merge(base, %{"mutation" => mutation, "mutation_spec" => spec})
  end

  defp prose(f, from, to), do: Sweep.render_prose(%{"file" => f, "from" => from, "to" => to})

  defp entry(f, from, to, n, replace \\ "all"),
    do: %{"file" => f, "from" => from, "to" => to, "occurrences" => n, "replace" => replace}

  defp in_fixture(bytes, fun) do
    f = tmp_path("fixture.ex")
    File.write!(f, bytes)

    try do
      fun.(f)
    after
      File.rm(f)
    end
  end

  defp tmp_path(stem), do: Path.join(System.tmp_dir!(), "etcc-emit-#{System.pid()}-#{stem}")

  # A limb as `{name, ok}`. A call to a function this tip does not define is reported as
  # such and counted red, rather than crashing the mode (main before MES-173).
  defp guarded(name, fun) do
    {name, fun.()}
  rescue
    e in UndefinedFunctionError ->
      IO.puts("  UNDEFINED AT THIS TIP  #{name}: #{Exception.message(e)}")
      {name <> " [UNDEFINED at this tip]", false}
  end

  defp refusal_of(fun) do
    fun.()
    nil
  rescue
    e in RuntimeError -> Exception.message(e)
  end

  defp siteless?(msg),
    do:
      msg != nil and
        msg =~
          ~r/\AGUARD 27: \d+ mutation_spec entry\/ies do not record a positive integer occurrences:/

  defp verdict_of(nil), do: "ACCEPTED"
  defp verdict_of(msg), do: "REFUSED -> " <> first_line(msg)

  defp show(name, msg) do
    IO.puts("  #{name |> String.split(" ") |> hd()}  #{verdict_of(msg)}")
  end

  defp lib_clean? do
    {out, 0} = System.cmd("git", ["status", "--porcelain", "--", "lib/"])
    out == ""
  end

  # --- verify: the TASK, in its own OS process, against a throwaway copy (MES-179) ---

  # `guards` calls check_table!/1 in process, so it cannot see what the TASK prints or how
  # it exits. These modes run `mix conformance.sweep --verify` as a child process, from
  # `env -i`, in a copy of this worktree whose .git link is removed. Every plant goes into
  # the copy; the real table's sha256 and `git status --porcelain` are taken before and
  # after, and a move in either halts 1. `System.cmd/3` returns the child's own exit
  # status: `env` execs mix, and there is no shell and no pipeline.
  #
  # Each case is adjudicated on these limbs:
  #   (i)   exit 0 iff "GUARDS 23-27 — no violation." is printed;
  #   (ii)  exit 0 iff the last non-blank line begins "ETCC-VERIFY PASS";
  #   (iii) the expected verdict. A pass: exit 0, and the last line equal to the PASS line
  #         whose counts THIS script counts from the copy's table, not the instrument. A
  #         refusal: exit non-zero, the original exception's own lines, a stack trace, and
  #         a last line `** (Mix) ETCC-VERIFY REFUSE: <kind>` naming the case's own guard;
  #   (iv)  the plant restored byte-exactly in the copy.
  @verify_pass "GUARDS 23-27 — no violation."
  @refuse "** (Mix) ETCC-VERIFY REFUSE: "
  @plant_note "\n# MES-179 control plant: "

  defp verify_mode do
    header("VERIFY — the task, in its own OS process, against a throwaway copy (MES-179)")

    results =
      with_copy(fn copy ->
        Enum.map(verify_cases(), &report_case(&1, run_case(&1, copy)))
      end)

    ran =
      Enum.filter(results, fn {_, limbs} -> String.starts_with?(elem(hd(limbs), 0), "(i)") end)

    iff = Enum.count(ran, fn {_, limbs} -> Enum.all?(Enum.take(limbs, 2), &elem(&1, 1)) end)
    IO.puts("\n  exit 0 iff a pass line printed: #{iff}/#{length(ran)} cases run")
    ok = Enum.count(results, fn {_, limbs} -> Enum.all?(limbs, &elem(&1, 1)) end)
    IO.puts("  #{ok}/#{length(results)} cases as expected.")
    if ok != length(results), do: System.halt(1)
  end

  defp verify_mutation do
    header("VERIFY-MUTATION — each control goes RED under a mutant, green when restored")
    cases = Map.new(verify_cases(), &{&1.id, &1})

    results =
      with_copy(fn copy ->
        verify_mutants()
        |> Enum.map(fn
          {n, p, a, m, ids} -> {n, p, a, m, ids, []}
          six -> six
        end)
        |> Enum.flat_map(fn {name, path, anchor, mutant, ids, stay} ->
          p = Path.join(copy, path)
          src = File.read!(p)
          n = src |> String.split(anchor) |> length() |> Kernel.-(1)
          IO.puts("\n  #{name}\n    anchor occurrences in #{path}: #{n} (must be 1)")

          if n == 1 do
            try do
              copy_write!(p, String.replace(src, anchor, mutant))
              IO.puts("    MUTANT:")
              red = Enum.map(ids, &report_case(cases[&1], run_case(cases[&1], copy), "      "))
              kept = Enum.map(stay, &report_case(cases[&1], run_case(cases[&1], copy), "      "))
              copy_write!(p, src)
              IO.puts("    RESTORED (bytes equal: #{File.read!(p) == src}):")

              green =
                Enum.map(
                  ids ++ stay,
                  &report_case(cases[&1], run_case(cases[&1], copy), "      ")
                )

              Enum.map(red, fn {id, l} -> {"#{name}: #{id} goes RED", not all_hold?(l)} end) ++
                Enum.map(kept, fn {id, l} ->
                  {"#{name}: #{id} stays as expected", all_hold?(l)}
                end) ++
                Enum.map(green, fn {id, l} -> {"restored: #{id} as expected", all_hold?(l)} end)
            after
              copy_write!(p, src)
            end
          else
            [{"#{name}: anchor occurs #{n} times, NOT RUN", false}]
          end
        end)
      end)

    IO.puts("")
    Enum.each(results, &report_limb/1)
    IO.puts("\n  #{Enum.count(results, &elem(&1, 1))}/#{length(results)} as expected.")
    if Enum.any?(results, fn {_, ok} -> not ok end), do: System.halt(1)
  end

  # Subjects by PREDICATE over the committed table, never by id.
  defp verify_cases do
    rows = read(@paths.boundaries)["boundaries"]
    t = @paths.boundaries
    dead = Enum.find(rows, &(&1["verdict"] == "dead"))
    zero_live = Enum.find(rows, &(zero_live?(&1) and &1["verdict"] == "live"))
    first_spec = Enum.find(rows, &((&1["mutation_spec"] || []) != []))
    live_spec = Enum.find(rows, &(&1["verdict"] == "live" and (&1["mutation_spec"] || []) != []))
    total = spec_count(rows)

    anchor =
      rows
      |> Enum.flat_map(&(&1["mutation_spec"] || []))
      |> Enum.find(fn e ->
        String.starts_with?(e["file"], "lib/") and e["occurrences"] == 1 and
          not (e["from"] =~ "\n") and e["from"] =~ "("
      end)

    # RA: a space after the anchor's first "(" — still compiles, no longer matches.
    [head, tail] = String.split(anchor["from"], "(", parts: 2)
    moved = head <> "( " <> tail
    f = anchor["file"]
    zero = entry(hd(live_spec["mutation_spec"])["file"], @nowhere, "X", 0)
    g = fn n, s -> "** (RuntimeError) GUARD #{n}: " <> s end
    rc_prose = List.update_at(first_spec["mutation"], 0, &(&1 <> " x"))

    [
      vcase("G0", "nothing planted", [], fn _ -> :ok end, :pass),
      vcase(
        "NA",
        "a comment appended to #{f}, no anchor touched",
        [f],
        &append(&1, f, "a comment, no anchor touched"),
        :pass
      ),
      vcase(
        "RA",
        "#{anchor["from"]} in #{f} edited to #{moved}",
        [f],
        &replace(&1, f, anchor["from"], moved),
        {:refuse, "GUARD 26", [g.(26, "1 mutation_spec"), "#{f} has 0, spec records 1"]}
      ),
      vcase(
        "RB",
        "the same anchor appended to #{f} again, as a comment",
        [f],
        &append(&1, f, anchor["from"]),
        {:refuse, "GUARD 26", [g.(26, "1 mutation_spec"), "#{f} has 2, spec records 1"]}
      ),
      vcase(
        "RC",
        "\" x\" appended to #{first_spec["id"]}'s first mutation prose line",
        [t],
        &edit_table(&1, fn rs ->
          put(rs, first_spec, %{
            "mutation" => rc_prose
          })
        end),
        {:refuse, "GUARD 27", [g.(27, "1 mutation_spec entry/ies do not render back")]}
      ),
      vcase(
        "RZ2",
        "#{live_spec["id"]} (LIVE): entry 1 made zero-site, prose rendered to match",
        [t],
        &edit_table(&1, fn rs ->
          put(rs, live_spec, %{
            "mutation_spec" => [zero | tl(live_spec["mutation_spec"])],
            "mutation" => [Sweep.render_prose(zero) | tl(live_spec["mutation"])]
          })
        end),
        {:refuse, "GUARD 27",
         [g.(27, "1 mutation_spec entry/ies do not record a positive integer occurrences")]}
      ),
      vcase(
        "RD",
        "l2 removed from #{zero_live["id"]} (live count 0, LIVE)",
        [t],
        &edit_table(&1, fn rs -> put(rs, zero_live, %{"l2" => nil}) end),
        {:refuse, "GUARD 23",
         [
           g.(
             23,
             "1 direction(s) have a live count of ZERO and no L2 record (#{zero_live["id"]})"
           )
         ]}
      ),
      vcase(
        "R24",
        "#{dead["id"]} (DEAD) made impotent",
        [t],
        &edit_table(&1, fn rs ->
          put(rs, dead, %{"reddened_outside_own" => dead["reddened_total"]})
        end),
        {:refuse, "GUARD 24",
         [
           g.(
             24,
             "1 DEAD direction(s) whose mutation reddened NONE of their own units (#{dead["id"]})"
           )
         ]}
      ),
      vcase(
        "R25",
        "#{dead["id"]} (DEAD) byte_probe removed",
        [t],
        &edit_table(&1, fn rs ->
          put(rs, dead, %{"l2" => Map.put(dead["l2"], "byte_probe", nil)})
        end),
        {:refuse, "GUARD 25", [g.(25, "1 DEAD direction(s) are missing an L2 conjunct")]}
      ),
      vcase(
        "RE",
        "the table moved away",
        [t, t <> ".moved"],
        &File.rename!(Path.join(&1, t), Path.join(&1, t <> ".moved")),
        {:refuse, "ERROR File.Error", ["** (File.Error) could not read file \"#{t}\""]}
      ),
      vcase(
        "RF",
        "boundaries emptied (CR F2 on MES-175)",
        [t],
        &edit_table(&1, fn _ -> [] end),
        {:refuse, "POPULATION",
         [
           "** (RuntimeError) POPULATION: --verify refuses a vacuous scan: guard_23_scanned 0, " <>
             "guard_24_scanned 0, guard_25_scanned 0, guard_26_scanned 0, guard_27_scanned 0."
         ]}
      ),
      vcase(
        "RS2",
        "every DEAD row deleted",
        [t],
        &edit_table(&1, fn rs -> Enum.reject(rs, fn b -> b["verdict"] == "dead" end) end),
        {:refuse, "POPULATION",
         ["POPULATION: --verify refuses a vacuous scan: guard_24_scanned 0, guard_25_scanned 0."]}
      ),
      vcase(
        "RS4",
        "every mutation_spec and its mutation prose removed",
        [t],
        &edit_table(&1, fn rs ->
          Enum.map(rs, fn b -> Map.drop(b, ["mutation_spec", "mutation"]) end)
        end),
        {:refuse, "POPULATION",
         ["POPULATION: --verify refuses a vacuous scan: guard_26_scanned 0, guard_27_scanned 0."]}
      ),
      vcase(
        "EQ1",
        "instrument plant: the task calls check_table! with check_tree: false (shape limb)",
        [@task_src],
        &replace(
          &1,
          @task_src,
          eq1_anchor(),
          "doc[\"boundaries\"] |> Sweep.check_table!(check_tree: false)"
        ),
        {:refuse, "POPULATION",
         ["POPULATION: --verify refuses a malformed scan: guard_26_scanned :skipped."]}
      ),
      vcase(
        "EQ2",
        "instrument plant: guard 26's scan short-counts by one",
        [@sweep_src],
        &replace(
          &1,
          @sweep_src,
          eq2_anchor(),
          String.replace(eq2_anchor(), "length(entries)", "length(entries) - 1")
        ),
        {:refuse, "POPULATION",
         [
           "POPULATION: guard_26_scanned #{total - 1} is not the table's mutation_spec total #{total}"
         ]}
      ),
      vcase(
        "EQ3",
        "instrument plant: guard 27's scan short-counts by one",
        [@sweep_src],
        &replace(
          &1,
          @sweep_src,
          eq3_anchor(),
          String.replace(eq3_anchor(), "length(entries)", "length(entries) - 1")
        ),
        {:refuse, "POPULATION",
         [
           "POPULATION: guard_27_scanned #{total - 1} is not the table's mutation_spec total #{total}"
         ]}
      ),
      scan_plant("S1", "guard_23_scanned -1", "Map.put(:guard_23_scanned, -1)"),
      scan_plant("S2", "guard_24_scanned absent", "Map.delete(:guard_24_scanned)"),
      scan_plant("S3", "guard_25_scanned :skipped", "Map.put(:guard_25_scanned, :skipped)"),
      verify_plant(
        "THROW",
        "throw(:mes179_control)",
        {:refuse, "THROW", ["** (throw) :mes179_control"]}
      ),
      verify_plant("EXIT", "exit(:normal)", {:refuse, "EXIT", ["** (exit) normal"]}),
      verify_plant(
        "G999",
        "raise(\"GUARD 999: MES-179 control plant\")",
        {:refuse, "ERROR RuntimeError", ["** (RuntimeError) GUARD 999: MES-179 control plant"]}
      ),
      vcase(
        "RS1",
        "RESIDUAL (MES-179 Q1): the first row deleted, no count at zero — PASSES",
        [t],
        &edit_table(&1, fn rs -> tl(rs) end),
        :pass
      )
    ]
  end

  defp eq1_anchor, do: "doc[\"boundaries\"] |> Sweep.check_table!()"

  defp eq3_anchor, do: "    length(entries)\n  end\n\n  @scanned_keys"

  # The scan's RETURN doctored before check_population! sees it: the shape limb's cases.
  defp scan_plant(id, what, change) do
    vcase(
      id,
      "instrument plant: the scan returns #{what} (shape limb)",
      [@task_src],
      &replace(
        &1,
        @task_src,
        " |> Sweep.check_population!(total)",
        " |> #{change} |> Sweep.check_population!(total)"
      ),
      {:refuse, "POPULATION", ["POPULATION: --verify refuses a malformed scan: #{what}."]}
    )
  end

  # A throw, an exit or a stray RuntimeError raised inside verify/0 (F1, F4).
  defp verify_plant(id, expr, expect) do
    vcase(
      id,
      "instrument plant: verify/0 runs #{expr}",
      [@task_src],
      &replace(
        &1,
        @task_src,
        "    total = spec_total(doc)\n",
        "    total = spec_total(doc)\n    if total > 0, do: #{expr}\n"
      ),
      expect
    )
  end

  defp eq2_anchor,
    do:
      "Enum.join(bad, \"\\n  \")\n    end\n\n    length(entries)\n  end\n\n  @doc \"\"\"\n  Guard 27"

  @refusing ~w(RA RB RC RZ2 RD R24 R25 RE RF RS2 RS4 EQ1 EQ2 EQ3 S1 S2 S3 THROW EXIT G999)

  # Each mutant undoes one thing a control holds, in the COPY's instrument, and names the
  # controls that must go red. The task runs in another OS process, so an in-memory
  # recompile cannot reach it.
  defp verify_mutants do
    s = @sweep_src
    k = @task_src
    off = fn a -> String.replace(a, ~r/if \w+ != \[\] do/, "if false do", global: false) end

    [
      {"V0 the population check refuses everything", s, "    if vacuous != [] do\n",
       "    if true do\n", ~w(G0 NA)},
      {"V23 guard 23 never raises", s, "    if naked != [] do\n", off.("    if naked != [] do\n"),
       ~w(RD)},
      {"V24 guard 24 never raises", s, "    if impotent != [] do\n",
       off.("    if impotent != [] do\n"), ~w(R24)},
      {"V25 guard 25 never raises", s, "    if missing != [] do\n",
       off.("    if missing != [] do\n"), ~w(R25)},
      {"V26 guard 26 never raises", s, v26_anchor(), off.(v26_anchor()), ~w(RA RB)},
      {"V27r guard 27's render comparison never raises", s, v27_anchor(), off.(v27_anchor()),
       ~w(RC)},
      {"V27p guard 27's positivity predicate accepts everything", s,
       "  def positive_occurrences?(entry),\n    do: is_integer(entry[\"occurrences\"]) and entry[\"occurrences\"] > 0\n",
       "  def positive_occurrences?(_entry), do: true\n", ~w(RZ2)},
      {"VZ the zero limb removed", s,
       "    vacuous = for {k, v} <- Enum.sort(scanned), v == 0, do: \"\#{k} 0\"\n",
       "    vacuous = []\n", ~w(RF RS2 RS4)},
      {"VE26 the equality limb's guard-26 half bypassed", s,
       "    equal_26? = scanned.guard_26_scanned == total\n", "    equal_26? = true\n", ~w(EQ2),
       ~w(EQ3)},
      {"VE27 the equality limb's guard-27 half bypassed", s,
       "    equal_27? = scanned.guard_27_scanned == total\n", "    equal_27? = true\n", ~w(EQ3),
       ~w(EQ2)},
      {"VS the shape limb removed", s,
       "      for k <- @scanned_keys, not well_formed?(Map.fetch(scanned, k)) do\n",
       "      for k <- [], not well_formed?(Map.fetch(scanned, k)) do\n", ~w(S1 S2 S3 EQ1)},
      {"VP the task never calls check_population!", k, " |> Sweep.check_population!(total)", "",
       ~w(RF RS2 RS4 EQ1 EQ2 EQ3)},
      {"VX the task prints REFUSE but exits 0", k,
       "    Mix.raise(\"ETCC-VERIFY REFUSE: \" <> kind)\n",
       "    Mix.shell().error(\"ETCC-VERIFY REFUSE: \" <> kind)\n", @refusing},
      {"VL the pass line printed before the guards run", k,
       "  defp verify do\n    doc = boundaries()\n",
       "  defp verify do\n    Mix.shell().info(\"#{@verify_pass}\")\n    doc = boundaries()\n",
       @refusing},
      {"VN the REFUSE line always names GUARD 23", k,
       "      {n, \":\" <> _} when n in 23..27 -> \"GUARD \#{n}\"\n",
       "      {n, \":\" <> _} when n in 23..27 -> \"GUARD 23\"\n", ~w(RA RB RC RZ2 R24 R25)},
      {"VR GUARD n labelled for any n, not 23-27 only", k,
       "      {n, \":\" <> _} when n in 23..27 ->", "      {n, \":\" <> _} ->", ~w(G999)},
      {"VF the rescue narrowed to RuntimeError", k, "  rescue\n    e -> refuse!(",
       "  rescue\n    e in RuntimeError -> refuse!(", ~w(RE)},
      {"VCT the :throw catch clause removed", k,
       "    :throw, reason -> refuse!(Exception.format(:throw, reason, __STACKTRACE__), \"THROW\")\n",
       "", ~w(THROW)},
      {"VCE the :exit catch clause removed", k,
       "    :exit, reason -> refuse!(Exception.format(:exit, reason, __STACKTRACE__), \"EXIT\")\n",
       "", ~w(EXIT)}
    ]
  end

  defp v26_anchor,
    do:
      "    if bad != [] do\n      raise \"GUARD 26: \#{length(bad)} mutation_spec entry/ies no longer resolve"

  defp v27_anchor,
    do:
      "    if bad != [] do\n      raise \"GUARD 27: \#{length(bad)} mutation_spec entry/ies do not render back"

  defp vcase(id, what, files, plant, expect),
    do: %{id: id, what: what, files: files, plant: plant, expect: expect}

  # Plant, run, restore, then adjudicate. A pass's expected line is computed from the
  # PLANTED table before the run, by counting here.
  # A plant that cannot be applied (an instrument anchor absent at this tip, as at main
  # before MES-179) is a RED case, not a crash, and the task is not run.
  defp run_case(c, copy) do
    saved = Map.new(c.files, &{&1, File.read(Path.join(copy, &1))})

    {run, limbs} =
      try do
        c.plant.(copy)
        expected = if c.expect == :pass, do: pass_line(read(Path.join(copy, @paths.boundaries)))
        run = run_task(copy)
        {run, adjudicate(c.expect, run, expected)}
      rescue
        e in RuntimeError ->
          {{"", "NOT RUN"}, [{"plant applied: #{Exception.message(e)}", false}]}
      after
        Enum.each(saved, fn
          {f, {:ok, bytes}} -> copy_write!(Path.join(copy, f), bytes)
          {f, {:error, _}} -> File.rm(Path.join(copy, f))
        end)
      end

    restored = Enum.all?(saved, fn {f, was} -> File.read(Path.join(copy, f)) == was end)
    {run, limbs ++ [{"(iv) plant restored byte-exactly", restored}]}
  end

  defp run_task(copy) do
    env = [
      "-i",
      "PATH=" <> System.fetch_env!("PATH"),
      "HOME=" <> System.fetch_env!("HOME"),
      "LANG=C.UTF-8"
    ]

    run =
      System.cmd("env", env ++ ["mix", "conformance.sweep", "--verify"],
        cd: copy,
        stderr_to_stdout: true
      )

    Process.put(:etcc_last_run, System.os_time(:second))
    run
  end

  defp adjudicate(expect, {out, status}, expected) do
    last = last_line(out)

    [
      {"(i) exit 0 iff the pass line", status == 0 == String.contains?(out, @verify_pass)},
      {"(ii) exit 0 iff the last line is ETCC-VERIFY PASS",
       status == 0 == String.starts_with?(last, "ETCC-VERIFY PASS")}
    ] ++ expected_limbs(expect, out, status, last, expected)
  end

  defp expected_limbs(:pass, _out, status, last, expected),
    do: [{"(iii) exit 0", status == 0}, {"(iii) last line is #{expected}", last == expected}]

  defp expected_limbs({:refuse, kind, needles}, out, status, last, _) do
    [{"(iii) exit non-zero", status != 0}] ++
      Enum.map(needles, &{"(iii) prints #{inspect(&1)}", String.contains?(out, &1)}) ++
      [
        {"(iii) prints a stack trace", out =~ ~r/^    \(\S+ [^)]+\) \S+:\d+: /m},
        {"(iii) last line is #{@refuse}#{kind}", last == @refuse <> kind}
      ]
  end

  defp report_case(c, {{out, status}, limbs}, indent \\ "  ") do
    tag = if all_hold?(limbs), do: "OK ", else: "RED"
    held = Enum.count(limbs, &elem(&1, 1))

    IO.puts(
      "#{indent}#{tag} #{String.pad_trailing(c.id, 4)} exit #{status}  " <>
        "#{held}/#{length(limbs)} limbs  #{c.what}"
    )

    first = out |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "** ("))

    if first && first != last_line(out),
      do: IO.puts("#{indent}       #{String.slice(first, 0, 150)}")

    IO.puts("#{indent}       last: #{String.slice(last_line(out), 0, 150)}")
    for {l, false} <- limbs, do: IO.puts("#{indent}       FAILS #{l}")
    {c.id, limbs}
  end

  defp all_hold?(limbs), do: Enum.all?(limbs, &elem(&1, 1))

  defp last_line(out),
    do: out |> String.split("\n") |> Enum.reject(&(String.trim(&1) == "")) |> List.last() || ""

  # Counted HERE, from the table, not by the instrument: 23 over live count 0, 24 and 25
  # over DEAD rows, 26 and 27 over mutation_spec entries.
  defp pass_line(doc) do
    rows = doc["boundaries"]
    dead = Enum.count(rows, &(&1["verdict"] == "dead"))
    n = spec_count(rows)

    "ETCC-VERIFY PASS (scanned 23:#{Enum.count(rows, &zero_live?/1)} 24:#{dead} 25:#{dead} " <>
      "26:#{n} 27:#{n}; mutation_spec total #{n})"
  end

  defp zero_live?(b), do: (b["reddened_outside_own_and_dead"] || 0) == 0
  defp spec_count(rows), do: Enum.sum(Enum.map(rows, &length(&1["mutation_spec"] || [])))

  # Every write into the copy lands in a LATER second than the last task run. Mix's stale
  # check works in whole seconds: a plant, its compile and its restore inside one second
  # leave the mutant's beam in place, and the next case then runs it (found on MES-179:
  # EQ3 ran EQ2's plant, both a same-size edit to boundary_sweep.ex).
  defp copy_write!(path, bytes, modes \\ []) do
    settle(Process.get(:etcc_last_run, 0))
    File.write!(path, bytes, modes)
  end

  defp settle(last) do
    if System.os_time(:second) <= last do
      Process.sleep(50)
      settle(last)
    end
  end

  defp edit_table(copy, fun) do
    p = Path.join(copy, @paths.boundaries)
    doc = read(p)
    copy_write!(p, Jason.encode!(%{doc | "boundaries" => fun.(doc["boundaries"])}, pretty: true))
  end

  defp append(copy, f, text),
    do: copy_write!(Path.join(copy, f), @plant_note <> text <> "\n", [:append])

  defp replace(copy, f, from, to) do
    p = Path.join(copy, f)
    src = File.read!(p)
    n = src |> String.split(from) |> length() |> Kernel.-(1)
    if n != 1, do: raise("plant anchor occurs #{n} times in #{f} (must be 1)")
    copy_write!(p, String.replace(src, from, to))
  end

  # One copy per mode, refused unless the tree is clean, fingerprinted before and after.
  defp with_copy(fun) do
    if porcelain() != "" do
      IO.puts("  REFUSING TO START: `git status --porcelain` is not empty")
      System.halt(1)
    end

    {head, 0} = System.cmd("git", ["rev-parse", "--short", "HEAD"])
    before = fingerprint()
    IO.puts("  HEAD #{String.trim(head)}; real table sha256 #{elem(before, 0)}\n")

    copy =
      Path.join(
        System.tmp_dir!(),
        "etcc-verify-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(copy)

    try do
      {_, 0} = System.cmd("cp", ["-a", File.cwd!() <> "/.", copy])
      File.rm!(Path.join(copy, ".git"))
      fun.(copy)
    after
      File.rm_rf!(copy)

      if fingerprint() != before do
        IO.puts("  THE REAL TREE MOVED: table sha256 or `git status --porcelain` differs")
        System.halt(1)
      end
    end
  end

  defp fingerprint do
    sha = :crypto.hash(:sha256, File.read!(@paths.boundaries)) |> Base.encode16(case: :lower)
    {sha, porcelain()}
  end

  defp porcelain do
    {out, 0} = System.cmd("git", ["status", "--porcelain"])
    out
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
