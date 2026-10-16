defmodule Mix.Tasks.Conformance.StringCitations do
  @shortdoc "G33: string-form file:N citations in the conformance artefacts hold their pinned bytes"

  @moduledoc """
  Runs **G33** (`MCP.Conformance.StringCitations`) over this repository, or
  maintains its ledger.

      mix conformance.string_citations
      mix conformance.string_citations --repin [--accept <target>:<a>-<b>]...
      mix conformance.string_citations --resolve [--from REV]

  **No flag**: the audit, read-only. Exit **0** when every citation under
  `conformance/data/` and `docs/conformance/` has its ledger row, every row its
  citation, and every pinned window its bytes. Exit **1** on any refusal, each
  printed as one line naming the guard, the kind, the occurrence and the
  command that fixes it. The same audit runs in gate 5
  (`test/conformance/string_citations_test.exs`); this is the reading
  instrument, not the enforcement.

  **`--resolve`**: the M1 re-resolver, for a `lib/` or `test/` edit that moved
  cited lines. For each pinned window that no longer holds its bytes it
  requires the bytes to be at that address at `REV` (default:
  `git merge-base HEAD main`), unique there and not blank, and to occur exactly
  once now. It then rewrites every citation of that window in place, derived
  copies included, and moves the ledger rows; the shas do not change. It
  refuses to start unless the only reds are window drifts and the artefacts and
  the ledger are clean against HEAD, so its diff stands alone. A window it
  cannot move stays red, named with the reason.

  **`--repin`**: adds a `pin` row for each citation the ledger lacks, drops the
  rows of citations that are gone, and re-hashes at the tip only the windows
  named with `--accept`: a window rewritten in place whose citation still means
  it. It never assigns any other state.

  Both write only the artefacts and the ledger, and only when asked: nothing
  here runs under `mix test`. Exit **64** on a usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, StringCitations}

  @switches [repin: :boolean, accept: :keep, resolve: :boolean, from: :string]
  @usage "mix conformance.string_citations [--repin [--accept <target>:<a>-<b>]...] | [--resolve [--from REV]]"
  @roots ["conformance/data", "docs/conformance"]
  @instrument_roots ["test", "conformance/lib", "conformance/controls"]

  @impl Mix.Task
  def run(argv) do
    {opts, _} =
      Argv.parse!("conformance.string_citations", argv, strict: @switches, usage: @usage)

    accept = Keyword.get_values(opts, :accept)

    case mode(opts, accept) do
      {:usage, why} -> usage(why)
      :repin -> repin(accept)
      :resolve -> resolve(opts[:from])
      :audit -> audit()
    end
  end

  defp mode(opts, accept),
    do: mode(opts[:repin] == true, opts[:resolve] == true, accept != [], opts[:from] != nil)

  defp mode(true, true, _accept, _from), do: {:usage, "--repin and --resolve are separate runs"}
  defp mode(false, _resolve, true, _from), do: {:usage, "--accept needs --repin"}
  defp mode(_repin, false, _accept, true), do: {:usage, "--from needs --resolve"}
  defp mode(true, _resolve, _accept, _from), do: :repin
  defp mode(_repin, true, _accept, _from), do: :resolve
  defp mode(_repin, _resolve, _accept, _from), do: :audit

  defp usage(why) do
    Mix.shell().error(
      "USAGE ERROR  mix conformance.string_citations\n\n  #{why}\n\n  usage: #{@usage}"
    )

    exit({:shutdown, Argv.usage_exit()})
  end

  defp audit do
    %{report: r, defects: defects} = StringCitations.load() |> StringCitations.audit()
    Mix.shell().info(render(r, defects))
    if defects != [], do: Mix.raise("G33 refused: #{length(defects)} defect(s) above.")
  end

  defp repin(accept) do
    inputs = StringCitations.load()
    {ledger, rep} = inputs |> StringCitations.repin(accept) |> or_refuse("--repin")
    File.write!(StringCitations.ledger_path(), StringCitations.encode_ledger(ledger))

    Mix.shell().info(
      "G33 --repin: #{rep.added} row(s) added, #{rep.dropped} dropped, #{length(rep.accepted)} window(s) accepted"
    )

    for {key, old, new} <- rep.accepted do
      Mix.shell().info(
        "  ACCEPTED #{key}  #{String.slice(old || "", 0, 12)} -> #{String.slice(new, 0, 12)}"
      )

      Mix.shell().info("           now: #{window_now(key)}")
    end

    for d <- rep.refused, do: Mix.shell().info("  REFUSED  " <> StringCitations.format_defect(d))
    after_write(rep.refused)
  end

  defp window_now(key) do
    with [_, t, a, b] <- Regex.run(~r/\A(.+):(\d+)-(\d+)\z/, key),
         {:ok, src} <- File.read(t) do
      src
      |> String.split("\n")
      |> Enum.slice((String.to_integer(a) - 1)..(String.to_integer(b) - 1)//1)
      |> Enum.join(" / ")
      |> String.slice(0, 160)
    else
      _ -> "(unreadable)"
    end
  end

  defp resolve(from) do
    inputs = StringCitations.load()
    %{defects: defects} = StringCitations.audit(inputs)
    other = Enum.reject(defects, &(&1.kind == :window_drift))

    if other != [] do
      Enum.each(other, &Mix.shell().info(StringCitations.format_defect(&1)))

      Mix.raise(
        "G33 --resolve refused: the ledger has #{length(other)} red(s) that are not window drifts; clear them first"
      )
    end

    dirty = git(["status", "--porcelain", "--" | @roots ++ [StringCitations.ledger_path()]])

    if dirty != "" do
      Mix.raise(
        "G33 --resolve refused (dirty_paths): commit or stash these first, so the re-address is its own diff:\n#{dirty}"
      )
    end

    rev = from || String.trim(git(["merge-base", "HEAD", "main"]))
    base_read = &git_show(rev, &1)

    result = inputs |> StringCitations.resolve(base_read, instrument()) |> or_refuse("--resolve")

    for {art, bin} <- result.docs, do: File.write!(art, bin)
    File.write!(StringCitations.ledger_path(), StringCitations.encode_ledger(result.ledger))

    Mix.shell().info(
      "G33 --resolve from #{String.slice(rev, 0, 12)}: #{length(result.moved)} window(s) moved, #{result.edited} citation(s) re-addressed in #{map_size(result.docs)} file(s)"
    )

    for {t, a, b, a2} <- result.moved,
        do: Mix.shell().info("  MOVED    #{t}:#{a}-#{b} -> :#{a2}-#{a2 + b - a}")

    for d <- result.refused,
        do: Mix.shell().info("  REFUSED  " <> StringCitations.format_defect(d))

    after_write(result.refused)
  end

  # A malformed ledger is refused as input: nothing is written.
  defp or_refuse({:error, defects}, mode) do
    Enum.each(defects, &Mix.shell().info(StringCitations.format_defect(&1)))

    Mix.raise(
      "G33 #{mode} refused: the ledger is malformed (#{length(defects)} defect(s)); nothing was written"
    )
  end

  defp or_refuse(result, _mode), do: result

  defp after_write(refused) do
    %{report: r, defects: defects} = StringCitations.load() |> StringCitations.audit()
    Mix.shell().info(render(r, defects))

    if refused != [] or defects != [],
      do: Mix.raise("G33: #{length(refused)} refused, #{length(defects)} defect(s) remain.")
  end

  defp instrument do
    git(["ls-files", "--" | @instrument_roots])
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.ends_with?(&1, [".ex", ".exs", ".py"]))
    |> Enum.map(&{&1, File.read!(&1)})
  end

  defp git(args) do
    {out, 0} = System.cmd("git", args)
    out
  end

  defp git_show(rev, path) do
    case System.cmd("git", ["show", "#{rev}:#{path}"], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, String.trim(out)}
    end
  end

  @doc "The report, as printed."
  def render(r, defects) do
    states = r["states"] |> Enum.sort() |> Enum.map_join("  ", fn {k, v} -> "#{k} #{v}" end)

    classes =
      r["classes"]
      |> Enum.sort()
      |> Enum.map_join("\n", fn {k, v} -> "    #{String.pad_trailing(k, 34)} #{v}" end)

    lines = Enum.map_join(defects, "\n", &StringCitations.format_defect/1)

    """
    G33 STRING CITATIONS — #{StringCitations.ledger_path()}

      files #{r["files"]} (#{r["files_with_citations"]} with citations)   occurrences #{r["occurrences"]}   rows #{r["rows"]}   windows #{r["windows"]}
      byte-checked #{r["byte_checked"]}   #{states}
    #{classes}

    #{if defects == [], do: "  CLEAN", else: "  #{length(defects)} DEFECT(S)\n" <> lines}
    """
  end
end
