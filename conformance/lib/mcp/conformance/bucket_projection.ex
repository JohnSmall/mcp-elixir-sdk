defmodule MCP.Conformance.BucketProjection do
  @moduledoc """
  C2 (MES-98) — the ten bucket views, as **projections** of C1a's one crosswalk.

  ## The one property this module exists to hold

  Every view is a **pure filter on fields C1a already stored**. Nothing here
  calls `MatchKey.bucket/1`, re-reads an axis, re-derives a shape or decides a
  verdict. A renderer that re-derived a bucket's membership by its own logic
  would be a second record of one fact, and two records of one fact can
  disagree — which is the drift the single matrix was built to remove
  (S5-20/S5-21).

  The consequence is stated rather than left implicit, because it is a real
  bound: **a green run here says the views faithfully project the crosswalk. It
  does not say the crosswalk is internally consistent.** A cell whose stored
  `bucket` disagrees with `f(verdicts, shape)` is rendered on its stored
  `bucket` and does not move. Detecting that disagreement would mean computing
  the bucket function a second time, here — the exact thing above. Matrix
  consistency is C1's `reconcile!` and C3's guards (PM ruling on MES-98 M3).

  ## Three universes, not one

  The ten buckets do **not** partition one set. They partition three:

  | universe | buckets |
  | --- | --- |
  | edges — the crosswalk's `cells` | 3, 4a, 4b, 5a, 5b, 6 (+ the escalated view) |
  | ET-CC members of the declared population | 1 |
  | OC checks of the declared population | 2a, 2b |
  | the 175 OC checks of A1's manifest | 0 |

  So "the sum of the ten equals the crosswalk row count" is a category error —
  it adds edges to members to checks and totals 26, which counts nothing. The
  roll-up therefore carries **three universe-labelled equations**. This is the
  same reason `Crosswalk.project/2` refuses a bucket-1 or bucket-2 projection
  without a declared universe: a complement is not a fact without one.

  ## Nine projections and one citation

  Bucket 0's two checks were removed from the denominator **before** the join,
  so they appear in no cell and cannot be filtered out of one. Its view is
  marked `derivation: "citation"` and cites A5's artefact; the other nine are
  `derivation: "projection"`. Claiming ten projections would claim a property
  that does not hold.

  ## The a/b splits are a second filter, not a second decision

  The ratified bucket function returns eight names; the ten pages need `2a`/`2b`
  and `5a`/`5b`. Per MES-96 and the subject master page the refinement is **by
  leg**, and leg is a field already on the row — `oc_key[0]` for an edge, the
  token's leg segment for a check. The split must also be **total** over its
  parent or a row would fall out of both halves and break the partition
  silently, so `:leg` is a fail-closed guard and `:edge_partition` /
  `:check_partition` are the backstops behind it.

  ## An escalation is not a bucket

  Four cells carry `bucket: null` and an `escalation`. The crosswalk's own rule
  is that *"an escalation is NOT a bucket and is never counted as one"*, so they
  are enumerated in a named **eleventh** view outside the ten, each with its
  reason. Rendering them into a bucket would launder a PM escalation into an
  adjudication.
  """

  alias MCP.Conformance.{Crosswalk, MatchKey}

  @revision "2026-07-28"

  # The guard set, as a list of ids so that `guard-mutation` can remove exactly
  # one of them by a single-line edit and re-run the input it catches. A guard
  # whose removal changes nothing is decoration.
  @guards [:vacuum, :leg, :edge_partition, :member_partition, :check_partition]

  @banner """
  POPULATION: the declared 21-member / 14-check slice adjudicated by
  MES-97 (C1a). This is NOT the whole conformance picture. The full
  comparison is 281 ET-CC members and 173 in-denominator OC checks; the
  remaining 260 members and 159 checks are not_yet_adjudicated -- a third
  state, distinct from bucket 1 -- and are owned by C1b (MES-104, client
  leg) and C1c (MES-105, server leg + the 29 none_determinable).

  A count of zero in this view means zero WITHIN THAT SLICE. It does not
  mean zero in the suite. When C1b and C1c land, this projection re-runs
  and fills.\
  """

  @buckets [
    %{
      id: "0",
      title: "out of denominator — unmatchable by construction",
      derivation: "citation",
      universe: "oc_checks_175"
    },
    %{
      id: "1",
      title: "ET-CC member with no OC counterpart",
      derivation: "projection",
      universe: "declared_members"
    },
    %{
      id: "2a",
      title: "OC check with no ET-CC match — server",
      derivation: "projection",
      universe: "declared_checks"
    },
    %{
      id: "2b",
      title: "OC check with no ET-CC match — client",
      derivation: "projection",
      universe: "declared_checks"
    },
    %{
      id: "3",
      title: "OC green, ET-CC red",
      derivation: "projection",
      universe: "edges"
    },
    %{
      id: "4a",
      title: "OC red, ET-CC green — contradiction",
      derivation: "projection",
      universe: "edges"
    },
    %{
      id: "4b",
      title: "OC red, ET-CC green — incompleteness",
      derivation: "projection",
      universe: "edges"
    },
    %{
      id: "5a",
      title: "green in both — server",
      derivation: "projection",
      universe: "edges"
    },
    %{
      id: "5b",
      title: "green in both — client",
      derivation: "projection",
      universe: "edges"
    },
    %{
      id: "6",
      title: "red in both",
      derivation: "projection",
      universe: "edges"
    }
  ]

  @predicates %{
    "0" =>
      "CITATION, not a projection. The in-scope OC checks A5 (MES-70) classified " <>
        "`matchable: false` in `docs/conformance/bucket-0-2026-07-28.json`. Universe: the 175 " <>
        "checks of A1's manifest. They were removed from the denominator BEFORE the join — the " <>
        "crosswalk is built against 173 — so they appear in no cell and cannot be filtered out " <>
        "of one.",
    "1" =>
      "Declared-population ET-CC members carrying NO edge in `cells`: the complement of " <>
        "`members_with_edges` over the declared population, taken through " <>
        "`Crosswalk.project(:bucket_1, ...)`. Universe: the 21 declared members, never all 281.",
    "2a" =>
      "Declared-population OC checks carrying NO edge in `cells`, whose token's leg segment is " <>
        "`server`. Complement taken through `Crosswalk.project(:bucket_2, ...)`, then filtered " <>
        "on the leg the token already carries. Universe: the server-leg checks of the declared " <>
        "14, never all 173.",
    "2b" =>
      "Declared-population OC checks carrying NO edge in `cells`, whose token's leg segment is " <>
        "`client`. Complement taken through `Crosswalk.project(:bucket_2, ...)`, then filtered " <>
        "on the leg the token already carries. Universe: the client-leg checks of the declared " <>
        "14, never all 173.",
    "3" => "`cells` where the stored `bucket` == \"3\". Universe: the crosswalk's edges.",
    "4a" => "`cells` where the stored `bucket` == \"4a\". Universe: the crosswalk's edges.",
    "4b" => "`cells` where the stored `bucket` == \"4b\". Universe: the crosswalk's edges.",
    "5a" =>
      "`cells` where the stored `bucket` == \"5\" AND the stored `oc_key[0]` == \"server\". " <>
        "Universe: the crosswalk's edges.",
    "5b" =>
      "`cells` where the stored `bucket` == \"5\" AND the stored `oc_key[0]` == \"client\". " <>
        "Universe: the crosswalk's edges.",
    "6" => "`cells` where the stored `bucket` == \"6\". Universe: the crosswalk's edges."
  }

  # Why a bucket would be EMPTY, and what would fill it. Emitted only when the
  # view really is empty, so it is data-driven and not a hard-coded "this one is
  # always zero": M2 (`bucket_projection_controls.exs movement`) moves one row
  # into bucket 3 and the reason disappears.
  #
  # Three codes, because five buckets are empty on this slice for three
  # DIFFERENT reasons and an empty file that does not distinguish them is the
  # "never asked" failure in a new costume.
  @emptiness %{
    "0" => {"by_adjudication", "an in-scope OC check A5 classifies as unmatchable."},
    "1" => {"by_adjudication", "a declared ET-CC member with no OC counterpart."},
    "2a" =>
      {"by_adjudication",
       "a declared server-leg OC check that no ET-CC member covers. Over the declared 14, " <>
         "explicitly NOT over the 173: the 159 in-denominator checks outside the population " <>
         "are not bucket 2, they are not_yet_adjudicated (C1b/C1c)."},
    "2b" =>
      {"by_adjudication",
       "a declared client-leg OC check that no ET-CC member covers. Over the declared 14, " <>
         "explicitly NOT over the 173: the 159 in-denominator checks outside the population " <>
         "are not bucket 2, they are not_yet_adjudicated (C1b/C1c)."},
    "3" =>
      {"by_construction",
       "an ET-CC member that FAILS against a check the harness passes. Not reachable while " <>
         "gate 5 is green — every declared member's et verdict is green."},
    "4a" => {"by_slice", "a server-leg contradiction inside the declared slice."},
    "4b" => {"by_slice", "a server-leg incompleteness inside the declared slice."},
    "5a" =>
      {"by_slice",
       "a server-leg agreement inside the declared slice. THIS IS NOT A STRUCTURAL FACT. All " <>
         "15 green-in-both edges adjudicated so far are client-leg; the declared slice simply " <>
         "contains no server-leg agreement yet. An unqualified empty \"green in both — " <>
         "server\" view would read as \"this SDK agrees with the official suite nowhere on the " <>
         "server leg\", which is FALSE. C1c (MES-105) is the ticket that fills it."},
    "5b" => {"by_slice", "a client-leg agreement inside the declared slice."},
    "6" =>
      {"by_construction",
       "an ET-CC member that fails against a check the harness also fails. Not reachable " <>
         "while gate 5 is green — every declared member's et verdict is green."}
  }

  @doc "The artefact revision these views are cut at."
  @spec revision() :: String.t()
  def revision, do: @revision

  @doc """
  The guard ids, in the order they run.

  Exposed so a control can enumerate them rather than restate them, and so
  `guard-mutation` can remove exactly one and show the removal changes the
  outcome.
  """
  @spec guards() :: [atom()]
  def guards, do: @guards

  @doc "The ten bucket ids, in page order."
  @spec bucket_ids() :: [String.t()]
  def bucket_ids, do: Enum.map(@buckets, & &1.id)

  @doc "The static spec of one bucket — title, derivation, universe, predicate."
  @spec spec(String.t()) :: map()
  def spec(id) do
    b = Enum.find(@buckets, &(&1.id == id)) || raise ArgumentError, "no such bucket: #{id}"
    Map.put(b, :predicate, Map.fetch!(@predicates, id))
  end

  @doc "The population banner every view and the roll-up carry verbatim."
  @spec banner() :: String.t()
  def banner, do: @banner

  @doc """
  Project one crosswalk into the ten views, the escalated view and the roll-up.

  `crosswalk` is the decoded `crosswalk-2026-07-28.json`; `bucket_zero` the
  decoded A5 artefact. `sources` carries the two paths and their digests, which
  are written into every view so a reader can tell which matrix a view is of.

  Returns `{:error, {guard_id, message}}` when a guard fires — the guard ids are
  `guards/0` and each message names its own guard.
  """
  @spec project(map(), map(), map()) ::
          {:ok, %{String.t() => map()}} | {:error, {atom(), String.t()}}
  def project(crosswalk, bucket_zero, sources) do
    ctx = context(crosswalk, bucket_zero, sources)

    case Enum.find_value(@guards, &guard(&1, ctx)) do
      nil -> {:ok, files(ctx)}
      error -> {:error, error}
    end
  end

  # --- the context: every view's rows, and the three partitions -------------

  defp context(crosswalk, bucket_zero, sources) do
    cells = crosswalk["cells"] || []
    population = crosswalk["population"] || %{}
    members = population["members"] || []
    checks = population["checks"] || []
    unmatched = crosswalk["declared_unmatched"] || []

    members_with_edges = cells |> Enum.map(&member_key/1) |> Enum.uniq() |> Enum.sort()
    checks_with_edges = cells |> Enum.map(& &1["tag"]) |> Enum.uniq() |> Enum.sort()

    base = %{
      cells: cells,
      crosswalk: crosswalk,
      bucket_zero: bucket_zero,
      sources: sources,
      members: members,
      checks: checks,
      unmatched: unmatched,
      members_with_edges: members_with_edges,
      checks_with_edges: checks_with_edges
    }

    rows = Map.new(bucket_ids(), &{&1, rows_for(&1, base)})

    base
    |> Map.put(:rows, rows)
    |> Map.put(:escalated, Enum.filter(cells, &(&1["bucket"] == nil)))
    |> partitions()
  end

  # EVERY ONE OF THESE IS A FILTER ON A STORED FIELD. No verdict, no shape and
  # no bucket is computed here; `MatchKey.bucket/1` is not called.
  defp rows_for("0", ctx),
    do: ctx.bucket_zero["checks"] |> Enum.reject(& &1["matchable"]) |> Enum.sort_by(& &1["key"])

  defp rows_for("1", ctx) do
    keys = complement(:bucket_1, ctx.members, ctx.members_with_edges)
    by_key = Map.new(ctx.unmatched, &{&1["member"]["register_key"], &1})

    Enum.map(keys, &Map.get(by_key, &1, %{"member" => %{"register_key" => &1}, "record" => nil}))
  end

  defp rows_for("2a", ctx), do: unmatched_checks(ctx, "server")
  defp rows_for("2b", ctx), do: unmatched_checks(ctx, "client")

  defp rows_for("5a", ctx),
    do: Enum.filter(ctx.cells, &(&1["bucket"] == "5" and leg(&1) == "server"))

  defp rows_for("5b", ctx),
    do: Enum.filter(ctx.cells, &(&1["bucket"] == "5" and leg(&1) == "client"))

  defp rows_for(id, ctx), do: Enum.filter(ctx.cells, &(&1["bucket"] == id))

  defp unmatched_checks(ctx, want) do
    :bucket_2
    |> complement(ctx.checks, ctx.checks_with_edges)
    |> Enum.map(&%{"tag" => &1, "leg" => tag_leg(&1)})
    |> Enum.filter(&(&1["leg"] == want))
  end

  # Both complements go THROUGH `Crosswalk.project/2` rather than being
  # recomputed: that function refuses a complement with no universe, and a
  # refusal on a path this module does not take protects nothing.
  defp complement(which, universe, with_edges) do
    case Crosswalk.project(which, %{population: universe, with_edges: with_edges}) do
      {:ok, rows} ->
        Enum.sort(rows)

      {:error, reason} ->
        raise ArgumentError, "#{which} could not be projected: #{inspect(reason)}"
    end
  end

  defp member_key(cell), do: cell["member"]["register_key"]
  defp leg(cell), do: cell |> Map.get("oc_key", []) |> List.first()

  # The leg a TOKEN carries. `MatchKey.decode/1` rather than a string split: the
  # token's grammar is A3's and is owned there.
  defp tag_leg(tag) do
    case MatchKey.decode(tag) do
      {:ok, %{kind: :oc, leg: leg}} -> leg
      _ -> nil
    end
  end

  # --- the three partitions, by SET COMPARISON in both directions -----------

  defp partitions(ctx) do
    edge_views = ~w(3 4a 4b 5a 5b 6)

    projected =
      edge_views
      |> Enum.flat_map(&Map.fetch!(ctx.rows, &1))
      |> Kernel.++(ctx.escalated)
      |> Enum.map(&edge_key/1)

    bucket_1 = Enum.map(Map.fetch!(ctx.rows, "1"), &get_in(&1, ["member", "register_key"]))
    unmatched_keys = Enum.map(ctx.unmatched, &get_in(&1, ["member", "register_key"]))
    bucket_2 = Enum.map(Map.fetch!(ctx.rows, "2a") ++ Map.fetch!(ctx.rows, "2b"), & &1["tag"])

    Map.put(ctx, :partition, %{
      edges: Crosswalk.set_compare(Enum.map(ctx.cells, &edge_key/1), projected),
      members: Crosswalk.set_compare(ctx.members, bucket_1 ++ ctx.members_with_edges),
      member_records: Crosswalk.set_compare(unmatched_keys, bucket_1),
      checks: Crosswalk.set_compare(ctx.checks, bucket_2 ++ ctx.checks_with_edges),
      pairwise: pairwise(ctx)
    })
  end

  defp edge_key(cell), do: [member_key(cell), cell["claim"], cell["tag"]]

  # Every pair of the eleven views. Pairs drawn from DIFFERENT universes are
  # disjoint by construction — their keys are different kinds of thing — so they
  # are reported with `within_universe: false` and are not evidence of anything.
  # Only the within-universe pairs carry weight, and they are flagged as such
  # rather than being buried in a count of 55 green rows.
  defp pairwise(ctx) do
    views = view_keys(ctx)
    ids = Enum.map(views, &elem(&1, 0))

    for {a, i} <- Enum.with_index(ids), b <- Enum.drop(ids, i + 1) do
      {_, ua, ka} = Enum.find(views, &(elem(&1, 0) == a))
      {_, ub, kb} = Enum.find(views, &(elem(&1, 0) == b))
      shared = MapSet.intersection(MapSet.new(ka), MapSet.new(kb))

      %{
        "a" => a,
        "b" => b,
        "within_universe" => ua == ub,
        "shared" => MapSet.size(shared),
        "shared_keys" => shared |> MapSet.to_list() |> Enum.sort()
      }
    end
  end

  defp view_keys(ctx) do
    ten =
      Enum.map(bucket_ids(), fn id ->
        {id, spec(id).universe, Enum.map(Map.fetch!(ctx.rows, id), &row_key(id, &1))}
      end)

    ten ++ [{"escalated", "edges", Enum.map(ctx.escalated, &edge_key/1)}]
  end

  defp row_key("0", row), do: row["key"]
  defp row_key("1", row), do: get_in(row, ["member", "register_key"])
  defp row_key(id, row) when id in ["2a", "2b"], do: row["tag"]
  defp row_key(_id, row), do: edge_key(row)

  # --- the guards -----------------------------------------------------------

  defp guard(:vacuum, %{cells: []}) do
    {:vacuum,
     "VACUUM — the crosswalk carries no cells. Ten clean empty views over an empty matrix " <>
       "satisfy every partition check here perfectly: every set comparison is equal, every " <>
       "pairwise intersection is empty, and all three equations reconcile at zero. That is " <>
       "the S9-15 vacuum, and emptiness is what this guard exists to fire on."}
  end

  defp guard(:vacuum, _ctx), do: nil

  defp guard(:leg, ctx) do
    bad_cells = Enum.reject(ctx.cells, &(leg(&1) in MatchKey.legs()))
    bad_checks = Enum.reject(ctx.checks, &(tag_leg(&1) in MatchKey.legs()))

    if bad_cells == [] and bad_checks == [] do
      nil
    else
      {:leg,
       "LEG GUARD — #{length(bad_cells)} cells and #{length(bad_checks)} declared checks carry " <>
         "a leg outside #{inspect(MatchKey.legs())}. The 2a/2b and 5a/5b splits are BY LEG, so " <>
         "a row with an unknown leg falls out of both halves of its split and the partition " <>
         "breaks silently — the row is in no view and nothing says so. Fail-closed:\n" <>
         Enum.map_join(bad_cells, "\n", &"  cell  #{inspect(leg(&1))}  #{&1["tag"]}") <>
         Enum.map_join(bad_checks, "\n", &"  check #{inspect(tag_leg(&1))}  #{&1}")}
    end
  end

  defp guard(:edge_partition, ctx) do
    c = ctx.partition.edges
    overlaps = Enum.filter(ctx.partition.pairwise, &(&1["within_universe"] and &1["shared"] > 0))

    if c.equal and overlaps == [] do
      nil
    else
      {:edge_partition,
       "EDGE PARTITION — the six edge views plus the escalated view do not partition the " <>
         "crosswalk's cells. Compared by SET in BOTH directions, never by count:\n" <>
         "  cells that reach no view (#{length(c.missing)}):\n" <>
         Enum.map_join(c.missing, "\n", &"    #{inspect(&1)}") <>
         "\n  rows in a view that are not cells (#{length(c.extra)}):\n" <>
         Enum.map_join(c.extra, "\n", &"    #{inspect(&1)}") <>
         "\n  within-universe view pairs sharing a row (#{length(overlaps)}):\n" <>
         Enum.map_join(overlaps, "\n", &"    #{&1["a"]} ∩ #{&1["b"]} = #{&1["shared"]}")}
    end
  end

  defp guard(:member_partition, ctx) do
    c = ctx.partition.members
    r = ctx.partition.member_records

    if c.equal and r.equal do
      nil
    else
      {:member_partition,
       "MEMBER PARTITION — bucket 1 and the members carrying an edge do not partition the " <>
         "declared members, or bucket 1 is not the set the crosswalk declares unmatched:\n" <>
         "  declared members reaching neither (#{length(c.missing)}):\n" <>
         Enum.map_join(c.missing, "\n", &"    #{&1}") <>
         "\n  members named by a cell but outside the declared population (#{length(c.extra)}):\n" <>
         Enum.map_join(c.extra, "\n", &"    #{&1}") <>
         "\n  declared unmatched, not projected into bucket 1 (#{length(r.missing)}):\n" <>
         Enum.map_join(r.missing, "\n", &"    #{&1}") <>
         "\n  projected into bucket 1 with no declared_unmatched record (#{length(r.extra)}):\n" <>
         Enum.map_join(r.extra, "\n", &"    #{&1}")}
    end
  end

  defp guard(:check_partition, ctx) do
    c = ctx.partition.checks

    if c.equal do
      nil
    else
      {:check_partition,
       "CHECK PARTITION — bucket 2a, bucket 2b and the checks carrying an edge do not " <>
         "partition the declared checks:\n" <>
         "  declared checks reaching no view (#{length(c.missing)}):\n" <>
         Enum.map_join(c.missing, "\n", &"    #{&1}") <>
         "\n  checks named by a cell but outside the declared population (#{length(c.extra)}):\n" <>
         Enum.map_join(c.extra, "\n", &"    #{&1}")}
    end
  end

  # --- the artefacts --------------------------------------------------------

  defp files(ctx) do
    views =
      Map.new(bucket_ids(), fn id -> {"bucket-#{id}-#{@revision}.json", view(id, ctx)} end)

    views
    |> Map.put("escalated-#{@revision}.json", escalated_view(ctx))
    |> Map.put("roll-up-#{@revision}.json", roll_up(ctx))
  end

  defp view(id, ctx) do
    s = spec(id)
    rows = Map.fetch!(ctx.rows, id)

    %{
      "schema" => "bucket-view/1",
      "revision" => @revision,
      "generated_by" => "mix conformance.buckets",
      "owner" => "MES-98 (C2)",
      "bucket" => id,
      "title" => s.title,
      "derivation" => s.derivation,
      "predicate" => s.predicate,
      "universe" => universe(s.universe, ctx),
      "population_banner" => @banner,
      "projected_from" => ctx.sources,
      "what_this_is" => what_this_is(s.derivation),
      "count" => length(rows),
      "emptiness_reason" => emptiness(id, rows, ctx),
      "rows" => rows
    }
  end

  defp what_this_is("citation") do
    "A CITATION, not a projection. These checks were removed from the denominator before the " <>
      "join, so they are in no crosswalk cell and cannot be filtered out of one. The rows are " <>
      "A5's records verbatim."
  end

  defp what_this_is("projection") do
    "A PURE PROJECTION of the crosswalk named in `projected_from`, on the `predicate` above " <>
      "and on fields the crosswalk already stores. Nothing here re-computes a verdict, an " <>
      "edge shape or a bucket assignment. The rows are the crosswalk's own records verbatim, " <>
      "so a reader can check this view against the matrix byte for byte."
  end

  defp universe("edges", ctx),
    do: %{"name" => "edges", "count" => length(ctx.cells), "of" => "the crosswalk's `cells`"}

  defp universe("declared_members", ctx),
    do: %{
      "name" => "declared_members",
      "count" => length(ctx.members),
      "of" => "the declared ET-CC members, never all 281"
    }

  defp universe("declared_checks", ctx),
    do: %{
      "name" => "declared_checks",
      "count" => length(ctx.checks),
      "of" => "the declared in-population OC checks, never all 173"
    }

  defp universe("oc_checks_175", ctx),
    do: %{
      "name" => "oc_checks_175",
      "count" => length(ctx.bucket_zero["checks"] || []),
      "of" => "A1's frozen manifest, before the 2 bucket-0 removals leave 173"
    }

  # Emitted ONLY when the view is really empty, and carrying a MEASURE rather
  # than an assertion: "checked, and zero" has to say what was checked.
  defp emptiness(_id, [_ | _], _ctx), do: nil

  defp emptiness(id, [], ctx) do
    {code, fill} = Map.fetch!(@emptiness, id)

    %{
      "code" => code,
      "result" => "CHECKED, AND ZERO — within the declared slice. Not 'never asked'.",
      "what_would_fill_it" => fill,
      "measured" => measure(id, ctx),
      "ticket_that_would_fill_it" => filler(code)
    }
  end

  defp measure(id, ctx) when id in ["3", "6"] do
    red = Enum.count(ctx.cells, &(get_in(&1, ["verdicts", "et"]) == "red"))

    "cells whose stored et verdict is `red`: #{red} of #{length(ctx.cells)}. Buckets 3 and 6 " <>
      "both require one."
  end

  defp measure(id, ctx) when id in ["2a", "2b"] do
    "declared checks carrying no edge: #{length(ctx.checks) - length(ctx.checks_with_edges)} " <>
      "of #{length(ctx.checks)}."
  end

  defp measure("5a", ctx) do
    five = Enum.count(ctx.cells, &(&1["bucket"] == "5"))
    server = Enum.count(ctx.cells, &(&1["bucket"] == "5" and leg(&1) == "server"))

    "bucket-5 cells with `oc_key[0] == \"server\"`: #{server} of #{five}. The other " <>
      "#{five - server} are client-leg."
  end

  defp measure(id, ctx) do
    "cells matching the predicate: 0 of #{length(ctx.cells)} (bucket #{id})."
  end

  defp filler("by_slice"),
    do: "C1b (MES-104, client leg) and C1c (MES-105, server leg) widen the population."

  defp filler("by_adjudication"),
    do: "A future adjudication inside the declared slice, or C1b/C1c widening it."

  defp filler("by_construction"),
    do: "Remediation — an ET-CC member that fails. Not reachable while gate 5 is green."

  defp escalated_view(ctx) do
    %{
      "schema" => "escalated-view/1",
      "revision" => @revision,
      "generated_by" => "mix conformance.buckets",
      "owner" => "MES-98 (C2)",
      "bucket" => nil,
      "title" => "escalated — routed to the PM, in NO bucket",
      "derivation" => "projection",
      "predicate" => "`cells` where the stored `bucket` is null and an `escalation` is recorded.",
      "universe" => universe("edges", ctx),
      "population_banner" => @banner,
      "projected_from" => ctx.sources,
      "what_this_is" =>
        "THE ELEVENTH VIEW, OUTSIDE THE TEN. The crosswalk's own rule is that \"an escalation " <>
          "is NOT a bucket and is never counted as one\" (match-relation.md §7). These rows are " <>
          "therefore visibly excluded by rule, each with its reason, rather than invisibly " <>
          "dropped — and rendering one into a bucket would launder a PM escalation into an " <>
          "adjudication, which is the one thing this ticket must not do. AC2's partition holds " <>
          "over the #{length(ctx.cells) - length(ctx.escalated)} BUCKETED edges; these " <>
          "#{length(ctx.escalated)} are enumerated here and are counted in the edge equation " <>
          "as their own term.",
      "count" => length(ctx.escalated),
      "emptiness_reason" => nil,
      "rows" => ctx.escalated
    }
  end

  defp roll_up(ctx) do
    %{
      "schema" => "bucket-roll-up/1",
      "revision" => @revision,
      "generated_by" => "mix conformance.buckets",
      "owner" => "MES-98 (C2)",
      "what_this_is" =>
        "The count roll-up, itself a projection: every figure below is derived from the same " <>
          "filters that wrote the views, in the same run. It makes the partition arithmetic " <>
          "VISIBLE. It does not prove the partition — E2 owns that proof as the epic's exit.",
      "population_banner" => @banner,
      "projected_from" => ctx.sources,
      "counts" => counts(ctx),
      "equations" => equations(ctx),
      "partition" => partition_report(ctx),
      "what_a_green_run_here_establishes" => boundary(),
      "residuals" => residuals(ctx)
    }
  end

  defp counts(ctx) do
    ten =
      Enum.map(bucket_ids(), fn id ->
        s = spec(id)
        rows = Map.fetch!(ctx.rows, id)

        %{
          "bucket" => id,
          "title" => s.title,
          "derivation" => s.derivation,
          "universe" => s.universe,
          "count" => length(rows),
          "empty" => rows == [],
          "emptiness_code" => if(rows == [], do: elem(Map.fetch!(@emptiness, id), 0))
        }
      end)

    ten ++
      [
        %{
          "bucket" => "escalated",
          "title" => "escalated — in NO bucket, outside the ten",
          "derivation" => "projection",
          "universe" => "edges",
          "count" => length(ctx.escalated),
          "empty" => ctx.escalated == [],
          "emptiness_code" => nil
        }
      ]
  end

  # THREE equations, each labelled with its universe. Not one: the ten buckets
  # partition three different sets, and adding an edge count to a member count
  # to a check count produces a figure that counts nothing.
  defp equations(ctx) do
    edge_terms = Enum.map(~w(3 4a 4b 5a 5b 6), &{&1, length(Map.fetch!(ctx.rows, &1))})
    edge_terms = edge_terms ++ [{"escalated", length(ctx.escalated)}]

    member_terms = [
      {"1", length(Map.fetch!(ctx.rows, "1"))},
      {"members_with_edges", length(ctx.members_with_edges)}
    ]

    check_terms = [
      {"2a", length(Map.fetch!(ctx.rows, "2a"))},
      {"2b", length(Map.fetch!(ctx.rows, "2b"))},
      {"checks_with_edges", length(ctx.checks_with_edges)}
    ]

    [
      equation("edges", length(ctx.cells), edge_terms, "the crosswalk's `cells`"),
      equation(
        "declared_members",
        length(ctx.members),
        member_terms,
        "the declared ET-CC members, never all 281"
      ),
      equation(
        "declared_checks",
        length(ctx.checks),
        check_terms,
        "the declared in-population OC checks, never all 173"
      ),
      %{
        "universe" => "oc_checks_175",
        "of" => "A1's frozen manifest — CITED from A5, not derived here",
        "total" => length(ctx.bucket_zero["checks"] || []),
        "terms" => [
          %{"term" => "in_denominator", "count" => in_denominator(ctx)},
          %{"term" => "0", "count" => length(Map.fetch!(ctx.rows, "0"))}
        ],
        "sum" => in_denominator(ctx) + length(Map.fetch!(ctx.rows, "0")),
        "holds" =>
          in_denominator(ctx) + length(Map.fetch!(ctx.rows, "0")) ==
            length(ctx.bucket_zero["checks"] || []),
        "measure" =>
          "ARITHMETIC ONLY, and cited. Bucket 0's members are in no cell, so there is no set " <>
            "comparison to make against the crosswalk. A5 owns the classification."
      }
    ]
  end

  defp in_denominator(ctx), do: Enum.count(ctx.bucket_zero["checks"] || [], & &1["matchable"])

  defp equation(universe, total, terms, of) do
    sum = terms |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{
      "universe" => universe,
      "of" => of,
      "total" => total,
      "terms" => Enum.map(terms, fn {t, n} -> %{"term" => t, "count" => n} end),
      "sum" => sum,
      "holds" => sum == total,
      "measure" =>
        "The arithmetic is the VISIBLE half. The evidence is the set comparison in " <>
          "`partition`, both directions with the negatives enumerated — two counts agreeing " <>
          "is not two sets agreeing."
    }
  end

  defp partition_report(ctx) do
    p = ctx.partition
    within = Enum.filter(p.pairwise, & &1["within_universe"])

    %{
      "measure" =>
        "SET COMPARISON in both directions, negatives ENUMERATED and not counted (ruling 4). " <>
          "Each of the three universes is compared separately, because the ten buckets " <>
          "partition three different sets.",
      "edges" =>
        direction_report(
          p.edges,
          "every cell reaches exactly one of the six edge views or the escalated view"
        ),
      "declared_members" =>
        direction_report(p.members, "every declared member is in bucket 1 or carries an edge"),
      "bucket_1_is_the_declared_unmatched_set" =>
        direction_report(
          p.member_records,
          "bucket 1, projected as a complement, equals the set the crosswalk declares unmatched"
        ),
      "declared_checks" =>
        direction_report(p.checks, "every declared check is in 2a, in 2b, or carries an edge"),
      "pairwise_disjoint" => %{
        "pairs_compared" => length(p.pairwise),
        "within_universe_pairs" => length(within),
        "cross_universe_pairs" => length(p.pairwise) - length(within),
        "overlapping" => Enum.filter(p.pairwise, &(&1["shared"] > 0)),
        "what_the_cross_universe_pairs_establish" =>
          "NOTHING, and they are reported as such. A bucket-1 key is a register key and a " <>
            "bucket-3 key is an (member, claim, tag) triple: they cannot collide, so their " <>
            "empty intersection is a fact about the key types and not about this data. Only " <>
            "the #{length(within)} within-universe pairs carry weight.",
        "pairs" => p.pairwise
      },
      "who_proves_it" =>
        "E2 (the epic's exit) PROVES the partition. This ticket establishes it MECHANICALLY " <>
          "and reports the comparison; the distinction is deliberate and E2's result is not " <>
          "claimed here."
    }
  end

  defp direction_report(c, claim) do
    %{
      "claim" => claim,
      "equal" => c.equal,
      "missing" => c.missing,
      "extra" => c.extra
    }
  end

  defp boundary do
    "That the views faithfully PROJECT the crosswalk. NOT that the crosswalk is internally " <>
      "consistent. A cell whose stored `bucket` disagrees with `f(verdicts, shape)` is " <>
      "rendered on its stored `bucket` and does not move — detecting that would mean " <>
      "computing the bucket function a SECOND time here, which is the two-records-that-can-" <>
      "disagree drift the single matrix exists to remove. Matrix consistency is C1's " <>
      "`reconcile!` and C3's falsification controls (PM ruling on MES-98, M3), and " <>
      "`bucket_projection_controls.exs movement` M3 shows the row not moving."
  end

  defp residuals(ctx) do
    [
      %{
        "id" => "C2-R1",
        "text" => String.replace(@banner, "\n", " ")
      },
      %{
        "id" => "C2-R2",
        "text" =>
          "THE MASTER PAGE'S MEMBER-LEVEL PARTITION WORDING IS ALREADY FALSIFIED ON THIS " <>
            "SLICE, and it is E2's to restate, not C2's. Page 276594833 states E2's target as " <>
            "\"every ET-CC member appears in exactly one of buckets {1, 3, 4a, 4b, 5a, 5b, " <>
            "6}\". #{multi_bucket_report(ctx)} The partition is exact PER EDGE and is not a " <>
            "function per member. Recorded here and as S9-21; owner E2."
      },
      %{
        "id" => "C2-R3",
        "text" =>
          "BUCKET 0 IS A CITATION. Its two rows are A5's records verbatim and were removed " <>
            "from the denominator before the join, so nine of the ten views are projections " <>
            "and the tenth says on its face why it is not."
      },
      %{
        "id" => "C2-R4",
        "text" => boundary()
      }
    ]
  end

  # Derived, not stated: the witness is named by running the count, so this
  # residual cannot go stale against the data it describes.
  defp multi_bucket_report(ctx) do
    spread =
      ctx.cells
      |> Enum.reject(&(&1["bucket"] == nil))
      |> Enum.group_by(&member_key/1, & &1["bucket"])
      |> Enum.filter(fn {_k, bs} -> length(Enum.uniq(bs)) > 1 end)
      |> Enum.sort()

    case spread do
      [] ->
        "On this slice no member's edges span two buckets, so the wording is not falsified here."

      rows ->
        "On this slice #{length(rows)} member(s) carry edges in more than one bucket: " <>
          Enum.map_join(rows, "; ", fn {k, bs} ->
            "#{k} -> #{inspect(Enum.sort(bs))}"
          end) <> "."
    end
  end
end
