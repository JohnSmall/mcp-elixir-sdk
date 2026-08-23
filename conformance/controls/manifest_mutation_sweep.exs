#!/usr/bin/env elixir
# MES-75 MANIFEST MUTATION SWEEP — the control for `in_scope_manifest_test.exs`.
#
#     mix run conformance/controls/manifest_mutation_sweep.exs five
#     mix run conformance/controls/manifest_mutation_sweep.exs exhaustive
#
# ## What this exists to establish
#
# `test/conformance/in_scope_manifest_test.exs` guards the one artefact every
# ticket downstream of A1 counts against. A guard is worth exactly what it can
# be shown to REJECT, and a suite that is green on the committed file is green
# whether it discriminates or not. This file mutates the committed manifest one
# way at a time and reads the suite's verdict off each mutation, so the guard's
# reach is a measured result rather than a claim about the assertions' wording.
#
# ## Why it is COMMITTED, and not a script in /tmp
#
# CODE_REVIEWER established this ticket's defect with a five-row table at
# MES-66's merge gate (comment 25594). The table was reported; the script that
# produced it was not committed and no longer exists. Reconstructing it from
# prose happened to reproduce the counts — but had it not, a bad reconstruction
# and a changed tree would have been indistinguishable, and the ticket's premise
# unfalsifiable in either direction. Recorded as S7-1 in `docs/sprint_7_issues.md`.
#
# So the MUTATION DEFINITIONS live here, not just a runner. They are the part
# that was lost. A runner that read them from somewhere uncommitted would
# reproduce S7-1 inside the fix for S7-1.
#
# ## The two layers, and why the exhaustive one is not showing off
#
# `five` is CODE_REVIEWER's table: four mutations plus the restored file, on the
# same row targets, so the before and after sit side by side as one comparison.
#
# `exhaustive` mutates EVERY row of the manifest one at a time under four
# families. A five-row table lets its author choose the row, and "I picked the
# one that goes red" is indistinguishable from "every row goes red" when only
# one is shown. At 0.67s a run, removing the choice costs about eight minutes.
#
# ## The families
#
#   * `EMPTY`                   — `scenarios: []`. The whole-file control.
#   * `DROP_EXCLUSION`          — drop `derivation.excluded[0]`.
#   * `FLIP_STATUS`             — one row's `status` replaced with a different
#     one of the five. Counts unchanged, key unchanged. This is the mutation
#     that passed before MES-75, and `status` is the field A5 applied the
#     match-target rule to and C1 computes the verdict pair from.
#   * `FABRICATE_ROW`           — one row's id/name/description replaced with
#     novel values, `key` LEFT STALE. CODE_REVIEWER's form.
#   * `FABRICATE_ROW_COHERENT`  — id/name/description AND the key's copies of
#     them changed together. Added at MES-75. `FABRICATE_ROW` is caught by any
#     key-consistency assertion; this one is not, and it is the honest test of
#     whether anything committed pins a row's identity.
#   * `ERROR_MESSAGE`           — one row's `errorMessage` replaced. **This is
#     the NEGATIVE CONTROL and it is expected to be caught on 21 rows only.**
#
# ## Reading the exhaustive result — the negative control is the point
#
# A sweep in which everything goes red proves nothing about discrimination; it
# is consistent with a suite that fails on any edit whatsoever. Uncaught rows
# are therefore ENUMERATED rather than counted, and an expected-uncaught set is
# a finding to be explained, not a hole to be quietly closed.
#
# The first three families all reach 175/175, so on their own they cannot tell
# a discriminating suite from an indiscriminate one. `ERROR_MESSAGE` is what
# separates the two. `errorMessage` is pinned by the censuses' `failed_checks`
# for FAILURE|WARNING rows and by NOTHING for the rest — no census list
# mentions a passing check, and `bucket-0` does not carry the field at all. A
# suite that failed on any edit whatsoever would go red on all 175 here. A
# suite that is measuring something goes red on exactly 21.
#
# So the expected reading of a healthy sweep is 175 / 175 / 175 / **21**, and
# the fourth number is the one that makes the first three mean anything.
#
# ## Safety
#
# The manifest is a COMMITTED file and this script rewrites it in place. The
# original bytes are held in memory, restored after every single run, and the
# md5 is re-checked at exit. If the restore ever fails the script says so and
# exits non-zero: a sweep that leaves a mutated artefact in the tree is worse
# than no sweep at all.

defmodule ManifestMutationSweep do
  @manifest "docs/conformance/in-scope-2026-07-28.json"
  @suite "test/conformance/in_scope_manifest_test.exs"

  # Fixed so two sweeps are comparable. Nothing here depends on order, and a
  # sweep whose numbers move between runs cannot be a control.
  @seed "0"

  @statuses ~w(SUCCESS FAILURE SKIPPED WARNING INFO)

  @novel_id "fabricated-check-id"
  @novel_name "FabricatedCheck"
  @novel_description "a check that was never run"
  @novel_message "a message no run produced"

  def main(argv) do
    original = File.read!(@manifest)
    md5 = :crypto.hash(:md5, original) |> Base.encode16(case: :lower)

    IO.puts("manifest #{@manifest}")
    IO.puts("md5      #{md5}")
    IO.puts("suite    #{@suite}\n")

    try do
      case argv do
        ["five"] -> five(original)
        ["exhaustive"] -> exhaustive(original)
        _ -> IO.puts("usage: mix run #{__ENV__.file} five|exhaustive")
      end
    after
      File.write!(@manifest, original)
      restore_check!(md5)
    end
  end

  defp restore_check!(md5) do
    now = :crypto.hash(:md5, File.read!(@manifest)) |> Base.encode16(case: :lower)

    if now == md5 do
      IO.puts("\nrestored, md5 #{now}")
    else
      IO.puts("\nRESTORE FAILED: md5 #{now}, expected #{md5}")
      System.halt(1)
    end
  end

  # --- layer 1: CODE_REVIEWER's five rows ----------------------------------

  defp five(original) do
    manifest = Jason.decode!(original)

    rows =
      for {entry, si} <- Enum.with_index(manifest["scenarios"]),
          {check, ci} <- Enum.with_index(entry["checks"]),
          do: {si, ci, entry["leg"], entry["scenario"], check}

    # The SAME row targets CODE_REVIEWER used: the first FAILURE row for
    # FLIP_STATUS, and the very first row of the manifest for FABRICATE_ROW —
    # which is a SUCCESS row, i.e. the case no census `failed_checks` reaches.
    {fsi, fci, fleg, fscen, fcheck} =
      Enum.find(rows, fn {_, _, _, _, c} -> c["status"] == "FAILURE" end)

    {bsi, bci, bleg, bscen, bcheck} = hd(rows)

    IO.puts("FLIP_STATUS    target #{fleg}/#{fscen} #{fcheck["id"]} (#{fcheck["status"]})")
    IO.puts("FABRICATE_ROW  target #{bleg}/#{bscen} #{bcheck["id"]} (#{bcheck["status"]})\n")

    trials = [
      {"EMPTY", fn m -> Map.put(m, "scenarios", []) end},
      {"DROP_EXCLUSION", &drop_exclusion/1},
      {"FABRICATE_ROW", &mutate_row(&1, bsi, bci, :fabricate)},
      {"FLIP_STATUS", &mutate_row(&1, fsi, fci, :flip)},
      {"FABRICATE_ROW_COHERENT", &mutate_row(&1, bsi, bci, :fabricate_coherent)},
      {"RESTORED", & &1}
    ]

    IO.puts(String.pad_trailing("mutation", 24) <> "tests  failures  verdict")

    for {name, fun} <- trials do
      {tests, failures} = run(manifest, fun, original)
      verdict = if failures > 0, do: "CAUGHT", else: "PASSES <-- not caught"

      verdict =
        if name == "RESTORED", do: if(failures == 0, do: "green", else: "BROKEN"), else: verdict

      IO.puts(
        String.pad_trailing(name, 24) <>
          String.pad_leading(to_string(tests), 5) <>
          String.pad_leading(to_string(failures), 10) <> "  " <> verdict
      )
    end
  end

  # --- layer 2: every row, three families ----------------------------------

  defp exhaustive(original) do
    manifest = Jason.decode!(original)

    rows =
      for {entry, si} <- Enum.with_index(manifest["scenarios"]),
          {check, ci} <- Enum.with_index(entry["checks"]),
          do: {si, ci, entry["leg"], entry["scenario"], check}

    families = [:flip, :fabricate, :fabricate_coherent, :error_message]

    IO.puts(
      "#{length(rows)} rows x #{length(families)} families = " <>
        "#{length(rows) * length(families)} runs\n"
    )

    for family <- families do
      uncaught =
        rows
        |> Enum.reduce([], fn {si, ci, leg, scen, check}, acc ->
          {_tests, failures} = run(manifest, &mutate_row(&1, si, ci, family), original)

          if failures > 0 do
            acc
          else
            [{leg, scen, check["id"], check["discriminator"], check["status"]} | acc]
          end
        end)
        |> Enum.reverse()

      caught = length(rows) - length(uncaught)
      IO.puts("#{family_name(family)}  caught #{caught}/#{length(rows)}")

      if uncaught == [] do
        IO.puts("  uncaught: none")
      else
        IO.puts("  uncaught (#{length(uncaught)}), ENUMERATED:")

        for {leg, scen, id, disc, status} <- uncaught do
          d = if disc in [nil, ""], do: "", else: "##{disc}"
          IO.puts("    #{status}  #{leg}/#{scen}  #{id}#{d}")
        end
      end

      IO.puts("")
    end
  end

  defp family_name(:flip), do: "FLIP_STATUS           "
  defp family_name(:fabricate), do: "FABRICATE_ROW         "
  defp family_name(:fabricate_coherent), do: "FABRICATE_ROW_COHERENT"
  defp family_name(:error_message), do: "ERROR_MESSAGE (control)  "

  # --- the mutations -------------------------------------------------------

  defp drop_exclusion(manifest) do
    update_in(manifest, ["derivation", "excluded"], fn [_first | rest] -> rest end)
  end

  defp mutate_row(manifest, si, ci, family) do
    update_in(manifest, ["scenarios", Access.at(si), "checks", Access.at(ci)], fn check ->
      apply_family(check, family)
    end)
  end

  # A DIFFERENT status, deterministically: the next one round the declared five.
  defp apply_family(check, :flip) do
    i = Enum.find_index(@statuses, &(&1 == check["status"]))
    Map.put(check, "status", Enum.at(@statuses, rem(i + 1, length(@statuses))))
  end

  # CODE_REVIEWER's form: the fields move, the key does not.
  defp apply_family(check, :fabricate) do
    check
    |> Map.put("id", @novel_id)
    |> Map.put("name", @novel_name)
    |> Map.put("description", @novel_description)
  end

  # Fields and key together, so no internal-consistency assertion can see it.
  defp apply_family(check, :fabricate_coherent) do
    key =
      check["key"]
      |> List.replace_at(2, @novel_id)
      |> List.replace_at(3, @novel_name)
      |> List.replace_at(4, @novel_description)

    check |> apply_family(:fabricate) |> Map.put("key", key)
  end

  # The negative control. Pinned by `failed_checks` on the 21 FAILURE|WARNING
  # rows and by nothing anywhere on the other 154.
  defp apply_family(check, :error_message), do: Map.put(check, "errorMessage", @novel_message)

  # --- running -------------------------------------------------------------

  defp run(manifest, fun, original) do
    File.write!(@manifest, Jason.encode!(fun.(manifest), pretty: true) <> "\n")

    {out, _status} =
      System.cmd("mix", ["test", @suite, "--seed", @seed],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    File.write!(@manifest, original)
    parse(out)
  end

  # "24 tests, 0 failures" — also matches the "N doctests, N tests" form.
  defp parse(out) do
    case Regex.run(~r/(\d+) tests?, (\d+) failures?/, out) do
      [_, t, f] ->
        {String.to_integer(t), String.to_integer(f)}

      nil ->
        IO.puts("\nCOULD NOT PARSE mix test output:\n#{out}")
        System.halt(1)
    end
  end
end

ManifestMutationSweep.main(System.argv())
