defmodule Mix.Tasks.Conformance.Crosswalk do
  @shortdoc "Join the adjudicated ET-CC members to the in-scope OC checks and assign the bucket"

  @moduledoc """
  Derive `docs/conformance/crosswalk-2026-07-28.json` — the matrix the ten
  buckets are projections of, over the populations the edges files declare.

      mix conformance.crosswalk \\
        --edges conformance/data/crosswalk-edges-client.json \\
        --edges conformance/data/crosswalk-edges.json \\
        --manifest docs/conformance/in-scope-2026-07-28.json \\
        --denominator docs/conformance/bucket-0-2026-07-28.json \\
        --register docs/conformance/etcc-register.json \\
        --attribution docs/conformance/etcc-attribution.json \\
        --a3-axes docs/conformance/oc-axes-2026-07-28.json \\
        --c1-axes conformance/data/oc-axes-c1.json \\
        --emitting-sites docs/conformance/oc-emitting-sites-2026-07-28.json \\
        --harness /tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js \\
        -o docs/conformance/crosswalk-2026-07-28.json

  ## What it refuses, and every one of these is a way a crosswalk lies

  * **A tag that does not resolve** in A1's manifest — A3 §6 state 2, a typo or
    a key gone stale against a harness bump.
  * **A tag that is not what its own key encodes** — the stored token and the
    token re-derived from the resolved row must be equal.
  * **An axis name the check's decomposition does not contain**, and an axis
    set that is not the decomposition's whole set. A verdict against an axis
    nobody extracted is a verdict about nothing; a missing axis is a `:partial`
    nobody declared.
  * **A state-4 member inside the declared population** — A3 §6's completeness
    half. It does NOT make an empty crosswalk fail, and D3's claim that it is
    "the limb that makes an EMPTY crosswalk fail" is wrong: the reject over an
    empty member list is empty, so `check_population([], tagged)` returns `:ok`
    and the VACUUM guard is what fires on emptiness (F2 / residual X7). Where a
    population is derived from its own file's rows the guard is entailed by
    G15a and cannot fire at all — recorded, not removed, because it is A3 §6's
    ratified rule (S9-15 / D3).
  * **Two axis artefacts claiming the same check** — one fact, one home (D4).
  * **A bucket-1 or bucket-2 projection with no declared universe** — a
    complement is not a fact without one.
  * **Arithmetic that does not reconcile**, and totality that holds by count
    but not by SET.
  * **Committed axis spans whose bytes have moved** — when `--harness` is
    given, the axis exprs are re-checked verbatim against the live build.
  * **Two edges sharing a `(member, claim, tag)` triple** — G14, the join's own
    key, counted twice.
  * **A population that is not the set its own `selector` denotes**, or that
    disagrees with its own declared counts — G15. The selector is evaluated
    against an artefact *outside* the file being validated, which is the whole
    point of it: C1a derived the population from the edges file itself, so a
    dropped row shrank the universe rather than violating it.
  * **A manifest whose verdicts have drifted from A5's bucket-0 artefact** —
    G16, compared as sets of keys and then per key.
  * **Two edges files declaring the same member** — G17. One member, one home.
    A member in two populations is adjudicated twice and the two adjudications
    need not agree, and nothing downstream notices: every equation reconciles
    over a union that counts it once.
  * **An axis row claiming a provenance for its emitting span that the
    locator's output does not support** — G18. A row may REJECT the locator's
    span, and the rejection is guarded harder than the acceptance.
  * **A DECLARED check with no axis decomposition** — G19. A bucket-2 check has
    to be read before it can be reported as having no ET counterpart.
  * **A claim-level unmatched record against a member that carries no edge** —
    that member is state 3 whole and belongs in `declared_unmatched`, where
    bucket 1 counts it.
  * **A quoted byte-string in a record's `evidence` that is not verbatim at an
    address the evidence itself names** — G30. Ruling 7 is "an address AND the
    bytes at it"; every sweep before this one established only the first half.
    Two limbs: WINDOWING compares against the CITED span and so catches a
    right-bytes/wrong-line citation, CONTIGUITY compares as one substring and so
    catches a quote spliced from two real but non-adjacent lines. A bare `:N`
    continuation is refused as a form, and an elision is refused rather than
    fragment-matched.
  * **A population figure in this generator's own prose that the run did not
    derive** — G21. CR-1 (MES-104) interpolated every figure in the PROJECTOR
    and guarded it; this generator's statements were left as literals, and one
    ticket later `trust_status` declared a `48-member / 29-declared-check`
    slice over a 68/39 population while the twelve views projected from it
    interpolated the right pair (CR-5, MES-108). The scan's universe is the
    EMITTED artefact and a string is this generator's own iff it occurs in no
    input document, so a statement added later is inside the guard without
    anyone adding it to a list.

  ## `--edges` is repeatable, and bucket 2 can now be non-empty

  MES-104's composition ruling put one edges file per leg, so the task takes
  several and the crosswalk's population is their UNION. Two things follow.
  Populations may not overlap (G17). And each file may declare its own **check**
  population from an external anchor — C1a derived its check universe from the
  tags its own edges carried, so bucket 2 was the complement of a set within
  itself, empty by construction, and its `CHECKED, AND ZERO` could not have said
  anything else. A file that declares no check population contributes none to
  bucket 2's universe, and the artefact says so rather than reporting a zero.

  ## The second source path

  `--verdicts-from manifest|bucket-0` reads the row set and the per-check
  verdicts from either A1's manifest (the default, and the committed artefact's
  provenance) or A5's bucket-0 artefact. The two runs must produce a
  byte-identical file. That is a **consistency** pin and not a correctness one
  (ruling 9): both artefacts descend from the same accepted harness run, so it
  witnesses that nobody edited one without regenerating the other.

  ## The keying control runs, and it runs BOTH directions

  There is no naturally unique check key: `http-standard-headers` has 11 checks
  sharing one `id`, `server-stateless` 30 checks with 28 `id`s and 26 `name`s.
  So the task measures, on the real 173, how many rows each candidate keying
  **loses** — and requires the obvious ones to lose rows and A1's six-field key
  to lose none. Only the second direction would pass over a crosswalk keyed on
  `id`; running only the first would prove nothing about the key in use.

  ## What a clean run does NOT establish

  That any axis verdict is right. Whether our claim really agrees with a
  conjunct is A3 §7's semantic-sameness residual and escalates per case — and
  no refusal can ever reach it, which is why C3 needs a pinned per-row bucket
  assignment (`crosswalk_falsification_controls.exs drift`) as well as these
  refusals.

  That anything **outside** the declared population is adjudicated. The tickets
  that own the rest are the ones `population.outside_the_population.owners`
  names. Neither that field nor this sentence may name the ticket that is
  RENDERING the artefact: a document naming its own producer as still owing the
  remainder is CR-1's defect (MES-104), and it recurred here as CR-5 (MES-108).

  ## Exit status

  `0` derived. `1` refused. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, CitationVerbatim, Crosswalk, Locator, MatchKey}

  @switches [
    edges: [:string, :keep],
    manifest: :string,
    denominator: :string,
    register: :string,
    attribution: :string,
    a3_axes: :string,
    c1_axes: :string,
    emitting_sites: :string,
    harness: :string,
    verdicts_from: :string,
    out: :string
  ]
  @aliases [o: :out]

  @usage """
  mix conformance.crosswalk --edges FILE [--edges FILE ...] --manifest FILE --denominator FILE \
  --register FILE --attribution FILE --a3-axes FILE --c1-axes FILE --emitting-sites FILE \
  [--harness FILE] [--verdicts-from manifest|bucket-0] -o FILE\
  """

  @revision "2026-07-28"

  @impl Mix.Task
  def run(argv) do
    {opts, _} =
      Argv.parse!("conformance.crosswalk", argv,
        strict: @switches,
        aliases: @aliases,
        usage: @usage
      )

    edges_docs = edges_docs!(opts)
    manifest = opts |> require!(:manifest) |> read_json!()
    denominator = opts |> require!(:denominator) |> read_json!()
    register = opts |> require!(:register) |> read_json!()
    attribution = opts |> require!(:attribution) |> read_json!()
    a3_axes = opts |> require!(:a3_axes) |> read_json!()
    c1_axes = opts |> require!(:c1_axes) |> read_json!()
    sites = opts |> require!(:emitting_sites) |> read_json!()
    out = require!(opts, :out)
    source = verdict_source!(opts)

    refuse_unless(manifest["arithmetic"]["total"] == 175, "the manifest is not the frozen 175")

    # G16 runs BEFORE the join, and before --verdicts-from picks one of the two
    # artefacts, because it is what makes either of them usable: a second source
    # that has silently drifted from the first would otherwise be read as
    # corroboration.
    agreement = cross_source!(manifest, denominator)

    {rows, statuses} = verdicts!(source, manifest, denominator)

    in_denominator =
      denominator["checks"] |> Enum.filter(& &1["matchable"]) |> Enum.map(& &1["key"])

    refuse_unless(
      length(in_denominator) == 173,
      "the denominator is not 173 — it is #{length(in_denominator)}"
    )

    axes = axis_index!([a3_axes, c1_axes])
    span_provenance = verify_emitting_spans!(c1_axes, sites, require!(opts, :emitting_sites))
    axis_bytes = verify_axis_bytes!(c1_axes, Keyword.get(opts, :harness))

    keys!(edges_docs)
    all_edges = Enum.flat_map(edges_docs, fn {_p, d} -> d["edges"] end)
    cells = cells!(all_edges, rows, statuses, axes)

    population =
      populations!(edges_docs, register, attribution, rows, axes, %{
        attribution: require!(opts, :attribution),
        register: require!(opts, :register),
        emitting_sites: require!(opts, :emitting_sites)
      })

    keying = keying!(in_denominator)
    absence = absence_searches!(edges_docs)

    citations =
      citation_verbatim!(
        edges_docs,
        c1_axes["checks"] ++ a3_axes["checks"],
        Keyword.get(opts, :harness)
      )

    buckets = buckets!(cells, population)
    claim_level = claim_level!(edges_docs, cells)

    # Bound BEFORE the artefact, because `trust_status` and three residuals are
    # interpolated from them. Every figure any statement below states comes from
    # here, and G21 refuses one that does not (CR-5 on MES-108).
    figures =
      figures(
        population,
        cells,
        buckets,
        claim_level,
        absence,
        length(in_denominator),
        manifest["arithmetic"]["total"]
      )

    artefact = %{
      "schema" => "crosswalk/1",
      "revision" => @revision,
      "generated_by" => "mix conformance.crosswalk",
      "owner" =>
        "MES-97 (C1a), MES-104 (C1b-i), MES-108 (C1b-ii), MES-109 (C1b-iii), MES-105 (C1c-i) " <>
          "and MES-115 (C1c-ii)",
      "what_this_is" =>
        "The single matrix the ten buckets are PROJECTIONS of. C2 renders it, C3 falsifies it, " <>
          "D adjudicates its cells. It decides what no bucket MEANS.",
      "trust_status" => trust_status(figures),
      "cross_source_agreement" => agreement,
      "population" => population,
      "absence_search_guard" => absence,
      "citation_verbatim_guard" => citations,
      "keying_control" => keying,
      "axis_provenance" => axis_bytes,
      "axis_span_provenance" => span_provenance,
      "verdict_mapping" => verdict_mapping(cells),
      "buckets" => buckets,
      "escalations" => escalations(cells),
      "totality" => totality(cells, population, edges_docs),
      "arithmetic" => arithmetic(cells, population),
      "residuals" => residuals(figures),
      "cells" => cells,
      "declared_unmatched" =>
        Enum.flat_map(edges_docs, fn {_p, d} -> d["declared_unmatched"] end),
      "claim_level_unmatched" => claim_level
    }

    # G21 reads the artefact as BUILT, then its own report is put in. The report
    # is required to carry no population claim of its own, so what it attests is
    # not changed by its being there.
    artefact =
      Map.put(
        artefact,
        "population_statement_guard",
        population_statement!(
          artefact,
          figures,
          Crosswalk.string_set(
            Enum.map(edges_docs, fn {_p, d} -> d end) ++
              [manifest, denominator, register, attribution, a3_axes, c1_axes, sites]
          )
        )
      )

    reconcile!(artefact)
    File.write!(out, Jason.encode!(artefact, pretty: true) <> "\n")
    report(artefact, out)
  end

  # `--edges` is REPEATABLE, and the order it is given in does not matter: every
  # cross-file result below is a set operation. One file per leg is the shape
  # MES-104's composition ruling settled on — the alternative, one file for
  # everything, cannot be declared by a per-leg selector, and the alternative of
  # a file per ticket splits a leg's adjudications by the accident of which
  # member happened to be tagged first.
  defp edges_docs!(opts) do
    case Keyword.get_values(opts, :edges) do
      [] ->
        Mix.raise("--edges is required (and may be given more than once).\n#{@usage}")

      paths ->
        dupes = (paths -- Enum.uniq(paths)) |> Enum.uniq()

        refuse_unless(dupes == [], """
        the same edges file was given twice: #{Enum.join(dupes, ", ")}.
        Every member and every edge in it would be counted twice, and the arithmetic would
        reconcile perfectly while doing so.
        """)

        Enum.map(paths, &{&1, read_json!(&1)})
    end
  end

  defp manifest_statuses(manifest) do
    for s <- manifest["scenarios"], c <- s["checks"], into: %{}, do: {c["key"], c["status"]}
  end

  defp bucket_zero_statuses(denominator) do
    Map.new(denominator["checks"], &{&1["key"], &1["status"]})
  end

  # --verdicts-from selects WHICH artefact the row set and the per-check verdicts
  # are read from. Both carry A1's six-field key and a `status`, they are written
  # by different generators at different tickets, and G16 above has just required
  # them to agree — so the two runs must produce a BYTE-IDENTICAL artefact. That
  # equality is C3's consistency pin (AC3), and it is the reason this flag does
  # not appear anywhere in the output: a field naming the source would make the
  # two files differ by construction and the pin would compare nothing.
  defp verdict_source!(opts) do
    case Keyword.get(opts, :verdicts_from, "manifest") do
      v when v in ["manifest", "bucket-0"] ->
        v

      other ->
        Mix.raise("--verdicts-from must be `manifest` or `bucket-0`, not #{inspect(other)}")
    end
  end

  defp verdicts!("manifest", manifest, _denominator),
    do: {MatchKey.rows_from_manifest(manifest), manifest_statuses(manifest)}

  defp verdicts!("bucket-0", _manifest, denominator),
    do: {Enum.map(denominator["checks"], & &1["key"]), bucket_zero_statuses(denominator)}

  # G16 — the two artefacts' verdicts, compared as SETS of keys and then per key.
  # A CONSISTENCY pin (ruling 9): both descend from the same accepted harness run,
  # so agreement witnesses that nobody edited one without regenerating the other,
  # and never that either is right.
  defp cross_source!(manifest, denominator) do
    a = Crosswalk.status_agreement(manifest_statuses(manifest), bucket_zero_statuses(denominator))

    refuse_unless(a["key_sets"]["equal"], """
    G16 — A1's manifest and A5's bucket-0 artefact do not carry the same check keys.
      in the manifest, absent from bucket-0: #{length(a["key_sets"]["missing"])}
      in bucket-0, absent from the manifest: #{length(a["key_sets"]["extra"])}
    Compared by SET, both directions. Two artefacts that each total 175 can still be
    about different 175s.
    """)

    refuse_unless(a["disagreements"] == [], """
    G16 — #{length(a["disagreements"])} checks carry a DIFFERENT status in A1's manifest than
    in A5's bucket-0 artefact, over an identical key set:
    #{Enum.map_join(Enum.take(a["disagreements"], 10), "\n", fn d -> "  #{Enum.join(Enum.take(d["key"], 4), " / ")}\n    manifest #{d["left"]}  vs  bucket-0 #{d["right"]}" end)}
    One of them has been edited without the other being regenerated. Which one is right
    is not decidable here — that is why this refuses rather than picking.
    """)

    a
  end

  # G14 — the join's own key, refused on the GENERATOR's path.
  #
  # C1a checks this on the committed output, which is a check on the artefact and
  # not a refusal by the generator (S9-15). Measured on MES-99: an edge duplicated
  # verbatim built cleanly, 23 edges -> 24, bucket 5 15 -> 16.
  defp keys!(edges_docs) do
    edges_doc = %{
      "edges" => Enum.flat_map(edges_docs, fn {_p, d} -> d["edges"] end),
      "declared_unmatched" => Enum.flat_map(edges_docs, fn {_p, d} -> d["declared_unmatched"] end)
    }

    # Over the UNION, not per file: two files each carrying the triple once is
    # the way a split-by-leg artefact counts one adjudication twice, and a
    # per-file check would pass over exactly that.
    dupes = Crosswalk.duplicate_edge_keys(edges_doc["edges"])

    refuse_unless(dupes == [], """
    G14 — repeated (member, claim, tag) triples (#{length(dupes)}). That triple is what the
    crosswalk is keyed on, so a repeat counts one adjudication twice — in the bucket
    frequencies, in the edge total and in every projection taken from them:
    #{Enum.map_join(dupes, "\n", fn {m, c, t} -> "  #{m}\n    claim: #{c}\n    tag:   #{t}" end)}
    """)

    unmatched_keys = Enum.map(edges_doc["declared_unmatched"], & &1["member"]["register_key"])
    unmatched_dupes = (unmatched_keys -- Enum.uniq(unmatched_keys)) |> Enum.uniq()

    refuse_unless(unmatched_dupes == [], """
    G14 — members declared unmatched more than once (#{length(unmatched_dupes)}):
    #{Enum.map_join(unmatched_dupes, "\n", &("  " <> &1))}
    """)
  end

  defp axis_index!(artefacts) do
    case Crosswalk.axis_index(artefacts) do
      {:ok, index} ->
        index

      {:error, {:axis_artefacts_overlap, keys}} ->
        Mix.raise("""
        two axis artefacts decompose the same check — one fact, two homes, and when they
        disagree nothing detects it (the MES-24 defect, D4):
        #{Enum.map_join(keys, "\n", &("  " <> Enum.join(Enum.take(&1, 4), " / ")))}
        """)
    end
  end

  # The axes are addressed spans into a build that lives in /tmp. When the build
  # is to hand, check the bytes: a citation whose bytes have moved still reads
  # as one. When it is not, say so — never treat absence as satisfaction.
  defp verify_axis_bytes!(c1_axes, nil) do
    %{
      "harness_checked" => false,
      "why" =>
        "--harness was not given, so the committed axis spans were NOT re-checked against the " <>
          "build. This is a stated gap, not a pass (MES-56: a silent skip reads absence as " <>
          "satisfaction).",
      "harness_dist_sha256_expected" => c1_axes["provenance"]["harness_dist_sha256"]
    }
  end

  defp verify_axis_bytes!(c1_axes, path) do
    {:ok, h} =
      case Locator.load(path) do
        {:ok, h} -> {:ok, h}
        {:error, r} -> Mix.raise("cannot read the harness at #{path}: #{inspect(r)}")
      end

    sha = Locator.sha256(h)
    expected = c1_axes["provenance"]["harness_dist_sha256"]

    refuse_unless(
      sha == expected,
      "the harness at #{path} is #{sha}, not the build the axes were read from (#{expected})"
    )

    violations = Enum.flat_map(c1_axes["checks"], &axis_violations(h, &1))

    refuse_unless(violations == [], """
    committed axis expressions are not verbatim at their committed spans:
    #{Enum.map_join(violations, "\n", &("  " <> inspect(&1)))}
    The spans address bytes and the bytes are the evidence. Re-cut them.
    """)

    %{
      "harness_checked" => true,
      "harness_dist_sha256" => sha,
      "harness_read_from" => path,
      "axes_checked" => Enum.sum(Enum.map(c1_axes["checks"], &length(&1["axes"]))),
      "what_was_checked" =>
        "every axis `expr`, every precondition `guard` and every listed conjunct occurs VERBATIM " <>
          "in the bytes at the span its row names — the emitting excerpt or a named context excerpt."
    }
  end

  defp axis_violations(h, check) do
    pool = byte_pool(h, check)

    axis_errs = Enum.flat_map(check["axes"], &axis_error(pool, Enum.at(check["key"], 2), &1))

    all = Map.values(pool)

    other_errs =
      Enum.flat_map(check["preconditions"], fn p ->
        if Enum.any?(all, &String.contains?(&1, p["guard"])),
          do: [],
          else: [{:precondition_not_verbatim, Enum.at(check["key"], 2), p["guard"]}]
      end) ++
        Enum.flat_map(conjuncts(check), fn c ->
          if Enum.any?(all, &String.contains?(&1, c)),
            do: [],
            else: [{:conjunct_not_verbatim, Enum.at(check["key"], 2), c}]
        end)

    axis_errs ++ other_errs ++ id_errors(pool, check)
  end

  # C1a's eleven rows all carry their check id as a backtick literal at the
  # emitting site, and this required exactly that. Fourteen of C1b-i's rows emit
  # with `id:c` — computed from the argument's value and declared type — and ten
  # more with `id:t`, a loop variable, so the literal is at an ADDRESSED span
  # the row names instead. `check_id_found_in` defaults to `evaluator_excerpt`,
  # which is C1a's behaviour unchanged, and the named span must exist.
  #
  # C1c-i meets a third shape, and it is the first one NO span can satisfy. The
  # `server-stateless` RequestMetaInvalid trio emits with
  # ``id:`sep-2575-request-meta-invalid-${e.slug}` `` — a TEMPLATE. Measured at
  # this build: none of `sep-2575-request-meta-invalid-missing-meta`,
  # `-missing-protocol-version` or `-missing-client-capabilities` occurs in the
  # 809 KB dist at all, so `String.contains?` can never be satisfied for them
  # and neither can any choice of `check_id_found_in`. The row therefore states
  # the COMPOSITION instead, and the guard checks the composition rather than
  # being weakened to let the row through:
  #
  #     "check_id_composition": {
  #       "template": "sep-2575-request-meta-invalid-${e.slug}",
  #       "template_found_in": "evaluator_excerpt",
  #       "hole": "${e.slug}",
  #       "substitution": "missing-meta",
  #       "substitution_found_in": "context:request_meta_invalid_slug_table"
  #     }
  #
  # Both halves must be VERBATIM at spans the row names, the hole must occur
  # EXACTLY ONCE in the template (twice and the substitution is ambiguous, zero
  # and the "composition" is a literal wearing a different name), and the
  # substituted result must equal the check id EXACTLY. That last conjunct is
  # what stops the degenerate composition S9-18 warns about — a row cannot
  # cover the id with fragments it found lying around, because the template is
  # pinned to the build and the only freedom is the one hole.
  #
  # `check_id_found_in` and `check_id_composition` are mutually exclusive: two
  # answers to one question, and nothing would choose between them.
  defp id_errors(pool, check) do
    id = Enum.at(check["key"], 2)

    case {Map.get(check, "check_id_found_in"), Map.get(check, "check_id_composition")} do
      {found_in, nil} -> [id_literal_error(pool, id, found_in || "evaluator_excerpt")]
      {nil, comp} -> id_composition_errors(pool, id, comp)
      {_, _} -> [{:check_id_is_both_located_and_composed, id}]
    end
    |> Enum.reject(&is_nil/1)
  end

  defp id_literal_error(pool, id, where) do
    case Map.fetch(pool, where) do
      :error ->
        {:check_id_found_in_names_no_such_span, id, where}

      {:ok, src} ->
        unless String.contains?(src, id), do: {:span_does_not_carry_the_check_id, id, where}
    end
  end

  defp id_composition_errors(pool, id, comp) do
    %{"template" => template, "hole" => hole, "substitution" => sub} = comp

    [
      verbatim_at(pool, comp["template_found_in"], template, {:template, id}),
      verbatim_at(pool, comp["substitution_found_in"], sub, {:substitution, id}),
      hole_error(template, hole, id),
      composition_error(template, hole, sub, id)
    ]
  end

  defp verbatim_at(pool, where, needle, {what, id}) do
    case Map.fetch(pool, where) do
      :error ->
        {:composition_names_no_such_span, what, id, where}

      {:ok, src} ->
        unless String.contains?(src, needle),
          do: {:composition_part_not_verbatim, what, id, needle, where}
    end
  end

  defp hole_error(template, hole, id) do
    case length(String.split(template, hole)) - 1 do
      1 -> nil
      n -> {:composition_hole_occurs_n_times, id, hole, n}
    end
  end

  defp composition_error(template, hole, sub, id) do
    composed = String.replace(template, hole, sub)

    unless composed == id, do: {:composition_does_not_yield_the_check_id, id, composed}
  end

  defp axis_error(pool, check_id, ax) do
    case Map.fetch(pool, ax["expr_found_in"]) do
      :error ->
        [{:no_such_source, check_id, ax["expr_found_in"]}]

      {:ok, src} ->
        if String.contains?(src, ax["expr"]),
          do: [],
          else: [{:expr_not_verbatim, check_id, ax["expr"]}]
    end
  end

  defp byte_pool(h, check) do
    [from, to] = check["emitting_byte_span"]

    check["context_excerpts"]
    |> Map.new(fn x ->
      [a, b] = x["byte_span"]
      {"context:" <> x["label"], Locator.bytes(h, {a, b})}
    end)
    |> Map.put("evaluator_excerpt", Locator.bytes(h, {from, to}))
  end

  defp conjuncts(%{"conjunct_grouping" => %{"conjuncts" => c}}), do: c
  defp conjuncts(_), do: []

  # G18 — every C1 axis row states where its `emitting_byte_span` came from, and
  # this checks the statement against MES-97's locator output.
  #
  # C1a's file said `emitting_spans_from: ... mix conformance.locator, not
  # re-cut by hand` and NOTHING checked it. That was true of all eleven rows;
  # it is not true of four of C1b-i's, and it could not be: the locator resolves
  # `ClientCustomHeader_Region` and three siblings on the `id_literal_site`
  # rung at pin level CHECK — it pins the id, not the row — and the sites it
  # names belong to two differently-named siblings that share the id. A row may
  # therefore REJECT the locator's span, and the rejection is guarded harder
  # than the acceptance: the locator must not claim to pin that row, the span
  # used must not be one the locator names, and a reason must be given.
  defp verify_emitting_spans!(c1_axes, sites, sites_path) do
    by_key = Map.new(sites["rows"], &{&1["key"], &1})
    problems = Enum.flat_map(c1_axes["checks"], &span_provenance_error(&1, by_key))

    refuse_unless(problems == [], """
    G18 — #{length(problems)} axis rows disagree with #{sites_path} about their emitting span:
    #{Enum.map_join(problems, "\n", &("  " <> inspect(&1)))}
    A span is an address into a build. A row that says the locator gave it one, and did not
    get it there, is citing a provenance it does not have.
    """)

    accepted = Enum.count(c1_axes["checks"], &(provenance(&1) == "locator_row"))

    %{
      "checked_against" => sites_path,
      "rows" => length(c1_axes["checks"]),
      "locator_row" => accepted,
      "locator_row_rejected" => length(c1_axes["checks"]) - accepted,
      "what_was_checked" =>
        "For every `locator_row` row, the committed `emitting_byte_span` is one the locator names " <>
          "for that row's key. For every `locator_row_rejected` row, the locator's own " <>
          "`rung_pin_level` is NOT `row`, the span used is NOT one the locator names, and a reason " <>
          "is recorded. An unknown provenance value is refused.",
      "what_this_does_not_establish" =>
        "That a rejected row's span is the RIGHT one. It establishes that the row is not claiming " <>
          "the locator's authority for a span the locator did not give it. The bytes at the span " <>
          "are checked separately, and only when --harness is given."
    }
  end

  defp provenance(check), do: Map.get(check, "emitting_span_provenance")

  defp span_provenance_error(check, by_key) do
    id = Enum.at(check["key"], 3)

    case {provenance(check), Map.fetch(by_key, check["key"])} do
      {_, :error} -> [{:no_locator_row_for, id}]
      {"locator_row", {:ok, row}} -> accepted_span_error(check, row, id)
      {"locator_row_rejected", {:ok, row}} -> rejected_span_error(check, row, id)
      {other, _} -> [{:unknown_emitting_span_provenance, id, other}]
    end
  end

  defp accepted_span_error(check, row, id) do
    if check["emitting_byte_span"] in locator_spans(row),
      do: [],
      else: [{:span_is_not_one_the_locator_names, id, check["emitting_byte_span"]}]
  end

  # Guarded HARDER than an acceptance, and each limb names a different way of
  # rejecting the locator dishonestly.
  defp rejected_span_error(check, row, id) do
    span = check["emitting_byte_span"]

    cond do
      row["rung_pin_level"] == "row" -> [{:rejected_a_row_level_pin, id, row["rung"]}]
      span in locator_spans(row) -> [{:rejection_uses_the_span_it_rejected, id, span}]
      no_reason?(check) -> [{:rejection_gives_no_reason, id}]
      true -> []
    end
  end

  defp locator_spans(row), do: Enum.map(row["sites"], & &1["byte_span"])

  defp no_reason?(check), do: (Map.get(check, "emitting_span_provenance_why") || "") == ""

  defp cells!(edges, rows, statuses, axes) do
    {cells, errors} =
      Enum.reduce(edges, {[], []}, fn edge, {ok, bad} ->
        case Crosswalk.cell(edge, rows, statuses, axes) do
          {:ok, cell} -> {[cell | ok], bad}
          {:error, reason} -> {ok, [{edge["claim"], reason} | bad]}
        end
      end)

    refuse_unless(errors == [], """
    #{length(errors)} stored edges did not survive re-derivation:
    #{errors |> Enum.reverse() |> Enum.map_join("\n", fn {claim, r} -> "  #{claim}\n    #{inspect(r)}" end)}
    """)

    Enum.reverse(cells)
  end

  # ---------------------------------------------------------------------------
  # The declared populations, one per edges file, and what holds ACROSS them.
  #
  # Per file: the vacuum guard, the ET-CC stray guard, G15a (set-equal to its
  # own external selector, both directions), G15b (its own counts), and A3 §6
  # state 3 on every declared_unmatched row.
  #
  # Across files: the populations may not OVERLAP (one member, one home — the
  # D4 rule, applied to members rather than to axis artefacts), and the A3 §6
  # state-4 guard runs over the union.
  #
  # There is no separate "an edge whose member lies outside its own file's
  # declared population" refusal, and that is deliberate rather than an
  # omission: G15a already refuses it, as an `extra` in the set comparison. A
  # second guard entailed by the first can never fire, and a guard that cannot
  # fire is as empty as one nobody calls.
  # ---------------------------------------------------------------------------
  defp populations!(edges_docs, register, attribution, rows, axes, paths) do
    # ONE HOME for the `label == "ET-CC"` predicate, and it is a pure function
    # with its own units (`Crosswalk.etcc_universe/1`): the stray guard needs it
    # as a membership test and G24 needs it as a SET, and deriving it twice would
    # be two homes for one fact.
    universe = Crosswalk.etcc_universe(register)
    etcc = MapSet.new(universe)

    sites = read_json!(paths.emitting_sites)

    files =
      Enum.map(edges_docs, &file_population!(&1, etcc, attribution, sites, rows, axes, paths))

    overlaps!(files)

    members = files |> Enum.flat_map(& &1["members"]) |> Enum.sort()

    totality = whole_crosswalk_totality!(universe, members, paths.register)

    declared_checks =
      files |> Enum.flat_map(& &1["declared_checks"]) |> Enum.uniq() |> Enum.sort()

    checks =
      edges_docs
      |> Enum.flat_map(fn {_p, d} -> Enum.map(d["edges"], & &1["tag"]) end)
      |> Enum.uniq()
      |> Enum.sort()

    # WHERE A TOKEN LIVES, and why this is not just B2b's register any more.
    #
    # C1a's population WAS B2b's tagged rows, so every member carried a B2b
    # token by construction. C1b-i's population is `client AND (CG7 OR already
    # adjudicated)`, and the 27 members the CG7 conjunct brings in are the ones
    # this ticket adjudicates: their tokens are produced HERE, in the edges
    # files, which is the home of the adjudication (D4). Reading the guard
    # against B2b alone would fail all 27 for not carrying a decision the run is
    # in the middle of making, and the only way to satisfy it would be to write
    # the adjudication into B2b's register as well — a second home for one fact.
    b2b_tagged =
      attribution["rows"]
      |> Enum.filter(&((&1["tokens"] || []) != [] or &1["contradicts_oc"] != nil))
      |> Enum.map(& &1["key"])

    tagged = Enum.uniq(b2b_tagged ++ Map.keys(member_tags(edges_docs)))

    inherited_tokens!(edges_docs, attribution, members)

    case Crosswalk.check_population(members, tagged) do
      :ok ->
        :ok

      {:error, {:state_4_members, untagged}} ->
        Mix.raise("""
        A3 §6 STATE 4 — #{length(untagged)} members of the declared population carry neither an
        `oc:` token nor an `oc:none` one. Silence must not encode a decision, and the guard
        fails them by design:
        #{Enum.map_join(untagged, "\n", &("  " <> &1))}
        """)
    end

    %{
      "declared" => true,
      "files" => files,
      "rule" => Enum.map_join(files, "  ||  ", fn f -> "#{f["path"]}: #{f["rule"]}" end),
      "members" => members,
      "member_count" => length(members),
      "members_with_edges" => Enum.sum(Enum.map(files, & &1["members_with_edges"])),
      "members_declared_unmatched" =>
        Enum.sum(Enum.map(files, & &1["members_declared_unmatched"])),
      "checks" => checks,
      "check_count" => length(checks),
      "declared_checks" => declared_checks,
      "declared_check_count" => length(declared_checks),
      "checks_addressed_outside_the_declared_check_population" =>
        outside_the_declared_checks(checks, declared_checks, files),
      "state_4_guard" =>
        "ran over these #{length(members)} members; 0 fired. ENTAILED BY G15a AND THEREFORE " <>
          "UNABLE TO FIRE, and that is recorded rather than left to be read as evidence: the " <>
          "population is set-equal to its selector's denotation in both directions, and it is " <>
          "derived from the file's own rows, so every member has a row and every row has a tag. " <>
          "It was equally entailed in C1a, where the selector and the tagging predicate were the " <>
          "same predicate. What fires on an EMPTY crosswalk is the vacuum guard, not this. The " <>
          "completeness question that is NOT entailed is G20 — every token B2b already records " <>
          "against a member of this population is still carried by one of that member's rows.",
      "inherited_tokens_guard" =>
        "G20 ran over the #{length(members)} declared members; 0 inherited tokens unaccounted for.",
      "outside_the_population" => %{
        "state" => "not_yet_adjudicated",
        "et_cc_members" => totality["et_cc_members_outside_every_declared_population"],
        "whole_crosswalk_totality" => totality,
        "in_denominator_checks" => 173 - length(Enum.uniq(declared_checks ++ checks)),
        "why_not_173_minus_the_declared" =>
          "A check that carries an edge has been adjudicated whether or not any file DECLARES it. " <>
            "#{length(outside_checks(checks, declared_checks))} " <>
            "of the addressed checks lie outside every declared check population — the inherited " <>
            "C1a edges — and counting them as not_yet_adjudicated would be as wrong in one " <>
            "direction as counting them in bucket 2 would be in the other.",
        "why_it_is_a_third_state" =>
          "Distinct from bucket 1 ('we looked and there is no counterpart') and from A3 §6 " <>
            "state 4 ('nobody has adjudicated this member, and the guard FAILS it'). Reporting " <>
            "these as bucket 1 would assert of each something false of every one.",
        "owners" =>
          "NOBODY \u2014 and the field is KEPT saying so rather than removed, because a stated " <>
            "zero is evidence and a removed block is silence. Through C1a, C1b and C1c-i to " <>
            "C1c-iv-a this named the tickets that still owed the remainder: the client leg " <>
            "closed at C1b-iii, the server leg at C1c-iv-a, and the none_determinable class at " <>
            "C1c-iv-b (MES-121), which also built G24. With all three of B2b's leg values " <>
            "declared there is no remainder to owe, and `et_cc_members` above is not merely " <>
            "reported zero, it is REFUSED non-zero: G24 set-compares the register's ET-CC " <>
            "universe against the union of the declared populations in both directions. The " <>
            "block stays in any case because `in_denominator_checks` is still non-zero \u2014 " <>
            "the CHECK side of the crosswalk is not total and no ticket claims it is.\n\n" <>
            "THE HISTORY THIS FIELD CARRIED IS KEPT BECAUSE THE DEFECT IT RECORDS RECURRED " <>
            "THREE TIMES. A field naming its own renderer as still owing the remainder is " <>
            "CR-1's defect (MES-104); it recurred as CR-5 (MES-108) and a third time at C1c-i, " <>
            "which rendered this artefact while this field read `C1c = MES-105 \u2026 It is the " <>
            "only ticket left` and went on to say `NOT C1b-iii, which rendered this artefact` " <>
            "\u2014 self-naming and, in its second clause, false. Corrected at C1c-ii (MES-115) " <>
            "and named in its close-out rather than quietly rewritten. The sub-population " <>
            "figures an earlier wording carried are the register's to state, not this " <>
            "artefact's \u2014 this artefact holds no figure it did not derive (G21)."
      }
    }
  end

  # --- G24 — THE WHOLE-CROSSWALK TOTALITY, AS A REFUSAL ----------------------
  #
  # G22b asserts of each declared population that it is a whole LEG. Nothing
  # asserted that the legs BETWEEN them are the whole ET-CC universe, and the
  # figure that would have shown a gap was COMPUTED AND NEVER CHECKED:
  # `MapSet.size(etcc) - length(members)` sat in the artefact as
  # `outside_the_population.et_cc_members` and a reader was invited to notice it
  # was not zero. A number nobody asserts is a comment with a digit in it, and it
  # stayed non-zero from C1a to C1c-iv-a without anything going red.
  #
  # WHY IT IS NOT ENTAILED BY THE THREE G22bs, WHICH IS THE WHOLE REASON IT CAN
  # FIRE: THE ANCHORS DIFFER. G15a, G22a and G22b all evaluate selectors against
  # B2b's ATTRIBUTION register; the universe here is the `ET-CC` label in the
  # REGISTER. The two agree today — measured, 0 in either direction — and that
  # agreement is exactly what makes the entailment look total while it is not.
  # An ET-CC member the register carries and the attribution register does not is
  # denoted by no selector on either side, so every G22b passes, every G15a
  # passes, the per-file stray guard passes (it is a subset test and the extra
  # key is in no file), and only this refuses. That mutation is committed and
  # runs beside the unmutated build (`crosswalk_controls.exs g24`).
  #
  # TWO DIRECTIONS, AND ONE OF THEM IS ENTAILED — stated rather than implied.
  # The `extra` limb (homed here, not ET-CC in the register) is already refused
  # PER FILE by the stray guard in `file_population!/8`, which runs first, so on
  # this artefact it can never be the limb that fires. It is computed and named
  # in the message for symmetry, so a reader of a refusal is not left working
  # out which direction failed; it is NOT an independent check and is not
  # presented as one. The `missing` limb is what nothing else reaches.
  #
  # WHAT A GREEN HERE IS NOT: evidence that any adjudication is RIGHT. It closes
  # the SCOPE claim and nothing else — a universe every member of which was
  # adjudicated wrongly passes it exactly as firmly.
  defp whole_crosswalk_totality!(universe, members, register_path) do
    against = Crosswalk.set_compare(universe, members)

    refuse_unless(against.equal, """
    G24 — the ET-CC universe and the union of every edges file's declared population are not the
    same set. Compared by SET in BOTH directions over #{length(universe)} ET-CC rows in
    #{register_path} and #{length(members)} homed members, never by count: a member the register
    gained and one an edges file lost reconcile perfectly on a difference of zero.
      ET-CC in the register, homed by NO edges file (#{length(against.missing)}):
    #{Enum.map_join(against.missing, "\n", &("      " <> &1))}
      homed by an edges file, NOT ET-CC in the register (#{length(against.extra)}):
    #{Enum.map_join(against.extra, "\n", &("      " <> &1))}
    The FIRST direction is the one only this guard reaches, and it is the one this refusal exists
    for: a member outside every declared population is adjudicated by nobody, and every equation
    downstream reconciles over a union that never counted it. The SECOND is already refused per
    file by the ET-CC stray guard, which runs first — it is named here for symmetry of the
    message and is not an independent check.
    """)

    %{
      "guard" => "G24",
      "et_cc_members_outside_every_declared_population" => length(against.missing),
      "universe" => length(universe),
      "homed" => length(members),
      "anchor" => register_path,
      "predicate" => "rows of #{register_path} carrying `label == \"ET-CC\"`",
      "what_it_asserts" =>
        "That the union of the #{length(members)} members the edges files declare IS the " <>
          "#{length(universe)}-member ET-CC universe, compared as SETS in both directions. The " <>
          "arithmetic falls out of the comparison rather than being asserted as a sum: nothing " <>
          "here adds the per-file figures up, and a run in which they summed correctly over the " <>
          "wrong members would still refuse.",
      "why_it_is_not_entailed_by_the_leg_totality_guards" =>
        "THE ANCHORS DIFFER. G15a, G22a and G22b evaluate selectors against the ATTRIBUTION " <>
          "register (B2b); this universe is the `ET-CC` label in the REGISTER. The two are " <>
          "set-identical on this data, which is what makes the entailment look total: an ET-CC " <>
          "row the register carries and the attribution register does not is denoted by no " <>
          "selector either side, so every leg guard stays green and only this refuses. Shown " <>
          "under mutation rather than argued.",
      "what_a_green_here_is_not" =>
        "Evidence that any adjudication is RIGHT. This is a SCOPE guard: it says every ET-CC " <>
          "member has been adjudicated by somebody, not that any verdict on any axis is " <>
          "correct. A universe every member of which was adjudicated wrongly passes it exactly " <>
          "as firmly, and the residual that covers correctness is A3 §7's, which no refusal " <>
          "reaches.",
      "what_it_does_not_cover" =>
        "The CHECK side. `in_denominator_checks` beside it is still non-zero and this guard says " <>
          "nothing about it: a check universe is declared per file and two of the three files " <>
          "declare one, so the complement is answerable where it is declared and is not a " <>
          "totality claim over the 173."
    }
  end

  defp member_tags(edges_docs) do
    Enum.reduce(edges_docs, %{}, fn {_p, d}, acc ->
      (d["edges"] ++ d["declared_unmatched"])
      |> Enum.reduce(acc, fn r, a ->
        Map.update(a, r["member"]["register_key"], [r["tag"]], &[r["tag"] | &1])
      end)
    end)
  end

  # G20 — every token B2b already recorded against a member of the declared
  # population must still be carried by one of that member's rows.
  #
  # This is the limb of A3 §6's completeness question that is NOT entailed by
  # G15a. The state-4 guard above asks whether each member carries a token, and
  # under G15a it cannot fail: the population is set-equal to the selector's
  # denotation, and the file's own rows are what derive it, so every member has
  # a row and every row has a tag. (Said plainly because a green there would
  # otherwise read as evidence. It was already entailed in C1a, where the
  # selector and the tagging predicate were the same predicate — what makes an
  # EMPTY crosswalk fail is the vacuum guard, not this.)
  #
  # What CAN happen is an inherited adjudication being lost in transit: MES-104
  # moved 18 rows between files, and a row silently dropping or re-slugging its
  # tag would leave the member still edge-bearing, still counted, still
  # reconciling — and no longer saying what B2b says it says.
  defp inherited_tokens!(edges_docs, attribution, members) do
    tags = member_tags(edges_docs)
    in_population = MapSet.new(members)

    lost =
      for row <- attribution["rows"],
          MapSet.member?(in_population, row["key"]),
          token <- row["tokens"] || [],
          token not in Map.get(tags, row["key"], []),
          do: {row["key"], token}

    refuse_unless(lost == [], """
    G20 — #{length(lost)} tokens B2b records against a member of the declared population are
    carried by NO row of that member:
    #{Enum.map_join(lost, "\n", fn {k, t} -> "  #{k}\n    #{t}" end)}
    B2b (MES-82) is the prior adjudication. A row that drops or re-slugs an inherited token
    leaves the member edge-bearing, counted and reconciling, while no longer saying what the
    register says it says.
    """)
  end

  # --- G23 — every bucket-1 record names the SEARCH that found none ----------
  #
  # A bucket-1 row asserts *we looked and there is no counterpart*. That is a
  # positive claim, and without the search behind it it is a silence wearing a
  # token (A2d). The guard has one LEG-WIDE limb and one that reaches as far as
  # the evidence does, and the difference between them is stated rather than
  # smoothed over.
  #
  # G23a is leg-wide with NO exception list: every declared_unmatched row in
  # every edges file carries a non-empty `the_search_that_found_none`. It fired
  # on two rows when this ticket started — C1b-i's `CG7-static-reachability`
  # and `CG7-integer-safe-range` — and the remedy was to RUN those two searches,
  # not to except them. A guard whose exception list is precisely the rows that
  # would fail it is the defect rather than the remedy.
  #
  # G23b/c/d are the REGISTRY limbs and reach the rows that carry a
  # `search_id`. C1b-i's and C1b-ii's 26 prose searches were run and recorded
  # but never registered in a re-runnable form; registering them now would mean
  # either re-running 26 searches this ticket did not run, or writing a
  # `hits: 0` nobody re-measured — the invented-field defect C1b-i refused. So
  # the reach is stated on the file and here, and is not pretended away.
  defp absence_searches!(edges_docs) do
    rows =
      Enum.flat_map(edges_docs, fn {path, d} ->
        Enum.map(d["declared_unmatched"], &{path, &1})
      end)

    searchless =
      Enum.reject(rows, fn {_p, r} ->
        is_binary(r["the_search_that_found_none"]) and r["the_search_that_found_none"] != ""
      end)

    refuse_unless(searchless == [], """
    G23a — #{length(searchless)} declared-unmatched rows record NO search:
    #{Enum.map_join(searchless, "\n", fn {p, r} -> "  #{p}\n    #{r["tag"]}" end)}
    A bucket-1 row asserts `we looked and there is no counterpart`. With no search behind it
    that is a silence wearing a token (A2d), and it reads identically to a search that found
    none. This limb is LEG-WIDE and carries no exception list, deliberately: a guard excepting
    exactly the rows that would fail it is the defect, not the remedy.
    """)

    registries =
      Map.new(edges_docs, fn {path, d} ->
        {path, Map.new(d["absence_searches"] || [], &{&1["id"], &1})}
      end)

    problems = Enum.flat_map(rows, &registry_problems(&1, registries))

    refuse_unless(problems == [], """
    G23b — #{length(problems)} declared-unmatched rows name a registry entry that does not hold up:
    #{Enum.map_join(problems, "\n", &("  " <> inspect(&1)))}
    An entry must record `hits: 0` (an entry IS a search that found none), a population, a
    runnable pattern, a near miss, and at least one positive control showing the sweep reached
    the population. A zero whose sweep is not shown to have run is not a measurement.
    """)

    named =
      rows
      |> Enum.flat_map(fn {p, r} -> if r["search_id"], do: [{p, r["search_id"]}], else: [] end)
      |> MapSet.new()

    orphans =
      for {path, reg} <- registries,
          {id, _e} <- reg,
          not MapSet.member?(named, {path, id}),
          do: {path, id}

    refuse_unless(orphans == [], """
    G23c — #{length(orphans)} registry entries are named by no row:
    #{Enum.map_join(orphans, "\n", fn {p, i} -> "  #{p}: #{i}" end)}
    A search nobody's record rests on is a measurement in search of a claim. Either a row was
    dropped and its zero went with it, or the entry was written for a claim that never landed.
    """)

    %{
      "entries" => Enum.sum(Enum.map(registries, fn {_p, r} -> map_size(r) end)),
      "rows_checked" => length(rows),
      "rows_naming_a_registered_search" =>
        Enum.count(rows, fn {_p, r} -> r["search_id"] != nil end),
      "distinct_searches_those_rows_name" => MapSet.size(named),
      "leg_wide_limb" =>
        "G23a ran over ALL #{length(rows)} declared-unmatched rows in this run, with no " <>
          "exception list, and requires a non-empty `the_search_that_found_none` on each.",
      "registry_limb_reach" =>
        "G23b/c/d reach the rows carrying a `search_id`. The rows without one carry a PROSE " <>
          "search that was run and recorded but not registered in a re-runnable form; " <>
          "back-filling a registry entry for a search this run did not re-measure would be " <>
          "inventing the measurement, which is the defect the field exists to prevent. Stated " <>
          "as a bound, not papered over.",
      "what_a_green_here_is_not" =>
        "Evidence that any search was well-chosen. G23 checks that a search is NAMED, RUNNABLE " <>
          "and REACHED its population. Whether the population was the right one to look in, and " <>
          "whether the member's claim is really what the search looked for, are judgements — " <>
          "they are carried on the row in `why_this_search_is_this_claims_search` so a reader " <>
          "can disagree with them, and no refusal can reach them."
    }
  end

  defp registry_problems({path, row}, registries) do
    case row["search_id"] do
      nil ->
        []

      id ->
        case get_in(registries, [path, id]) do
          nil ->
            [{:search_id_resolves_to_nothing, path, row["tag"], id}]

          entry ->
            Enum.map(
              Crosswalk.absence_entry_problems(row["tag"], id, entry, row),
              &Tuple.insert_at(&1, 1, path)
            )
        end
    end
  end

  # --- G30 — every quoted byte-string is verbatim at an address it names ------
  #
  # Ruling 7 is "an address AND the bytes at it". Every sweep before this one
  # established the address half; MES-108 and MES-109 ran the byte half by hand
  # over their OWN rows, each caught defects a careful read had passed, and each
  # said in terms that the general guard was MES-112's. This is it, INSIDE the
  # generator, where a bad citation cannot be committed because the artefact
  # cannot be regenerated over it.
  #
  # THE RECORD POPULATION IS READ OFF THE FILE'S SHAPE, not off a list of
  # collection names kept here. Every top-level list of objects is a record
  # collection, so a collection added by a later ticket is inside the guard
  # without anyone remembering to add it — the same reasoning G21 uses for its
  # universe. A record carrying no `evidence` is VISITED and contributes
  # nothing, and the two counts are reported side by side so the gap between
  # them is on the face of the artefact rather than in this comment.
  #
  # THE WINDOWS ARE THE INSTRUMENT. ET is the cited line span in the repo; OC is
  # the byte spans the axis row FOR THIS EDGE'S TAG addresses — not "somewhere
  # in 800KB", because a quote only findable by searching the whole build is a
  # quote with no address, which is the thing ruling 7 forbids. Each span is its
  # OWN window, so a quote cannot be contiguous across two of them.
  #
  # WITHOUT `--harness` the OC spans cannot be read, and a quote the ET window
  # does not place is then UNDETERMINABLE rather than wrong. That is a refusal,
  # not a pass: MES-56's rule is that a silent skip reads absence as
  # satisfaction. It costs nothing in practice — the committed artefact's own
  # generation line passes `--harness`.
  defp citation_verbatim!(edges_docs, axis_rows, harness_path) do
    build = if harness_path, do: File.read!(harness_path)
    squashed_build = if build, do: CitationVerbatim.squash(build)
    records = Enum.flat_map(edges_docs, fn {path, doc} -> records_of(path, doc) end)

    ctx = %{axes: axis_rows, build: build, squashed_build: squashed_build}
    result = CitationVerbatim.audit(records, &Crosswalk.citation_windows(&1, ctx))

    refuse_unless(result["defects"] == [], """
    G30 — #{length(result["defects"])} quoted byte-string(s) in `evidence` are not verbatim at an
    address the evidence names. Ruling 7 is an address AND the bytes at it, and every one of these
    has the address without the bytes:
    #{Enum.map_join(result["defects"], "\n", &("      " <> defect_line(&1)))}
      The remedies, and there is no fourth: RE-ADDRESS it (the bytes are right and the line is
      wrong), RE-LIFT it (write the bytes that are actually there), or DE-QUOTE it (a described
      shape or an absent token is not a lift, so it does not wear backticks). An elision is
      refused outright — fragment-matching `A … B` is the composed-quote hole re-opened.
    """)

    citation_verbatim_report(result)
  end

  # Every top-level list of objects, in the order the file writes them.
  defp records_of(path, doc) do
    for {key, value} <- doc,
        is_list(value),
        Enum.all?(value, &is_map/1),
        value != [],
        record <- value,
        do: Map.merge(record, %{"__file" => Path.basename(path), "__collection" => key})
  end

  defp defect_line(d) do
    "#{d["kind"]} — #{inspect(d["detail"])}\n        in: #{d["row"]}" <>
      "\n        windows: #{Enum.join(d["windows_addressed"], ", ")}" <>
      case d["windows_unavailable"] do
        [] -> ""
        why -> "\n        UNAVAILABLE: #{Enum.join(why, "; ")}"
      end
  end

  # Every figure here is interpolated from the audit, and the prose deliberately
  # counts RECORDS and QUOTES rather than members or checks: G21's scan reads
  # digits followed by `member(s)`/`check(s)`, and a block that is not part of
  # the population vocabulary cannot be mistaken for a population claim.
  defp citation_verbatim_report(result) do
    # `matched_in` names every window that placed a quote, which is a hundred
    # keys that move whenever a cited line moves. The artefact carries the
    # SUMMARY — derived from that map, never counted twice — and the controls
    # take the full map from `audit/3`, where it is worth having.
    by_side =
      result["matched_in"]
      |> Enum.group_by(fn {label, _} -> label |> String.split(":") |> hd() end, &elem(&1, 1))
      |> Map.new(fn {side, counts} -> {side, Enum.sum(counts)} end)

    result
    |> Map.delete("matched_in")
    |> Map.merge(%{
      "guard" => "G30",
      "quotes_placed_by_window_kind" => by_side,
      "distinct_windows_that_placed_a_quote" => map_size(result["matched_in"]),
      "what_was_checked" =>
        "Every SOURCE-SHAPED backtick span in `evidence` — one carrying `=`, `(`, `[`, `!==` " <>
          "or `===` — occurs VERBATIM and CONTIGUOUS, modulo runs of whitespace, inside a " <>
          "window the evidence itself ADDRESSES: the cited `file.exs:N[-M]` span in the repo, " <>
          "or a byte span the axis row for this edge's tag names in the harness build. Two " <>
          "limbs: WINDOWING (the comparison is against the cited span, never the whole " <>
          "artefact) catches a right-bytes/wrong-line citation; CONTIGUITY (one squashed " <>
          "string, substring containment) catches a quote spliced from lines that are real " <>
          "and non-adjacent. A bare `:N` continuation is refused as a FORM — it has no " <>
          "syntactic referent and resolving it by proximity is guessing. An elision inside a " <>
          "source-shaped span is refused rather than fragment-matched, because matching " <>
          "`A … B`'s halves green-lights a quote whose parts sit arbitrarily far apart, which " <>
          "is the composed-quote hole this guard exists to close.",
      "reach" =>
        "`quotes_compared` equals `quotes_counted`, and that attests exactly one thing: NO " <>
          "QUOTE FAILED TO PLACE. It is NOT an independent recount, and by itself it is not " <>
          "evidence of reach. Both figures come out of ONE traversal in `audit/3` — " <>
          "`quotes_counted` is the length of the quote list that traversal built and " <>
          "`quotes_compared` counts the members of that same list which matched — so the " <>
          "equality is another spelling of `no quote-level defect`, and a sweep that read " <>
          "NOTHING satisfies it at 0 == 0, as does one reading a field that does not exist. " <>
          "What bears on reach here is the MAGNITUDE and never the equality: " <>
          "`quotes_compared` quotes placed, over `records_with_evidence` records, over " <>
          "`records_visited` visited. The independent recount — the span regex walked a " <>
          "SECOND time over the same records by code that is not `audit/3` — and the " <>
          "`counted > 0` that stops an empty population passing both live in " <>
          "`conformance/controls/citation_verbatim_controls.exs`, not in this artefact. The " <>
          "record population is every top-level list of objects in each edges file, so a " <>
          "collection a later ticket adds is inside the guard without being named here.",
      "what_it_does_not_establish" =>
        "That a quote SUPPORTS the verdict it is filed under — that is a judgement and A3 " <>
          "§7's residual, and no refusal reaches it. That a backticked PROSE phrase is " <>
          "accurate: only source-shaped spans are compared, so an inaccurate paraphrase in " <>
          "backticks passes, and the ruling's remedy is to de-quote prose rather than to " <>
          "widen the shape test until English fails it. That a quoted byte-string in a field " <>
          "OTHER than `evidence` is verbatim — the gap between `records_visited` and " <>
          "`records_with_evidence` is exactly that population, reported rather than implied."
    })
  end

  defp file_population!({path, doc}, etcc, attribution, sites, rows, axes, paths) do
    declared = doc["the_population_this_file_declares"]

    members =
      (Enum.map(doc["edges"], & &1["member"]["register_key"]) ++
         Enum.map(doc["declared_unmatched"], & &1["member"]["register_key"]))
      |> Enum.uniq()
      |> Enum.sort()

    # THE VACUUM GUARD. An artefact with no population is total over nothing,
    # and MES-97's original AC3 was satisfied PERFECTLY by exactly that
    # (S9-15 / D3). Per FILE, not only over the union: a run given one real
    # file and one empty one would otherwise pass.
    refuse_unless(members != [], """
    #{path} declares an EMPTY population. A crosswalk with no members is total over nothing:
    every check falls into bucket 2, every member into bucket 1, every set enumerates exactly,
    and the arithmetic reconciles. That is the vacuum MES-97's AC3 was satisfied by, and
    emptiness is what this guard exists to fire on (S9-15 / D3).
    """)

    strays = Enum.reject(members, &MapSet.member?(etcc, &1))

    refuse_unless(
      strays == [],
      "#{path} names members that are not ET-CC in the register:\n#{Enum.join(strays, "\n")}"
    )

    # G15a — THE EXTERNAL ANCHOR. `members` above is derived by unioning the
    # keys this very file carries, so a dropped row does not violate the
    # universe, it SHRINKS it: measured on MES-99, dropping one edge and
    # dropping one declared-unmatched member each built cleanly at 20 members,
    # with every equation and both set_compare directions still exact.
    selected = selected!(declared["selector"], attribution, paths.attribution, path)
    against_selector = Crosswalk.set_compare(selected, members)

    refuse_unless(against_selector.equal, """
    G15a — the population #{path} derives is not the set its own selector denotes.
    Compared by SET in BOTH directions, never by count: a dropped row and an added one
    reconcile perfectly on a count.
      denoted by the selector, absent from this file (#{length(against_selector.missing)}):
    #{Enum.map_join(against_selector.missing, "\n", &("      " <> &1))}
      in this file, not denoted by the selector (#{length(against_selector.extra)}):
    #{Enum.map_join(against_selector.extra, "\n", &("      " <> &1))}
    """)

    # State 3 must actually BE state 3 — declared, not merely untagged.
    bad =
      Enum.reject(doc["declared_unmatched"], fn d ->
        match?({:declared_unmatched, _}, MatchKey.guard_state(d["tag"], rows))
      end)

    refuse_unless(bad == [], """
    #{path}: #{length(bad)} declared-unmatched members do not guard-check to A3 §6 state 3:
    #{Enum.map_join(bad, "\n", &("  " <> &1["tag"]))}
    """)

    addressed = doc["edges"] |> Enum.map(& &1["tag"]) |> Enum.uniq() |> Enum.sort()

    with_edges =
      doc["edges"] |> Enum.map(& &1["member"]["register_key"]) |> Enum.uniq() |> length()

    # G15b — the four numbers the file declares about itself, against the four
    # the generator derives. Weaker than G15a and kept beside it: counts
    # agreeing is not sets agreeing, and `members_with_edges` is not a set G15a
    # compares at all.
    mismatches =
      Crosswalk.declaration_mismatches(declared, %{
        "members" => length(members),
        "members_with_edges" => with_edges,
        "members_declared_unmatched" => length(doc["declared_unmatched"]),
        "checks_addressed" => length(addressed)
      })

    refuse_unless(mismatches == [], """
    G15b — #{path}'s `the_population_this_file_declares` disagrees with what the generator derives:
    #{Enum.map_join(mismatches, "\n", fn m -> "  #{m["field"]}: declared #{inspect(m["declared"])}, derived #{inspect(m["derived"])}" end)}
    The block is the file's statement about itself. Left unchecked it is a comment.
    """)

    {declared_checks, check_block} =
      declared_checks!(
        doc["the_check_population_this_file_declares"],
        sites,
        paths,
        rows,
        axes,
        path
      )

    %{
      "path" => path,
      "rule" => declared["rule"],
      "selector" =>
        Map.put(
          declared["selector"],
          "evaluated",
          "#{length(selected)} members denoted; set-equal to the population this file derives in " <>
            "both directions (G15a). The counts block was checked field by field (G15b)."
        ),
      "members" => members,
      "member_count" => length(members),
      "members_with_edges" => with_edges,
      "members_declared_unmatched" => length(doc["declared_unmatched"]),
      "checks_addressed" => addressed,
      "declared_checks" => declared_checks,
      "check_population" => check_block,
      "leg_totality" => leg_totality!(path, doc, members, attribution, paths.attribution)
    }
  end

  # --- G22 — the LEG-TOTALITY assertion, and why it is two guards ------------
  #
  # A file may declare that its population is a whole LEG. C1b-iii is the last
  # of the three tickets that adjudicated the client leg, so the claim "these
  # are ALL the client members" lands there — and it lands as a REFUSAL, not as
  # prose. Two comparisons, and neither subsumes the other.
  #
  # G22a — THE COVER. The file records one sub-population per contributing
  # ticket, each with its own runnable selector against the same external
  # anchor. Their UNION is set-compared with the members the file derives. It
  # catches a member adjudicated but in no declared slice (who added it, and
  # under what rule?) and a slice member with no row.
  #
  # G22b — THE LEG. `all_of[{leg equals <leg>}]` is evaluated FRESH against
  # B2b and set-compared with the file's members. A client ET-CC member in
  # neither an edge nor a declared_unmatched record refuses the build.
  #
  # WHY G22b IS NOT ENTAILED BY G15a, which is the whole reason it can fire.
  # The file's top-level selector is a UNION OF TICKET SLICES, and it stays
  # that way deliberately. Simplifying it to a bare `leg equals client` would
  # make G22b ask G15a's question in G15a's words — the X7 shape, a guard as
  # empty as one nobody calls. Under the union shape one mutation separates
  # them: a B2b row with `leg=client, cg="CG9"` is not denoted by any limb of
  # the union, so G15a compares 107 denoted against 107 rows and passes, while
  # G22b compares 108 against 107 and refuses. That mutation is committed and
  # runs beside the unmutated build (`crosswalk_controls.exs totality`).
  #
  # THE BLOCK IS OPTIONAL, and its absence is a stated result rather than a
  # default — the same shape `declared_checks!/6` uses. `crosswalk-edges.json`
  # holds three server members that are NOT the server leg (C1c owns that), so
  # asserting leg-totality over them would be a false claim, not a missing one.
  # Half-declaring it — a `leg` with no sub-populations, or the reverse — is
  # refused, because that is how a claim gets made with nothing checking it.
  defp leg_totality!(path, doc, members, attribution, attribution_path) do
    case {doc["leg"], doc["the_sub_populations_this_file_records"]} do
      {nil, nil} ->
        not_asserted()

      {leg, %{"entries" => entries}} when is_binary(leg) and is_list(entries) and entries != [] ->
        assert_leg_totality!(path, leg, entries, members, attribution, attribution_path)

      {leg, block} ->
        Mix.raise("""
        G22 — #{path} half-declares a leg totality: `leg` is #{inspect(leg)} and
        `the_sub_populations_this_file_records` is #{inspect(block)}.
        Both or neither. A `leg` with no sub-populations is a claim with nothing checking it,
        and sub-populations with no `leg` is a cover over a universe nobody named.
        """)
    end
  end

  defp not_asserted do
    %{
      "declared" => false,
      "result" =>
        "NOT ASSERTED — this file declares no `leg`, so it makes no claim to hold a whole one " <>
          "and none is checked. Reported rather than passed: a file whose members are a slice " <>
          "of a leg would be claiming something false if this said `total`."
    }
  end

  defp assert_leg_totality!(path, leg, entries, members, attribution, attribution_path) do
    slices =
      Enum.map(entries, fn e ->
        {e["ticket"], selected!(e["selector"], attribution, attribution_path, path)}
      end)

    union = slices |> Enum.flat_map(fn {_t, keys} -> keys end) |> Enum.uniq() |> Enum.sort()
    cover = Crosswalk.set_compare(union, members)

    refuse_unless(cover.equal, """
    G22a — the UNION of #{path}'s declared sub-populations is not the population it derives.
    Compared by SET in both directions:
      denoted by some slice, absent from this file (#{length(cover.missing)}):
    #{Enum.map_join(cover.missing, "\n", &("      " <> &1))}
      in this file, denoted by NO slice (#{length(cover.extra)}):
    #{Enum.map_join(cover.extra, "\n", &("      " <> &1))}
    A member in no slice was adjudicated under no declared rule; a slice member with no row is
    an adjudication the file claims and does not carry.
    """)

    fresh = %{
      "source" => attribution_path,
      "rows_at" => "rows",
      "key_field" => "key",
      "all_of" => [%{"field" => "leg", "test" => "equals", "value" => leg}]
    }

    whole_leg = selected!(fresh, attribution, attribution_path, path)
    against_leg = Crosswalk.set_compare(whole_leg, members)

    refuse_unless(against_leg.equal, """
    G22b — #{path} declares `leg: #{inspect(leg)}` and is NOT total over it.
    `all_of[{leg equals #{leg}}]` was evaluated FRESH against #{attribution_path} and compared
    by SET in both directions:
      on the #{leg} leg in B2b, in NEITHER an edge nor a declared_unmatched record here
      (#{length(against_leg.missing)}):
    #{Enum.map_join(against_leg.missing, "\n", &("      " <> &1))}
      in this file, NOT on the #{leg} leg in B2b (#{length(against_leg.extra)}):
    #{Enum.map_join(against_leg.extra, "\n", &("      " <> &1))}
    This is the claim the file makes by naming a leg, and it is the one guard here that is not
    entailed by G15a — G15a asks whether the population is what the file's own UNION-shaped
    selector denotes, and this asks whether that union is the leg.
    """)

    overlap =
      slices
      |> Enum.flat_map(fn {_t, keys} -> keys end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_k, n} -> n > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    %{
      "declared" => true,
      "leg" => leg,
      "members" => length(members),
      "slices" =>
        Enum.map(slices, fn {ticket, keys} -> %{"ticket" => ticket, "denotes" => length(keys)} end),
      "cover_not_partition" => %{
        "sum_of_the_slices" => Enum.sum(Enum.map(slices, fn {_t, k} -> length(k) end)),
        "distinct" => length(union),
        "in_more_than_one_slice" => length(overlap),
        "members" => overlap,
        "why" =>
          "The slices OVERLAP, so this is a cover and not a partition and the sum above is not " <>
            "the leg. The overlap is DERIVED here rather than taken from the file's word for it: " <>
            "a member that carried a C1a token and also falls in a later ticket's CG slice keeps " <>
            "ONE home and appears in two slices, which is the one-home rule working, not failing."
      },
      "what_this_establishes" =>
        "That every ET-CC member B2b puts on the #{leg} leg has a row in this file — an edge or " <>
          "a declared_unmatched record — and that every member this file carries is on that leg. " <>
          "Both directions, by SET, against an anchor outside the file.",
      "and_what_it_does_not" =>
        "That any adjudication is RIGHT. It is a totality guard, not a correctness one: a leg " <>
          "every member of which was adjudicated wrongly passes it exactly as firmly. The " <>
          "state-4 guard over this population is still ENTAILED by G15a and still cannot fire " <>
          "(residual X7) — what G22b adds is that the population it cannot fire over is now " <>
          "provably the WHOLE leg rather than a slice somebody chose, and that scope claim is " <>
          "not entailed by anything."
    }
  end

  # A check population is OPTIONAL, and its absence is a stated result rather
  # than a default. Without one, bucket 2 is the complement of the edge-bearing
  # checks within a universe derived from those same edges — which is empty by
  # construction, and C1a's `CHECKED, AND ZERO` was exactly that vacuous truth.
  # With one, bucket 2 is answerable, and G19 below is what stops it being
  # answered cheaply.
  defp declared_checks!(nil, _sites, _paths, _rows, _axes, _path), do: {[], nil}

  defp declared_checks!(block, sites, paths, rows, axes, path) do
    selected = selected!(block["selector"], sites, paths.emitting_sites, path)

    refuse_unless(length(selected) == block["checks"], """
    G15b — #{path}'s check population declares #{inspect(block["checks"])} checks and its own
    selector denotes #{length(selected)}.
    """)

    # G19 — every DECLARED check must be axis-decomposed. This is what makes
    # "total over these checks" cost something: a bucket-2 check has to be
    # decomposed before it can be shown to have no ET counterpart, otherwise a
    # file could declare a large check population it had never looked at and
    # report the whole of it as bucket 2.
    undecomposed =
      Enum.reject(selected, fn tag ->
        match?({:matched, key} when is_map_key(axes, key), MatchKey.guard_state(tag, rows))
      end)

    refuse_unless(undecomposed == [], """
    G19 — #{length(undecomposed)} checks in #{path}'s DECLARED check population have no axis
    decomposition in A3's artefact or C1's:
    #{Enum.map_join(undecomposed, "\n", &("  " <> &1))}
    A check with no decomposition is one nobody has read. Declaring it and then reporting it in
    bucket 2 would say 'we looked and there is no ET counterpart' about a check we had not looked
    at. (A tag that does not resolve in A1's manifest at all lands here too.)
    """)

    {Enum.sort(selected),
     %{
       "rule" => block["rule"],
       "selector" =>
         Map.put(
           block["selector"],
           "evaluated",
           "#{length(selected)} checks denoted; equal to the count this file declares, and every " <>
             "one of them is axis-decomposed (G19)."
         ),
       "checks" => Enum.sort(selected)
     }}
  end

  defp overlaps!(files) do
    pairs =
      for {a, i} <- Enum.with_index(files),
          b <- Enum.drop(files, i + 1),
          shared = MapSet.intersection(MapSet.new(a["members"]), MapSet.new(b["members"])),
          not Enum.empty?(shared),
          do: {a["path"], b["path"], Enum.sort(MapSet.to_list(shared))}

    refuse_unless(pairs == [], """
    G17 — two edges files declare the SAME member. One member, one home:
    #{Enum.map_join(pairs, "\n", fn {a, b, keys} -> "  #{a}\n  #{b}\n#{Enum.map_join(keys, "\n", &("    " <> &1))}" end)}
    A member in two populations is adjudicated twice, and the two adjudications need not agree —
    the MES-24 two-censuses defect, arriving through the split this run's --edges makes possible.
    Nothing downstream would notice: the member equation, both set comparisons and the bucket
    arithmetic all reconcile over a union that quietly counts it once.
    """)
  end

  # Hoisted out of the string interpolation it used to live in: credo 1.7.16's
  # tokenizer raises `Protocol.UndefinedError ... {:in_op, ...}` on a `not in`
  # inside `#{}`, which takes gate 3 down with a stack trace rather than a
  # finding. A tool defect, not a code one — but the gate has to be runnable.
  defp outside_checks(addressed, declared), do: Enum.reject(addressed, &(&1 in declared))

  defp outside_the_declared_checks(addressed, declared, files) do
    outside = outside_checks(addressed, declared)

    %{
      "count" => length(outside),
      "checks" => outside,
      "what_this_is" =>
        "Checks an edge addresses that no file declares. They carry adjudicated edges and take NO " <>
          "part in bucket 2, because bucket 2 is a complement and these checks are not in any " <>
          "declared universe to be complemented within.",
      "why_this_is_not_refused" =>
        "An edge addresses the check its claim is about; refusing one outside the declared check " <>
          "population would force a file to declare every scenario it touches, and then bucket 2 " <>
          "would report every UNADJUDICATED sibling as having no ET counterpart. That is the " <>
          "false claim the third state exists to prevent.",
      "declared_by" =>
        Enum.map(
          files,
          &%{"path" => &1["path"], "declares_checks" => length(&1["declared_checks"])}
        )
    }
  end

  # A3's state 3 is a property of a MEMBER — the generator's own bucket-1
  # reconciliation requires a member to be edge-bearing or declared unmatched,
  # never both. A member that matches on some claims and not on others has
  # nowhere to put the unmatched ones. Recorded here and ESCALATED, and the two
  # ways of getting it wrong are refused: a record against a member that is NOT
  # edge-bearing (it should have been a declared_unmatched row), and one against
  # a member no file's population contains.
  defp claim_level!(edges_docs, cells) do
    with_edges = cells |> Enum.map(& &1["member"]["register_key"]) |> MapSet.new()

    rows =
      Enum.flat_map(edges_docs, fn {path, d} ->
        Enum.map(d["claims_without_an_edge"] || [], &Map.put(&1, "from", path))
      end)

    strays = Enum.reject(rows, &MapSet.member?(with_edges, &1["member"]["register_key"]))

    refuse_unless(strays == [], """
    #{length(strays)} claim-level unmatched records name a member that carries NO edge:
    #{Enum.map_join(strays, "\n", &("  " <> &1["member"]["register_key"]))}
    A member with no edge at all is A3 §6 state 3 whole, and belongs in `declared_unmatched` where
    bucket 1 counts it. Recording it here instead would hide it from bucket 1 and from the member
    equation both.
    """)

    %{
      "count" => length(rows),
      "what_this_is" =>
        "A claim within an EDGE-BEARING member that has no counterpart in its file's declared " <>
          "check population. A3 §6's state 3 is a property of a member, so there is no bucket for " <>
          "this and none is invented.",
      "routed_to" =>
        "the PM, per case — match-relation.md §7. Whether A3 §6 should gain a claim-level state 3 " <>
          "is a ruling, not an adjudication an edges file can make.",
      "rows" => rows
    }
  end

  defp selected!(selector, source_doc, source_path, file) do
    refuse_unless(is_map(selector), """
    G15 — a declaration block in #{file} carries no `selector`, so its `rule` is prose and its
    population is derived from the file being validated. That is circular: a dropped row shrinks
    the universe instead of violating it, and nothing goes red.
    """)

    refuse_unless(selector["source"] == source_path, """
    G15 — a selector in #{file} names #{inspect(selector["source"])} as its source, but this run
    was given #{inspect(source_path)}. An anchor is only external if it is the anchor the file
    names; silently accepting a substituted one would make the selector circular again by
    another route.
    """)

    case Crosswalk.select(selector, source_doc) do
      {:ok, keys} ->
        keys

      {:error, reason} ->
        Mix.raise("""
        G15 — the selector did not evaluate: #{inspect(reason)}
        A selector that cannot be run is prose with a JSON key. It is fail-closed on an
        unknown test, an absent rows path, a key field a row does not carry, and a source
        whose keys are not unique.
        """)
    end
  end

  defp keying!(in_denominator) do
    k = Crosswalk.keying_control(in_denominator)

    refuse_unless(
      k["by_a1s_six_field_key"] == 0,
      "A1's six-field key loses #{k["by_a1s_six_field_key"]} rows — it is not a key"
    )

    refuse_unless(
      k["by_check_id_alone"] > 0,
      "the obvious-field control did not fire: keying on check_id alone lost NOTHING, so this population cannot show the hazard and the control proves nothing"
    )

    refuse_unless(k["by_name_alone"] > 0, "keying on name alone lost nothing — same problem")

    Map.merge(k, %{
      "measure" =>
        "ROWS LOST — rows that disappear when the projection is deduplicated. A1's measure and match-relation.md §5's, so the keyings are compared in the unit those documents already use.",
      "population" => "the 173 in-denominator rows",
      "what_the_two_directions_establish" =>
        "POSITIVE: the obvious keyings DO merge rows on this population, so the hazard is real " <>
          "here and not merely quoted from A1. NEGATIVE: A1's six-field key merges none. Either " <>
          "direction alone is vacuous — a control that only ran the second would pass over a " <>
          "crosswalk keyed on `id`.",
      "the_row_this_leg_DEPENDS_on" =>
        "`sep-2243-client-includes-standard-headers` — NINE in-denominator client checks share that " <>
          "one `check_id`: ClientMcpMethodHeader_tools_list / _tools_call / _resources_list / " <>
          "_resources_read / _prompts_list / _prompts_get and ClientMcpNameHeader_tools_call / " <>
          "_resources_read / _prompts_get, plus the 2 SKIPPED ones, 11 rows on one id. Keying on " <>
          "`check_id` would merge nine CLIENT checks into one; A1's six-field key merges none. It is " <>
          "CG1's whole scenario, so it is a row the client leg depends on rather than an example " <>
          "quoted from A1 — and it is why the control stays on the 173: re-scoped to CG7's 29, the " <>
          "`name` and `description` limbs lose NOTHING (measured 0 of 54 on the whole client leg) and " <>
          "could not fire at all, which is the vacuity the two-direction design exists to prevent.",
      "what_the_crosswalk_is_keyed_on" =>
        "A3's token for the address and A1's six-field key for the join. The token carries five " <>
          "fields; `description` cannot live in a test name, so reversibility is THROUGH A1's " <>
          "manifest, not lexical."
    })
  end

  defp verdict_mapping(cells) do
    %{
      "rule" => "SUCCESS -> :green. FAILURE -> :red. WARNING -> :green carrying warning: true.",
      "warning_basis" =>
        "PM-ratified D2, measured not chosen: WARNING is leg-dependent — the client-leg reducer " <>
          "fails it, `requirements_exit` and the server-leg reducer ignore it — and BOTH " <>
          "in-denominator WARNING checks are on the server leg, where the reducer that would " <>
          "disagree does not apply.",
      "warning_residual" =>
        "A future CLIENT-leg WARNING needs its own ruling. The mapping must not be extended to " <>
          "cover one silently.",
      "warning_rows_in_this_population" => Enum.count(cells, & &1["verdicts"]["oc_warning"]),
      "warning_live_data" => warning_live_data(cells),
      "observed_statuses" =>
        Enum.frequencies_by(cells, & &1["verdicts"]["oc_status_at_accepted_run"])
    }
  end

  # `warning_is_untested_by_live_data_here` was a LITERAL that said the mapping
  # fires on zero rows and is unit-tested rather than demonstrated. It was true
  # for four tickets and stopped being true at MES-115, which declared the
  # `input-required-result-*` family and with it `IgnoreUnexpectedParams` — one
  # of the suite's only two in-denominator WARNING checks. A field asserting "no
  # live instance" over a population that has one is the stale-banner defect
  # (S9's generated-artefact-banner finding), so it is DERIVED from the same
  # count the field above reports rather than re-typed.
  #
  # Three states, and the middle one is the one a literal could not express: the
  # check may be outside the declared population altogether, or declared and
  # carrying no edge (so still not exercised, but for a different reason), or
  # actually reached by an edge.
  defp warning_live_data(cells) do
    n = Enum.count(cells, & &1["verdicts"]["oc_warning"])

    case n do
      0 ->
        "NOT EXERCISED. The mapping fires on ZERO cells of this run's population. It is " <>
          "implemented and unit-tested (test/conformance/crosswalk_test.exs) rather than " <>
          "demonstrated, and that is said here because a rule with no live instance reads as " <>
          "exercised when it is not."

      _ ->
        "EXERCISED on #{n} cell(s) of this run's population — the mapping fires on real data " <>
          "and is no longer unit-tested only. WHAT THAT DOES NOT ESTABLISH: that it is RIGHT. " <>
          "A mapping that labelled every non-red check `warning` would fire here exactly as " <>
          "readily, so `exercised` and `correct` are different claims and only the first is " <>
          "made by this count. The second is the business of " <>
          "`conformance/controls/crosswalk_falsification_controls.exs warning_mapping`, which " <>
          "requires the real WARNING cell to land where the mapping sends it AND requires it " <>
          "to move OUT when the OC verdict is mutated away from WARNING."
    end
  end

  # Buckets 1 and 2 go THROUGH `Crosswalk.project/2` rather than being recomputed
  # here. That is the point of the function: it refuses a complement with no
  # universe, and a refusal on a path the generator does not take protects
  # nothing.
  defp buckets!(cells, population) do
    bucketed = Enum.reject(cells, &is_nil(&1["bucket"]))

    members_with_edges = cells |> Enum.map(& &1["member"]["register_key"]) |> Enum.uniq()
    checks_with_edges = cells |> Enum.map(& &1["tag"]) |> Enum.uniq()

    bucket_1 = project!(:bucket_1, population["members"], members_with_edges)
    bucket_2 = bucket_2(population["declared_checks"], checks_with_edges)

    refuse_unless(
      length(bucket_1) == population["members_declared_unmatched"],
      "bucket 1 projected #{length(bucket_1)} members but #{population["members_declared_unmatched"]} are declared unmatched — " <>
        "the complement and the declaration disagree, and one of them is wrong"
    )

    %{
      "from_edges" => Enum.frequencies_by(bucketed, & &1["bucket"]),
      "bucket_5_partial_sub_count" =>
        Enum.count(bucketed, &("partial" in &1["bucket_attributes"])),
      "bucket_1" => %{
        "count" => length(bucket_1),
        "members" => bucket_1,
        "rule" => "an ET-CC member of the declared population with NO edge — A3 §6 state 3",
        "universe" => "the #{population["member_count"]} declared members, never all 281"
      },
      "bucket_2" => bucket_2_block(bucket_2, population),
      "empty_by_construction" => %{
        "bucket_3" => "green OC / red ET — 0",
        "bucket_6" => "red in both — 0",
        "predicate_that_returned_zero" =>
          "Every ET-CC member of this population has et_verdict green: re-measured at 42e6b19 " <>
            "over the full suite, all 281 ET-CC members pass, 0 absent from the run. Buckets 3 " <>
            "and 6 both require a RED ET verdict, so both are empty BY CONSTRUCTION on this data " <>
            "— checked and zero, with the predicate recorded rather than left as a silence (A2d).",
        "what_would_change_it" =>
          "An ET-CC member that fails. Not reachable while gate 5 is green."
      },
      "bucket_0" => %{
        "count" => 2,
        "owner" => "A5 = MES-70, docs/conformance/bucket-0-2026-07-28.json",
        "note" =>
          "Removed from the denominator BEFORE the join. The crosswalk is built against 173, not 175. Cited, not recomputed."
      }
    }
  end

  # Bucket 2 goes through `Crosswalk.project/2` like bucket 1, and its refusal
  # of a complement with no universe is REPORTED rather than raised: a run over
  # files that declare no check population has no bucket-2 question to answer,
  # and saying so is not the same as answering it zero. C1a answered it zero.
  defp bucket_2(declared_checks, with_edges) do
    case Crosswalk.project(:bucket_2, %{population: declared_checks, with_edges: with_edges}) do
      {:ok, rows} -> {:declared, rows}
      {:error, :empty_population} -> :no_declared_universe
      {:error, reason} -> Mix.raise("bucket 2 could not be projected: #{inspect(reason)}")
    end
  end

  defp bucket_2_block(:no_declared_universe, _population) do
    %{
      "declared" => false,
      "result" =>
        "NOT REPORTED — no edges file declares a check population, so bucket 2 has no universe. " <>
          "`Crosswalk.project/2` refuses a complement without one and that refusal is what this is.",
      "why_a_zero_here_would_be_a_lie" =>
        "C1a derived its check universe from the tags its OWN edges carried, so the complement " <>
          "was empty BY CONSTRUCTION and its `CHECKED, AND ZERO` could not have said anything " <>
          "else. A file that wants a bucket-2 answer declares its checks from outside itself."
    }
  end

  defp bucket_2_block({:declared, rows}, population) do
    n = population["declared_check_count"]

    %{
      "declared" => true,
      "count" => length(rows),
      "checks" => rows,
      "rule" => "a check in a DECLARED check population that carries no edge",
      "result" =>
        if(rows == [],
          do: "CHECKED, AND ZERO — all #{n} declared checks carry at least one edge",
          else:
            "#{length(rows)} of the #{n} declared checks carry no edge from any ET-CC member of " <>
              "the declared member population"
        ),
      "universe" => "the #{n} declared checks, never all 173",
      "why_not_the_rest_of_the_173" =>
        "The in-denominator checks outside every declared check population are NOT bucket 2. " <>
          "Bucket 2 is 'we adjudicated and found no ET counterpart'; those were not adjudicated."
    }
  end

  defp project!(which, universe, with_edges) do
    case Crosswalk.project(which, %{population: universe, with_edges: with_edges}) do
      {:ok, rows} ->
        rows

      {:error, reason} ->
        Mix.raise("""
        #{which} could not be projected: #{inspect(reason)}.
        Both buckets are COMPLEMENTS over the edge set, and a complement is not a fact
        about the world without a universe to take it in.
        """)
    end
  end

  defp escalations(cells) do
    esc = Enum.reject(cells, &is_nil(&1["escalation"]))

    %{
      "count" => length(esc),
      "routed_to" =>
        "the PM, per case — match-relation.md §7. An escalation is NOT a bucket and is never counted as one.",
      "rows" =>
        Enum.map(esc, fn c ->
          %{
            "member" => c["member"]["module"] <> " / " <> c["member"]["test"],
            "claim" => c["claim"],
            "tag" => c["tag"],
            "shape" => c["shape"],
            "escalation" => c["escalation"]
          }
        end)
    }
  end

  defp totality(cells, population, edges_docs) do
    edge_members = cells |> Enum.map(& &1["member"]["register_key"]) |> Enum.uniq()
    edge_checks = cells |> Enum.map(& &1["tag"]) |> Enum.uniq()

    unmatched =
      Enum.flat_map(edges_docs, fn {_p, d} ->
        Enum.map(d["declared_unmatched"], & &1["member"]["register_key"])
      end)

    members = Crosswalk.set_compare(population["members"], edge_members ++ unmatched)
    declared = population["declared_checks"]

    %{
      "measure" =>
        "SET COMPARISON, not arithmetic — two counts agreeing is not two sets agreeing.",
      "every_declared_member_appears" => %{
        "equal" => members.equal,
        "missing" => members.missing,
        "extra" => members.extra
      },
      "every_declared_check_is_decomposed_and_accounted_for" => %{
        "declared" => length(declared),
        "with_an_edge" => Enum.count(declared, &(&1 in edge_checks)),
        "in_bucket_2" => Enum.count(declared, &(&1 not in edge_checks)),
        "equation" => "declared checks = checks with an edge + bucket 2",
        "why_this_is_not_a_set_equality" =>
          "C1a asserted `every declared check appears` as a set equality, and it held " <>
            "TRIVIALLY: the declared set was derived from the tags the edges carried, so the two " <>
            "sides were the same list twice. Once the checks are declared from outside the file " <>
            "the equality is no longer expected — the checks that do NOT appear are bucket 2, " <>
            "which is the answer rather than a failure."
      },
      "negatives_are_enumerated_not_counted" =>
        "Bucket 1's members and bucket 2's checks are listed by name in `buckets`, and the " <>
          "not_yet_adjudicated remainder is counted with its owner named (A2d / ruling 4)."
    }
  end

  defp arithmetic(cells, population) do
    bucketed = Enum.count(cells, &(not is_nil(&1["bucket"])))
    escalated = Enum.count(cells, &(not is_nil(&1["escalation"])))

    %{
      "edges" => length(cells),
      "bucketed" => bucketed,
      "escalated" => escalated,
      "equation" => "edges = bucketed + escalated",
      "members_equation" =>
        "population members = members with >=1 edge + members declared unmatched",
      "members" => population["member_count"],
      "members_with_edges" => population["members_with_edges"],
      "members_declared_unmatched" => population["members_declared_unmatched"]
    }
  end

  # --- the population figures, and G21 over every statement that states one ---
  #
  # Every figure the prose below states is bound HERE, from the run's own
  # derivation, and G21 refuses a figure that is not. What made that necessary
  # is CR-5 on MES-108: `trust_status` was a literal `48-member /
  # 29-declared-check`, MES-104 moved the population to 48/29 and MES-108 to
  # 68/39, and the sentence never moved — while the twelve bucket views
  # projected from this file interpolated the right pair, because CR-1 fixed the
  # PROJECTOR and nothing reached the generator.
  defp figures(population, cells, buckets, claim_level, absence, in_denominator, manifest_total) do
    outside = population["outside_the_population"]
    addressed = cells |> Enum.map(& &1["tag"]) |> Enum.uniq()
    legs = Enum.filter(population["files"], &get_in(&1, ["leg_totality", "declared"]))

    %{
      declared_members: population["member_count"],
      declared_checks: population["declared_check_count"],
      members_with_edges: population["members_with_edges"],
      members_declared_unmatched: population["members_declared_unmatched"],
      outside_members: outside["et_cc_members"],
      outside_checks: outside["in_denominator_checks"],
      total_members: population["member_count"] + outside["et_cc_members"],
      addressed_checks: length(addressed),
      addressed_not_declared: length(addressed -- population["declared_checks"]),
      in_denominator_checks: in_denominator,
      manifest_checks: manifest_total,
      bucket_1: buckets["bucket_1"]["count"],
      bucket_2: get_in(buckets, ["bucket_2", "count"]),
      edges: length(cells),
      escalated: Enum.count(cells, &(not is_nil(&1["escalation"]))),
      claim_level_unmatched: claim_level["count"],
      absence_entries: absence["entries"],
      absence_rows: absence["rows_checked"],
      absence_rows_registered: absence["rows_naming_a_registered_search"],
      per_file_members:
        Enum.map(population["files"], &{Path.basename(&1["path"]), &1["member_count"]}),
      # ADDED BY MES-105 (C1c-i), and it is a HOLE BEING CLOSED rather than a
      # figure being added. Each file's `check_population.selector.evaluated` is
      # generator prose stating `N checks denoted` — derived by this run, from
      # `length(selected)` — yet the held set carried only the UNION
      # (`declared_checks`) and the per-file MEMBER counts, never the per-file
      # CHECK counts. G21 therefore refused a figure the run had just computed,
      # whenever that figure did not coincide with some other held one.
      #
      # It went unnoticed while one file declared checks: the client file's 54
      # happened to equal `addressed_checks`, and the server file's 30 happened
      # to equal `bucket_2`. Both coincidences broke on the same mutated build
      # in `crosswalk_controls.exs composition` — one dropped edge moved
      # `addressed_checks` to 53 and `bucket_2` to 31, and two correct,
      # freshly-derived sentences went red at once. The remedy is to hold what
      # the generator states, not to stop stating it.
      per_file_declared_checks:
        Enum.map(population["files"], fn f ->
          {Path.basename(f["path"]), length(get_in(f, ["check_population", "checks"]) || [])}
        end),
      # A leg this run asserts TOTALITY over, and the shape of the cover that
      # reaches it. Derived from the files' own `leg_totality` blocks, so a run
      # over files that assert no leg holds no such figure and any prose stating
      # one goes red at G21 — which is the behaviour wanted: the sentence about
      # a closed leg must not survive a run that closed none.
      legs_asserted_total: length(legs),
      leg_members:
        Enum.map(
          legs,
          &{get_in(&1, ["leg_totality", "leg"]), get_in(&1, ["leg_totality", "members"])}
        ),
      leg_slices:
        Enum.map(
          legs,
          &{get_in(&1, ["leg_totality", "leg"]), length(get_in(&1, ["leg_totality", "slices"]))}
        ),
      leg_overlap:
        Enum.map(
          legs,
          &{get_in(&1, ["leg_totality", "leg"]),
           get_in(&1, ["leg_totality", "cover_not_partition", "in_more_than_one_slice"])}
        )
    }
  end

  # The figures the crosswalk HOLDS, as a set, for G21's against-the-tree limb.
  #
  # ZERO IS NOT EXCLUDED, and that was measured rather than reasoned. Excluding
  # it looked right — admitting a zero licenses every "0 checks" sentence in that
  # run, and a false zero is the strongest wrong claim these artefacts can make.
  # But a run over files that declare NO check population derives zero honestly,
  # and the `composition` control drives exactly that: the guard refused a
  # perfectly good crosswalk for stating a figure it had itself derived. A
  # derived zero is true; the set is for figures the run did NOT derive, and
  # where no figure is zero, zero is refused like any other.
  defp held_figures(f) do
    f
    |> Map.values()
    |> Enum.flat_map(fn
      n when is_integer(n) -> [n]
      l when is_list(l) -> Enum.map(l, fn {_name, n} -> n end)
      _ -> []
    end)
    |> MapSet.new()
  end

  # The phrases the load-bearing statements must contain, built from `figures`
  # and NOT from the templates that rendered them. Two independently authored
  # statements of one figure, pinned against each other — a consistency pin
  # (ruling 9). It catches an interpolation of the WRONG held figure, which the
  # against-the-tree limb cannot see.
  #
  # A residual's path is resolved through its `id`, so re-ordering the list
  # cannot silently drop a pin: an id that is not there yields a path that is
  # not there, and an absent statement is a missing phrase.
  defp required_phrases(artefact, f) do
    at = fn id ->
      "residuals.[#{Enum.find_index(artefact["residuals"], &(&1["id"] == id))}].text"
    end

    # X10 IS NOT UNIQUE BY ID, and `at/1` cannot address it. One X10 is emitted
    # per ASSERTED LEG, so the moment a second leg closes there are two rows
    # carrying that id and `Enum.find_index/2` returns the first for both —
    # pinning BOTH legs' phrases onto ONE leg's sentence. Measured at MES-117,
    # the run that closed the server leg: the server's `all 145 of them` was
    # required of the CLIENT's X10 text and the build refused a correct
    # artefact. The false RED is the harmless half. The hazard is the other
    # one: where two legs happen to share a member count and an overlap, both
    # pins pass against the first row and the second leg's sentence is pinned
    # by NOTHING — a figure free to be wrong with nothing comparing it. So the
    # address is the pair, and `leg` is carried on the row for the purpose.
    at_leg = fn id, leg ->
      i = Enum.find_index(artefact["residuals"], &(&1["id"] == id and &1["leg"] == leg))
      "residuals.[#{i}].text"
    end

    [
      {"trust_status",
       "#{f.declared_members}-member / #{f.declared_checks}-declared-check slice"},
      {at.("X5"), "member population is #{f.declared_members} across"},
      {at.("X9"), "#{f.claim_level_unmatched} of them"},
      {"buckets.bucket_1.universe", "the #{f.declared_members} declared members"},
      {"population.state_4_guard", "these #{f.declared_members} members"}
    ] ++ bucket_2_phrase(at, f) ++ leg_phrase(at_leg, f)
  end

  # Pinned only where a leg was ASSERTED, for the same reason bucket 2's pin is
  # conditional: a run over files that close no leg must not be made to state a
  # figure it does not hold. X10 is not in `residuals` at all on such a run, so
  # `at.("X10")` would resolve to a path that is not there — and an absent
  # statement IS a missing phrase, which would fire the pin over a run that was
  # right. The condition is what keeps the pin honest, not what weakens it.
  defp leg_phrase(_at_leg, %{legs_asserted_total: 0}), do: []

  defp leg_phrase(at_leg, f) do
    overlaps = Map.new(f.leg_overlap)

    Enum.flat_map(f.leg_members, fn {leg, n} ->
      [
        {at_leg.("X10", leg), "all #{n} of them"},
        {at_leg.("X10", leg), "#{Map.fetch!(overlaps, leg)} members sit in two"}
      ]
    end)
  end

  # Pinned only where bucket 2 was ASKED. A pin over a run that declares no
  # check population would require the artefact to state an answer it does not
  # have, which is the failure the pin exists to prevent, inverted.
  defp bucket_2_phrase(_at, %{bucket_2: nil}), do: []

  defp bucket_2_phrase(at, f),
    do: [{at.("X8"), "#{f.bucket_2} of the #{f.declared_checks} declared checks"}]

  # G21. Three limbs, in the order of what they can determine: nothing scanned,
  # a figure the run did not derive, a held figure in the wrong place.
  defp population_statement!(artefact, f, input_strings) do
    statements = Crosswalk.authored_statements(artefact, input_strings)
    held = held_figures(f)

    # L1 — fail-closed on the vacuum. A scan that reached nothing reports
    # exactly the green of a scan that found nothing wrong (S9-15's shape), and
    # the authorship anchor is a set difference, so a change to how the inputs
    # are read could empty it silently.
    refuse_unless(statements != [], """
    G21 — the population-statement scan found NOTHING to read. Every string this generator
    emits was matched to an input document, or none carries a population figure at all.
    Either way the guard below would pass over an artefact it never examined, and a green
    from an unrun scan is indistinguishable from a green from a clean one.
    """)

    unheld = Crosswalk.unheld_figures(statements, held)

    refuse_unless(unheld == [], """
    G21 — #{length(unheld)} population figure(s) in this generator's OWN prose are not figures
    this run derived. That is CR-5 on MES-108: `trust_status` said `48-member /
    29-declared-check` while the artefact's own arithmetic said 68 and 39, because the figures
    were literals and the population moved twice underneath them. Interpolate each from
    `figures/1`, or drop the claim — a fresh literal is the same defect one ticket later:
    #{Enum.map_join(unheld, "\n", fn {path, n, phrase} -> "      #{path}: #{n} — in #{inspect(phrase)}" end)}
      the figures this run holds: #{held |> MapSet.to_list() |> Enum.sort() |> Enum.join(", ")}
    """)

    missing = Crosswalk.missing_phrases(artefact, required_phrases(artefact, f))

    refuse_unless(missing == [], """
    G21 — #{length(missing)} statement(s) do not state the figure this run holds. The phrase is
    built from the run's figures independently of the text that rendered it, so this fires on an
    interpolation of the WRONG held figure — which the against-the-tree limb cannot see, because
    a wrong HELD figure is still a held figure:
    #{Enum.map_join(missing, "\n", fn {path, phrase} -> "      #{path}: expected to contain #{inspect(phrase)}" end)}
    """)

    report =
      "G21 — every population figure this generator's own prose states is one this run " <>
        "derived. Scanned #{length(statements)} authored statements against the " <>
        "#{MapSet.size(held)} distinct figures the run holds, and pinned " <>
        "#{length(required_phrases(artefact, f))} load-bearing phrases built from those figures " <>
        "independently of the text. THE UNIVERSE IS THE EMITTED ARTEFACT, not a list this " <>
        "module declares: a string is this generator's own iff it occurs in no input document, " <>
        "so a statement added later is inside the guard without anyone remembering to add it. " <>
        "This block is written AFTER the scan and is required to carry no population claim of " <>
        "its own, so it is not part of what it attests. BOUNDS: a figure spelled as a word, or " <>
        "stated without the noun it counts, is invisible to the scan — both occur here and are " <>
        "handled by interpolating them, not by the scan; a literal that coincides with some " <>
        "other held figure survives until the population next moves, which is when CR-5's " <>
        "recurrence would land anyway; and prose this generator does not EMIT (the moduledoc, a " <>
        "branch not taken) is outside the universe by construction."

    refuse_unless(
      Crosswalk.population_claims(report) == [],
      "G21's own report states a population figure, so the block would be part of what it attests"
    )

    report
  end

  defp residuals(f) do
    leg_residual(f) ++
      [
        %{
          "id" => "X1",
          "text" =>
            "Axis verdicts are JUDGEMENTS. Whether a claim really agrees with a conjunct is A3 §7's semantic-sameness residual and escalates per case; nothing here decides it."
        },
        %{
          "id" => "X2",
          "text" =>
            "FALSIFICATION-TESTED by C3 (MES-99) and STANDING — the attempts were made and none " <>
              "succeeded, which is not the same as proven. The bound is narrow. The generator now refuses a " <>
              "duplicated join key (G14), a population that is not the set its external selector " <>
              "denotes or that disagrees with its own declared counts (G15), and a manifest whose " <>
              "verdicts have drifted from A5's bucket-0 artefact (G16). Every falsification class is " <>
              "shown firing on a mutated input with the unmutated build as the negative control in " <>
              "the same run, at the OS exit status and not only in-VM, and restored green after; " <>
              "C1a's own thirteen are re-run with the after-restoration they lacked. A per-row " <>
              "bucket-assignment drift is caught naming the row and the buckets it crosses " <>
              "(conformance/controls/crosswalk_falsification_controls.exs). What that does NOT " <>
              "establish: that any axis verdict is right (X1 is untouched — an axis verdict is a " <>
              "judgement and no refusal can reach it), and that anything outside the declared " <>
              "population was falsified at all. MES-104 added four refusals to the set C3 covers — " <>
              "G17 (two files declaring the same member), G18 (an axis row citing a provenance for " <>
              "its emitting span the locator does not support), G19 (a DECLARED check with no axis " <>
              "decomposition) and G20 (an inherited B2b token no row carries) — each shown firing on " <>
              "a mutated input with the unmutated build as the negative control in the same run. " <>
              "MES-108 added G21, which refuses a population figure in this generator's own prose " <>
              "that the run did not derive. What lies OUTSIDE the declared population is " <>
              "unfalsified, and the tickets that own it are the ones " <>
              "`population.outside_the_population.owners` names — this residual does not name " <>
              "them, because it named C1b-ii while C1b-ii was rendering it, and a statement that " <>
              "names its own producer as still owing the remainder is CR-1 (MES-104) recurring as " <>
              "CR-5 (MES-108)."
        },
        %{
          "id" => "X6",
          "text" =>
            "The second-source re-derivation (`--verdicts-from bucket-0`) is a CONSISTENCY pin, " <>
              "not a correctness one (ruling 9). A1's manifest and A5's bucket-0 artefact are " <>
              "different files, different schemas, different generators — but both descend from the " <>
              "SAME accepted harness run. Byte-identical output witnesses that nobody edited one " <>
              "without regenerating the other. A wrong run would be wrong in both, and this pin " <>
              "would agree just as firmly."
        },
        %{
          "id" => "X3",
          "text" =>
            "Axis spans address ONE build. A harness bump invalidates them, and --harness is what detects it — a run without it records `harness_checked: false` rather than a pass."
        },
        %{
          "id" => "X4",
          "text" =>
            "`no_axis_contact` is a THIRD escalation, added here by generalising A3 §2's 'covering zero of one axis is no match, not a partial one' to N axes. A3 §3's table has no row for it. Escalation rather than a new bucket is deliberate: it routes to the PM and costs nothing if the ruling goes the other way."
        },
        %{
          "id" => "X5",
          "text" =>
            "The member population is #{f.declared_members} across #{length(f.per_file_members)} " <>
              "edges files — " <>
              Enum.map_join(f.per_file_members, " and ", fn {file, n} ->
                "#{n} members from #{file}"
              end) <>
              ". Two of the checks C1a addresses enter through A3 §1's cardinality rule and §4's " <>
              "published worked edge, not through B2b's tokens — inherited, not newly adjudicated, " <>
              "and said so in the edges file. Every figure in this sentence is interpolated: all " <>
              "three were literals until MES-108, and two of the three were already wrong when " <>
              "CR-5 found them."
        },
        %{
          "id" => "X7",
          "text" =>
            "A3 §6's STATE-4 GUARD IS ENTAILED BY G15a and cannot fire. The population is set-equal to its selector's denotation in both directions and is derived from the file's own rows, so every member has a row and every row has a tag. This was already true in C1a, where the selector and the tagging predicate were literally the same predicate — so D3's claim that the state-4 guard 'is the limb that makes an EMPTY crosswalk fail' is not what happens: `check_population([], tagged)` returns `:ok`, and the vacuum guard is what fires. Recorded rather than removed, because the guard is A3 §6's ratified one and dropping it would be a silent change to a ratified rule. The completeness question that is NOT entailed is G20."
        },
        %{
          "id" => "X8",
          "text" =>
            "BUCKET 2 WAS EMPTY BY CONSTRUCTION UNTIL MES-104. C1a derived its check universe " <>
              "from the tags its own edges carried, so the complement within it was necessarily " <>
              "empty and its `CHECKED, AND ZERO` could not have said anything else. A file may now " <>
              "declare its check population from an external anchor. " <>
              bucket_2_answer(f) <>
              " A file that declares none contributes none to the universe and the " <>
              "artefact reports that bucket 2 was not asked, rather than reporting a zero. The " <>
              "answer is interpolated — this sentence froze C1b-i's at nine and went on stating it " <>
              "after MES-108 moved the check population (CR-5)."
        },
        %{
          "id" => "X9",
          "text" =>
            "A CLAIM-LEVEL STATE 3 HAS NO BUCKET. A3 §6's state 3 is a property of a MEMBER, and the bucket-1 reconciliation requires a member to be edge-bearing or declared unmatched, never both — so a member matching on some claims and not on others has nowhere to record the unmatched ones. C1b-i found five; MES-108 resolved " <>
              "two of them into real edges and found one more. This run carries " <>
              "#{f.claim_level_unmatched} of them in `claim_level_unmatched`, each with the search " <>
              "that found none, and ESCALATED — the figure interpolated, because it was written as " <>
              "a word and so would not have moved (CR-5). Whether A3 §6 should gain a claim-level " <>
              "state is the PM's."
        },
        %{
          "id" => "X11",
          "text" =>
            "THE ABSENCE-SEARCH REGISTRY DOES NOT REACH EVERY BUCKET-1 ROW, and the shortfall is " <>
              "stated rather than hidden behind a green. G23's prose limb is LEG-WIDE with no " <>
              "exception list — every declared-unmatched row in this run records the search that " <>
              "found none, and the two rows that did not when MES-109 opened were fixed by RUNNING " <>
              "their searches, not by excepting them. Its registry limb — id resolves, entry " <>
              "records a zero over a named population with a runnable pattern, positive controls " <>
              "and a near miss, no orphans, and the entry's kind equal to the row's own reason " <>
              "slug — reaches only the rows that carry a `search_id`. The rest carry a search that " <>
              "was run and recorded in prose but never registered, and registering it now would " <>
              "mean writing a zero this run did not re-measure: the invented-field defect C1b-i " <>
              "refused when it declined to backfill. C1c faces the same choice on the server leg " <>
              "and should settle it there rather than inherit it silently."
        }
      ]
  end

  # X10 exists only on a run that ASSERTS a leg, and that is the point: a
  # sentence about a closed leg must not survive a run that closed none. On such
  # a run the id is absent from `residuals`, `required_phrases/2` adds no pin for
  # it, and neither half can go stale in the other's direction.
  defp leg_residual(%{legs_asserted_total: 0}), do: []

  defp leg_residual(f) do
    overlaps = Map.new(f.leg_overlap)
    slices = Map.new(f.leg_slices)

    Enum.map(f.leg_members, fn {leg, n} ->
      %{
        "id" => "X10",
        "leg" => leg,
        "text" =>
          "THE #{String.upcase(leg)} LEG IS CLOSED, BY REFUSAL AND NOT BY ASSERTION. Every " <>
            "ET-CC member B2b puts on the #{leg} leg carries a row here — all #{n} of them — " <>
            "and a member in neither an edge nor a declared_unmatched record REFUSES THE BUILD " <>
            "(G22b), evaluated fresh against B2b and compared by set in both directions. The " <>
            "leg was reached by #{Map.fetch!(slices, leg)} ticket slices declared as a COVER " <>
            "and not a partition: #{Map.fetch!(overlaps, leg)} members sit in two slices at " <>
            "once, because a member a later ticket's CG brings in may already have carried an " <>
            "earlier ticket's token, and it keeps ONE home. The overlap is derived here, not " <>
            "taken from the file's word for it, so the slices cannot be summed into a leg that " <>
            "is not one. WHAT THIS IS NOT: a claim that any adjudication is right. A leg every " <>
            "member of which was adjudicated wrongly passes G22b exactly as firmly, and the " <>
            "state-4 guard over this population remains ENTAILED by G15a and unable to fire " <>
            "(X7) — what is new is that the population it cannot fire over is provably the " <>
            "whole leg rather than a slice somebody chose."
      }
    end)
  end

  # `nil` is not zero here: a run whose files declare no check population has no
  # bucket-2 question to answer, and rendering that as `0 of the 0` would report
  # an answer where there was none.
  defp bucket_2_answer(%{bucket_2: nil}),
    do: "No file in this run declares one, so bucket 2 is not asked."

  defp bucket_2_answer(f),
    do:
      "This run's answer is #{f.bucket_2} of the #{f.declared_checks} declared checks carrying " <>
        "no edge from any ET-CC member."

  defp trust_status(f) do
    "FALSIFICATION-TESTED by C3 (MES-99) and STANDING — over the declared " <>
      "#{f.declared_members}-member / #{f.declared_checks}-declared-check slice and no " <>
      "further. Both figures are INTERPOLATED from the population this run derives, and the " <>
      "slice is NOT decomposed by ticket here. The pair was a literal that had to be re-typed " <>
      "by hand at every move of the population: it was re-typed at MES-104, the population " <>
      "moved again at MES-108, and it was not. That is an argument against the SHAPE and not " <>
      "against an author — it is CR-1 (MES-104) recurring in " <>
      "the one generator CR-1's remedy did not reach (CR-5, MES-108). The parenthetical was " <>
      "the worse half — it enumerated the slice in a way that positively excluded the members " <>
      "the very run rendering it had just added — so it is dropped rather than re-typed: a " <>
      "fresh decomposition would be a third literal, and `population.files` carries the same " <>
      "fact derived. G21 refuses a figure here that the run did not derive. (Standing, not proven: the attempts were made " <>
      "and none succeeded. `UNFALSIFIED` here previously meant `not yet attempted`.) " <>
      "Ruling 5 asked for the control this artefact was unfalsified against: the generator " <>
      "refuses on each falsification class with the mutation committed and shown firing, a " <>
      "drifted per-row bucket assignment is caught naming the row and the buckets it crosses, " <>
      "and the artefact re-derives byte-identically from a second source path. That last is a " <>
      "CONSISTENCY pin, not a correctness claim (ruling 9, residual X6). Nothing here " <>
      "establishes that an axis verdict is RIGHT (X1), and nothing outside the declared " <>
      "population has been falsified at all — the tickets " <>
      "`population.outside_the_population.owners` names own that."
  end

  defp reconcile!(a) do
    ar = a["arithmetic"]

    refuse_unless(
      ar["edges"] == ar["bucketed"] + ar["escalated"],
      "edges != bucketed + escalated"
    )

    refuse_unless(
      ar["members"] == ar["members_with_edges"] + ar["members_declared_unmatched"],
      "the member arithmetic does not reconcile"
    )

    refuse_unless(
      a["totality"]["every_declared_member_appears"]["equal"],
      "not every declared member appears: #{inspect(a["totality"]["every_declared_member_appears"])}"
    )

    t = a["totality"]["every_declared_check_is_decomposed_and_accounted_for"]

    refuse_unless(
      t["declared"] == t["with_an_edge"] + t["in_bucket_2"],
      "the declared-check arithmetic does not reconcile: #{inspect(t)}"
    )

    refuse_unless(
      a["buckets"]["bucket_2"]["declared"] == false or
        a["buckets"]["bucket_2"]["count"] == t["in_bucket_2"],
      "bucket 2 and the declared-check arithmetic disagree about how many checks carry no edge"
    )

    refuse_unless(
      length(a["cells"]) == ar["edges"],
      "the cell count does not equal the edge count"
    )
  end

  defp report(a, out) do
    b = a["buckets"]
    p = a["population"]
    k = a["keying_control"]

    Mix.shell().info("""

    CROSSWALK — #{a["revision"]}, written to #{out}

      population        #{p["member_count"]} ET-CC members (#{p["members_with_edges"]} with edges, #{p["members_declared_unmatched"]} declared unmatched)
                        over #{length(p["files"])} edges file(s): #{Enum.map_join(p["files"], ", ", fn f -> "#{Path.basename(f["path"])} #{f["member_count"]}" end)}
                        #{p["declared_check_count"]} OC checks DECLARED, #{p["check_count"]} addressed (#{p["checks_addressed_outside_the_declared_check_population"]["count"]} outside any declared population)
                        State-4 guard: #{p["state_4_guard"]}
                        outside it: #{p["outside_the_population"]["et_cc_members"]} members / #{p["outside_the_population"]["in_denominator_checks"]} checks = not_yet_adjudicated

      edges             #{a["arithmetic"]["edges"]} = #{a["arithmetic"]["bucketed"]} bucketed + #{a["arithmetic"]["escalated"]} escalated

      buckets           #{b["from_edges"] |> Enum.sort() |> Enum.map_join(", ", fn {k2, v} -> "#{k2}: #{v}" end)}
                        bucket 5 partial sub-count: #{b["bucket_5_partial_sub_count"]}
                        bucket 1: #{b["bucket_1"]["count"]}   bucket 2: #{b["bucket_2"]["result"]}
                        buckets 3 and 6: 0, by construction — every ET verdict is green

      keying control    rows lost over the 173 — check_id #{k["by_check_id_alone"]}, name #{k["by_name_alone"]}, description #{k["by_description_alone"]},
                        check_id+name #{k["by_check_id_and_name"]}, the token's five #{k["by_the_token_five"]}, A1's six #{k["by_a1s_six_field_key"]}

      axis provenance   harness checked: #{a["axis_provenance"]["harness_checked"]}#{if a["axis_provenance"]["harness_checked"], do: " (#{a["axis_provenance"]["axes_checked"]} axes verbatim at their spans)", else: ""}
                        spans vs the locator (G18): #{a["axis_span_provenance"]["locator_row"]} accepted, #{a["axis_span_provenance"]["locator_row_rejected"]} rejected with a reason

      claim-level       #{a["claim_level_unmatched"]["count"]} claims inside edge-bearing members with no counterpart — escalated, not bucketed

      leg totality      #{leg_line(p)}

      whole crosswalk   #{g24_line(p)}

      absence searches  #{a["absence_search_guard"]["rows_checked"]} bucket-1 rows, all naming a search (G23a, leg-wide, no exceptions);
                        #{a["absence_search_guard"]["rows_naming_a_registered_search"]} of them name one of #{a["absence_search_guard"]["entries"]} registry entries re-run by the controls (G23b/c/d)

      citations         #{a["citation_verbatim_guard"]["quotes_compared"]} quoted byte-strings compared verbatim at an address their own evidence names
                        (G30, of #{a["citation_verbatim_guard"]["quotes_counted"]} counted over #{a["citation_verbatim_guard"]["records_with_evidence"]} of #{a["citation_verbatim_guard"]["records_visited"]} records).
                        ONE traversal, so the equality attests that no quote failed to place, NOT reach;
                        the independent recount and `counted > 0` are in the control. See `reach`.

      cross-source      #{a["cross_source_agreement"]["compared"]} checks compared against A5's bucket-0 artefact, #{length(a["cross_source_agreement"]["disagreements"])} disagreements (G16)

      trust             FALSIFICATION-TESTED by MES-99 (C3) and standing, over this declared slice only.
                        Ruling 5.
    """)
  end

  # G24's one line. The universe and the union are printed as two figures rather
  # than as their difference: a difference of zero is what a reader would have to
  # trust, and two equal figures with the anchor named is what they can check.
  defp g24_line(p) do
    u = p["outside_the_population"]["whole_crosswalk_totality"]

    "TOTAL at #{u["homed"]} members \u2014 the union of the declared populations set-compared " <>
      "in both directions (G24) against the #{u["universe"]} `label == \"ET-CC\"` rows of " <>
      "#{u["anchor"]}, a DIFFERENT anchor from the leg guards' B2b; " <>
      "#{u["et_cc_members_outside_every_declared_population"]} outside every declared population"
  end

  defp leg_line(p) do
    case Enum.filter(p["files"], &get_in(&1, ["leg_totality", "declared"])) do
      [] ->
        "none asserted — no edges file declares a `leg`"

      files ->
        Enum.map_join(files, "; ", fn f ->
          t = f["leg_totality"]
          c = t["cover_not_partition"]

          "#{t["leg"]} leg TOTAL at #{t["members"]} members (G22b, fresh against B2b, both directions) " <>
            "— reached by #{length(t["slices"])} slices as a COVER, #{c["in_more_than_one_slice"]} in two"
        end)
    end
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()

  defp require!(opts, key),
    do: Keyword.get(opts, key) || Mix.raise("--#{key} is required.\n#{@usage}")

  defp refuse_unless(true, _why), do: :ok
  defp refuse_unless(false, why), do: Mix.raise(why)
end
