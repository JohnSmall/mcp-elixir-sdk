defmodule MCP.Conformance.ManifestTest do
  @moduledoc """
  Paired controls for the adjudicator (R3).

  Every refusal condition gets a *pair*: a fabricated run that must be refused
  with that exact code, and the same run with **only that one field corrected**,
  which must be accepted. The pairing is the mutation. Nine "it refuses" tests
  would pass just as happily against an adjudicator that refuses everything —
  which is C1's failure mode, and the reason a control that has never been shown
  to pass is not evidence either.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.{Beacon, Manifest, Provenance}

  @good_commit "1111111111111111111111111111111111111111"
  @other_commit "2222222222222222222222222222222222222222"

  # A manifest that MUST be accepted. Every refusal test below is this map with
  # exactly one field spoiled, so a test that goes red names the field.
  defp good_manifest do
    %{
      "schema_version" => Manifest.schema_version(),
      "leg" => "client",
      "git" => %{
        "commit_sha_start" => @good_commit,
        "commit_sha_end" => @good_commit,
        "branch_start" => "MES-51",
        "branch_end" => "MES-51",
        "worktree_root" => "/tmp/wt",
        "dirty_start" => false,
        "dirty_end" => false,
        "dirty_digest_start" => "d0",
        "dirty_digest_end" => "d0",
        "dirty_entries_start" => [],
        "dirty_entries_end" => [],
        "dirty_entry_count_start" => 0,
        "dirty_entry_count_end" => 0,
        "dirty_excluded_paths" => ["/tmp/run"],
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
        "sha256" => "beef"
      },
      "invocation" => %{
        "argv" => ["node", "index.js", "client"],
        "cwd" => "/tmp/wt",
        "project_root" => "/tmp/wt",
        "cwd_is_project_root" => true,
        "adapter_command" => "mix run conformance/client_adapter.exs",
        "out_dir" => "/tmp/run",
        "compiled_before_run" => true
      },
      "timing" => %{
        "started_at" => "2026-08-20T19:00:00.000000Z",
        "ended_at" => "2026-08-20T19:00:30.000000Z",
        "utc_offset" => "+00:00",
        "duration_ms" => 30_000
      },
      "toolchain" => %{"elixir" => "1.19.5", "otp" => "28", "mix_env" => "dev"},
      "beacon" => %{
        "token" => "tok",
        "preflight_ok" => true,
        "preflight_detail" => %{"ok" => true},
        "adapter_count" => 8,
        "preflight_count" => 1,
        "foreign_lines" => 0,
        "unparseable_lines" => 0,
        "adapter_sources" => ["conformance/client_adapter.exs"]
      },
      "result" => %{
        "harness_exit_code" => 1,
        "console_sha256" => "c0ffee",
        "console_bytes" => 15_381,
        "scenario_dir_count" => 2,
        "scenario_dirs" => ["client-tools_call-A", "client-request-metadata-B"]
      }
    }
  end

  defp observed do
    %{
      scenario_dirs: ["client-request-metadata-B", "client-tools_call-A"],
      console_sha256: "c0ffee"
    }
  end

  defp expect(overrides \\ %{}) do
    Map.merge(
      %{commit: @good_commit, requirements_md5: nil, harness_dist_sha256: nil},
      overrides
    )
  end

  defp judge(m, o \\ nil, e \\ nil) do
    Manifest.judge(m, o || observed(), e || expect())
  end

  defp diagnose(m, o \\ nil, e \\ nil) do
    Manifest.diagnose(m, o || observed(), e || expect())
  end

  defp outstanding(m), do: for({code, {:refused, _}} <- diagnose(m), do: code)
  defp not_evaluated(m), do: for({code, {:not_evaluated, _}} <- diagnose(m), do: code)

  defp put_in_path(m, [k], v), do: Map.put(m, k, v)
  defp put_in_path(m, [k | rest], v), do: Map.put(m, k, put_in_path(Map.fetch!(m, k), rest, v))

  # --- The accept half of every pair -------------------------------------

  describe "a well-formed run" do
    test "is accepted" do
      assert :ok == judge(good_manifest())
    end
  end

  # --- Paired refusals ----------------------------------------------------
  # Each case: spoil ONE field -> that code; restore only that field -> :ok.

  @pairs [
    {:CWD_NOT_PROJECT_ROOT, ["invocation", "cwd_is_project_root"], false, true},
    {:COMMIT_MOVED_MID_RUN, ["git", "commit_sha_end"], @other_commit, @good_commit},
    {:WORKTREE_DIRTY, ["git", "dirty_start"], true, false},
    {:WORKTREE_DIRTY, ["git", "dirty_end"], true, false},
    {:BEACON_PREFLIGHT_FAILED, ["beacon", "preflight_ok"], false, true},
    {:ADAPTER_NEVER_STARTED, ["beacon", "adapter_count"], 0, 8},
    {:ARTEFACTS_INCONSISTENT, ["beacon", "foreign_lines"], 3, 0},
    {:ARTEFACTS_INCONSISTENT, ["result", "scenario_dir_count"], 0, 2},
    {:ARTEFACTS_INCONSISTENT, ["result", "console_sha256"], "not-this-runs-console", "c0ffee"},
    # --- round 1 corrections: B1 ---
    {:DIRTY_EXCLUSION_COVERS_ROOT, ["git", "dirty_excluded_paths"], ["/tmp/wt"], ["/tmp/run"]},
    {:DIRTY_EXCLUSION_COVERS_ROOT, ["git", "dirty_excluded_paths"], ["/tmp"], ["/tmp/run"]},
    {:DIRTY_EXCLUSION_COVERS_ROOT, ["git", "dirty_exclusions_rejected"], ["/tmp/wt"], []},
    # --- round 1 corrections: B2 ---
    {:ARTEFACTS_INCONSISTENT, ["result", "scenario_dir_count"], 999, 2},
    {:ARTEFACTS_INCONSISTENT, ["beacon", "unparseable_lines"], 1, 0},
    # --- round 1 corrections: the class (MANIFEST_INCOMPLETE on a null) ---
    {:MANIFEST_INCOMPLETE, ["git", "commit_sha_start"], nil, @good_commit},
    {:MANIFEST_INCOMPLETE, ["beacon", "adapter_count"], nil, 8},
    {:MANIFEST_INCOMPLETE, ["result", "console_sha256"], nil, "c0ffee"}
  ]

  for {code, path, bad, good} <- @pairs do
    @code code
    @path path
    @bad bad
    @good good

    test "#{code}: refuses when #{Enum.join(path, ".")} is #{inspect(bad)}, accepts when corrected" do
      spoiled = put_in_path(good_manifest(), @path, @bad)

      assert {:refused, @code, detail} = judge(spoiled),
             "expected #{@code} when #{Enum.join(@path, ".")} = #{inspect(@bad)}"

      assert is_binary(detail) and detail != ""

      # The accept half: correcting ONLY this field must clear the refusal.
      assert :ok == judge(put_in_path(spoiled, @path, @good)),
             "correcting #{Enum.join(@path, ".")} alone did not clear #{@code}"
    end
  end

  describe "COMMIT_MISMATCH" do
    test "refuses a run measured on another tree, accepts the matching one" do
      m = good_manifest()

      assert {:refused, :COMMIT_MISMATCH, _} =
               judge(m, observed(), expect(%{commit: @other_commit}))

      assert :ok == judge(m, observed(), expect(%{commit: @good_commit}))
    end

    test "is not judged when no tree is nominated" do
      assert :ok == judge(good_manifest(), observed(), expect(%{commit: nil}))
    end
  end

  describe "HARNESS_MISMATCH" do
    test "refuses a foreign requirement set, accepts the pinned one" do
      m = good_manifest()
      wanted = m["requirements"]["md5"]

      assert {:refused, :HARNESS_MISMATCH, _} =
               judge(
                 m,
                 observed(),
                 expect(%{requirements_md5: "0" <> String.slice(wanted, 1..-1//1)})
               )

      assert :ok == judge(m, observed(), expect(%{requirements_md5: wanted}))
    end

    test "refuses a foreign harness dist, accepts the pinned one" do
      m = good_manifest()
      wanted = m["harness"]["dist_sha256"]

      assert {:refused, :HARNESS_MISMATCH, _} =
               judge(m, observed(), expect(%{harness_dist_sha256: "deadbeef"}))

      assert :ok == judge(m, observed(), expect(%{harness_dist_sha256: wanted}))
    end

    test "is not judged when the instrument is not pinned" do
      assert :ok == judge(good_manifest())
    end
  end

  describe "ARTEFACTS_INCONSISTENT via on-disk drift" do
    test "refuses when the directories on disk are not the ones recorded" do
      drifted = %{observed() | scenario_dirs: ["client-tools_call-A", "some-other-run"]}

      assert {:refused, :ARTEFACTS_INCONSISTENT, detail} = judge(good_manifest(), drifted)
      assert detail =~ "scenario directories on disk differ"

      assert :ok == judge(good_manifest(), observed())
    end
  end

  # --- Round 1: the class, enumerated ------------------------------------
  #
  # B1 and B2 were three instances of one shape: a check that does not fire
  # because its input is absent, and absence read as satisfaction. Fixing three
  # instances would leave the class. These tests assert the property instead,
  # over every field the manifest carries, and they assert BOTH directions — a
  # rule that refused everything would satisfy the refusal half alone.

  describe "MANIFEST_INCOMPLETE — the class property" do
    test "EVERY field, removed, is refused: absence is never satisfaction" do
      good = good_manifest()

      accepted_absent =
        for path <- all_paths(good),
            verdict = safe_judge(drop_at(good, path)),
            verdict != {:refused, :MANIFEST_INCOMPLETE},
            do: {Enum.join(path, "."), verdict}

      assert accepted_absent == [],
             "these fields could be deleted without judge/3 refusing: " <>
               inspect(accepted_absent)
    end

    test "every CONSUMED field, set to null, is refused" do
      good = good_manifest()

      leaked =
        for path <- all_paths(good),
            consumed?(path),
            verdict = safe_judge(put_in_path(good, path, nil)),
            verdict != {:refused, :MANIFEST_INCOMPLETE},
            do: {Enum.join(path, "."), verdict}

      assert leaked == [],
             "a refusal condition would have been judged against a null operand: " <>
               inspect(leaked)
    end

    test "every PROVENANCE-ONLY field, set to null, is still accepted" do
      good = good_manifest()

      refused =
        for path <- all_paths(good),
            not consumed?(path),
            verdict = safe_judge(put_in_path(good, path, nil)),
            verdict != :ok,
            do: {Enum.join(path, "."), verdict}

      assert refused == [],
             "\"we looked and could not tell\" is legitimate provenance and must not " <>
               "refuse a run; these did: #{inspect(refused)}"
    end

    test "the counts behind the two rules, enumerated (A2d)" do
      good = good_manifest()
      paths = all_paths(good)
      {consumed, provenance} = Enum.split_with(paths, &consumed?/1)

      assert length(paths) == map_size(Manifest.field_dispositions())

      # Both halves must be non-empty, and that is not pedantry: an empty
      # `consumed` would mean the rule judges nothing, an empty `provenance`
      # would mean it refuses every null. Either satisfies the two tests above
      # while establishing nothing.
      refute consumed == []
      refute provenance == []

      assert Enum.sort(consumed ++ provenance) == paths,
             "every field is in exactly one half; none was dropped or counted twice"
    end

    test "a field absent from the manifest names itself in the refusal detail" do
      spoiled = drop_at(good_manifest(), ["result", "scenario_dirs"])

      assert {:refused, :MANIFEST_INCOMPLETE, detail} = judge(spoiled)
      assert detail =~ "result.scenario_dirs"
    end
  end

  describe "DIRTY_EXCLUSION_COVERS_ROOT" do
    test "C3's case is preserved: a run directory INSIDE the repo is still accepted" do
      m =
        good_manifest()
        |> put_in_path(["git", "worktree_root"], "/tmp/wt")
        |> put_in_path(["git", "dirty_excluded_paths"], ["/tmp/wt/conformance-run-scratch"])

      assert :ok == judge(m),
             "excluding a proper subdirectory is the C3 fix and must keep working"
    end

    test "a sibling path that merely shares a prefix does not count as covering" do
      m =
        good_manifest()
        |> put_in_path(["git", "worktree_root"], "/tmp/wt")
        |> put_in_path(["git", "dirty_excluded_paths"], ["/tmp/wt-other"])

      assert :ok == judge(m)
    end
  end

  describe "ARTEFACTS_INCONSISTENT — console.txt must exist, not merely be recorded" do
    test "refuses when the file is absent, accepts when it is there" do
      absent = %{observed() | console_sha256: nil}

      assert {:refused, :ARTEFACTS_INCONSISTENT, detail} = judge(good_manifest(), absent)
      assert detail =~ "no readable console.txt"

      assert :ok == judge(good_manifest(), observed())
    end
  end

  # --- MANIFEST_ABSENT / MANIFEST_UNREADABLE: these live in read/1 --------

  describe "read/1" do
    @tag :tmp_dir
    test "MANIFEST_ABSENT for a run directory with no manifest, :ok once written", %{
      tmp_dir: dir
    } do
      assert {:refused, :MANIFEST_ABSENT, detail} = Manifest.read(dir)
      assert detail =~ Manifest.filename()

      File.write!(Path.join(dir, Manifest.filename()), Manifest.encode(good_manifest()))
      assert {:ok, m} = Manifest.read(dir)
      assert m["git"]["commit_sha_start"] == @good_commit
    end

    @tag :tmp_dir
    test "MANIFEST_UNREADABLE for non-JSON, :ok once repaired", %{tmp_dir: dir} do
      path = Path.join(dir, Manifest.filename())

      File.write!(path, "{not json")
      assert {:refused, :MANIFEST_UNREADABLE, _} = Manifest.read(dir)

      File.write!(path, Manifest.encode(good_manifest()))
      assert {:ok, _} = Manifest.read(dir)
    end

    @tag :tmp_dir
    test "MANIFEST_UNREADABLE for a schema version this build does not know", %{tmp_dir: dir} do
      path = Path.join(dir, Manifest.filename())
      future = Map.put(good_manifest(), "schema_version", Manifest.schema_version() + 1)

      File.write!(path, Manifest.encode(future))
      assert {:refused, :MANIFEST_UNREADABLE, detail} = Manifest.read(dir)
      assert detail =~ "schema_version"

      File.write!(path, Manifest.encode(good_manifest()))
      assert {:ok, _} = Manifest.read(dir)
    end
  end

  # --- C5: no field may be unlabelled ------------------------------------

  describe "field dispositions (C5)" do
    test "every field a manifest carries is either judged or labelled provenance-only" do
      carried = flatten_keys(good_manifest())
      labelled = Manifest.field_dispositions() |> Map.keys() |> MapSet.new()

      unlabelled = MapSet.difference(MapSet.new(carried), labelled)

      assert MapSet.size(unlabelled) == 0,
             "these manifest fields are neither consumed by a refusal condition nor " <>
               "labelled provenance-only: #{inspect(MapSet.to_list(unlabelled))}"
    end

    test "every labelled field is actually carried by a manifest" do
      carried = good_manifest() |> flatten_keys() |> MapSet.new()
      labelled = Manifest.field_dispositions() |> Map.keys() |> MapSet.new()

      assert MapSet.size(MapSet.difference(labelled, carried)) == 0,
             "the disposition table names fields no manifest carries: " <>
               inspect(MapSet.to_list(MapSet.difference(labelled, carried)))
    end

    test "every refusal code in the table is one judge/3 can actually return" do
      judged =
        Manifest.field_dispositions()
        |> Map.values()
        |> Enum.reject(&(&1 == :provenance_only))
        |> MapSet.new()

      assert MapSet.subset?(judged, MapSet.new(Manifest.refusal_codes()))
    end
  end

  # --- B1 at the writer layer --------------------------------------------
  #
  # The judge refuses a manifest that carries a covering exclusion. This is the
  # other half: the collector must not produce one in the first place, or a
  # dirty tree would be recorded as clean and the judge would be reading a
  # field that already lied.

  describe "Provenance.collect_git/2 — an exclusion may not cover the root" do
    @tag :tmp_dir
    test "a covering exclusion is NOT applied; a proper subdirectory still is", %{tmp_dir: dir} do
      root = init_repo(dir)
      File.write!(Path.join(root, "tracked.txt"), "edited\n")
      File.mkdir_p!(Path.join(root, "run-scratch"))
      File.write!(Path.join([root, "run-scratch", "artefact.txt"]), "noise\n")

      # Excluding the root would hide the edit to tracked.txt. It must not.
      covering = Provenance.collect_git(root, [root])
      assert covering["dirty"] == true
      assert covering["dirty_excluded_paths"] == []
      assert covering["dirty_exclusions_rejected"] == [root]

      # The C3 case: excluding the run directory hides only the run directory.
      File.write!(Path.join(root, "tracked.txt"), "original\n")
      scratch = Path.join(root, "run-scratch")
      narrow = Provenance.collect_git(root, [scratch])
      assert narrow["dirty"] == false
      assert narrow["dirty_excluded_paths"] == [scratch]
      assert narrow["dirty_exclusions_rejected"] == []

      # ...and it still sees a real edit outside it.
      File.write!(Path.join(root, "tracked.txt"), "edited again\n")
      assert Provenance.collect_git(root, [scratch])["dirty"] == true
    end

    test "covers_root?/2 separates ancestors from siblings and descendants" do
      assert Provenance.covers_root?("/tmp/wt", "/tmp/wt")
      assert Provenance.covers_root?("/tmp", "/tmp/wt")
      refute Provenance.covers_root?("/tmp/wt/run", "/tmp/wt")
      refute Provenance.covers_root?("/tmp/wt-other", "/tmp/wt")
      refute Provenance.covers_root?("/var", "/tmp/wt")
    end

    test "partition_exclusions/2 splits, and keeps every path in exactly one half" do
      root = "/tmp/wt"
      given = ["/tmp/wt/run", "/tmp/wt", "/tmp", "/tmp/wt-other"]
      {applied, rejected} = Provenance.partition_exclusions(root, given)

      assert applied == ["/tmp/wt/run", "/tmp/wt-other"]
      assert rejected == ["/tmp/wt", "/tmp"]
      assert Enum.sort(applied ++ rejected) == Enum.sort(given)
    end
  end

  defp init_repo(dir) do
    root = Path.join(dir, "repo")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "tracked.txt"), "original\n")

    for args <- [
          ["init", "-q"],
          ["config", "user.email", "test@example.invalid"],
          ["config", "user.name", "Test"],
          ["add", "tracked.txt"],
          ["commit", "-q", "-m", "seed"]
        ] do
      {_, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true)
    end

    root
  end

  # --- helpers for the class tests ---------------------------------------

  defp all_paths(manifest) do
    manifest
    |> flatten_keys()
    |> Enum.map(&String.split(&1, "."))
    |> Enum.sort()
  end

  defp consumed?(path) do
    Manifest.field_dispositions()
    |> Map.fetch!(Enum.join(path, "."))
    |> Kernel.!=(:provenance_only)
  end

  defp drop_at(m, [k]), do: Map.delete(m, k)
  defp drop_at(m, [k | rest]), do: Map.put(m, k, drop_at(Map.fetch!(m, k), rest))

  # A raise is not a refusal. `git.dirty_start` used to raise BadBooleanError
  # when absent, and a crash reported as anything other than a failure here
  # would let that behaviour back in.
  defp safe_judge(m) do
    case Manifest.judge(m, observed(), expect()) do
      :ok -> :ok
      {:refused, code, _detail} -> {:refused, code}
    end
  rescue
    e -> {:raised, e.__struct__}
  end

  defp flatten_keys(map, prefix \\ "") do
    Enum.flat_map(map, fn {k, v} -> flatten_entry(k, v, join(prefix, k)) end)
  end

  defp join("", key), do: key
  defp join(prefix, key), do: "#{prefix}.#{key}"

  # `preflight_detail` is an opaque diagnostic blob rather than a field set, so it
  # is labelled as a whole instead of key by key.
  defp flatten_entry("preflight_detail", _value, path), do: [path]

  defp flatten_entry(_key, %{} = nested, path)
       when not is_struct(nested) and map_size(nested) > 0 do
    flatten_keys(nested, path)
  end

  defp flatten_entry(_key, _value, path), do: [path]

  # --- diagnose/3: report every condition, accept nothing ------------------
  #
  # `--allow-dirty` used to waive WORKTREE_DIRTY and exit 0. It is gone, and
  # `diagnose/3` is what replaced the reason it existed: seeing a run's problems
  # without any way to obtain acceptance for one that should not have it. These
  # tests hold two things — that it reports ALL conditions where `judge/3`
  # reports one, and that it never says :ok about a comparison it did not run.

  describe "diagnose/3" do
    test "a well-formed run: every condition reported, every one passing" do
      rows = diagnose(good_manifest())

      assert Enum.map(rows, &elem(&1, 0)) == Manifest.refusal_codes()
      assert Enum.all?(rows, &(elem(&1, 1) == :ok)), "unexpected: #{inspect(rows)}"
    end

    test "reports EVERY outstanding condition where judge/3 reports only the first" do
      spoiled =
        good_manifest()
        |> put_in_path(["invocation", "cwd_is_project_root"], false)
        |> put_in_path(["git", "dirty_start"], true)
        |> put_in_path(["beacon", "adapter_count"], 0)

      # The control: judge/3 halts, and names one of the three.
      assert {:refused, :CWD_NOT_PROJECT_ROOT, _} = judge(spoiled)

      assert outstanding(spoiled) == [
               :CWD_NOT_PROJECT_ROOT,
               :WORKTREE_DIRTY,
               :ADAPTER_NEVER_STARTED
             ]

      # ... and nothing was skipped to get there.
      assert not_evaluated(spoiled) == []
    end

    test "MANIFEST_INCOMPLETE collapses everything below it to NOT EVALUATED" do
      spoiled = put_in_path(good_manifest(), ["git", "dirty_start"], nil)
      rows = diagnose(spoiled)

      assert outstanding(spoiled) == [:MANIFEST_INCOMPLETE]

      # Before it: read/1 got this far, so those two conditions did pass.
      assert Enum.take(rows, 2) == [{:MANIFEST_ABSENT, :ok}, {:MANIFEST_UNREADABLE, :ok}]

      # After it: every remaining condition, unevaluated. Not one reported :ok.
      assert not_evaluated(spoiled) == Manifest.judged_codes() -- [:MANIFEST_INCOMPLETE]

      # WORKTREE_DIRTY is the condition that would have READ the nulled field.
      # Under judge/3 that comparison raised. Here it must not claim a pass.
      assert {:not_evaluated, why} = Keyword.fetch!(rows, :WORKTREE_DIRTY)
      assert why =~ "nil compares as satisfied"
    end

    test "a read-stage refusal reports itself and evaluates nothing after it" do
      refusal = {:refused, :MANIFEST_ABSENT, "no manifest.json at /tmp/nope/manifest.json"}
      rows = Manifest.diagnose(refusal, observed(), expect())

      assert Enum.map(rows, &elem(&1, 0)) == Manifest.refusal_codes()
      assert [{:MANIFEST_ABSENT, {:refused, _}} | rest] = rows
      assert Enum.all?(rest, &match?({_, {:not_evaluated, _}}, &1))
    end

    test "every condition, spoiled alone, is reported outstanding — and only it" do
      for {code, path, bad, good} <- @pairs do
        spoiled = put_in_path(good_manifest(), path, bad)

        assert outstanding(spoiled) == [code],
               "spoiling #{Enum.join(path, ".")} = #{inspect(bad)} should leave exactly " <>
                 "#{code} outstanding, got #{inspect(outstanding(spoiled))}"

        assert outstanding(put_in_path(spoiled, path, good)) == [],
               "correcting #{Enum.join(path, ".")} alone left a condition outstanding"
      end
    end

    test "the condition list is read_codes ++ judged_codes, enumerated (A2d)" do
      assert Manifest.read_codes() ++ Manifest.judged_codes() == Manifest.refusal_codes()
      assert length(Manifest.read_codes()) == 2
      assert length(Manifest.judged_codes()) == 10
      assert Enum.uniq(Manifest.refusal_codes()) == Manifest.refusal_codes()
    end
  end

  # --- The residual must be stated, not implied (AC5) ---------------------

  describe "residual/0" do
    test "enumerates what an accepted manifest does not establish" do
      residual = Manifest.residual()

      assert length(residual) >= 6
      assert Enum.any?(residual, &(&1 =~ "ATTRIBUTABLE, not CORRECT"))
      assert Enum.any?(residual, &(&1 =~ "per-scenario"))
      assert Enum.any?(residual, &(&1 =~ "BEAMS"))
    end
  end

  # --- The beacon itself --------------------------------------------------

  describe "beacon" do
    @tag :tmp_dir
    test "is a no-op without its environment, and cannot raise", %{tmp_dir: dir} do
      System.delete_env(Beacon.env_path_var())
      System.delete_env(Beacon.env_token_var())

      assert :noop == Beacon.emit(:adapter, "probe.exs")
      refute File.exists?(Path.join(dir, "beacon.jsonl"))
    end

    @tag :tmp_dir
    test "pre-flight succeeds on a writable path and is read back", %{tmp_dir: dir} do
      path = Path.join(dir, "beacon.jsonl")

      assert {:ok, detail} = Beacon.preflight(path, "tok-a")
      assert detail["ok"] == true
      assert detail["preflight_lines_read_back"] == 1

      counts = Beacon.read(path, "tok-a")
      assert counts.preflight == 1
      assert counts.adapter == 0
    end

    @tag :tmp_dir
    test "pre-flight FAILS on an unwritable path — the control fires", %{tmp_dir: dir} do
      # A path whose parent is a regular file cannot be created.
      blocker = Path.join(dir, "blocker")
      File.write!(blocker, "not a directory")
      path = Path.join([blocker, "nested", "beacon.jsonl"])

      assert {:error, detail} = Beacon.preflight(path, "tok-b")
      assert detail["ok"] == false
    end

    @tag :tmp_dir
    test "counts adapter lines by token and flags foreign ones", %{tmp_dir: dir} do
      path = Path.join(dir, "beacon.jsonl")

      System.put_env(Beacon.env_path_var(), path)
      System.put_env(Beacon.env_token_var(), "mine")

      assert :ok == Beacon.emit(:adapter, "conformance/client_adapter.exs")
      assert :ok == Beacon.emit(:adapter, "conformance/client_adapter.exs")

      # A line from an earlier run that reused this directory.
      System.put_env(Beacon.env_token_var(), "someone-elses")
      assert :ok == Beacon.emit(:adapter, "conformance/client_adapter.exs")

      System.delete_env(Beacon.env_path_var())
      System.delete_env(Beacon.env_token_var())

      counts = Beacon.read(path, "mine")
      assert counts.adapter == 2
      assert counts.foreign == 1
      assert counts.adapter_sources == ["conformance/client_adapter.exs"]
    end
  end
end
