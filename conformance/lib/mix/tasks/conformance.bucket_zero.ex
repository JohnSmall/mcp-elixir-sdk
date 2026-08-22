defmodule Mix.Tasks.Conformance.BucketZero do
  @shortdoc "Sweep the in-scope 175 for structural unmatchability and write bucket 0"

  @moduledoc """
  Derive `docs/conformance/bucket-0-2026-07-28.json` — every in-scope check
  classified against the ratified match-target rule, with a reason each.

      mix conformance.bucket_zero \\
        --manifest docs/conformance/in-scope-2026-07-28.json \\
        --harness /tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js \\
        --control /tmp/mes57-f/null_exit0/http-standard-headers-2026-08-21T07-25-30-828Z \\
        -o docs/conformance/bucket-0-2026-07-28.json

  ## Why the harness is an input and not a memory

  Every bucket-0 citation is an address into a minified `dist/index.js`. An
  address is not evidence — the bytes at it are — and the harness lives in
  `/tmp` and is committed nowhere, so a citation to it is a citation to nothing
  after a wipe. This task therefore lifts the cited bytes **live** and writes
  them into the artefact, and refuses if the committed classification and the
  live file disagree about which addresses exist. A citation whose bytes have
  moved is worse than none, because it still reads as one.

  The committed artefact is what the tests read, so a clean checkout still
  verifies. What it loses is the ability to *re-derive*, which is the standing
  `/tmp` residual (R6 / MES-72), stated rather than discovered.

  ## Why the control is an input and not a description

  The claim that a SKIPPED-reading classifier is wrong by nine is a
  measurement, and the committed null-exit0 census records only a status
  HISTOGRAM — `{"SKIPPED": 11, "total": 11, ...}` — which is precisely the form
  that cannot tell 2 from 11. So the eleven KEYS are extracted here from the
  run tree, once, and committed inside this artefact as a named fixture with
  its provenance. The task asserts the extracted key set equals A1's eleven
  committed keys for that scenario and refuses otherwise: a control drawn from
  a different population proves nothing about this one.

  Hand-building the fixture instead would be the S5-22 shape and is not an
  option here.

  ## What it refuses

  A manifest whose total is not the frozen 175; a harness whose skip-site
  addresses do not match the committed classification; a control whose key set
  is not A1's; and any arithmetic that does not reconcile.

  ## Exit status

  `0` derived. `1` refused. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, BucketZero}

  @switches [manifest: :string, harness: :string, control: :string, out: :string]
  @aliases [o: :out]

  @usage "mix conformance.bucket_zero --manifest FILE --harness FILE --control DIR -o FILE"

  @impl Mix.Task
  def run(argv) do
    {opts, _} =
      Argv.parse!("conformance.bucket_zero", argv,
        strict: @switches,
        aliases: @aliases,
        usage: @usage
      )

    manifest_path = require!(opts, :manifest)
    harness_path = require!(opts, :harness)
    control_dir = require!(opts, :control)
    out = require!(opts, :out)

    manifest = manifest_path |> File.read!() |> Jason.decode!()

    refuse_unless(
      manifest["arithmetic"]["total"] == 175,
      "#{manifest_path} is not the frozen 175"
    )

    quotes =
      case BucketZero.verify_sites(harness_path) do
        {:ok, quotes} ->
          quotes

        {:error, reason} ->
          Mix.raise(
            "the committed skip-site classification does not match #{harness_path}: " <>
              "#{inspect(reason)}. Re-classify the sites before citing them; a citation whose " <>
              "bytes have moved still reads as one."
          )
      end

    control = control(control_dir, manifest)
    artefact = BucketZero.classify(manifest, control, quotes)

    reconcile!(artefact)
    File.write!(out, Jason.encode!(artefact, pretty: true) <> "\n")
    report(artefact, out)
  end

  # Extract the eleven control rows from the run tree, and prove they are the
  # same population as A1's eleven before letting anything rest on them.
  defp control(dir, manifest) do
    path = Path.join(dir, "checks.json")
    raw = File.read!(path)
    rows = Jason.decode!(raw)

    keys =
      Enum.map(rows, fn row ->
        ["client", "http-standard-headers", row["id"], row["name"], row["description"], ""]
      end)

    a1 =
      manifest["scenarios"]
      |> Enum.find(&(&1["scenario"] == "http-standard-headers"))
      |> Map.fetch!("checks")
      |> Enum.map(& &1["key"])

    refuse_unless(
      MapSet.new(keys) == MapSet.new(a1),
      "the control key set at #{path} is not A1's eleven http-standard-headers keys — it is not " <>
        "the same population and nothing may rest on it"
    )

    classified = Enum.map(rows, &control_verdict(&1["name"]))
    out = Enum.count(classified, &(&1 == 0))

    %{
      "name" => "null-exit0 / http-standard-headers",
      "what_it_is" =>
        "a null client that connects and exits 0, driving nothing. Every one of the eleven " <>
          "synthesised rows comes back SKIPPED.",
      "artefact_dir" => dir,
      "checks_json_sha256" => :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower),
      "rows" => length(rows),
      "statuses" => Enum.frequencies(Enum.map(rows, & &1["status"])),
      "key_set_equals_a1" => true,
      "keys" => keys,
      "classifier_result" => %{
        "out_of_denominator" => out,
        "in_denominator" => length(rows) - out
      },
      "naive_skipped_classifier_result" => %{
        "out_of_denominator" => Enum.count(rows, &(&1["status"] == "SKIPPED"))
      },
      "what_it_establishes" =>
        "The rule is not \"SKIPPED is excluded\", written as a measurement instead of an " <>
          "assertion: on this population a SKIPPED-reading classifier returns 11 where the truth " <>
          "is #{out}. The other #{length(rows) - out} are methods a conforming client MAY drive " <>
          "and that client did not — coverage gaps, bucket 2, in the denominator.",
      "why_it_matters" =>
        "It is what makes the criterion falsifiable. A classifier that could only ever return " <>
          "the in-scope run's answer would pass this ticket while ruling nothing out."
    }
  end

  defp control_verdict(name) do
    if Map.has_key?(BucketZero.members(), name), do: 0, else: nil
  end

  defp reconcile!(artefact) do
    a = artefact["arithmetic"]

    refuse_unless(
      a["in_denominator"] + a["out_of_denominator"] == a["total"],
      "the arithmetic does not reconcile: #{a["in_denominator"]} + #{a["out_of_denominator"]} " <>
        "!= #{a["total"]}"
    )

    refuse_unless(
      a["total"] == length(artefact["checks"]),
      "the total does not equal the number of classified rows"
    )
  end

  defp require!(opts, key) do
    Keyword.get(opts, key) ||
      Mix.raise("--#{key} is required.\n#{@usage}")
  end

  defp refuse_unless(true, _why), do: :ok
  defp refuse_unless(false, why), do: Mix.raise(why)

  defp report(artefact, out) do
    a = artefact["arithmetic"]
    v = artefact["vocabulary"]
    h = artefact["subset_hypothesis"]

    Mix.shell().info("""

    BUCKET 0 — #{artefact["revision"]}, written to #{out}

      arithmetic      #{a["in_denominator"]} + #{a["out_of_denominator"]} = #{a["total"]}
                      the word is #{a["word"]}

      vocabulary      #{v["token_site_totals"]["total"]} token sites, #{v["flag_write_totals"]["total"]} flag writes, #{length(v["flag_reads"])} flag reads
                      emits_check #{v["token_site_totals"]["emits_check"]}, emits_scenario #{v["token_site_totals"]["emits_scenario"]}, compares #{v["token_site_totals"]["compares"]}, message_only #{v["token_site_totals"]["message_only"]}

      subset test     direction 1 (non-SKIPPED yet unmatchable): #{h["direction_1"]["count"]}
                      direction 2 (SKIPPED yet matchable):       #{h["direction_2"]["count"]}

      control         #{artefact["control"]["name"]}
                      classifier #{artefact["control"]["classifier_result"]["out_of_denominator"]}, naive SKIPPED-reader #{artefact["control"]["naive_skipped_classifier_result"]["out_of_denominator"]}

      members         #{Enum.map_join(artefact["members"], ", ", & &1["name"])}
    """)
  end
end
