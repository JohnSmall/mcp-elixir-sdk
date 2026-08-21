defmodule Mix.Tasks.Conformance.Discounts do
  @shortdoc "Derive the client leg's in-scope figure and its two discounts from committed censuses"

  @moduledoc """
  Read the measurement census, the null-control censuses and the probe census,
  and render the headline figure with every subtraction behind it.

      mix conformance.discounts docs/conformance/client-2026-07-28.json \\
        --null docs/conformance/client-2026-07-28-null-exit0.json \\
        --null docs/conformance/client-2026-07-28-null-connect.json \\
        --null docs/conformance/client-2026-07-28-null-request.json \\
        --probe docs/conformance/client-2026-07-28-probe-strict-connect.json \\
        --markdown docs/conformance/client-2026-07-28-discounts.md

  ## Options

    * `--null` — a null-control census. **Repeatable**, and on this leg it should
      be repeated: a stricter null scores LOWER, so "the null control" is not one
      number and one of them cannot stand for the rest.
    * `--probe` — the `strict_connect` census, which is what makes discount 1 a
      measurement rather than an inheritance.
    * `--markdown` — render to this path. Rendered FROM the derivation, never
      written beside it.

  ## What this task refuses

  A census whose `run.role` is not what the flag says it is. A control joined as
  the measurement, or the measurement joined as a null, would produce a
  plausible headline computed against the wrong thing — and the whole point of
  `MCP.Conformance.Adapters`' role field is that nothing has to remember which
  file is which.

  ## Exit status

  `0` derived. `1` refused. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Adapters, Argv, Discounts}

  @switches [null: :keep, probe: :string, markdown: :string]

  @usage "mix conformance.discounts MEASUREMENT_CENSUS --null NULL_CENSUS [--null ...] " <>
           "[--probe PROBE_CENSUS] [--markdown FILE]"

  @impl Mix.Task
  def run(argv) do
    {opts, [measurement_path]} =
      Argv.parse!("conformance.discounts", argv,
        strict: @switches,
        positional: 1,
        usage: @usage
      )

    measurement = read!(measurement_path, "measurement")

    nulls =
      opts
      |> Keyword.get_values(:null)
      |> Map.new(&{label(&1), read!(&1, "control")})

    probe = opts[:probe] && read!(opts[:probe], "probe")

    if nulls == %{} do
      Mix.raise(
        "--null is required at least once. A client figure with no null control cannot " <>
          "state which of its passes are ours alone, and MES-49 measured a null client at " <>
          "2/32 to show that the difference is not small."
      )
    end

    # From the registry, never from a flag. An operator-supplied scope would be a
    # number-moving parameter on the headline, and the probe reads the same
    # declaration to decide what to drive.
    derived =
      Discounts.derive(
        measurement: measurement,
        nulls: nulls,
        probe: probe,
        probe_scope: probe && Adapters.scope(:client, "strict_connect")
      )

    if path = opts[:markdown] do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Discounts.to_markdown(derived, measurement["run"]))
      Mix.shell().info("markdown: #{path}")
    end

    report(derived)
  end

  # The role check, done against the census's own `run.role` — which
  # `MCP.Conformance.Census` derived from the adapter registry and corroborated
  # against `beacon.jsonl` on disk. So this is not taking a filename's word for
  # what a run is.
  defp read!(path, expected_role) do
    census = path |> File.read!() |> Jason.decode!()
    role = get_in(census, ["run", "role"])

    if role != expected_role do
      Mix.raise(
        "#{path} has role #{inspect(role)} and was passed as the #{expected_role}. " <>
          "Deriving a headline against the wrong role produces a plausible number computed " <>
          "from the wrong run, which is the one failure mode a role field exists to prevent."
      )
    end

    census
  end

  defp label(path), do: path |> Path.basename(".json") |> String.replace_prefix("client-", "")

  defp report(d) do
    n = length(d.in_scope)

    Mix.shell().info("""

    CLIENT LEG — in-scope figure, reducer client_summary

      in scope                 #{n} scenarios (scored, not auth/*)
      as driven                #{length(d.as_driven)} of #{n}
      after drive-policy only  #{length(d.after_drive_policy)} of #{n}   removed: #{inspect(d.drive_policy_removed)}
                               (probe scope: #{inspect(d.probe_scope)} — outside it the probe says nothing)
      after null-passable only #{length(d.after_null_passable)} of #{n}   removed: #{inspect(d.null_passable_removed)}
      SURVIVING BOTH           #{length(d.surviving_both)} of #{n}   #{inspect(d.surviving_both)}

      raw                      #{length(d.raw.scored_passed)} of #{d.raw.scored_total} scored — quotable ONLY beside the
                               ADR-003 exclusion of #{length(d.excluded_auth)} auth/* scenarios, never as a bare rate
    """)
  end
end
