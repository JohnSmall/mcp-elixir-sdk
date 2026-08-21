defmodule MCP.Conformance.RequirementSetTest do
  @moduledoc """
  Controls for the denominator parser.

  The parser's whole value is that it can be **falsified**: it reads the frozen
  set twice, from the file and from the harness's own listing of the file, and
  refuses if the two disagree. So the tests come in the same shape as the
  adjudicator's — every refusal is paired with the corrected input it must
  accept, because a parser that refused everything would satisfy the refusal
  half on its own.

  One test reads the **real installed harness** when it is present. A parser
  verified only against fixtures I wrote is a parser verified against my own
  understanding of the format; the fixtures pin the behaviour and the real file
  pins the format.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.{RequirementSet, TestHarness}

  @yaml """
  # A leading comment.

  server:
    - tools-list
    - resources-list

  client:
    - tools_call

  not_scored:
    - scenario: tasks-lifecycle
      leg: server
      reason: extension
      note: >-
        a folded note spanning
        two lines
    - scenario: json-schema-2020-12
      leg: server
      reason: pending
    - scenario: auth/dpop
      leg: client
      reason: extension
  """

  @expected """
  Required for 2026-07-28 (3 scenarios, frozen; run at the 2026-07-28 wire):

  Server scenarios (test against a server):
    - tools-list
    - resources-list

  Client scenarios (test against a client):
    - tools_call

  Run and reported, but never scored:
    extension (2):
      - tasks-lifecycle [server]
      - auth/dpop [client]
    pending (1):
      - json-schema-2020-12 [server]
  """

  describe "parse/2 — the two derivations agreeing" do
    test "reads both and returns the set" do
      assert {:ok, set} = RequirementSet.parse(@yaml, @expected)

      assert set.scored == %{
               "server" => ["tools-list", "resources-list"],
               "client" => ["tools_call"]
             }

      assert length(set.not_scored) == 3
    end

    test "carries the HARNESS's reason, not one of ours" do
      {:ok, set} = RequirementSet.parse(@yaml, @expected)

      assert RequirementSet.harness_reason(set, "tasks-lifecycle") == "extension"
      assert RequirementSet.harness_reason(set, "json-schema-2020-12") == "pending"
      assert RequirementSet.harness_reason(set, "tools-list") == nil
    end

    test "the folded note is consumed and never mistaken for a field" do
      {:ok, set} = RequirementSet.parse(@yaml, @expected)
      entry = Enum.find(set.not_scored, &(&1.scenario == "tasks-lifecycle"))

      assert entry == %{scenario: "tasks-lifecycle", leg: "server", reason: "extension"}
    end
  end

  describe "parse/2 — the cross-check is the point, so it must actually fire" do
    test "refuses when the listing scores a scenario the frozen file does not" do
      diverged = String.replace(@expected, "  - tools_call", "  - tools_call\n  - sneaked-in")

      assert {:error, why} = RequirementSet.parse(@yaml, diverged)
      assert why =~ "disagree"
      assert why =~ "sneaked-in"

      assert {:ok, _} = RequirementSet.parse(@yaml, @expected)
    end

    test "refuses when the two disagree about a not-scored REASON" do
      diverged = String.replace(@yaml, "    reason: pending", "    reason: extension")

      assert {:error, why} = RequirementSet.parse(diverged, @expected)
      assert why =~ "not_scored"

      assert {:ok, _} = RequirementSet.parse(@yaml, @expected)
    end

    test "refuses when the two disagree about a not-scored scenario's LEG" do
      diverged =
        String.replace(
          @yaml,
          "  - scenario: auth/dpop\n    leg: client",
          "  - scenario: auth/dpop\n    leg: server"
        )

      assert {:error, _} = RequirementSet.parse(diverged, @expected)
      assert {:ok, _} = RequirementSet.parse(@yaml, @expected)
    end

    test "ORDER is not a disagreement: the two group their not-scored entries differently" do
      reordered = """
      Required for 2026-07-28 (3 scenarios, frozen; run at the 2026-07-28 wire):

      Client scenarios (test against a client):
        - tools_call

      Server scenarios (test against a server):
        - resources-list
        - tools-list

      Run and reported, but never scored:
        pending (1):
          - json-schema-2020-12 [server]
        extension (2):
          - auth/dpop [client]
          - tasks-lifecycle [server]
      """

      assert {:ok, _} = RequirementSet.parse(@yaml, reordered),
             "the yaml groups by scenario and the listing by reason; requiring the same " <>
               "order would refuse every healthy run"
    end
  end

  # MES-56 correction round 2. Every denominator here is a LIST and every
  # membership test taken against it is a SET, so multiplicity survives the
  # counts and dies in the comparisons. Measured before it was guarded: with
  # `resources-list` listed twice, an accepted run reported
  # `expected_counts.scored = 2` over a one-scenario set with `absentees.scored
  # = []` — the AC2 denominator vouching for a total it had inflated itself.
  describe "parse/2 — a denominator may not be ambiguous" do
    test "REFUSES a scored scenario listed twice under one leg, in EITHER derivation" do
      dup = fn body, leg_line, id ->
        String.replace(
          body,
          leg_line <> "\n  - " <> id,
          leg_line <> "\n  - " <> id <> "\n  - " <> id
        )
      end

      yaml = dup.(@yaml, "server:", "tools-list")
      expected = dup.(@expected, "Server scenarios (test against a server):", "tools-list")

      # Ours, and the harness's own listing: a repeat in either makes the
      # denominator equally unusable, so both derivations are checked.
      assert {:error, ours} = RequirementSet.parse(yaml, expected)
      assert ours =~ "the frozen set"
      assert ours =~ ~s(server: "tools-list" x2)
      assert ours =~ "inflates the denominator"

      assert {:error, theirs} = RequirementSet.parse(@yaml, expected)
      assert theirs =~ "the harness's own listing"
    end

    test "the yaml-vs-listing cross-check CANNOT catch it, which is why this gate exists" do
      # Both sides become MapSets before they are compared — deliberately, since
      # they differ in order by construction. A MapSet discards multiplicity as
      # well as order, so a repeat present in BOTH derivations agrees with
      # itself perfectly. Without the gate above this pair parses clean.
      dup = fn body, head, id ->
        String.replace(body, head <> "\n  - " <> id, head <> "\n  - " <> id <> "\n  - " <> id)
      end

      yaml = dup.(@yaml, "server:", "tools-list")
      expected = dup.(@expected, "Server scenarios (test against a server):", "tools-list")

      assert {:error, why} = RequirementSet.parse(yaml, expected)
      refute why =~ "disagree", "this must fail on multiplicity, not on the cross-check"
    end

    test "REFUSES a not-scored scenario listed twice, because harness_reason/2 takes the first" do
      yaml =
        String.replace(
          @yaml,
          "  - scenario: json-schema-2020-12\n    leg: server\n    reason: pending",
          "  - scenario: json-schema-2020-12\n    leg: server\n    reason: pending\n" <>
            "  - scenario: json-schema-2020-12\n    leg: server\n    reason: extension"
        )

      assert {:error, why} = RequirementSet.parse(yaml, @expected)
      assert why =~ ~s("json-schema-2020-12" x2)
      assert why =~ "FIRST match"
    end

    test "REFUSES a scenario that is both scored and not-scored for one leg" do
      yaml = String.replace(@yaml, "  - scenario: tasks-lifecycle", "  - scenario: tools-list")

      expected =
        String.replace(@expected, "    - tasks-lifecycle [server]", "    - tools-list [server]")

      assert {:error, why} = RequirementSet.parse(yaml, expected)
      assert why =~ ~s(server: "tools-list")
      assert why =~ "BOTH scored and not-scored"
    end

    test "does NOT refuse the same id scored on both legs — a bound it declines to claim" do
      # `scored` is keyed by leg and every reader takes Map.get(scored, leg), so
      # cross-leg repetition is well defined. The real 2026-07-28 set has no
      # such id, so a rule against it would be untested as well as unwarranted.
      yaml =
        String.replace(
          @yaml,
          "client:\n  - tools_call",
          "client:\n  - tools_call\n  - tools-list"
        )

      expected =
        String.replace(
          @expected,
          "Client scenarios (test against a client):\n  - tools_call",
          "Client scenarios (test against a client):\n  - tools_call\n  - tools-list"
        )

      assert {:ok, set} = RequirementSet.parse(yaml, expected)
      assert set.scored["server"] == ["tools-list", "resources-list"]
      assert set.scored["client"] == ["tools_call", "tools-list"]
    end

    test "the accept half: the unmodified pair still parses" do
      assert {:ok, _} = RequirementSet.parse(@yaml, @expected)
    end
  end

  describe "parse/2 — a line it does not recognise is never skipped" do
    test "refuses an unparseable entry under a leg key rather than dropping it" do
      broken = String.replace(@yaml, "- resources-list", "~ resources-list")

      assert {:error, why} = RequirementSet.parse(broken, @expected)
      assert why =~ "not a scenario id"
    end

    test "refuses a not_scored entry missing its reason" do
      broken = String.replace(@yaml, "    reason: pending\n", "")

      assert {:error, why} = RequirementSet.parse(broken, @expected)
      assert why =~ "missing leg or reason"
    end

    test "refuses a frozen set with no client key at all" do
      broken = String.replace(@yaml, "client:\n  - tools_call\n", "")

      assert {:error, why} = RequirementSet.parse(broken, @expected)
      assert why =~ "no client"
    end

    # Found by dialyzer, not by a test: this path returned `{:cont, {:error, _}}`,
    # which handed the NEXT line an accumulator no clause matches — so a parse
    # error became a FunctionClauseError one line later. Every error path halts.
    test "refuses a field that appears before any scenario, without crashing" do
      broken = """
      server:
        - tools-list

      client:
        - tools_call

      not_scored:
          leg: server
          reason: extension
      """

      assert {:error, why} = RequirementSet.parse(broken, @expected)
      assert why =~ "before any"
    end

    test "refuses a listing that is not a listing" do
      assert {:error, _} = RequirementSet.parse(@yaml, "command not found: conformance\n")
    end
  end

  describe "diff/3 — absentees are NAMED (A2d)" do
    setup do
      {:ok, set} = RequirementSet.parse(@yaml, @expected)
      %{set: set}
    end

    test "a complete run has nothing missing", %{set: set} do
      ran = ["tools-list", "resources-list", "tasks-lifecycle", "json-schema-2020-12"]

      assert RequirementSet.diff(set, "server", ran) ==
               %{missing_scored: [], missing_not_scored: [], unexpected: []}
    end

    test "names the scored absentee rather than counting it", %{set: set} do
      diff =
        RequirementSet.diff(set, "server", [
          "tools-list",
          "tasks-lifecycle",
          "json-schema-2020-12"
        ])

      assert diff.missing_scored == ["resources-list"]
      assert diff.missing_not_scored == []
    end

    test "separates a not-scored absentee from a scored one", %{set: set} do
      diff = RequirementSet.diff(set, "server", ["tools-list", "resources-list"])

      assert diff.missing_scored == []
      assert diff.missing_not_scored == ["json-schema-2020-12", "tasks-lifecycle"]
    end

    test "reports a scenario that ran and is outside the frozen set", %{set: set} do
      diff =
        RequirementSet.diff(set, "server", [
          "tools-list",
          "resources-list",
          "tasks-lifecycle",
          "json-schema-2020-12",
          "surprise"
        ])

      assert diff.unexpected == ["surprise"]
    end

    test "the other leg's scenarios are not this leg's denominator", %{set: set} do
      assert RequirementSet.expected_to_run(set, "client") ==
               %{scored: ["tools_call"], not_scored: ["auth/dpop"]}
    end
  end

  # A parser verified only against fixtures is verified against my reading of
  # the format. This reads the real thing.
  #
  # It used to skip INSIDE the test body when the harness was absent, which read
  # as green. The precondition is now a tag: a host without `node` or without the
  # pinned harness reports this EXCLUDED, with the reason printed by
  # test_helper.exs and the excluded count as evidence. The live call itself is
  # deliberately kept — a recorded fixture would compare this parser against
  # itself, and two independent derivations is the whole property.
  describe "the real installed harness" do
    @tag :requires_live_harness
    test "the frozen 2026-07-28 set parses, and both derivations agree" do
      assert {:ok, set} =
               RequirementSet.parse(
                 File.read!(TestHarness.requirements_yaml()),
                 TestHarness.listing!()
               )

      assert length(set.scored["server"]) == 37
      assert length(set.scored["client"]) == 32
      assert length(set.not_scored) == 20

      by_reason = Enum.frequencies_by(set.not_scored, & &1.reason)
      assert by_reason == %{"extension" => 16, "pending" => 3, "added-after-release" => 1}
    end
  end
end
