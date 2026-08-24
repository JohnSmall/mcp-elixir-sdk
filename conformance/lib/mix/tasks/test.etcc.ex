defmodule Mix.Tasks.Test.Etcc do
  @shortdoc "Run exactly the ET-CC member set, and refuse anything that is not exactly it"

  @moduledoc """
  Run our conformance claims as a **command** rather than as a document.

      mix test.etcc
      mix test.etcc --seed 42
      mix test.etcc --rows /tmp/etcc-rows.json    # keep the capture

  ## What it selects, and from what

  `--only <tag>` over the marks `mix conformance.etcc_tags` wrote, plus one
  `--only 'test:<name>'` per name-selected member. Both lists are derived from
  `docs/conformance/etcc-register.json` at run time. Nothing here carries a
  hard-coded key, a count, or a file name.

  ## What it refuses, and why a status could never have told you

  **The exit status of a selection run answers the wrong question.** A run that
  selected 1 member of 281 and passed it exits 0 and prints a green summary; so
  does a run that selected all 281. No status can separate them, because both are
  "everything selected passed". What has to be checked is *what was selected* —
  so this task adjudicates the **captured key set** against the register, and
  refuses on any difference in either direction.

  Zero selected is one instance of that comparison rather than a special case,
  and it is named in the message because a run that evaluated nothing is the
  failure most likely to be read as success (S6-10, and HAZARD 4). Worth stating
  plainly: **ExUnit already refuses a totally vacuous `--only` run** — measured at
  this seat, `mix test --only no_such_tag` prints "All tests have been excluded"
  and exits 1. The zero case is not ours to have discovered. What is ours is the
  *partial* case, which ExUnit cannot see and no exit code can express.

  It also refuses a capture it cannot adjudicate at all: a run whose `argv` is not
  the one it launched, an incomplete run, a `--max-failures` cut-off or an
  `--only-test-ids` run. A drift guard fed a one-file capture would otherwise
  report 280 phantom missing marks — a confident wrong answer, which is worse than
  a refusal.

  ## `MCP_ETCC_TAG`, and its one visible consequence

  The knob names the tag to select on (default `:etcc`), so the refusal path can
  be exercised without mutating 265 source lines (E4, PM `26116`). It cannot touch
  the register-side expectation: that comes from `MCP.Conformance.ETCCTags.expected_keys/1`
  and from nothing else.

  When the selected tag is **not** the tag the source carries, the name proxies are
  dropped. A proxy stands in for a tag ExUnit cannot place; standing it in for a
  tag nobody applied would be inventing membership. That is what makes a genuinely
  zero-selecting run reachable end to end.

  ## Exit status

  `0` the selection was exactly the register's member set and every selected test
  passed. `1` refused, or the suite failed. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, ETCCTags, ExUnitRows}

  @switches [seed: :string, rows: :string]
  @usage "mix test.etcc [--seed N] [--rows FILE]"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = Argv.parse!("test.etcc", argv, strict: @switches, usage: @usage)

    register = ETCCTags.read_register!()
    plan = ETCCTags.plan(register)
    refuse_escalations!(plan)
    refuse_name_collisions!(register)

    tag = ETCCTags.selection_tag()
    proxies = proxies(plan, tag)
    args = args(tag, proxies, opts)
    out = opts[:rows] || tmp_path()

    {output, status} = capture(args, out)
    artefact = fired!(output, out, args)
    refuse_partial_capture!(artefact, args)
    unless opts[:rows], do: File.rm_rf!(out)

    selected = for row <- artefact["rows"], row["status"] != "excluded", do: row["key"]
    verdict = ETCCTags.adjudicate(plan.expected_keys, selected)

    report(verdict, artefact, tag, proxies, status, out, opts)
    finish(verdict, status)
  end

  # ---------------------------------------------------------------------------
  # Selection
  # ---------------------------------------------------------------------------

  # The proxies move with the tag. See the moduledoc: a proxy is a stand-in for a
  # tag ExUnit cannot place, so it has nothing to stand in for once the selected
  # tag is not the one the source carries.
  defp proxies(plan, tag) do
    if tag == ETCCTags.default_tag(), do: ETCCTags.name_proxies(plan), else: []
  end

  defp args(tag, proxies, opts) do
    seed = if opts[:seed], do: ["--seed", opts[:seed]], else: []

    ["test", "--only", to_string(tag)] ++
      Enum.flat_map(proxies, &["--only", "test:" <> &1.name]) ++ seed
  end

  defp capture(args, out) do
    File.mkdir_p!(Path.dirname(Path.expand(out)))
    File.rm_rf!(out)

    System.cmd("mix", args,
      env: [{"MIX_ENV", "test"}, {ExUnitRows.env_path_var(), out}],
      stderr_to_stdout: true
    )
  end

  # ---------------------------------------------------------------------------
  # Refusals — before any adjudication, never after
  # ---------------------------------------------------------------------------

  # S7-4: "the instrument did not fire" and "the instrument fired and found
  # nothing" are the same silence. Three conditions, because each fails
  # differently, and none of them is the suite's own status.
  defp fired!(output, path, args) do
    unless String.contains?(output, "[etcc-rows] wrote") do
      Mix.shell().info(output)

      Mix.raise("""
      DID NOT FIRE (not a result): the row formatter never announced a write.
      Launched: mix #{Enum.join(args, " ")}
      Without a capture there is nothing to adjudicate, and the suite's own exit
      status is exactly the thing this task exists not to trust.
      """)
    end

    unless File.exists?(path),
      do: Mix.raise("DID NOT FIRE (not a result): no artefact at #{path}")

    path |> File.read!() |> Jason.decode!()
  end

  defp refuse_partial_capture!(artefact, args) do
    run = artefact["run"]

    cond do
      run["argv"] != args ->
        refuse("""
        the capture is not of the run this task launched.
          launched: #{inspect(args)}
          captured: #{inspect(run["argv"])}
        """)

      run["only_test_ids"] != nil ->
        refuse(
          "the capture is an --only-test-ids run, which selects by id and not by the register"
        )

      run["max_failures"] not in [":infinity", nil] ->
        refuse("the capture was cut off by --max-failures #{run["max_failures"]}")

      run["complete"] != true ->
        refuse(
          "the capture is incomplete: #{run["modules_started"]} modules started, " <>
            "#{run["modules_finished"]} finished"
        )

      run["key_collisions"] != [] ->
        refuse("the capture has key collisions: #{inspect(run["key_collisions"])}")

      true ->
        :ok
    end
  end

  # Always raises — see the note on `refuse_target/4` in
  # `Mix.Tasks.Conformance.EtccTags` for why the spec is here.
  @spec refuse(String.t()) :: no_return()
  defp refuse(why) do
    Mix.raise("""
    REFUSING TO ADJUDICATE — #{why}

    A guard fed a capture it cannot read gives a confident wrong answer: a one-file
    run would be reported as 280 missing marks. A refusal is the correct output
    here, and it is not a verdict about the marks.
    """)
  end

  defp refuse_escalations!(%{escalations: []}), do: :ok

  defp refuse_escalations!(%{escalations: escalations}) do
    Mix.raise(
      "REFUSING: #{length(escalations)} `test` declaration(s) mix members with non-members " <>
        "and so cannot carry a mark (AC5). Run `mix conformance.etcc_tags` for the enumeration."
    )
  end

  defp refuse_name_collisions!(register) do
    case ETCCTags.name_collisions(register) do
      [] ->
        :ok

      collisions ->
        Mix.raise(
          "REFUSING: #{length(collisions)} test name(s) are not unique tree-wide, so a bare " <>
            "`--only 'test:<name>'` filter would over-select. Exactness is a property of this " <>
            "tree, not of the mechanism, which is why it is checked and not assumed."
        )
    end
  end

  # ---------------------------------------------------------------------------
  # Reporting and verdict
  # ---------------------------------------------------------------------------

  defp report(verdict, artefact, tag, proxies, status, out, opts) do
    totals = artefact["totals"]
    run = artefact["run"]

    Mix.shell().info("""

    ET-CC SELECTION — #{ETCCTags.paths().register}

      tag selected on       :#{tag}#{knob_note(tag)}
      name proxies          #{length(proxies)}#{proxy_note(tag, proxies)}
      suite rows captured   #{totals["total"]}
      excluded              #{totals["by_status"]["excluded"]}

      selected              #{verdict.selected}   #{inspect(totals["by_test_type_not_excluded"])}
      expected (register)   #{verdict.expected}
      missing               #{length(verdict.missing)}
      stray                 #{length(verdict.stray)}

      suite exit status     #{status}   passed #{totals["by_status"]["passed"]}, failed #{totals["by_status"]["failed"]}, skipped #{totals["by_status"]["skipped"]}, invalid #{totals["by_status"]["invalid"]}
      run exclude/include   #{inspect(run["exclude"])} / #{inspect(run["include"])}
      capture               #{capture_note(out, opts)}
    """)

    for key <- verdict.missing, do: Mix.shell().info("  MISSING  #{key}")
    for key <- verdict.stray, do: Mix.shell().info("  STRAY    #{key}")
  end

  defp knob_note(tag) do
    if tag == ETCCTags.default_tag(),
      do: "  (#{ETCCTags.tag_env_var()} unset)",
      else: "  (#{ETCCTags.tag_env_var()} set — DIAGNOSTIC RUN)"
  end

  defp proxy_note(tag, _proxies) do
    if tag == ETCCTags.default_tag(),
      do: "",
      else: "  — dropped: a proxy cannot stand in for a tag nobody applied"
  end

  defp capture_note(out, opts) do
    if opts[:rows], do: "kept at #{out}", else: "#{out} (removed)"
  end

  defp finish(verdict, status) do
    unless verdict.ok do
      Mix.raise("ET-CC SELECTION REFUSED — #{verdict.cause}")
    end

    if status != 0 do
      Mix.raise(
        "the selection was exactly the register's #{verdict.expected} member(s), and the " <>
          "suite FAILED (exit #{status}). The set is right; the claims are not all holding."
      )
    end

    Mix.shell().info(
      "  every one of the register's #{verdict.expected} members was selected, and nothing " <>
        "else was. Both directions asserted.\n"
    )
  end

  defp tmp_path do
    Path.join(System.tmp_dir!(), "etcc_selection_#{System.unique_integer([:positive])}.json")
  end
end
