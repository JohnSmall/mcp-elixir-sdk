# Controls for gate 9, `mix conformance.register_drift` (MES-241).
#
#     mix run conformance/controls/register_drift_controls.exs plants
#     mix run conformance/controls/register_drift_controls.exs guards
#     mix run conformance/controls/register_drift_controls.exs neverwrite
#     mix run conformance/controls/register_drift_controls.exs mutation
#     mix run conformance/controls/register_drift_controls.exs live
#     mix run conformance/controls/register_drift_controls.exs livedoc
#     mix run conformance/controls/register_drift_controls.exs all
#
# THE FIXTURE. Every mode works in a full-history clone of this tree's COMMITTED HEAD under
# the system tmp dir (deps and _build copied in), never in the tree that runs it. So commit
# before running, as with oc_gate_controls. Each plant edits the clone's sources and builds
# its FRESH capture from the clone's committed rows file plus exactly the change a real
# capture would show (keys, and lines shifted by arithmetic, not by the locator under test).
# The plant is then COMMITTED, and the capture given that commit as its tip and a suite_rc of
# 0, because gate 9 judges a capture only at its own commit over a clean tree (RT1-RT3,
# correction round 1). No plant captures the suite; `live` is the one mode that does.
#
# plants     — the REAL task as a subprocess in the clone (`--fresh F --json R`). Each plant is
#              adjudicated on the REASON CLASS of every step, never on a bare exit: reproduce
#              ok / not identical / refused-with-a-message, keysets ok / differ, fresh ok /
#              refused-with-a-message / rows (only committed, only fresh, changed fields).
#              P0 is the no-op and P1 a test/conformance-only change: both must exit 0.
# guards     — one plant per RowsDrift guard, RD1-RD9, and per provenance guard, RT1 (a
#              stale tip: CR's keep-at-A-replay-at-B case; a missing tip), RT2 (the tree being
#              judged is dirty) and RT3 (no suite_rc), through the real task. Each must exit 2
#              and be refused by its own guard alone. FG is the false-green route: an
#              end-appended test with an incomplete capture that lacks it. INJ1/INJ2 inject an
#              ArgumentError and a non-REFUSING RuntimeError into a compiled copy of the
#              module: each must be refused RT4 (exit 2), never drift (CR finding R4). GL: the
#              guards the module advertises (`RegisterDrift.guards/0`) equal those exercised.
# neverwrite — `--keep` and `--json` at the committed rows file or the register (literally,
#              through a symlinked parent, through a hard link) must exit 64 with both files
#              byte-unchanged; NW0, an unrelated --json path, is written and exits 0. WT1/WT2
#              call `RowsDrift.write_output!/3` with the gate's protected list at a path that
#              already IS a link to either file (the at-write re-check): refused, bytes
#              unchanged.
# mutation   — compiled copies of `MCP.Conformance.RegisterDrift`, each with one change. Each
#              must turn red the cases it names, and the unmutated module must satisfy those
#              cases first. ML: the mutants run must equal the advertised list, and every
#              equivalent mutant is listed with its reason rather than silently skipped.
# live       — two real captures. L1-L5: one at HEAD with --keep (exit 0; the kept file is
#              the adjudicated artefact, suite_rc 0), replayed clean at HEAD (L3), refused RT1
#              after a commit (L4) and RT2 over a dirty tree (L5). L6-L8, CR's R2 fixture: a
#              suite that exits 7 with every row green is refused RD7 live, the kept capture
#              carries suite_rc 7 and is refused RD7 on replay, and with suite_rc stripped it
#              is refused RT3. About five minutes.
# livedoc    — one real capture (round 3, CR R5): a test/mcp file doctests three test/support
#              modules (outside lib/) by a qualified call, an attribute reassigned inside `if`
#              and an attribute, and a lib/ module through `require ..., as:`. RT5 must refuse,
#              naming the three and not the lib/ module, and ExUnit must have run all four.
#              D4 (round 4): a second capture of CR's shadow, a byte-copy of lib/'s HeaderMirror
#              compiled from conformance/ and loaded by a test_helper.exs hook; RT5 must refuse
#              it alone, from the compile source the capture recorded.
#
# WHY A SCRIPT AND NOT AN ExUnit TEST: a test would join the population the rows file records,
# and would move the register it checks just by existing (`etcc_register_controls.exs`).

defmodule RegisterDriftControls do
  alias MCP.Conformance.{ETCCRegister, ExUnitRows, RegisterDrift, RowsDrift}

  @project File.cwd!()
  @source "conformance/lib/mcp/conformance/register_drift.ex"
  @modes ~w(plants guards neverwrite mutation live livedoc)
  @rows "docs/conformance/etcc-exunit-rows.json"
  @register "docs/conformance/etcc-register.json"
  @sse "test/mcp/transport/sse_dispatch_test.exs"
  @sse_moved "test/mcp/transport/sse_dispatch_moved_test.exs"
  @hm_test "test/mcp/protocol/header_mirror_test.exs"
  @hm_lib "lib/mcp/protocol/header_mirror.ex"
  @conf "test/conformance/classification_retired_test.exs"

  # Mutants that are run, and mutants that are NOT, each with the reason. Both lists are
  # checked against what `mutation` actually does (ML).
  @advertised_mutants ~w(M1 M2 M4 M6a M6b M7 MP MT1 MT2 MT3 MK MR4 MR4f MR4s MT5 MT5n MR4n)
  @equivalent_mutants %{
    "M3" =>
      "skip keysets: equivalent in verdict (measured as M3e). keysets can be red only when reproduce is red, " <>
        "because a green reproduce means the register IS build/1's output, and build/1 " <>
        "refuses a key-set or partition failure (check_key_sets!/2, check_partition!/3). " <>
        "P10 shows keysets reporting DIFFER alongside reproduce.",
    "M5" =>
      "compare rows without totals: there is no totals comparison to remove. The in-scope " <>
        "totals are a function of rows (totals/4 counts the rows; check_totality!/2 ties " <>
        "in_scope to them), so the plan's totals compare was dropped as equivalent."
  }

  def run(["plants"]), do: in_clone(&plants/1)
  def run(["guards"]), do: in_clone(&guards/1)
  def run(["neverwrite"]), do: in_clone(&neverwrite/1)
  def run(["mutation"]), do: in_clone(&mutation/1)
  def run(["live"]), do: in_clone(&live/1)
  def run(["livedoc"]), do: in_clone(&livedoc/1)
  def run(["all"]), do: all()

  def run(_) do
    IO.puts("usage: plants | guards | neverwrite | mutation | live | livedoc | all")
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

  # --- the plants --------------------------------------------------------------------

  # {id, what, tree edit (fx -> :ok), fresh (committed rows artefact -> artefact), want}.
  # want: %{reproduce: r, keysets: k, fresh: f} with r :: :ok | :not_identical | {:refused, re},
  # k :: :ok | :differ, f :: :ok | {:refused, re} | {:rows, only_committed, only_fresh, fields}.
  defp plant_cases do
    no_decision = ~r/in-scope unit\(s\) have no decision/
    cannot_locate = ~r/cannot locate .* no `test` declaration has that name/
    ok3 = %{reproduce: :ok, keysets: :ok, fresh: :ok}

    [
      {"P0", "no-op: nothing changed", fn _ -> :ok end, &same/2, ok3},
      {"P1", "a test added under test/conformance/ only (out_of_scope is not compared)",
       &append_describe(&1, @conf), &add_appended(&1, &2, @conf), ok3},
      {"P2", "a1: a test added mid-file in #{@sse}", &insert_test_mid/1, &fresh_insert_mid/2,
       %{reproduce: :not_identical, keysets: :ok, fresh: {:refused, no_decision}}},
      {"P3", "a2: a test appended at the end of #{@sse}", &append_describe(&1, @sse),
       &add_appended(&1, &2, @sse), %{ok3 | fresh: {:refused, no_decision}}},
      {"P4", "b: three lines inserted above a test (a move)", &move_down/1, &fresh_move_down/2,
       %{reproduce: :not_identical, keysets: :ok, fresh: {:rows, 0, 0, ["line"]}}},
      {"P5", "c: a test renamed", &rename/1, &fresh_rename/2,
       %{reproduce: {:refused, cannot_locate}, keysets: :ok, fresh: {:refused, no_decision}}},
      {"P6", "d: a test deleted", &delete/1, &fresh_delete/2,
       %{
         reproduce: {:refused, cannot_locate},
         keysets: :ok,
         fresh: {:refused, ~r/decision\(s\) name a key that is not an in-scope unit/}
       }},
      {"P7", "a doctest example added in #{@hm_lib}", &add_doctest/1, &fresh_add_doctest/2,
       %{ok3 | fresh: {:refused, no_decision}}},
      {"P8", "residual (iii): the doctest directive in #{@hm_test} moved down two lines",
       &move_directive/1, &fresh_move_directive/2, %{ok3 | fresh: {:rows, 0, 0, ["line"]}}},
      {"P9", "the register's provenance hand-edited (only reproduce can see it)",
       &edit_provenance/1, &same/2, %{ok3 | reproduce: :not_identical}},
      {"P10", "one register row hand-deleted (keysets reports it)", &drop_register_row/1, &same/2,
       %{reproduce: :not_identical, keysets: :differ, fresh: {:rows, 0, 1, []}}},
      {"P11", "#{@sse} renamed, register rebuilt from the fresh capture, rows file not",
       &rename_file/1, &fresh_rename_file/2,
       %{reproduce: {:refused, ~r/^File\.Error: could not read file/}, keysets: :ok, fresh: :ok}}
    ]
  end

  defp plants(fx) do
    header("PLANTS — the real task, each step adjudicated on its reason class")

    for {id, what, edit, fresh, want} <- plant_cases() do
      {report, status, last} = with_plant(fx, edit, fresh, &through_task(fx, &1))
      want_exit = if want == ok_want(), do: 0, else: 1
      banner = if want_exit == 0, do: "register-drift: CLEAN", else: "register-drift: DRIFT"
      ok = status == want_exit and String.starts_with?(last, banner) and satisfied?(report, want)
      check(id, "#{what} -> exit #{status}; #{summary(report)}\n        #{last}", ok)
    end
  end

  defp same(c, _fx), do: c

  defp ok_want, do: %{reproduce: :ok, keysets: :ok, fresh: :ok}

  # Apply the plant to the clone, build its fresh capture, COMMIT the plant (gate 9 judges a
  # clean tree at the capture's tip, RT1/RT2), give the capture that tip and a suite_rc of
  # 0, run `fun`, then restore the clone to where it was. opts: tip: :head | :orig |
  # :missing; rc: an integer, or nil for none; dirty: true leaves the plant uncommitted.
  defp with_plant(fx, edit, fresh_fun, fun, opts \\ %{}) do
    orig = git!(fx, ["rev-parse", "HEAD"])
    edit.(fx)
    fresh = fresh_fun.(committed_rows(fx), fx)

    unless opts[:dirty] do
      git!(fx, ["add", "-A"])

      git!(fx, [
        "-c",
        "user.name=fixture",
        "-c",
        "user.email=fixture@invalid",
        "commit",
        "-q",
        "--allow-empty",
        "-m",
        "plant"
      ])
    end

    head = git!(fx, ["rev-parse", "HEAD"])

    try do
      fun.(provenance(fresh, head, orig, opts, fx))
    after
      reset!(fx, orig)
    end
  end

  defp provenance(:missing, _, _, _, _), do: :missing

  defp provenance(fresh, head, orig, opts, fx) do
    run =
      case Map.get(opts, :tip, :head) do
        :head -> Map.put(fresh["run"], "tip", head)
        :orig -> Map.put(fresh["run"], "tip", orig)
        :missing -> Map.delete(fresh["run"], "tip")
      end

    run =
      case Map.fetch(opts, :rc) do
        {:ok, nil} -> Map.delete(run, "suite_rc")
        {:ok, rc} -> Map.put(run, "suite_rc", rc)
        :error -> Map.put(run, "suite_rc", 0)
      end

    run =
      case Map.get(opts, :sources, :lib) do
        :lib ->
          Map.put(run, "doctest_sources", lib_sources(fresh, fx))

        :strip ->
          Map.delete(run, "doctest_sources")

        {:override, mod, path} ->
          Map.put(run, "doctest_sources", Map.put(lib_sources(fresh, fx), mod, path))
      end

    %{fresh | "run" => run}
  end

  # What a capture in the clone records for its doctested modules: the compile source of the
  # loaded definition, i.e. the module's lib/ file inside the clone. A module this VM cannot
  # place under the project (e.g. one outside lib/) gets no entry, as a capture whose VM
  # could not read one would record nil.
  defp lib_sources(fresh, fx) do
    for %{"test_type" => "doctest", "tags" => %{"doctest" => mod}} <- fresh["rows"],
        source = clone_source(mod, fx),
        into: %{},
        do: {mod, source}
  end

  defp clone_source(mod, fx) do
    module = String.to_existing_atom("Elixir." <> mod)
    rel = module.module_info(:compile)[:source] |> to_string() |> Path.relative_to(@project)
    if String.starts_with?(rel, "lib/"), do: Path.join(fx, rel)
  rescue
    _ -> nil
  end

  defp through_task(fx, fresh, extra \\ []) do
    dir = scratch("register_drift_run")
    f = Path.join(dir, "fresh.json")
    j = Path.join(dir, "report.json")
    File.write!(f, if(is_map(fresh), do: ExUnitRows.encode(fresh), else: fresh))

    {out, status} =
      System.cmd("mix", ["conformance.register_drift", "--fresh", f, "--json", j] ++ extra,
        cd: fx,
        stderr_to_stdout: true
      )

    report =
      case File.read(j) do
        {:ok, bytes} -> Jason.decode!(bytes)
        _ -> %{"verdict" => "NO REPORT", "output" => out}
      end

    File.rm_rf!(dir)
    {report, status, out |> String.trim_trailing() |> String.split("\n") |> List.last()}
  end

  defp satisfied?(report, want) do
    report["verdict"] in ["clean", "drift"] and
      step?(report["reproduce"], :reproduce, want.reproduce) and
      step?(report["keysets"], :keysets, want.keysets) and
      step?(report["fresh"], :fresh, want.fresh)
  end

  defp step?(%{"ok" => true, "refused" => nil}, :reproduce, :ok), do: true
  defp step?(%{"ok" => false, "refused" => nil}, :reproduce, :not_identical), do: true
  defp step?(%{"ok" => true}, :keysets, :ok), do: true
  defp step?(%{"ok" => false, "differ" => [_ | _]}, :keysets, :differ), do: true

  defp step?(%{"ok" => true, "refused" => nil} = s, :fresh, :ok),
    do: s["only_committed"] == [] and s["only_fresh"] == [] and s["changed"] == []

  defp step?(%{"ok" => false, "refused" => msg}, _, {:refused, re}) when is_binary(msg),
    do: Regex.match?(re, msg)

  defp step?(%{"ok" => false, "refused" => nil} = s, :fresh, {:rows, oc, of, fields}) do
    length(s["only_committed"]) == oc and length(s["only_fresh"]) == of and
      Enum.all?(s["changed"], &(&1["fields"] == fields)) and
      (fields == [] or s["changed"] != [])
  end

  defp step?(_, _, _), do: false

  defp summary(%{"verdict" => "refused"} = r),
    do: "refused by #{inspect(Enum.map(r["refusals"], &{&1["guard"], &1["side"]}))}"

  defp summary(%{"verdict" => v} = r) when v in ["clean", "drift"] do
    "#{v}: " <>
      Enum.map_join(RegisterDrift.steps(), "; ", fn s -> "#{s} #{step_summary(r[s])}" end)
  end

  defp summary(r), do: inspect(r, limit: 5, printable_limit: 300)

  defp step_summary(%{"refused" => msg}) when is_binary(msg),
    do: "refused (#{String.slice(msg, 0, 90)})"

  defp step_summary(%{"ok" => true}), do: "ok"
  defp step_summary(%{"differ" => d}), do: "differ #{length(d)}"

  defp step_summary(%{"changed" => c} = s),
    do:
      "rows only_committed=#{length(s["only_committed"])} only_fresh=#{length(s["only_fresh"])} " <>
        "changed=#{length(c)} #{inspect(c |> Enum.flat_map(& &1["fields"]) |> Enum.uniq())}"

  defp step_summary(s), do: "not identical (#{s["committed_md5"]} vs #{s["rebuilt_md5"]})"

  # --- the source edits and the fresh captures that go with them ----------------------

  @added_describe "register drift plant"
  @added_title "an added test"

  defp new_test(indent),
    do: [
      "#{indent}test \"#{@added_title}\" do",
      "#{indent}  assert true",
      "#{indent}end"
    ]

  # An appended describe, before the module's final `end`.
  defp append_describe(fx, file) do
    lines = read_lines(fx, file)
    e = last_index(lines, "end")

    write_lines(
      fx,
      file,
      List.insert_at(
        lines,
        e,
        ["", "  describe \"#{@added_describe}\" do"] ++ new_test("    ") ++ ["  end"]
      )
      |> List.flatten()
    )
  end

  defp add_appended(c, fx, file) do
    module = c["rows"] |> Enum.find(&(&1["file"] == file)) |> Map.fetch!("module")
    line = index_of(read_lines(fx, file), ~s(test "#{@added_title}")) + 1
    name = "test #{@added_describe} #{@added_title}"
    add_row(c, test_row(module, file, name, @added_describe, line))
  end

  @mid_before "a later event without an id carries the last id"

  defp insert_test_mid(fx) do
    lines = read_lines(fx, @sse)
    j = block_start(lines, @mid_before)
    write_lines(fx, @sse, List.insert_at(lines, j, new_test("    ") ++ [""]) |> List.flatten())
  end

  defp fresh_insert_mid(c, fx) do
    lines = read_lines(fx, @sse)
    line = index_of(lines, ~s(test "#{@added_title}")) + 1

    before =
      c["rows"] |> Enum.find(&(&1["file"] == @sse and String.ends_with?(&1["key"], @mid_before)))

    c
    |> shift(@sse, line, 4)
    |> add_row(
      test_row(
        before["module"],
        @sse,
        "test #{before["describe"]} #{@added_title}",
        before["describe"],
        line
      )
    )
  end

  @moved "an id with NUL is not set"

  defp move_down(fx) do
    lines = read_lines(fx, @sse)
    j = block_start(lines, @moved)
    comment = ["    # register drift plant: moved", "    # down", "    # three lines"]
    write_lines(fx, @sse, List.insert_at(lines, j, comment) |> List.flatten())
  end

  defp fresh_move_down(c, fx) do
    first = index_of(read_lines(fx, @sse), "# register drift plant: moved") + 1
    shift(c, @sse, first, 3)
  end

  @renamed "an id without NUL is kept"
  @renamed_to "an id without NUL is retained"

  defp rename(fx) do
    lines = read_lines(fx, @sse)
    i = index_of(lines, ~s(test "#{@renamed}"))
    write_lines(fx, @sse, List.update_at(lines, i, &String.replace(&1, @renamed, @renamed_to)))
  end

  defp fresh_rename(c, _fx) do
    update_rows(c, fn r ->
      if r["file"] == @sse and String.ends_with?(r["key"], @renamed),
        do: %{
          r
          | "key" => String.replace(r["key"], @renamed, @renamed_to),
            "name" => String.replace(r["name"], @renamed, @renamed_to)
        },
        else: r
    end)
  end

  @deleted "decode_event/1 ignores an id with NUL"

  # Removes the test's block and the blank line above it: n lines, from line `from` on.
  defp delete(fx) do
    {from, n} = deleted_span(read_lines(fx, @sse))
    lines = read_lines(fx, @sse)
    write_lines(fx, @sse, Enum.take(lines, from - 1) ++ Enum.drop(lines, from - 1 + n))
  end

  defp deleted_span(lines) do
    j = block_start(lines, @deleted)
    k = Enum.find_index(Enum.drop(lines, j), &(&1 == "    end")) + j
    {j, k - j + 2}
  end

  # The span is measured on the file as committed: the plant has already removed it.
  defp fresh_delete(c, fx) do
    {from, n} = deleted_span(git!(fx, ["show", "HEAD:" <> @sse]) |> String.split("\n"))

    %{
      c
      | "rows" =>
          Enum.reject(c["rows"], &(&1["file"] == @sse and String.ends_with?(&1["key"], @deleted)))
    }
    |> shift(@sse, from + n, -n)
  end

  @last_example ~s(      "=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=")

  defp add_doctest(fx) do
    lines = read_lines(fx, @hm_lib)
    i = index_of(lines, @last_example)
    extra = ["", ~s|      iex> MCP.Protocol.HeaderMirror.encode_value("abc")|, ~s(      "abc")]
    write_lines(fx, @hm_lib, List.insert_at(lines, i + 1, extra) |> List.flatten())
  end

  defp fresh_add_doctest(c, _fx) do
    four = Enum.find(c["rows"], &String.ends_with?(&1["key"], "HeaderMirror.encode_value/1 (4)"))
    tags = %{four["tags"] | "doctest_line" => four["tags"]["doctest_line"] + 3}

    add_row(c, %{
      four
      | "key" => String.replace(four["key"], "(4)", "(5)"),
        "name" => String.replace(four["name"], "(4)", "(5)"),
        "tags" => put_in(tags, ["doctest_data", "end_line"], four["tags"]["doctest_line"] + 4)
    })
  end

  @directive "  doctest MCP.Protocol.HeaderMirror, tags: [:etcc]"

  # The directive swaps places with the `defp schema` line two below it: no test moves.
  defp move_directive(fx) do
    lines = read_lines(fx, @hm_test)
    d = index_of(lines, @directive)
    "" = Enum.at(lines, d + 1)
    true = String.starts_with?(Enum.at(lines, d + 2), "  defp schema(")

    write_lines(
      fx,
      @hm_test,
      lines |> List.replace_at(d, Enum.at(lines, d + 2)) |> List.replace_at(d + 2, @directive)
    )
  end

  defp fresh_move_directive(c, fx) do
    line = index_of(read_lines(fx, @hm_test), @directive) + 1

    update_rows(c, fn r ->
      if r["file"] == @hm_test and r["test_type"] == "doctest", do: %{r | "line" => line}, else: r
    end)
  end

  defp edit_provenance(fx) do
    reg = fx |> Path.join(@register) |> File.read!() |> Jason.decode!()
    reg = put_in(reg, ["provenance", "note"], "hand-edited by a register_drift_controls plant")
    File.write!(Path.join(fx, @register), ETCCRegister.encode(reg))
  end

  defp drop_register_row(fx) do
    reg = fx |> Path.join(@register) |> File.read!() |> Jason.decode!()
    File.write!(Path.join(fx, @register), ETCCRegister.encode(%{reg | "rows" => tl(reg["rows"])}))
  end

  # The test file is renamed (keys unchanged: a key is module/name), the contributor
  # rebuilt the register from a fresh capture and did NOT commit the re-captured rows file.
  defp rename_file(fx) do
    git!(fx, ["mv", @sse, @sse_moved])
    fresh = fresh_rename_file(committed_rows(fx), fx)

    spec =
      fx
      |> Path.join(@register)
      |> File.read!()
      |> Jason.decode!()
      |> get_in(["provenance", "spec_files"])

    File.cd!(fx, fn -> ETCCRegister.write(artefact: fresh, spec_md5s: spec) end)
  end

  defp fresh_rename_file(c, _fx),
    do: update_rows(c, &if(&1["file"] == @sse, do: %{&1 | "file" => @sse_moved}, else: &1))

  defp doctest_row(name, tag) do
    module = "MCP.RegisterDriftPlantTest"

    %{
      test_row(module, "test/mcp/register_drift_plant_test.exs", name, nil, 5)
      | "test_type" => "doctest",
        "tags" => if(tag, do: %{"doctest" => tag, "doctest_line" => 3}, else: %{})
    }
  end

  defp test_row(module, file, name, describe, line),
    do: %{
      "describe" => describe,
      "failure" => nil,
      "file" => file,
      "key" => module <> "/" <> name,
      "line" => line,
      "module" => module,
      "name" => name,
      "reason" => nil,
      "status" => "passed",
      "tags" => %{},
      "test_type" => "test"
    }

  # Every row of `file` at or below line `from` moves by `by`.
  defp shift(c, file, from, by) do
    update_rows(c, fn r ->
      if r["file"] == file and r["line"] >= from, do: %{r | "line" => r["line"] + by}, else: r
    end)
  end

  # --- guards --------------------------------------------------------------------------

  defp guard_plants(c) do
    r1 = Enum.find(c["rows"], &String.starts_with?(&1["file"], "test/mcp/"))

    unsealed = fn a ->
      %{a | "rows" => Enum.map(a["rows"], &if(&1 == r1, do: %{&1 | "line" => 1}, else: &1))}
    end

    [
      {"RD1", "schema etcc-exunit-rows/0", &%{&1 | "schema" => "etcc-exunit-rows/0"}},
      {"RD2", "a row edited without resealing rows_md5", unsealed},
      {"RD3", "complete false", &put_run(&1, "complete", false)},
      {"RD4", "argv names one file", &put_run(&1, "argv", ["test", @sse, "--seed", "0"])},
      {"RD5", "exclude [:requires_live_harness]",
       &put_run(&1, "exclude", [":requires_live_harness"])},
      {"RD6", "tree_clean false, one dirty path",
       &(&1 |> put_run("tree_clean", false) |> put_run("tree_dirty", ["lib/planted.ex"]))},
      {"RD7", "one row failed",
       &update_rows(&1, fn r -> if r == r1, do: %{r | "status" => "failed"}, else: r end)},
      {"RD8", "one row duplicated, rows_md5 resealed", &add_row(&1, r1)},
      {"RD9", "a row whose module is not its key's, rows_md5 resealed",
       &update_rows(&1, fn r -> if r == r1, do: %{r | "module" => "MCP.Planted"}, else: r end)}
    ]
  end

  # {id, what, tree edit, fresh, guard, with_plant opts}
  defp guard_cases(fx) do
    c = committed_rows(fx)
    none = fn _ -> :ok end
    same = fn a, _ -> a end

    for(
      {g, what, plant} <- guard_plants(c),
      do: {g, "fresh: " <> what, none, fn a, _ -> plant.(a) end, g, %{}}
    ) ++
      [
        {"FG",
         "false green: #{@sse} gains an appended test, the fresh capture lacks it and is incomplete",
         &append_describe(&1, @sse), fn a, _ -> put_run(a, "complete", false) end, "RD3", %{}},
        {"RD1m", "--fresh names no file", none, fn _, _ -> :missing end, "RD1", %{}},
        {"RD7rc", "every row passed, but the suite exited 2", none, same, "RD7", %{rc: 2}},
        {"RT1",
         "stale tip (R1): a capture of the commit BEFORE an appended test, replayed after it",
         &append_describe(&1, @sse), same, "RT1", %{tip: :orig}},
        {"RT1m", "a capture with no tip", none, same, "RT1", %{tip: :missing}},
        {"RT2", "the tree being judged is dirty (R1): an appended test, not committed",
         &append_describe(&1, @sse), same, "RT2", %{dirty: true}},
        {"RT3", "a capture with no suite_rc (R2: a replay must not lose the suite's status)",
         none, same, "RT3", %{rc: nil}},
        {"RT5a", "a test/mcp doctest unit of a function of a module outside lib/ (R5)", none,
         fn a, _ ->
           add_row(
             a,
             doctest_row(
               "doctest MCP.Conformance.RequestState.verify/2 (1)",
               "MCP.Conformance.RequestState"
             )
           )
         end, "RT5", %{}},
        {"RT5b", "a test/mcp moduledoc doctest unit of a module outside lib/", none,
         fn a, _ ->
           add_row(
             a,
             doctest_row(
               "doctest module MCP.Conformance.RequestState (1)",
               "MCP.Conformance.RequestState"
             )
           )
         end, "RT5", %{}},
        {"RT5c", "a test/mcp doctest unit whose name cannot be parsed", none,
         fn a, _ -> add_row(a, doctest_row("doctest 42 (1)", nil)) end, "RT5", %{}},
        {"RT5s", "a capture whose doctest_sources record is stripped (R5 round 4)", none, same,
         "RT5", %{sources: :strip}},
        {"RT5o", "a lib/ name whose recorded definition was compiled outside lib/ (CR's shadow)",
         none, same, "RT5",
         %{sources: {:override, "MCP.Protocol.HeaderMirror", "conformance/cr_header_mirror.ex"}}},
        {"RT5d", "a test/mcp doctest unit whose name (lib/) and doctest tag (outside) disagree",
         none,
         fn a, _ ->
           add_row(
             a,
             doctest_row(
               "doctest MCP.Protocol.HeaderMirror.encode_value/1 (9)",
               "MCP.Conformance.RequestState"
             )
           )
         end, "RT5", %{}}
      ]
  end

  # R4: an unexpected exception inside a build is refused RT4, never drift. Injected into a
  # compiled copy of the module, since no real input raises it. {id, what, from, to, step}
  defp injections do
    [
      {"INJ1", "an ArgumentError injected into the reproduce build",
       "rebuilt = ETCCRegister.encode(ETCCRegister.build(spec_md5s: spec_md5s(committed)))",
       ~s|rebuilt = raise(ArgumentError, "injected implementation fault")|, "reproduce", &same/2},
      {"INJ2", "a RuntimeError that is not a generator refusal, injected into the fresh build",
       "built = ETCCRegister.build(artefact: fresh, spec_md5s: spec_md5s(committed))",
       ~s|built = raise("injected: not a REFUSING message")|, "fresh", &same/2},
      # Round 2 (CR R4): a File.Error is drift only as :enoent on a test source the committed
      # register cites. Permission, descriptor exhaustion and an unrelated missing file are not.
      {"INJ3", "File.Error :eacces on a cited test source, injected into the reproduce build",
       "rebuilt = ETCCRegister.encode(ETCCRegister.build(spec_md5s: spec_md5s(committed)))",
       file_error("rebuilt", ":eacces", "./#{@sse}"), "reproduce", &same/2},
      {"INJ4", "File.Error :emfile on a cited test source, injected into the reproduce build",
       "rebuilt = ETCCRegister.encode(ETCCRegister.build(spec_md5s: spec_md5s(committed)))",
       file_error("rebuilt", ":emfile", "./#{@sse}"), "reproduce", &same/2},
      {"INJ5", "File.Error :enoent on a path the register does not cite, in the fresh build",
       "built = ETCCRegister.build(artefact: fresh, spec_md5s: spec_md5s(committed))",
       file_error("built", ":enoent", "./tmp/not-a-register-input.json"), "fresh", &same/2},
      # Round 3 (CR R4): only IN-SCOPE sources are cited. An :enoent on a test/conformance file
      # (named only by out_of_scope rows of an unmodified capture), or on a path an out_of_scope
      # row was planted to name, is an instrument error, never drift.
      {"INJ6",
       "File.Error :enoent on test/conformance/gate_9_trigger_test.exs, fresh build of an unmodified capture",
       "built = ETCCRegister.build(artefact: fresh, spec_md5s: spec_md5s(committed))",
       file_error("built", ":enoent", "./test/conformance/gate_9_trigger_test.exs"), "fresh",
       &with_trigger_row/2},
      {"INJ7",
       "File.Error :enoent on tmp/cr-arbitrary-input.json, which a planted out_of_scope row names",
       "built = ETCCRegister.build(artefact: fresh, spec_md5s: spec_md5s(committed))",
       file_error("built", ":enoent", "./tmp/cr-arbitrary-input.json"), "fresh", &self_cited/2}
    ]
  end

  # A live capture at this tip has rows for test/conformance/gate_9_trigger_test.exs (L1's kept
  # capture does); the committed rows file predates that file (MES-247), so INJ6's capture is
  # given one of them, as an unmodified capture would carry it.
  defp with_trigger_row(c, _fx) do
    add_row(
      c,
      test_row(
        "MCP.Conformance.Gate9TriggerTest",
        "test/conformance/gate_9_trigger_test.exs",
        "test the command's text CLAUDE.md carries the identical command, once",
        "the command's text",
        106
      )
    )
  end

  # CR's planted case: an out_of_scope row, consistent and resealed, naming an arbitrary path.
  defp self_cited(c, _fx) do
    module = "MCP.Conformance.CrArbitraryInputTest"
    name = "test cr arbitrary input"

    add_row(c, %{
      test_row(module, "tmp/cr-arbitrary-input.json", name, nil, 1)
      | "describe" => nil
    })
  end

  defp file_error(var, reason, path) do
    "#{var} = raise(File.Error, reason: #{reason}, action: \"read file\", path: #{inspect(path)})"
  end

  defp guards(fx) do
    header("GUARDS — each capture refused by its own guard alone; R4 instrument errors refused")

    results =
      for {id, what, edit, fresh, g, opts} <- guard_cases(fx) do
        {report, status, last} =
          with_plant(
            fx,
            edit,
            fresh,
            fn
              :missing -> through_missing(fx)
              a -> through_task(fx, a)
            end,
            opts
          )

        fired =
          report["refusals"] |> List.wrap() |> Enum.map(&{&1["guard"], &1["side"]}) |> Enum.uniq()

        ok =
          status == 2 and report["verdict"] == "refused" and fired == [{g, "fresh"}] and
            String.contains?(last, "register-drift: REFUSED - #{g} (")

        check(id, "#{what} -> exit #{status}; fired #{inspect(fired)}\n        #{last}", ok)
      end

    source = File.read!(Path.join(@project, @source))

    injected =
      for {id, what, from, to, step, fresh_fun} <- injections() do
        variant = compile_variant(source, id, [{from, to}])

        report =
          with_plant(fx, & &1, fresh_fun, fn f -> File.cd!(fx, fn -> variant.check(f) end) end)

        fired = Enum.map(report["refusals"], &{&1["guard"], &1["side"]})
        detail = report["refusals"] |> Enum.map_join(" ", & &1["detail"])

        check(
          id,
          "#{what} -> exit #{RegisterDrift.exit_status(report)}; fired #{inspect(fired)}; #{String.slice(detail, 0, 80)}",
          RegisterDrift.exit_status(report) == 2 and fired == [{"RT4", step}] and
            (String.contains?(detail, "injected") or String.starts_with?(detail, "File.Error: "))
        )
      end

    exercised =
      (Enum.map(guard_cases(fx), &elem(&1, 4)) ++ ["RT4"]) |> Enum.uniq() |> Enum.sort()

    results ++
      injected ++
      [
        check(
          "GL",
          "advertised #{inspect(RegisterDrift.guards())} == exercised #{inspect(exercised)}",
          Enum.sort(RegisterDrift.guards()) == exercised
        )
      ]
  end

  defp through_missing(fx) do
    dir = scratch("register_drift_run")
    j = Path.join(dir, "report.json")

    {out, status} =
      System.cmd(
        "mix",
        ["conformance.register_drift", "--fresh", Path.join(dir, "absent.json"), "--json", j],
        cd: fx,
        stderr_to_stdout: true
      )

    report = j |> File.read!() |> Jason.decode!()
    File.rm_rf!(dir)
    {report, status, out |> String.trim_trailing() |> String.split("\n") |> List.last()}
  end

  # --- neverwrite ----------------------------------------------------------------------

  defp neverwrite(fx) do
    header("NEVERWRITE — no output may name the rows file or the register, by any route")

    # Every route is planted OUTSIDE the clone, so the tree stays clean (RT2) and NW0 can
    # pass. The hard links share the clone's filesystem (both are under the tmp dir).
    nw = scratch("register_drift_nw")
    alias_dir = Path.join(nw, "alias")
    :ok = File.ln_s(Path.join(fx, "docs/conformance"), alias_dir)
    hard_rows = Path.join(nw, "hard-rows.json")
    hard_reg = Path.join(nw, "hard-register.json")
    :ok = File.ln(Path.join(fx, @rows), hard_rows)
    :ok = File.ln(Path.join(fx, @register), hard_reg)

    fresh = Path.join(nw, "fresh.json")
    head = git!(fx, ["rev-parse", "HEAD"])
    File.write!(fresh, ExUnitRows.encode(provenance(committed_rows(fx), head, head, %{}, fx)))
    unrelated = Path.join(nw, "report.json")
    alias_reg = Path.join(alias_dir, "etcc-register.json")
    alias_rows = Path.join(alias_dir, "etcc-exunit-rows.json")

    cases = [
      {"NW1", "--keep at the rows file", ["--keep", @rows], 64},
      {"NW2", "--keep at the register", ["--keep", @register], 64},
      {"NW3", "--keep at the register through a symlinked parent", ["--keep", alias_reg], 64},
      {"NW4", "--keep at a hard link to the rows file", ["--keep", hard_rows], 64},
      {"NW5", "--json at the register (with --fresh)", ["--fresh", fresh, "--json", @register],
       64},
      {"NW6", "--json at the rows file through a symlinked parent",
       ["--fresh", fresh, "--json", alias_rows], 64},
      {"NW7", "--json at a hard link to the register", ["--fresh", fresh, "--json", hard_reg],
       64},
      {"NW0", "--json at an unrelated path (the guard refuses selectively)",
       ["--fresh", fresh, "--json", unrelated], 0}
    ]

    results =
      for {id, what, args, want} <- cases do
        before = protected_md5s(fx)

        {out, status} =
          System.cmd("mix", ["conformance.register_drift" | args], cd: fx, stderr_to_stdout: true)

        unchanged = protected_md5s(fx) == before
        written = want != 0 or File.exists?(unrelated)
        last = out |> String.trim_trailing() |> String.split("\n") |> List.last()

        check(
          id,
          "#{what} -> exit #{status}; protected bytes unchanged #{unchanged}\n        #{last}",
          status == want and unchanged and written
        )
      end

    results = results ++ [at_write(fx, "WT1", @rows), at_write(fx, "WT2", @register)]
    File.rm_rf!(nw)
    results
  end

  # The at-write re-check: the output path already IS a link to the protected file when
  # write_output!/3 runs (as after a link planted during the capture).
  defp at_write(fx, id, target) do
    File.cd!(fx, fn ->
      link = "docs/planted-link.json"
      :ok = File.ln_s(Path.expand(target), link)
      before = protected_md5s(fx)
      result = RowsDrift.write_output!(link, "PLANTED", RegisterDrift.protected())
      unchanged = protected_md5s(fx) == before
      File.rm!(link)

      check(
        id,
        "write_output!/3 at a link to #{target}, gate 9's protected list -> #{inspect(result)}; bytes unchanged #{unchanged}",
        match?({:refused, _}, result) and unchanged
      )
    end)
  end

  defp protected_md5s(fx), do: Enum.map([@rows, @register], &md5(File.read!(Path.join(fx, &1))))

  # --- mutation -------------------------------------------------------------------------

  defp mutants do
    [
      {"M1", "the fresh step skipped", ~s|"fresh" => fresh_build(fresh, committed)|,
       ~s|"fresh" => %{"ok" => true}|, ~w(P3 P7 P8)},
      {"M2", "the reproduce step skipped", ~s|"reproduce" => reproduce(bytes, committed),|,
       ~s|"reproduce" => %{"ok" => true},|, ~w(P9)},
      {"M4", "every capture guard skipped", "refusals = refusals(fresh)", "refusals = []",
       ~w(FG RD3 RD7 RT1 RT3)},
      {"M6a", "a reproduce refusal read as clean",
       "defp reproduce_refused(e, cited), do: refused_or_error(e, cited)",
       ~s|defp reproduce_refused(_, _), do: %{"ok" => true, "refused" => nil}|, ~w(P11)},
      {"M6b", "a fresh-build refusal read as clean",
       "defp fresh_refused(e, cited), do: refused_or_error(e, cited)",
       ~s|defp fresh_refused(_, _), do: %{"ok" => true, "refused" => nil, "only_committed" => [], "only_fresh" => [], "changed" => []}|,
       ~w(P3 P7)},
      {"M7", "changed fields never reported", "defp changed_fields(a, b) do",
       "defp changed_fields(_, _), do: []\n  defp changed_fields(a, b) do", ~w(P8)},
      {"MP", "the register dropped from the protected list",
       "def protected, do: [RowsDrift.committed_path(), ETCCRegister.paths().register]",
       "def protected, do: [RowsDrift.committed_path()]", ~w(PR2)},
      {"MT1", "RT1 skipped: a capture of another commit accepted (R1)", "def rt1_tip(fresh) do",
       "def rt1_tip(_), do: nil\n  def rt1_tip(fresh) do", ~w(RT1 RT1m)},
      {"MT2", "RT2 skipped: a dirty tree judged (R1)", "def rt2_worktree do",
       "def rt2_worktree, do: nil\n  def rt2_worktree do", ~w(RT2)},
      {"MT3", "RT3 skipped: a capture with no suite_rc accepted (R2)",
       "def rt3_suite_rc(fresh) do", "def rt3_suite_rc(_), do: nil\n  def rt3_suite_rc(fresh) do",
       ~w(RT3)},
      {"MK", "--keep writes the formatter's raw bytes, dropping suite_rc (R2)",
       "def keep_bytes(%{} = artefact, _raw_path), do: ExUnitRows.encode(artefact)",
       "def keep_bytes(%{} = _artefact, raw_path), do: File.read!(raw_path)", ~w(K1)},
      {"MR4", "the blanket rescue restored: every exception is drift (R4)",
       "def expected_refusal?(e, cited) do",
       "def expected_refusal?(_, _), do: true\n  def expected_refusal?(e, cited) do",
       ~w(INJ1 INJ2 INJ3 INJ4 INJ5 INJ6 INJ7)},
      {"MR4f", "every File.Error read as drift again (round-1 predicate, CR R4 round 2)",
       "def expected_refusal?(e, cited) do",
       "def expected_refusal?(%File.Error{}, _), do: true\n  def expected_refusal?(e, cited) do",
       ~w(INJ3 INJ4 INJ5 INJ6 INJ7)},
      {"MR4s",
       "the in-scope filter dropped: any row's file is cited (round 2's set, CR R4 round 3)",
       "    |> Enum.filter(&in_scope?/1)\n", "", ~w(INJ6 INJ7)},
      {"MT5", "RT5 skipped: a doctest of a module outside lib/ accepted (R5)",
       "def rt5_doctests(fresh) do", "def rt5_doctests(_), do: nil\n  def rt5_doctests(fresh) do",
       ~w(RT5a RT5b RT5c RT5d)},
      {"MT5n", "RT5 falls back to name-only: the loaded definition's origin is not checked",
       "def loaded_from_lib(mod, sources) do",
       "def loaded_from_lib(mod, _), do: {:ok, mod}\n  def loaded_from_lib(mod, sources) do",
       ~w(RT5s RT5o)},
      {"MR4n", "a missing cited test source read as an instrument error, not drift",
       "%File.Error{reason: :enoent, path: path} -> MapSet.member?(cited, relative(path))",
       "%File.Error{reason: :enoent, path: _} -> false", ~w(P11)}
    ]
  end

  defp mutation(fx) do
    header("MUTATION — each one-change mutant turns red exactly the cases it names")

    plants = Map.new(plant_cases(), fn {id, _, e, f, w} -> {id, {:plant, e, f, w}} end)

    guards =
      Map.new(guard_cases(fx), fn {id, _, e, f, g, o} -> {id, {:guard, e, f, g, o}} end)

    injected =
      Map.new(injections(), fn {id, _, from, to, step, f} ->
        {id, {:inject, from, to, step, f}}
      end)

    cases =
      plants
      |> Map.merge(guards)
      |> Map.merge(injected)
      |> Map.merge(%{"PR2" => {:protected, @register}, "K1" => :keep_bytes})

    source = File.read!(Path.join(@project, @source))
    unmutated = {RegisterDrift, source}

    results =
      Enum.map(mutants(), fn {mid, what, from, to, reds} ->
        control = Enum.all?(reds, &satisfied_by?(unmutated, fx, cases[&1]))
        mutant_source = mutate(source, mid, [{from, to}])
        mutant = {compile_source(mutant_source, mid), mutant_source}
        flipped = for id <- reds, not satisfied_by?(mutant, fx, cases[id]), do: id

        check(
          mid,
          "#{what}: unmutated satisfies #{Enum.join(reds, ",")} = #{control}; mutant turns red #{inspect(flipped)}",
          control and flipped == reds
        )
      end)

    run_ids = mutants() |> Enum.map(&elem(&1, 0))

    # M3 is claimed equivalent IN VERDICT. The claim is also measured: the mutant runs on
    # every plant and guard case, and its exit status must equal the unmutated module's on
    # each. A case where they differ would refute the claim.
    m3 =
      compile_variant(source, "M3", [
        {~s|"keysets" => keysets(committed),|, ~s|"keysets" => %{"ok" => true, "differ" => []},|}
      ])

    ids =
      cases
      |> Enum.filter(fn {_, c} -> is_tuple(c) and elem(c, 0) in [:plant, :guard] end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    differ =
      for id <- ids, exit_of(RegisterDrift, fx, cases[id]) != exit_of(m3, fx, cases[id]), do: id

    m3_check =
      check(
        "M3e",
        "skip keysets: exit status equal to the unmutated module's on all #{length(ids)} plant and guard cases " <>
          "(differ on #{inspect(differ)})",
        differ == []
      )

    equivalents =
      for {id, why} <- Enum.sort(@equivalent_mutants) do
        IO.puts("  --    #{id}  EQUIVALENT, dropped (not counted as killed): #{why}")
        id
      end

    results ++
      [
        m3_check,
        check(
          "ML",
          "mutants run #{inspect(run_ids)} == advertised #{inspect(@advertised_mutants)}; " <>
            "equivalent (stated and dropped) #{inspect(equivalents)}",
          run_ids == @advertised_mutants and
            MapSet.disjoint?(MapSet.new(run_ids), MapSet.new(equivalents))
        )
      ]
  end

  defp exit_of(module, fx, {:plant, edit, fresh_fun, _}),
    do: exit_of(module, fx, edit, fresh_fun, %{})

  defp exit_of(module, fx, {:guard, edit, fresh_fun, _, opts}),
    do: exit_of(module, fx, edit, fresh_fun, opts)

  defp exit_of(module, fx, edit, fresh_fun, opts) do
    with_plant(
      fx,
      edit,
      fresh_fun,
      fn fresh -> RegisterDrift.exit_status(File.cd!(fx, fn -> module.check(fresh) end)) end,
      opts
    )
  end

  defp satisfied_by?({module, _}, fx, {:plant, edit, fresh_fun, want}) do
    with_plant(fx, edit, fresh_fun, fn fresh ->
      report = File.cd!(fx, fn -> module.check(fresh) end)
      want_exit = if want == ok_want(), do: 0, else: 1
      RegisterDrift.exit_status(report) == want_exit and satisfied?(report, want)
    end)
  end

  defp satisfied_by?({module, _}, fx, {:guard, edit, fresh_fun, g, opts}) do
    with_plant(
      fx,
      edit,
      fresh_fun,
      fn
        :missing ->
          report = File.cd!(fx, fn -> module.check(:missing) end)
          report["verdict"] == "refused" and Enum.map(report["refusals"], & &1["guard"]) == [g]

        fresh ->
          report = File.cd!(fx, fn -> module.check(fresh) end)
          report["verdict"] == "refused" and Enum.map(report["refusals"], & &1["guard"]) == [g]
      end,
      opts
    )
  end

  # The injection is applied to the module under test (unmutated or mutated) as it stands.
  defp satisfied_by?({_, source}, fx, {:inject, from, to, step, fresh_fun}) do
    variant = compile_variant(source, "INJ", [{from, to}])
    report = with_plant(fx, & &1, fresh_fun, fn f -> File.cd!(fx, fn -> variant.check(f) end) end)

    RegisterDrift.exit_status(report) == 2 and
      Enum.map(report["refusals"], &{&1["guard"], &1["side"]}) == [{"RT4", step}]
  end

  defp satisfied_by?({module, _}, fx, {:protected, target}) do
    File.cd!(fx, fn ->
      link = "docs/planted-link.json"
      :ok = File.ln_s(Path.expand(target), link)

      try do
        Enum.any?(module.protected(), &RowsDrift.same_file?(link, &1))
      after
        File.rm!(link)
      end
    end)
  end

  # R2, in-process: the bytes --keep writes for a capture whose suite exited 7 must still
  # say so, though the formatter's own file (the raw path) carries no suite_rc.
  defp satisfied_by?({module, _}, fx, :keep_bytes) do
    dir = scratch("register_drift_keep")
    raw = Path.join(dir, "rows.json")
    c = committed_rows(fx)
    File.write!(raw, ExUnitRows.encode(%{c | "run" => Map.delete(c["run"], "suite_rc")}))
    artefact = put_run(c, "suite_rc", 7)
    kept = module.keep_bytes(artefact, raw) |> Jason.decode!()
    File.rm_rf!(dir)
    get_in(kept, ["run", "suite_rc"]) == 7
  end

  # Replace each `from` (exactly once) with its `to`. Raises if a `from` is not there exactly
  # once: a mutation that cannot be applied must not read as a pass.
  defp mutate(source, mid, pairs) do
    Enum.reduce(pairs, source, fn {from, to}, acc ->
      n = acc |> String.split(from) |> length() |> Kernel.-(1)

      unless n == 1 do
        raise "CANNOT MUTATE — #{mid}'s target text occurs #{n} times in #{@source} " <>
                "(need exactly 1): #{inspect(from)}"
      end

      String.replace(acc, from, to)
    end)
  end

  defp compile_variant(source, mid, pairs),
    do: source |> mutate(mid, pairs) |> compile_source(mid)

  defp compile_source(source, mid) do
    name = "RegisterDriftMutant#{mid}#{System.unique_integer([:positive])}"

    renamed =
      Regex.replace(~r/defmodule [A-Za-z0-9.]+ do/, source, "defmodule #{name} do", global: false)

    {result, _diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(renamed) end)
    [{module, _} | _] = result
    module
  end

  # --- live -------------------------------------------------------------------------------

  defp live(fx) do
    header("LIVE — real captures of the clone: replay provenance (R1) and the suite's exit (R2)")
    dir = scratch("register_drift_live")
    k0 = Path.join(dir, "kept-head.json")
    head = git!(fx, ["rev-parse", "HEAD"])

    {report, status, last} = task(fx, ["--keep", k0], dir)
    kept = decode_file(k0)

    l1 = [
      check(
        "L1",
        "capture at #{String.slice(head, 0, 7)} -> exit #{status}; #{summary(report)}\n        #{last}",
        status == 0 and report["verdict"] == "clean"
      ),
      check(
        "L2",
        "the kept capture is the adjudicated artefact at HEAD (tip #{inspect(get_in(kept, ["run", "tip"]))}, " <>
          "suite_rc #{inspect(get_in(kept, ["run", "suite_rc"]))}, #{length(kept["rows"] || [])} rows)",
        kept["schema"] == "etcc-exunit-rows/1" and get_in(kept, ["run", "tip"]) == head and
          get_in(kept, ["run", "suite_rc"]) == 0
      )
    ]

    {r, st, la} = task(fx, ["--fresh", k0], dir)

    l3 =
      check(
        "L3",
        "positive limb: the kept capture replayed at the same clean HEAD -> exit #{st}\n        #{la}",
        st == 0 and r["verdict"] == "clean"
      )

    # R1, CR's case: keep at commit A, add a test, commit B, replay A's capture at B.
    append_describe(fx, @sse)
    git!(fx, ["add", "-A"])

    git!(fx, [
      "-c",
      "user.name=fixture",
      "-c",
      "user.email=fixture@invalid",
      "commit",
      "-q",
      "-m",
      "B"
    ])

    {r, st, la} = task(fx, ["--fresh", k0], dir)
    reset!(fx, head)

    l4 =
      refused_alone(
        "L4",
        "stale tip: A's capture replayed at B (a test appended)",
        r,
        st,
        la,
        "RT1"
      )

    # R1, dirty variant: the same append, not committed.
    append_describe(fx, @sse)
    {r, st, la} = task(fx, ["--fresh", k0], dir)
    reset!(fx, head)

    l5 =
      refused_alone(
        "L5",
        "dirty tree: the capture of HEAD replayed over an uncommitted append",
        r,
        st,
        la,
        "RT2"
      )

    # R2, CR's fixture: the suite exits 7 at exit with every row green (test_helper.exs's
    # first comment line replaced, so no line address moves).
    helper = read_lines(fx, "test/test_helper.exs")
    "#" <> _ = hd(helper)

    write_lines(fx, "test/test_helper.exs", [
      "System.at_exit(fn _ -> System.halt(7) end)" | tl(helper)
    ])

    git!(fx, ["add", "-A"])

    git!(fx, [
      "-c",
      "user.name=fixture",
      "-c",
      "user.email=fixture@invalid",
      "commit",
      "-q",
      "-m",
      "exit 7"
    ])

    k7 = Path.join(dir, "kept-exit7.json")
    {r, st, la} = task(fx, ["--keep", k7], dir)
    l6 = refused_alone("L6", "live: a suite that exits 7 with every row green", r, st, la, "RD7")
    kept7 = decode_file(k7)

    l7a =
      check(
        "L7a",
        "the kept capture carries suite_rc #{inspect(get_in(kept7, ["run", "suite_rc"]))} and " <>
          "#{Enum.count(kept7["rows"] || [], &(&1["status"] in ["failed", "invalid"]))} red rows",
        get_in(kept7, ["run", "suite_rc"]) == 7
      )

    {r, st, la} = task(fx, ["--fresh", k7], dir)
    l7 = refused_alone("L7", "replay of that kept capture", r, st, la, "RD7")

    stripped = Path.join(dir, "stripped.json")

    File.write!(
      stripped,
      ExUnitRows.encode(%{kept7 | "run" => Map.delete(kept7["run"], "suite_rc")})
    )

    {r, st, la} = task(fx, ["--fresh", stripped], dir)
    l8 = refused_alone("L8", "the same capture with suite_rc stripped by hand", r, st, la, "RT3")
    reset!(fx, head)
    File.rm_rf!(dir)

    l1 ++ [l3, l4, l5, l6, l7a, l7, l8]
  end

  # R5 on a real capture (correction round 3). Three modules OUTSIDE lib/ (test/support, so
  # compiled with docs) are doctested from one test/mcp file by CR's three legal forms: the
  # qualified call, an attribute reassigned inside `if`, and an attribute naming the module.
  # The same file doctests a lib/ module through `require ..., as:`. RT5 must refuse, naming
  # the three plants and not the lib/ module, and the capture must hold all four's units.
  defp livedoc(fx), do: livedoc_forms(fx) ++ livedoc_shadow(fx)

  # R5 round 4, CR's shadow (35761): a byte-copy of lib/'s HeaderMirror compiled from
  # conformance/cr_header_mirror.ex and loaded in place of lib's by a test_helper.exs hook.
  # Name and tag both say MCP.Protocol.HeaderMirror; only the recorded compile source tells.
  defp livedoc_shadow(fx) do
    head = git!(fx, ["rev-parse", "HEAD"])

    File.cp!(
      Path.join(fx, "lib/mcp/protocol/header_mirror.ex"),
      Path.join(fx, "conformance/cr_header_mirror.ex")
    )

    File.write!(
      Path.join(fx, "test/test_helper.exs"),
      File.read!(Path.join(fx, "test/test_helper.exs")) <>
        """

        # register_drift_controls shadow plant (MES-241 round 4): load an outside-lib definition.
        shadow = Path.expand("conformance/cr_header_mirror.ex")
        ebin = MCP.Protocol.HeaderMirror |> :code.which() |> to_string() |> Path.dirname()
        Code.put_compiler_option(:ignore_module_conflict, true)
        [{shadow_mod, shadow_bin} | _] = Code.compile_file(shadow)
        File.write!(Path.join(ebin, "Elixir.MCP.Protocol.HeaderMirror.beam"), shadow_bin)
        :code.purge(shadow_mod)
        :code.delete(shadow_mod)
        :code.purge(shadow_mod)
        {:module, ^shadow_mod} = :code.load_file(shadow_mod)
        """
    )

    git!(fx, ["add", "-A"])

    git!(fx, [
      "-c",
      "user.name=fixture",
      "-c",
      "user.email=fixture@invalid",
      "commit",
      "-q",
      "-m",
      "shadow plant"
    ])

    dir = scratch("register_drift_shadow")
    keep = Path.join(dir, "kept.json")
    {report, status, last} = task(fx, ["--keep", keep], dir)
    kept = decode_file(keep)
    reset!(fx, head)
    # The shadow beam was written into the clone's test build: drop it, so no later capture
    # in this clone reads it.
    File.rm_rf!(Path.join(fx, "_build/test/lib/mcp_elixir_sdk"))
    File.rm_rf!(dir)

    detail = report["refusals"] |> List.wrap() |> Enum.map_join(" ", & &1["detail"])
    fired = report["refusals"] |> List.wrap() |> Enum.map(& &1["guard"]) |> Enum.uniq()
    recorded = get_in(kept, ["run", "doctest_sources", "MCP.Protocol.HeaderMirror"])

    [
      check(
        "D4",
        "shadow: lib/ name, definition compiled from conformance/ -> exit #{status}; fired #{inspect(fired)}; recorded source #{inspect(recorded)}\n        #{last}",
        status == 2 and fired == ["RT5"] and is_binary(recorded) and
          String.ends_with?(recorded, "conformance/cr_header_mirror.ex") and
          String.contains?(detail, "MCP.Protocol.HeaderMirror was loaded from")
      )
    ]
  end

  defp livedoc_forms(fx) do
    header("LIVEDOC — RT5 on a real capture of CR's doctest forms (about two and a half minutes)")

    for x <- ~w(A B C) do
      File.write!(Path.join(fx, "test/support/register_drift_plant_#{String.downcase(x)}.ex"), """
      defmodule MCP.Test.RegisterDriftPlant#{x} do
        @moduledoc "A register_drift_controls plant: a module outside lib/ with a doctest."

        @doc \"""
            iex> MCP.Test.RegisterDriftPlant#{x}.one()
            1
        \"""
        def one, do: 1
      end
      """)
    end

    File.write!(Path.join(fx, "test/mcp/register_drift_plant_test.exs"), """
    defmodule MCP.RegisterDriftPlantTest do
      use ExUnit.Case, async: true
      require ExUnit.DocTest

      # Form 1: the qualified call.
      ExUnit.DocTest.doctest(MCP.Test.RegisterDriftPlantA)

      # Form 2: an attribute reassigned inside `if`; Elixir doctests the second value.
      @plant MCP.Protocol.HeaderMirror
      if true do
        @plant MCP.Test.RegisterDriftPlantB
      end

      doctest @plant

      # Form 3: an attribute naming a module outside lib/.
      @outside MCP.Test.RegisterDriftPlantC
      doctest @outside

      # A lib/ module through `require ..., as:`: must NOT be refused.
      require MCP.Protocol.Extensions, as: ExtDocs
      doctest ExtDocs
    end
    """)

    head = git!(fx, ["rev-parse", "HEAD"])
    git!(fx, ["add", "-A"])

    git!(fx, [
      "-c",
      "user.name=fixture",
      "-c",
      "user.email=fixture@invalid",
      "commit",
      "-q",
      "-m",
      "doctest plants"
    ])

    dir = scratch("register_drift_livedoc")
    keep = Path.join(dir, "kept.json")
    {report, status, last} = task(fx, ["--keep", keep], dir)
    kept = decode_file(keep)
    reset!(fx, head)
    File.rm_rf!(dir)

    detail = report["refusals"] |> List.wrap() |> Enum.map_join(" ", & &1["detail"])
    fired = report["refusals"] |> List.wrap() |> Enum.map(& &1["guard"]) |> Enum.uniq()

    plant_modules =
      for r <- kept["rows"] || [],
          r["module"] == "MCP.RegisterDriftPlantTest",
          r["test_type"] == "doctest",
          uniq: true,
          do: get_in(r, ["tags", "doctest"])

    named = for x <- ~w(A B C), String.contains?(detail, "MCP.Test.RegisterDriftPlant#{x}"), do: x

    [
      check(
        "D1",
        "capture with the three outside-lib forms -> exit #{status}; fired #{inspect(fired)}; names plants #{inspect(named)}\n        #{last}",
        status == 2 and fired == ["RT5"] and named == ~w(A B C)
      ),
      check(
        "D2",
        "the lib/ module doctested through require ..., as: is not refused (detail names Extensions: #{String.contains?(detail, "Extensions")}; HeaderMirror: #{String.contains?(detail, "HeaderMirror")})",
        not String.contains?(detail, "Extensions") and
          not String.contains?(detail, "HeaderMirror")
      ),
      check(
        "D3",
        "ExUnit ran all four forms: doctest modules in the plant file #{inspect(Enum.sort(plant_modules))}",
        Enum.sort(plant_modules) ==
          Enum.sort(
            ~w(MCP.Protocol.Extensions MCP.Test.RegisterDriftPlantA MCP.Test.RegisterDriftPlantB MCP.Test.RegisterDriftPlantC)
          )
      )
    ]
  end

  defp task(fx, args, dir) do
    j = Path.join(dir, "report-#{System.unique_integer([:positive])}.json")

    {out, status} =
      System.cmd("mix", ["conformance.register_drift", "--json", j | args],
        cd: fx,
        stderr_to_stdout: true
      )

    {decode_file(j), status, out |> String.trim_trailing() |> String.split("\n") |> List.last()}
  end

  defp refused_alone(id, what, report, status, last, g) do
    fired = report["refusals"] |> List.wrap() |> Enum.map(& &1["guard"]) |> Enum.uniq()

    check(
      id,
      "#{what} -> exit #{status}; fired #{inspect(fired)}\n        #{last}",
      status == 2 and fired == [g]
    )
  end

  defp decode_file(path),
    do: if(File.exists?(path), do: path |> File.read!() |> Jason.decode!(), else: %{})

  # --- the clone ----------------------------------------------------------------------------

  defp in_clone(fun) do
    root = scratch("register_drift_controls")
    fx = Path.join(root, "repo")

    status =
      try do
        head = git!(@project, ["rev-parse", "HEAD"])
        git!(root, ["clone", "-q", "--no-checkout", @project, fx])
        git!(fx, ["checkout", "-q", "-B", "main", head])
        for d <- ["deps", "_build"], do: File.cp_r!(Path.join(@project, d), Path.join(fx, d))
        # The app's test build is dropped so a capture recompiles it HERE: copied beams would
        # record this tree's sources, not the clone's, and RT5 reads where a doctested
        # definition was compiled from (correction round 4).
        File.rm_rf!(Path.join(fx, "_build/test/lib/mcp_elixir_sdk"))
        {_, 0} = System.cmd("mix", ["compile"], cd: fx, stderr_to_stdout: true)
        IO.puts("fixture: #{fx} at #{String.slice(head, 0, 7)}")
        verdict(fun.(fx))
      after
        File.rm_rf!(root)
      end

    if status != 0, do: System.halt(status)
  end

  defp reset!(fx, sha) do
    git!(fx, ["reset", "-q", "--hard", sha])
    git!(fx, ["clean", "-fdq"])
  end

  defp committed_rows(fx), do: fx |> Path.join(@rows) |> File.read!() |> Jason.decode!()

  # --- plumbing -------------------------------------------------------------------------------

  defp read_lines(fx, file), do: fx |> Path.join(file) |> File.read!() |> String.split("\n")
  defp write_lines(fx, file, lines), do: File.write!(Path.join(fx, file), Enum.join(lines, "\n"))

  defp index_of(lines, needle) do
    case Enum.filter(Enum.with_index(lines), fn {l, _} -> String.contains?(l, needle) end) do
      [{_, i}] -> i
      other -> raise "PLANT CANNOT BE PLACED: #{inspect(needle)} matches #{length(other)} lines"
    end
  end

  defp last_index(lines, exact),
    do:
      lines |> Enum.with_index() |> Enum.filter(&(elem(&1, 0) == exact)) |> List.last() |> elem(1)

  # The 0-based index of the first line of the test's block: its tags run up to it.
  defp block_start(lines, title) do
    i = index_of(lines, ~s(test "#{title}"))
    j = Enum.find(i..0//-1, fn k -> String.trim(Enum.at(lines, k - 1)) == "" end)
    j
  end

  defp put_run(art, k, v), do: %{art | "run" => Map.put(art["run"], k, v)}
  defp add_row(art, row), do: reseal(%{art | "rows" => art["rows"] ++ [row]})
  defp update_rows(art, fun), do: reseal(%{art | "rows" => Enum.map(art["rows"], fun)})

  defp reseal(art) do
    rows = ExUnitRows.sort_rows(art["rows"])
    %{art | "rows" => rows} |> put_run("rows_md5", ExUnitRows.rows_md5(rows))
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    String.trim(out)
  end

  defp scratch(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp md5(bin), do: :crypto.hash(:md5, bin) |> Base.encode16(case: :lower)

  defp header(t), do: IO.puts("\n== #{t} ==\n")

  defp check(id, what, ok) do
    IO.puts("  #{if ok, do: "ok  ", else: "FAIL"}  #{id}  #{what}")
    if ok, do: :ok, else: :error
  end

  defp verdict(results) do
    failed = Enum.count(results, &(&1 == :error))
    IO.puts("\n  #{length(results) - failed}/#{length(results)} as expected.")
    if failed > 0, do: 1, else: 0
  end
end

RegisterDriftControls.run(System.argv())
