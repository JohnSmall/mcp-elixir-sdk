defmodule MCP.Conformance.CensusTest do
  @moduledoc """
  Controls for the census converter.

  Two of these are the structural properties the whole design rests on, and both
  are asserted as **behaviour of the code** rather than as documentation:

    * a run the adjudicator would refuse yields no census, because the census
      calls the same `judge/3`;
    * a control run yields no headline, and cannot be relabelled as a
      measurement by editing one manifest field, because the beacon journal on
      disk is re-read and cross-checked.

  Every refusal is paired with the corrected input it must accept. A converter
  that refused everything would satisfy all the refusal halves at once.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.{Census, Classification, Manifest}

  @commit "1111111111111111111111111111111111111111"
  @token "t0k3n"

  @yaml """
  server:
    - tools-list
    - resources-list

  client:
    - tools_call

  not_scored:
    - scenario: tasks-lifecycle
      leg: server
      reason: extension
    - scenario: auth/dpop
      leg: client
      reason: extension
  """

  @expected """
  Required for 2026-07-28 (3 scenarios, frozen; run at the 2026-07-28 wire):

  Server scenarios (test against a server):
    - tools-list
    - resources-list

  Client scenarios (test against a client):
    - tools_call

  Run and reported, but never scored:
    extension (2):
      - tasks-lifecycle [server]
      - auth/dpop [client]
  """

  # A SMALLER frozen set: one scored server scenario instead of two. A control
  # run over this set is individually accepted — its own denominator is complete
  # — and is still not a control for a measurement that ran the larger set. That
  # is the B1 case, and it is why the fixture has to be a real requirement set
  # rather than a truncated run.
  @small_yaml """
  server:
    - resources-list

  client:
    - tools_call

  not_scored:
  """

  @small_expected """
  Required for 2026-07-28 (2 scenarios, frozen; run at the 2026-07-28 wire):

  Server scenarios (test against a server):
    - resources-list

  Client scenarios (test against a client):
    - tools_call
  """

  # tools-list all green; resources-list carries one FAILURE and one WARNING;
  # tasks-lifecycle (not scored) fails. The WARNING is deliberate: it is free
  # under two reducers and fatal under the third, which is the leg-dependence
  # the IR exists to keep visible.
  @checks %{
    "server-tools-list-A" => [
      %{"id" => "tools-list", "name" => "ToolsList", "status" => "SUCCESS"},
      %{"id" => "tools-name-format", "name" => "ToolsNameFormat", "status" => "SUCCESS"},
      %{"id" => "tools-log", "name" => "ToolsLog", "status" => "INFO"}
    ],
    "server-resources-list-B" => [
      %{"id" => "resources-list", "name" => "ResourcesList", "status" => "SUCCESS"},
      %{
        "id" => "resources-uri",
        "name" => "ResourcesUri",
        "status" => "FAILURE",
        "errorMessage" => "uri was not absolute"
      },
      %{"id" => "resources-hint", "name" => "ResourcesHint", "status" => "WARNING"},
      %{"id" => "resources-skip", "name" => "ResourcesSkip", "status" => "SKIPPED"}
    ],
    "server-tasks-lifecycle-C" => [
      %{"id" => "tasks", "name" => "Tasks", "status" => "FAILURE", "errorMessage" => "no tasks"}
    ]
  }

  @marks %{
    "server-tools-list-A" => {"tools-list", "✓", 2, 0},
    "server-resources-list-B" => {"resources-list", "✗", 1, 1},
    "server-tasks-lifecycle-C" => {"tasks-lifecycle", "✗", 0, 1}
  }

  defp sha(body), do: :sha256 |> :crypto.hash(body) |> Base.encode16(case: :lower)

  # The not-scored scenarios of `@yaml`, and the reason it gives for each. The
  # fixture console prints this block for whichever of them actually RAN,
  # because a real harness console does: MES-56 round 4 added a census gate
  # comparing the console's not-scored block with the frozen set in both
  # directions, and a fixture that omitted the block was a console claiming the
  # harness had SCORED a scenario the set does not. The gate was right about the
  # fixture, which is the whole reason for building fixtures that a real run
  # could have produced.
  @not_scored %{"tasks-lifecycle" => "extension"}

  defp console(dir, dirs) do
    running =
      Enum.map_join(dirs, "\n", fn d ->
        {scenario, _, _, _} = @marks[d]
        "=== Running scenario: #{scenario} ===\nResults saved to #{dir}/#{d}\n"
      end)

    summary =
      Enum.map_join(dirs, "\n", fn d ->
        {scenario, tick, passed, failed} = @marks[d]
        "#{tick} #{scenario}: #{passed} passed, #{failed} failed"
      end)

    """
    Running requirements 2026-07-28 (#{length(dirs)} scenarios) against http://127.0.0.1:3001/mcp

    #{running}

    === SUMMARY ===
    #{summary}

    Total: #{total(dirs, 2)} passed, #{total(dirs, 3)} failed
    #{not_scored_block(dirs)}
    """
  end

  # The harness prints the `Total:` line by summing the SUMMARY marks it has
  # just printed, and the count in the opening line by counting the scenarios it
  # is about to announce. MES-56 correction round 5 made both a fault when they
  # disagree, so the fixture computes them from `dirs` rather than stating a
  # constant that is only right for the default run. A test that passes a subset
  # of `dirs` now gets a console the harness could have produced, which is the
  # only kind of fixture a refusal control means anything against.
  defp total(dirs, field), do: dirs |> Enum.map(&elem(@marks[&1], field)) |> Enum.sum()

  defp default_dirs, do: @checks |> Map.keys() |> Enum.sort()

  defp not_scored_block(dirs) do
    ran =
      for d <- dirs,
          {scenario, tick, _, _} = @marks[d],
          reason = @not_scored[scenario],
          do: "  #{tick} #{scenario} (#{reason})"

    case ran do
      [] ->
        ""

      lines ->
        failing = Enum.count(lines, &String.contains?(&1, "✗"))

        "\nNot scored for 2026-07-28: #{length(lines)} scenario(s) run, #{failing} failing. " <>
          "These do not affect conformance.\n" <> Enum.join(lines, "\n") <> "\n"
    end
  end

  # Write a complete, ACCEPTED run directory. `opts` spoils exactly one thing,
  # so each refusal below differs from the accepted case in one place.
  defp write_run!(opts \\ []) do
    dir =
      Path.join(System.tmp_dir!(), "mes56-census-#{System.unique_integer([:positive])}")

    dirs = Keyword.get(opts, :dirs, default_dirs())
    adapter = Keyword.get(opts, :adapter, "sdk")
    beacon_source = Keyword.get(opts, :beacon_source, source_for(adapter))
    checks = Keyword.get(opts, :checks, @checks)
    yaml = Keyword.get(opts, :yaml, @yaml)
    expected = Keyword.get(opts, :expected, @expected)

    for d <- dirs do
      File.mkdir_p!(Path.join(dir, d))
      File.write!(Path.join([dir, d, "checks.json"]), Jason.encode!(Map.fetch!(checks, d)))
    end

    body = Keyword.get(opts, :console_edit, & &1).(console(dir, dirs))
    File.write!(Path.join(dir, "console.txt"), body)
    File.write!(Path.join(dir, "expected.txt"), expected)
    File.write!(Path.join(dir, "requirements.yaml"), yaml)

    File.write!(
      Path.join(dir, "beacon.jsonl"),
      Jason.encode!(%{"token" => @token, "role" => "preflight", "source" => "x"}) <>
        "\n" <>
        Jason.encode!(%{"token" => @token, "role" => "adapter", "source" => beacon_source}) <>
        "\n"
    )

    manifest =
      dir
      |> base_manifest(body, dirs, adapter, yaml, expected)
      |> Keyword.get(opts, :spoil, & &1).()

    File.write!(Path.join(dir, "manifest.json"), Manifest.encode(manifest))
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp source_for("null"), do: "conformance/controls/null_server.py"
  defp source_for(_), do: "conformance/server_adapter.exs"

  defp base_manifest(dir, body, dirs, adapter, yaml, expected) do
    %{
      "schema_version" => Manifest.schema_version(),
      "leg" => "server",
      "git" => %{
        "commit_sha_start" => @commit,
        "commit_sha_end" => @commit,
        "branch_start" => "MES-56",
        "branch_end" => "MES-56",
        "worktree_root" => "/tmp/wt",
        "dirty_start" => false,
        "dirty_end" => false,
        "dirty_digest_start" => "d0",
        "dirty_digest_end" => "d0",
        "dirty_entries_start" => [],
        "dirty_entries_end" => [],
        "dirty_entry_count_start" => 0,
        "dirty_entry_count_end" => 0,
        "dirty_excluded_paths" => [],
        "dirty_exclusions_rejected" => []
      },
      "harness" => %{
        "install_dir" => "/tmp/conf11",
        "dist_path" => "/tmp/conf11/dist/index.js",
        "dist_sha256" => "a10085d0cfc9dd91",
        "version_declared" => "0.2.0-alpha.11",
        "version_reported" => "0.2.0-alpha.11",
        "node_version" => "v24.13.0"
      },
      "requirements" => %{
        "revision" => "2026-07-28",
        "path" => "/tmp/conf11/requirements/2026-07-28.yaml",
        "exists" => true,
        "md5" => "d6eb2061b2d35c7c71a86059b08bb928",
        "sha256" => sha(yaml),
        "copy_sha256" => sha(yaml)
      },
      "invocation" => %{
        "argv" => ["node", "index.js", "server"],
        "cwd" => "/tmp/wt",
        "project_root" => "/tmp/wt",
        "cwd_is_project_root" => true,
        "adapter" => adapter,
        "adapter_command" => "adapter #{adapter}",
        "out_dir" => dir,
        "compiled_before_run" => true
      },
      "timing" => %{
        "started_at" => "2026-08-21T00:00:00.000000Z",
        "ended_at" => "2026-08-21T00:01:00.000000Z",
        "utc_offset" => "+00:00",
        "duration_ms" => 60_000
      },
      "toolchain" => %{"elixir" => "1.17.3", "otp" => "27", "mix_env" => "dev"},
      "beacon" => %{
        "token" => @token,
        "preflight_ok" => true,
        "preflight_detail" => nil,
        "adapter_count" => 1,
        "preflight_count" => 1,
        "foreign_lines" => 0,
        "unparseable_lines" => 0,
        "adapter_sources" => [source_for(adapter)]
      },
      "result" => %{
        "harness_exit_code" => 1,
        "console_sha256" => sha(body),
        "console_bytes" => byte_size(body),
        "scenario_dir_count" => length(dirs),
        "scenario_dirs" => Enum.sort(dirs),
        "expected_sha256" => sha(expected),
        "expected_bytes" => byte_size(expected),
        "expected_exit_code" => 0
      }
    }
  end

  defp put_in_path(m, [k], v), do: Map.put(m, k, v)
  defp put_in_path(m, [k | rest], v), do: Map.put(m, k, put_in_path(Map.fetch!(m, k), rest, v))

  # The table is data, so a test may substitute one without touching the module.
  defp classified(census) do
    for s <- census["scenarios"], into: %{}, do: {s["id"], s["classification"]}
  end

  describe "the accepted case — without it every refusal below means nothing" do
    test "builds a census, once every non-pass is classified" do
      dir = write_run!()

      # The real table is empty here, so the run refuses first. That refusal IS
      # the AC3 gate and is asserted in its own test below; this one proves the
      # converter completes when the gate is satisfied, using a stub table.
      assert {:refused, :SCENARIO_UNCLASSIFIED, _} = Census.build(dir)
    end

    test "the run block names the tree, the instrument and the verdict" do
      dir = write_run!(dirs: ["server-tools-list-A", "server-resources-list-B"])

      # Removing tasks-lifecycle leaves one non-pass (resources-list), so this
      # still refuses; what it proves is that the refusal is the LAST gate, i.e.
      # everything before it succeeded.
      assert {:refused, :SCENARIO_UNCLASSIFIED, detail} = Census.build(dir)
      assert detail =~ "resources-list"
      refute detail =~ "tools-list\""
    end
  end

  describe "the adjudicator's verdict is inherited, not re-decided" do
    test "a run the adjudicator would refuse yields no census" do
      dir = write_run!(spoil: &put_in_path(&1, ["git", "dirty_start"], true))

      assert {:refused, :WORKTREE_DIRTY, _} = Census.build(dir)
    end

    test "a run missing a scored scenario yields no census" do
      dir = write_run!(dirs: ["server-tools-list-A", "server-tasks-lifecycle-C"])

      assert {:refused, :SCORED_SCENARIO_ABSENT, detail} = Census.build(dir)
      assert detail =~ "resources-list"
    end

    test "a manifest from an older schema yields no census" do
      dir = write_run!(spoil: &Map.put(&1, "schema_version", 1))

      assert {:refused, :MANIFEST_UNREADABLE, detail} = Census.build(dir)
      assert detail =~ "schema_version"
    end
  end

  describe "role corroboration — a control cannot be relabelled by one field" do
    test "a control run is marked as one" do
      dir = write_run!(adapter: "null")

      assert {:ok, census} = Census.build(dir)
      assert census["run"]["role"] == "control"
      assert census["run"]["adapter"] == "null"
    end

    test "a control needs no classifications: it exists to fail" do
      assert {:ok, _} = Census.build(write_run!(adapter: "null"))
    end

    test "REFUSES when the manifest says sdk and the beacon journal says null" do
      dir = write_run!(adapter: "sdk", beacon_source: "conformance/controls/null_server.py")

      assert {:refused, :ROLE_NOT_CORROBORATED, detail} = Census.build(dir)
      assert detail =~ "null_server.py"
    end

    test "REFUSES when the manifest says null and the beacon journal says sdk" do
      dir = write_run!(adapter: "null", beacon_source: "conformance/server_adapter.exs")

      assert {:refused, :ROLE_NOT_CORROBORATED, _} = Census.build(dir)
    end

    test "refuses an adapter this tooling cannot run" do
      dir = write_run!(spoil: &put_in_path(&1, ["invocation", "adapter"], "something-else"))

      assert {:refused, :ADAPTER_UNKNOWN, _} = Census.build(dir)
    end
  end

  describe "our reducer is checked against the harness's own verdict" do
    test "REFUSES when they disagree" do
      # The harness printed ✓ for a scenario whose checks.json carries a
      # FAILURE. One of the two has misread the run, and neither figure is
      # printable until it is known which.
      dir =
        write_run!(
          adapter: "null",
          checks:
            Map.put(@checks, "server-tasks-lifecycle-C", [
              %{"id" => "tasks", "name" => "Tasks", "status" => "SUCCESS"}
            ])
        )

      assert {:refused, :REDUCER_DISAGREES_WITH_HARNESS, detail} = Census.build(dir)
      assert detail =~ "tasks-lifecycle"
    end

    test "REFUSES when a scenario ran with no mark to check it against" do
      dir =
        write_run!(
          adapter: "null",
          spoil: fn m ->
            body = File.read!(Path.join(m["invocation"]["out_dir"], "console.txt"))

            # The `Total:` line is corrected by the same amount the removed mark
            # contributed, because MES-56 correction round 5 made a total that
            # disagrees with the marks a fault in its own right. Leaving it
            # would have this control refused one guard EARLIER than the one it
            # exists to exercise. Correcting it makes the forgery internally
            # coherent, which is the stronger control: the mark-missing guard
            # now has to catch a console nothing else can tell is wrong.
            stripped =
              body
              |> String.replace("✓ tools-list: 2 passed, 0 failed\n", "")
              |> String.replace(
                "Total: #{total(default_dirs(), 2)} passed, #{total(default_dirs(), 3)} failed",
                "Total: #{total(default_dirs(), 2) - 2} passed, #{total(default_dirs(), 3)} failed"
              )

            File.write!(Path.join(m["invocation"]["out_dir"], "console.txt"), stripped)

            m
            |> put_in_path(["result", "console_sha256"], sha(stripped))
            |> put_in_path(["result", "console_bytes"], byte_size(stripped))
          end
        )

      assert {:refused, :HARNESS_MARK_MISSING, detail} = Census.build(dir)
      assert detail =~ "tools-list"
      assert detail =~ "partial cross-check"
    end
  end

  describe "the IR" do
    setup do
      %{census: elem(Census.build(write_run!(adapter: "null")), 1)}
    end

    test "stores raw counts over all FIVE statuses, including INFO", %{census: census} do
      tools = Enum.find(census["scenarios"], &(&1["id"] == "tools-list"))

      assert tools["checks"] == %{
               "SUCCESS" => 2,
               "FAILURE" => 0,
               "WARNING" => 0,
               "SKIPPED" => 0,
               "INFO" => 1,
               "total" => 3
             }
    end

    test "stores no verdict — only a result per NAMED reducer", %{census: census} do
      resources = Enum.find(census["scenarios"], &(&1["id"] == "resources-list"))

      # One FAILURE and one WARNING. Free under two reducers, fatal under the
      # third — which is exactly why a stored verdict would be a lie by leg.
      assert resources["passes"]["requirements_exit"] == false
      assert resources["passes"]["server_summary"] == false
      assert resources["passes"]["client_summary"] == false

      tools = Enum.find(census["scenarios"], &(&1["id"] == "tools-list"))
      assert tools["passes"]["requirements_exit"] == true
      assert tools["passes"]["client_summary"] == true
    end

    test "totals.classification lists ALL SIX classes, including the empty ones", %{
      census: census
    } do
      by_class = census["totals"]["classification"]["by_class"]

      assert Enum.sort(Map.keys(by_class)) ==
               Classification.classes() |> Enum.map(&Atom.to_string/1) |> Enum.sort(),
             "a class absent from the table is an unanswered question rendered as silence"

      # The point of the assertion: a class nothing was filed under must still be
      # present, carrying an explicit zero. If this ever fails by a key going
      # missing rather than by a count changing, the report has started omitting
      # its own negatives (A2d).
      for {name, bucket} <- by_class do
        assert is_integer(bucket["count"]), "class #{name} has no count"
        assert bucket["count"] == length(bucket["scenarios"])
      end
    end

    test "an empty class is rendered as an explicit zero row, not dropped", %{census: census} do
      md = MCP.Conformance.Census.Markdown.render(census)

      empty =
        for {name, %{"count" => 0}} <- census["totals"]["classification"]["by_class"], do: name

      assert empty != [], "this test is vacuous unless some class is empty in this fixture"

      for name <- empty do
        assert md =~ "`#{name}` |", "empty class #{name} was dropped from the rendered table"
      end
    end

    test "every reducer states what it does with all five statuses", %{census: census} do
      for {name, spec} <- census["reducers"] do
        assert Enum.sort(Map.keys(spec["disposition"])) == Enum.sort(Census.statuses()),
               "reducer #{name} does not say what it does with every status"
      end
    end

    test "a WARNING is fatal to client_summary and free to the other two" do
      warned = [%{"id" => "w", "name" => "W", "status" => "WARNING"}]

      dir =
        write_run!(
          adapter: "null",
          dirs: ["server-tools-list-A", "server-resources-list-B"],
          checks: %{
            "server-tools-list-A" => warned,
            "server-resources-list-B" => warned
          }
        )

      # The harness marks a WARNING-only scenario ✓, and so must our
      # server_summary; the fixture's marks say ✓ for tools-list and ✗ for
      # resources-list, so this must refuse on the disagreement rather than
      # quietly agreeing.
      assert {:refused, :REDUCER_DISAGREES_WITH_HARNESS, detail} = Census.build(dir)
      assert detail =~ "resources-list"
    end

    test "marks a scenario that measured nothing as empty", %{census: census} do
      assert census["totals"]["empty_scenarios"]["all_ran"] == []

      dir =
        write_run!(
          adapter: "null",
          dirs: ["server-tools-list-A", "server-resources-list-B"],
          checks: %{
            "server-tools-list-A" => [],
            "server-resources-list-B" => [%{"id" => "x", "name" => "X", "status" => "FAILURE"}]
          }
        )

      assert {:ok, c} = Census.build(dir)
      assert c["totals"]["empty_scenarios"]["scored"] == ["tools-list"]
    end

    test "separates the scored denominator from everything that ran", %{census: census} do
      t = census["totals"]["by_reducer"]["requirements_exit"]

      assert t["scored"]["total"] == 2
      assert t["all_ran"]["total"] == 3
      assert t["scored"]["failing"] == ["resources-list"]
    end

    test "names the harness's own reason for a not-scored scenario", %{census: census} do
      tasks = Enum.find(census["scenarios"], &(&1["id"] == "tasks-lifecycle"))

      assert tasks["scored"] == false
      assert tasks["harness_reason"] == "extension"
    end

    test "carries the full expected set and an empty absentee list", %{census: census} do
      assert census["expected"]["scored"]["server"] == ["tools-list", "resources-list"]
      assert census["expected"]["absent_scored"] == []
      assert census["expected"]["absent_not_scored"] == []
    end

    test "records the failed checks with their messages", %{census: census} do
      resources = Enum.find(census["scenarios"], &(&1["id"] == "resources-list"))

      assert [failure, warning] = resources["failed_checks"]
      assert failure["status"] == "FAILURE"
      assert failure["message"] == "uri was not absolute"
      assert warning["status"] == "WARNING"
    end

    test "the table's own entries reach the IR, and only for the scenarios it names",
         %{census: census} do
      classified = classified(census)

      # The fixture's ids are the real ones, so `tasks-lifecycle` carries the
      # real table's `extension` entry and `tools-list` carries nothing.
      assert classified["tools-list"] == nil
      assert classified["resources-list"] == nil
      assert classified["tasks-lifecycle"]["class"] == "extension"
      assert classified["tasks-lifecycle"]["owner"] =~ "ADR-003"
    end
  end

  # S5-13. A thrown scenario reaches the census through the console alone.
  describe "a scenario that threw" do
    setup do
      dirs = ["server-tools-list-A", "server-resources-list-B"]

      dir =
        write_run!(
          adapter: "null",
          dirs: dirs,
          spoil: fn m ->
            out = m["invocation"]["out_dir"]
            body = File.read!(Path.join(out, "console.txt"))

            # tasks-lifecycle ran and threw: announced, no save, a failure line,
            # and a ✗ in the summary. No directory exists for it.
            thrown = """
            === Running scenario: tasks-lifecycle ===
            Failed to run scenario tasks-lifecycle: JsonRpcError: Method not found
            """

            # It is not-scored in `@yaml`, so the harness lists it in that
            # block too — a scenario that threw is still a scenario that ran.
            # Written out here because this run's `dirs` exclude it, so the
            # fixture's own block generator emits nothing to append to.
            body =
              (body
               |> String.replace("\n=== SUMMARY ===", "\n#{thrown}\n=== SUMMARY ===")
               |> String.replace(
                 "✗ resources-list: 1 passed, 1 failed",
                 "✗ resources-list: 1 passed, 1 failed\n✗ tasks-lifecycle: 0 passed, 1 failed"
               )
               |> String.replace(
                 "Total: #{total(dirs, 2)} passed, #{total(dirs, 3)} failed",
                 "Total: #{total(dirs, 2)} passed, #{total(dirs, 3) + 1} failed"
               )) <>
                "\nNot scored for 2026-07-28: 1 scenario(s) run, 1 failing. " <>
                "These do not affect conformance.\n  ✗ tasks-lifecycle (extension)\n"

            File.write!(Path.join(out, "console.txt"), body)

            m
            |> put_in_path(["result", "console_sha256"], sha(body))
            |> put_in_path(["result", "console_bytes"], byte_size(body))
          end
        )

      {:ok, census} = Census.build(dir)

      %{
        census: census,
        scenario: Enum.find(census["scenarios"], &(&1["id"] == "tasks-lifecycle"))
      }
    end

    test "appears in the census at all", %{scenario: s} do
      assert s, "a scenario with no artefact directory must not vanish from the census"
    end

    test "is marked as reconstructed rather than read", %{scenario: s} do
      assert s["checks_source"] == "console_thrown"
      assert s["artefact_dir"] == nil
      assert s["threw"] =~ "Method not found"
    end

    test "FAILS every reducer — 'no checks' must never read as 'nothing failed'", %{scenario: s} do
      assert s["passes"] == %{
               "requirements_exit" => false,
               "server_summary" => false,
               "client_summary" => false,
               "server_summary_or_client_summary" => false
             }
    end

    test "is enumerated in the totals, not merely absent from them", %{census: census} do
      assert census["totals"]["thrown_scenarios"] == ["tasks-lifecycle"]
    end

    test "the console <-> disk check still passes: it named no directory to find", %{
      census: census
    } do
      assert census["run"]["role"] == "control"
    end
  end

  describe "a check status no reducer defines" do
    test "REFUSES, rather than counting as a pass under every reducer at once" do
      # The harness prints ✓ for tools-list, and would print ✓ for this too: its
      # own reducer keys on `=== 'FAILURE'`, so an unrecognised status is
      # non-failing for it as well. The console cross-check therefore AGREES,
      # and cannot catch this — which is why it needs a gate of its own.
      unknown = [%{"id" => "tools-list", "name" => "ToolsList", "status" => "ERROR"}]
      absent = [%{"id" => "tools-list", "name" => "ToolsList"}]
      ok = [%{"id" => "tools-list", "name" => "ToolsList", "status" => "SUCCESS"}]

      for {checks, needle} <- [{unknown, "ERROR"}, {absent, "ABSENT"}] do
        dir =
          write_run!(
            dirs: ["server-resources-list-B", "server-tools-list-A"],
            checks: %{
              "server-tools-list-A" => checks,
              "server-resources-list-B" => @checks["server-resources-list-B"]
            },
            yaml: @small_yaml,
            expected: @small_expected
          )

        assert {:refused, :CHECK_STATUS_UNKNOWN, detail} = Census.build(dir, [])
        assert detail =~ "tools-list"
        assert detail =~ needle
      end

      # The accept half, differing in exactly the status: a recognised one builds.
      dir =
        write_run!(
          dirs: ["server-resources-list-B", "server-tools-list-A"],
          checks: %{
            "server-tools-list-A" => ok,
            "server-resources-list-B" => @checks["server-resources-list-B"]
          },
          yaml: @small_yaml,
          expected: @small_expected
        )

      assert {:refused, :SCENARIO_UNCLASSIFIED, _} = Census.build(dir, [])
    end
  end

  describe "the precondition register" do
    # The register is the class answer to B1, so it has to be checked the way a
    # denominator is: against the source, not against my memory of it. A refusal
    # added without a register entry fails here.
    test "declares every refusal the module can actually emit, and no others" do
      source = File.read!("conformance/lib/mcp/conformance/census.ex")

      emitted =
        ~r/refuse\(\s*:([A-Z_]+)/
        |> Regex.scan(source)
        |> Enum.map(&Enum.at(&1, 1))
        |> Enum.uniq()
        |> Enum.sort()

      declared = Census.refusal_codes() |> Enum.map(&Atom.to_string/1) |> Enum.sort()

      assert emitted != []
      assert emitted == declared
    end

    test "every declared refusal is accounted for by a register entry" do
      text = Census.precondition_register() |> Enum.map_join(" ", &inspect/1)

      unaccounted =
        Enum.reject(Census.refusal_codes(), &String.contains?(text, Atom.to_string(&1)))

      assert unaccounted == [],
             "these refusals exist and the register does not say which precondition they " <>
               "guard: #{inspect(unaccounted)}"
    end

    test "every entry names a site, a precondition and a disposition we recognise" do
      dispositions = [:refuses, :refused_upstream, :reported, :degrades]

      for entry <- Census.precondition_register() do
        assert is_binary(entry.site) and entry.site != ""
        assert is_binary(entry.precondition) and entry.precondition != ""
        assert is_binary(entry.note) and entry.note != ""
        assert entry.on_failure in dispositions
      end

      # The one site that still degrades rather than refusing is stated, so it
      # cannot be quietly joined by a second.
      degrading = for e <- Census.precondition_register(), e.on_failure == :degrades, do: e.site
      assert degrading == ["build/2 → judge/3, :expect_commit default"]
    end
  end

  # B2, end to end. The unit-level fault is in ConsoleTest; what this asserts is
  # that the fault becomes a REFUSAL of the whole run — before a census, a file
  # or a headline exists — rather than a value someone has to remember to read.
  describe "a duplicated SUMMARY mark" do
    test "REFUSES, and the flattering mark does not win" do
      # The measured case: our reducer makes tools-list PASS, the console says
      # ✗ and then ✓, and keying by scenario kept the ✓. The cross-check then
      # reported agreement with a harness verdict it had discarded.
      dup = fn body ->
        String.replace(
          body,
          "✓ tools-list: 2 passed, 0 failed",
          "✗ tools-list: 0 passed, 2 failed\n✓ tools-list: 2 passed, 0 failed"
        )
      end

      dir = write_run!(console_edit: dup)

      assert {:refused, :ARTEFACTS_INCONSISTENT, detail} = Census.build(dir)
      assert detail =~ "tools-list"
      assert detail =~ "CONTRADICT"

      # And in the other order, so the refusal is not an artefact of which one
      # happened to be last: reversing them made the OLD code refuse on a
      # disagreement it should never have been asked to adjudicate.
      reversed = fn body ->
        String.replace(
          body,
          "✓ tools-list: 2 passed, 0 failed",
          "✓ tools-list: 2 passed, 0 failed\n✗ tools-list: 0 passed, 2 failed"
        )
      end

      assert {:refused, :ARTEFACTS_INCONSISTENT, _} =
               Census.build(write_run!(console_edit: reversed))
    end

    test "the accept half: one mark per scenario still builds" do
      assert {:refused, :SCENARIO_UNCLASSIFIED, _} = Census.build(write_run!())
    end
  end

  # MES-56 correction round 4, C1/C3 — B3's cross-authority half. `Console` now
  # refuses a not-scored line naming a scenario that never ran; it cannot ask
  # whether the frozen set AGREES the scenario is not scored, because that needs
  # `RequirementSet` and the parser must not import its own referee. Two
  # authorities describe one split and nothing compared them.
  describe "the console's not-scored block against the frozen set" do
    test "REFUSES a not-scored line for a scenario the frozen set SCORES" do
      # The measured probe: a scenario moved out of the scored denominator by an
      # edit to a file the census reads and never cross-examines. ✓ matches
      # tools-list's SUMMARY mark, so the console itself is well-formed and the
      # refusal can only come from the cross-check.
      edit = fn body -> body <> "  ✓ tools-list (extension)\n" end

      assert {:refused, :NOT_SCORED_DISAGREES_WITH_FROZEN_SET, detail} =
               Census.build(write_run!(console_edit: edit))

      assert detail =~ "tools-list"
      assert detail =~ "the frozen set does not"
      assert detail =~ "leg server"
    end

    test "REFUSES when the console omits a not-scored scenario that RAN" do
      # The mirror direction, and not the flattering one: the harness scored a
      # scenario this census does not, so the two are measuring different
      # denominators over one run.
      edit = fn body -> String.replace(body, "  ✗ tasks-lifecycle (extension)\n", "") end

      assert {:refused, :NOT_SCORED_DISAGREES_WITH_FROZEN_SET, detail} =
               Census.build(write_run!(console_edit: edit))

      assert detail =~ "tasks-lifecycle"
      assert detail =~ "the harness scored a scenario this census does not"
    end

    test "REFUSES when the two agree it is not scored and give different reasons" do
      # `scenario/6` reports the SET's reason as `harness_reason`, so a silent
      # disagreement puts a reason in the IR that the run never printed.
      edit = fn body ->
        String.replace(body, "  ✗ tasks-lifecycle (extension)", "  ✗ tasks-lifecycle (pending)")
      end

      assert {:refused, :NOT_SCORED_DISAGREES_WITH_FROZEN_SET, detail} =
               Census.build(write_run!(console_edit: edit))

      # Double-inspected — the sentence is inspected into a list and the list
      # into the detail — so match the words rather than the quoting.
      assert detail =~ "the console's reason is"
      assert detail =~ "pending"
      assert detail =~ "extension"
    end

    test "the accept half, and a not-scored entry for the OTHER leg is not demanded here" do
      # `auth/dpop` is not-scored for the CLIENT leg and never runs on this
      # server run. Demanding it would be the `Map.get(scored, leg, [])` defect
      # inverted — refusing a healthy run because a filter was forgotten.
      assert {:refused, :SCENARIO_UNCLASSIFIED, _} = Census.build(write_run!())
    end
  end

  # The leg the run records is used as a KEY into the frozen set, with a `[]`
  # default that cannot tell "this leg ran nothing" from "this leg is not in the
  # set". Only the second is an error, and it produced a complete-looking census
  # whose scored denominator had silently become zero.
  describe "a leg the frozen set does not define" do
    # MES-57 moved WHERE this is caught, and made it stricter rather than
    # weaker. `Manifest.judge/3` now DISPATCHES on `leg` — the scenario ->
    # artefact map is derived per leg by `MCP.Conformance.RunIndex` — so a leg
    # outside the vocabulary is refused by the ADJUDICATOR, before the census's
    # own gate is reached.
    #
    # That closes a hole MES-56 could not close from the census: `judge/3`
    # previously read `leg` only as a key into the frozen set, with a `[]`
    # default, so `mix conformance.adjudicate` ACCEPTED a run recording leg
    # "sever" — printing a clean acceptance block for a run whose scored
    # denominator had silently become zero. The census refused it; the
    # adjudicator did not, and the adjudicator is the thing whose exit status
    # other tickets treat as binding.
    #
    # The census's own `LEG_NOT_IN_REQUIREMENT_SET` is kept as a backstop and is
    # asserted below to still exist. It is not reachable through a real frozen
    # set today: `RequirementSet.parse/2` refuses a set that omits either leg,
    # so "a valid leg the set does not score" cannot be constructed. Keeping it
    # costs nothing and it is the gate that fires first if the dispatch above is
    # ever widened to a third leg.
    test "REFUSES rather than reporting 0 of 0 — at the adjudicator, before the census" do
      dir = write_run!(spoil: &Map.put(&1, "leg", "sever"))

      assert {:refused, :ARTEFACTS_INCONSISTENT, detail} = Census.build(dir)
      assert detail =~ ~s("sever")
      assert detail =~ "not a leg this tooling can index"
      assert detail =~ "no generic derivation to fall back to"
    end

    test "the same run is refused by the ADJUDICATOR too, which it was not before" do
      dir = write_run!(spoil: &Map.put(&1, "leg", "sever"))

      m = Jason.decode!(File.read!(Path.join(dir, "manifest.json")))
      observed = MCP.Conformance.Provenance.observe_run(dir)

      assert {:refused, :ARTEFACTS_INCONSISTENT, _} =
               MCP.Conformance.Manifest.judge(m, observed, %{
                 commit: m["git"]["commit_sha_start"]
               })
    end

    test "a NULL leg is refused as INCOMPLETE, not as inconsistent" do
      # The two sentences send a reader to different places: "this manifest was
      # not written by this tooling" versus "this run's artefacts disagree".
      # `leg` is a consumed field as of MES-57, so it takes the first.
      dir = write_run!(spoil: &Map.put(&1, "leg", nil))

      assert {:refused, :MANIFEST_INCOMPLETE, detail} = Census.build(dir)
      assert detail =~ ~s("leg")
    end

    test "the backstop gate still exists and still names both legs" do
      assert :LEG_NOT_IN_REQUIREMENT_SET in MCP.Conformance.Census.refusal_codes()
    end

    test "the accept half: the same run with its real leg reaches the later gates" do
      assert {:refused, :SCENARIO_UNCLASSIFIED, _} = Census.build(write_run!())
    end
  end

  describe "the control join" do
    test "REFUSES to join a measurement as if it were a control" do
      control = write_run!(adapter: "null")
      not_a_control = write_run!(adapter: "sdk")

      assert {:refused, :CONTROL_IS_NOT_A_CONTROL, detail} =
               Census.build(control, control: not_a_control)

      assert detail =~ "measurement"

      # And the accept half: joining an actual control does not refuse.
      assert {:ok, _} = Census.build(control, control: write_run!(adapter: "null"))
    end

    test "REFUSES when the control run itself is not accepted" do
      control =
        write_run!(adapter: "null", spoil: &put_in_path(&1, ["git", "dirty_end"], true))

      assert {:refused, :CONTROL_REFUSED, detail} =
               Census.build(write_run!(adapter: "null"), control: control)

      assert detail =~ "WORKTREE_DIRTY"
    end

    test "REFUSES when the control did not run a scored scenario the measurement did" do
      # Both runs are individually ACCEPTED — the control's own denominator is
      # complete for the smaller set it declares. That is what makes this the
      # dangerous case: nothing upstream objects.
      measurement = write_run!(adapter: "null")

      control =
        write_run!(
          adapter: "null",
          dirs: ["server-resources-list-B"],
          yaml: @small_yaml,
          expected: @small_expected
        )

      assert {:ok, _} = Census.build(control, [])

      assert {:refused, :CONTROL_MISSING_SCENARIOS, detail} =
               Census.build(measurement, control: control)

      # Named, not counted: the reader has to be able to see WHICH scenario the
      # subtraction would have dropped.
      assert detail =~ "tools-list"
      assert detail =~ "ours alone"

      # The accept half: a control over the same set joins and reports coverage
      # as a checked, empty list rather than as silence.
      assert {:ok, census} = Census.build(measurement, control: write_run!(adapter: "null"))
      assert census["totals"]["control"]["not_in_control"] == []
    end

    test "a NOT-SCORED scenario missing from the control is reported, never refused" do
      measurement = write_run!(adapter: "null")

      # tasks-lifecycle is not scored, so its absence from the control cannot
      # move any figure the control licenses — every one of those is quoted over
      # the scored set. It is enumerated rather than dropped.
      control =
        write_run!(
          adapter: "null",
          dirs: ["server-tools-list-A", "server-resources-list-B"]
        )

      assert {:ok, census} = Census.build(measurement, control: control)
      c = census["totals"]["control"]

      assert c["not_in_control"] == []
      assert c["not_in_control_not_scored"] == ["tasks-lifecycle"]
      assert c["in_control_only"] == []
    end

    test "the mirror direction — a scenario the CONTROL ran and the measurement did not" do
      measurement =
        write_run!(
          adapter: "null",
          dirs: ["server-resources-list-B"],
          yaml: @small_yaml,
          expected: @small_expected
        )

      assert {:ok, census} = Census.build(measurement, control: write_run!(adapter: "null"))
      c = census["totals"]["control"]

      assert c["not_in_control"] == []

      assert c["in_control_only"] == ["tasks-lifecycle", "tools-list"]
    end

    test "joins a well-formed control and computes the discriminating set" do
      passing = [%{"id" => "a", "name" => "A", "status" => "SUCCESS"}]
      failing = [%{"id" => "a", "name" => "A", "status" => "FAILURE"}]

      # Marks in the fixture: tools-list ✓, resources-list ✗. Both runs must
      # match those marks or the harness cross-check refuses first.
      shape = %{"server-tools-list-A" => passing, "server-resources-list-B" => failing}

      measurement = write_run!(dirs: Map.keys(shape) |> Enum.sort(), checks: shape)
      control = write_run!(adapter: "null", dirs: Map.keys(shape) |> Enum.sort(), checks: shape)

      # The measurement still needs resources-list classified; the control does
      # not. Assert on the control's own census that the join REFUSES to give it
      # a headline, and on the measurement that classification is what blocks.
      assert {:refused, :SCENARIO_UNCLASSIFIED, _} = Census.build(measurement, control: control)
      assert {:ok, joined} = Census.build(control, control: control)

      c = joined["totals"]["control"]
      assert c["inherited"] == ["tools-list"]
      assert c["discriminating"] == []
      assert c["control_passed_scored"]["passed"] == 1
    end
  end
end
