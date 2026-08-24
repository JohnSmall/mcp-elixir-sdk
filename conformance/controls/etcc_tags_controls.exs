#!/usr/bin/env elixir
# MES-84 (B4) CONTROLS — the evidence that the drift guard FAILS RED, in both
# directions, and that `mix test.etcc` cannot pass vacuously.
#
#     mix run conformance/controls/etcc_tags_controls.exs derive
#     mix run conformance/controls/etcc_tags_controls.exs doctest_options
#     mix run conformance/controls/etcc_tags_controls.exs diff
#     mix run conformance/controls/etcc_tags_controls.exs select
#     mix run conformance/controls/etcc_tags_controls.exs mutate
#     mix run conformance/controls/etcc_tags_controls.exs vacuous
#     mix run conformance/controls/etcc_tags_controls.exs all
#
# ## Why this is a `mix run` script and not a tagged ExUnit test
#
# Ruled at MES-84's ratification, and it is the sharpest case of the denominator
# note in the sprint. A guard implemented as a tagged ExUnit test would become a
# **282nd member of the population it validates**, and `mix test.etcc` would run
# the guard as one of our conformance claims. An instrument that changes its own
# denominator by existing is a perturbation, not a test.
#
# ## HAZARD 3 — both directions, at two levels, because they answer different
# ## questions
#
#   * **L1 `diff`** — the comparison itself, fed mutated inputs, with its red
#     ASSERTED rather than described. Runs every time. A guard whose red is
#     asserted on every run cannot decay into a claim.
#
#   * **L2 `mutate`** — the whole chain: a source edit, compiled, tagged by
#     ExUnit, captured into the artefact, adjudicated by `mix test.etcc`. L1
#     proves the comparison; only L2 proves that the comparison is wired to the
#     tree. Both mutations are made HERE, restored HERE, and the restoration is
#     md5-verified (S7-2) rather than asserted.
#
# ## HAZARD 4 — `vacuous`
#
# `mix test.etcc` must not be able to exit 0 having evaluated nothing. Note what
# is and is not ours: ExUnit ALREADY refuses a totally vacuous `--only` run, so
# this is a second independent guard on that condition. The case no exit status
# can express is PARTIAL selection, and that is what `mutate` demonstrates.
#
# ## S7-4 — the instrument must be shown to have FIRED
#
# Every subcommand that runs a subprocess checks that the capture exists and was
# written by that run before believing any figure off it. A miss prints
# `CONTROL DID NOT FIRE (not a result)` and exits non-zero, rather than a table
# that reads as a result.
defmodule ETCCTagsControls do
  alias MCP.Conformance.ETCCTags

  @all_fixture "conformance/controls/etcc_doctest_all_fixture.exs"
  @only_fixture "conformance/controls/etcc_doctest_only_fixture.exs"
  @typo_fixture "conformance/controls/etcc_doctest_typo_fixture.exs"

  # What the probe must observe. Stated up front so the control has an
  # expectation to MISS rather than a table to narrate afterwards.
  @probe_expected %{
    "MES84.DoctestAllFixture/doctest MCP.Conformance.DoctestOptionSubject.a/1 (1)" => nil,
    "MES84.DoctestAllFixture/doctest MCP.Conformance.DoctestOptionSubject.a/1 (2)" => nil,
    "MES84.DoctestAllFixture/doctest MCP.Conformance.DoctestOptionSubject.b?/1 (3)" => nil,
    "MES84.DoctestAllFixture/doctest MCP.Conformance.DoctestOptionSubject.b?/1 (4)" => nil,
    "MES84.DoctestAllFixture/doctest MCP.Conformance.DoctestOptionSubject.c/1 (5)" => nil,
    "MES84.DoctestOnlyFixture/doctest MCP.Conformance.DoctestOptionSubject.b?/1 (1)" => true,
    "MES84.DoctestOnlyFixture/doctest MCP.Conformance.DoctestOptionSubject.b?/1 (2)" => true,
    "MES84.DoctestTypoFixture/doctest MCP.Conformance.DoctestOptionSubject.c/1 (1)" => nil
  }

  @tag_body "@tag :etcc"

  def main(argv) do
    before = tree_state()

    try do
      case argv do
        ["derive"] -> derive()
        ["doctest_options"] -> doctest_options()
        ["diff"] -> diff_control()
        ["select"] -> select()
        ["mutate"] -> mutate()
        ["vacuous"] -> vacuous()
        ["all"] -> all()
        _ -> usage()
      end
    after
      tree_check!(before)
    end
  end

  defp usage do
    IO.puts(
      "usage: mix run #{__ENV__.file} derive|doctest_options|diff|select|mutate|vacuous|all"
    )
  end

  defp all do
    derive()
    doctest_options()
    diff_control()
    select()
    mutate()
    vacuous()
  end

  # --- the derivation, enumerated rather than summarised --------------------

  defp derive do
    section("DERIVE — the mechanism rule applied to the register, per declaration")

    plan = plan()

    IO.puts("declarations              #{length(plan.declarations)}")

    IO.puts(
      "  producing 1 unit        #{Enum.count(plan.declarations, &(length(&1.units) == 1))}"
    )

    IO.puts("  producing >1 unit       #{Enum.count(plan.declarations, &(length(&1.units) > 1))}")

    IO.puts(
      "units                     #{plan.declarations |> Enum.map(&length(&1.units)) |> Enum.sum()}"
    )

    IO.puts("")

    IO.puts(
      "mechanism :tag            #{length(plan.tag_points)} decl / #{members_of(plan.tag_points)} members"
    )

    IO.puts(
      "mechanism :directive      #{length(plan.directive_points)} decl / #{members_of(plan.directive_points)} members"
    )

    IO.puts(
      "mechanism :name           #{length(plan.name_points)} decl / #{members_of(plan.name_points)} members"
    )

    IO.puts("mechanism :escalate       #{length(plan.escalations)} decl  <== AC5: must be 0")
    IO.puts("expected member keys      #{plan.expected_count}")

    IO.puts(
      "\nevery declaration producing more than one runtime unit, and the mechanism the rule gives it:"
    )

    for d <- Enum.filter(plan.declarations, &(length(&1.units) > 1)) do
      labels =
        d.units
        |> Enum.frequencies_by(& &1["label"])
        |> Enum.sort()
        |> Enum.map_join(", ", fn {l, n} -> "#{l} #{n}" end)

      IO.puts(
        "  #{pad("#{d.file}:#{d.line}", 50)} n=#{pad(length(d.units), 4)} #{pad(d.test_type, 9)} #{pad(d.mechanism, 11)} #{labels}"
      )
    end

    IO.puts(
      "\nthe #{members_of(plan.name_points)} members carrying NO source mark (E1, S7-33) — first-class in the guard, never a special case:"
    )

    for p <- ETCCTags.name_proxies(plan), do: IO.puts("  #{p.key}")

    cond do
      plan.escalations != [] ->
        halt("#{length(plan.escalations)} test declaration(s) mix members with non-members (AC5)")

      ETCCTags.name_collisions(register()) != [] ->
        halt("test names are not unique tree-wide; exact-name selection would over-select")

      members_of(plan.tag_points) + members_of(plan.directive_points) +
        members_of(plan.name_points) !=
          plan.expected_count ->
        halt("the mechanisms do not partition the member set")

      true ->
        IO.puts("\nmechanisms partition the member set, 0 escalations, 0 name collisions: OK")
    end
  end

  # --- AC4: the doctest option vocabulary, measured ------------------------

  defp doctest_options do
    section("DOCTEST OPTIONS — tags: works, only: RENUMBERS, an unknown option is SILENT (AC4)")

    {_out, artefact} = capture_test([@all_fixture, @only_fixture, @typo_fixture], ["--seed", "0"])
    seen = Map.new(artefact["rows"], &{&1["key"], &1["tags"]["etcc"]})

    IO.puts(pad("module", 26) <> pad("generated test name", 60) <> "etcc tag")

    for row <- Enum.sort_by(artefact["rows"], & &1["key"]) do
      IO.puts(pad(row["module"], 26) <> pad(row["name"], 60) <> inspect(row["tags"]["etcc"]))
    end

    misses =
      for {key, want} <- @probe_expected,
          Map.get(seen, key, :absent) != want,
          do: {key, want, Map.get(seen, key, :absent)}

    if misses != [] do
      for {key, want, got} <- misses,
          do: IO.puts("MISS  #{key}: wanted #{inspect(want)}, got #{inspect(got)}")

      halt("the doctest option probe did not reproduce")
    end

    IO.puts("""

    Three results, and the third is why E1 was ruled "do not split":

      tags:   WORKS  — reaches every example of the selected {function, arity},
                       which is what makes the header_mirror directive exact.
      tagz:   SILENT — no error, no warning, exit 0, no tag. The mechanism rests
                       on a misspelling being caught somewhere ELSE, which is
                       `mix conformance.etcc_tags --check` and this guard.
      only:   RENUMBERS — b?/1 (3),(4) -> (1),(2) and c/1 (5) -> (1). The index
                       is inside the row key, and the row key is the authored
                       join key of conformance/data/etcc-decisions.json.
    """)
  end

  # --- L1: the comparison, red ASSERTED on every run ------------------------

  defp diff_control do
    section("DIFF (L1) — the comparison fed mutated inputs, its RED asserted every run")

    expected = plan().expected_keys
    a_member = expected |> Enum.sort() |> hd()
    invented = "MES84.NoSuchModule/test a key no register row carries"

    cases = [
      {"unmutated", expected, %{missing: 0, stray: 0}},
      {"a tag on a NON-member", MapSet.put(expected, invented), %{missing: 0, stray: 1}},
      {"a member's tag REMOVED", MapSet.delete(expected, a_member), %{missing: 1, stray: 0}},
      {"both at once", expected |> MapSet.delete(a_member) |> MapSet.put(invented),
       %{missing: 1, stray: 1}},
      {"nothing selected", MapSet.new(), %{missing: MapSet.size(expected), stray: 0}}
    ]

    IO.puts(pad("mutation", 30) <> pad("missing", 10) <> pad("stray", 10) <> "verdict")

    failures =
      for {name, actual, want} <- cases do
        got = ETCCTags.diff(expected, actual)
        ok? = length(got.missing) == want.missing and length(got.stray) == want.stray

        IO.puts(
          pad(name, 30) <>
            pad(length(got.missing), 10) <>
            pad(length(got.stray), 10) <>
            if(ok?, do: "as expected", else: "WRONG, wanted #{inspect(want)}")
        )

        if ok?, do: nil, else: name
      end

    IO.puts("\nthe two keys the mutations move, quoted so the assertion is checkable:")
    IO.puts("  removed member : #{a_member}")
    IO.puts("  invented stray : #{invented}")

    verdict = ETCCTags.adjudicate(expected, MapSet.new())
    IO.puts("\nzero-selection cause, verbatim from adjudicate/2:\n  #{verdict.cause}")

    partial = ETCCTags.adjudicate(expected, MapSet.delete(expected, a_member))
    IO.puts("\npartial-selection cause, verbatim:\n  #{partial.cause}")

    cond do
      Enum.any?(failures, & &1) ->
        halt("L1 did not behave as asserted: #{inspect(Enum.filter(failures, & &1))}")

      verdict.ok or partial.ok ->
        halt("adjudicate/2 called a mutated selection OK")

      true ->
        IO.puts("\nfive inputs, five expected verdicts, both directions asserted: OK")
    end
  end

  # --- AC1: the clean selection ---------------------------------------------

  defp select do
    section("SELECT — mix test.etcc over the tree as committed (AC1)")

    {out, status, artefact} = run_etcc([])
    selected = selected_keys(artefact)
    plan = plan()
    verdict = ETCCTags.adjudicate(plan.expected_keys, selected)

    IO.puts(summary_lines(out))

    IO.puts(
      "\nexit status #{status}, selected #{verdict.selected}, expected #{verdict.expected}, missing #{length(verdict.missing)}, stray #{length(verdict.stray)}"
    )

    IO.puts("\nthe 6 doctest members, by the mechanism each is selected by:")

    for row <- artefact["rows"],
        row["status"] != "excluded",
        row["test_type"] == "doctest" do
      by = if row["tags"]["etcc"], do: "directive tags:", else: "exact name filter"
      IO.puts("  #{pad(by, 20)} #{row["key"]}")
    end

    cond do
      not verdict.ok ->
        halt("the clean selection was not the member set: #{verdict.cause}")

      status != 0 ->
        halt("the clean selection exited #{status}")

      true ->
        IO.puts("\nselection == register member set, both directions, and the suite is green: OK")
    end
  end

  # --- L2: the whole chain, on the real tree --------------------------------

  defp mutate do
    section("MUTATE (L2) — a source edit, through compile, ExUnit, capture, adjudication")

    stray_target = first_untagged_test!()
    missing_target = first_tag_line!()

    IO.puts("""
    Both targets are chosen from the TREE, not from the register's line fields,
    so this control is valid whether or not the register has been re-synced:

      stray direction   add    #{@tag_body} above an UNTAGGED test declaration.
                        Untagged is the criterion because every member is marked,
                        so an untagged test declaration is a non-member by
                        construction rather than by a lookup.
      missing direction remove an existing #{@tag_body} line.
    """)

    with_mutation(stray_target, fn ->
      report_mutation("STRAY", stray_target, %{missing: 0}, fn v ->
        v.stray != [] and v.missing == []
      end)
    end)

    with_mutation(missing_target, fn ->
      report_mutation("MISSING", missing_target, %{stray: 0}, fn v ->
        v.missing != [] and v.stray == []
      end)
    end)

    section("MUTATE — restored, and green again")
    {_out, status, artefact} = run_etcc([])
    verdict = ETCCTags.adjudicate(plan().expected_keys, selected_keys(artefact))

    IO.puts(
      "after both restorations: exit #{status}, selected #{verdict.selected}, missing #{length(verdict.missing)}, stray #{length(verdict.stray)}"
    )

    unless verdict.ok and status == 0,
      do: halt("the tree did not come back green after the mutations")

    IO.puts("\nred, red, green — and the red named the key each time: OK")
  end

  defp report_mutation(direction, target, _want, ok_fun) do
    IO.puts("\n--- #{direction} — #{target.file}:#{target.line}")
    IO.puts("    bytes: #{inspect(target.bytes)}")

    {_out, status, artefact} = run_etcc([])
    verdict = ETCCTags.adjudicate(plan().expected_keys, selected_keys(artefact))

    IO.puts(
      "    mix test.etcc exit #{status}; selected #{verdict.selected} of #{verdict.expected}"
    )

    IO.puts("    missing #{length(verdict.missing)}, stray #{length(verdict.stray)}")
    for k <- verdict.missing, do: IO.puts("      MISSING  #{k}")
    for k <- verdict.stray, do: IO.puts("      STRAY    #{k}")
    IO.puts("    cause: #{verdict.cause}")

    cond do
      verdict.ok -> halt("#{direction}: the guard stayed GREEN over a mutated tree")
      status == 0 -> halt("#{direction}: mix test.etcc exited 0 over a mutated tree")
      not ok_fun.(verdict) -> halt("#{direction}: the guard went red in the wrong direction")
      true -> IO.puts("    RED, in the #{direction} direction only: OK")
    end
  end

  # --- HAZARD 4: the vacuous run --------------------------------------------

  defp vacuous do
    section("VACUOUS — mix test.etcc must not be able to evaluate nothing and exit 0")

    {out, status, artefact} = run_etcc([], %{ETCCTags.tag_env_var() => "mes84_no_such_tag"})
    selected = selected_keys(artefact)
    verdict = ETCCTags.adjudicate(plan().expected_keys, selected)

    IO.puts("MCP_ETCC_TAG=mes84_no_such_tag mix test.etcc")
    IO.puts("  exit status      #{status}")
    IO.puts("  selected         #{verdict.selected}")
    IO.puts("  expected         #{verdict.expected}")
    IO.puts("  our cause:       #{verdict.cause}")
    IO.puts("  captured tail:   #{last_line(out)}")

    # Measured here rather than asserted in prose: ExUnit's OWN behaviour on a
    # totally vacuous `--only`, run directly so the credit for the zero case is
    # given on evidence.
    {ex_out, ex_status} =
      System.cmd("mix", ["test", "--only", "mes84_no_such_tag", "--seed", "0"],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    IO.puts("\nmix test --only mes84_no_such_tag  (ExUnit alone, no task of ours)")
    IO.puts("  exit status      #{ex_status}")
    IO.puts("  says             #{exunit_says(ex_out)}")

    if ex_status == 0,
      do: halt("ExUnit exited 0 on a vacuous --only run — the write-up's premise is wrong")

    IO.puts("""

    What is NOT claimed here. ExUnit already refuses a totally vacuous `--only`
    run and names the cause, so the zero case was never ours to discover; this is
    a SECOND, independent guard on the same condition. The case that needs us is
    partial selection, which exits 0 whether 1 or 281 were selected — see
    `mutate`, where 1 removed tag turns a green run red.
    """)

    cond do
      status == 0 ->
        halt("a zero-selection run exited 0")

      verdict.selected != 0 ->
        halt("the knob did not produce a zero selection: #{verdict.selected}")

      verdict.cause == nil ->
        halt("the refusal named no cause")

      true ->
        IO.puts("zero selected, non-zero exit, cause named: OK")
    end
  end

  # --- mutation plumbing — restore is md5-verified, not asserted -------------

  defp with_mutation(target, fun) do
    original = File.read!(target.file)
    before_md5 = md5(original)

    try do
      File.write!(target.file, target.mutated)
      fun.()
    after
      File.write!(target.file, original)
      after_md5 = md5(File.read!(target.file))

      if after_md5 == before_md5 do
        IO.puts("    restored #{target.file}, md5 #{after_md5} == #{before_md5}: OK")
      else
        halt("RESTORE FAILED for #{target.file}: #{after_md5} != #{before_md5}")
      end
    end
  end

  # The first `test "literal name"` declaration in the in-scope tree that carries
  # no mark. Literal, because an interpolated name comes from a `for` and would
  # move N units at once; one unit makes the evidence crisp.
  defp first_untagged_test! do
    result =
      Enum.find_value(in_scope_files(), fn file ->
        lines = File.read!(file) |> String.split("\n")

        Enum.find_value(Enum.with_index(lines, 1), fn {text, index} ->
          if Regex.match?(~r/^\s*test\s+"/, text) and not String.contains?(text, "\#{") and
               String.trim(Enum.at(lines, index - 2) || "") != @tag_body do
            indent = Regex.run(~r/^\s*/, text) |> hd()

            %{
              file: file,
              line: index,
              bytes: String.trim(text),
              mutated: Enum.join(List.insert_at(lines, index - 1, indent <> @tag_body), "\n")
            }
          end
        end)
      end)

    result || halt("no untagged test declaration found — cannot demonstrate the stray direction")
  end

  # The first existing mark, removed.
  defp first_tag_line! do
    result =
      Enum.find_value(in_scope_files(), fn file ->
        lines = File.read!(file) |> String.split("\n")

        Enum.find_value(Enum.with_index(lines, 1), fn {text, index} ->
          if String.trim(text) == @tag_body do
            %{
              file: file,
              line: index,
              bytes: String.trim(Enum.at(lines, index) || ""),
              mutated: Enum.join(List.delete_at(lines, index - 1), "\n")
            }
          end
        end)
      end)

    result || halt("no #{@tag_body} line found — cannot demonstrate the missing direction")
  end

  defp in_scope_files, do: "test/mcp/**/*.exs" |> Path.wildcard() |> Enum.sort()

  # --- running --------------------------------------------------------------

  defp run_etcc(args, env \\ %{}) do
    out_path = tmp("etcc_control")
    File.rm_rf!(out_path)
    started = System.os_time(:second)

    {out, status} =
      System.cmd("mix", ["test.etcc", "--rows", out_path] ++ args,
        env: Enum.map(env, fn {k, v} -> {k, v} end),
        stderr_to_stdout: true
      )

    fired!(out, out_path, started)
    artefact = out_path |> File.read!() |> Jason.decode!()
    File.rm_rf!(out_path)
    {out, status, artefact}
  end

  defp capture_test(paths, args) do
    out_path = tmp("etcc_probe")
    File.rm_rf!(out_path)
    started = System.os_time(:second)

    {out, _status} =
      System.cmd("mix", ["test"] ++ paths ++ args,
        env: [{"MIX_ENV", "test"}, {MCP.Conformance.ExUnitRows.env_path_var(), out_path}],
        stderr_to_stdout: true
      )

    fired!(out, out_path, started)
    artefact = out_path |> File.read!() |> Jason.decode!()
    File.rm_rf!(out_path)
    {out, artefact}
  end

  # S7-4. "The instrument never ran" and "the instrument ran and found nothing"
  # are the same silence, so the firing is checked before any figure is believed.
  defp fired!(out, path, started) do
    cond do
      not File.exists?(path) ->
        IO.puts(out)
        halt("CONTROL DID NOT FIRE (not a result): no capture at #{path}")

      File.stat!(path, time: :posix).mtime < started ->
        halt("CONTROL DID NOT FIRE (not a result): #{path} predates this run")

      true ->
        :ok
    end
  end

  # --- shared ---------------------------------------------------------------

  defp register, do: ETCCTags.read_register!()

  defp plan, do: register() |> ETCCTags.plan()

  defp selected_keys(artefact) do
    for row <- artefact["rows"], row["status"] != "excluded", do: row["key"]
  end

  defp members_of(decls), do: decls |> Enum.map(&length(&1.members)) |> Enum.sum()

  defp exunit_says(out) do
    out
    |> String.split("\n")
    |> Enum.find("(no such line)", &String.contains?(&1, "All tests have been excluded"))
    |> String.trim()
  end

  defp last_line(out) do
    out |> String.split("\n", trim: true) |> List.last("(no output)") |> String.trim()
  end

  defp summary_lines(out) do
    out
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["selected", "expected (register)", "missing", "stray"]))
    |> Enum.join("\n")
  end

  defp md5(binary), do: :md5 |> :crypto.hash(binary) |> Base.encode16(case: :lower)

  defp tmp(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}.json")
  end

  # --- tree state — a measurement, not an assurance -------------------------

  defp tree_state do
    {out, 0} = System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true)
    String.trim(out)
  end

  defp tree_check!(before) do
    now = tree_state()

    cond do
      now == before and now == "" ->
        IO.puts("\ntree clean before and after: OK (every mutation was restored)")

      now == before ->
        IO.puts("\ntree unchanged by this run (it was already dirty): OK")

      true ->
        IO.puts("\nTREE CHANGED BY THIS RUN:\n#{now}")
    end
  end

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

ETCCTagsControls.main(System.argv())
