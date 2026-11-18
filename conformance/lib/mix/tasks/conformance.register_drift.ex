defmodule Mix.Tasks.Conformance.RegisterDrift do
  @shortdoc "Gate 9: would a fresh capture of the suite change the ET-CC register?"

  @moduledoc """
  Gate 9 (MES-241, `docs/procedure/gate-9.md`).

      mix conformance.register_drift
      mix conformance.register_drift --keep /tmp/fresh.json
      mix conformance.register_drift --fresh /tmp/fresh.json --json /tmp/report.json

  By default it captures the suite at HEAD (`MCP.Conformance.RowsDrift.capture!/0`:
  `mix test --seed 0` into a private, freshly made temporary directory, never the
  committed rows file). It refuses a capture that fails any RowsDrift guard (RD1-RD9) or
  any of the gate's provenance guards (RT1: the capture's tip is not HEAD; RT2: the tree
  being judged is dirty; RT3: the capture carries no `suite_rc`; RT5: an in-scope doctest
  unit names a module not defined under `lib/`), and then runs the three
  steps documented in `MCP.Conformance.RegisterDrift`: `reproduce`, `keysets` and
  `fresh`. Run it with the branch checked out and the tree clean. An unexpected exception
  inside a build is refused RT4, never reported as drift.

  ## Options

    * `--fresh FILE` adjudicates an existing capture instead of capturing. It must be a
      capture of HEAD that records `suite_rc` (RT1, RT3), such as one kept with `--keep`,
      and the tree must still be clean (RT2).
    * `--keep FILE` writes the adjudicated capture to FILE once it is taken, `suite_rc`
      included. Keep FILE outside the tree: an untracked file in it is refused RT2.
    * `--json OUT` also writes the `etcc-register-drift/1` report to OUT.

  `--fresh` and `--keep` are mutually exclusive.

  **Never-write.** Neither `--keep` nor `--json` may name the committed rows file
  (`docs/conformance/etcc-exunit-rows.json`) or the register
  (`docs/conformance/etcc-register.json`) by any route: it is checked before the capture
  and again at the write, which goes through `RowsDrift.write_output!/3`. A match exits
  64 and writes nothing. Re-capturing either file is the contributor's deliberate act
  (gate-9.md, "When it is red"), never a side effect of the gate.

  ## Exit status

  `0` clean. `1` drift: each red step is listed. `2` refused: the guard is named, and
  nothing was compared (RD1-RD9, RT1-RT3, RT5), or the instrument failed (RT4, with the
  exception). `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, RegisterDrift, RowsDrift}

  @switches [fresh: :string, keep: :string, json: :string]
  @usage "mix conformance.register_drift [--fresh FILE | --keep FILE] [--json OUT]"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = Argv.parse!("conformance.register_drift", argv, strict: @switches, usage: @usage)

    if Keyword.has_key?(opts, :fresh) and Keyword.has_key?(opts, :keep) do
      usage_error("--fresh and --keep are mutually exclusive\nusage: #{@usage}")
    end

    protected = RegisterDrift.protected()
    for flag <- [:keep, :json], out = opts[flag], do: refuse_protected!(flag, out, protected)

    {fresh, note} = fresh(opts, protected)

    report = RegisterDrift.check(fresh)
    Mix.shell().info(note)
    Mix.shell().info(RegisterDrift.render(report))

    if out = opts[:json] do
      write!(:json, out, Jason.encode_to_iodata!(report, pretty: true), protected)
    end

    case RegisterDrift.exit_status(report) do
      0 -> :ok
      n -> exit({:shutdown, n})
    end
  end

  defp fresh(opts, protected) do
    if path = opts[:fresh] do
      {read(path), "fresh: #{path} (given, not captured)"}
    else
      {artefact, path, _out} = RowsDrift.capture!()
      note = "fresh: captured at HEAD into #{path} (transcript #{path}.log)"

      if keep = opts[:keep] do
        # Checked again at the write itself: the capture took minutes (MES-240 R1-1).
        # The adjudicated artefact, suite_rc included, not the formatter's raw bytes: a
        # replay must be judged on the same facts as this run (MES-241 R2).
        write!(:keep, keep, RegisterDrift.keep_bytes(artefact, path), protected)
        {artefact, note <> "; copied to #{keep}"}
      else
        {artefact, note}
      end
    end
  end

  # Every output is checked before anything runs, and again at the write itself.
  defp refuse_protected!(flag, out, protected) do
    case Enum.find(protected, &RowsDrift.same_file?(out, &1)) do
      nil -> :ok
      p -> refuse(flag, out, p, "is")
    end
  end

  defp write!(flag, out, bytes, protected) do
    case RowsDrift.write_output!(out, bytes, protected) do
      :ok -> :ok
      {:refused, p} -> refuse(flag, out, p, "became")
    end
  end

  @spec refuse(atom(), String.t(), String.t(), String.t()) :: no_return()
  defp refuse(flag, out, p, verb) do
    usage_error(
      "--#{flag} #{out} #{verb} the protected file #{p} (resolved: #{RowsDrift.real_path(out)}). " <>
        "Gate 9 never writes the rows file or the register; re-capturing them is the " <>
        "contributor's act, not a side effect. Nothing was written."
    )
  end

  @spec usage_error(String.t()) :: no_return()
  defp usage_error(msg) do
    Mix.shell().error("mix conformance.register_drift: " <> msg)
    exit({:shutdown, Argv.usage_exit()})
  end

  defp read(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, %{} = a} <- Jason.decode(bytes) do
      a
    else
      _ -> :missing
    end
  end
end
