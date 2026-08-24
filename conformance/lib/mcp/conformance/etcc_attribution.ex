defmodule MCP.Conformance.ETCCAttribution do
  @moduledoc """
  Builds `docs/conformance/etcc-attribution.json` — B2b's enriched register — by
  **joining** ONE authored source to B2a's delivered member register.

  ## It JOINS B2a's register. It does not copy it.

  `conformance/data/etcc-attribution.json` carries `key` and the six attributes
  B2b establishes — `leg`, `leg_reason`, `cg`, `cg_basis`, `tokens`,
  `contradicts_oc` — and nothing else. Every other fact about a member (`file`,
  `line`, `label`, `boundary`, `evidence`, …) stays in
  `docs/conformance/etcc-register.json`, which is this build's other input and is
  never rewritten here.

  That is AC5, and it is enforced rather than promised. `check_disjoint!/2`
  refuses a build whose authored field names overlap the register's, so adding
  `label` or `line` to the authored source becomes a **build failure**, not a
  review catch. Two registers over one fact is the S5-31 two-indexes hazard, and
  this is the antecedent made unrepresentable.

  ## `boundary` is NEVER read, and that is checkable rather than promised

  The register's `boundary` field decides gate 2. It is **not** a leg
  attribution: `MCP.Client` as a boundary means "the asserted bytes come from
  this module's encoder", not "this member is a client-leg claim". This module
  reads `key` and `label` off the register and nothing else, so
  `conformance/controls/etcc_attribution_controls.exs strip-boundary` can delete
  `boundary` from every register row, re-run the whole build, and assert the
  output is byte-identical. A build that had used it could not survive that; a
  build that had not, cannot fail it.

  ## Fail-closed

  `build/1` raises rather than writing an enriched register that could mislead:

    * **field disjointness** — an authored field name (other than `key`) that
      also names a register row field;
    * **key-set equality, BOTH ways**, over exactly the register rows with
      `label == "ET-CC"`. A member with no attribution and an attribution naming
      a non-member raise *differently*, so the two failures cannot be confused.
      That is AC1's and AC2's completeness half;
    * **key verbatim** — the join is on the key as
      `docs/conformance/etcc-row-key.md` §1 spells it, with nothing trimmed,
      no describe prefix stripped and no test-type prefix stripped. Nothing here
      normalises, so a one-character difference cannot be absorbed;
    * a `leg` outside `server | client | none_determinable`, or a
      `none_determinable` with no reason — AC1 wants a reason, not a bucket;
    * an absent `cg_basis`. AC2 wants an explicit `none` **with** its reason, so
      a silent `nil` is refused: silence must not encode a decision;
    * a `cg` outside `CG1`–`CG7`;
    * a `contradicts_oc` naming no OC check. A contradiction needs something to
      contradict, and a bare flag would assert one without an address;
    * a malformed token — `oc:none/<reason-slug>/<origin-id>-<claim-slug>` or
      `oc:<leg>/<scenario>/<check_id>/<name>`, per
      `docs/conformance/match-relation.md` §5 and §6.

  ## Totals are DERIVED

  `totals` comes from `rows` and from nothing else, and a test re-derives the
  committed totals from the committed rows. `by_leg` and `by_cg` **always carry
  every key including zeros** — a consumer must never have to tell "zero" from
  "absent" (A2d).
  """

  @register "docs/conformance/etcc-register.json"
  @authored "conformance/data/etcc-attribution.json"
  @enriched "docs/conformance/etcc-attribution.json"

  @legs ~w(server client none_determinable)
  @cgs ~w(CG1 CG2 CG3 CG4 CG5 CG6 CG7)
  @authored_fields ~w(key leg leg_reason cg cg_basis tokens contradicts_oc)

  @doc "Paths, so a control script and the build script cannot drift apart."
  def paths, do: %{register: @register, authored: @authored, enriched: @enriched}

  @doc "The leg vocabulary, so a consumer never has to guess at the third value."
  def legs, do: @legs

  @doc """
  Builds the enriched register map. Raises on any fail-closed condition.

  `opts` may carry `:register` and `:authored` — both used by the controls to
  drive the same code over a mutated input.
  """
  def build(opts \\ []) do
    register = read_json(Keyword.get(opts, :register, @register))
    authored = read_json(Keyword.get(opts, :authored, @authored))

    register_rows = Map.fetch!(register, "rows")
    members = Enum.filter(register_rows, &(&1["label"] == "ET-CC"))

    check_disjoint!(authored, register_rows)
    check_key_sets!(MapSet.new(members, & &1["key"]), MapSet.new(authored, & &1["key"]))
    Enum.each(authored, &check_row!/1)

    rows = authored |> Enum.map(&project/1) |> Enum.sort_by(& &1["key"])

    %{
      "schema" => "etcc-attribution/1",
      "joins" => %{
        "register" => @register,
        "on" => "docs/conformance/etcc-row-key.md §1, verbatim",
        "member_set" => "the register rows with label == \"ET-CC\"",
        "note" =>
          "This artefact carries ONLY the attributes B2b establishes. Every other " <>
            "fact about a member is the register's and is not duplicated here."
      },
      "authorities" => %{
        "row_key" => "docs/conformance/etcc-row-key.md",
        "match_relation" => "docs/conformance/match-relation.md",
        "cg_reconciliation" => "docs/conformance/cg-reconciliation.md",
        "reasoning" => "docs/conformance/etcc-attribution.md"
      },
      "totals" => derive_totals(rows),
      "rows" => rows
    }
  end

  @doc "Builds and writes the enriched register. Returns its path."
  def write(opts \\ []) do
    path = Keyword.get(opts, :enriched, @enriched)
    File.write!(path, Jason.encode!(build(opts), pretty: true) <> "\n")
    path
  end

  @doc """
  Derives `totals` from `rows` and from nothing else.

  `by_leg` and `by_cg` carry every key including zeros — see the moduledoc.
  """
  def derive_totals(rows) do
    by_leg = Map.new(@legs, &{&1, Enum.count(rows, fn r -> r["leg"] == &1 end)})
    by_cg = Map.new(@cgs, &{&1, Enum.count(rows, fn r -> r["cg"] == &1 end)})

    %{
      "members" => length(rows),
      "by_leg" => by_leg,
      "by_cg" => Map.put(by_cg, "none", Enum.count(rows, &is_nil(&1["cg"]))),
      "with_cg" => Enum.count(rows, &(not is_nil(&1["cg"]))),
      "tokens" => rows |> Enum.flat_map(& &1["tokens"]) |> length(),
      "members_with_tokens" => Enum.count(rows, &(&1["tokens"] != [])),
      "state_1_tokens" => count_tokens(rows, &(not none_token?(&1))),
      "state_3_tokens" => count_tokens(rows, &none_token?/1),
      "contradicts_oc" => Enum.count(rows, &(not is_nil(&1["contradicts_oc"])))
    }
  end

  defp count_tokens(rows, pred), do: rows |> Enum.flat_map(& &1["tokens"]) |> Enum.count(pred)

  defp none_token?(token), do: String.starts_with?(token, "oc:none/")

  defp project(row), do: Map.take(row, @authored_fields)

  # --- the three AC5 refusals ----------------------------------------------

  defp check_disjoint!(authored, register_rows) do
    authored_fields =
      authored |> Enum.flat_map(&Map.keys/1) |> MapSet.new() |> MapSet.delete("key")

    register_fields = register_rows |> Enum.flat_map(&Map.keys/1) |> MapSet.new()

    case MapSet.intersection(authored_fields, register_fields) |> Enum.sort() do
      [] ->
        :ok

      overlap ->
        raise """
        AC5 violated: the authored source duplicates register field(s): #{Enum.join(overlap, ", ")}.

        The enriched register JOINS docs/conformance/etcc-register.json; it does not
        copy it. A fact with two homes diverges (S5-31). Remove the field and read it
        off the register.
        """
    end

    unknown = MapSet.difference(authored_fields, MapSet.new(@authored_fields))

    unless Enum.empty?(unknown) do
      raise "authored source carries unknown field(s): #{unknown |> Enum.sort() |> Enum.join(", ")}"
    end
  end

  defp check_key_sets!(member_keys, authored_keys) do
    missing = MapSet.difference(member_keys, authored_keys)
    extra = MapSet.difference(authored_keys, member_keys)

    # Both sides non-empty is the KEY-VERBATIM failure wearing its own name. A
    # normalisation — a trimmed key, a stripped `test ` prefix, a stripped
    # describe prefix — subtracts one key and adds another, so it shows up here
    # and nowhere else. Saying so is the difference between a reviewer chasing a
    # missing member and a reviewer looking at the two keys side by side.
    if not Enum.empty?(missing) and not Enum.empty?(extra) do
      raise """
      AC5 violated: #{MapSet.size(missing)} member(s) unattributed AND #{MapSet.size(extra)} attribution(s) naming a non-member.

      Both sides moving together is what a NORMALISED key looks like. The join is on
      docs/conformance/etcc-row-key.md §1 VERBATIM — nothing is trimmed and no
      describe or test-type prefix is stripped, so compare these two directly:
        member with no attribution: #{missing |> Enum.sort() |> hd() |> inspect()}
        attribution with no member: #{extra |> Enum.sort() |> hd() |> inspect()}
      """
    end

    unless Enum.empty?(missing) do
      raise """
      AC1/AC2 violated: #{MapSet.size(missing)} ET-CC member(s) carry no attribution.

      Every member must carry a leg AND a CG correspondence (or an explicit none).
      First missing key: #{missing |> Enum.sort() |> hd() |> inspect()}
      """
    end

    unless Enum.empty?(extra) do
      raise """
      AC5 violated: #{MapSet.size(extra)} attribution(s) name a key that is not an
      ET-CC member of docs/conformance/etcc-register.json.

      The key is joined VERBATIM (etcc-row-key.md §1) — nothing here trims, strips a
      describe prefix or strips a test-type prefix, so this is a real disagreement
      about the member set and not a normalisation artefact.
      First extra key: #{extra |> Enum.sort() |> hd() |> inspect()}
      """
    end
  end

  # --- per-row refusals -----------------------------------------------------

  defp check_row!(row) do
    key = row["key"]

    unless row["leg"] in @legs do
      raise "#{inspect(key)}: leg #{inspect(row["leg"])} is not one of #{Enum.join(@legs, ", ")}"
    end

    unless is_binary(row["leg_reason"]) and row["leg_reason"] != "" do
      raise "#{inspect(key)}: every leg attribution needs a reason (AC1), including a definite one"
    end

    unless is_binary(row["cg_basis"]) and row["cg_basis"] != "" do
      raise """
      #{inspect(key)}: cg_basis is missing.

      AC2 wants an explicit `none` WITH its reason. A silent nil would let silence
      encode a decision, which is the one thing this register may not do.
      """
    end

    unless is_nil(row["cg"]) or row["cg"] in @cgs do
      raise "#{inspect(key)}: cg #{inspect(row["cg"])} is not one of #{Enum.join(@cgs, ", ")}"
    end

    check_contradiction!(key, row["contradicts_oc"])
    Enum.each(row["tokens"] || [], &check_token!(key, &1))
  end

  defp check_contradiction!(_key, nil), do: :ok

  defp check_contradiction!(key, %{"check" => check, "note" => note})
       when is_binary(check) and is_binary(note) and check != "" and note != "" do
    unless String.starts_with?(check, "oc:") do
      raise "#{inspect(key)}: contradicts_oc.check #{inspect(check)} is not an OC token"
    end

    :ok
  end

  defp check_contradiction!(key, other) do
    raise """
    #{inspect(key)}: contradicts_oc must name the check it contradicts and say why,
    as %{"check" => <oc token>, "note" => <prose>}. Got: #{inspect(other)}

    A contradiction needs something to contradict — a bare flag asserts one without
    an address, and C1 cannot act on it.
    """
  end

  # `oc:none/<reason-slug>/<origin-id>-<claim-slug>` (match-relation.md §6) or
  # `oc:<leg>/<scenario>/<check_id>/<name>` (§5).
  defp check_token!(key, token) when is_binary(token) do
    case String.split(token, "/") do
      ["oc:none", reason, native] ->
        charset!(key, token, [reason, native])

      ["oc:" <> leg, scenario, check_id, name] when leg in ["server", "client"] ->
        charset!(key, token, [scenario, check_id, name])

      _ ->
        raise "#{inspect(key)}: token #{inspect(token)} is neither an oc: nor an oc:none/ address"
    end
  end

  defp check_token!(key, other),
    do: raise("#{inspect(key)}: token #{inspect(other)} is not a string")

  defp charset!(key, token, parts) do
    Enum.each(parts, fn part ->
      if part == "" or not Regex.match?(~r/^[A-Za-z0-9_-]+$/, part) do
        raise "#{inspect(key)}: token #{inspect(token)} has a part outside [A-Za-z0-9_-]: #{inspect(part)}"
      end
    end)
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()
end
