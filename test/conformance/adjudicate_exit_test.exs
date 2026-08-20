defmodule Mix.Tasks.Conformance.AdjudicateExitTest do
  @moduledoc """
  The adjudicator's exit status is its contract, and this file is the whole of
  the evidence for it.

  MES-56 and MES-57 gate on `mix conformance.adjudicate` exiting 0: no figure
  appears anywhere without it. A consumer reading only the exit status cannot
  see anything the task printed, so the property under test is about the status
  and nothing else:

  > **No invocation may exit 0 while a refusal condition is outstanding.**

  `--allow-dirty` used to break it. It waived `WORKTREE_DIRTY`, printed
  "WAIVED — a refusal condition was switched off for this run" and exited 0.
  The waiver was loud and the exit status was silent, and only the exit status
  is load-bearing. It is gone; `--diagnose` replaced the need it served and
  cannot exit 0 for any input at all.

  These tests run the task in-process and read the exit status out of
  `catch_exit/1`, so they measure the status a shell would see rather than a
  stand-in for it. `async: false` — they capture the named stdio devices.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias MCP.Conformance.Manifest
  alias Mix.Tasks.Conformance.Adjudicate

  @commit "1111111111111111111111111111111111111111"
  @console "conformance console output\n"

  setup do
    dir = Path.join(System.tmp_dir!(), "mes51-adj-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "client-tools_call-A"))
    File.write!(Path.join([dir, "client-tools_call-A", "checks.json"]), "[]")
    File.write!(Path.join(dir, Manifest.console_filename()), @console)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  # An acceptable run, written to disk. `spoil` applies one edit before writing,
  # so each test below differs from the accepted case in exactly one field.
  defp write_manifest(dir, spoil \\ & &1) do
    console_sha =
      :sha256 |> :crypto.hash(@console) |> Base.encode16(case: :lower)

    manifest =
      %{
        "schema_version" => Manifest.schema_version(),
        "leg" => "client",
        "git" => %{
          "commit_sha_start" => @commit,
          "commit_sha_end" => @commit,
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
          "sha256" => "beef"
        },
        "invocation" => %{
          "argv" => ["node", "index.js", "client"],
          "cwd" => "/tmp/wt",
          "project_root" => "/tmp/wt",
          "cwd_is_project_root" => true,
          "adapter_command" => "elixir conformance/client_adapter.exs",
          "out_dir" => dir,
          "compiled_before_run" => true
        },
        "timing" => %{
          "started_at" => "2026-08-20T21:30:00+00:00",
          "ended_at" => "2026-08-20T21:31:00+00:00",
          "utc_offset" => "+00:00",
          "duration_ms" => 60_000
        },
        "toolchain" => %{"elixir" => "1.17.3", "otp" => "27", "mix_env" => "dev"},
        "beacon" => %{
          "token" => "t0",
          "preflight_ok" => true,
          "preflight_detail" => nil,
          "adapter_count" => 8,
          "preflight_count" => 1,
          "foreign_lines" => 0,
          "unparseable_lines" => 0,
          "adapter_sources" => ["conformance/client_adapter.exs"]
        },
        "result" => %{
          "harness_exit_code" => 1,
          "console_sha256" => console_sha,
          "console_bytes" => byte_size(@console),
          "scenario_dir_count" => 1,
          "scenario_dirs" => ["client-tools_call-A"]
        }
      }
      |> spoil.()

    File.write!(Path.join(dir, Manifest.filename()), Manifest.encode(manifest))
  end

  # Run the task and return `{exit_status, stdout, stderr}` — 0 for a task that
  # returns normally, since a Mix task that falls off its end exits 0.
  defp adjudicate(argv) do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            send(parent, {:status, run_status(argv)})
          end)

        send(parent, {:stdout, stdout})
      end)

    assert_received {:status, status}
    assert_received {:stdout, stdout}
    {status, stdout, stderr}
  end

  # The status a shell would see: whatever the task exits with, or 0 when it
  # returns without exiting — which is the acceptance path, and the ONLY path
  # that reaches 0.
  defp run_status(argv) do
    Adjudicate.run(argv)
    0
  catch
    :exit, {:shutdown, n} -> n
  end

  describe "the ordinary adjudication is unchanged" do
    test "a good run is ACCEPTED and exits 0", %{dir: dir} do
      write_manifest(dir)

      {status, out, _err} = adjudicate([dir, "--expect-commit", @commit])

      assert status == 0
      assert out =~ "ACCEPTED"
      assert out =~ "VERIFIED"
      refute out =~ "WAIVED"
    end

    test "a dirty run is REFUSED and exits 1", %{dir: dir} do
      write_manifest(dir, &put_in(&1["git"]["dirty_start"], true))

      {status, _out, err} = adjudicate([dir, "--expect-commit", @commit])

      assert status == 1
      assert err =~ "REFUSED"
      assert err =~ "WORKTREE_DIRTY"
    end
  end

  describe "--diagnose cannot exit 0 (the property)" do
    # The successor to --allow-dirty, on the input --allow-dirty existed for.
    test "a dirty run: reports WORKTREE_DIRTY outstanding, exits 2", %{dir: dir} do
      write_manifest(dir, &put_in(&1["git"]["dirty_start"], true))

      {status, out, _err} = adjudicate([dir, "--diagnose", "--expect-commit", @commit])

      assert status == 2
      assert out =~ "OUTSTANDING    WORKTREE_DIRTY"
      assert out =~ "would refuse it with WORKTREE_DIRTY"
      refute out =~ "ACCEPTED"
    end

    # The one that matters most: a run with NOTHING outstanding still may not
    # exit 0 under --diagnose. If it did, `--diagnose` would be the waiver again
    # by another name — pass it always, and a dirty run's status becomes
    # indistinguishable from a clean one's.
    test "a run with nothing outstanding STILL exits 2, not 0", %{dir: dir} do
      write_manifest(dir)

      {status, out, _err} = adjudicate([dir, "--diagnose", "--expect-commit", @commit])

      assert status == 2
      assert out =~ "0 outstanding, 0 not evaluated, 12 passing"
      assert out =~ "still not accepted"
      refute out =~ "ACCEPTED"
    end

    test "an absent manifest: exits 2, and claims no check it did not run", %{dir: dir} do
      File.rm!(Path.join(dir, Manifest.console_filename()))

      {status, out, _err} = adjudicate([dir, "--diagnose", "--expect-commit", @commit])

      assert status == 2
      assert out =~ "OUTSTANDING    MANIFEST_ABSENT"
      assert out =~ "NOT EVALUATED  WORKTREE_DIRTY"
      assert out =~ "1 outstanding, 11 not evaluated, 0 passing"
    end

    # Enumerated rather than argued (A2d): every condition, one at a time, over
    # both --diagnose branches. 24 invocations, not one of them exits 0.
    test "no input reaches exit 0 under --diagnose", %{dir: dir} do
      spoilers = [
        {:MANIFEST_UNREADABLE, &put_in(&1["schema_version"], 99)},
        {:MANIFEST_INCOMPLETE, &put_in(&1["git"]["commit_sha_start"], nil)},
        {:CWD_NOT_PROJECT_ROOT, &put_in(&1["invocation"]["cwd_is_project_root"], false)},
        {:COMMIT_MISMATCH, &put_in(&1["git"]["commit_sha_start"], String.duplicate("2", 40))},
        {:COMMIT_MOVED_MID_RUN, &put_in(&1["git"]["commit_sha_end"], String.duplicate("3", 40))},
        {:DIRTY_EXCLUSION_COVERS_ROOT, &put_in(&1["git"]["dirty_excluded_paths"], ["/tmp/wt"])},
        {:WORKTREE_DIRTY, &put_in(&1["git"]["dirty_end"], true)},
        {:BEACON_PREFLIGHT_FAILED, &put_in(&1["beacon"]["preflight_ok"], false)},
        {:ADAPTER_NEVER_STARTED, &put_in(&1["beacon"]["adapter_count"], 0)},
        {:ARTEFACTS_INCONSISTENT, &put_in(&1["result"]["scenario_dir_count"], 99)},
        {:none, & &1}
      ]

      for {code, spoil} <- spoilers do
        write_manifest(dir, spoil)

        {status, out, _err} = adjudicate([dir, "--diagnose", "--expect-commit", @commit])

        assert status == 2, "--diagnose exited #{status} on the #{code} case"
        refute out =~ "ACCEPTED", "--diagnose printed an acceptance on the #{code} case"
      end

      # HARNESS_MISMATCH is raised by a pin, not by a spoiled field.
      write_manifest(dir)

      {status, _out, _err} =
        adjudicate([
          dir,
          "--diagnose",
          "--expect-commit",
          @commit,
          "--expect-requirements-md5",
          "x"
        ])

      assert status == 2
    end

    test "--diagnose reports all outstanding conditions, not just the first", %{dir: dir} do
      write_manifest(dir, fn m ->
        m
        |> put_in(["invocation", "cwd_is_project_root"], false)
        |> put_in(["git", "dirty_start"], true)
        |> put_in(["beacon", "preflight_ok"], false)
      end)

      {status, out, _err} = adjudicate([dir, "--diagnose", "--expect-commit", @commit])

      assert status == 2
      assert out =~ "3 outstanding"
      assert out =~ "OUTSTANDING    CWD_NOT_PROJECT_ROOT"
      assert out =~ "OUTSTANDING    WORKTREE_DIRTY"
      assert out =~ "OUTSTANDING    BEACON_PREFLIGHT_FAILED"

      # The control for the improvement: the ordinary adjudication still names
      # exactly one, so "reports all" is a real difference and not a restatement.
      {refuse_status, _out, err} = adjudicate([dir, "--expect-commit", @commit])
      assert refuse_status == 1
      assert err =~ "CWD_NOT_PROJECT_ROOT"
      refute err =~ "BEACON_PREFLIGHT_FAILED"
    end
  end

  describe "the waiver is gone, not renamed" do
    # This test used to assert status 1 on a DIRTY manifest, reasoning that
    # "OptionParser drops the unknown switch; the run is refused on its merits".
    # Both halves were true and the conclusion was still wrong: the run was
    # refused because it was dirty, not because the flag was rejected, so the
    # test passed for a reason unrelated to what it claimed to check. On a
    # CLEAN manifest — the case it never tried — the same invocation exited 0
    # ACCEPTED. A test whose subject and whose cause of passing differ is a
    # green that means nothing, which is this ticket's own subject.
    test "--allow-dirty is rejected on a CLEAN run, where nothing else would refuse it", %{
      dir: dir
    } do
      write_manifest(dir)

      {status, out, err} = adjudicate([dir, "--allow-dirty", "--expect-commit", @commit])

      assert status == MCP.Conformance.Argv.usage_exit()
      refute out =~ "ACCEPTED"
      refute err =~ "WAIVED"
      assert err =~ "was removed, not renamed"
    end

    test "--allow-dirty on a dirty run is a usage error, not a refusal", %{dir: dir} do
      write_manifest(dir, &put_in(&1["git"]["dirty_start"], true))

      {status, out, err} = adjudicate([dir, "--allow-dirty", "--expect-commit", @commit])

      # The run IS dirty, and it is still not adjudicated: argv is rejected
      # first, so the operator fixes the command line rather than reading a
      # verdict produced from an invocation that was not the one they wrote.
      assert status == MCP.Conformance.Argv.usage_exit()
      refute out =~ "ACCEPTED"
      refute err =~ "WAIVED"
    end

    # The control for the pair above: a dirty run with VALID argv still refuses
    # exactly as it did, so the new rejection has not swallowed the old verdict.
    test "a dirty run with valid argv still refuses WORKTREE_DIRTY, exit 1", %{dir: dir} do
      write_manifest(dir, &put_in(&1["git"]["dirty_start"], true))

      {status, _out, err} = adjudicate([dir, "--expect-commit", @commit])

      assert status == 1
      assert err =~ "WORKTREE_DIRTY"
    end
  end

  describe "invalid argv is rejected before adjudication (the class fix)" do
    # Measured at delivered tip ee10773: every one of these exited 0 ACCEPTED
    # against this same good manifest.
    test "the misspelled pin no longer accepts what the spelled one refuses", %{dir: dir} do
      write_manifest(dir)
      zeros = String.duplicate("0", 40)

      {spelled, _, err} = adjudicate([dir, "--expect-commit", zeros])
      assert spelled == 1
      assert err =~ "COMMIT_MISMATCH"

      {misspelled, out, _} = adjudicate([dir, "--expect-comit", zeros])
      assert misspelled == MCP.Conformance.Argv.usage_exit()
      refute out =~ "ACCEPTED"
    end

    test "an extra positional argument is rejected", %{dir: dir} do
      write_manifest(dir)

      {status, out, _err} = adjudicate([dir, "/some/other/run", "--expect-commit", @commit])

      assert status == MCP.Conformance.Argv.usage_exit()
      refute out =~ "ACCEPTED"
    end

    test "--diagnose=maybe is rejected rather than read as a bare --diagnose", %{dir: dir} do
      write_manifest(dir)

      {status, out, _err} = adjudicate([dir, "--diagnose=maybe", "--expect-commit", @commit])

      assert status == MCP.Conformance.Argv.usage_exit()
      refute out =~ "ACCEPTED"
      refute out =~ "DIAGNOSIS"
    end
  end
end
