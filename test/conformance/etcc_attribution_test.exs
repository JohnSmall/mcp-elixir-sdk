defmodule MCP.Conformance.ETCCAttributionTest do
  @moduledoc """
  AC5's cross-file test: `docs/conformance/etcc-attribution.json` **joins**
  `docs/conformance/etcc-register.json` and does not duplicate it, and the two
  cannot disagree about the member set without this failing.

  ## What this file costs, stated rather than discovered

  It sits under `test/conformance/`, which `etcc-membership.md` gate 1 puts
  OUT of scope, so its tests join the register's out-of-scope population rather
  than its members. `docs/conformance/etcc-exunit-rows.json` is B3's committed
  snapshot at B3's own tip and is NOT regenerated here, so nothing in this ticket
  moves the 992 — but the next regeneration (B4's, or a later B3 refresh) will see
  992 + the tests in this file, all of them out-of-scope. Recorded because
  `etcc-row-key.md` §5.1 asks a reader to tell expected movement from a finding.

  Every other instrument for this register is a control script for exactly this
  reason (`conformance/controls/etcc_attribution_controls.exs`). AC5 asks for a
  test in gate 5, so this one file is the deliberate exception.
  """
  use ExUnit.Case, async: true

  alias MCP.Conformance.ETCCAttribution

  @register "docs/conformance/etcc-register.json"
  @enriched "docs/conformance/etcc-attribution.json"
  @authored "conformance/data/etcc-attribution.json"

  setup_all do
    %{
      register: read(@register),
      enriched: read(@enriched),
      authored: read(@authored)
    }
  end

  describe "AC5 — the enriched register JOINS B2a's and does not duplicate it" do
    test "the member sets are equal, and a disagreement fails HERE", ctx do
      members =
        ctx.register["rows"]
        |> Enum.filter(&(&1["label"] == "ET-CC"))
        |> MapSet.new(& &1["key"])

      attributed = MapSet.new(ctx.enriched["rows"], & &1["key"])

      assert MapSet.equal?(members, attributed), """
      The two files disagree about the member set.
        members with no attribution: #{MapSet.difference(members, attributed) |> Enum.take(3) |> inspect()}
        attributions with no member: #{MapSet.difference(attributed, members) |> Enum.take(3) |> inspect()}
      """
    end

    test "the enriched rows carry NO field the register already carries", ctx do
      register_fields = ctx.register["rows"] |> Enum.flat_map(&Map.keys/1) |> MapSet.new()
      enriched_fields = ctx.enriched["rows"] |> Enum.flat_map(&Map.keys/1) |> MapSet.new()

      overlap =
        enriched_fields
        |> MapSet.intersection(register_fields)
        |> MapSet.delete("key")

      assert Enum.empty?(overlap),
             "duplicated field(s): #{overlap |> Enum.sort() |> inspect()} — a fact with two homes diverges (S5-31)"
    end

    test "the join key is the row key VERBATIM — nothing normalised", ctx do
      # etcc-row-key.md §1: `name` carries the test-type prefix AND the describe
      # prefix, and neither is stripped. If either side had normalised, the sets
      # above would differ; this asserts the property positively as well, so a
      # future both-sides-normalised change cannot pass by symmetry.
      keys = Enum.map(ctx.enriched["rows"], & &1["key"])

      assert Enum.all?(keys, &String.contains?(&1, "/")),
             "every key is `inspect(module) <> \"/\" <> name` (etcc-row-key.md §1)"

      assert Enum.any?(keys, &String.contains?(&1, "/test ")),
             "the `test ` type prefix is carried, not stripped"

      assert Enum.any?(keys, &String.contains?(&1, "/doctest ")),
             "the `doctest ` type prefix is carried, not stripped"

      assert Enum.all?(keys, &(&1 == String.trim(&1))), "no key is trimmed on either side"
    end
  end

  describe "AC1/AC2 — completeness, with the zeros reported" do
    test "every member carries a leg from the vocabulary, and a reason", ctx do
      for row <- ctx.enriched["rows"] do
        assert row["leg"] in ETCCAttribution.legs(), "#{row["key"]}: leg #{inspect(row["leg"])}"

        assert is_binary(row["leg_reason"]) and row["leg_reason"] != "",
               "#{row["key"]}: no reason"
      end
    end

    test "every member carries a CG correspondence or an explicit none, with a basis", ctx do
      for row <- ctx.enriched["rows"] do
        assert is_nil(row["cg"]) or row["cg"] in ~w(CG1 CG2 CG3 CG4 CG5 CG6 CG7)
        assert is_binary(row["cg_basis"]) and row["cg_basis"] != "", "#{row["key"]}: no cg_basis"
      end
    end

    test "by_leg and by_cg carry EVERY key, including the zeros", ctx do
      totals = ctx.enriched["totals"]

      for leg <- ETCCAttribution.legs() do
        assert Map.has_key?(totals["by_leg"], leg), "by_leg must not omit #{leg}"
      end

      for cg <- ~w(CG1 CG2 CG3 CG4 CG5 CG6 CG7 none) do
        assert Map.has_key?(totals["by_cg"], cg), "by_cg must not omit #{cg}"
      end

      # CG3, CG5 and CG6 have no ET-CC member at this tip, and the artefact says
      # so with a 0 rather than by leaving the key out. A consumer must never have
      # to tell "zero" from "absent" (A2d).
      assert totals["by_cg"]["CG3"] == 0
      assert totals["by_cg"]["CG5"] == 0
      assert totals["by_cg"]["CG6"] == 0
    end
  end

  describe "totals are DERIVED from rows" do
    test "the committed totals re-derive from the committed rows", ctx do
      assert ETCCAttribution.derive_totals(ctx.enriched["rows"]) == ctx.enriched["totals"]
    end

    test "the leg populations partition the member set", ctx do
      totals = ctx.enriched["totals"]
      by_leg = totals["by_leg"]

      assert by_leg["server"] + by_leg["client"] + by_leg["none_determinable"] ==
               totals["members"]

      assert totals["members"] == length(ctx.enriched["rows"])
    end
  end

  describe "the artefact is what the authored source builds" do
    test "rebuilding reproduces the committed bytes", ctx do
      assert ETCCAttribution.build() == ctx.enriched
    end

    test "the authored source carries only the six attributes B2b establishes", ctx do
      fields = ctx.authored |> Enum.flat_map(&Map.keys/1) |> MapSet.new()

      assert MapSet.equal?(
               fields,
               MapSet.new(~w(key leg leg_reason cg cg_basis tokens contradicts_oc))
             )
    end
  end

  describe "tokens are addresses under match-relation.md" do
    test "every oc:none/ token is state 3 — three parts, and no `/` in the native id", ctx do
      for row <- ctx.enriched["rows"], token <- row["tokens"], none_token?(token) do
        assert ["oc:none", _reason, _native] = String.split(token, "/")
      end
    end

    test "every state-1 token addresses a check in A1's frozen manifest", ctx do
      keys = manifest_keys()

      for row <- ctx.enriched["rows"], token <- row["tokens"], not none_token?(token) do
        assert MapSet.member?(keys, token),
               "#{row["key"]}: token #{token} does not resolve in docs/conformance/in-scope-2026-07-28.json"
      end
    end

    test "no oc:none/ token resolves as an OC key — the state-3 assertion", ctx do
      keys = manifest_keys()

      for row <- ctx.enriched["rows"], token <- row["tokens"], none_token?(token) do
        refute MapSet.member?(keys, token), "#{token} resolves, so it is not a declared non-match"
      end
    end
  end

  describe "a contradiction names what it contradicts" do
    test "every contradicts_oc addresses a check in A1's manifest", ctx do
      keys = manifest_keys()

      for row <- ctx.enriched["rows"], contra = row["contradicts_oc"], not is_nil(contra) do
        assert MapSet.member?(keys, contra["check"]),
               "#{row["key"]}: contradicts_oc names #{contra["check"]}, which does not resolve"

        assert is_binary(contra["note"]) and contra["note"] != ""
      end
    end

    test "HAZARD 3's worked case survives the join intact", ctx do
      # A member that asserts wire behaviour and DISAGREES with the official
      # suite is still a member. Excluding it would empty bucket 4a by
      # construction, so the row C1 and D4a need is asserted by name here.
      row =
        Enum.find(
          ctx.enriched["rows"],
          &(&1["key"] =~ "MCP.Server.DispatchTest" and &1["key"] =~ "initialize is removed")
        )

      assert row, "dispatch_test's `initialize` member is missing from the enriched register"
      assert row["leg"] == "server"
      assert row["contradicts_oc"]["check"] =~ "404-initialize"
    end
  end

  defp none_token?(token), do: String.starts_with?(token, "oc:none/")

  defp manifest_keys do
    "docs/conformance/in-scope-2026-07-28.json"
    |> read()
    |> Map.fetch!("scenarios")
    |> Enum.flat_map(& &1["checks"])
    |> MapSet.new(fn check ->
      [leg, scenario, check_id, name | _] = check["key"]
      "oc:#{leg}/#{scenario}/#{check_id}/#{name}"
    end)
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()
end
