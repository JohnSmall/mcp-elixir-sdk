defmodule MCP.Conformance.Gate8TriggerTest do
  @moduledoc """
  DoD gate 8's trigger command (MES-180), run against real git fixtures.

  The command is not retyped here: it is extracted from the one fenced block in
  `docs/procedure/gate-8.md` that runs `git diff`, and `CLAUDE.md` must carry the same bytes.
  It is then run through `bash` against a throwaway repository with one branch per case.
  **Fires** = non-empty stdout and exit 0; **silent** = empty stdout and exit 1.

  Each case is shown able to fail: a named mutation of the extracted command, held in memory,
  must flip that case's verdict (M1-M8). The retired `lib/`-only grep must be absent from
  every tracked file except the sprint registers (R4), and the absence check is itself shown
  firing on a fixture plant. E1 pins an observed behaviour, not a desired one: an
  unresolvable ref reads as silent (gate-8.md residual 6).
  """

  # Sync (MES-180 Q-A): its ~40 git/bash processes must not starve timing-sensitive async tests.
  use ExUnit.Case, async: false

  @project File.cwd!()
  @page "docs/procedure/gate-8.md"
  @core "CLAUDE.md"
  # Sprint registers are historical records: a later one may quote the retired form (R4).
  @registers ~r{^docs/sprint_\d+_issues\.md$}
  # Assembled from parts so that this file does not carry the literal it forbids.
  @retired "grep -E '" <> "^lib/" <> "'"

  @table "conformance/data/etcc-boundaries.json"
  @guards "conformance/lib/mcp/conformance/boundary_sweep.ex"
  @task "conformance/lib/mix/tasks/conformance.sweep.ex"

  @base [
    "lib/mcp/x.ex",
    @table,
    @guards,
    @task,
    "conformance/data/other.json",
    "conformance/lib/mcp/conformance/etcc_register.ex",
    "conformance/controls/etcc_boundary_sweep_controls.exs",
    "docs/notes.md"
  ]

  # {case, files the branch adds or edits, expected verdict}
  @cases [
    {"F1", ["lib/mcp/x.ex"], :fires},
    {"F2a", [@table], :fires},
    {"F2b", [@guards], :fires},
    {"F2c", [@task], :fires},
    {"U1",
     [
       "conformance/data/other.json",
       "conformance/lib/mcp/conformance/etcc_register.ex",
       "conformance/controls/etcc_boundary_sweep_controls.exs"
     ], :silent},
    {"N1", ["conformance/data/etcc-boundaries.json.bak"], :silent},
    {"N2", ["conformance/lib/mcp/conformance/boundary_sweep.ex.orig"], :silent},
    {"N3", ["conformance/data/etcc-boundariesXjson"], :silent},
    {"N4", ["x/lib/a.ex"], :silent},
    {"N5", ["x/conformance/data/etcc-boundaries.json"], :silent}
  ]

  # F3 (a rename of the table) and B1 (a lib/ change only main made) are built apart.
  @verdicts Map.new(@cases, fn {name, _, want} -> {name, want} end)
            |> Map.merge(%{"F3" => :fires, "B1" => :silent})

  # {mutation, from, to, the cases whose verdict it must flip}
  @mutations [
    {"M1", "'^(lib/|", "'^(", ["F1"]},
    {"M2a", "conformance/data/etcc-boundaries\\.json$|", "", ["F2a"]},
    {"M2b", "conformance/lib/mcp/conformance/boundary_sweep\\.ex$|", "", ["F2b"]},
    {"M2c", "|conformance/lib/mix/tasks/conformance\\.sweep\\.ex$", "", ["F2c"]},
    {"M3", "--no-renames ", "", ["F3"]},
    {"M4", "'^(lib/|", "'^(lib/|conformance/|", ["U1"]},
    {"M5", "$", "", ["N1", "N2"]},
    {"M6", "\\.", ".", ["N3"]},
    {"M7", "'^(", "'(", ["N4", "N5"]},
    {"M8", "main...", "main..", ["B1"]}
  ]

  setup_all do
    root =
      Path.join(
        System.tmp_dir!(),
        "mes180-g8-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{repo: build_fixture(root), command: extract_command!()}
  end

  describe "the command's text" do
    @tag oc: :none
    @tag oc_reason: "procedure text (the gate-8 trigger command); no OC check covers it"
    test "gate-8.md holds exactly one trigger block, and it is three-dot and anchored" do
      command = extract_command!()
      assert command =~ "git diff --no-renames --name-only main...{TICKET_KEY} | grep -E '^("
      assert String.ends_with?(command, "$)'")
    end

    @tag oc: :none
    @tag oc_reason: "procedure text (the gate-8 trigger command); no OC check covers it"
    test "CLAUDE.md carries the identical command, once" do
      core = File.read!(Path.join(@project, @core))
      assert length(String.split(core, "`" <> extract_command!() <> "`")) == 2
    end

    @tag oc: :none
    @tag oc_reason: "procedure text (the gate-8 trigger command); no OC check covers it"
    test "R4: no tracked file outside the sprint registers carries the retired lib/-only grep" do
      assert retired_hits(@project, nil) == []
    end

    @tag oc: :none
    @tag oc_reason: "procedure text (the gate-8 trigger command); no OC check covers it"
    test "R4 can fire: a planted copy is reported, the same copy in a sprint register is not",
         %{repo: repo} do
      assert retired_hits(repo, "R4") == ["docs/notes.md"]
    end
  end

  describe "the verdict on each fixture" do
    for {name, want} <- @verdicts do
      @tag oc: :none
      @tag oc_reason: "procedure text (the gate-8 trigger command); no OC check covers it"
      test "#{name} #{want}", %{repo: repo, command: command} do
        assert {unquote(want), _} = verdict(repo, command, unquote(name))
      end
    end

    @tag oc: :none
    @tag oc_reason: "procedure text (the gate-8 trigger command); no OC check covers it"
    test "E1 (observed, residual 6): an unresolvable ref reads as silent",
         %{repo: repo, command: command} do
      assert {:silent, stderr} = verdict(repo, command, "NO-SUCH-BRANCH")
      assert stderr =~ "fatal:"
    end
  end

  describe "each case can fail: a mutation of the extracted command flips it" do
    for {m, from, to, flips} <- @mutations do
      @tag oc: :none
      @tag oc_reason: "procedure text (the gate-8 trigger command); no OC check covers it"
      test "#{m} flips #{Enum.join(flips, ", ")}", %{repo: repo, command: command} do
        mutated = String.replace(command, unquote(from), unquote(to))
        assert mutated != command

        for name <- unquote(flips) do
          {got, _} = verdict(repo, mutated, name)
          assert got == flip(Map.fetch!(@verdicts, name)), "#{unquote(m)} left #{name} at #{got}"
        end
      end
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

  defp retired_hits(dir, rev) do
    args = ["grep", "-l", "-F", "-e", @retired] ++ List.wrap(rev)

    case System.cmd("git", args, cd: dir, env: git_env()) do
      {_, 1} ->
        []

      {out, 0} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.map(&String.replace_prefix(&1, "#{rev}:", ""))
        |> Enum.reject(&(&1 =~ @registers))
    end
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

    branch!(repo, "F3", fn -> git!(repo, ["mv", @table, "conformance/data/moved.json"]) end)
    branch!(repo, "B1", fn -> write!(repo, "docs/notes.md", "B1\n") end)

    branch!(repo, "R4", fn ->
      write!(repo, "docs/notes.md", "#{@retired}\n")
      write!(repo, "docs/sprint_15_issues.md", "#{@retired}\n")
    end)

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
