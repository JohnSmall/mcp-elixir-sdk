defmodule MCP.Conformance.ETCCRegister do
  @moduledoc """
  Builds `docs/conformance/etcc-register.json` — B2a's ET-CC membership register
  — by joining ONE authored decisions file to MES-83's ExUnit row artefact.

  ## One authored source, one derived artefact

  Labels, gates, spec anchors and evidence are authored by hand in
  `conformance/data/etcc-decisions.json` and live nowhere else. Every other field
  on a register row (`module`, `name`, `file`, `line`, `test_type`, `describe`) is
  **joined** from `docs/conformance/etcc-exunit-rows.json` and is never re-derived
  here. So a label has exactly one home, and a reviewer reproduces the register by
  re-running the build and diffing.

  The criterion itself is `docs/conformance/etcc-membership.md` and the row key is
  `docs/conformance/etcc-row-key.md` §1. Neither is restated here — this module
  enforces the SHAPE the criterion requires, never the judgement.

  ## Fail-closed, both ways

  `build/1` raises rather than writing a register that could mislead:

    * an in-scope key with no decision, or a decision naming a key the artefact
      does not have (the key sets must be equal, checked BOTH ways);
    * the four labels not summing to the enumerated in-scope population (§7);
    * an `ET-CC` row with no `spec_anchor` (AC3 enforced, not footnoted);
    * an `ET-ADJ` row with no `consumed_at`, or an `ET-CTRL` row whose `controls`
      names a key that does not exist;
    * `excluding_gate: 4` anywhere — amendment 2 made UNREPRESENTABLE rather than
      merely promised — or an excluding gate on a member, or none on a non-member;
    * `falsifiable` on anything but an `ET-CC` row (§4/§8);
    * an `adjudication` on a row that is not `escalated` — an answered escalation
      must stay visible AS one (MES-81 correction contract, comment `26037` item 2),
      because a row that silently becomes an ordinary decision loses the evidence
      that a human had to decide it;
    * an `adjudication` whose `raised_by` is not `sweep` or `PM` — `escalated` alone
      cannot say WHO found the row hard, and after a PM-raised re-decision the
      "the sweep flagged this" reading of `escalated` is simply wrong (CODE_REVIEWER
      at `26046`, adopted by the PM at `26047`);
    * a boundary the boundaries file records `dead` with no `l2` record beside it —
      **guard 20** (MES-81 correction contract, comment `26059` item 4). L2's trigger
      is mechanical: it runs on every boundary-direction whose live count is zero, so
      a DEAD verdict with no L2 record beside it means the trigger did not fire where
      its antecedent held. That is F6, and this is the guard that would have caught it;
    * an `ET-CC` row with no `boundary`, a `boundary` on a row that is not `ET-CC`,
      a `boundary` naming an id the boundaries file does not have, or — the one the
      PM asked for by name (`26048` item 5) — **an `ET-CC` row every one of whose
      boundaries the boundaries file records `dead`**. That is ruling A's antecedent
      made unrepresentable rather than promised: a dead boundary is one no `lib/`
      call site routes to a transport, so a member asserting only its output would
      be the F1 overstatement re-entering the register;
    * an `ET-CC` row that calls a SPLIT module's decode-side producer in its own test
      body without naming that module's `(decode)` direction — **guard 21** (PM ruling
      `26070`). This is the only guard about ATTRIBUTION rather than about a label or a
      measurement: which rows a verdict is applied to, which every other guard here
      takes as given. Its reach is stated in `check_attribution!/2` — doctest rows are
      outside it, and that residual is named rather than left to be found.
  """

  @artefact "docs/conformance/etcc-exunit-rows.json"
  @decisions "conformance/data/etcc-decisions.json"
  @boundaries "conformance/data/etcc-boundaries.json"
  @register "docs/conformance/etcc-register.json"

  @labels ~w(ET-CC ET-CTRL ET-ADJ ET-OUT)
  @in_scope_prefix "test/mcp/"

  @joined_fields ~w(module name file line test_type describe)

  @doc "Paths, so a control script and the build script cannot drift apart."
  def paths,
    do: %{
      artefact: @artefact,
      decisions: @decisions,
      boundaries: @boundaries,
      register: @register
    }

  @doc """
  Builds the register map. Raises on any fail-closed condition.

  `opts` may carry `:artefact`, `:decisions` and `:spec_md5s`.
  """
  def build(opts \\ []) do
    artefact = read_json(Keyword.get(opts, :artefact, @artefact))
    decisions_doc = read_json(Keyword.get(opts, :decisions, @decisions))
    decisions = Map.fetch!(decisions_doc, "decisions")

    boundary_rows =
      Keyword.get(opts, :boundaries, @boundaries) |> read_json() |> Map.fetch!("boundaries")

    check_boundaries!(boundary_rows)
    boundaries = Map.new(boundary_rows, &{&1["id"], &1["verdict"]})

    rows = Map.fetch!(artefact, "rows")

    {in_scope_rows, out_rows} =
      Enum.split_with(rows, &String.starts_with?(&1["file"], @in_scope_prefix))

    by_key = Map.new(rows, &{&1["key"], &1})
    in_scope_keys = MapSet.new(in_scope_rows, & &1["key"])
    decided_keys = MapSet.new(decisions, & &1["key"])

    check_key_sets!(in_scope_keys, decided_keys)
    Enum.each(decisions, &check_decision!(&1, by_key, boundaries))

    register_rows =
      decisions
      |> Enum.map(&join(&1, Map.fetch!(by_key, &1["key"])))
      |> Enum.sort_by(& &1["key"])

    check_controls_targets!(register_rows, by_key)
    check_attribution!(register_rows, Map.keys(boundaries))

    counts = Enum.frequencies_by(register_rows, & &1["label"])
    total = Enum.count(in_scope_rows)
    check_totality!(counts, total)

    out_of_scope =
      out_rows
      |> Enum.map(
        &%{"key" => &1["key"], "file" => &1["file"], "label" => "OUT-OF-SCOPE", "gate" => 1}
      )
      |> Enum.sort_by(& &1["key"])

    check_partition!(register_rows, out_of_scope, rows)

    %{
      "schema" => "etcc-register/1",
      "authorities" => %{
        "criterion" => "docs/conformance/etcc-membership.md",
        "row_key" => "docs/conformance/etcc-row-key.md",
        "boundaries" => @boundaries,
        "note" =>
          "Both are CITED, never restated. This file records decisions and their evidence; " <>
            "it does not carry the rules those decisions were made under."
      },
      "provenance" => provenance(artefact, Keyword.get(opts, :decisions, @decisions), opts),
      "totals" => totals(counts, total, register_rows, out_of_scope),
      "rows" => register_rows,
      "out_of_scope" => out_of_scope
    }
  end

  @doc "Builds and writes the register. Returns the path."
  def write(opts \\ []) do
    path = Keyword.get(opts, :register, @register)
    json = build(opts) |> Jason.encode!(pretty: true)
    File.write!(path, json <> "\n")
    path
  end

  # --- fail-closed checks ---

  # Guard 20. The rule is NOT restated here — `conformance/data/etcc-boundaries.json`
  # owns L2's trigger and `docs/conformance/etcc-register.md` §6a owns the reasoning.
  defp check_boundaries!(rows) do
    naked =
      for %{"id" => id, "verdict" => "dead"} = b <- rows,
          not match?(%{"ran" => true, "verdict" => "dead"}, b["l2"]),
          do: id

    if naked != [] do
      raise "REFUSING to write: #{length(naked)} boundary/ies are recorded DEAD with no L2 record " <>
              "(#{Enum.join(naked, ", ")}). L2 runs on EVERY boundary whose live count is zero, so a " <>
              "DEAD verdict without one means the trigger did not fire where its antecedent held."
    end

    :ok
  end

  defp check_key_sets!(in_scope, decided) do
    missing = MapSet.difference(in_scope, decided)
    extra = MapSet.difference(decided, in_scope)

    if MapSet.size(missing) > 0 do
      raise "REFUSING to write: #{MapSet.size(missing)} in-scope unit(s) have no decision, e.g.\n  " <>
              (missing |> Enum.take(5) |> Enum.join("\n  "))
    end

    if MapSet.size(extra) > 0 do
      raise "REFUSING to write: #{MapSet.size(extra)} decision(s) name a key that is not an in-scope unit, e.g.\n  " <>
              (extra |> Enum.take(5) |> Enum.join("\n  "))
    end
  end

  defp check_decision!(d, by_key, boundaries) do
    unless Map.has_key?(by_key, d["key"]),
      do: raise("REFUSING to write: #{d["key"]} is in no artefact row")

    check_label!(d)
    check_gate!(d)
    check_label_fields!(d)
    check_row_hygiene!(d)
    check_boundary!(d, boundaries)
    :ok
  end

  # Ruling A (MES-81 `26034`, applied to the whole population at `26048`) made
  # unrepresentable. The rule is NOT restated here — `docs/conformance/etcc-register.md`
  # §6a owns it and `conformance/data/etcc-boundaries.json` owns the measurement.
  # This only enforces that a row and the table cannot disagree.
  defp check_boundary!(%{"label" => "ET-CC", "key" => key, "boundary" => bs}, boundaries) do
    if bs in [nil, []] do
      raise "REFUSING to write: #{key} is ET-CC with no boundary. Ruling A is decided per " <>
              "boundary, so a member that names none cannot have been put to it."
    end

    unknown = Enum.reject(bs, &Map.has_key?(boundaries, &1))

    if unknown != [] do
      raise "REFUSING to write: #{key} names boundary/ies #{inspect(unknown)} that the " <>
              "boundaries file does not record. An unmeasured boundary is not a verdict."
    end

    if Enum.all?(bs, &(Map.fetch!(boundaries, &1) == "dead")) do
      raise "REFUSING to write: #{key} is ET-CC but every boundary it asserts " <>
              "(#{Enum.join(bs, ", ")}) is recorded DEAD. Ruling A: no lib/ call site routes " <>
              "a dead boundary to a transport, so gate 2 fails and the row is not a member."
    end

    :ok
  end

  defp check_boundary!(%{"key" => key, "boundary" => bs}, _boundaries) when bs not in [nil, []] do
    raise "REFUSING to write: #{key} is not ET-CC but records a boundary. Ruling A's " <>
            "antecedent is asked of members; a non-member has already failed a gate."
  end

  defp check_boundary!(_d, _boundaries), do: :ok

  defp check_label!(%{"key" => key, "label" => label}) do
    unless label in @labels do
      raise "REFUSING to write: #{key} carries label #{inspect(label)}, which is not one of " <>
              "#{Enum.join(@labels, ", ")}. OUT-OF-SCOPE is not one of the four labels (§1) " <>
              "and belongs in out_of_scope, not here."
    end
  end

  defp check_gate!(%{"key" => key, "label" => label, "excluding_gate" => gate}) do
    if gate == 4 do
      raise "REFUSING to write: #{key} records excluding_gate 4. Gate 4 NEVER excludes (§4); " <>
              "it is recorded as the `falsifiable` attribute. A 4 here is a defect in the sweep, " <>
              "not a finding."
    end

    cond do
      label == "ET-CC" and not is_nil(gate) ->
        raise "REFUSING to write: #{key} is a member and carries an excluding gate"

      label != "ET-CC" and gate not in [1, 2, 3] ->
        raise "REFUSING to write: #{key} is a non-member and its excluding gate is " <>
                "#{inspect(gate)}, not 1, 2 or 3"

      true ->
        :ok
    end
  end

  defp check_label_fields!(%{"label" => "ET-CC", "key" => key} = d) do
    if blank?(d["spec_anchor"]) do
      raise "REFUSING to write: #{key} is ET-CC with no spec_anchor. A member with no nameable " <>
              "2026-07-28 requirement fails gate 3 and is not a member (AC3)."
    end

    if d["falsifiable"] not in ~w(yes no undetermined) do
      raise "REFUSING to write: #{key} is ET-CC with falsifiable #{inspect(d["falsifiable"])} (§4)"
    end

    :ok
  end

  defp check_label_fields!(%{"key" => key, "label" => label} = d) do
    if not blank?(d["spec_anchor"]),
      do: raise("REFUSING to write: #{key} is a non-member carrying a spec_anchor")

    if not is_nil(d["falsifiable"]) do
      raise "REFUSING to write: #{key} is not a member but records falsifiable " <>
              "(§4/§8: it is a per-MEMBER field)"
    end

    if label == "ET-ADJ" and blank?(d["consumed_at"]),
      do: raise("REFUSING to write: #{key} is ET-ADJ with no consumed_at (§5)")

    if label == "ET-CTRL" and blank?(d["controls"]),
      do: raise("REFUSING to write: #{key} is ET-CTRL naming no controlled unit (§5)")

    :ok
  end

  defp check_row_hygiene!(%{"key" => key} = d) do
    if d["escalated"] and blank?(d["question"]) do
      raise "REFUSING to write: #{key} is escalated with no question. " <>
              "§9 requires the QUESTION on the row."
    end

    if blank?(d["evidence"]) do
      raise "REFUSING to write: #{key} carries no evidence. Epic ruling 7: every claim carries " <>
              "an address AND the bytes at it."
    end

    check_adjudication!(d)
  end

  defp check_adjudication!(%{"key" => key} = d) do
    case d["adjudication"] do
      nil ->
        :ok

      %{"ruling" => r, "comment" => c, "date" => date, "raised_by" => by}
      when r != nil and c != nil and date != nil ->
        unless by in ~w(sweep PM) do
          raise "REFUSING to write: #{key} carries an adjudication whose raised_by is " <>
                  "#{inspect(by)}, not \"sweep\" or \"PM\". `escalated` says a human decided " <>
                  "the row; only raised_by says who found it hard."
        end

        if d["escalated"] do
          :ok
        else
          raise "REFUSING to write: #{key} carries an adjudication but is not escalated. " <>
                  "An answered escalation must stay visible as one — a row that silently becomes " <>
                  "an ordinary decision loses the evidence that a human had to decide it."
        end

      other ->
        raise "REFUSING to write: #{key} carries an adjudication #{inspect(other)} that does not " <>
                "name a ruling, a comment id, a date and a raised_by"
    end
  end

  defp check_controls_targets!(rows, by_key) do
    for %{"label" => "ET-CTRL", "key" => key, "controls" => target} <- rows,
        not Map.has_key?(by_key, target) do
      raise "REFUSING to write: #{key} controls #{inspect(target)}, which is not a unit in the artefact"
    end

    :ok
  end

  # Guard 21 (MES-81 round 5, PM ruling `26070`). ATTRIBUTION — which rows a verdict is
  # applied to, which is upstream of every other guard here and was the last step still
  # done by eye. The rule is NOT restated: `docs/conformance/etcc-register.md` §6a step 1
  # owns it, and `26070` is what makes it literal — a row names every producer whose
  # correctness is LOAD-BEARING for what it asserts, and a decode-side producer is
  # load-bearing whenever the asserted value passed through it.
  #
  # So: read the member's OWN TEST BODY and refuse a member that calls a SPLIT module's
  # decode-side producer without naming that module's `(decode)` direction. Alias-aware,
  # because a qualified-name grep can only fail toward "it does not" (S7-16).
  #
  # REACH, stated rather than assumed: `test_type: "doctest"` rows are OUT of it. A
  # doctest's body is the `@doc` in `lib/`, not the test file at that line, so scanning
  # there would scan the wrong bytes — and a guard that scans the wrong bytes and finds
  # nothing reports a false green. Six ET-CC rows are outside the guard for that reason.
  defp check_attribution!(rows, boundary_ids) do
    split = split_modules(boundary_ids)

    members = Enum.filter(rows, &(&1["label"] == "ET-CC" and &1["test_type"] == "test"))

    sources =
      members
      |> Enum.map(& &1["file"])
      |> Enum.uniq()
      |> Map.new(&{&1, &1 |> File.read!() |> String.split("\n")})

    alias_maps = Map.new(sources, fn {file, lines} -> {file, aliases(lines)} end)

    offenders =
      Enum.flat_map(members, fn row ->
        named = MapSet.new(row["boundary"] || [])
        lines = Map.fetch!(sources, row["file"])

        row
        |> unit_body(lines)
        |> decode_producers_called(Map.fetch!(alias_maps, row["file"]), split)
        |> Enum.reject(&MapSet.member?(named, "#{&1} (decode)"))
        |> Enum.map(&{row, &1})
      end)

    if offenders != [] do
      detail =
        Enum.map_join(offenders, "\n", fn {row, mod} ->
          "  #{row["file"]}:#{row["line"]} calls #{mod}'s decode side, names #{inspect(row["boundary"])}"
        end)

      raise "REFUSING to write: #{length(offenders)} ET-CC row(s) call a split module's " <>
              "decode-side producer without naming its (decode) direction (guard 21).\n#{detail}"
    end

    :ok
  end

  # The modules the boundaries file records in BOTH directions. One recorded in a single
  # direction was measured as one boundary, so there is no `(decode)` id to name.
  defp split_modules(ids) do
    set = MapSet.new(ids)

    for id <- ids,
        String.ends_with?(id, " (decode)"),
        mod = String.replace_suffix(id, " (decode)", ""),
        MapSet.member?(set, "#{mod} (encode)"),
        into: MapSet.new(),
        do: mod
  end

  defp decode_producers_called(body, aliases, split) do
    body
    |> Enum.flat_map(
      &Regex.scan(~r/\b([A-Z][\w.]*)\.(from_map|decode_[a-z_]+|parse_[a-z_]+)\(/, &1)
    )
    |> Enum.map(fn [_all, name, _fun] -> resolve(name, aliases, split) end)
    |> Enum.filter(&MapSet.member?(split, &1))
    |> Enum.uniq()
  end

  # The unit's own body: its `test` line to the `end` that closes it, which `mix format`
  # puts at the same column. A body that cannot be delimited RAISES rather than being
  # skipped — a guard that quietly scans nothing reports a false green.
  defp unit_body(%{"file" => file, "line" => line}, lines) do
    first = Enum.at(lines, line - 1)

    unless is_binary(first) and Regex.match?(~r/^\s*test\s/, first) do
      raise "REFUSING to write: guard 21 cannot delimit #{file}:#{line} — that line is " <>
              "#{inspect(first)}, not a `test` declaration"
    end

    indent = String.length(first) - String.length(String.trim_leading(first))
    closing = String.duplicate(" ", indent) <> "end"
    rest = Enum.drop(lines, line)
    body = Enum.take_while(rest, &(&1 != closing))

    if length(body) == length(rest) do
      raise "REFUSING to write: guard 21 found no closing `end` for #{file}:#{line}"
    end

    body
  end

  defp resolve(name, aliases, split) do
    [head | rest] = String.split(name, ".")

    expanded =
      case Map.fetch(aliases, head) do
        {:ok, full} -> Enum.join([full | rest], ".")
        :error -> name
      end

    if MapSet.member?(split, expanded) do
      expanded
    else
      # A bare segment with no alias line of its own — match it against the measured
      # modules by suffix rather than declaring it unknown.
      Enum.find(split, expanded, &String.ends_with?(&1, "." <> name))
    end
  end

  # `alias A.B.C`, `alias A.B.C, as: X`, `alias A.B.{C, D}` — the three spellings this
  # tree uses. Bound name -> full module.
  defp aliases(lines) do
    lines
    |> Enum.flat_map(&alias_bindings/1)
    |> Map.new()
  end

  defp alias_bindings(line) do
    cond do
      m = Regex.run(~r/^\s*alias\s+([A-Z][\w.]*)\.\{([^}]*)\}/, line) ->
        [_, base, list] = m

        list
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&{&1, base <> "." <> &1})

      m = Regex.run(~r/^\s*alias\s+([A-Z][\w.]*),\s*as:\s*([A-Z]\w*)/, line) ->
        [_, full, as] = m
        [{as, full}]

      m = Regex.run(~r/^\s*alias\s+([A-Z][\w.]*)\s*$/, String.trim_trailing(line)) ->
        [_, full] = m
        [{full |> String.split(".") |> List.last(), full}]

      true ->
        []
    end
  end

  defp check_totality!(counts, total) do
    sum = @labels |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()

    if sum != total do
      raise "REFUSING to write: the four labels sum to #{sum}, not the enumerated in-scope population #{total} (§7)"
    end

    :ok
  end

  defp check_partition!(rows, out_of_scope, all_rows) do
    covered = MapSet.union(MapSet.new(rows, & &1["key"]), MapSet.new(out_of_scope, & &1["key"]))
    all = MapSet.new(all_rows, & &1["key"])

    unless MapSet.equal?(covered, all) do
      raise "REFUSING to write: rows + out_of_scope do not equal the artefact's key set, both ways"
    end

    :ok
  end

  # --- assembly ---

  defp join(decision, row) do
    joined = Map.take(row, @joined_fields)

    Map.merge(joined, %{
      "key" => decision["key"],
      "label" => decision["label"],
      "excluding_gate" => decision["excluding_gate"],
      "spec_anchor" => decision["spec_anchor"],
      "falsifiable" => decision["falsifiable"],
      "mixed" => decision["mixed"],
      "consumed_at" => decision["consumed_at"],
      "controls" => decision["controls"],
      "escalated" => decision["escalated"],
      "question" => decision["question"],
      "adjudication" => decision["adjudication"],
      "boundary" => decision["boundary"],
      "evidence" => decision["evidence"]
    })
  end

  defp totals(counts, total, rows, out_of_scope) do
    %{
      "in_scope" => total,
      "by_label" => Map.new(@labels, &{&1, Map.get(counts, &1, 0)}),
      "by_excluding_gate" =>
        Map.new([1, 2, 3], fn g ->
          {Integer.to_string(g), Enum.count(rows, &(&1["excluding_gate"] == g))}
        end),
      "by_falsifiable" =>
        Map.new(~w(yes no undetermined), fn v ->
          {v, Enum.count(rows, &(&1["falsifiable"] == v))}
        end),
      "mixed" => Enum.count(rows, & &1["mixed"]),
      "escalated" => Enum.count(rows, & &1["escalated"]),
      "adjudicated" => Enum.count(rows, &(&1["adjudication"] != nil)),
      "adjudications_raised_by" =>
        Map.new(~w(sweep PM), fn by ->
          {by, Enum.count(rows, &(get_in(&1, ["adjudication", "raised_by"]) == by))}
        end),
      "et_cc_by_boundary" =>
        rows
        |> Enum.filter(&(&1["label"] == "ET-CC"))
        |> Enum.flat_map(& &1["boundary"])
        |> Enum.frequencies(),
      "out_of_scope" => Enum.count(out_of_scope)
    }
  end

  defp provenance(artefact, decisions_path, opts) do
    %{
      "artefact" => @artefact,
      "artefact_rows_md5" => get_in(artefact, ["run", "rows_md5"]),
      "decisions" => decisions_path,
      "decisions_md5" => md5_file(decisions_path),
      "spec_pin" => "5f5440bb26a62e2cf3440b92da5a667efa03b267",
      "spec_files" => Keyword.get(opts, :spec_md5s, %{}),
      "note" =>
        "CONTENT HASHES, not a tip: the branch commit a measurement was taken at is left unreferenced " <>
          "by the squash-merge (etcc-row-key.md §5.2), so rows_md5 and the decisions md5 are what a " <>
          "later reader can actually verify against."
    }
  end

  # --- helpers ---

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp md5_file(path),
    do: path |> File.read!() |> then(&:crypto.hash(:md5, &1)) |> Base.encode16(case: :lower)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
