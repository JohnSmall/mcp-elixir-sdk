defmodule MCP.Conformance.Provenance do
  @moduledoc """
  The impure edge of the run-provenance tooling: git, the resolved harness, the
  clock and file hashes.

  Everything that shells out or reads the world lives here so that
  `MCP.Conformance.Manifest` — which decides whether a run may be quoted — stays
  a pure function of a map and can be unit-tested against fabricated runs.
  """

  @doc "Absolute path of the git worktree root containing `dir`, or `nil`."
  @spec project_root(String.t()) :: String.t() | nil
  def project_root(dir) do
    case git(dir, ["rev-parse", "--show-toplevel"]) do
      {:ok, out} -> Path.expand(out)
      :error -> nil
    end
  end

  @doc """
  Collect the git facts for `root`, ignoring anything under `exclude`.

  `exclude` is a list of absolute paths whose contents must not count towards
  the dirty computation. This closes C3: a run whose output directory sits
  inside the repository dirties the very tree it is measuring, and
  `WORKTREE_DIRTY` would then refuse every good run — a control that refuses
  everything is as useless as one that never fires. The excluded paths are
  recorded in the manifest so the exclusion is auditable rather than silent.

  ## An exclusion may never cover the root (B1)

  The C3 fix manufactured something strictly worse than the false-red it cured.
  An exclusion that *equals or contains* `root` silences the dirty computation
  over the **whole tree**: measured, `collect_git(root, [root])` returned
  `dirty: false` on a worktree with a modified tracked file. A false-red is loud
  and gets investigated; that false-green is silent and gets published.

  So a covering exclusion is **not applied**. It is moved to
  `dirty_exclusions_rejected`, the dirty computation runs as if it had never
  been asked for, and the rejection is carried into the manifest where
  `DIRTY_EXCLUSION_COVERS_ROOT` refuses the run outright. Dropping it silently
  would only move the lie one field along.

  `dirty_digest` is the sha256 of the (filtered) porcelain output, so "dirty" is
  a measurement with a fingerprint rather than a boolean assertion.
  """
  @spec collect_git(String.t(), [String.t()]) :: map()
  def collect_git(root, exclude \\ []) do
    {applied, rejected} = partition_exclusions(root, exclude)
    entries = porcelain_entries(root, applied)

    %{
      "commit_sha" => unwrap(git(root, ["rev-parse", "HEAD"])),
      "branch" => unwrap(git(root, ["rev-parse", "--abbrev-ref", "HEAD"])),
      "worktree_root" => root,
      "dirty" => entries != [],
      "dirty_entry_count" => length(entries),
      "dirty_entries" => Enum.take(entries, 50),
      "dirty_digest" => sha256_string(Enum.join(entries, "\n")),
      "dirty_excluded_paths" => Enum.sort(applied),
      "dirty_exclusions_rejected" => Enum.sort(rejected)
    }
  end

  @doc """
  Split `exclude` into the paths that may be honoured and those that may not.

  A path is rejected when it equals `root` or is an ancestor of it — either way
  it would suppress the dirty computation over the entire tree under
  measurement. Exposed because `MCP.Conformance.Manifest` applies the same
  predicate to a manifest it did not write.
  """
  @spec partition_exclusions(String.t(), [String.t()]) :: {[String.t()], [String.t()]}
  def partition_exclusions(root, exclude) do
    Enum.split_with(exclude, fn path -> not covers_root?(path, root) end)
  end

  @doc "Does `path` equal, or contain, the worktree `root`?"
  @spec covers_root?(String.t(), String.t()) :: boolean()
  def covers_root?(path, root), do: under?(Path.expand(root), Path.expand(path))

  defp porcelain_entries(root, exclude) do
    case git(root, ["status", "--porcelain"]) do
      {:ok, ""} ->
        []

      {:ok, out} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.reject(&excluded?(&1, root, exclude))

      :error ->
        []
    end
  end

  # A porcelain line is "XY path" or "XY orig -> new"; the path starts at
  # column 4. Renames are judged on the destination, which is the one that
  # exists.
  defp excluded?(line, root, exclude) do
    path =
      line
      |> String.slice(3..-1//1)
      |> String.split(" -> ")
      |> List.last()
      |> String.trim()
      |> String.trim("\"")

    abs = Path.expand(path, root)
    Enum.any?(exclude, &under?(abs, &1))
  end

  defp under?(path, dir) do
    dir = Path.expand(dir)
    path == dir or String.starts_with?(path, dir <> "/")
  end

  @doc """
  Resolve the conformance harness installed under `dir`.

  Records the version the binary *reports* alongside the sha256 of the dist
  bundle actually executed. The hash is what turns "the harness version" into a
  measurement: an alpha dist-tag can move under a fixed version string, and this
  project pinned an alpha channel deliberately.
  """
  @spec resolve_harness(String.t()) :: map()
  def resolve_harness(dir) do
    dist =
      Path.join([dir, "node_modules", "@modelcontextprotocol", "conformance", "dist", "index.js"])

    pkg = Path.join([dir, "node_modules", "@modelcontextprotocol", "conformance", "package.json"])

    %{
      "install_dir" => Path.expand(dir),
      "dist_path" => dist,
      "dist_sha256" => sha256_file(dist),
      "version_declared" => declared_version(pkg),
      "version_reported" => reported_version(dist),
      "node_version" => unwrap(cmd("node", ["--version"], dir))
    }
  end

  defp declared_version(pkg) do
    with {:ok, body} <- File.read(pkg),
         {:ok, %{"version" => v}} <- Jason.decode(body) do
      v
    else
      _ -> nil
    end
  end

  defp reported_version(dist) do
    case cmd("node", [dist, "--version"], Path.dirname(dist)) do
      {:ok, out} -> out
      :error -> nil
    end
  end

  @doc "Identity of the frozen requirement set the run was scored against."
  @spec resolve_requirements(String.t(), String.t()) :: map()
  def resolve_requirements(harness_dir, revision) do
    path =
      Path.join([
        harness_dir,
        "node_modules",
        "@modelcontextprotocol",
        "conformance",
        "requirements",
        "#{revision}.yaml"
      ])

    %{
      "revision" => revision,
      "path" => path,
      "exists" => File.exists?(path),
      "md5" => md5_file(path),
      "sha256" => sha256_file(path)
    }
  end

  @doc """
  Capture the harness's own listing of a frozen requirement set.

  Runs `conformance list --requirements REV` and returns its combined output and
  exit code verbatim. The output is written into the run directory as
  `expected.txt` and hashed into the manifest: the manifest already pins the
  frozen file's *identity* (path, md5, sha256) but never its **contents**, so
  without this capture a run directory cannot state its own denominator, and a
  scored scenario that silently did not run stays invisible.

  A non-zero exit is returned rather than raised. The adjudicator refuses on it,
  which is where a refusal belongs; raising here would abort a run that has
  already measured something and lose the evidence.
  """
  @spec capture_expected(String.t(), String.t()) :: {String.t(), integer()}
  def capture_expected(harness_dir, revision) do
    dist =
      Path.join([harness_dir, "node_modules", "@modelcontextprotocol", "conformance", "dist"])

    case System.cmd("node", [Path.join(dist, "index.js"), "list", "--requirements", revision],
           cd: harness_dir,
           stderr_to_stdout: true
         ) do
      {out, code} -> {out, code}
    end
  rescue
    e -> {"`conformance list` could not be invoked: #{Exception.message(e)}\n", 127}
  end

  @doc "Elixir/OTP/Mix facts for the tree that produced the run."
  @spec toolchain() :: map()
  def toolchain do
    %{
      "elixir" => System.version(),
      "otp" => System.otp_release(),
      "mix_env" => Atom.to_string(Mix.env())
    }
  end

  @doc """
  Current UTC instant with an explicit `Z`, plus the container's local offset.

  R2: a bare local timestamp in a provenance record is a defect. Both halves are
  recorded so a reader can relate these stamps to Jira's +0100 without guessing
  which clock they came from.
  """
  @spec now() :: %{iso: String.t(), utc_offset: String.t()}
  def now do
    %{iso: DateTime.to_iso8601(DateTime.utc_now()), utc_offset: local_utc_offset()}
  end

  defp local_utc_offset do
    seconds = NaiveDateTime.diff(NaiveDateTime.local_now(), NaiveDateTime.utc_now())
    minutes = round(seconds / 60)
    sign = if minutes < 0, do: "-", else: "+"
    abs_minutes = abs(minutes)

    sign <>
      String.pad_leading(Integer.to_string(div(abs_minutes, 60)), 2, "0") <>
      ":" <> String.pad_leading(Integer.to_string(rem(abs_minutes, 60)), 2, "0")
  end

  @doc """
  Every scenario directory under `run_dir`, as sorted paths relative to it.

  A *scenario directory* is one that holds a `checks.json` — the harness's own
  unit of a scored scenario. The walk is RECURSIVE and that is the whole point:
  the harness nests suite scenarios one level deeper, so `auth/` is a single
  top-level entry holding 31 checks-bearing directories of its own. A top-level
  count reported 9 where the truth was 39, understating by a factor of four.
  Naming a number after something it does not count is this ticket's own subject
  matter, so it is counted properly here.

  Both the runner (recording) and the adjudicator (observing) call THIS function.
  Two copies of the walk could drift apart and manufacture a spurious
  `ARTEFACTS_INCONSISTENT` on a perfectly good run.
  """
  @spec scenario_dirs(String.t()) :: [String.t()]
  def scenario_dirs(run_dir) do
    run_dir
    |> walk()
    |> Enum.map(&Path.relative_to(&1, run_dir))
    |> Enum.sort()
  end

  defp walk(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        here = if File.regular?(Path.join(dir, "checks.json")), do: [dir], else: []

        entries
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.flat_map(&walk/1)
        |> Kernel.++(here)

      {:error, _} ->
        []
    end
  end

  @doc """
  Describe a run directory as it stands NOW, for `MCP.Conformance.Manifest.judge/3`.

  Lives here rather than in either caller because both `mix
  conformance.adjudicate` and `mix conformance.census` must judge the same run
  identically: two copies of this could drift and let a figure be printed from a
  run the adjudicator would have refused.

  Every artefact is read **once** and returned as body *and* hash from that one
  read, so a file cannot pass its hash comparison and then be parsed from a
  different version of itself.
  """
  @spec observe_run(String.t()) :: map()
  def observe_run(run_dir) do
    console = read_artefact(run_dir, "console.txt")
    expected = read_artefact(run_dir, "expected.txt")
    copy = read_artefact(run_dir, "requirements.yaml")

    %{
      # Where the run is being read FROM, which is not always where it was
      # written to: `invocation.out_dir` is the path the harness wrote, and an
      # archived or copied run is judged on its contents rather than on where it
      # now sits. The client leg's scenario key walks the artefact tree, so it
      # needs the tree that exists rather than the one that used to.
      run_dir: Path.expand(run_dir),
      scenario_dirs: scenario_dirs(run_dir),
      console_sha256: console.sha256,
      console_body: console.body,
      expected_sha256: expected.sha256,
      expected_body: expected.body,
      requirements_copy_sha256: copy.sha256,
      requirements_body: copy.body
    }
  end

  defp read_artefact(run_dir, name) do
    case File.read(Path.join(run_dir, name)) do
      {:ok, body} -> %{body: body, sha256: sha256_string(body)}
      {:error, _} -> %{body: nil, sha256: nil}
    end
  end

  @doc "sha256 of a file's contents as lowercase hex, or `nil` if unreadable."
  @spec sha256_file(String.t()) :: String.t() | nil
  def sha256_file(path) do
    case File.read(path) do
      {:ok, body} -> sha256_string(body)
      {:error, _} -> nil
    end
  end

  @doc "md5 of a file's contents as lowercase hex, or `nil` if unreadable."
  @spec md5_file(String.t()) :: String.t() | nil
  def md5_file(path) do
    case File.read(path) do
      {:ok, body} -> Base.encode16(:crypto.hash(:md5, body), case: :lower)
      {:error, _} -> nil
    end
  end

  @doc "sha256 of a binary as lowercase hex."
  @spec sha256_string(binary()) :: String.t()
  def sha256_string(body), do: Base.encode16(:crypto.hash(:sha256, body), case: :lower)

  defp git(dir, args), do: cmd("git", ["-C", dir | args], dir)

  defp cmd(bin, args, dir) do
    case System.cmd(bin, args, cd: dir, stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp unwrap({:ok, out}), do: out
  defp unwrap(:error), do: nil
end
