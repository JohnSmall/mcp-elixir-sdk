defmodule Mix.Tasks.Conformance.Sweep do
  @shortdoc "Re-runs the ET-CC boundary-liveness sweep and diffs it against the committed table"

  @moduledoc """
  Re-runs MES-81's boundary-liveness sweep and compares the result with
  `conformance/data/etcc-boundaries.json`.

      mix conformance.sweep --verify         # guards 23-27 only. No test runs. Seconds.
      mix conformance.sweep --host           # skip condition (c). No test runs. Seconds.
      mix conformance.sweep --check          # full sweep, then diff. Nonzero on drift.
      mix conformance.sweep --out PATH       # full sweep, write the regenerated table
      mix conformance.sweep --only ID        # one direction (repeatable)
      mix conformance.sweep --disambiguate   # both readings of an ambiguous mutation_spec
      mix conformance.sweep --emit-spec PATH # (re)derive mutation_spec from the prose
      mix conformance.sweep --record-host    # re-measure the baseline, record control.host

  ## Cadence

  This is an **end-of-sprint** instrument, not a per-ticket gate — `CLAUDE.md`,
  End-of-Sprint Procedure step 4, which also states the three-condition skip and what the
  cadence gives up. A full `--check` is roughly 25 minutes: 50 mutation cycles at ~22 s
  plus a byte-probe run for every direction whose live count is zero.

  ## `--host`, and why a git diff is not enough

  Conditions (a) and (b) of the skip are `git diff` over `lib/` and over the unit
  population's files. **Neither can see the host**, and L1's population depends on it:
  `test_helper.exs` excludes three `:requires_live_harness` conformance tests where
  `node` or the pinned harness is absent, so one unchanged tip measures 994 units with
  `node` and 991 without — with both git conditions empty across the pair (`S8-11`).
  `--host` is condition (c): it compares this host's fingerprint against the one recorded
  in the committed table's `control` block and **exits 1 unless they match**, including
  when nothing is recorded and when the current fact cannot be read. Fail-closed, because
  "I could not tell" must mean *run the sweep*.

  ## What `--check` compares, and why not everything

  **Verdict fields only** — `verdict`, `established_by`, `direction`, `l2.ran`,
  `l2.verdict`. Those are claims about `lib/`. The measurement fields are functions
  of `lib/` **and** of the unit population (§2.3(e) as extended on MES-88), so they are
  reported as a stated delta rather than compared: the population moved 979 → 1021 with
  `lib/` byte-unchanged, and a criterion that cannot be satisfied gets met by fudging.

  A verdict difference exits **1** and names the direction, the old and new verdict, and
  the ET-CC register rows that direction would move.
  """

  use Mix.Task

  alias MCP.Conformance.BoundarySweep, as: Sweep

  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          verify: :boolean,
          host: :boolean,
          record_host: :boolean,
          check: :boolean,
          out: :string,
          only: :keep,
          disambiguate: :boolean,
          emit_spec: :string
        ]
      )

    only = for {:only, v} <- opts, do: v
    only = if only == [], do: nil, else: only

    # Split by COST, which is also the split a caller cares about: everything above
    # `measuring/2` answers in seconds and runs no test, everything below re-measures.
    cond do
      opts[:verify] -> verify()
      opts[:host] -> host()
      opts[:emit_spec] -> emit_spec(opts[:emit_spec])
      true -> measuring(opts, only)
    end
  end

  defp measuring(opts, only) do
    cond do
      opts[:record_host] -> record_host()
      opts[:disambiguate] -> disambiguate(only)
      opts[:check] -> check(only, opts[:out])
      opts[:out] -> generate(only, opts[:out])
      true -> Mix.raise("nothing to do: pass --verify, --host, --check, --out or --disambiguate")
    end
  end

  # --- --verify: the guards alone, with their populations printed ---

  defp verify do
    rows = boundaries()["boundaries"]
    scanned = Sweep.check_table!(rows)

    Mix.shell().info("GUARDS 23-27 — no violation. Populations actually scanned:")

    for {k, v} <- Enum.sort(scanned) do
      Mix.shell().info("  #{String.pad_trailing(to_string(k), 20)} #{v}")
    end

    Mix.shell().info("""

    The counts above are the POSITIVE control. A guard reporting zero violations is
    otherwise indistinguishable between "the predicate fired and nothing matched" and
    "the sweep never reached the population". Only a mutation proves the predicate can
    fire: conformance/controls/etcc_boundary_sweep_controls.exs guards.
    """)
  end

  # --- --host: skip condition (c), the one a git diff cannot express ---

  # Prints BOTH fingerprints and the verdict, in the shape the skip record wants, so that
  # "checked, and zero" carries the host it was checked under rather than just the answer.
  defp host do
    committed = boundaries()["control"]
    current = Sweep.host()

    case Sweep.host_check(committed, current) do
      {:match, host} ->
        report_host(committed["host"], host)
        Mix.shell().info("  HOST MATCHES — condition (c) is satisfied.")

      {:differ, recorded, host} ->
        report_host(recorded, host)

        Mix.raise(
          "HOST DIFFERS — the sweep may NOT be skipped. L1 quantifies over the unit " <>
            "population and the population is a function of this host, so a verdict " <>
            "taken on the recorded host is not a claim about this one."
        )

      {:unrecorded, host} ->
        report_host(nil, host)

        Mix.raise(
          "NO HOST RECORDED with the committed table — the sweep may NOT be skipped. " <>
            "Fail-closed on purpose: an unrecorded host and a matching one are " <>
            "indistinguishable from the skip's point of view, and reading absence as " <>
            "satisfaction is the defect this condition exists to close."
        )
    end
  end

  defp report_host(recorded, current) do
    Mix.shell().info("== SKIP CONDITION (c) — the host ==")
    Mix.shell().info("  recorded with the table: #{(recorded || %{})["fingerprint"] || "(none)"}")
    Mix.shell().info("  this host:               #{current["fingerprint"]}")

    if current["harness_reason"],
      do: Mix.shell().info("  harness:                 #{current["harness_reason"]}")
  end

  # --- --record-host: put this host into the committed table, generated not hand-edited ---

  defp record_host do
    control = Sweep.record_host!(log: &log/1)
    Mix.shell().info("  recorded host: #{control["host"]["fingerprint"]}")

    Mix.shell().info("""

    Written into #{Sweep.paths().boundaries}'s GENERATED `control` block, by the same
    control_block/3 the full sweep uses. It refuses unless the baseline it just measured
    is the one the committed block already records — same suite total, same baseline
    failures, green — so the fingerprint cannot be attached to a population the table was
    never taken at.
    """)
  end

  # --- --check: sweep, then diff on the verdict fields ---

  defp check(only, out) do
    committed = boundaries()
    generated = Sweep.sweep(only: only, log: &log/1)
    if out, do: write(generated, out)

    %{verdict_diffs: vd, measurement_deltas: md} = Sweep.check(generated, committed)

    Mix.shell().info("\n== MEASUREMENT DELTA (§2.3(e), reported not raised on) ==")

    if md == [] do
      Mix.shell().info("  none — every measurement field reproduces at this population too.")
    else
      Mix.shell().info("  #{length(md)} direction(s) differ on measurement fields only:")
      for d <- md, do: Mix.shell().info("    #{d["id"]}: #{Enum.join(d["fields"], ", ")}")

      Mix.shell().info("""
        CAUSE: the unit population, not lib/. L1 quantifies over the suite; a verdict
        expires when lib/ moves, its L1 measurements additionally when the population does.
      """)
    end

    Mix.shell().info("\n== VERDICT DIFF (AC5 — this is the loud one) ==")

    if vd == [] do
      Mix.shell().info("  none — every verdict field reproduces byte-exactly.")
    else
      Enum.each(vd, &report_drift/1)
      Mix.raise("#{length(vd)} boundary-direction(s) have DRIFTED from the committed table")
    end
  end

  # AC5: a drifted verdict names the direction, the old and new value, AND the ET-CC rows
  # it would move. A drift report that does not say what it costs is a prompt to ignore it.
  defp report_drift(d) do
    Mix.shell().error("  DRIFTED  #{d["id"]}")
    Enum.each(d["fields"], &report_field/1)

    Mix.shell().error(
      "     would move #{length(d["et_cc_rows"])} ET-CC row(s): " <>
        (d["et_cc_rows"] |> Enum.take(6) |> Enum.join("; ")) <>
        if(length(d["et_cc_rows"]) > 6, do: " ...", else: "")
    )
  end

  defp report_field(f) do
    Mix.shell().error("     #{f["field"]}: #{inspect(f["was"])} -> #{inspect(f["now"])}")
  end

  defp generate(only, out) do
    Sweep.sweep(only: only, log: &log/1) |> write(out)
  end

  defp write(doc, path) do
    File.write!(path, Jason.encode!(doc, pretty: true) <> "\n")
    Mix.shell().info("wrote #{path}")
  end

  # --- --emit-spec: derive mutation_spec from the committed prose ---

  # `mutation_spec` is an ADDITION, never a replacement: the authored `mutation` prose
  # stays byte-identical so AC1's byte-comparison is about the bytes MES-81 committed.
  # An existing `replace` is PRESERVED — the reading of a multi-occurrence FROM was
  # settled by measurement (`--disambiguate`), and re-deriving must not quietly discard
  # that answer.
  defp emit_spec(path) do
    doc = boundaries()

    rows =
      Enum.map(doc["boundaries"], fn b ->
        overrides =
          (b["mutation_spec"] || [])
          |> Enum.with_index()
          |> Map.new(fn {e, i} -> {i, e["replace"] || "all"} end)

        Map.put(b, "mutation_spec", Sweep.derive_spec(b, overrides))
      end)

    doc = %{doc | "boundaries" => rows}
    Sweep.check_spec_prose!(rows)
    Sweep.check_spec_resolves!(rows)
    write(doc, path)

    Mix.shell().info(
      "  #{Enum.sum(Enum.map(rows, &length(&1["mutation_spec"])))} entries; " <>
        "guards 26 and 27 pass over them"
    )
  end

  # --- --disambiguate: settle a multi-occurrence FROM by RE-MEASUREMENT ---

  # 16 of the 194 committed mutation lines have a FROM that occurs 2-6 times in its file,
  # and nothing in the record says whether the sweeper replaced one occurrence or all of
  # them. S7-19 says the answer can decide the verdict: a narrow mutation under-reports
  # reachability and returns the reassuring "dead". So it is settled by RUNNING BOTH
  # READINGS and keeping whichever reproduces the committed `reddened_by_module` — never
  # by reading the record and forming a view. Where NEITHER reproduces, that is a finding.
  defp disambiguate(only) do
    rows = boundaries()["boundaries"]

    subjects =
      rows
      |> Enum.filter(fn b -> Enum.any?(Sweep.derive_spec(b), &(&1["occurrences"] > 1)) end)
      |> then(fn bs -> if only, do: Enum.filter(bs, &(&1["id"] in only)), else: bs end)

    Mix.shell().info("#{length(subjects)} direction(s) carry an ambiguous FROM.\n")

    Enum.each(subjects, fn b ->
      Mix.shell().info("== #{b["id"]}")
      Enum.each(~w(all first), &try_reading(b, &1))
    end)
  end

  # Run ONE reading of an ambiguous FROM and say whether it reproduces the committed
  # breakdown. Whichever reproduces is the reading the original sweeper used; where
  # NEITHER does, that is a finding and not a coin toss (S7-19).
  defp try_reading(b, reading) do
    committed = b["reddened_by_module"]
    spec = Sweep.derive_spec(b, blanket(b, reading))
    backups = Sweep.apply!(spec)

    run =
      try do
        Sweep.run_suite()
      after
        Sweep.revert!(backups)
      end

    got =
      run.units
      |> Enum.map(&(&1 |> String.split(["(", ")"]) |> Enum.at(1)))
      |> Enum.frequencies()

    Mix.shell().info(
      "   #{String.pad_trailing(reading, 6)} #{run.summary} " <>
        "reddened_by_module #{if got == committed, do: "REPRODUCES", else: "differs"}"
    )

    unless got == committed do
      Mix.shell().info("          committed #{inspect(committed)}")
      Mix.shell().info("          measured  #{inspect(got)}")
    end
  end

  defp blanket(b, reading) do
    b |> Sweep.derive_spec() |> Enum.with_index() |> Map.new(fn {_e, i} -> {i, reading} end)
  end

  defp boundaries, do: Sweep.paths().boundaries |> File.read!() |> Jason.decode!()

  defp log(line), do: Mix.shell().info(line)
end
