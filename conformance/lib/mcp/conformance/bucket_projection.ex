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
  @guards [
    :vacuum,
    :leg,
    :edge_partition,
    :member_partition,
    :check_partition,
    :population_statement
  ]

  # --- the population figures, and why no statement here states one --------
  #
  # CR-1 on MES-104. The banner and three predicates below used to carry
  # C1a's 21-member / 14-check population as HARD-CODED text. C1b-i moved the
  # population to 48/29 and the strings did not move with it, so twelve
  # committed views declared a population their own computed `universe` counts
  # contradicted, and the banner named as PENDING the very ticket that was
  # rendering it. Nothing went red: the unit compared the view against the
  # recorded constant and `--check` re-projected that same constant, so both
  # sides were the constant (the guard-19 shape).
  #
  # The fix is not better strings. EVERY population figure that any emitted
  # statement carries is interpolated from the crosswalk under projection,
  # through `figures/1`, and `:population_statement` refuses a statement that
  # carries a population figure it did not interpolate. C1b-ii, C1b-iii and
  # C1c each move these numbers again.
  @figure_keys ~w(declared_members declared_checks addressed_not_declared
                  outside_members outside_checks total_members
                  in_denominator_checks manifest_checks unmatchable_checks)a

  @banner_template """
  POPULATION: this projection covers {{declared_members}} declared ET-CC
  members and {{declared_checks}} declared in-population OC checks. That is
  the slice adjudicated so far, and it is NOT the whole conformance picture:
  the full comparison is {{total_members}} ET-CC members and
  {{in_denominator_checks}} in-denominator OC checks, of which
  {{outside_members}} members and {{outside_checks}} checks are
  not_yet_adjudicated -- a third state, distinct from bucket 1 -- owned by the
  tickets the crosswalk's own `outside_the_population` block names. A further
  {{addressed_not_declared}} checks carry an edge without being declared by
  any file, so they are counted in neither.

  A count of zero in this view means zero WITHIN THAT SLICE. It does not mean
  zero in the suite. As the declared population grows this projection re-runs
  and fills.

  EVERY FIGURE ABOVE IS INTERPOLATED from the crosswalk being projected; none
  is written here. The [population_statement] guard refuses a population
  figure that is not.\
  """

  @buckets [
    %{
      id: "0",
      title: "out of denominator — unmatchable by construction",
      derivation: "citation",
      universe: "oc_checks_manifest"
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

  @predicate_templates %{
    "0" =>
      "CITATION, not a projection. The in-scope OC checks A5 (MES-70) classified " <>
        "`matchable: false` in `docs/conformance/bucket-0-2026-07-28.json`. Universe: the " <>
        "{{manifest_checks}} checks of A1's manifest. They were removed from the denominator " <>
        "BEFORE the join — the crosswalk is built against {{in_denominator_checks}} checks — " <>
        "so they appear in no cell and cannot be filtered out of one.",
    "1" =>
      "Declared-population ET-CC members carrying NO edge in `cells`: the complement of " <>
        "`members_with_edges` over the declared population, taken through " <>
        "`Crosswalk.project(:bucket_1, ...)`. Universe: the {{declared_members}} declared " <>
        "members, never all {{total_members}} members.",
    "2a" =>
      "Declared-population OC checks carrying NO edge in `cells`, whose token's leg segment is " <>
        "`server`. Complement taken through `Crosswalk.project(:bucket_2, ...)`, then filtered " <>
        "on the leg the token already carries. Universe: the server-leg half of the " <>
        "{{declared_checks}} declared checks, never all {{in_denominator_checks}} " <>
        "in-denominator checks.",
    "2b" =>
      "Declared-population OC checks carrying NO edge in `cells`, whose token's leg segment is " <>
        "`client`. Complement taken through `Crosswalk.project(:bucket_2, ...)`, then filtered " <>
        "on the leg the token already carries. Universe: the client-leg half of the " <>
        "{{declared_checks}} declared checks, never all {{in_denominator_checks}} " <>
        "in-denominator checks.",
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
       "a declared server-leg OC check that no ET-CC member covers. Over the " <>
         "{{declared_checks}} DECLARED checks, explicitly NOT over the " <>
         "{{in_denominator_checks}} in-denominator checks: the ones outside every declared " <>
         "check population are not bucket 2, they are not_yet_adjudicated (C1b-ii, C1b-iii, " <>
         "C1c)."},
    "2b" =>
      {"by_adjudication",
       "a declared client-leg OC check that no ET-CC member covers. Over the " <>
         "{{declared_checks}} DECLARED checks, explicitly NOT over the " <>
         "{{in_denominator_checks}} in-denominator checks: the ones outside every declared " <>
         "check population are not bucket 2, they are not_yet_adjudicated (C1b-ii, C1b-iii, " <>
         "C1c)."},
    "3" =>
      {"by_construction",
       "an ET-CC member that FAILS against a check the harness passes. Not reachable while " <>
         "gate 5 is green — every declared member's et verdict is green."},
    "4a" => {"by_slice", "a server-leg contradiction inside the declared slice."},
    "4b" => {"by_slice", "a server-leg incompleteness inside the declared slice."},
    "5a" =>
      {"by_slice",
       "a server-leg agreement inside the declared slice. THIS IS NOT A STRUCTURAL FACT. Every " <>
         "green-in-both edge adjudicated so far is client-leg; the declared slice simply " <>
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

  # The `of` line each universe carries into every view and into the roll-up's
  # equations. Templates for the same reason the banner is one: two of these
  # state a TOTAL, and a total moves every time a sibling ticket declares more.
  @universe_of %{
    "edges" => "the crosswalk's `cells`",
    "declared_members" =>
      "the {{declared_members}} declared ET-CC members, never all {{total_members}} members",
    "declared_checks" =>
      "the {{declared_checks}} declared in-population OC checks, never all " <>
        "{{in_denominator_checks}} in-denominator checks",
    "oc_checks_manifest" =>
      "A1's frozen manifest of {{manifest_checks}} checks, before the {{unmatchable_checks}} " <>
        "bucket-0 checks are removed, leaving {{in_denominator_checks}} in-denominator checks"
  }

  @doc "The ten bucket ids, in page order."
  @spec bucket_ids() :: [String.t()]
  def bucket_ids, do: Enum.map(@buckets, & &1.id)

  @doc """
  The static spec of one bucket — title, derivation, universe, and the
  UNRENDERED predicate template.

  `spec/2` is what a view uses. This arity exists for the parts that are the
  same whatever the population is, and it deliberately does not hand back a
  `:predicate`: a caller that got one without passing figures would be
  rendering `{{declared_members}}` into an artefact.
  """
  @spec spec(String.t()) :: map()
  def spec(id) do
    b = Enum.find(@buckets, &(&1.id == id)) || raise ArgumentError, "no such bucket: #{id}"
    Map.put(b, :predicate_template, Map.fetch!(@predicate_templates, id))
  end

  @doc "The spec of one bucket with its predicate rendered against `figures`."
  @spec spec(String.t(), map()) :: map()
  def spec(id, figures) do
    s = spec(id)
    Map.put(s, :predicate, render(s.predicate_template, figures))
  end

  @doc """
  The population banner every view and the roll-up carry, rendered against the
  figures of the crosswalk being projected.

  There is no arity-zero form. A banner that can be produced without the
  crosswalk is a banner that can disagree with it, which is CR-1 on MES-104.
  """
  @spec banner(map()) :: String.t()
  def banner(figures), do: @banner_template |> render(figures) |> reflow()

  # Re-wrapped AFTER substitution, per paragraph. A template wrapped by hand is
  # wrapped for the figures it was written against: `48` and `1024` are not the
  # same width, so the committed artefact would go ragged every time the
  # population moved — a small thing, but this whole ticket is about text that
  # no longer matches its numbers.
  defp reflow(text) do
    text
    |> String.split(~r/\n\s*\n/)
    |> Enum.map_join("\n\n", &wrap/1)
  end

  defp wrap(paragraph) do
    paragraph
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce([], &place_word/2)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp place_word(word, [line | rest]) when byte_size(line) + 1 + byte_size(word) <= 72,
    do: [line <> " " <> word | rest]

  defp place_word(word, lines), do: [word | lines]

  @doc """
  The population figures, every one of them COUNTED from the crosswalk under
  projection or read from a field that crosswalk states.

  A figure the crosswalk does not state is `nil`, and every figure derived
  from it is `nil` too — the `:population_statement` guard then refuses,
  naming the field. A figure that cannot be determined is a refusal; it is not
  a zero, because "0 members are not_yet_adjudicated" is the most dangerous
  sentence this generator could emit.
  """
  @spec figures(map(), map()) :: %{atom() => non_neg_integer() | nil}
  def figures(crosswalk, bucket_zero) do
    population = crosswalk["population"] || %{}
    outside = population["outside_the_population"] || %{}
    manifest = bucket_zero["checks"] || []

    cells = crosswalk["cells"] || []
    members = population["members"] || []
    checks = population["declared_checks"] || []
    addressed = cells |> Enum.map(& &1["tag"]) |> Enum.uniq()

    declared_members = length(members)
    declared_checks = length(checks)
    not_declared = length(addressed -- checks)
    outside_members = outside["et_cc_members"]
    outside_checks = outside["in_denominator_checks"]

    %{
      declared_members: declared_members,
      declared_checks: declared_checks,
      addressed_not_declared: not_declared,
      outside_members: outside_members,
      outside_checks: outside_checks,
      total_members: sum([declared_members, outside_members]),
      in_denominator_checks: sum([declared_checks, outside_checks, not_declared]),
      manifest_checks: length(manifest),
      unmatchable_checks: Enum.count(manifest, &(&1["matchable"] == false))
    }
  end

  @doc "The figure keys, so a control can enumerate them without reaching in."
  @spec figure_keys() :: [atom()]
  def figure_keys, do: @figure_keys

  @doc """
  Every population STATEMENT this generator emits, labelled, rendered against
  `figures`.

  This is the population `:population_statement` scans, and it is public so a
  control can assert the scan reached all of it — a scan over an empty
  population finds no defect and reports exactly the green of a scan that
  found none.
  """
  @spec statements(map()) :: [{String.t(), String.t()}]
  def statements(figures) do
    [{"banner", banner(figures)}] ++
      Enum.map(bucket_ids(), &{"predicate #{&1}", spec(&1, figures).predicate}) ++
      Enum.map(Enum.sort(Map.keys(@universe_of)), fn name ->
        {"universe.of #{name}", render(Map.fetch!(@universe_of, name), figures)}
      end) ++
      Enum.map(bucket_ids(), fn id ->
        {"emptiness #{id}", render(elem(Map.fetch!(@emptiness, id), 1), figures)}
      end)
  end

  # `{{key}}` -> the figure. An unknown key RAISES: a template naming a figure
  # that does not exist would otherwise emit `{{typo}}` into a committed
  # artefact, where it reads as decoration rather than as a fault.
  defp render(template, figures) do
    Regex.replace(~r/\{\{([a-z_]+)\}\}/, template, fn _whole, key ->
      case Map.fetch(figures, safe_key(key)) do
        {:ok, nil} -> "UNSTATED"
        {:ok, value} -> to_string(value)
        :error -> raise ArgumentError, "no such population figure: #{key}"
      end
    end)
  end

  defp safe_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :__no_such_figure__
  end

  defp sum(parts) do
    if Enum.any?(parts, &is_nil/1), do: nil, else: Enum.sum(parts)
  end

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

    # The bucket-2 universe is the DECLARED check population, never the checks
    # the cells happen to address. MES-104 separated the two: an edges file may
    # declare its checks from an external anchor, and it may also address checks
    # no file declares (C1a's inherited rows do). Projecting the complement
    # within the addressed set is what made bucket 2 empty by construction —
    # the set would be its own universe.
    checks = population["declared_checks"] || []
    addressed = cells |> Enum.map(& &1["tag"]) |> Enum.uniq() |> Enum.sort()
    unmatched = crosswalk["declared_unmatched"] || []

    members_with_edges = cells |> Enum.map(&member_key/1) |> Enum.uniq() |> Enum.sort()
    checks_with_edges = Enum.filter(addressed, &(&1 in checks))

    base = %{
      cells: cells,
      crosswalk: crosswalk,
      bucket_zero: bucket_zero,
      sources: sources,
      members: members,
      checks: checks,
      addressed: addressed,
      unmatched: unmatched,
      members_with_edges: members_with_edges,
      checks_with_edges: checks_with_edges
    }

    rows = Map.new(bucket_ids(), &{&1, rows_for(&1, base)})

    base
    |> Map.put(:rows, rows)
    |> Map.put(:escalated, Enum.filter(cells, &(&1["bucket"] == nil)))
    |> Map.put(:figures, figures(crosswalk, bucket_zero))
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

  # A crosswalk whose edges files declare NO check population has no bucket-2
  # question to answer, and `Crosswalk.project/2` refusing the complement is
  # how that is found out. The refusal is REPORTED — the view is empty with the
  # `not_declared` reason — rather than raised: an empty 2a/2b carrying
  # `by_adjudication` would say "we looked at the declared checks and every one
  # of them is covered", which is a claim nobody made.
  defp unmatched_checks(ctx, want) do
    case Crosswalk.project(:bucket_2, %{
           population: ctx.checks,
           with_edges: ctx.checks_with_edges
         }) do
      {:ok, rows} ->
        rows
        |> Enum.sort()
        |> Enum.map(&%{"tag" => &1, "leg" => tag_leg(&1)})
        |> Enum.filter(&(&1["leg"] == want))

      {:error, :empty_population} ->
        []

      {:error, reason} ->
        raise ArgumentError, "bucket_2 could not be projected: #{inspect(reason)}"
    end
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
      # The CHECK partition, re-cut by MES-104 because its old form could no
      # longer fail. It compared the declared checks against `2a ++ 2b ++ the
      # checks carrying an edge` — and once the declared checks became the
      # bucket-2 UNIVERSE, `2a ++ 2b` is that universe minus the edge-bearing
      # ones by construction, so the two sides were the same set written twice.
      # A guard entailed by the way its own inputs are computed is as empty as
      # one nobody calls.
      #
      # What it compares now is the crosswalk's OWN stored bucket 2 against the
      # one these views project. Two independently produced statements about the
      # same thing — `mix conformance.crosswalk` computed the first, this module
      # the second — so a disagreement is a real defect: an edited artefact, or
      # a projection that has drifted from the matrix it claims to render. A
      # CONSISTENCY pin in ruling 9's sense; it does not witness that either is
      # right.
      checks: Crosswalk.set_compare(stored_bucket_2(ctx.crosswalk), bucket_2),
      checks_reach_a_view: Crosswalk.set_compare(ctx.checks, bucket_2 ++ ctx.checks_with_edges),
      pairwise: pairwise(ctx)
    })
  end

  defp stored_bucket_2(crosswalk) do
    get_in(crosswalk, ["buckets", "bucket_2", "checks"]) || []
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
    r = ctx.partition.checks_reach_a_view

    if c.equal and r.equal do
      nil
    else
      {:check_partition,
       "CHECK PARTITION — the bucket 2 these views project is not the bucket 2 the crosswalk " <>
         "stores, or the declared checks are not partitioned by 2a, 2b and the checks carrying " <>
         "an edge:\n" <>
         "  in the crosswalk's bucket 2, in no view (#{length(c.missing)}):\n" <>
         Enum.map_join(c.missing, "\n", &"    #{&1}") <>
         "\n  in 2a or 2b, not in the crosswalk's bucket 2 (#{length(c.extra)}):\n" <>
         Enum.map_join(c.extra, "\n", &"    #{&1}") <>
         "\n  declared checks reaching no view (#{length(r.missing)}):\n" <>
         Enum.map_join(r.missing, "\n", &"    #{&1}") <>
         "\n  in a view, not a declared check (#{length(r.extra)}):\n" <>
         Enum.map_join(r.extra, "\n", &"    #{&1}")}
    end
  end

  # --- :population_statement -------------------------------------------------
  #
  # CR-1's guard. The four limbs answer four different questions, and none of
  # them is entailed by the interpolation that fixed the instance:
  #
  #   P1  can the figures be determined at all? A crosswalk that does not state
  #       its outside-the-population block gives `nil`, and a banner rendered
  #       over a nil is the "0 members remain" sentence. Fail-closed.
  #   P2  do the crosswalk's OWN stated counts agree with its own lists? Two
  #       statements produced separately inside one artefact, pinned. This is
  #       the limb a mutated CROSSWALK fires, which is why the guard is visible
  #       to `guard-mutation`.
  #   P3  does any emitted statement carry a population figure it did not
  #       interpolate? Answered by rendering every statement a SECOND time
  #       against sentinel figures and looking for a number that did not move.
  #       A literal cannot move, so it is caught by its own constancy — no
  #       allow-list of permitted numbers, which would decay into the
  #       exception list that licenses the next one.
  #   P4  do the rendered statements actually STATE the tree's figures? P3
  #       catches a literal; P4 catches an interpolation of the WRONG figure,
  #       which P3 cannot see because a wrong figure moves under sentinels just
  #       as a right one does. The phrases are built here, independently of the
  #       templates, so the two have to be edited together — a consistency pin
  #       (ruling 9), not a proof that either wording is right.
  #
  # WHAT IT DOES NOT COVER, stated rather than implied. The scan reads the
  # statements in `statements/1` only, so prose elsewhere in this module —
  # moduledoc, `boundary/0`, the residual texts — is outside it. It reads a
  # figure written in DIGITS adjacent to `members` or `checks`; a figure spelled
  # as a word, or stated without its noun, is not a claim it can see.
  @population_claim ~r/(\d+)[\s-](?:[A-Za-z][\w-]*[\s-]){0,3}?(?:members?|checks?)\b/

  @required_crosswalk_fields [
    ["population", "member_count"],
    ["population", "declared_check_count"],
    ["population", "outside_the_population", "et_cc_members"],
    ["population", "outside_the_population", "in_denominator_checks"]
  ]

  # Four limbs, in order of what they can determine: no figures at all, figures
  # the artefact contradicts, a figure that is not a figure, a figure in the
  # wrong place. The first to fire is the one reported, so the message names
  # the cheapest true explanation rather than the last one checked.
  defp guard(:population_statement, ctx) do
    Enum.find_value(
      [
        &undeterminable/1,
        &stated_counts/1,
        &hard_coded_figures/1,
        &statements_against_the_tree/1
      ],
      & &1.(ctx)
    )
  end

  # P1
  defp undeterminable(ctx) do
    missing = Enum.reject(@required_crosswalk_fields, &(get_in(ctx.crosswalk, &1) != nil))

    if missing == [] do
      nil
    else
      {:population_statement,
       "POPULATION STATEMENT — the crosswalk does not state #{length(missing)} of the figures " <>
         "every view's banner declares, so the population cannot be determined and this " <>
         "generator will not guess one. Rendering a nil as 0 would emit \"0 members and 0 " <>
         "checks are not_yet_adjudicated\", which is the strongest false claim these artefacts " <>
         "could make:\n" <> Enum.map_join(missing, "\n", &"  #{Enum.join(&1, ".")}")}
    end
  end

  # P2
  defp stated_counts(ctx) do
    pairs = [
      {"population.member_count", get_in(ctx.crosswalk, ["population", "member_count"]),
       length(ctx.members)},
      {"population.declared_check_count",
       get_in(ctx.crosswalk, ["population", "declared_check_count"]), length(ctx.checks)}
    ]

    case Enum.reject(pairs, fn {_f, stated, counted} -> stated == counted end) do
      [] ->
        nil

      bad ->
        {:population_statement,
         "POPULATION STATEMENT — the crosswalk's own stated counts disagree with its own " <>
           "lists, so a banner interpolated from either would be a statement the other " <>
           "artefact contradicts:\n" <>
           Enum.map_join(bad, "\n", fn {field, stated, counted} ->
             "  #{field}: states #{inspect(stated)}, the list holds #{counted}"
           end)}
    end
  end

  @doc """
  The sentinel figures P3 renders against — one distinct improbable value per
  figure key, so a number that is not one of them did not come from a figure.
  """
  @spec sentinel_figures() :: %{atom() => pos_integer()}
  def sentinel_figures,
    do: Map.new(Enum.with_index(@figure_keys), fn {k, i} -> {k, 900_001 + i} end)

  @doc """
  Every population figure in `statements` that is NOT a sentinel — i.e. every
  one that a render against `sentinel_figures/0` left standing, which is every
  one written as a literal.

  Public because it is P3's whole decision, and a decision only a whole-module
  recompile can reach is a decision gate 5 cannot hold. The control does the
  recompile; the units drive this.
  """
  @spec frozen_figures([{String.t(), String.t()}]) :: [{String.t(), String.t(), String.t()}]
  def frozen_figures(statements) do
    allowed = sentinel_figures() |> Map.values() |> MapSet.new()

    for {label, text} <- statements,
        [_whole, number | _] <- Regex.scan(@population_claim, text),
        not MapSet.member?(allowed, String.to_integer(number)),
        do: {label, number, text}
  end

  @doc """
  Every phrase a statement is required to contain and does not, with the
  phrases built from `figures` rather than from the templates.

  Public for the same reason as `frozen_figures/1`.
  """
  @spec missing_phrases([{String.t(), String.t()}], map()) :: [{String.t(), String.t()}]
  def missing_phrases(statements, figures) do
    rendered = Map.new(statements, fn {label, text} -> {label, squash(text)} end)

    for {label, phrases} <- required_phrases(figures),
        text = Map.get(rendered, label),
        text != nil,
        phrase <- phrases,
        not String.contains?(text, squash(phrase)),
        do: {label, phrase}
  end

  # P3
  defp hard_coded_figures(_ctx) do
    frozen = frozen_figures(statements(sentinel_figures()))

    if frozen == [] do
      nil
    else
      {:population_statement,
       "POPULATION STATEMENT — #{length(frozen)} population figure(s) are HARD-CODED. Every " <>
         "figure below survived a render against sentinel figures unchanged, so it states a " <>
         "population this generator did not count. That is CR-1 on MES-104: C1a's banner was a " <>
         "literal, three populations went past it, and twelve committed views declared a slice " <>
         "their own universe counts contradicted. Interpolate it from `figures/1`:\n" <>
         Enum.map_join(frozen, "\n", fn {label, number, text} ->
           "  #{label}: #{number} — in #{inspect(String.slice(text, 0, 90))}"
         end)}
    end
  end

  # P4
  defp statements_against_the_tree(ctx) do
    absent = missing_phrases(statements(ctx.figures), ctx.figures)

    if absent == [] do
      nil
    else
      {:population_statement,
       "POPULATION STATEMENT — #{length(absent)} statement(s) do not state the figure this " <>
         "tree holds. The phrase is built from the crosswalk under projection and looked for " <>
         "in the rendered statement, so this fires on an interpolation of the WRONG figure, " <>
         "which the hard-coded check cannot see (a wrong figure moves under sentinels exactly " <>
         "as a right one does):\n" <>
         Enum.map_join(absent, "\n", fn {label, phrase} ->
           "  #{label}: expected to contain #{inspect(phrase)}"
         end)}
    end
  end

  # Written HERE and not in the templates, on purpose: a pin between two
  # independently authored statements is only a pin while they are two.
  defp required_phrases(f) do
    %{
      "banner" => [
        "#{f.declared_members} declared ET-CC members",
        "#{f.declared_checks} declared in-population OC checks",
        "#{f.total_members} ET-CC members",
        "#{f.in_denominator_checks} in-denominator OC checks",
        "#{f.outside_members} members and #{f.outside_checks} checks are not_yet_adjudicated",
        "#{f.addressed_not_declared} checks carry an edge"
      ],
      "predicate 0" => [
        "the #{f.manifest_checks} checks of A1's manifest",
        "built against #{f.in_denominator_checks} checks"
      ],
      "predicate 1" => [
        "the #{f.declared_members} declared members",
        "never all #{f.total_members} members"
      ],
      "predicate 2a" => [
        "the #{f.declared_checks} declared checks",
        "never all #{f.in_denominator_checks} in-denominator checks"
      ],
      "predicate 2b" => [
        "the #{f.declared_checks} declared checks",
        "never all #{f.in_denominator_checks} in-denominator checks"
      ],
      "universe.of declared_members" => [
        "the #{f.declared_members} declared ET-CC members",
        "never all #{f.total_members} members"
      ],
      "universe.of declared_checks" => [
        "the #{f.declared_checks} declared in-population OC checks",
        "never all #{f.in_denominator_checks} in-denominator checks"
      ],
      "universe.of oc_checks_manifest" => [
        "manifest of #{f.manifest_checks} checks",
        "the #{f.unmatchable_checks} bucket-0 checks",
        "leaving #{f.in_denominator_checks} in-denominator checks"
      ]
    }
  end

  # A template wraps; a phrase written on one line does not. Both sides are
  # whitespace-collapsed so the pin is on the WORDS and not on the fill.
  defp squash(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()

  # --- the artefacts --------------------------------------------------------

  defp files(ctx) do
    views =
      Map.new(bucket_ids(), fn id -> {"bucket-#{id}-#{@revision}.json", view(id, ctx)} end)

    views
    |> Map.put("escalated-#{@revision}.json", escalated_view(ctx))
    |> Map.put("roll-up-#{@revision}.json", roll_up(ctx))
  end

  defp view(id, ctx) do
    s = spec(id, ctx.figures)
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
      "population_banner" => banner(ctx.figures),
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
    do: %{"name" => "edges", "count" => length(ctx.cells), "of" => universe_of("edges", ctx)}

  defp universe("declared_members", ctx),
    do: %{
      "name" => "declared_members",
      "count" => length(ctx.members),
      "of" => universe_of("declared_members", ctx)
    }

  defp universe("declared_checks", ctx),
    do: %{
      "name" => "declared_checks",
      "count" => length(ctx.checks),
      "of" => universe_of("declared_checks", ctx),
      "addressed_but_not_declared" => length(ctx.addressed) - length(ctx.checks_with_edges),
      "why_that_number_is_not_in_this_universe" =>
        "Checks an edge addresses that no file DECLARES. They carry adjudicated edges, so they " <>
          "are not bucket 2, and they are in no declared universe, so they are not in 2a or 2b " <>
          "either. Counting them here would make the complement — which is what 2a and 2b are — " <>
          "a complement within the very set it is taken from."
    }

  defp universe("oc_checks_manifest", ctx),
    do: %{
      "name" => "oc_checks_manifest",
      "count" => length(ctx.bucket_zero["checks"] || []),
      "of" => universe_of("oc_checks_manifest", ctx)
    }

  defp universe_of(name, ctx), do: render(Map.fetch!(@universe_of, name), ctx.figures)

  # Emitted ONLY when the view is really empty, and carrying a MEASURE rather
  # than an assertion: "checked, and zero" has to say what was checked.
  defp emptiness(_id, [_ | _], _ctx), do: nil

  defp emptiness(id, [], ctx) when id in ["2a", "2b"] do
    if ctx.checks == [] do
      %{
        "code" => "not_declared",
        "result" =>
          "NOT ASKED — no edges file in this run declares a check population, so bucket 2 has no " <>
            "universe and this view is empty for want of a question, not for want of a member.",
        "what_would_fill_it" =>
          "An edges file declaring its check population from an external anchor. Until one does, " <>
            "`Crosswalk.project/2` refuses the complement and that refusal is what this is.",
        "measured" => "declared checks: 0. Addressed by an edge: #{length(ctx.addressed)}.",
        "ticket_that_would_fill_it" => "whichever ticket declares the checks for this leg"
      }
    else
      standard_emptiness(id, ctx)
    end
  end

  defp emptiness(id, [], ctx), do: standard_emptiness(id, ctx)

  defp standard_emptiness(id, ctx) do
    {code, fill} = Map.fetch!(@emptiness, id)

    %{
      "code" => code,
      "result" => "CHECKED, AND ZERO — within the declared slice. Not 'never asked'.",
      "what_would_fill_it" => render(fill, ctx.figures),
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
      "of #{length(ctx.checks)}. (#{length(ctx.addressed) - length(ctx.checks_with_edges)} " <>
      "further checks carry an edge but are DECLARED by no file, so they are in no universe " <>
      "this view takes a complement within.)"
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
      "population_banner" => banner(ctx.figures),
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
      "population_banner" => banner(ctx.figures),
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
        universe_of("declared_members", ctx)
      ),
      equation(
        "declared_checks",
        length(ctx.checks),
        check_terms,
        universe_of("declared_checks", ctx)
      ),
      %{
        "universe" => "oc_checks_manifest",
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
        direction_report(
          p.checks,
          "the bucket 2 these views project equals the bucket 2 the crosswalk stores — a " <>
            "CONSISTENCY pin between two independently produced statements (ruling 9), not a " <>
            "claim that either is right"
        ),
      "declared_checks_reach_a_view" =>
        direction_report(
          p.checks_reach_a_view,
          "every declared check is in 2a, in 2b, or carries an edge. ENTAILED by the way the " <>
            "views are computed and therefore unable to fail — recorded as arithmetic, not as " <>
            "evidence (MES-104)"
        ),
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
        "text" => String.replace(banner(ctx.figures), "\n", " ")
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
          "BUCKET 0 IS A CITATION. Its #{ctx.figures.unmatchable_checks} rows are A5's " <>
            "records verbatim and were removed " <>
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
