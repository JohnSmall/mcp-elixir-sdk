defmodule Mix.Tasks.Conformance.InScope do
  @shortdoc "Freeze the in-scope 2026-07-28 subset as a keyed, machine-readable manifest"

  @moduledoc """
  Derive `docs/conformance/in-scope-2026-07-28.json` from the ACCEPTED censuses
  and the run trees they were written from.

      mix conformance.in_scope \\
        --server-census docs/conformance/server-2026-07-28.json \\
        --server-run /tmp/mes56r3-sdk \\
        --client-census docs/conformance/client-2026-07-28.json \\
        --client-run /tmp/mes57-f/sdk \\
        -o docs/conformance/in-scope-2026-07-28.json

  ## Why this is a generator and not a checked-in hand-written file

  AC1 requires the manifest to **re-derive** 44 scenarios / 175 checks from the
  artefacts rather than inherit them from a brief. A hand-written file cannot
  re-derive anything: it can only agree with a number somebody typed, which is
  the MES-24 defect aimed at the one artefact every downstream ticket counts
  against.

  ## What this task refuses

  A census whose `run.role` is not `measurement`, and a census whose
  adjudication verdict is not `accepted`. The manifest freezes the subset the
  published figures were measured over; deriving it from a control, a probe or
  an unadjudicated run would produce a plausible manifest over the wrong rows,
  and every downstream ticket would count against it without noticing.

  ## What it deliberately does NOT write

  A `census_schema_version` key. `test/conformance/classification_test.exs`
  globs `docs/conformance/*-2026-07-28*.json` — which this filename matches —
  decodes each file, and routes on that marker. Files carrying it are held to
  the census contract and fail without a conforming `scenarios` list; files
  without it are skipped deliberately. The decode happens before the routing,
  so invalid JSON in that directory still raises — one more reason this file is
  generated.

  ## Exit status

  `0` derived. `1` refused. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, InScope}

  @switches [
    server_census: :string,
    server_run: :string,
    client_census: :string,
    client_run: :string,
    out: :string
  ]

  @aliases [o: :out]

  @usage "mix conformance.in_scope --server-census FILE --server-run DIR " <>
           "--client-census FILE --client-run DIR [-o FILE]"

  @default_out "docs/conformance/in-scope-2026-07-28.json"

  @impl Mix.Task
  def run(argv) do
    {opts, _args} =
      Argv.parse!("conformance.in_scope", argv,
        strict: @switches,
        aliases: @aliases,
        positional: 0,
        usage: @usage
      )

    inputs =
      for leg <- ~w(server client) do
        census_path = fetch!(opts, :"#{leg}_census", "--#{leg}-census")
        run_dir = fetch!(opts, :"#{leg}_run", "--#{leg}-run")

        %{leg: leg, census: read_census!(census_path, leg), run_dir: run_dir(run_dir, leg)}
      end

    manifest = InScope.derive(inputs)
    out = opts[:out] || @default_out

    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Jason.encode!(manifest, pretty: true) <> "\n")

    report(manifest, out)
  end

  defp fetch!(opts, key, flag) do
    opts[key] || Mix.raise("#{flag} is required. #{@usage}")
  end

  defp run_dir(dir, leg) do
    if File.dir?(dir) do
      dir
    else
      Mix.raise(
        "--#{leg}-run #{dir} is not a directory. The manifest's rows are read from the " <>
          "run tree, not from the census, so a missing tree is a refusal and not a partial " <>
          "manifest."
      )
    end
  end

  # Checked against the census's own `run` block, which `MCP.Conformance.Census`
  # derived from the adapter registry and the adjudicator wrote its verdict
  # into. So this is not taking a filename's word for what a run is.
  defp read_census!(path, leg) do
    census = path |> File.read!() |> Jason.decode!()

    refuse_unless(census["run"]["leg"] == leg, path, "is the #{census["run"]["leg"]} leg")

    refuse_unless(
      census["run"]["role"] == "measurement",
      path,
      "has role #{census["run"]["role"]}"
    )

    refuse_unless(
      get_in(census, ["run", "adjudication", "verdict"]) == "accepted",
      path,
      "was adjudicated #{inspect(get_in(census, ["run", "adjudication", "verdict"]))}"
    )

    census
  end

  defp refuse_unless(true, _path, _what), do: :ok

  defp refuse_unless(false, path, what) do
    Mix.raise(
      "#{path} #{what} and was joined as an accepted measurement census. Freezing the " <>
        "in-scope subset over the wrong run produces a plausible manifest that every " <>
        "downstream ticket then counts against."
    )
  end

  defp report(manifest, out) do
    totals = manifest["totals"]
    key = manifest["check_key"]
    sources = key["rows_by_discriminator_source"]

    Mix.shell().info("""

    IN-SCOPE MANIFEST — #{manifest["revision"]}, written to #{out}

      in scope        #{totals["scenarios"]} scenarios / #{totals["checks"]} checks
                      server #{leg_line(totals, "server")}, client #{leg_line(totals, "client")}
      excluded        #{length(manifest["derivation"]["excluded"])} scenarios, each NAMED with a reason

      key             #{Enum.join(key["fields"], ", ")}
      distinct keys   #{key["distinct_keys"]} of #{key["rows"]} rows
      by rule         unique #{sources["unique"]}, field_issue #{sources["field_issue"]}, ordinal #{sources["ordinal"]}

      arithmetic      total = #{manifest["arithmetic"]["total"]}; in/out-of-denominator owned by #{manifest["arithmetic"]["owner"]}
    """)
  end

  defp leg_line(totals, leg) do
    %{"scenarios" => s, "checks" => c} = totals["by_leg"][leg]
    "#{s}/#{c}"
  end
end
