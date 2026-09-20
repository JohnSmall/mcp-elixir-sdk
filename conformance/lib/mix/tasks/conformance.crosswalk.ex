defmodule Mix.Tasks.Conformance.Crosswalk do
  @shortdoc "Join the adjudicated ET-CC members to the in-scope OC checks and assign the bucket"

  @moduledoc """
  Derive `docs/conformance/crosswalk-2026-07-28.json` — the matrix the ten
  buckets are projections of, over C1a's declared population.

      mix conformance.crosswalk \\
        --edges conformance/data/crosswalk-edges.json \\
        --manifest docs/conformance/in-scope-2026-07-28.json \\
        --denominator docs/conformance/bucket-0-2026-07-28.json \\
        --register docs/conformance/etcc-register.json \\
        --attribution docs/conformance/etcc-attribution.json \\
        --a3-axes docs/conformance/oc-axes-2026-07-28.json \\
        --c1-axes conformance/data/oc-axes-c1.json \\
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
    half. This is the limb that makes an EMPTY crosswalk fail: a member with no
    token is exactly what the guard fires on (S9-15 / D3).
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

  That anything **outside** the declared population is adjudicated. C1b
  (MES-104) and C1c (MES-105) own the rest.

  ## Exit status

  `0` derived. `1` refused. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, Crosswalk, Locator, MatchKey}

  @switches [
    edges: :string,
    manifest: :string,
    denominator: :string,
    register: :string,
    attribution: :string,
    a3_axes: :string,
    c1_axes: :string,
    harness: :string,
    verdicts_from: :string,
    out: :string
  ]
  @aliases [o: :out]

  @usage """
  mix conformance.crosswalk --edges FILE --manifest FILE --denominator FILE --register FILE \
  --attribution FILE --a3-axes FILE --c1-axes FILE [--harness FILE] \
  [--verdicts-from manifest|bucket-0] -o FILE\
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

    edges_doc = opts |> require!(:edges) |> read_json!()
    manifest = opts |> require!(:manifest) |> read_json!()
    denominator = opts |> require!(:denominator) |> read_json!()
    register = opts |> require!(:register) |> read_json!()
    attribution = opts |> require!(:attribution) |> read_json!()
    a3_axes = opts |> require!(:a3_axes) |> read_json!()
    c1_axes = opts |> require!(:c1_axes) |> read_json!()
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
    axis_bytes = verify_axis_bytes!(c1_axes, Keyword.get(opts, :harness))

    keys!(edges_doc)
    cells = cells!(edges_doc["edges"], rows, statuses, axes)
    population = population!(edges_doc, register, attribution, rows, require!(opts, :attribution))
    keying = keying!(in_denominator)

    artefact = %{
      "schema" => "crosswalk/1",
      "revision" => @revision,
      "generated_by" => "mix conformance.crosswalk",
      "owner" => "MES-97 (C1a)",
      "what_this_is" =>
        "The single matrix the ten buckets are PROJECTIONS of. C2 renders it, C3 falsifies it, " <>
          "D adjudicates its cells. It decides what no bucket MEANS.",
      "trust_status" => trust_status(),
      "cross_source_agreement" => agreement,
      "population" => population,
      "keying_control" => keying,
      "axis_provenance" => axis_bytes,
      "verdict_mapping" => verdict_mapping(cells),
      "buckets" => buckets!(cells, population),
      "escalations" => escalations(cells),
      "totality" => totality(cells, population, edges_doc),
      "arithmetic" => arithmetic(cells, population),
      "residuals" => residuals(),
      "cells" => cells,
      "declared_unmatched" => edges_doc["declared_unmatched"]
    }

    reconcile!(artefact)
    File.write!(out, Jason.encode!(artefact, pretty: true) <> "\n")
    report(artefact, out)
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
  defp keys!(edges_doc) do
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

    id_err =
      if String.contains?(Map.fetch!(pool, "evaluator_excerpt"), Enum.at(check["key"], 2)),
        do: [],
        else: [{:emitting_span_does_not_carry_the_check_id, Enum.at(check["key"], 2)}]

    axis_errs ++ other_errs ++ id_err
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

  defp population!(edges_doc, register, attribution, rows, attribution_path) do
    declared = edges_doc["the_population_this_file_declares"]

    members =
      (Enum.map(edges_doc["edges"], & &1["member"]["register_key"]) ++
         Enum.map(edges_doc["declared_unmatched"], & &1["member"]["register_key"]))
      |> Enum.uniq()
      |> Enum.sort()

    # THE VACUUM GUARD. An artefact with no population is total over nothing, and
    # MES-97's original AC3 was satisfied PERFECTLY by exactly that (S9-15 / D3).
    # It is refused here, on the path the task actually takes — a refusal living
    # only in a function the generator never calls is a refusal nobody makes.
    refuse_unless(members != [], """
    the declared population is EMPTY. A crosswalk with no members is total over nothing:
    every check falls into bucket 2, every member into bucket 1, every set enumerates
    exactly, and the arithmetic reconciles. That is the vacuum MES-97's AC3 was
    satisfied by, and emptiness is what this guard exists to fire on (S9-15 / D3).
    """)

    etcc =
      register["rows"]
      |> Enum.filter(&(&1["label"] == "ET-CC"))
      |> Enum.map(& &1["key"])
      |> MapSet.new()

    strays = Enum.reject(members, &MapSet.member?(etcc, &1))

    refuse_unless(
      strays == [],
      "the population names members that are not ET-CC in the register:\n#{Enum.join(strays, "\n")}"
    )

    # G15a — THE EXTERNAL ANCHOR. `members` above is derived by unioning the keys
    # this very file carries, so a dropped row does not violate the universe, it
    # SHRINKS it: measured on MES-99, dropping one edge and dropping one
    # declared-unmatched member each built cleanly at 20 members, with the edge
    # equation, the member equation and both set_compare directions still exact.
    # An artefact internally perfect while being about less than it claims.
    #
    # The fix is only a fix if the population is denoted from OUTSIDE the file
    # under validation. That is what the `selector` is: B2b's own register, the
    # rows carrying a token of either kind, evaluated here rather than described.
    selected = selected!(declared["selector"], attribution, attribution_path)

    against_selector = Crosswalk.set_compare(selected, members)

    refuse_unless(against_selector.equal, """
    G15 — the population this file derives is not the set its own selector denotes.
    Compared by SET in BOTH directions, never by count: a dropped row and an added one
    reconcile perfectly on a count.
      denoted by the selector, absent from this file (#{length(against_selector.missing)}):
    #{Enum.map_join(against_selector.missing, "\n", &("      " <> &1))}
      in this file, not denoted by the selector (#{length(against_selector.extra)}):
    #{Enum.map_join(against_selector.extra, "\n", &("      " <> &1))}
    """)

    tagged =
      attribution["rows"]
      |> Enum.filter(&((&1["tokens"] || []) != [] or &1["contradicts_oc"] != nil))
      |> Enum.map(& &1["key"])

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

    # State 3 must actually BE state 3 — declared, not merely untagged.
    bad =
      Enum.reject(edges_doc["declared_unmatched"], fn d ->
        match?({:declared_unmatched, _}, MatchKey.guard_state(d["tag"], rows))
      end)

    refuse_unless(bad == [], """
    #{length(bad)} declared-unmatched members do not guard-check to A3 §6 state 3:
    #{Enum.map_join(bad, "\n", &("  " <> &1["tag"]))}
    """)

    checks = edges_doc["edges"] |> Enum.map(& &1["tag"]) |> Enum.uniq() |> Enum.sort()

    with_edges =
      edges_doc["edges"] |> Enum.map(& &1["member"]["register_key"]) |> Enum.uniq() |> length()

    # G15b — the four numbers the file declares about itself, against the four
    # the generator derives. C1a read this block for its `rule` STRING and never
    # checked one of its numbers. Weaker than G15a and kept beside it: counts
    # agreeing is not sets agreeing, and `members_with_edges` is not a set G15a
    # compares at all.
    mismatches =
      Crosswalk.declaration_mismatches(declared, %{
        "members" => length(members),
        "members_with_edges" => with_edges,
        "members_declared_unmatched" => length(edges_doc["declared_unmatched"]),
        "checks_addressed" => length(checks)
      })

    refuse_unless(mismatches == [], """
    G15 — `the_population_this_file_declares` disagrees with what the generator derives:
    #{Enum.map_join(mismatches, "\n", fn m -> "  #{m["field"]}: declared #{inspect(m["declared"])}, derived #{inspect(m["derived"])}" end)}
    The block is the file's statement about itself. Left unchecked it is a comment.
    """)

    %{
      "declared" => true,
      "rule" => declared["rule"],
      "selector" =>
        Map.put(
          declared["selector"],
          "evaluated",
          "#{length(selected)} members denoted; set-equal to the derived population in both " <>
            "directions (G15a). The counts block was checked field by field (G15b)."
        ),
      "members" => members,
      "member_count" => length(members),
      "members_with_edges" => with_edges,
      "members_declared_unmatched" => length(edges_doc["declared_unmatched"]),
      "checks" => checks,
      "check_count" => length(checks),
      "state_4_guard" => "ran over these #{length(members)} members; 0 fired",
      "outside_the_population" => %{
        "state" => "not_yet_adjudicated",
        "et_cc_members" => MapSet.size(etcc) - length(members),
        "in_denominator_checks" => 173 - length(checks),
        "why_it_is_a_third_state" =>
          "Distinct from bucket 1 ('we looked and there is no counterpart') and from A3 §6 " <>
            "state 4 ('nobody has adjudicated this member, and the guard FAILS it'). Reporting " <>
            "these as bucket 1 would assert of 260 members something false of every one.",
        "owners" =>
          "C1b = MES-104 (client leg), C1c = MES-105 (server leg + the 29 none_determinable)"
      }
    }
  end

  defp selected!(selector, attribution, attribution_path) do
    refuse_unless(is_map(selector), """
    G15 — `the_population_this_file_declares` carries no `selector`, so its `rule` is prose
    and the population is derived from the file being validated. That is circular: a dropped
    row shrinks the universe instead of violating it, and nothing goes red.
    """)

    refuse_unless(selector["source"] == attribution_path, """
    G15 — the selector names #{inspect(selector["source"])} as its source, but this run was
    given #{inspect(attribution_path)}. An anchor is only external if it is the anchor the
    file names; silently accepting a substituted one would make the selector circular again
    by another route.
    """)

    case Crosswalk.select(selector, attribution) do
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
    bucket_2 = project!(:bucket_2, population["checks"], checks_with_edges)

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
      "bucket_2" => %{
        "count" => length(bucket_2),
        "checks" => bucket_2,
        "rule" => "an in-population OC check with no edge",
        "result" =>
          if(bucket_2 == [],
            do:
              "CHECKED, AND ZERO — all #{population["check_count"]} checks in the declared population carry at least one edge",
            else: "#{length(bucket_2)} declared checks carry no edge"
          ),
        "universe" => "the #{population["check_count"]} declared checks, never all 173",
        "why_not_159" =>
          "The 159 in-denominator checks outside the population are NOT bucket 2. Bucket 2 is " <>
            "'we adjudicated and found no ET counterpart'; those were not adjudicated. C1b/C1c own them."
      },
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

  defp totality(cells, population, edges_doc) do
    edge_members = cells |> Enum.map(& &1["member"]["register_key"]) |> Enum.uniq()
    edge_checks = cells |> Enum.map(& &1["tag"]) |> Enum.uniq()
    unmatched = Enum.map(edges_doc["declared_unmatched"], & &1["member"]["register_key"])

    members = Crosswalk.set_compare(population["members"], edge_members ++ unmatched)
    checks = Crosswalk.set_compare(population["checks"], edge_checks)

    %{
      "measure" =>
        "SET COMPARISON, not arithmetic — two counts agreeing is not two sets agreeing.",
      "every_declared_member_appears" => %{
        "equal" => members.equal,
        "missing" => members.missing,
        "extra" => members.extra
      },
      "every_declared_check_appears" => %{
        "equal" => checks.equal,
        "missing" => checks.missing,
        "extra" => checks.extra
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
            "judgement and no refusal can reach it), and that anything outside the declared 21 " <>
            "members / 14 checks was falsified at all. C1b (MES-104) and C1c (MES-105) own the rest."
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
          "The population is 21 members and 14 checks. Two of the 14 enter through A3 §1's cardinality rule and §4's published worked edge, not through B2b's tokens — inherited, not newly adjudicated, and said so in the edges file."
      }
    ]
  end

  defp trust_status do
    "FALSIFICATION-TESTED by C3 (MES-99) and STANDING — over the declared 21-member / " <>
      "14-check slice and no further. (Standing, not proven: the attempts were made and none " <>
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

    refuse_unless(
      a["totality"]["every_declared_check_appears"]["equal"],
      "not every declared check appears: #{inspect(a["totality"]["every_declared_check_appears"])}"
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
                        #{p["check_count"]} OC checks.  State-4 guard: #{p["state_4_guard"]}
                        outside it: #{p["outside_the_population"]["et_cc_members"]} members / #{p["outside_the_population"]["in_denominator_checks"]} checks = not_yet_adjudicated

      edges             #{a["arithmetic"]["edges"]} = #{a["arithmetic"]["bucketed"]} bucketed + #{a["arithmetic"]["escalated"]} escalated

      buckets           #{b["from_edges"] |> Enum.sort() |> Enum.map_join(", ", fn {k2, v} -> "#{k2}: #{v}" end)}
                        bucket 5 partial sub-count: #{b["bucket_5_partial_sub_count"]}
                        bucket 1: #{b["bucket_1"]["count"]}   bucket 2: #{b["bucket_2"]["count"]} (#{b["bucket_2"]["result"]})
                        buckets 3 and 6: 0, by construction — every ET verdict is green

      keying control    rows lost over the 173 — check_id #{k["by_check_id_alone"]}, name #{k["by_name_alone"]}, description #{k["by_description_alone"]},
                        check_id+name #{k["by_check_id_and_name"]}, the token's five #{k["by_the_token_five"]}, A1's six #{k["by_a1s_six_field_key"]}

      axis provenance   harness checked: #{a["axis_provenance"]["harness_checked"]}#{if a["axis_provenance"]["harness_checked"], do: " (#{a["axis_provenance"]["axes_checked"]} axes verbatim at their spans)", else: ""}

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
