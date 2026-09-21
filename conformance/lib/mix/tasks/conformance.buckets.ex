defmodule Mix.Tasks.Conformance.Buckets do
  @shortdoc "Project C1a's crosswalk into the ten bucket views, the escalated view and the roll-up"

  @moduledoc """
  Render `docs/conformance/buckets/` — the ten bucket views the E group's pages
  display and E2's partition proof consumes.

      mix conformance.buckets \\
        --crosswalk docs/conformance/crosswalk-2026-07-28.json \\
        --bucket-zero docs/conformance/bucket-0-2026-07-28.json \\
        -o docs/conformance/buckets

      mix conformance.buckets --check          # regenerate, byte-compare, write nothing

  ## It PROJECTS. It does not decide.

  Every view is a filter on fields C1a's crosswalk already stores.
  `MatchKey.bucket/1` is not called here, no axis is re-read, no verdict and no
  edge shape is re-derived. A renderer that re-derived a bucket's membership by
  its own logic would be a second record of one fact — the drift the single
  matrix was built to remove.

  What that gives up is stated in the roll-up rather than left implicit: a green
  run says the views faithfully project the crosswalk, **not** that the
  crosswalk is internally consistent. Matrix consistency is C1's `reconcile!`
  and C3's falsification controls.

  ## What it refuses

  * **A crosswalk with no cells** — ten clean empty views over an empty matrix
    satisfy every partition check here perfectly. That is the S9-15 vacuum.
  * **A leg outside `MatchKey.legs/0`**, on a cell or on a declared check. The
    2a/2b and 5a/5b splits are by leg, so an unknown leg drops the row out of
    both halves and breaks the partition *silently*.
  * **An edge partition that does not hold** — the six edge views plus the
    escalated view must set-equal the cells, both directions, and no two views
    of one universe may share a row.
  * **A member partition that does not hold** — bucket 1 and the members
    carrying an edge must set-equal the declared members, and bucket 1 must
    equal the set the crosswalk declares unmatched.
  * **A check partition that does not hold** — 2a, 2b and the checks carrying
    an edge must set-equal the declared checks.

  Every one is a SET comparison in both directions with the negatives
  enumerated, never a count: a dropped row and an added one reconcile perfectly
  on a count.

  ## `--check` is the no-op control

  It regenerates into a temporary directory and byte-compares every file
  against the committed one, writing nothing. Exit 1 names the files that
  differ and the files that are missing or extra. It is run **before** any
  other work on the views, so that a later diff means a change and not
  formatting noise (S8-4), and it is shown red on a planted byte in
  `conformance/controls/bucket_projection_controls.exs noop`.

  ## Exit status

  `0` rendered (or `--check` clean). `1` refused, or `--check` found a
  difference. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, BucketProjection}

  @switches [crosswalk: :string, bucket_zero: :string, out: :string, check: :boolean]
  @aliases [o: :out]

  @usage """
  mix conformance.buckets [--crosswalk FILE] [--bucket-zero FILE] [-o DIR] [--check]\
  """

  @default_crosswalk "docs/conformance/crosswalk-2026-07-28.json"
  @default_bucket_zero "docs/conformance/bucket-0-2026-07-28.json"
  @default_out "docs/conformance/buckets"

  @impl Mix.Task
  def run(argv) do
    {opts, _} =
      Argv.parse!("conformance.buckets", argv,
        strict: @switches,
        aliases: @aliases,
        usage: @usage
      )

    crosswalk_path = Keyword.get(opts, :crosswalk, @default_crosswalk)
    bucket_zero_path = Keyword.get(opts, :bucket_zero, @default_bucket_zero)
    out = Keyword.get(opts, :out, @default_out)

    files = build!(crosswalk_path, bucket_zero_path)

    if Keyword.get(opts, :check, false),
      do: check!(files, out),
      else: write!(files, out, crosswalk_path)
  end

  defp build!(crosswalk_path, bucket_zero_path) do
    crosswalk = read_json!(crosswalk_path)
    bucket_zero = read_json!(bucket_zero_path)

    sources = %{
      "crosswalk" => source(crosswalk_path),
      "bucket_zero" => source(bucket_zero_path)
    }

    case BucketProjection.project(crosswalk, bucket_zero, sources) do
      {:ok, files} -> Map.new(files, fn {name, doc} -> {name, encode(doc)} end)
      {:error, {guard, message}} -> Mix.raise("[#{guard}] " <> message)
    end
  end

  defp source(path) do
    bytes = File.read!(path)

    %{
      "file" => path,
      "sha256" => :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower),
      "bytes" => byte_size(bytes)
    }
  end

  defp encode(doc), do: Jason.encode!(doc, pretty: true) <> "\n"

  defp write!(files, out, crosswalk_path) do
    File.mkdir_p!(out)
    Enum.each(files, fn {name, bytes} -> File.write!(Path.join(out, name), bytes) end)
    report(files, out, crosswalk_path)
  end

  # THE NO-OP CONTROL. Byte-comparable regeneration, writing nothing: the
  # committed views are only evidence if regenerating them is a no-op, and a
  # check that has never been seen red is not a check (S8-4).
  defp check!(files, out) do
    on_disk = existing(out)
    expected = MapSet.new(Map.keys(files))
    present = MapSet.new(Map.keys(on_disk))

    differs =
      files
      |> Enum.filter(fn {name, bytes} -> Map.get(on_disk, name) != bytes end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    missing = expected |> MapSet.difference(present) |> MapSet.to_list() |> Enum.sort()
    extra = present |> MapSet.difference(expected) |> MapSet.to_list() |> Enum.sort()

    if differs == [] and missing == [] and extra == [] do
      Mix.shell().info(
        "conformance.buckets --check: #{map_size(files)} files in #{out} are byte-identical " <>
          "to a fresh projection."
      )
    else
      Mix.raise(diff_report(out, differs, missing, extra, files, on_disk))
    end
  end

  defp diff_report(out, differs, missing, extra, files, on_disk) do
    """
    conformance.buckets --check FAILED against #{out}.

      differ from a fresh projection (#{length(differs)}):
    #{Enum.map_join(differs, "\n", &"      #{&1}  committed #{size(on_disk[&1])}, projected #{size(files[&1])}")}
      expected and absent (#{length(missing)}):
    #{Enum.map_join(missing, "\n", &("      " <> &1))}
      present and not expected (#{length(extra)}):
    #{Enum.map_join(extra, "\n", &("      " <> &1))}

    Regenerate with `mix conformance.buckets -o #{out}` and commit the result, or find out
    why the projection moved. A file that differs means the crosswalk moved, the predicates
    moved, or the committed view was hand-edited — and the third is the one this check exists
    to catch.
    """
  end

  defp size(nil), do: "absent"
  defp size(bytes), do: "#{byte_size(bytes)} bytes"

  defp existing(out) do
    case File.ls(out) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Map.new(&{&1, File.read!(Path.join(out, &1))})

      {:error, _} ->
        %{}
    end
  end

  defp report(files, out, crosswalk_path) do
    roll_up = Jason.decode!(Map.fetch!(files, "roll-up-#{BucketProjection.revision()}.json"))

    Mix.shell().info("""

    BUCKET PROJECTIONS — #{BucketProjection.revision()}, #{map_size(files)} files in #{out}
    projected from #{crosswalk_path}

    #{Enum.map_join(roll_up["counts"], "\n", &count_line/1)}

    #{Enum.map_join(roll_up["equations"], "\n", &equation_line/1)}

      partition         #{Enum.map_join(~w(edges declared_members declared_checks), "  ", &"#{&1}: #{roll_up["partition"][&1]["equal"]}")}
                        within-universe pairs disjoint: #{roll_up["partition"]["pairwise_disjoint"]["overlapping"] == []} (#{roll_up["partition"]["pairwise_disjoint"]["within_universe_pairs"]} pairs, #{roll_up["partition"]["pairwise_disjoint"]["cross_universe_pairs"]} cross-universe pairs prove nothing)

      A green run here says the views faithfully PROJECT the crosswalk. It does NOT say
      the crosswalk is internally consistent — that is C1's reconcile! and C3's controls.
      E2 proves the partition; this renders it.
    """)
  end

  defp count_line(c) do
    label = String.pad_trailing(c["bucket"], 10)
    empty = if c["empty"], do: "  EMPTY (#{c["emptiness_code"]})", else: ""

    "      #{label}#{String.pad_leading(to_string(c["count"]), 4)}  " <>
      "#{String.pad_trailing(c["universe"], 20)}#{c["title"]}#{empty}"
  end

  defp equation_line(e) do
    terms = Enum.map_join(e["terms"], " + ", &"#{&1["term"]}(#{&1["count"]})")

    "      #{String.pad_trailing(e["universe"], 20)}#{e["total"]} = #{terms}  " <>
      "[#{if e["holds"], do: "holds", else: "DOES NOT HOLD"}]"
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
