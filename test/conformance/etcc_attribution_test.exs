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

  ## MES-113 — the PROSE joins the exception, and why it had to

  This file guarded the artefact and nothing guarded the prose ABOUT it, so
  `etcc_attribution_controls.exs figures` — the only instrument over
  `etcc-attribution.md` — was red on `main` from 2026-08-24 to 2026-09-24 and
  no gate or sweep saw it. It is a `mix run` script: gate 5 does not reach it
  and the end-of-sprint sweep set is dependency / boundary-liveness /
  publication. A control nothing runs is a control whose red nobody sees.

  So the enumeration predicate is driven from HERE as well, over the committed
  artefacts. The cost is two file reads, a JSON parse and a set compare —
  neither the gate-6 cadence argument (network-dependent, side-effecting) nor
  the boundary-sweep one (25–30 minutes) transfers, and the rot is caused at
  TICKET granularity: MES-84 inserted `@tag :etcc` lines and moved 738
  citations, which a sprint-boundary check would catch up to a sprint late and
  land on whoever ran the sweep. Guard 29 — the same rot class on the sibling
  document — is already in gate 5 as `etcc_citations_test.exs`; this closes the
  gap rather than opening an exception.

  **The tax, stated because it is real and recurring:** a future ticket that
  inserts a line above a cited ET-CC test now goes RED here and must re-address
  the prose. That is the price of addressing units by LINE at all, and its
  retirement — guard 29's row-key scheme, extended to this document — is
  MES-125, not this file.

  The control keeps the fixtures and the mutation mode
  (`etcc_attribution_controls.exs mutation`), which is the ratified split:
  control script for fixtures and mutation, gate-5 test for decision logic.
  """
  use ExUnit.Case, async: true

  alias MCP.Conformance.AttributionCitations
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

  describe "MES-113 — per-item enumeration of the prose, in gate 5" do
    setup do
      %{prose: File.read!(ETCCAttribution.paths().prose)}
    end

    test "every counted member is cited at its own address in its own section", ctx do
      report = AttributionCitations.audit(ctx.prose, ctx.register, ctx.enriched)

      uncited = for p <- report.populations, p.missing != [], do: {p.label, p.missing}

      assert uncited == [], """
      A counted population has members cited nowhere in the section that
      enumerates it, so the count has no per-item backing (epic ruling 4):

        #{inspect(uncited, pretty: true)}
      """
    end

    test "an enumerating section cites NOTHING but its own members", ctx do
      report = AttributionCitations.audit(ctx.prose, ctx.register, ctx.enriched)

      extra = for s <- report.sections, s.extra != [], do: {s.section, s.extra}

      assert extra == [], """
      A section that enumerates a population cites an address that is not one of
      its members and is not declared in `non_member_citations/0`. A containment
      check cannot report this, which is how a citation that had drifted onto
      ANOTHER live member's address read true for a month:

        #{inspect(extra, pretty: true)}
      """
    end

    test "the unresolvable bare `:NN` residual has not grown", ctx do
      report = AttributionCitations.audit(ctx.prose, ctx.register, ctx.enriched)

      assert report.unresolvable == report.unresolvable_recorded, """
      A bare `:NN` whose paragraph names no `.exs` cannot be resolved by the
      reader, and 37 of the 40 that existed were stale when MES-113 measured
      them. This is a RATCHET and not a check: it does not say the recorded
      #{report.unresolvable_recorded} are correct, only that a new one cannot
      arrive unnoticed. Found #{report.unresolvable}.
      """
    end

    test "a `:NN` after a non-`.exs` filename is that file's, and binds nothing" do
      # The superseded reader recognised only `.exs` names, so `connection.ex:3`
      # became a bare `:3` bound to the paragraph's `stdio_test.exs` — crediting
      # a citation nobody wrote, in a population the check then reported on.
      prose = "para\n\n`stdio_test.exs:28,50` and `connection.ex:3` names it\n"

      tokens = AttributionCitations.tokens(prose)

      assert Enum.filter(tokens, &(&1.kind == :exs)) |> Enum.map(& &1.line) == [28, 50]
      assert Enum.filter(tokens, &(&1.kind == :other)) |> Enum.map(& &1.line) == [3]
      refute Enum.any?(tokens, &(&1.kind == :exs and &1.line == 3))
    end

    test "a comma-run continuation still belongs to its paragraph's file" do
      # The narrow refusal above must not take the form §2.4 and §3.3 are
      # written in with it — refusing that would red the document rather than
      # check it.
      tokens = AttributionCitations.tokens("`header_mirror_test.exs:31`, `:133,205`\n")

      assert Enum.map(tokens, &{&1.kind, &1.file, &1.line}) == [
               {:exs, "header_mirror_test.exs", 31},
               {:exs, "header_mirror_test.exs", 133},
               {:exs, "header_mirror_test.exs", 205}
             ]
    end

    test "a bare run reaches no further than its own paragraph" do
      tokens = AttributionCitations.tokens("`header_mirror_test.exs:31`\n\n`:133`\n")

      assert Enum.map(tokens, &{&1.kind, &1.line}) == [{:exs, 31}, {:unresolvable, 133}]
    end

    test "every non-member citation carries a section and a reason" do
      for {{section, {file, line}}, reason} <- AttributionCitations.non_member_citations() do
        assert section =~ ~r/\A§\d/, "#{inspect(section)} is not a section anchor"
        assert String.ends_with?(file, ".exs")
        assert is_integer(line) and line > 0
        assert is_binary(reason) and reason != "", "#{section} #{file}:#{line} has no reason"
      end
    end

    test "an allowed address is allowed in ITS section only — the key is the occurrence", ctx do
      # MES-94's review falsified the first cut of guard 29's limb B by keying
      # on citation text alone: a live citation appended anywhere returned ok,
      # because the string was grandfathered somewhere else. That grandfathers
      # the STRING, not the occurrence. This drives the real audit to show the
      # same address is refused one section over.
      {{allowed_section, {file, line}}, _} =
        AttributionCitations.non_member_citations() |> Enum.sort() |> hd()

      other = Enum.find(["§2.4", "§3.3"], &(&1 != allowed_section))

      moved =
        String.replace(
          ctx.prose,
          "### #{other} ",
          "### #{other} `#{file}:#{line}` ",
          global: false
        )

      refute moved == ctx.prose, "the fixture did not reach #{other}'s heading"

      report = AttributionCitations.audit(moved, ctx.register, ctx.enriched)

      assert {other, [{file, line}]} in for(
               s <- report.sections,
               s.extra != [],
               do: {s.section, s.extra}
             ),
             "#{file}:#{line} is grandfathered in #{allowed_section} and must NOT be in #{other}"
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
