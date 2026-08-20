defmodule MCP.Conformance.Beacon do
  @moduledoc """
  Startup beacon for the conformance adapters.

  ## Why this exists

  MES-49 measured a *null client* — a script whose entire body is `exit 0` — at
  2/32, with a census of 13 SUCCESS / 83 FAILURE / 17 SKIPPED / 1 INFO. That is
  identical, check for check, to the misconfigured wrong-cwd run from MES-19
  Control A. A run whose adapter never started is therefore indistinguishable,
  from the artefacts alone, from having no implementation at all.

  `invocation.cwd` separates the *wrong-cwd* case, but it cannot separate the
  general one: an adapter can fail to start from the right directory. The beacon
  is the mechanism that can. Each adapter appends one line at startup; the
  manifest records how many such lines carry this run's token, and the
  adjudicator refuses a run with zero of them against a full sheet of scenario
  directories (`ADAPTER_NEVER_STARTED`).

  ## Discipline — this module is loaded by the measurement instrument

  MES-56 and MES-57 measure with the adapters this hooks into, so the hook is
  constrained on purpose:

    * it is a **no-op** unless both `MCP_CONFORMANCE_BEACON` and
      `MCP_CONFORMANCE_BEACON_TOKEN` are set;
    * it writes to a file and **never** to stdout, stderr or the wire, so it
      cannot enter a transcript the harness scores;
    * it cannot raise and cannot change an exit code — every failure path
      returns an atom;
    * it is off the protocol path by construction: nothing in `MCP.*` calls it.

  The cost of that safety is that a *broken* beacon is silent, which would make
  `beacon_count: 0` ambiguous between "the adapter never started" and "the
  beacon never worked" — a false-red, and a false-red teaches people to bypass
  the gate. `preflight/2` closes that: the runner proves this mechanism can
  write and be read back **before** launching the adapter, and records the
  result in the manifest. A later count of zero then means the adapter.
  """

  @env_path "MCP_CONFORMANCE_BEACON"
  @env_token "MCP_CONFORMANCE_BEACON_TOKEN"

  @roles [:preflight, :adapter]

  @doc "Name of the environment variable carrying the beacon file path."
  @spec env_path_var() :: String.t()
  def env_path_var, do: @env_path

  @doc "Name of the environment variable carrying this run's beacon token."
  @spec env_token_var() :: String.t()
  def env_token_var, do: @env_token

  @doc """
  Append one beacon line for `role`, attributing it to `source`.

  Returns `:ok` when a line was written, `:noop` when the environment does not
  ask for one, and `:error` when the write failed. Never raises: an adapter that
  crashed here would perturb the very measurement the beacon exists to attest.
  """
  @spec emit(:preflight | :adapter, term()) :: :ok | :noop | :error
  def emit(role, source) when role in @roles do
    with path when is_binary(path) <- System.get_env(@env_path),
         token when is_binary(token) <- System.get_env(@env_token) do
      append(path, line(token, role, source))
    else
      _ -> :noop
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  @doc """
  Prove the beacon mechanism works, before the adapter is launched (C1).

  Writes a `preflight` line through the same code path `emit/2` uses, then reads
  it back through the same parser the manifest is built with. Returns
  `{:ok, detail}` or `{:error, detail}`; the detail map is recorded in the
  manifest either way, so the evidence survives the run.
  """
  @spec preflight(String.t(), String.t()) :: {:ok, map()} | {:error, map()}
  def preflight(path, token) do
    written = append(path, line(token, :preflight, __MODULE__))
    counts = read(path, token)

    detail = %{
      "write_result" => to_string(written),
      "preflight_lines_read_back" => counts.preflight,
      "beacon_path" => path
    }

    if written == :ok and counts.preflight > 0 do
      {:ok, Map.put(detail, "ok", true)}
    else
      {:error, Map.put(detail, "ok", false)}
    end
  end

  @doc """
  Classify the lines in a beacon file against `token`.

  `foreign` counts lines carrying some *other* token. A run directory is created
  fresh, so a foreign line means the directory was reused — the MES-24
  stale-artefact defect, visible in the beacon rather than asserted about it.
  `unparseable` counts lines that are not JSON objects.
  """
  @spec read(String.t(), String.t()) :: %{
          adapter: non_neg_integer(),
          preflight: non_neg_integer(),
          foreign: non_neg_integer(),
          unparseable: non_neg_integer(),
          adapter_sources: [String.t()]
        }
  def read(path, token) do
    path
    |> File.read()
    |> case do
      {:ok, body} -> String.split(body, "\n", trim: true)
      {:error, _} -> []
    end
    |> Enum.reduce(
      %{adapter: 0, preflight: 0, foreign: 0, unparseable: 0, adapter_sources: []},
      &classify(&1, token, &2)
    )
    |> Map.update!(:adapter_sources, &Enum.sort(Enum.uniq(&1)))
  end

  defp classify(raw, token, acc) do
    case Jason.decode(raw) do
      {:ok, %{"token" => ^token, "role" => "adapter"} = row} ->
        %{acc | adapter: acc.adapter + 1}
        |> Map.update!(:adapter_sources, &[Map.get(row, "source", "?") | &1])

      {:ok, %{"token" => ^token, "role" => "preflight"}} ->
        %{acc | preflight: acc.preflight + 1}

      {:ok, %{"token" => _}} ->
        %{acc | foreign: acc.foreign + 1}

      _ ->
        %{acc | unparseable: acc.unparseable + 1}
    end
  end

  defp line(token, role, source) do
    Jason.encode!(%{
      "token" => token,
      "role" => Atom.to_string(role),
      "source" => to_string(source),
      "os_pid" => System.pid(),
      # Explicit offset per R2. Everything this tooling stamps is UTC with a
      # literal `Z`; the container clock is UTC and Jira renders +0100, and
      # reading one as the other has already manufactured a phantom stall here.
      "at" => DateTime.to_iso8601(DateTime.utc_now())
    })
  end

  # Total by construction. `preflight/2` calls this directly, and a raise here
  # would crash the runner on exactly the pre-flight whose job is to report a
  # broken beacon calmly. Caught by the unwritable-path pair in
  # `manifest_test.exs`, which is what a control is for.
  defp append(path, payload) do
    with :ok <- mkdir_p(Path.dirname(path)),
         {:ok, _} <- File.open(path, [:append, :binary], &IO.binwrite(&1, payload <> "\n")) do
      :ok
    else
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp mkdir_p(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end
end
