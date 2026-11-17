# Controls for `mix conformance.rows_drift` (MES-240).
#
#     mix run conformance/controls/rows_drift_controls.exs plants
#     mix run conformance/controls/rows_drift_controls.exs guards
#     mix run conformance/controls/rows_drift_controls.exs neverwrite
#     mix run conformance/controls/rows_drift_controls.exs mutation
#     mix run conformance/controls/rows_drift_controls.exs all
#
# THE FIXTURE. Every case plants a change in a copy of `conformance/controls/rows_drift_fixture.json`,
# never in live `main`. That file holds 7 rows lifted verbatim from
# `docs/conformance/etcc-exunit-rows.json` at dec37c2 (file md5 a4b1a4547e69ddb1adbe3291244700e5,
# rows_md5 7d4a2d36b67723c4c7107adf7747dd9d, MES-230's capture). The rows chosen are the first
# doctest row, the first test/mcp row that has both a describe and tags, the first test/mcp row
# that has neither, and the first five rows of that second row's file. The run block is copied
# unchanged, except that rows_md5 is recomputed over the 7 rows (9c756d4ab916c2b5eadce3247b6f486b).
# The rows were built with `ExUnitRows.artefact/2` and written with `ExUnitRows.encode/1`, the
# same path a capture takes.
#
# plants     — the REAL task, run as a subprocess (`mix conformance.rows_drift --committed
#              FIXTURE --fresh PLANTED --json OUT`). P0 is the fixture against itself: exit 0
#              CLEAN, the no-drift control. P1-P8 each plant one change: added, renamed (removed
#              + added), moved, relined (delimit), refielded, restatus, removed, and moved WITH a
#              new line (F3: both moved and relined). Each must exit 1 and report EXACTLY its own
#              class counts and nothing else.
# guards     — the real task again, one plant per refusal guard RD1-RD9 on the FRESH side and
#              one per guard on the COMMITTED side (RDnc), plus RD7's suite_rc limb (fresh only:
#              only a live capture carries suite_rc) and RD9's cross-check limb. Each must exit 2,
#              print `REFUSED - <its guard>` and report its own guard ALONE, on the planted side
#              ALONE: no plant may be entailed by, or entail, another guard or the other side.
# neverwrite — F1, the real task in a DECOY directory under the system tmp dir, never the real
#              committed file. decoy/committed.json is the protected file (--committed);
#              decoy/alias is a symlink to decoy/; decoy/hard.json is a hard link to it. Each
#              output path naming the protected file (literally, through the parent symlink,
#              through the hard link, and via --keep through the symlink) must exit 64 and leave
#              the protected bytes unchanged. NW0, an unrelated --json path, must be written
#              (exit 0), so the guard is shown refusing selectively. NW5/NW6 plant the link DURING
#              the capture (a decoy `mix`, used only for capture's child). NW7/NW8 are `..` after
#              a symlink, both directions. NW9/NW10/WB3 (R2-1, no race): an output that is a
#              symlink to an UNRELATED file must succeed with the link REPLACED by a regular file
#              holding the output, its target and the protected file byte-unchanged. That case
#              is what tells the rename apart from a direct write, deterministically.
# mutation   — compiled copies of `MCP.Conformance.RowsDrift`, each with ONE change. Whole-function
#              stubs (M1 diff empty, M3 all refusals off, each class, each guard), one-SIDE
#              bypasses (each guard skipped on the committed side only, then on the fresh side
#              only: F2), the F3 regression (relined restricted to same-file keys again) and the
#              F1 regression (same_file?/2 lexical only), and the R1/R2 write mutants: write
#              boundary removed (M-R1-1), re-check removed with the rename kept (M-R1-1r), and
#              the rename removed with the re-check kept (M-R1-1w, killed by WB3). Each mutant must turn red the cases it
#              names, and the unmutated module must satisfy those cases first (the control on the
#              control). A mutant whose target text is gone raises CANNOT MUTATE rather than
#              passing. Scope: each mutant is checked against its NAMED cases only.
#
# WHY A SCRIPT AND NOT AN ExUnit TEST: a test would join the very population the rows file
# records, and would drift that file just by existing. This is the same reasoning as
# `etcc_register_controls.exs`.

defmodule RowsDriftControls do
  alias MCP.Conformance.{ExUnitRows, RowsDrift}

  @fixture "conformance/controls/rows_drift_fixture.json"
  @source "conformance/lib/mcp/conformance/rows_drift.ex"
  @modes ~w(plants guards neverwrite mutation)

  # {guard, the call `refusals/2` makes for it}. The side mutants rewrite exactly that call.
  @guard_calls [
    {"RD1", "rd1_schema(artefact)"},
    {"RD2", "rd2_md5(artefact)"},
    {"RD3", "rd3_incomplete(artefact)"},
    {"RD4", "rd4_partial(artefact)"},
    {"RD5", "rd5_host(artefact)"},
    {"RD6", "rd6_dirty(artefact)"},
    {"RD7", "rd7_red(artefact)"},
    {"RD8", "rd8_collisions(artefact)"},
    {"RD9", "rd9_consistency(artefact)"}
  ]

  def run(["plants"]), do: verdict(plants())
  def run(["guards"]), do: verdict(guards())
  def run(["neverwrite"]), do: verdict(neverwrite())
  def run(["mutation"]), do: verdict(mutation())
  def run(["all"]), do: all()

  def run(_) do
    IO.puts("usage: plants | guards | neverwrite | mutation | all")
    System.halt(2)
  end

  # --- all: each mode in its own VM, one verdict per mode ---------------------------

  defp all do
    header("ALL — #{Enum.join(@modes, ", ")}")
    mix = System.find_executable("mix") || raise "mix is not on PATH"

    results =
      for mode <- @modes do
        {_, status} =
          System.cmd(mix, ["run", __ENV__.file, mode],
            into: IO.stream(:stdio, :line),
            stderr_to_stdout: true
          )

        {mode, status}
      end

    IO.puts("\n== ALL — verdicts ==\n")

    for {mode, status} <- results,
        do: IO.puts("  #{if status == 0, do: "ok  ", else: "FAIL"}  #{mode}  (exit #{status})")

    failed = Enum.count(results, fn {_, st} -> st != 0 end)
    IO.puts("\n  #{length(results) - failed}/#{length(results)} modes green.")
    if failed > 0, do: System.halt(1)
  end

  # --- the cases ---------------------------------------------------------------------

  # {id, what, committed, fresh, want}. want is {:clean} | {:drift, %{class => n}} |
  # {:refused, guard, side}. A drift want lists every non-zero class; every other must be 0.
  defp plant_cases do
    fx = fixture()
    [r0, r1 | _] = fx["rows"]
    tagged = Enum.find(fx["rows"], &(&1["tags"] != %{}))

    [
      {"P0", "the fixture against itself (no-drift control)", fx, fx, {:clean}},
      {"P1", "a planted add", fx,
       add_row(fx, %{
         r1
         | "key" => r1["module"] <> "/test planted by MES-240",
           "name" => "test planted by MES-240",
           "line" => 9999
       }), {:drift, %{"added" => 1}}},
      {"P2", "a planted rename", fx,
       update_row(fx, r1["key"], fn r ->
         %{r | "key" => r["key"] <> " renamed", "name" => r["name"] <> " renamed"}
       end), {:drift, %{"added" => 1, "removed" => 1}}},
      {"P3", "a planted move (other file, same line)", fx,
       update_row(fx, r0["key"], &%{&1 | "file" => "test/mcp/planted_move_test.exs"}),
       {:drift, %{"moved" => 1}}},
      {"P4", "a planted delimit change (line + 3)", fx,
       update_row(fx, r1["key"], &%{&1 | "line" => &1["line"] + 3}), {:drift, %{"relined" => 1}}},
      {"P5", "a planted tag change", fx,
       update_row(fx, tagged["key"], &%{&1 | "tags" => Map.put(&1["tags"], "planted", "yes")}),
       {:drift, %{"refielded" => 1}}},
      {"P6", "a planted status change (passed -> skipped)", fx,
       update_row(fx, r1["key"], &%{&1 | "status" => "skipped", "reason" => "due to @tag :skip"}),
       {:drift, %{"restatus" => 1}}},
      {"P7", "a planted removal", fx, drop_row(fx, r1["key"]), {:drift, %{"removed" => 1}}},
      {"P8", "a planted move WITH a line change (+10)", fx,
       update_row(
         fx,
         r1["key"],
         &%{&1 | "file" => "test/mcp/planted_move_test.exs", "line" => &1["line"] + 10}
       ), {:drift, %{"moved" => 1, "relined" => 1}}}
    ]
  end

  # One plant per guard, as a function of the artefact, so the same plant is used on both sides.
  defp guard_plants do
    fx = fixture()
    [_, r1 | _] = fx["rows"]

    unsealed = fn a ->
      %{a | "rows" => Enum.map(a["rows"], &if(&1 == r1, do: %{&1 | "line" => 1}, else: &1))}
    end

    [
      {"RD1", "schema etcc-exunit-rows/0", &%{&1 | "schema" => "etcc-exunit-rows/0"}},
      {"RD2", "a row edited without resealing rows_md5", unsealed},
      {"RD3", "complete false", &put_run(&1, "complete", false)},
      {"RD4", "argv names one file",
       &put_run(&1, "argv", ["test", "test/mcp/client_conformance_test.exs", "--seed", "0"])},
      {"RD5", "exclude [:requires_live_harness], argv whole",
       &put_run(&1, "exclude", [":requires_live_harness"])},
      {"RD6", "tree_clean false, one dirty path",
       &(&1 |> put_run("tree_clean", false) |> put_run("tree_dirty", ["lib/planted.ex"]))},
      {"RD7", "one row failed",
       &update_row(&1, r1["key"], fn r ->
         %{r | "status" => "failed", "failure" => ["planted"]}
       end)},
      {"RD8", "one row duplicated, rows_md5 resealed", &add_row(&1, r1)},
      {"RD9", "a row whose module is not its key's, rows_md5 resealed",
       &update_row(&1, r1["key"], fn r -> %{r | "module" => "MCP.PlantedOtherModule"} end)}
    ]
  end

  defp guard_cases do
    fx = fixture()

    fresh =
      for {g, what, plant} <- guard_plants(),
          do: {g, "fresh: " <> what, fx, plant.(fx), {:refused, g, "fresh"}}

    committed =
      for {g, what, plant} <- guard_plants(),
          do: {g <> "c", "committed: " <> what, plant.(fx), fx, {:refused, g, "committed"}}

    disagreement = %{
      fx["run"]["module_cross_check"]
      | "disagreements" => [%{"module" => "MCP.Planted", "planted" => true}]
    }

    fresh ++
      committed ++
      [
        {"RD7rc", "fresh: every row passed, but the suite exited 2", fx,
         put_run(fx, "suite_rc", 2), {:refused, "RD7", "fresh"}},
        {"RD9x", "fresh: a planted module_cross_check disagreement", fx,
         put_run(fx, "module_cross_check", disagreement), {:refused, "RD9", "fresh"}}
      ]
  end

  # --- plants and guards: the real task ------------------------------------------------

  defp plants do
    header("PLANTS — the real task, each plant reporting exactly its own class")
    Enum.map(plant_cases(), &through_task/1)
  end

  defp guards do
    header("GUARDS — the real task, each plant refused by its own guard, on its own side, alone")
    Enum.map(guard_cases(), &through_task/1) ++ [guard_list(RowsDrift)]
  end

  # R1-3: the advertised guard set (`RowsDrift.guards/0`) must be exactly the set the plants
  # exercise. A guard added without a plant, or dropped from the list, goes red here.
  defp guard_list(module) do
    exercised = guard_plants() |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    advertised = Enum.sort(module.guards())

    check(
      "GL",
      "advertised guards #{inspect(advertised)} == exercised #{inspect(exercised)}",
      advertised == exercised
    )
  end

  defp through_task({id, what, committed, fresh, want}) do
    dir = scratch_dir("rows_drift_controls")
    c = Path.join(dir, "committed.json")
    f = Path.join(dir, "fresh.json")
    j = Path.join(dir, "report.json")
    File.write!(c, ExUnitRows.encode(committed))
    File.write!(f, ExUnitRows.encode(fresh))

    {out, status} =
      System.cmd(
        "mix",
        ["conformance.rows_drift", "--committed", c, "--fresh", f, "--json", j],
        stderr_to_stdout: true
      )

    report = j |> File.read!() |> Jason.decode!()
    last = out |> String.trim_trailing() |> String.split("\n") |> List.last()
    File.rm_rf!(dir)

    ok =
      status == want_exit(want) and satisfied?(report, want) and
        String.contains?(last, want_banner(want))

    check(id, "#{what} -> exit #{status}; #{summary(report)}\n        #{last}", ok)
  end

  defp want_exit({:clean}), do: 0
  defp want_exit({:drift, _}), do: 1
  defp want_exit({:refused, _, _}), do: 2

  defp want_banner({:clean}), do: "rows-drift: CLEAN"
  defp want_banner({:drift, _}), do: "rows-drift: DRIFT"
  defp want_banner({:refused, g, _}), do: "rows-drift: REFUSED - #{g} ("

  defp satisfied?(report, {:clean}), do: report["verdict"] == "clean" and counts(report) == %{}

  defp satisfied?(report, {:drift, want}),
    do: report["verdict"] == "drift" and counts(report) == want

  defp satisfied?(report, {:refused, g, side}),
    do: report["verdict"] == "refused" and fired(report) == [{g, side}]

  defp counts(report) do
    for c <- RowsDrift.classes(), n = length(report[c] || []), n > 0, into: %{}, do: {c, n}
  end

  defp fired(report),
    do: report["refusals"] |> Enum.map(&{&1["guard"], &1["side"]}) |> Enum.uniq()

  defp summary(%{"verdict" => "refused"} = r), do: "refused by #{inspect(fired(r))}"
  defp summary(r), do: "#{r["verdict"]} #{inspect(counts(r))}"

  # --- neverwrite: F1, on decoys only ---------------------------------------------------

  defp neverwrite do
    header("NEVERWRITE — no output path may name the protected file, by any route (decoys only)")
    {dir, protected, alias_dir, hard} = decoy()
    before = File.read!(protected)
    fx = Path.expand(@fixture)
    via_alias = Path.join(alias_dir, "committed.json")
    other = Path.join(dir, "other-report.json")

    cases = [
      {"NW1", "--json names the protected file literally", ["--fresh", fx, "--json", protected],
       64},
      {"NW2", "--json reaches it through a parent-directory symlink",
       ["--fresh", fx, "--json", via_alias], 64},
      {"NW3", "--json reaches it through a hard link", ["--fresh", fx, "--json", hard], 64},
      {"NW4", "--keep reaches it through a parent-directory symlink (refused before capture)",
       ["--keep", via_alias], 64},
      {"NW0", "--json names an unrelated path (must be written)",
       ["--fresh", fx, "--json", other], 0}
    ]

    results =
      for {id, what, args, want} <- cases do
        {out, status} =
          System.cmd("mix", ["conformance.rows_drift", "--committed", protected | args],
            stderr_to_stdout: true
          )

        intact = File.read!(protected) == before
        wrote_other = id != "NW0" or File.exists?(other)
        last = out |> String.trim_trailing() |> String.split("\n") |> List.last()

        check(
          id,
          "#{what} -> exit #{status}; protected bytes unchanged: #{intact}\n        #{last}",
          status == want and intact and wrote_other
        )
      end

    File.rm_rf!(dir)
    results ++ post_capture_links() ++ dotdot() ++ unrelated_links()
  end

  # NW5/NW6 (R1-1): the output path does not exist when the task starts, so the first check
  # passes. A DECOY `mix`, first on the task's PATH and used only for capture's child, copies
  # the fixture to MCP_ETCC_ROWS and then plants the output path as a symlink to the protected
  # file. The write must still be refused (64), with the protected bytes unchanged.
  defp post_capture_links do
    for {id, flag} <- [{"NW5", "--json"}, {"NW6", "--keep"}] do
      {dir, protected, _alias, _hard} = decoy()
      before = File.read!(protected)
      out = Path.join(dir, "output.json")
      bin = decoy_mix(dir)
      real_mix = System.find_executable("mix") || raise "mix is not on PATH"

      {text, status} =
        System.cmd(real_mix, ["conformance.rows_drift", "--committed", protected, flag, out],
          stderr_to_stdout: true,
          env: [
            {"PATH", bin <> ":" <> System.get_env("PATH", "")},
            {"RD_DECOY_FIXTURE", Path.expand(@fixture)},
            {"RD_DECOY_TARGET", protected},
            {"RD_DECOY_LINK", out}
          ]
        )

      planted = match?({:ok, _}, :file.read_link(out))
      intact = File.read!(protected) == before
      File.rm_rf!(dir)
      last = text |> String.trim_trailing() |> String.split("\n") |> List.last()

      check(
        id,
        "#{flag} planted as a link to the protected file DURING the capture -> exit #{status}; " <>
          "link planted: #{planted}; protected bytes unchanged: #{intact}\n        #{last}",
        status == 64 and planted and intact
      )
    end
  end

  # A decoy `mix` for capture's child only: copies the fixture to MCP_ETCC_ROWS and, when
  # RD_DECOY_LINK is set, plants it as a symlink to RD_DECOY_TARGET. Returns its directory.
  defp decoy_mix(dir) do
    bin = Path.join(dir, "decoy-bin")
    File.mkdir_p!(bin)
    fake = Path.join(bin, "mix")

    File.write!(fake, """
    #!/bin/sh
    cp "$RD_DECOY_FIXTURE" "$MCP_ETCC_ROWS"
    if [ -n "$RD_DECOY_LINK" ]; then ln -s "$RD_DECOY_TARGET" "$RD_DECOY_LINK"; fi
    exit 0
    """)

    File.chmod!(fake, 0o755)
    bin
  end

  # NW9/NW10 (R2-1), no race: the output path ALREADY is a symlink to an UNRELATED decoy
  # file, and a separate decoy is protected. Nothing is refused, so the run succeeds; the
  # write must REPLACE the link with a regular file holding the output (the report for
  # --json, the capture for --keep), leaving the link's target and the protected file
  # byte-unchanged. A direct write would follow the link and change the target. WB3 is the
  # same case at helper level, on `write_output!/3`.
  defp unrelated_links do
    fx = Path.expand(@fixture)

    task_cases =
      for {id, flag} <- [{"NW9", "--json"}, {"NW10", "--keep"}] do
        {dir, protected, _alias, _hard} = decoy()
        before = File.read!(protected)
        target = Path.join(dir, "unrelated.json")
        File.write!(target, "UNRELATED-TARGET")
        out = Path.join(dir, "output.json")
        :ok = File.ln_s(target, out)
        bin = decoy_mix(dir)
        real_mix = System.find_executable("mix") || raise "mix is not on PATH"

        args =
          if flag == "--json",
            do: ["--fresh", fx, "--json", out],
            else: ["--keep", out]

        {text, status} =
          System.cmd(real_mix, ["conformance.rows_drift", "--committed", protected | args],
            stderr_to_stdout: true,
            env: [
              {"PATH", bin <> ":" <> System.get_env("PATH", "")},
              {"RD_DECOY_FIXTURE", fx},
              {"RD_DECOY_LINK", ""}
            ]
          )

        regular = match?({:ok, %File.Stat{type: :regular}}, File.lstat(out))
        body = if regular, do: File.read!(out), else: ""

        holds =
          if flag == "--json",
            do: match?({:ok, %{"schema" => "etcc-rows-drift/1"}}, Jason.decode(body)),
            else: body == File.read!(fx)

        target_intact = File.read!(target) == "UNRELATED-TARGET"
        intact = File.read!(protected) == before
        File.rm_rf!(dir)
        last = text |> String.trim_trailing() |> String.split("\n") |> List.last()

        check(
          id,
          "#{flag} is a symlink to an unrelated file -> exit #{status}; output now a regular " <>
            "file: #{regular}; holds the #{if flag == "--json", do: "report", else: "capture"}: " <>
            "#{holds}; link target unchanged: #{target_intact}; protected unchanged: #{intact}" <>
            "\n        #{last}",
          status == 0 and regular and holds and target_intact and intact
        )
      end

    {ok, detail} = unrelated_link_write(RowsDrift)

    task_cases ++
      [check("WB3", "write_output!/3 through a link to an unrelated file: " <> detail, ok)]
  end

  # Helper-level R2-1: returns {satisfied, detail}.
  defp unrelated_link_write(module) do
    {dir, protected, _alias, _hard} = decoy()
    before = File.read!(protected)
    target = Path.join(dir, "unrelated.json")
    File.write!(target, "UNRELATED-TARGET")
    out = Path.join(dir, "output.json")
    :ok = File.ln_s(target, out)

    result =
      try do
        module.write_output!(out, "REPORT", [protected])
      rescue
        e -> {:raised, Exception.message(e)}
      end

    regular = match?({:ok, %File.Stat{type: :regular}}, File.lstat(out))
    holds = regular and File.read!(out) == "REPORT"
    target_intact = File.read!(target) == "UNRELATED-TARGET"
    intact = File.read!(protected) == before
    File.rm_rf!(dir)

    {result == :ok and regular and holds and target_intact and intact,
     "result #{inspect(result)}; output regular file: #{regular}; holds REPORT: #{holds}; " <>
       "link target unchanged: #{target_intact}; protected unchanged: #{intact}"}
  end

  # NW7/NW8 (R1-2): a/link -> b/sub, so the kernel resolves a/link/../committed.json to
  # b/committed.json. (a) With b/committed.json protected and NOT yet existing, --json through
  # that path must be refused 64 and must not create it. (b) With a/committed.json protected
  # and a distinct b/committed.json existing, the same path must NOT be refused: it is written,
  # and the protected file is unchanged.
  defp dotdot do
    fx = Path.expand(@fixture)

    a_case =
      with_dotdot(fn %{via: via, b_committed: b, a_committed: _} ->
        {text, status} =
          System.cmd(
            "mix",
            ["conformance.rows_drift", "--committed", b, "--fresh", fx, "--json", via],
            stderr_to_stdout: true
          )

        created = File.exists?(b)
        last = text |> String.trim_trailing() |> String.split("\n") |> List.last()

        check(
          "NW7",
          "--json a/link/../committed.json with b/committed.json protected and absent -> " <>
            "exit #{status}; b/committed.json created: #{created}\n        #{last}",
          status == 64 and not created
        )
      end)

    b_case =
      with_dotdot(fn %{via: via, b_committed: b, a_committed: a} ->
        File.cp!(@fixture, a)
        File.write!(b, "DISTINCT-B")
        before = File.read!(a)

        {text, status} =
          System.cmd(
            "mix",
            ["conformance.rows_drift", "--committed", a, "--fresh", fx, "--json", via],
            stderr_to_stdout: true
          )

        intact = File.read!(a) == before
        written = File.read!(b) != "DISTINCT-B"
        last = text |> String.trim_trailing() |> String.split("\n") |> List.last()

        check(
          "NW8",
          "--json a/link/../committed.json with a/committed.json protected, distinct b exists -> " <>
            "exit #{status}; b written: #{written}; a unchanged: #{intact}\n        #{last}",
          status == 0 and written and intact
        )
      end)

    [a_case, b_case]
  end

  defp with_dotdot(fun) do
    dir = scratch_dir("rows_drift_dotdot")
    a = Path.join(dir, "a")
    b = Path.join(dir, "b")
    File.mkdir_p!(a)
    File.mkdir_p!(Path.join(b, "sub"))
    :ok = File.ln_s(Path.join(b, "sub"), Path.join(a, "link"))

    paths = %{
      dir: dir,
      via: Path.join([a, "link", "..", "committed.json"]),
      a_committed: Path.join(a, "committed.json"),
      b_committed: Path.join(b, "committed.json")
    }

    try do
      fun.(paths)
    after
      File.rm_rf!(dir)
    end
  end

  # decoy/committed.json (the protected file: the fixture's bytes), decoy/alias -> decoy,
  # decoy/hard.json hard-linked to the protected file.
  defp decoy do
    dir = scratch_dir("rows_drift_decoy")
    protected = Path.join(dir, "committed.json")
    File.cp!(@fixture, protected)
    alias_dir = Path.join(dir, "alias")
    :ok = File.ln_s(dir, alias_dir)
    hard = Path.join(dir, "hard.json")
    :ok = File.ln(protected, hard)
    {dir, protected, alias_dir, hard}
  end

  # --- mutation -------------------------------------------------------------------------

  defp mutants do
    stubs = [
      {"M1", "diff/2 returns no drift at all", "def diff(committed, fresh) do",
       ~s|def diff(_, _), do: Map.new(~w(added removed moved relined refielded restatus rename_candidates), &{&1, []})|,
       ~w(P1 P2 P3 P4 P5 P6 P7 P8)},
      {"M3", "every refusal stubbed", "def refusals(side, artefact) do",
       "def refusals(_, _), do: []", Enum.map(guard_cases(), &elem(&1, 0))},
      {"M-added", "added/2 stubbed", "def added(c, f)", "def added(_, _), do: []", ~w(P1 P2)},
      {"M-removed", "removed/2 stubbed", "def removed(c, f)", "def removed(_, _), do: []",
       ~w(P2 P7)},
      {"M-moved", "moved/3 stubbed", "def moved(c, f, shared) do", "def moved(_, _, _), do: []",
       ~w(P3 P8)},
      {"M-relined", "relined/3 stubbed", "def relined(c, f, shared) do",
       "def relined(_, _, _), do: []", ~w(P4 P8)},
      {"M-refielded", "refielded/3 stubbed", "def refielded(c, f, shared) do",
       "def refielded(_, _, _), do: []", ~w(P5)},
      {"M-restatus", "restatus/3 stubbed", "def restatus(c, f, shared) do",
       "def restatus(_, _, _), do: []", ~w(P6)}
    ]

    guard_stubs =
      for {g, call} <- @guard_calls do
        [fun, _] = String.split(call, "(")
        reds = [g, g <> "c"] ++ extra_reds(g)

        # rd1_schema/1 has three clauses; its first clause's head is unique.
        head =
          if g == "RD1", do: ~s|def rd1_schema(%{"schema" => @rows_schema|, else: "def #{fun}("

        {"M-#{g}", "#{g} stubbed", head, "def #{fun}(_), do: nil", reds}
      end

    side_bypasses =
      for {g, call} <- @guard_calls, {skip, keep, reds} <- side_reds(g) do
        {"M-#{g}-#{skip}", "#{g} skipped on the #{skip} side only", call,
         ~s|if(side == "#{keep}", do: #{call})|, reds}
      end

    regressions = [
      {"M-F3", "relined restricted to same-file keys again (the pre-F3 condition)",
       ~s|for k <- shared,\n        c[k]["line"] != f[k]["line"],|,
       ~s|for k <- shared,\n        c[k]["file"] == f[k]["file"],\n        c[k]["line"] != f[k]["line"],|,
       ~w(P8)},
      {"M-R1-1", "the write-boundary protection removed (outputs written directly)",
       "  def write_output!(out, bytes, protected) do",
       "  def write_output!(out, bytes, _protected), do: File.write!(out, bytes)\n" <>
         "  def write_output!(out, bytes, protected) do", ~w(WB1 WB2)},
      {"M-R1-1w", "the rename removed, the write-boundary re-check kept (R2-1)",
       "  defp atomic_write!(out, bytes) do",
       "  defp atomic_write!(out, bytes), do: File.write!(out, bytes)\n" <>
         "  defp atomic_write!(out, bytes) do", ~w(WB3)},
      {"M-R1-1r", "the write-boundary re-check removed, the rename kept",
       "  def write_output!(out, bytes, protected) do",
       "  def write_output!(out, bytes, _protected), do: atomic_write!(out, bytes)\n" <>
         "  def write_output!(out, bytes, protected) do", ~w(WB1 WB2)},
      {"M-R1-2", "real_path/1 collapses `..` lexically first again (the pre-R1-2 resolution)",
       "  defp absolute_parts(path) do",
       "  defp absolute_parts(path), do: tl(Path.split(Path.expand(path)))\n" <>
         "  defp absolute_parts(path) do", ~w(RPa RPb)},
      {"M-R1-3", "RD9 dropped from the advertised guard list",
       "@guards ~w(RD1 RD2 RD3 RD4 RD5 RD6 RD7 RD8 RD9)",
       "@guards ~w(RD1 RD2 RD3 RD4 RD5 RD6 RD7 RD8)", ~w(GL)},
      {"M-F1", "same_file?/2 lexical only (the pre-F1 comparison)", "  def same_file?(a, b) do",
       "  def same_file?(a, b), do: Path.expand(a) == Path.expand(b)\n  def same_file?(a, b) do",
       ~w(NW2 NW3)}
    ]

    Enum.map(stubs ++ guard_stubs, fn {id, what, head, stub, reds} ->
      {id, what, "  " <> head, "  " <> stub <> "\n  " <> head, reds}
    end) ++ side_bypasses ++ regressions
  end

  defp extra_reds("RD7"), do: ["RD7rc"]
  defp extra_reds("RD9"), do: ["RD9x"]
  defp extra_reds(_), do: []

  # {side skipped, side kept, cases that must go red}
  defp side_reds(g),
    do: [{"committed", "fresh", [g <> "c"]}, {"fresh", "committed", [g] ++ extra_reds(g)}]

  defp mutation do
    header("MUTATION — each one-change mutant turns red exactly the cases it names")

    {dir, protected, alias_dir, hard} = decoy()

    nw = %{
      "NW2" => {:same_file, Path.join(alias_dir, "committed.json"), protected},
      "NW3" => {:same_file, hard, protected}
    }

    cases =
      Map.new(plant_cases() ++ guard_cases(), fn {id, _, c, f, w} -> {id, {c, f, w}} end)
      |> Map.merge(nw)
      |> Map.merge(%{
        "WB1" => {:write_boundary, :final_link},
        "WB2" => {:write_boundary, :parent_link},
        "WB3" => :unrelated_link,
        "RPa" => {:dotdot, :a},
        "RPb" => {:dotdot, :b},
        "GL" => :guard_list
      })

    source = File.read!(@source)

    results =
      Enum.map(mutants(), fn {mid, what, from, to, reds} ->
        control = Enum.all?(reds, &satisfied_by?(RowsDrift, cases[&1]))
        mutant = compile_mutant(source, mid, from, to)
        flipped = for id <- reds, do: {id, not satisfied_by?(mutant, cases[id])}

        check(
          mid,
          "#{what}: unmutated satisfies #{Enum.join(reds, ",")} = #{control}; " <>
            "mutant turns red #{inspect(for {id, true} <- flipped, do: id)}",
          control and Enum.all?(flipped, &elem(&1, 1))
        )
      end)

    File.rm_rf!(dir)
    results
  end

  defp satisfied_by?(module, {:same_file, a, b}), do: module.same_file?(a, b)

  defp satisfied_by?(module, :unrelated_link), do: module |> unrelated_link_write() |> elem(0)

  defp satisfied_by?(module, :guard_list) do
    Enum.sort(module.guards()) == guard_plants() |> Enum.map(&elem(&1, 0)) |> Enum.sort()
  end

  # R1-2 in-process: (a) the dotdot path IS b/committed.json (absent); (b) it is NOT
  # a/committed.json, though a lexical collapse says it is.
  defp satisfied_by?(module, {:dotdot, which}) do
    with_dotdot(fn %{via: via, a_committed: a, b_committed: b} ->
      case which do
        :a ->
          module.same_file?(via, b)

        :b ->
          File.write!(a, "A")
          File.write!(b, "B")
          not module.same_file?(via, a)
      end
    end)
  end

  # R1-1 in-process, on a fresh decoy each time: the output path already IS a link to the
  # protected file when write_output!/3 is called (as after a mid-capture swap). WB1 links
  # the final component; WB2 links a parent directory. Satisfied only if the write is
  # refused AND the protected bytes are unchanged.
  defp satisfied_by?(module, {:write_boundary, kind}) do
    {dir, protected, _alias, _hard} = decoy()
    before = File.read!(protected)

    out =
      case kind do
        :final_link ->
          link = Path.join(dir, "out.json")
          :ok = File.ln_s(protected, link)
          link

        :parent_link ->
          plink = Path.join(dir, "plink")
          :ok = File.ln_s(dir, plink)
          Path.join(plink, "committed.json")
      end

    result =
      try do
        module.write_output!(out, "REPORT", [protected])
      rescue
        e -> {:raised, Exception.message(e)}
      end

    ok = match?({:refused, _}, result) and File.read!(protected) == before
    File.rm_rf!(dir)
    ok
  end

  defp satisfied_by?(module, {committed, fresh, want}) do
    report = module.check(committed, fresh)
    RowsDrift.exit_status(report) == want_exit(want) and satisfied?(report, want)
  end

  # Replace exactly one occurrence of `from` with `to`. Raises if `from` is not there exactly
  # once: a mutation that cannot be applied must not read as a pass.
  defp compile_mutant(source, mid, from, to) do
    n = source |> String.split(from) |> length() |> Kernel.-(1)

    unless n == 1 do
      raise "CANNOT MUTATE — #{mid}'s target text occurs #{n} times in #{@source} " <>
              "(need exactly 1): #{inspect(from)}. Update the mutation, or its cases are " <>
              "unfalsified."
    end

    name = "RowsDriftMutant#{String.replace(mid, "-", "")}#{System.unique_integer([:positive])}"

    mutated =
      source
      |> String.replace(from, to)
      |> String.replace("defmodule MCP.Conformance.RowsDrift do", "defmodule #{name} do")

    {result, _diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(mutated) end)
    [{module, _} | _] = result
    module
  end

  # --- plumbing --------------------------------------------------------------------------

  defp fixture, do: @fixture |> File.read!() |> Jason.decode!()

  defp scratch_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp reseal(art) do
    rows = ExUnitRows.sort_rows(art["rows"])
    %{art | "rows" => rows} |> put_run("rows_md5", ExUnitRows.rows_md5(rows))
  end

  defp put_run(art, k, v), do: %{art | "run" => Map.put(art["run"], k, v)}
  defp add_row(art, row), do: reseal(%{art | "rows" => art["rows"] ++ [row]})

  defp drop_row(art, key),
    do: reseal(%{art | "rows" => Enum.reject(art["rows"], &(&1["key"] == key))})

  defp update_row(art, key, fun),
    do:
      reseal(%{
        art
        | "rows" => Enum.map(art["rows"], &if(&1["key"] == key, do: fun.(&1), else: &1))
      })

  defp header(t), do: IO.puts("\n== #{t} ==\n")

  defp check(id, what, ok) do
    IO.puts("  #{if ok, do: "ok  ", else: "FAIL"}  #{id}  #{what}")
    if ok, do: :ok, else: :error
  end

  defp verdict(results) do
    failed = Enum.count(results, &(&1 == :error))
    IO.puts("\n  #{length(results) - failed}/#{length(results)} as expected.")
    if failed > 0, do: System.halt(1)
  end
end

RowsDriftControls.run(System.argv())
