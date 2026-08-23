#!/usr/bin/env elixir
# MES-83 (B3) CONTROLS — the evidence that the row capture DISCRIMINATES.
#
#     mix run conformance/controls/exunit_rows_controls.exs states
#     mix run conformance/controls/exunit_rows_controls.exs flip
#     mix run conformance/controls/exunit_rows_controls.exs reconcile
#     mix run conformance/controls/exunit_rows_controls.exs sweep [seeds]
#     mix run conformance/controls/exunit_rows_controls.exs all
#
# ## What this exists to establish (hazard 4)
#
# A reporter that emitted `{"status": "passed"}` unconditionally would produce a
# perfect-looking artefact on every run, and a suite that is green tells you
# nothing about which of the two you have. "A control never seen red is a
# claim." So:
#
#   * `states`    — POSITIVE control. A real run over the committed fixtures
#                   produces all five statuses, each with its own row. The rows
#                   are PRINTED, not described.
#   * `flip`      — NEGATIVE control, and the sharper one. The SAME test, the
#                   same bytes, run twice: once excluded, once not. Its row must
#                   change status. A reporter that stamped a constant cannot do
#                   that, and neither can one that reads the source rather than
#                   the run.
#   * `reconcile` — AC1. The row count against ExUnit's OWN summary, per test
#                   type, on the full suite.
#   * `sweep`     — AC5. Row content across ~20 seeds.
#
# ## S7-4 — the instrument must be shown to have FIRED
#
# "The fixture did not load" and "the formatter emitted nothing" both produce a
# clean-looking run with no failure row: the well-formed answer that means the
# instrument never ran. Every subcommand therefore checks, as its own reported
# outcome, that the artefact exists, was written by THIS run (mtime at or after
# the run's start), and that the formatter announced itself on stderr. A miss
# prints `CONTROL DID NOT FIRE (not a result)` and exits non-zero, rather than
# printing a table that reads as a result.
#
# ## S7-2 — nothing here is restored, because nothing here is mutated
#
# The fixtures are committed files outside `test_paths`. The tree is checked
# with `git status --porcelain` before and after every subcommand anyway: an
# assurance that nothing was mutated is worth less than a measurement of it.
defmodule ExUnitRowsControls do
  alias MCP.Conformance.ExUnitRows

  @fixture "conformance/controls/exunit_rows_control_fixture.exs"
  @invalid_fixture "conformance/controls/exunit_rows_invalid_fixture.exs"
  @exclude_tag "mes83_control_excluded"
  @seed "0"
  @default_seeds 20

  # The five keys the `states` control must produce, and the status each must
  # carry. Stated up front so the control has an expectation to MISS, rather
  # than a table to describe after the fact.
  @expected %{
    "MES83.ControlFixture/test passes" => "passed",
    "MES83.ControlFixture/test fails deliberately" => "failed",
    "MES83.ControlFixture/test is skipped by tag" => "skipped",
    "MES83.ControlFixture/test is excluded by filter" => "excluded",
    "MES83.InvalidFixture/test never runs, and is invalid rather than failed" => "invalid"
  }

  def main(argv) do
    before = tree_state()

    try do
      case argv do
        ["states"] -> states()
        ["flip"] -> flip()
        ["reconcile"] -> reconcile()
        ["sweep"] -> sweep(@default_seeds)
        ["sweep", n] -> sweep(String.to_integer(n))
        ["all"] -> all()
        _ -> usage()
      end
    after
      tree_check!(before)
    end
  end

  defp usage do
    IO.puts("usage: mix run #{__ENV__.file} states|flip|reconcile|sweep [seeds]|all")
  end

  defp all do
    states()
    flip()
    reconcile()
  end

  # --- positive control: all five states, from one real run ------------------

  defp states do
    section("STATES — the five ExUnit states, each with its own row")

    {out, artefact} = capture([@fixture, @invalid_fixture], ["--exclude", @exclude_tag])

    print_rows(artefact["rows"])
    IO.puts("\nExUnit's own summary: #{summary_line(out)}")

    print_totals(artefact)
    print_cross_check(artefact)

    seen = Map.new(artefact["rows"], &{&1["key"], &1["status"]})
    misses = for {key, want} <- @expected, Map.get(seen, key) != want, do: {key, want, seen[key]}

    if misses == [] do
      IO.puts("\nall five expected keys carry their expected status: OK")
    else
      for {key, want, got} <- misses, do: IO.puts("MISS  #{key}: wanted #{want}, got #{inspect(got)}")
      halt("expected states not produced")
    end

    present = artefact["rows"] |> Enum.map(& &1["status"]) |> Enum.uniq() |> Enum.sort()

    if present == Enum.sort(ExUnitRows.statuses()) do
      IO.puts("all five statuses present in one run: #{Enum.join(present, " ")}")
    else
      halt("statuses present were #{inspect(present)}")
    end
  end

  # --- negative control: the same test, two runs, two statuses ---------------

  defp flip do
    section("FLIP — one test, two runs. The status is a function of the RUN.")

    key = "MES83.ControlFixture/test is excluded by filter"

    {_out_a, a} = capture([@fixture], ["--exclude", @exclude_tag])
    {_out_b, b} = capture([@fixture], [])

    row_a = find_row(a, key)
    row_b = find_row(b, key)

    IO.puts("with    --exclude #{@exclude_tag}:  status=#{row_a["status"]}  reason=#{inspect(row_a["reason"])}")
    IO.puts("without --exclude #{@exclude_tag}:  status=#{row_b["status"]}  reason=#{inspect(row_b["reason"])}")

    cond do
      row_a["status"] != "excluded" ->
        halt("the excluded run did not produce an excluded row")

      row_b["status"] != "passed" ->
        halt("the unfiltered run did not produce a passed row")

      row_a["file"] != row_b["file"] or row_a["line"] != row_b["line"] ->
        halt("the two rows are not the same test")

      true ->
        IO.puts("\nsame key, same file:line, status flipped excluded -> passed: OK")
        IO.puts("A reporter stamping a constant, or reading the source rather than the run,")
        IO.puts("cannot produce this pair. That is what the flip buys over the states table.")
    end
  end

  # --- AC1: the full suite against ExUnit's own summary ----------------------

  defp reconcile do
    section("RECONCILE — rows against ExUnit's OWN summary, per test type (AC1)")

    {out, artefact} = capture([], ["--seed", @seed])
    result = ExUnitRows.reconcile(out, artefact["totals"])

    IO.puts("ExUnit says: #{result["summary_line"]}")
    IO.puts("rows:        #{artefact["totals"]["total"]}\n")

    IO.puts(pad("check", 20) <> pad("exunit", 10) <> pad("rows", 10) <> "verdict")

    for c <- result["checks"] do
      IO.puts(
        pad(c["name"], 20) <>
          pad(to_string(c["exunit"]), 10) <>
          pad(to_string(c["rows"]), 10) <> if(c["ok"], do: "agree", else: "DISAGREE")
      )
    end

    print_cross_check(artefact)
    IO.puts("key_collisions: #{inspect(artefact["run"]["key_collisions"])}")
    IO.puts("complete: #{artefact["run"]["complete"]}")

    unless result["ok"], do: halt("reconciliation disagreed")
    IO.puts("\nreconciliation: OK")
  end

  # --- AC5: row content across seeds ----------------------------------------

  defp sweep(seeds) do
    section("SWEEP — row CONTENT across #{seeds} seeds (AC5)")

    results =
      for seed <- 0..(seeds - 1) do
        {_out, artefact} = capture([], ["--seed", to_string(seed)])
        {seed, ExUnitRows.rows_md5(artefact["rows"]), artefact["run"]}
      end

    for {seed, md5, _run} <- results, do: IO.puts("seed #{pad(to_string(seed), 6)} rows md5 #{md5}")

    md5s = results |> Enum.map(fn {_, md5, _} -> md5 end) |> Enum.uniq()

    if length(md5s) == 1 do
      IO.puts("\n#{seeds} seeds, ONE rows md5: #{hd(md5s)}")
    else
      IO.puts("\nROW CONTENT MOVED WITH THE SEED: #{inspect(md5s)}")
      halt("row content is not seed-independent")
    end

    # What is NOT claimed: the run block. Show exactly which of its fields move.
    {_, _, first} = hd(results)

    moved =
      results
      |> Enum.flat_map(fn {_, _, run} -> for {k, v} <- run, v != first[k], do: k end)
      |> Enum.uniq()
      |> Enum.sort()

    IO.puts("run-block fields that differ across the sweep: #{inspect(moved)}")
    IO.puts("(claimed: `rows` is byte-identical. NOT claimed: the run block, or")
    IO.puts(" failure-detail text — a green suite has no failure rows to exercise it.)")
  end

  # --- running, and the S7-4 fire check -------------------------------------

  defp capture(paths, args) do
    out_path = Path.join(System.tmp_dir!(), "mes83_control_#{System.unique_integer([:positive])}.json")
    File.rm_rf!(out_path)
    started = System.os_time(:second)

    {out, _status} =
      System.cmd("mix", ["test"] ++ paths ++ args,
        env: [{"MIX_ENV", "test"}, {ExUnitRows.env_path_var(), out_path}],
        stderr_to_stdout: true
      )

    fired!(out, out_path, started)
    artefact = out_path |> File.read!() |> Jason.decode!()
    File.rm_rf!(out_path)
    {out, artefact}
  end

  # S7-4, one domain over: assert the instrument LANDED before believing its
  # result. Three independent conditions, because each fails differently.
  defp fired!(out, path, started) do
    cond do
      not String.contains?(out, "[etcc-rows] wrote") ->
        IO.puts(out)
        halt("CONTROL DID NOT FIRE (not a result): the formatter never announced a write")

      not File.exists?(path) ->
        halt("CONTROL DID NOT FIRE (not a result): no artefact at #{path}")

      File.stat!(path, time: :posix).mtime < started ->
        halt("CONTROL DID NOT FIRE (not a result): #{path} predates this run — stale artefact")

      true ->
        :ok
    end
  end

  # --- tree state — a measurement, not an assurance -------------------------

  defp tree_state do
    {out, 0} = System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true)
    String.trim(out)
  end

  defp tree_check!(before) do
    now = tree_state()

    cond do
      now == before and now == "" -> IO.puts("\ntree clean before and after: OK (nothing was mutated)")
      now == before -> IO.puts("\ntree unchanged by this run (it was already dirty): OK")
      true -> IO.puts("\nTREE CHANGED BY THIS RUN:\n#{now}")
    end
  end

  # --- printing --------------------------------------------------------------

  defp print_rows(rows) do
    IO.puts(pad("status", 10) <> pad("type", 10) <> pad("file:line", 56) <> "key")

    for row <- rows do
      IO.puts(
        pad(row["status"], 10) <>
          pad(row["test_type"], 10) <>
          pad("#{row["file"]}:#{row["line"]}", 56) <> row["key"]
      )

      if row["reason"], do: IO.puts(pad("", 20) <> "reason: " <> row["reason"])

      for f <- row["failure"] || [] do
        IO.puts(pad("", 20) <> "failure: #{f["exception"]} at #{f["at"]} — #{one_line(f["message"])}")
      end
    end
  end

  defp print_totals(artefact) do
    t = artefact["totals"]
    IO.puts("\ntotals (DERIVED from the rows above, never counted alongside them):")
    IO.puts("  total            #{t["total"]}")
    IO.puts("  by_status        #{inspect(t["by_status"])}")
    IO.puts("  by_test_type     #{inspect(t["by_test_type"])}")

    derived = ExUnitRows.derive_totals(artefact["rows"])
    IO.puts("  re-derived here: #{if derived == t, do: "identical", else: "DIFFERS — #{inspect(derived)}"}")
  end

  # The second witness. Its MEMBERSHIP is established here rather than
  # described: `module_finished` carries the module's own test list, and the
  # control run says which rows are in it.
  # The second witness, and its MEMBERSHIP established rather than described.
  #
  # `compared` is the number of keys the modules' own `module_finished` lists
  # carried. Only rows with status passed/failed/invalid are offered to the
  # comparison, so if an excluded or skipped test WERE in those lists the run
  # would report `missing_from_events` for it and `compared` would exceed the
  # run/invalid row count. An empty disagreement list in the presence of
  # excluded and skipped rows is therefore a measurement of what that list
  # holds, not an assumption about it.
  defp print_cross_check(artefact) do
    cc = artefact["run"]["module_cross_check"]
    by_status = artefact["totals"]["by_status"]
    in_list = by_status["passed"] + by_status["failed"] + by_status["invalid"]
    not_in_list = by_status["excluded"] + by_status["skipped"]

    IO.puts("\nmodule_finished membership (established by this run, not described):")
    IO.puts("  modules reporting a test list        #{cc["modules"]}")
    IO.puts("  keys in those lists                  #{cc["compared"]}")
    IO.puts("  rows passed/failed/invalid           #{in_list}")
    IO.puts("  rows excluded/skipped                #{not_in_list}  <- absent from those lists")
    IO.puts("  disagreements                        #{inspect(cc["disagreements"])}")
  end

  defp summary_line(out) do
    case ExUnitRows.parse_summary(out) do
      {:ok, s} -> s["line"]
      :error -> "(no summary line found)"
    end
  end

  defp find_row(artefact, key) do
    Enum.find(artefact["rows"], &(&1["key"] == key)) ||
      halt("no row for #{key} — the fixture did not produce it")
  end

  defp one_line(nil), do: ""
  defp one_line(s), do: s |> String.split("\n") |> Enum.reject(&(&1 == "")) |> Enum.join(" / ")

  defp pad(s, n), do: String.pad_trailing(to_string(s), n)

  defp section(title) do
    IO.puts("\n" <> String.duplicate("=", 78))
    IO.puts(title)
    IO.puts(String.duplicate("=", 78))
  end

  defp halt(message) do
    IO.puts("\n" <> message)
    System.halt(1)
  end
end

ExUnitRowsControls.main(System.argv())
