defmodule Mix.Tasks.Conformance.RowsDrift do
  @shortdoc "Capture the suite fresh and compare it with the committed etcc-exunit-rows.json"

  @moduledoc """
  The test-rows drift check (MES-240). `docs/procedure/end-of-sprint.md` step 6 runs it at
  the sprint's final tip.

      mix conformance.rows_drift
      mix conformance.rows_drift --keep /tmp/fresh.json --json /tmp/drift.json
      mix conformance.rows_drift --fresh /tmp/fresh.json
      mix conformance.rows_drift --committed-at main

  By default it captures the suite at HEAD, running `mix test --seed 0` with
  `MCP_ETCC_ROWS` naming a temporary file and never the committed one. It then compares
  that capture with `docs/conformance/etcc-exunit-rows.json` in the working tree. The
  comparison and its refusal guards are documented in `MCP.Conformance.RowsDrift`.

  ## Options

    * `--committed FILE` compares against FILE instead of the committed path.
    * `--committed-at REF` compares against `git show REF:docs/conformance/etcc-exunit-rows.json`.
      This is the per-ticket entry MES-241 needs, for a base and a tip.
    * `--fresh FILE` adjudicates an existing capture instead of capturing.
    * `--keep FILE` copies the fresh capture to FILE once it is taken. The capture
      itself is always made in a private, freshly created temporary directory.
    * `--json OUT` also writes the `etcc-rows-drift/1` report to OUT.

  **Never-write.** Neither `--keep` nor `--json` may name the committed rows file, or the
  `--committed` file, by any route. Paths are compared with every symlink resolved and,
  when both exist, by device and inode (`MCP.Conformance.RowsDrift.same_file?/2`). A match
  exits 64 before anything is captured or written.

  **Comparable refs for `--committed-at`.** The earliest committed rows file that passes
  every guard is `b439347` (MES-230, 2026-11-14). The two before it, `18df3a6` (MES-84)
  and `1a0fe5c` (MES-83), predate `run.row_errors` and are refused RD3. A base at or after
  `b439347` is comparable; one before it is refused, never compared.

  **Outputs are re-checked at the write.** `--keep` and `--json` are checked again just
  before each is written, and written by an exclusive temporary file renamed over the
  target in its resolved real directory (`RowsDrift.write_output!/3`), so a link planted
  during the capture is refused (64) and a link at the final name is replaced, not
  followed.

  `--committed` and `--committed-at` are mutually exclusive, and so are `--fresh` and
  `--keep`.

  ## Exit status

  `0` clean. `1` drift: every drifted key is listed by class. `2` refused: the guard is
  named, and nothing was compared. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, RowsDrift}

  @switches [
    committed: :string,
    committed_at: :string,
    fresh: :string,
    keep: :string,
    json: :string
  ]
  @usage "mix conformance.rows_drift [--committed FILE | --committed-at REF] " <>
           "[--fresh FILE | --keep FILE] [--json OUT]"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = Argv.parse!("conformance.rows_drift", argv, strict: @switches, usage: @usage)
    exclusive!(opts, :committed, :committed_at)
    exclusive!(opts, :fresh, :keep)

    protected = protected(opts)
    never_write!(opts, protected)

    committed = committed(opts)
    {fresh, note} = fresh(opts, protected)

    report = RowsDrift.check(committed, fresh)
    Mix.shell().info(note)
    Mix.shell().info(RowsDrift.render(report))

    if out = opts[:json] do
      write!(:json, out, Jason.encode_to_iodata!(report, pretty: true), protected)
    end

    case RowsDrift.exit_status(report) do
      0 -> :ok
      n -> exit({:shutdown, n})
    end
  end

  defp exclusive!(opts, a, b) do
    if Keyword.has_key?(opts, a) and Keyword.has_key?(opts, b) do
      Mix.shell().error(
        "mix conformance.rows_drift: --#{dash(a)} and --#{dash(b)} are mutually exclusive\n" <>
          "usage: #{@usage}"
      )

      exit({:shutdown, Argv.usage_exit()})
    end
  end

  # The never-write condition (MES-240 F1). The protected files are the committed rows file
  # and, when given, the --committed file. No output path (--keep, --json) may name one of
  # them by any route: literally, through a symlink in any parent directory, or through a
  # hard link. `RowsDrift.same_file?/2` decides that, never a lexical comparison.
  defp protected(opts) do
    Enum.reject([RowsDrift.committed_path(), opts[:committed]], &is_nil/1)
  end

  defp never_write!(opts, protected) do
    for flag <- [:keep, :json], out = opts[flag], p <- protected, RowsDrift.same_file?(out, p) do
      Mix.shell().error(
        "mix conformance.rows_drift: --#{flag} #{out} is the protected file #{p} " <>
          "(resolved: #{RowsDrift.real_path(out)}). This check never writes a rows file it " <>
          "compares against; re-capturing it is a ticket, not a side effect."
      )

      exit({:shutdown, Argv.usage_exit()})
    end

    :ok
  end

  # Every output goes through `RowsDrift.write_output!/3`, which re-checks the protected
  # files at the write itself and writes by rename (MES-240 R1-1).
  defp write!(flag, out, bytes, protected) do
    case RowsDrift.write_output!(out, bytes, protected) do
      :ok ->
        :ok

      {:refused, p} ->
        Mix.shell().error(
          "mix conformance.rows_drift: --#{flag} #{out} became the protected file #{p} " <>
            "during the run (resolved: #{RowsDrift.real_path(out)}). Nothing was written."
        )

        exit({:shutdown, Argv.usage_exit()})
    end
  end

  defp dash(k), do: k |> Atom.to_string() |> String.replace("_", "-")

  defp committed(opts) do
    if ref = opts[:committed_at] do
      case System.cmd("git", ["show", "#{ref}:#{RowsDrift.committed_path()}"],
             stderr_to_stdout: true
           ) do
        {bytes, 0} -> decode(bytes)
        {_, _} -> :missing
      end
    else
      read(opts[:committed] || RowsDrift.committed_path())
    end
  end

  defp fresh(opts, protected) do
    if path = opts[:fresh] do
      {read(path), "fresh: #{path} (given, not captured)"}
    else
      {artefact, path, _out} = RowsDrift.capture!()
      note = "fresh: captured at HEAD into #{path} (transcript #{path}.log)"

      if keep = opts[:keep] do
        # Checked again at the write itself: the capture took minutes (R1-1).
        write!(:keep, keep, File.read!(path), protected)
        {artefact, note <> "; copied to #{keep}"}
      else
        {artefact, note}
      end
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, bytes} -> decode(bytes)
      {:error, _} -> :missing
    end
  end

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{} = a} -> a
      _ -> :missing
    end
  end
end
