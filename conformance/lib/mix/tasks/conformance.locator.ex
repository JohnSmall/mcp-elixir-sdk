defmodule Mix.Tasks.Conformance.Locator do
  @shortdoc "Resolve every in-denominator OC check to its emitting site in the harness build"

  @moduledoc """
  Derive `docs/conformance/oc-emitting-sites-2026-07-28.json` — for each of the
  173 in-denominator checks, the site in the harness `dist/index.js` that emits
  it, addressed by byte span **and quoted verbatim**.

      mix conformance.locator \\
        --harness /tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js \\
        --denominator docs/conformance/bucket-0-2026-07-28.json \\
        --axes docs/conformance/oc-axes-2026-07-28.json \\
        -o docs/conformance/oc-emitting-sites-2026-07-28.json

  ## Why it exists as an artefact and not as the written procedure it came from

  MES-76 wrote the traversal down and A3 hand-cut 13 rows with it. C1b and C1c
  have to adjudicate the other 160, and a hand traversal per check does not
  reach 173 — nor should it, because the same traversal run twice by hand is
  two answers. This task runs it once, mechanically, and commits the result
  **with the bytes**: the harness lives in `/tmp` and is committed nowhere, so
  an address into it is an address into nothing after a wipe (the standing
  R6/MES-72 residual). What the artefact loses is re-derivability on a clean
  checkout; what it keeps is the evidence.

  ## The self-validating step, and it runs FIRST

  The mechanical procedure is checked against the only other answer that exists
  for it: A3's 13 hand-cut `evaluator_excerpt`s. All 13 must come back
  **byte-identical** or the task refuses and emits nothing. A run whose
  mechanism was never checked against a hand answer would be 173 rows of
  unfalsified output, and 160 of those rows have nothing to compare against at
  all.

  Shown able to fail rather than assumed to be: move one committed span by 16
  bytes and the control reports the row, the rung and the spans it derived.
  `conformance/controls/crosswalk_controls.exs` drives that mutation.

  ## The three numbers this artefact exists to keep apart (S9-14)

  MES-65, MES-96 and MES-97's own body all say *"6 of 13 check ids do not occur
  in the harness build at all"*. That sentence conflates three different
  measurements, and it is wrong on two of them. The artefact prints each
  **next to its own predicate**, never as one figure:

    * **occurs at all** — 5 of A3's 13 rows (5 distinct ids); 8 of the 173.
    * **reached by a bare grep on the check_id** — 7 of 13 reach, **6 do not**
      (5 template-built + 1 constant-bound). This is the true home of the 6,
      and `reverse_lookup_procedure.direction` says so in those words.
    * **distinct check ids** — 11 among A3's 13 rows; 110 among the 173.

  The 6 is real. It belongs to reach-the-site, not to occur-at-all, and its
  denominator is rows, not ids.

  ## Exit status

  `0` derived. `1` refused. `64` usage error.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, Locator}

  @switches [
    harness: :string,
    denominator: :string,
    axes: :string,
    manifest: :string,
    out: :string
  ]
  @aliases [o: :out]

  @usage "mix conformance.locator --harness FILE --denominator FILE --axes FILE -o FILE"

  @revision "2026-07-28"
  @reaching_rungs [:id_literal_pair, :id_literal_site]

  @impl Mix.Task
  def run(argv) do
    {opts, _} =
      Argv.parse!("conformance.locator", argv,
        strict: @switches,
        aliases: @aliases,
        usage: @usage
      )

    harness_path = require!(opts, :harness)
    out = require!(opts, :out)
    denominator = opts |> require!(:denominator) |> read_json!()
    axes = opts |> require!(:axes) |> read_json!()

    h =
      case Locator.load(harness_path) do
        {:ok, h} ->
          h

        {:error, reason} ->
          Mix.raise("cannot read the harness at #{harness_path}: #{inspect(reason)}")
      end

    sha = Locator.sha256(h)

    refuse_unless(sha == axes["provenance"]["harness_dist_sha256"], """
    the harness at #{harness_path} is not the build the axes were read from.
      here:      #{sha}
      oc-axes:   #{axes["provenance"]["harness_dist_sha256"]}
    Every span this task emits addresses a build. Emitting them against a different one
    would produce citations that still read as citations.
    """)

    control = positive_control!(h, axes)

    rows =
      denominator["checks"]
      |> Enum.filter(& &1["matchable"])
      |> Enum.map(&row(h, &1))

    refuse_unless(
      length(rows) == 173,
      "the denominator is not 173 matchable checks — it is #{length(rows)}"
    )

    unresolved = Enum.filter(rows, &(&1["rung"] == "unresolved"))
    mispinned = Enum.filter(rows, &mispinned?/1)

    refuse_unless(mispinned == [], """
    #{length(mispinned)} rows claim a ROW-LEVEL pin while their own rung_detail says the
    address that resolved them does not name the row (row_key_matches == false):
    #{Enum.map_join(mispinned, "\n", &("  " <> &1["check_id"] <> " / " <> &1["name"] <> "  via " <> &1["rung_detail"]["table"] <> "[" <> &1["rung_detail"]["table_key"] <> "]"))}
    An artefact may record a coarser pin than it would like; it may not record a finer one
    than it has. The consistency is COMPUTED in every case and ENFORCED here, because a
    computed field nobody acts on is the state CR found in the first cut of this artefact.
    """)

    artefact = %{
      "schema" => "oc-emitting-sites/1",
      "revision" => @revision,
      "generated_by" => "mix conformance.locator",
      "owner" => "MES-97 (C1a). The PROCEDURE is MES-76's and is cited, never restated.",
      "what_this_is" =>
        "For each in-denominator OC check, the site in the harness build that emits it — " <>
          "addressed by byte span AND quoted verbatim, because an address is not evidence and " <>
          "the build it addresses is committed nowhere.",
      "provenance" => provenance(harness_path, sha, opts),
      "positive_control" => control,
      "ladder" => ladder(rows),
      "predicates" => predicates(rows, h, axes),
      "totals" => %{
        "rows" => length(rows),
        "distinct_check_ids" => rows |> Enum.map(& &1["check_id"]) |> Enum.uniq() |> length(),
        "distinct_sites" =>
          rows
          |> Enum.flat_map(& &1["sites"])
          |> Enum.map(& &1["byte_span"])
          |> Enum.uniq()
          |> length(),
        "rows_with_no_site" => Enum.count(rows, &(&1["sites"] == [])),
        "unresolved" => length(unresolved)
      },
      "residuals" => residuals(rows),
      "rows" => rows
    }

    refuse_unless(unresolved == [], """
    #{length(unresolved)} rows resolved to no emitting site at all:
    #{Enum.map_join(unresolved, "\n", &("  " <> &1["check_id"] <> " / " <> &1["name"]))}
    A row with no site is not a locator entry. Extend the ladder, or record the row as a
    stated negative — do not emit an artefact whose silence reads as a resolution.
    """)

    File.write!(out, Jason.encode!(artefact, pretty: true) <> "\n")
    report(artefact, out)
  end

  defp positive_control!(h, axes) do
    case Locator.positive_control(h, axes) do
      {:ok, n} ->
        %{
          "rows" => n,
          "source" => "docs/conformance/oc-axes-2026-07-28.json — A3's 13 hand-cut rows",
          "result" =>
            "all #{n} re-derived from the ladder and the excerpt rule, BYTE-IDENTICAL to the committed evaluator_excerpt",
          "what_it_establishes" =>
            "The mechanical traversal agrees with the hand traversal on the only population " <>
              "where both answers exist. It is the one place this mechanism can be checked " <>
              "against something that is not itself.",
          "what_it_does_not_establish" =>
            "That the emitting site is where the check's VERDICT is decided. " <>
              "sep-2575-client-retry-supported-version is emitted with a hard-coded " <>
              "status:`WARNING` and decided ~200 bytes later at a this.checks.find(...) " <>
              "mutation site that carries no id literal in an emitting position (S9-16). " <>
              "It also says nothing about the other 160 rows, which have no hand answer to " <>
              "be compared against."
        }

      {:error, mismatches} ->
        Mix.raise("""
        POSITIVE CONTROL FAILED — the mechanical traversal does not reproduce A3's hand-cut rows.
        #{length(mismatches)} of 13 mismatched:
        #{Enum.map_join(mismatches, "\n", fn m -> "  #{m.check_id} / #{m.name}  rung=#{m.rung}  a3=#{inspect(m.a3_span)}  derived=#{inspect(m.derived_spans)}" end)}
        Nothing is emitted. Fix the ladder or the excerpt rule; do not commit 173 rows whose
        mechanism failed on the 13 that can be checked.
        """)
    end
  end

  defp row(h, check) do
    [leg, scenario, check_id, name, description, discriminator] = check["key"]
    {rung, sites, meta} = Locator.resolve(h, check_id, name)

    %{
      "key" => check["key"],
      "token" => check["token"],
      "leg" => leg,
      "scenario" => scenario,
      "check_id" => check_id,
      "name" => name,
      "description" => description,
      "discriminator" => discriminator,
      "status_at_accepted_run" => check["status"],
      "check_id_occurrences" => Locator.occurrence_count(h, check_id),
      "grep_for" => "`" <> check_id <> "`",
      "rung" => Atom.to_string(rung),
      "rung_pin_level" => Atom.to_string(Locator.pin_level(rung, meta)),
      "rung_pins" => pins(rung, meta),
      "reached_by_bare_grep" => rung in @reaching_rungs,
      "rung_detail" => meta,
      "sites" => Enum.map(sites, &site(h, &1)) |> Enum.uniq_by(& &1["byte_span"])
    }
  end

  defp site(h, pos) do
    case Locator.excerpt(h, pos) do
      :none ->
        %{"site_byte_offset" => pos, "byte_span" => nil, "char_span" => nil, "bytes" => nil}

      {from, to} ->
        %{
          "site_byte_offset" => pos,
          "byte_span" => [from, to],
          "char_span" => [Locator.char_offset(h, from), Locator.char_offset(h, to)],
          "bytes" => Locator.bytes(h, {from, to})
        }
    end
  end

  defp pins(:id_literal_pair, _), do: "the ROW — the id literal sits next to this row's own name"

  defp pins(:id_literal_site, _),
    do:
      "the CHECK, not the row — the name at the site is computed, so rows sharing this id share this site"

  defp pins(:id_bound_variable, _),
    do: "the CHECK — the id reaches the site through a variable binding"

  defp pins(:id_table_value, %{"row_key_matches" => true, "table" => t, "table_key" => k}),
    do:
      "the ROW, via the table ENTRY #{t}[#{k}] — that key IS this row's own name suffix, and the " <>
        "entry's span and bytes are in rung_detail.table_entry. The emitting SITE below is the " <>
        "loop that consumes the table and names no row; the entry is what addresses this row."

  defp pins(:id_table_value, %{"table" => t, "table_key" => k}),
    do:
      "the LOOP, not the row — the id was reached through the SIBLING key #{t}[#{k}], which does " <>
        "not name this row. The site consumes the whole table and emits this row with its " <>
        "siblings; no address in hand distinguishes it. A real resolution, one level coarser."

  defp pins(:id_template_prefix, _),
    do: "the LOOP, not the row — the id does not occur; the site emits this row and its siblings"

  defp pins(:unresolved, _), do: "nothing"

  defp ladder(rows) do
    %{
      "rungs" => Enum.map(Locator.ladder(), &Atom.to_string/1),
      "order_note" =>
        "Tried in order; the first that hits wins. The rungs do NOT establish the same thing — " <>
          "see each row's rung_pins.",
      "per_rung" => Enum.frequencies_by(rows, & &1["rung"]),
      "per_pin_level" => Enum.frequencies_by(rows, & &1["rung_pin_level"]),
      "pin_level_note" =>
        "The level is a function of the rung AND its metadata, not of the rung alone: an " <>
          "id_table_value row pins the ROW when the entry that resolved is keyed by its own " <>
          "name suffix and the LOOP when it is a sibling's key. Counting by rung would " <>
          "over-state row-level resolution by 6 rows (MES-97 CR finding)."
    }
  end

  defp predicates(rows, h, axes) do
    a3 =
      Enum.map(axes["checks"], fn c ->
        [_, _, cid, name, _, _] = c["key"]
        {rung, _, _} = Locator.resolve(h, cid, name)
        {cid, rung, Locator.occurrence_count(h, cid)}
      end)

    %{
      "why_this_block_exists" =>
        "MES-65, MES-96 and MES-97's body all say '6 of 13 check ids do not occur in the harness " <>
          "build at all'. That conflates three measurements and is wrong on two. Each number is " <>
          "printed next to its own predicate here, and this artefact supersedes those sentences " <>
          "(PM ruling, MES-97 comment 27858). Recorded as S9-14.",
      "occurs_at_all" => %{
        "predicate" => "the check_id occurs as a backtick literal anywhere in dist/index.js",
        "over_the_173_rows" => %{
          "yes" => Enum.count(rows, &(&1["check_id_occurrences"] > 0)),
          "no" => Enum.count(rows, &(&1["check_id_occurrences"] == 0))
        },
        "over_a3s_13_rows" => %{
          "yes" => Enum.count(a3, fn {_, _, n} -> n > 0 end),
          "no" => Enum.count(a3, fn {_, _, n} -> n == 0 end)
        },
        "distinct_ids_occurring_zero_times" => %{
          "over_the_173" =>
            rows
            |> Enum.filter(&(&1["check_id_occurrences"] == 0))
            |> Enum.map(& &1["check_id"])
            |> Enum.uniq()
            |> length(),
          "over_a3s_13" =>
            a3
            |> Enum.filter(fn {_, _, n} -> n == 0 end)
            |> Enum.map(&elem(&1, 0))
            |> Enum.uniq()
            |> length()
        },
        "zero_occurrence_rows" =>
          rows
          |> Enum.filter(&(&1["check_id_occurrences"] == 0))
          |> Enum.map(&Enum.take(&1["key"], 4))
      },
      "reached_by_a_bare_grep" => %{
        "predicate" =>
          "a grep on the check_id lands ON the emitting site — rung id_literal_pair or " <>
            "id_literal_site. The other three rungs reach a site only by a further hop.",
        "over_the_173_rows" => %{
          "reaches" => Enum.count(rows, & &1["reached_by_bare_grep"]),
          "does_not" => Enum.count(rows, &(not &1["reached_by_bare_grep"]))
        },
        "over_a3s_13_rows" => %{
          "reaches" => Enum.count(a3, fn {_, r, _} -> r in @reaching_rungs end),
          "does_not" => Enum.count(a3, fn {_, r, _} -> r not in @reaching_rungs end)
        },
        "this_is_where_the_6_lives" =>
          "6 of A3's 13 ROWS are not reached by a bare grep — 5 template-built plus 1 " <>
            "constant-bound. MES-76's reverse_lookup_procedure.direction states it in exactly " <>
            "those words: 'a grep on the check_id reaches the emitting site for only 7 of the 13 " <>
            "rows'. Re-derived here mechanically and independently, and it comes back 7.",
        "a3_ladder" => Enum.frequencies_by(a3, fn {_, r, _} -> Atom.to_string(r) end)
      },
      "distinct_check_ids" => %{
        "predicate" => "how many DISTINCT check_ids the rows carry — ids, not rows",
        "over_the_173_rows" => rows |> Enum.map(& &1["check_id"]) |> Enum.uniq() |> length(),
        "over_a3s_13_rows" => a3 |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length(),
        "why_it_matters" =>
          "A figure quoted as '13' is a ROW count and its id count is 11. Keying anything on " <>
            "the id merges rows — the hazard A1's six-field key exists for."
      }
    }
  end

  defp residuals(rows) do
    [
      %{
        "id" => "L1",
        "text" =>
          "The site is where the check is EMITTED, not necessarily where its verdict is decided. " <>
            "sep-2575-client-retry-supported-version is emitted with status:`WARNING` hard-coded " <>
            "and mutated later at a this.checks.find(...) site. A consumer reading the emitting " <>
            "excerpt for that check reads a constant, not a predicate. S9-16."
      },
      %{
        "id" => "L2",
        "text" =>
          "Spans address ONE build. A harness bump invalidates every one of them, exactly as A1's " <>
            "residual R3 and A3's axis residual say. The sha lets a reader tell; nothing detects it."
      },
      %{
        "id" => "L3",
        "text" =>
          "Not every row is pinned to ITSELF. #{Enum.count(rows, &(&1["rung_pin_level"] != "row"))} " <>
            "of #{length(rows)} rows resolve to their CHECK's or their LOOP's address rather than " <>
            "their own: #{level_breakdown(rows)}. Every row carries rung_pin_level and rung_pins, " <>
            "so a consumer cannot mistake one for the other. This figure was hard-coded at 21 in " <>
            "the first cut — it counted two rungs and missed id_bound_variable's 12 and the six " <>
            "sibling-keyed id_table_value rows CR found. It is computed from the rows now.",
        "was" => "21, hard-coded (MES-97 CR finding)"
      },
      %{
        "id" => "L5",
        "text" =>
          "Where a row IS pinned at row level by rung id_table_value, the pinning address is the " <>
            "table ENTRY, not the emitting site: the site is a loop and its bytes name no row. " <>
            "Both addresses are recorded with their bytes. A reader wanting the row's own evidence " <>
            "must read rung_detail.table_entry.bytes, not sites[].bytes.",
        "routed" =>
          "All ten id_table_value rows DO have an entry keyed by their own name suffix in the " <>
            "table — measured, not assumed. The resolver takes the FIRST occurrence of the id " <>
            "literal, which for a shared id is a sibling's entry, so six rows resolve one level " <>
            "coarser than the bytes would allow. Selecting the row-keyed entry instead would pin " <>
            "all ten at row level. Recorded, not done: PM ratified reclassification (MES-97 " <>
            "comment 27866) and epic ruling 3 forbids fixing what a measurement surfaces. S9-19."
      },
      %{
        "id" => "L4",
        "text" =>
          "The bracket scanner skips ', \" and ` contexts but not regex literals. A regex holding " <>
            "an unbalanced bracket or a lone quote would desynchronise it. None does in this build " <>
            "— established by the positive control passing and by every one of the 173 rows cutting " <>
            "a span — but it is a property of this build, not of the scanner."
      }
    ]
  end

  defp provenance(harness_path, sha, opts) do
    %{
      "harness_dist_sha256" => sha,
      "harness_read_from" => harness_path,
      "equals" =>
        "in-scope-2026-07-28.json provenance.server/.client harness_dist_sha256, and " <>
          "oc-axes-2026-07-28.json provenance.harness_dist_sha256 — asserted by this task, not assumed",
      "denominator" => Keyword.get(opts, :denominator),
      "denominator_rule" => "bucket-0-2026-07-28.json checks where matchable == true (A5's 173)",
      "procedure" =>
        "docs/conformance/oc-axes-2026-07-28.json provenance.reverse_lookup_procedure (MES-76) — " <>
          "cited, not restated. This task extends it with two rungs that population found: " <>
          "id_bound_variable generalises the CONSTANT case to non-literal initialisers, and " <>
          "id_table_value is a case MES-76 does not name.",
      "axes" => Keyword.get(opts, :axes)
    }
  end

  defp report(a, out) do
    p = a["predicates"]

    Mix.shell().info("""

    OC EMITTING SITES — #{a["revision"]}, written to #{out}

      positive control  #{a["positive_control"]["rows"]} of A3's hand-cut rows re-derived byte-identical

      ladder            #{a["ladder"]["per_rung"] |> Enum.sort_by(&(-elem(&1, 1))) |> Enum.map_join(", ", fn {k, v} -> "#{k} #{v}" end)}
      pins              #{a["ladder"]["per_pin_level"] |> Enum.sort_by(&(-elem(&1, 1))) |> Enum.map_join(", ", fn {k, v} -> "#{k} #{v}" end)}
                        (level is rung AND metadata — see ladder.pin_level_note)

      rows              #{a["totals"]["rows"]} in-denominator, #{a["totals"]["distinct_check_ids"]} distinct check_ids, #{a["totals"]["distinct_sites"]} distinct sites
                        unresolved #{a["totals"]["unresolved"]}, rows with no site #{a["totals"]["rows_with_no_site"]}

      three predicates, three numbers (S9-14) — over the 173 / over A3's 13:
        occurs at all             #{p["occurs_at_all"]["over_the_173_rows"]["no"]} / #{p["occurs_at_all"]["over_a3s_13_rows"]["no"]} rows do NOT
        reached by a bare grep    #{p["reached_by_a_bare_grep"]["over_the_173_rows"]["does_not"]} / #{p["reached_by_a_bare_grep"]["over_a3s_13_rows"]["does_not"]} rows do NOT
        distinct check ids        #{p["distinct_check_ids"]["over_the_173_rows"]} / #{p["distinct_check_ids"]["over_a3s_13_rows"]}
    """)
  end

  defp level_breakdown(rows) do
    rows
    |> Enum.reject(&(&1["rung_pin_level"] == "row"))
    |> Enum.frequencies_by(&{&1["rung_pin_level"], &1["rung"]})
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.map_join(", ", fn {{level, rung}, n} -> "#{n} #{level} (#{rung})" end)
  end

  # The guard's predicate, stated independently of `Locator.pin_level/2` so that
  # it cross-checks that function rather than restating it: whatever computed the
  # level, a "row" claim must be backed by a row-naming address.
  defp mispinned?(row) do
    row["rung_pin_level"] == "row" and Map.get(row["rung_detail"], "row_key_matches") == false
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()

  defp require!(opts, key),
    do: Keyword.get(opts, key) || Mix.raise("--#{key} is required.\n#{@usage}")

  defp refuse_unless(true, _why), do: :ok
  defp refuse_unless(false, why), do: Mix.raise(why)
end
