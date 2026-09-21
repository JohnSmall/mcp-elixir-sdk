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

  That anything **outside** the declared population is adjudicated. C1b-ii and
  C1b-iii (MES-104's siblings) and C1c (MES-105) own the rest.

  ## Exit status

  `0` derived. `1` refused. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, Crosswalk, Locator, MatchKey}

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
        emitting_sites: require!(opts, :emitting_sites)
      })

    keying = keying!(in_denominator)

    artefact = %{
      "schema" => "crosswalk/1",
      "revision" => @revision,
      "generated_by" => "mix conformance.crosswalk",
      "owner" => "MES-97 (C1a) and MES-104 (C1b-i)",
      "what_this_is" =>
        "The single matrix the ten buckets are PROJECTIONS of. C2 renders it, C3 falsifies it, " <>
          "D adjudicates its cells. It decides what no bucket MEANS.",
      "trust_status" => trust_status(),
      "cross_source_agreement" => agreement,
      "population" => population,
      "keying_control" => keying,
      "axis_provenance" => axis_bytes,
      "axis_span_provenance" => span_provenance,
      "verdict_mapping" => verdict_mapping(cells),
      "buckets" => buckets!(cells, population),
      "escalations" => escalations(cells),
      "totality" => totality(cells, population, edges_docs),
      "arithmetic" => arithmetic(cells, population),
      "residuals" => residuals(),
      "cells" => cells,
      "declared_unmatched" =>
        Enum.flat_map(edges_docs, fn {_p, d} -> d["declared_unmatched"] end),
      "claim_level_unmatched" => claim_level!(edges_docs, cells)
    }

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
  defp id_errors(pool, check) do
    id = Enum.at(check["key"], 2)
    where = Map.get(check, "check_id_found_in", "evaluator_excerpt")

    case Map.fetch(pool, where) do
      :error ->
        [{:check_id_found_in_names_no_such_span, id, where}]

      {:ok, src} ->
        if String.contains?(src, id),
          do: [],
          else: [{:span_does_not_carry_the_check_id, id, where}]
    end
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
    etcc =
      register["rows"]
      |> Enum.filter(&(&1["label"] == "ET-CC"))
      |> Enum.map(& &1["key"])
      |> MapSet.new()

    sites = read_json!(paths.emitting_sites)

    files =
      Enum.map(edges_docs, &file_population!(&1, etcc, attribution, sites, rows, axes, paths))

    overlaps!(files)

    members = files |> Enum.flat_map(& &1["members"]) |> Enum.sort()

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
        "et_cc_members" => MapSet.size(etcc) - length(members),
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
          "C1b-ii and C1b-iii (MES-104's siblings — CG1/CG2/CG4 and the 55 no-CG client members); " <>
            "C1c = MES-105 (server leg + the 29 none_determinable)"
      }
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
      "check_population" => check_block
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
      "warning_is_untested_by_live_data_here" =>
        "The mapping fires on ZERO rows of C1a's population — both WARNING checks are outside " <>
          "it. It is implemented and unit-tested (test/conformance/crosswalk_test.exs) rather " <>
          "than demonstrated, and that is said here because a rule with no live instance reads " <>
          "as exercised when it is not.",
      "observed_statuses" =>
        Enum.frequencies_by(cells, & &1["verdicts"]["oc_status_at_accepted_run"])
    }
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
          "was empty BY CONSTRUCTION and `CHECKED, AND ZERO — all 14 checks carry at least one " <>
          "edge` could not have said anything else. A file that wants a bucket-2 answer declares " <>
          "its checks from outside itself."
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

  defp residuals do
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
            "C1b-ii, C1b-iii and C1c (MES-105) own the rest."
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
          "The member population is 48 across two edges files — C1b-i's 45 client members and the 3 non-client rows C1a's file was re-declared to. Two of the checks C1a addresses enter through A3 §1's cardinality rule and §4's published worked edge, not through B2b's tokens — inherited, not newly adjudicated, and said so in the edges file."
      },
      %{
        "id" => "X7",
        "text" =>
          "A3 §6's STATE-4 GUARD IS ENTAILED BY G15a and cannot fire. The population is set-equal to its selector's denotation in both directions and is derived from the file's own rows, so every member has a row and every row has a tag. This was already true in C1a, where the selector and the tagging predicate were literally the same predicate — so D3's claim that the state-4 guard 'is the limb that makes an EMPTY crosswalk fail' is not what happens: `check_population([], tagged)` returns `:ok`, and the vacuum guard is what fires. Recorded rather than removed, because the guard is A3 §6's ratified one and dropping it would be a silent change to a ratified rule. The completeness question that is NOT entailed is G20."
      },
      %{
        "id" => "X8",
        "text" =>
          "BUCKET 2 WAS EMPTY BY CONSTRUCTION UNTIL THIS TICKET. C1a derived its check universe from the tags its own edges carried, so the complement within it was necessarily empty and `CHECKED, AND ZERO — all 14 checks in the declared population carry at least one edge` could not have said anything else. A file may now declare its check population from an external anchor, and C1b-i's first non-vacuous answer is NINE: nine of CG7's 29 OC checks carry no edge from any ET-CC member. A file that declares none contributes none to the universe and the artefact reports that bucket 2 was not asked, rather than reporting a zero."
      },
      %{
        "id" => "X9",
        "text" =>
          "A CLAIM-LEVEL STATE 3 HAS NO BUCKET. A3 §6's state 3 is a property of a MEMBER, and the bucket-1 reconciliation requires a member to be edge-bearing or declared unmatched, never both — so a member matching on some claims and not on others has nowhere to record the unmatched ones. C1b-i found five. They are carried in `claim_level_unmatched` with the search that found none, and ESCALATED. Whether A3 §6 should gain a claim-level state is the PM's."
      }
    ]
  end

  defp trust_status do
    "FALSIFICATION-TESTED by C3 (MES-99) and STANDING — over the declared 48-member / " <>
      "29-declared-check slice (C1a's 21 as re-split by MES-104, plus CG7's 27 new) and no " <>
      "further. (Standing, not proven: the attempts were made and none " <>
      "succeeded. `UNFALSIFIED` here previously meant `not yet attempted`.) " <>
      "Ruling 5 asked for the control this artefact was unfalsified against: the generator " <>
      "refuses on each falsification class with the mutation committed and shown firing, a " <>
      "drifted per-row bucket assignment is caught naming the row and the buckets it crosses, " <>
      "and the artefact re-derives byte-identically from a second source path. That last is a " <>
      "CONSISTENCY pin, not a correctness claim (ruling 9, residual X6). Nothing here " <>
      "establishes that an axis verdict is RIGHT (X1), and nothing outside the declared " <>
      "population has been falsified at all — C1b (MES-104) and C1c (MES-105) own that."
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

      cross-source      #{a["cross_source_agreement"]["compared"]} checks compared against A5's bucket-0 artefact, #{length(a["cross_source_agreement"]["disagreements"])} disagreements (G16)

      trust             FALSIFICATION-TESTED by MES-99 (C3) and standing, over this declared slice only.
                        Ruling 5.
    """)
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()

  defp require!(opts, key),
    do: Keyword.get(opts, key) || Mix.raise("--#{key} is required.\n#{@usage}")

  defp refuse_unless(true, _why), do: :ok
  defp refuse_unless(false, why), do: Mix.raise(why)
end
