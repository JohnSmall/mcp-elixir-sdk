defmodule MCP.Conformance.Runner do
  @moduledoc """
  Runs one conformance leg and writes a `manifest.json` beside its artefacts.

  The order of operations is the design, not an implementation detail:

      compile -> beacon pre-flight -> git START -> launch adapter -> invoke
      harness (console teed into the run directory) -> stop adapter ->
      git END -> read beacon -> enumerate artefacts -> write manifest

  Two of those steps exist because of specific failures.

  **The pre-flight comes before the adapter launches.** The beacon is wrapped so
  it can never crash an adapter, which means a broken beacon is silent — and a
  silent beacon would make `adapter_count: 0` read as "the adapter never
  started" when the truth was "the beacon never worked". That is a false-red,
  and a false-red teaches people to bypass the gate. So the runner proves the
  mechanism can write and be read back first, and records the proof.

  **The console is captured into the run directory.** The scored/not-scored
  split — "Not scored for 2026-07-28: 13 scenario(s)" — appears in run-level
  console output and *nowhere in the artefact tree*. MES-49 kept it beside the
  run rather than in it, so a reader given only a run directory could not
  reconstruct the denominator. The denominator is the headline of both MES-56
  and MES-57.
  """

  alias MCP.Conformance.{Beacon, Manifest, Provenance, RequirementSet}

  @default_harness_dir "/tmp/conf11"
  @default_requirements "2026-07-28"
  @default_port 3001

  # An ENUM, not a command. The null control has to be selectable by the same
  # runner as the measurement — an unreproducible control is not a control, and
  # MES-49's lived in /tmp — but "let the operator name a command" would turn a
  # provenance tool into an arbitrary-process launcher whose manifest records
  # whatever it was told. Two named adapters, each with a fixed command line, so
  # `invocation.adapter` is a fact about which of two known things ran.
  @adapters %{
    sdk: "conformance/server_adapter.exs",
    null: "conformance/controls/null_server.py"
  }

  @doc """
  Run a leg. Options:

    * `:leg` — `:server` or `:client` (required)
    * `:out_dir` — where artefacts and the manifest go. Defaults **outside the
      repository**, so a run cannot dirty the tree it is measuring (C3). An
      in-repo path still works: the directory is excluded from the dirty
      computation and the exclusion is recorded in the manifest.
    * `:cwd` — the directory the harness (and so the spawned adapter) runs in.
      Defaults to the project root. Setting it elsewhere is how the wrong-cwd
      positive control is produced.
    * `:adapter` — `:sdk` (default) or `:null`, the do-nothing control. Server
      leg only; the client leg has no adapter to substitute.
    * `:harness_dir`, `:requirements`, `:port`
  """
  @spec run(keyword()) :: {:ok, map(), String.t()} | {:error, term()}
  def run(opts) do
    leg = Keyword.fetch!(opts, :leg)
    adapter_kind = Keyword.get(opts, :adapter, :sdk)
    harness_dir = Keyword.get(opts, :harness_dir, @default_harness_dir)
    requirements = Keyword.get(opts, :requirements, @default_requirements)
    port_no = Keyword.get(opts, :port, @default_port)

    if adapter_kind == :null and leg != :server do
      Mix.raise("--adapter null substitutes the SERVER under test; there is no client leg form")
    end

    project_root = Provenance.project_root(File.cwd!()) || File.cwd!()
    cwd = opts |> Keyword.get(:cwd, project_root) |> Path.expand()
    out_dir = opts |> Keyword.get(:out_dir, default_out_dir(leg, adapter_kind)) |> Path.expand()

    File.mkdir_p!(out_dir)

    beacon_path = Path.join(out_dir, Manifest.beacon_filename())
    console_path = Path.join(out_dir, Manifest.console_filename())
    token = token()

    log("run dir: #{out_dir}")
    log("cwd for harness + adapter: #{cwd}")

    compiled = compile(project_root)

    # C1: prove the beacon works BEFORE anything depends on its silence.
    {preflight_ok, preflight_detail} =
      case Beacon.preflight(beacon_path, token) do
        {:ok, d} -> {true, d}
        {:error, d} -> {false, d}
      end

    if preflight_ok do
      log("beacon pre-flight ok")
    else
      log("BEACON PRE-FLIGHT FAILED: #{inspect(preflight_detail)}")
    end

    env = [
      {Beacon.env_path_var(), beacon_path},
      {Beacon.env_token_var(), token}
    ]

    # The denominator, captured INTO the run directory before anything runs.
    # `requirements.{md5,sha256}` already identify the frozen file; neither says
    # what is in it, so a run directory alone could not state which scenarios it
    # was supposed to have executed. Both derivations are captured — the
    # harness's rendering and a byte copy of its source — because
    # `MCP.Conformance.RequirementSet` cross-checks them rather than trusting
    # either.
    requirements_info = Provenance.resolve_requirements(harness_dir, requirements)
    {expected, expected_exit} = Provenance.capture_expected(harness_dir, requirements)
    File.write!(Path.join(out_dir, RequirementSet.expected_filename()), expected)

    copy_sha =
      copy_requirements(requirements_info["path"], out_dir)

    log("expected set captured (list exit #{expected_exit}, #{byte_size(expected)} bytes)")

    started = Provenance.now()
    started_ms = System.monotonic_time(:millisecond)
    git_start = Provenance.collect_git(project_root, [out_dir])

    adapter =
      if leg == :server, do: start_server_adapter(adapter_kind, cwd, port_no, env), else: nil

    argv = harness_argv(leg, harness_dir, requirements, out_dir, port_no)

    {console, exit_code} = invoke_harness(argv, cwd, env)
    File.write!(console_path, console)

    if adapter, do: stop_server_adapter(adapter)

    ended = Provenance.now()
    git_end = Provenance.collect_git(project_root, [out_dir])
    beacon = Beacon.read(beacon_path, token)
    scenario_dirs = Provenance.scenario_dirs(out_dir)

    manifest =
      Manifest.build(%{
        leg: Atom.to_string(leg),
        git_start: git_start,
        git_end: git_end,
        harness: Provenance.resolve_harness(harness_dir),
        requirements: Map.put(requirements_info, "copy_sha256", copy_sha),
        invocation: %{
          "argv" => argv,
          "cwd" => cwd,
          "project_root" => project_root,
          "cwd_is_project_root" => Path.expand(cwd) == Path.expand(project_root),
          "adapter" => Atom.to_string(adapter_kind),
          "adapter_command" => adapter_command(leg, adapter_kind, port_no),
          "out_dir" => out_dir,
          "compiled_before_run" => compiled
        },
        timing: %{
          "started_at" => started.iso,
          "ended_at" => ended.iso,
          "utc_offset" => started.utc_offset,
          "duration_ms" => System.monotonic_time(:millisecond) - started_ms
        },
        toolchain: Provenance.toolchain(),
        beacon: %{
          "token" => token,
          "preflight_ok" => preflight_ok,
          "preflight_detail" => preflight_detail,
          "adapter_count" => beacon.adapter,
          "preflight_count" => beacon.preflight,
          "foreign_lines" => beacon.foreign,
          "unparseable_lines" => beacon.unparseable,
          "adapter_sources" => beacon.adapter_sources
        },
        result: %{
          "harness_exit_code" => exit_code,
          "console_sha256" => Provenance.sha256_string(console),
          "console_bytes" => byte_size(console),
          "expected_sha256" => Provenance.sha256_string(expected),
          "expected_bytes" => byte_size(expected),
          "expected_exit_code" => expected_exit,
          "scenario_dir_count" => length(scenario_dirs),
          "scenario_dirs" => scenario_dirs
        }
      })

    manifest_path = Path.join(out_dir, Manifest.filename())
    File.write!(manifest_path, Manifest.encode(manifest))

    log(
      "harness exit #{exit_code}; #{length(scenario_dirs)} scenario dirs; " <>
        "#{beacon.adapter} adapter beacons"
    )

    log("manifest: #{manifest_path}")

    {:ok, manifest, out_dir}
  end

  defp default_out_dir(leg, adapter_kind) do
    stamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(~r/[^0-9TZ]/, "")
    suffix = if adapter_kind == :sdk, do: "", else: "-#{adapter_kind}"
    Path.join("/tmp/mcp-conformance-runs", "#{leg}#{suffix}-#{stamp}")
  end

  # The runner compiles so the adapter cannot serve stale beams from an older
  # tree. This narrows R5's third residual; it does not close it (dependency
  # beams stay unbound).
  defp compile(root) do
    case System.cmd("mix", ["compile"], cd: root, stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp harness_argv(leg, harness_dir, requirements, out_dir, port_no) do
    dist =
      Path.join([
        harness_dir,
        "node_modules",
        "@modelcontextprotocol",
        "conformance",
        "dist",
        "index.js"
      ])

    base = ["node", dist, Atom.to_string(leg), "--requirements", requirements, "-o", out_dir]

    case leg do
      :server -> base ++ ["--url", "http://127.0.0.1:#{port_no}/mcp"]
      :client -> base ++ ["--command", adapter_command(:client, :sdk, port_no)]
    end
  end

  # A byte copy, not a re-render. The manifest hashes it, and the adjudicator
  # re-hashes it from disk, so the copy in the run directory is bound to the
  # file the run was scored against rather than merely resembling it.
  defp copy_requirements(nil, _out_dir), do: nil

  defp copy_requirements(path, out_dir) do
    dest = Path.join(out_dir, RequirementSet.requirements_copy_filename())

    case File.cp(path, dest) do
      :ok -> Provenance.sha256_file(dest)
      {:error, _} -> nil
    end
  end

  # Deliberately cwd-relative, exactly as the runs this ticket is fixing were
  # invoked. An absolute path here would silently repair the wrong-cwd failure
  # mode and there would be nothing left for the positive control to catch.
  defp adapter_command(:client, _kind, _port), do: "mix run conformance/client_adapter.exs"

  defp adapter_command(:server, :sdk, port),
    do: "mix run --no-halt #{@adapters.sdk} #{port}"

  defp adapter_command(:server, :null, port),
    do: "python3 #{@adapters.null} #{port}"

  defp invoke_harness([bin | args], cwd, env) do
    {out, code} = System.cmd(bin, args, cd: cwd, env: env, stderr_to_stdout: true)
    {out, code}
  rescue
    e -> {"harness could not be invoked: #{Exception.message(e)}\n", 127}
  end

  defp start_server_adapter(kind, cwd, port_no, env) do
    {bin, args} =
      case kind do
        :sdk -> {"mix", ["run", "--no-halt", @adapters.sdk, Integer.to_string(port_no)]}
        :null -> {"python3", [@adapters.null, Integer.to_string(port_no)]}
      end

    port =
      Port.open({:spawn_executable, System.find_executable(bin)}, [
        :binary,
        :exit_status,
        :hide,
        :stderr_to_stdout,
        {:args, args},
        {:cd, String.to_charlist(cwd)},
        {:env, Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)}
      ])

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    await_listening(port_no, 60)
    %{port: port, os_pid: os_pid}
  end

  defp stop_server_adapter(%{port: port, os_pid: os_pid}) do
    if os_pid,
      do: System.cmd("kill", ["-TERM", Integer.to_string(os_pid)], stderr_to_stdout: true)

    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    _ -> :ok
  end

  defp await_listening(_port_no, 0), do: :timeout

  defp await_listening(port_no, tries) do
    case :gen_tcp.connect(~c"127.0.0.1", port_no, [:binary, active: false], 250) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        :ok

      {:error, _} ->
        Process.sleep(250)
        await_listening(port_no, tries - 1)
    end
  end

  defp token, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  defp log(msg), do: Mix.shell().info("[conformance.run] " <> msg)
end
