defmodule Mix.Tasks.Conformance.Adjudications do
  @shortdoc "G32: every edge a bound view projects is adjudicated exactly once, by a closed disposition"

  @moduledoc """
  Runs **G32** (`MCP.Conformance.Adjudications`) over this repository and
  prints its report.

      mix conformance.adjudications

  Exit **0** when every record under `docs/conformance/adjudications/` equals
  the views its sections bind, both ways, with every disposition in the closed
  set and every repository citation holding its bytes. Exit **1** on any
  refusal, each printed as one line naming the guard, the refusal kind, the
  record file and the edge key. Exit **64** on a usage error.

  The same audit runs in gate 5 (`test/conformance/adjudications_test.exs`).
  This task is the reading instrument, not the enforcement.
  """

  use Mix.Task

  alias MCP.Conformance.{Adjudications, Argv}

  @usage "mix conformance.adjudications"

  @impl Mix.Task
  def run(argv) do
    Argv.parse!("conformance.adjudications", argv, strict: [], usage: @usage)

    %{report: r, defects: defects} = Adjudications.load() |> Adjudications.audit()
    Mix.shell().info(render(r, defects))

    if defects != [], do: Mix.raise("G32 refused: #{length(defects)} defect(s) above.")
  end

  @doc """
  The universe line: how many views are owed a record, how many a closed
  section closes, and each pending view with the ticket that closes it.
  """
  def views(r) do
    pending =
      r["pending"]
      |> Enum.sort()
      |> Enum.map_join(", ", fn {v, t} -> "#{short(v)} (#{t})" end)

    "owed #{r["owed"]} — closed #{length(r["closed"])}, pending #{map_size(r["pending"])}: #{pending}"
  end

  defp short(view),
    do: view |> Path.basename(".json") |> String.replace(~r/-\d{4}-\d{2}-\d{2}$/, "")

  @doc """
  The printed report. A count of citations VERIFIED is printed only on a clean
  audit: a refused run verifies nothing, so it prints what it found and how
  many drifted instead (MES-135 K5).
  """
  def render(r, defects) do
    citations =
      case defects do
        [] ->
          "#{r["repo_citations_holding"]} repository citations verified at the tip; " <>
            "#{r["harness_citations_not_verified_in_gate_5"]} harness citations NOT verified here (control `harness` mode)"

        _ ->
          "#{r["repo_citations_found"]} repository citations found, " <>
            "#{r["repo_citations_found"] - r["repo_citations_holding"]} drifted; " <>
            "#{r["harness_citations_not_verified_in_gate_5"]} harness citations — a refused run verifies nothing"
      end

    verdict =
      case defects do
        [] -> ["  CLEAN — every bound view is adjudicated, both ways.\n"]
        _ -> Enum.map(defects, &("  " <> Adjudications.format_defect(&1)))
      end

    Enum.join(
      [
        """

        G32 — D-group adjudication records against their views

          views         #{views(r)}
          records       #{r["records_visited"]}   (#{r["sections"]} sections over #{r["views_bound"]} views)
          rows          #{r["rows_visited"]}
          dispositions  #{inspect(r["dispositions"])}
          citations     #{citations}
        """
        | verdict
      ],
      "\n"
    )
  end
end
