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
#     mix run conformance/controls/etcc_tags_controls.exs source_strays
#     mix run conformance/controls/etcc_tags_controls.exs source_strays_mutation
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
# ## MES-166 — `source_strays`, and its mutation mode
#
# Everything above reads the tags ExUnit reports. `source_strays` is the SOURCE
# side: the real `mix conformance.etcc_tags --check`, over a throwaway copy of the
# tree with one file planted per case — a mark inside a literal is not counted,
# a real mark is. `source_strays_mutation` recompiles the reader in memory with
# each direction broken and requires exactly the named cases to go red.
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
        ["source_strays"] -> source_strays()
        ["source_strays_mutation"] -> source_strays_mutation()
        ["all"] -> all()
        _ -> usage()
      end
    after
      tree_check!(before)
    end
  end

  defp usage do
    IO.puts(
      "usage: mix run #{__ENV__.file} " <>
        "derive|doctest_options|diff|select|mutate|vacuous|source_strays|source_strays_mutation|all"
    )
  end

  defp all do
    derive()
    doctest_options()
    diff_control()
    select()
    mutate()
    vacuous()
    source_strays()
    source_strays_mutation()
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

  # --- MES-166: the SOURCE check's stray direction, both ways ----------------
  #
  # `mix conformance.etcc_tags --check` read marks off lines, so a test that
  # builds a test module in a heredoc was reported as carrying a stray mark. The
  # reader now walks the AST. These cases drive the REAL task, in-process, over a
  # throwaway copy of `test/` and the register — the real tree is never written —
  # with one file planted per case. Each case is judged on the PLANTED file's
  # strays, so a mutation reddens exactly the cases it should and no others.

  @plant "test/mes166_plant_test.exs"
  @reader_source "conformance/lib/mcp/conformance/etcc_tags.ex"

  # The one expression every mutation replaces. Required to occur exactly once:
  # a refactor that moves it makes the mutation mode refuse, not pass unmutated.
  @reader_anchor "{:ok, ast} -> {:ok, ast |> marks_in() |> Enum.sort()}"

  # M1 — the pre-MES-166 line scan (`classify_mark/2` at 0fcdbbc), put back.
  @line_scan ~S'''
  {:ok, _ast} ->
        marks =
          for {text, i} <- source |> String.split("\n") |> Enum.with_index(1),
              kind =
                (cond do
                   String.trim(text) == "@tag :etcc" -> :tag
                   Regex.match?(~r/^\s*doctest\s/, text) and String.contains?(text, "tags: [:etcc]") -> :directive
                   true -> nil
                 end),
              kind != nil,
              do: {i, kind}

        {:ok, marks}
  '''

  # M2 — a reader that sees nothing at all.
  @blind "{:ok, _ast} -> {:ok, []}"

  # M5 — the reader crashes on the planted file once it has parsed it (MES-166
  # correction round 2, B1). Every case whose plant parses must go red: a crash is
  # never a pass. F1 and F2 do not parse, so they never reach the raise.
  @raise_on_plant ~S"""
  {:ok, ast} ->
        if String.ends_with?(file, "mes166_plant_test.exs"),
          do: raise("M5: the reader cannot read the plant"),
          else: {:ok, ast |> marks_in() |> Enum.sort()}
  """

  # M3 — the UTF-8 rescue removed (MES-166 F2): a non-UTF-8 file then crashes
  # the check with an exception that names no file, instead of being refused.
  @utf8_rescue "  rescue\n    e in UnicodeConversionError -> {:error, {:encoding, Exception.message(e)}}\n"

  @mutations [
    {"M1", "the line scan restored", @reader_anchor, @line_scan, ~w(P0 L1 L2 L3 R3)},
    {"M2", "the reader returns no marks", @reader_anchor, @blind, ~w(R1 R2 R3)},
    {"M3", "the UTF-8 rescue removed", @utf8_rescue, "", ~w(F2)},
    {"M5", "the reader raises on a planted file it can parse", @reader_anchor, @raise_on_plant,
     ~w(L1 L2 L3 R1 R2 R3)}
  ]

  defp stray_cases do
    [
      %{id: "P0", what: "nothing planted — the copy of the real tree", plant: nil, want: :clean},
      %{
        id: "L1",
        what: "the tag inside an ~S heredoc (the MES-160 fixture shape)",
        plant: ~S"""
        defmodule MES166.PlantTest do
          use ExUnit.Case

          test "builds a module" do
            src = ~S'''
            @tag :etcc
            test "x", do: :ok
            '''

            assert src
          end
        end
        """,
        want: {:plant, []}
      },
      %{
        id: "L2",
        what: "the tag inside a plain heredoc string",
        plant: ~S'''
        defmodule MES166.PlantTest do
          use ExUnit.Case

          test "builds a module" do
            src = """
            @tag :etcc
            test "x", do: :ok
            """

            assert src
          end
        end
        ''',
        want: {:plant, []}
      },
      %{
        id: "L3",
        what: "a doctest directive inside a heredoc",
        plant: ~S"""
        defmodule MES166.PlantTest do
          use ExUnit.Case

          @fixture ~S'''
          doctest MES166.Nothing, tags: [:etcc]
          '''

          test "reads the fixture", do: assert(@fixture)
        end
        """,
        want: {:plant, []}
      },
      %{
        id: "R1",
        what: "a real tag above an untagged test",
        plant: ~S"""
        defmodule MES166.PlantTest do
          use ExUnit.Case

          @tag :etcc
          test "planted", do: :ok
        end
        """,
        want: {:plant, [{4, "tag"}]}
      },
      %{
        id: "R2",
        what: "a real doctest directive carrying the tag",
        plant: ~S"""
        defmodule MES166.PlantTest do
          use ExUnit.Case
          doctest MES166.Nothing, tags: [:etcc]
        end
        """,
        want: {:plant, [{3, "directive"}]}
      },
      %{
        id: "R3",
        what: "a literal AND a real tag in one file — only the real one",
        plant: ~S"""
        defmodule MES166.PlantTest do
          use ExUnit.Case

          test "builds a module" do
            src = ~S'''
            @tag :etcc
            test "x", do: :ok
            '''

            assert src
          end

          @tag :etcc
          test "planted", do: :ok
        end
        """,
        want: {:plant, [{13, "tag"}]}
      },
      %{
        id: "F1",
        what: "a test file that does not parse",
        plant: ~S"""
        defmodule MES166.PlantTest do
          @tag :etcc
          test "planted", do: :ok
        """,
        want: {:parse_refused, "missing terminator"}
      },
      %{
        id: "F2",
        what: "a test file that is not UTF-8 (MES-166 F2)",
        plant: "defmodule MES166.PlantTest do\n  @tag :etcc\n  @a \"" <> <<0xFF>> <> "\"\nend\n",
        want: {:parse_refused, "not valid UTF-8"}
      }
    ]
  end

  defp source_strays do
    section("SOURCE STRAYS (MES-166) — the real --check, a literal is not a mark, a real mark is")
    preflight_plants!()
    reds = with_stray_root(&run_stray_cases/1)

    if reds == [],
      do: IO.puts("\nevery case as expected, both directions: OK"),
      else: halt("SOURCE STRAYS: #{Enum.join(reds, ", ")} did not behave as expected")
  end

  defp source_strays_mutation do
    section("SOURCE STRAYS MUTATION (MES-166) — each direction shown able to go red")
    preflight_plants!()
    original = File.read!(@reader_source)
    before_md5 = md5(original)

    for {id, _what, anchor, _replacement, _want_red} <- @mutations do
      case length(String.split(original, anchor)) - 1 do
        1 ->
          :ok

        n ->
          halt(
            "#{id}: its anchor occurs #{n} times in #{@reader_source}, not once — no mutation made"
          )
      end
    end

    with_stray_root(fn root ->
      for {id, what, anchor, replacement, want_red} <- @mutations do
        IO.puts("\n--- #{id}: #{what}  (compiled in memory; no file is written)")
        compile_reader!(String.replace(original, anchor, replacement))
        red = run_stray_cases(root)

        if Enum.sort(red) == Enum.sort(want_red),
          do:
            IO.puts("    red: #{Enum.join(red, " ")} — exactly the cases #{id} must redden: OK"),
          else: halt("#{id}: red #{inspect(red)}, expected exactly #{inspect(want_red)}")
      end

      IO.puts("\n--- restored: the reader as committed, recompiled in memory")
      compile_reader!(original)
      red = run_stray_cases(root)
      if red != [], do: halt("restored reader: #{inspect(red)} red")
    end)

    after_md5 = md5(File.read!(@reader_source))

    if after_md5 == before_md5,
      do: IO.puts("\n#{@reader_source} md5 #{after_md5} == #{before_md5}: never written: OK"),
      else: halt("#{@reader_source} CHANGED during the mutation run")
  end

  # Every planted line a case expects is checked to BE a mark-shaped line before
  # any case runs, so an expectation cannot silently point at the wrong line.
  defp preflight_plants! do
    for %{id: id, plant: plant, want: {:plant, expected}} <- stray_cases(),
        {line, _kind} <- expected do
      text = plant |> String.split("\n") |> Enum.at(line - 1, "") |> String.trim()

      unless text == @tag_body or String.starts_with?(text, "doctest "),
        do: halt("#{id}: line #{line} of the plant is #{inspect(text)}, not a mark")
    end
  end

  defp with_stray_root(fun) do
    root = Path.join(System.tmp_dir!(), "mes166_strays_#{System.unique_integer([:positive])}")
    register = ETCCTags.paths().register

    try do
      File.mkdir_p!(Path.join(root, Path.dirname(register)))
      File.cp_r!("test", Path.join(root, "test"))
      File.cp!(register, Path.join(root, register))
      fun.(root)
    after
      File.rm_rf!(root)
    end
  end

  # Returns the ids of the cases that did NOT behave as expected.
  defp run_stray_cases(root) do
    IO.puts(
      pad("case", 6) <> pad("check", 10) <> pad("strays", 8) <> pad("planted", 22) <> "verdict"
    )

    for c <- stray_cases(), reduce: [] do
      reds ->
        plant_path = Path.join(root, @plant)
        if c.plant, do: File.write!(plant_path, c.plant)
        {outcome, out} = check_in(root)
        File.rm_rf!(plant_path)

        {ok?, planted, total} = verdict(c.want, outcome, out)

        check =
          case outcome do
            :ok -> "OK"
            {:refused, _} -> "REFUSED"
            {:crashed, _} -> "CRASHED"
          end

        IO.puts(
          pad(c.id, 6) <>
            pad(check, 10) <>
            pad(total, 8) <>
            pad(inspect(planted), 22) <> if(ok?, do: "as expected", else: "NOT as expected")
        )

        IO.puts("      #{c.what}")
        if ok?, do: reds, else: reds ++ [c.id]
    end
  end

  # The one place every case is judged through. A run has exactly three outcomes
  # (check_in/1): :ok, {:refused, message} and {:crashed, reason}. No case wants a
  # crash, so a crash is never as expected — decided HERE, once, and not left to
  # each clause, because a clause that reads "not refused" as "OK" passes a crash
  # (MES-166 correction round 2, B1). Each clause below then requires its intended
  # outcome positively; none is satisfied by the absence of another.
  defp verdict(_want, {:crashed, _reason}, out), do: {false, planted_strays(out), "-"}
  defp verdict(want, outcome, out), do: judge(want, outcome, out)

  # P0: the check ran, reported, and found nothing.
  defp judge(:clean, outcome, out) do
    total = total_strays(out)
    {outcome == :ok and total == 0, [], total}
  end

  # L: the check ran and passed, and the planted file contributed no stray.
  defp judge({:plant, []}, outcome, out) do
    planted = planted_strays(out)
    {outcome == :ok and planted == [], planted, total_strays(out)}
  end

  # R: refused FOR DISAGREEING — not for any other reason — at exactly the planted
  # lines.
  defp judge({:plant, expected}, outcome, out) do
    planted = planted_strays(out)

    ok? =
      match?({:refused, _}, outcome) and
        String.contains?(elem(outcome, 1), "source and register disagree") and
        planted == expected

    {ok?, planted, total_strays(out)}
  end

  # F: refused, by name, for the stated reason.
  defp judge({:parse_refused, why}, outcome, _out) do
    ok? =
      match?({:refused, _}, outcome) and String.contains?(elem(outcome, 1), @plant) and
        String.contains?(elem(outcome, 1), "does not parse") and
        String.contains?(elem(outcome, 1), why)

    {ok?, [], "-"}
  end

  # The real task, in-process, with its shell captured. S7-4: a run that printed
  # no report and raised nothing did not fire, and is not read as a result.
  defp check_in(root) do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    outcome =
      try do
        File.cd!(root, fn -> Mix.Task.rerun("conformance.etcc_tags", ["--check"]) end)
        :ok
      rescue
        e in Mix.Error -> {:refused, Exception.message(e)}
        # Any other exception is recorded, not propagated: it is a case that did not
        # behave, and the control must go on to report the rest (M3 needs this).
        e -> {:crashed, Exception.message(e)}
      catch
        # A throw or an exit is a crash too, so the outcome set is closed at three.
        kind, reason -> {:crashed, "#{kind}: #{inspect(reason)}"}
      after
        Mix.shell(previous)
      end

    out = drain_shell([])

    if outcome == :ok and not String.contains?(out, "ETCC TAG CHECK"),
      do: halt("CONTROL DID NOT FIRE (not a result): --check printed no report")

    {outcome, out}
  end

  defp drain_shell(acc) do
    receive do
      {:mix_shell, _kind, [line]} -> drain_shell([line | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp planted_strays(out) do
    for [kind, line] <-
          Regex.scan(~r/STRAY\s+(tag|directive)\s+#{Regex.escape(@plant)}:(\d+)/, out,
            capture: :all_but_first
          ),
        do: {String.to_integer(line), kind}
  end

  defp total_strays(out) do
    case Regex.run(~r/stray marks\s+(\d+)/, out, capture: :all_but_first) do
      [n] -> String.to_integer(n)
      nil -> "-"
    end
  end

  defp compile_reader!(source) do
    {_modules, diagnostics} =
      Code.with_diagnostics(fn ->
        Code.compiler_options(ignore_module_conflict: true)
        Code.compile_string(source, @reader_source)
      end)

    errors = Enum.filter(diagnostics, &(&1.severity == :error))
    if errors != [], do: halt("the mutated reader did not compile: #{inspect(errors)}")
    # A mutation leaves the AST helpers unused, so warnings there are expected.
    IO.puts("    compiled in memory, #{length(diagnostics)} compiler warning(s)")
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
