defmodule Mix.Tasks.Conformance.Figures do
  @shortdoc "G31: every population figure a hand-authored conformance input asserts, adjudicated at the tip"

  @moduledoc """
  Runs **G31** (`MCP.Conformance.InputFigures`) over this repository and prints
  its report.

      mix conformance.figures

  Exit **0** when every figure the hand-authored inputs assert is adjudicated
  and holds, every backticked field-name reference resolves, and the universe
  registry equals the walk. Exit **1** on any refusal, each printed as one line
  naming the guard, the refusal kind, the file and the field. Exit **64** usage
  error.

  The same audit runs in gate 5 (`test/conformance/input_figures_test.exs`), so
  this task is the reading instrument, not the enforcement.

  The report prints the PENDING count on every run. Pending is MES-131's
  remainder, and it may only shrink.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, InputFigures}

  @usage "mix conformance.figures"

  @impl Mix.Task
  def run(argv) do
    Argv.parse!("conformance.figures", argv, strict: [], usage: @usage)

    %{report: r, defects: defects} = InputFigures.load() |> InputFigures.audit()

    Mix.shell().info("""

    G31 — population figures in hand-authored conformance inputs

      universe      #{inspect(r["universe"])}
      scanned       #{r["files_scanned"]} hand-authored files
      visited       #{r["visited"]} figure occurrences
        measured    #{r["measured"]}   (against #{r["quantities"]} registered quantities)
        enumerated  #{r["enumerated"]}
        historical  #{r["historical"]}
        not_a_count #{r["not_a_count"]}
        pending     #{r["pending"]}   (MES-131; may only shrink)
        unparseable #{r["unparseable"]}
        refused     #{r["refused"]}
      references    #{r["references_visited"]} backticked snake_case tokens: #{r["references_in_data"]} resolve in the data, #{r["references_in_code"]} in the sources, #{r["references_exempt"]} exempted
    """)

    case defects do
      [] ->
        Mix.shell().info("  CLEAN — every figure is adjudicated and holds.\n")

      _ ->
        Enum.each(defects, &Mix.shell().info("  " <> InputFigures.format_defect(&1)))
        Mix.raise("G31 refused: #{length(defects)} defect(s) above.")
    end
  end
end
