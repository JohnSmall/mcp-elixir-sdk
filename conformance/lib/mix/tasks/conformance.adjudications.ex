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

    Mix.shell().info("""

    G32 — D-group adjudication records against their views

      records       #{r["records_visited"]}   (#{r["sections"]} sections over #{r["views_bound"]} views)
      rows          #{r["rows_visited"]}
      dispositions  #{inspect(r["dispositions"])}
      citations     #{r["citations_verified"]} repository citations verified at the tip; #{r["harness_citations_not_verified_in_gate_5"]} harness citations NOT verified here (control `harness` mode)
    """)

    case defects do
      [] ->
        Mix.shell().info("  CLEAN — every bound view is adjudicated, both ways.\n")

      _ ->
        Enum.each(defects, &Mix.shell().info("  " <> Adjudications.format_defect(&1)))
        Mix.raise("G32 refused: #{length(defects)} defect(s) above.")
    end
  end
end
