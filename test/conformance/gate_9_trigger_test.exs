defmodule MCP.Conformance.Gate9TriggerTest do
  @moduledoc """
  DoD gate 9's trigger command (MES-241), run against real git fixtures. The same idiom as
  `Gate8TriggerTest`.

  The command is not retyped here: it is extracted from the one fenced block in
  `docs/procedure/gate-9.md` that runs `git diff`, and `CLAUDE.md` must carry the same bytes.
  It is then run through `bash` against a throwaway repository with one branch per case.
  **Fires** = non-empty stdout and exit 0; **silent** = empty stdout and exit 1.

  Every alternation of the regex has a firing case, and each case is shown able to fail: a
  named mutation of the extracted command, held in memory, must flip it (M1-M13). The silent
  cases are paths that cannot move the register (U1) and near-misses of trigger paths (N1-N9).
  `mix.exs`, `config/` and `test/support/` were added in correction round 1 (F8-F10, M14-M16).

  The premise the trigger's `lib/` alternation rests on (every module doctested from
  `test/mcp/` is defined under `lib/`) is not checked here. Gate 9's refusal guard RT5
  (`MCP.Conformance.RegisterDrift.rt5_doctests/1`) checks the doctested modules' names and
  suite-end compile sources against `lib/`; it does not establish the premise in full
  (gate-9.md residual 8, MES-248).
  """

  # Sync, as Gate8TriggerTest: its git/bash processes must not starve timing-sensitive tests.
  use ExUnit.Case, async: false

  @project File.cwd!()
  @page "docs/procedure/gate-9.md"
  @core "CLAUDE.md"

  @lib "conformance/lib/mcp/conformance/"
  @modules ~w(etcc_register unit_locator exunit_rows boundary_sweep rows_drift register_drift)

  # {case, files the branch adds or edits, expected verdict}
  @cases [
           {"F1", ["lib/mcp/x.ex"], :fires},
           {"F2", ["test/mcp/x_test.exs"], :fires},
           {"F3", ["test/test_helper.exs"], :fires},
           {"F4a", ["docs/conformance/etcc-register.json"], :fires},
           {"F4b", ["docs/conformance/etcc-exunit-rows.json"], :fires},
           {"F5a", ["conformance/data/etcc-decisions.json"], :fires},
           {"F5b", ["conformance/data/etcc-boundaries.json"], :fires},
           {"F7", ["conformance/lib/mix/tasks/conformance.register_drift.ex"], :fires},
           {"F8", ["mix.exs"], :fires},
           {"F9", ["config/config.exs"], :fires},
           {"F10", ["test/support/x.ex"], :fires},
           {"U1",
            [
              "test/conformance/a_test.exs",
              "mix.lock",
              ".formatter.exs",
              "test/fixtures/x.json",
              "conformance/request_state.ex",
              "docs/procedure/gate-9.md",
              "docs/conformance/etcc-register.md",
              "conformance/controls/register_drift_controls.exs",
              "conformance/lib/mcp/conformance/other.ex",
              "conformance/lib/mix/tasks/conformance.rows_drift.ex"
            ], :silent},
           {"N1", ["test/test_helper.exs.bak"], :silent},
           {"N2", ["docs/conformance/etcc-register.json.bak"], :silent},
           {"N3", ["docs/conformance/etcc-registerXjson"], :silent},
           {"N4", ["x/lib/a.ex"], :silent},
           {"N5", ["x/test/mcp/a_test.exs"], :silent},
           {"N6", ["conformance/lib/mcp/conformance/etcc_register.ex.orig"], :silent},
           {"N7", ["mix.exs.bak"], :silent},
           {"N8", ["x/mix.exs"], :silent},
           {"N9", ["mixXexs"], :silent}
         ] ++
           for(m <- @modules, do: {"F6-" <> m, [@lib <> m <> ".ex"], :fires})

  @base Enum.flat_map(@cases, &elem(&1, 1)) ++ ["docs/notes.md"]

  # FR (a rename out of test/mcp/) and B1 (a lib/ change only main made) are built apart.
  @verdicts Map.new(@cases, fn {name, _, want} -> {name, want} end)
            |> Map.merge(%{"FR" => :fires, "B1" => :silent})

  @f6 for m <- @modules, do: "F6-" <> m

  # {mutation, from, to, the cases whose verdict it must flip}
  @mutations [
    {"M1", "|lib/|", "|", ["F1"]},
    {"M2", "test/mcp/|", "", ["F2"]},
    {"M3", "test/test_helper\\.exs$|", "", ["F3"]},
    {"M4", "docs/conformance/etcc-(register|exunit-rows)\\.json$|", "", ["F4a", "F4b"]},
    {"M5", "conformance/data/etcc-(decisions|boundaries)\\.json$|", "", ["F5a", "F5b"]},
    {"M6",
     "conformance/lib/mcp/conformance/(etcc_register|unit_locator|exunit_rows|boundary_sweep|rows_drift|register_drift)\\.ex$|",
     "", @f6},
    {"M7", "|conformance/lib/mix/tasks/conformance\\.register_drift\\.ex$", "", ["F7"]},
    {"M8", "--no-renames ", "", ["FR"]},
    {"M9", "$", "", ["N1", "N2", "N6", "N7"]},
    {"M10", "\\.", ".", ["N3", "N9"]},
    {"M11", "'^(", "'(", ["N4", "N5", "N8"]},
    {"M12", "main...", "main..", ["B1"]},
    {"M13", "|lib/|", "|lib/|test/|docs/|conformance/|mix\\.lock$|\\.formatter|", ["U1"]},
    {"M14", "'^(mix\\.exs$|", "'^(", ["F8"]},
    {"M15", "config/|", "", ["F9"]},
    {"M16", "test/support/|", "", ["F10"]}
  ]

  setup_all do
    root =
      Path.join(
        System.tmp_dir!(),
        "mes241-g9-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{repo: build_fixture(root), command: extract_command!()}
  end

  describe "the command's text" do
    @tag oc: :none
    @tag oc_reason: "procedure text (the gate-9 trigger command); no OC check covers it"
    test "gate-9.md holds exactly one trigger block, and it is three-dot, no-renames and anchored" do
      command = extract_command!()
      assert command =~ "git diff --no-renames --name-only main...{TICKET_KEY} | grep -E '^("
      assert String.ends_with?(command, "$)'")
    end

    @tag oc: :none
    @tag oc_reason: "procedure text (the gate-9 trigger command); no OC check covers it"
    test "CLAUDE.md carries the identical command, once" do
      core = File.read!(Path.join(@project, @core))
      assert length(String.split(core, "`" <> extract_command!() <> "`")) == 2
    end
  end

  describe "the verdict on each fixture" do
    for {name, want} <- @verdicts do
      @tag oc: :none
      @tag oc_reason: "procedure text (the gate-9 trigger command); no OC check covers it"
      test "#{name} #{want}", %{repo: repo, command: command} do
        assert {unquote(want), _} = verdict(repo, command, unquote(name))
      end
    end
  end

  describe "each case can fail: a mutation of the extracted command flips it" do
    for {m, from, to, flips} <- @mutations do
      @tag oc: :none
      @tag oc_reason: "procedure text (the gate-9 trigger command); no OC check covers it"
      test "#{m} flips #{Enum.join(flips, ", ")}", %{repo: repo, command: command} do
        mutated = String.replace(command, unquote(from), unquote(to))
        assert mutated != command

        for name <- unquote(flips) do
          {got, _} = verdict(repo, mutated, name)
          assert got == flip(Map.fetch!(@verdicts, name)), "#{unquote(m)} left #{name} at #{got}"
        end
      end
    end

    @tag oc: :none
    @tag oc_reason: "procedure text (the gate-9 trigger command); no OC check covers it"
    test "every firing case is flipped by some mutation" do
      fires = for {n, :fires} <- @verdicts, do: n
      flipped = @mutations |> Enum.flat_map(&elem(&1, 3)) |> MapSet.new()
      assert Enum.reject(fires, &MapSet.member?(flipped, &1)) == []
    end
  end

  defp flip(:fires), do: :silent
  defp flip(:silent), do: :fires

  defp extract_command! do
    blocks =
      ~r/```bash\n(.*?)\n```/s
      |> Regex.scan(File.read!(Path.join(@project, @page)), capture: :all_but_first)
      |> List.flatten()
      |> Enum.filter(&String.starts_with?(&1, "git diff"))

    case blocks do
      [command] -> command
      other -> flunk("expected one git-diff bash block in #{@page}, found #{length(other)}")
    end
  end

  defp verdict(repo, command, key) do
    assert_contained!(repo)
    err = Path.join(Path.dirname(repo), "stderr-#{System.unique_integer([:positive])}")
    script = "{ " <> String.replace(command, "{TICKET_KEY}", key) <> " ; } 2>" <> err
    {out, code} = System.cmd("bash", ["-c", script], cd: repo, env: git_env())
    stderr = File.read!(err)
    File.rm!(err)

    case {out, code} do
      {"", 1} -> {:silent, stderr}
      {out, 0} when out != "" -> {:fires, stderr}
      other -> flunk("neither verdict for #{key}: #{inspect(other)} #{stderr}")
    end
  end

  # The command must run in the fixture, never in this repository.
  defp assert_contained!(repo) do
    {top, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"], cd: repo, env: git_env())
    {real, 0} = System.cmd("pwd", ["-P"], cd: repo)
    assert String.trim(top) == String.trim(real)
    refute String.starts_with?(String.trim(top), @project)
  end

  defp build_fixture(root) do
    repo = Path.join(root, "repo")
    File.mkdir_p!(repo)
    git!(repo, ["init", "-q", "-b", "main"])
    Enum.each(@base, &write!(repo, &1, "base\n"))
    commit!(repo, "base")

    for {name, files, _} <- @cases do
      branch!(repo, name, fn -> Enum.each(files, &write!(repo, &1, "#{name}\n")) end)
    end

    # FR: a test/mcp/ file renamed out of test/mcp/. Without --no-renames only the new
    # path is listed, and it is not a trigger path.
    branch!(repo, "FR", fn ->
      git!(repo, ["mv", "test/mcp/x_test.exs", "test/conformance/moved_test.exs"])
    end)

    branch!(repo, "B1", fn -> write!(repo, "docs/notes.md", "B1\n") end)

    # main moves on after every fork: only a two-dot diff would charge B1 with this.
    git!(repo, ["checkout", "-q", "main"])
    write!(repo, "lib/mcp/x.ex", "main moved\n")
    commit!(repo, "main moves")
    repo
  end

  defp branch!(repo, name, edit) do
    git!(repo, ["checkout", "-q", "-b", name, "main"])
    edit.()
    commit!(repo, name)
  end

  defp write!(repo, path, body) do
    full = Path.join(repo, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, body)
  end

  defp commit!(repo, message) do
    git!(repo, ["add", "-A"])
    git!(repo, ["commit", "-q", "-m", message])
  end

  defp git!(repo, args) do
    config = ["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"]

    {out, code} =
      System.cmd("git", config ++ args, cd: repo, env: git_env(), stderr_to_stdout: true)

    assert code == 0, "git #{Enum.join(args, " ")}: #{out}"
    out
  end

  # A fixture identity, and no inherited repository pointers.
  defp git_env do
    [
      {"GIT_AUTHOR_NAME", "fixture"},
      {"GIT_AUTHOR_EMAIL", "fixture@invalid"},
      {"GIT_COMMITTER_NAME", "fixture"},
      {"GIT_COMMITTER_EMAIL", "fixture@invalid"},
      {"GIT_DIR", nil},
      {"GIT_WORK_TREE", nil},
      {"GIT_INDEX_FILE", nil}
    ]
  end
end
