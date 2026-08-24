defmodule Mix.Tasks.Conformance.EtccTags do
  @shortdoc "Apply (or check) the :etcc source marks derived from B2a's register"

  @moduledoc """
  Write the `:etcc` source marks that `mix test.etcc` selects on, **derived from
  `docs/conformance/etcc-register.json` and from nothing else**.

      mix conformance.etcc_tags            # apply
      mix conformance.etcc_tags --check    # verify source against the register

  ## Why this is a generator and not 265 hand-edits

  A hand-applied tag is a second record of membership maintained beside the
  register, and the two drift the first time anyone adds a test. `--check` is the
  source half of the drift guard: it fails when the marks and the register stop
  agreeing, **in both directions** — a member whose mark is missing, and a mark on
  something the register does not call a member.

  It is deliberately not the whole guard. `--check` reads *source text*; the
  runtime guard (`conformance/controls/etcc_tags_controls.exs`) reads the tags
  **ExUnit itself reports**, which is the only side that can catch a mark that is
  present in the file and does not reach the test. Both, because they fail
  differently.

  ## What it refuses to do

  A `test` declaration mixing members with non-members has no available mark — a
  `@tag` reaches every unit the declaration generates (S6-6) and there is nothing
  smaller. This task **refuses the whole run** rather than picking a direction to
  be wrong in: over-tagging claims coverage we do not have, under-tagging drops a
  real claim, and choosing silently is how a register and a suite start
  disagreeing. `MCP.Conformance.ETCCTags.plan/1` reports those as `:escalations`;
  the tree has none, and the refusal is what makes that a measured statement
  rather than an assumption.

  It also refuses when two rows share a test name, because the 2 name-selected
  members (see `MCP.Conformance.ETCCTags`) are selected by name alone.

  ## The address shift this causes, and where it is repaired

  Inserting a line above a test moves every address below it in that file. This
  run therefore invalidates `line` fields and authored `file:line` citations in
  the conformance artefacts — E2, ruled option (ii) at MES-84 `26116`: re-capture
  and rebuild the artefacts, and mechanically re-address the authored citations,
  as the ticket's last commit. Row **keys** are unaffected, because a key carries
  module and name and never a line — which is what makes the repair mechanical.

  ## Exit status

  `0` applied, or checked clean. `1` refused, or checked dirty. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, ETCCTags}

  @switches [check: :boolean]
  @usage "mix conformance.etcc_tags [--check]"

  # A `test` declaration, as the register addresses it. `test(` is admitted
  # because the parenthesised call form is legal and would otherwise be silently
  # skipped as "not a test".
  @test_decl ~r/^\s*test[\s(]/
  @doctest_decl ~r/^\s*doctest\s/

  @impl Mix.Task
  def run(argv) do
    {opts, _} = Argv.parse!("conformance.etcc_tags", argv, strict: @switches, usage: @usage)

    register = ETCCTags.read_register!()
    plan = ETCCTags.plan(register)

    refuse_escalations!(plan)
    refuse_name_collisions!(register)

    if opts[:check], do: check(plan), else: apply_marks(plan)
  end

  # ---------------------------------------------------------------------------
  # Apply
  # ---------------------------------------------------------------------------

  defp apply_marks(plan) do
    results =
      plan
      |> edits()
      |> Enum.group_by(& &1.file)
      |> Enum.sort()
      |> Enum.map(fn {file, file_edits} -> apply_file(file, file_edits) end)

    report_apply(results, plan)
  end

  # Descending line order, so an insertion never moves a point this pass has not
  # reached yet. The alternative — tracking a running offset — is the same
  # arithmetic with somewhere to be wrong.
  defp apply_file(file, file_edits) do
    lines = file |> File.read!() |> String.split("\n")

    {lines, outcomes} =
      file_edits
      |> Enum.sort_by(& &1.line, :desc)
      |> Enum.reduce({lines, []}, fn edit, {lines, outcomes} ->
        {lines, outcome} = apply_edit(file, lines, edit)
        {lines, [outcome | outcomes]}
      end)

    File.write!(file, Enum.join(lines, "\n"))
    %{file: file, outcomes: outcomes}
  end

  defp apply_edit(file, lines, %{kind: :tag, line: line}) do
    target = at!(file, lines, line)

    cond do
      already_tagged?(lines, line) ->
        {lines, :present}

      not Regex.match?(@test_decl, target) ->
        refuse_target(file, line, target, "a `test` declaration")

      true ->
        {List.insert_at(lines, line - 1, indent(target) <> ETCCTags.tag_line_body()), :inserted}
    end
  end

  defp apply_edit(file, lines, %{kind: :directive, line: line}) do
    target = at!(file, lines, line)

    cond do
      String.contains?(target, "tags: [:#{ETCCTags.default_tag()}]") ->
        {lines, :present}

      not Regex.match?(@doctest_decl, target) ->
        refuse_target(file, line, target, "a `doctest` directive")

      true ->
        {List.replace_at(lines, line - 1, directive_with_tags(target)), :inserted}
    end
  end

  # `doctest Mod` becomes `doctest Mod, tags: [:etcc]`. The module is read off the
  # SOURCE line rather than derived from the register's module name, because the
  # register names the *test* module and the directive names the module under
  # test — they are never the same atom.
  defp directive_with_tags(target) do
    String.trim_trailing(target) <> ", tags: [:#{ETCCTags.default_tag()}]"
  end

  # ---------------------------------------------------------------------------
  # Check — both directions
  # ---------------------------------------------------------------------------

  defp check(plan) do
    by_state =
      plan
      |> edits()
      |> Enum.group_by(&state(&1, read_lines(&1.file)))

    report_check(plan, by_state, strays(edits(plan)))
  end

  # Three states, not two, because "the mark is absent" and "the register cannot
  # address this tree" want opposite corrections and would otherwise print
  # identically. A register built BEFORE the marks were applied names the line the
  # `@tag` now occupies, so every point reads unmarked — 266 MISSINGs whose real
  # cause is one stale artefact (E2). `:stale` says that in one word.
  defp state(%{kind: :tag, line: line}, lines) do
    cond do
      already_tagged?(lines, line) -> :marked
      Regex.match?(@test_decl, at(lines, line)) -> :missing
      true -> :stale
    end
  end

  defp state(%{kind: :directive, line: line}, lines) do
    target = at(lines, line)

    cond do
      String.contains?(target, "tags: [:#{ETCCTags.default_tag()}]") -> :marked
      Regex.match?(@doctest_decl, target) -> :missing
      true -> :stale
    end
  end

  # The other direction: every `@tag :etcc` in the tree must sit immediately above
  # a declaration the register calls wholly-member. A mark the register does not
  # account for is a stray, and a check that only looked for missing marks would
  # pass with any number of them.
  defp strays(expected) do
    wanted = MapSet.new(expected, &{&1.file, &1.line, &1.kind})
    body = ETCCTags.tag_line_body()

    for file <- test_files(),
        {text, index} <- file |> read_lines() |> Enum.with_index(1),
        stray = classify_mark(text, body),
        stray != nil,
        not MapSet.member?(wanted, {file, marked_line(index, stray), stray}),
        do: %{file: file, line: index, kind: stray, text: String.trim(text)}
  end

  defp classify_mark(text, body) do
    cond do
      String.trim(text) == body -> :tag
      Regex.match?(@doctest_decl, text) and String.contains?(text, "tags: [:etcc]") -> :directive
      true -> nil
    end
  end

  # A `@tag` line marks the declaration BELOW it; a directive marks itself.
  defp marked_line(index, :tag), do: index + 1
  defp marked_line(index, :directive), do: index

  defp test_files do
    "test/**/*.exs" |> Path.wildcard() |> Enum.sort()
  end

  # ---------------------------------------------------------------------------
  # The edit list — the one place the plan becomes source addresses
  # ---------------------------------------------------------------------------

  defp edits(plan) do
    tags = Enum.map(plan.tag_points, &%{kind: :tag, file: &1.file, line: &1.line, decl: &1})

    directives =
      Enum.map(
        plan.directive_points,
        &%{kind: :directive, file: &1.file, line: &1.line, decl: &1}
      )

    Enum.sort_by(tags ++ directives, &{&1.file, &1.line})
  end

  # ---------------------------------------------------------------------------
  # Refusals
  # ---------------------------------------------------------------------------

  defp refuse_escalations!(%{escalations: []}), do: :ok

  defp refuse_escalations!(%{escalations: escalations}) do
    listing =
      Enum.map_join(escalations, "\n  ", fn d ->
        "#{d.file}:#{d.line} — #{length(d.units)} units, #{length(d.members)} of them members"
      end)

    Mix.raise("""
    REFUSING: #{length(escalations)} `test` declaration(s) mix members with non-members.

      #{listing}

    A `@tag` reaches every unit a declaration generates, so tagging these would
    over-tag and not tagging them would drop a real claim. Neither is this task's
    to choose (MES-84 AC5): escalate, and the remedy — a refactor, or a ruling —
    is the PM's.
    """)
  end

  defp refuse_name_collisions!(register) do
    case ETCCTags.name_collisions(register) do
      [] ->
        :ok

      collisions ->
        listing = Enum.map_join(collisions, "\n  ", &"#{&1.rows} rows share the name: #{&1.name}")

        Mix.raise("""
        REFUSING: #{length(collisions)} test name(s) are not unique tree-wide.

          #{listing}

        The name-selected members are chosen by a bare `--only 'test:<name>'`
        filter, which matches across every module. Exactness there is a property
        of this tree, not a guarantee of the mechanism — so a collision goes red
        here instead of silently widening the selection.
        """)
    end
  end

  # Always raises. The spec is what tells dialyzer so; without it the function
  # is reported `no_return`, which is true and is not a defect.
  @spec refuse_target(String.t(), pos_integer(), String.t(), String.t()) :: no_return()
  defp refuse_target(file, line, target, wanted) do
    Mix.raise("""
    REFUSING at #{file}:#{line} — the register addresses this line, but it is not #{wanted}:

      #{inspect(target)}

    The most likely cause is that the register's line fields are stale relative to
    the tree: a previous run of this task shifted every address below each
    insertion (E2), so re-running against a register built BEFORE that run points
    into the wrong place. Rebuild the register from a fresh capture and re-run.
    """)
  end

  # ---------------------------------------------------------------------------
  # Reporting
  # ---------------------------------------------------------------------------

  defp report_apply(results, plan) do
    counted = results |> Enum.flat_map(& &1.outcomes) |> Enum.frequencies()

    for %{file: file, outcomes: outcomes} <- results do
      f = Enum.frequencies(outcomes)

      Mix.shell().info(
        "  #{pad(file, 62)} inserted #{g(f, :inserted)}  present #{g(f, :present)}"
      )
    end

    Mix.shell().info("""

    ETCC TAGS APPLIED — derived from #{ETCCTags.paths().register}

      members                 #{plan.expected_count}
      by :tag                 #{count_members(plan.tag_points)} over #{length(plan.tag_points)} declaration(s)
      by :directive           #{count_members(plan.directive_points)} over #{length(plan.directive_points)} declaration(s)
      by exact name           #{count_members(plan.name_points)} — NOT marked in source (E1, S7-33)

      lines inserted/rewritten #{g(counted, :inserted)}
      already present          #{g(counted, :present)}

    Every insertion moves the addresses below it. The artefacts are re-synced as
    this ticket's last commit (E2 option ii); row keys are unaffected.
    """)
  end

  defp report_check(plan, by_state, strays) do
    marked = Map.get(by_state, :marked, [])
    missing = Map.get(by_state, :missing, [])
    stale = Map.get(by_state, :stale, [])
    total = length(marked) + length(missing) + length(stale)

    Mix.shell().info("""

    ETCC TAG CHECK — source against #{ETCCTags.paths().register}

      declarations to mark    #{total}
      marked                  #{length(marked)}
      NOT marked              #{length(missing)}
      register STALE here     #{length(stale)}  (line addresses a non-declaration)
      stray marks             #{length(strays)}

      not source-marked by design: #{count_members(plan.name_points)} name-selected member(s) (E1, S7-33)
    """)

    for e <- missing, do: Mix.shell().info("  MISSING  #{e.kind}  #{e.file}:#{e.line}")
    for e <- stale, do: Mix.shell().info("  STALE    #{e.kind}  #{e.file}:#{e.line}")
    for s <- strays, do: Mix.shell().info("  STRAY    #{s.kind}  #{s.file}:#{s.line}  #{s.text}")

    if missing == [] and stale == [] and strays == [] do
      Mix.shell().info("\n  source and register agree, both directions: OK")
    else
      Mix.raise(
        "source and register disagree: #{length(missing)} missing, #{length(stale)} stale, " <>
          "#{length(strays)} stray. Both directions are checked because either alone passes " <>
          "over the other's failure; STALE is neither, and means the register cannot address " <>
          "this tree at all — rebuild it from a fresh capture before reading the other two."
      )
    end
  end

  defp count_members(decls), do: decls |> Enum.map(&length(&1.members)) |> Enum.sum()

  defp g(freqs, key), do: Map.get(freqs, key, 0)

  defp pad(s, n), do: String.pad_trailing(to_string(s), n)

  # ---------------------------------------------------------------------------
  # Source helpers
  # ---------------------------------------------------------------------------

  defp read_lines(file), do: file |> File.read!() |> String.split("\n")

  defp at!(file, lines, line) do
    Enum.at(lines, line - 1) ||
      Mix.raise("#{file} has no line #{line} — the register addresses a line that is not there.")
  end

  # `--check` reports a line past the end of the file as STALE rather than
  # raising: a check is meant to enumerate every disagreement it finds, and
  # stopping at the first one would hide the rest.
  defp at(lines, line), do: Enum.at(lines, line - 1) || ""

  defp already_tagged?(lines, line) do
    line > 1 and String.trim(Enum.at(lines, line - 2) || "") == ETCCTags.tag_line_body()
  end

  defp indent(text) do
    case Regex.run(~r/^\s*/, text) do
      [ws] -> ws
      _ -> ""
    end
  end
end
