defmodule MCP.Conformance.ClassificationTest do
  @moduledoc """
  The classification table is data, so these are the properties data has to
  hold. The *enforcement* — that a non-pass must have an entry and a pass must
  not — lives in `MCP.Conformance.CensusTest`, because it is the census's job.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.{Classification, RequirementSet, TestHarness}

  # MES-63. The censuses committed at the time of writing. See
  # `classify_glob_matches/0` below for why this is the floor and not the rule.
  @committed_censuses [
    "client-2026-07-28-null-connect.json",
    "client-2026-07-28-null-exit0.json",
    "client-2026-07-28-null-request.json",
    "client-2026-07-28-probe-strict-connect.json",
    "client-2026-07-28.json",
    "server-2026-07-28-null-control.json",
    "server-2026-07-28.json"
  ]

  describe "the vocabulary" do
    test "the six classes are the six the ticket names, and no others" do
      assert Enum.sort(Classification.classes()) ==
               Enum.sort([
                 :added_after_release,
                 :by_design_2025_11_25,
                 :extension,
                 :out_of_scope_adr_003,
                 :pending,
                 :real_gap
               ])
    end

    test "three of them restate the harness's own reason rather than our judgement" do
      assert Enum.sort(Classification.harness_classes()) ==
               Enum.sort([:added_after_release, :extension, :pending])
    end

    # Read from the REAL frozen set, so a reason the harness invents fails here
    # rather than being filed silently as a gap. The `if File.exists?` guard this
    # used to carry made the test pass on a host with no harness — a check that
    # passed because it could not see. The precondition is a tag now, so a host
    # that cannot run it reports it EXCLUDED with a reason (see test_helper.exs).
    @tag :requires_live_harness
    test "every reason the frozen set can carry maps to a class" do
      {:ok, set} =
        RequirementSet.parse(File.read!(TestHarness.requirements_yaml()), TestHarness.listing!())

      unmapped =
        set.not_scored
        |> Enum.map(& &1.reason)
        |> Enum.uniq()
        |> Enum.reject(&Classification.class_for_harness_reason/1)

      assert unmapped == [],
             "the frozen set carries reasons this module does not know: #{inspect(unmapped)}"
    end

    test "an unknown reason maps to nothing rather than to a default" do
      assert Classification.class_for_harness_reason("something-new") == nil
    end
  end

  # MES-56 correction round 2, from the same mechanical question that found B2:
  # the table is three sources merged, and `Map.merge/2` resolves a collision
  # silently in favour of its second argument. A scenario named both by us and
  # by the harness's own reason would lose its `:real_gap` entry — owned, inside
  # ADR-003's denominator — to an `:extension` entry that says failing it costs
  # nothing. The module refuses to compile on a collision; this is the property
  # that refusal protects, asserted where a reader will look for it.
  describe "the table is a merge, so it must not lose an entry to one" do
    test "every scenario we classify ourselves survives the merge as ours" do
      ours = %{
        "server-stateless" => :real_gap,
        "input-required-result-non-tool-request" => :real_gap
      }

      for {id, class} <- ours do
        assert %{class: ^class} = Classification.fetch(id),
               "#{id} is classified by us and the merged table does not say so"
      end
    end

    test "the merged table holds every entry its four sources contribute" do
      # SERVER: 2 ours + 9 extension + 2 pending = 13.
      # CLIENT (MES-57): 24 out_of_scope_adr_003 + 6 extension = 30.
      # A collision cannot change this number in the safe direction: any overlap
      # makes the table SMALLER, so a count is a sufficient oracle here even
      # though a count usually is not.
      assert map_size(Classification.table()) == 43

      by_class = Enum.frequencies_by(Map.values(Classification.table()), & &1.class)
      assert by_class == %{real_gap: 2, extension: 15, pending: 2, out_of_scope_adr_003: 24}
    end

    test "every scenario the CLIENT leg classifies survives the merge as ours" do
      # The direction the merge could lose: `@client_table` is merged BEFORE
      # `@harness_table`, so a client id also named by a harness source would be
      # silently overwritten. The compile-time collision guard makes that
      # impossible; this asserts the property that guard protects, at the two
      # ids where the two tables come closest to each other.
      assert %{class: :out_of_scope_adr_003} = Classification.fetch("auth/metadata-default")
      assert %{class: :extension} = Classification.fetch("auth/dpop")

      # And the both-ways half: the one auth scenario that PASSES must carry no
      # entry at all, or the census would refuse it as a rationale for something
      # that is not happening.
      assert Classification.fetch("auth/resource-mismatch") == nil
    end
  end

  describe "every entry in the table" do
    test "names a class this module recognises" do
      bad =
        for {id, entry} <- Classification.table(),
            entry.class not in Classification.classes(),
            do: {id, entry.class}

      assert bad == []
    end

    test "carries a non-empty why and a non-empty owner" do
      thin =
        for {id, entry} <- Classification.table(),
            entry.why in [nil, ""] or entry.owner in [nil, ""],
            do: id

      assert thin == [],
             "a classification without a reason or an owner is a label, not a judgement: " <>
               inspect(thin)
    end

    @tag :requires_live_harness
    test "names a scenario the frozen 2026-07-28 set actually contains" do
      {:ok, set} =
        RequirementSet.parse(File.read!(TestHarness.requirements_yaml()), TestHarness.listing!())

      known =
        MapSet.new(
          Map.get(set.scored, "server", []) ++
            Map.get(set.scored, "client", []) ++
            Enum.map(set.not_scored, & &1.scenario)
        )

      strays = Classification.table() |> Map.keys() |> Enum.reject(&MapSet.member?(known, &1))

      assert strays == [],
             "these classifications name scenarios the frozen set does not: #{inspect(strays)}"
    end
  end

  describe "the committed censuses carry THIS table's reasons, not an edited copy" do
    # The JSON counterpart of `CensusMarkdownTest`'s "each renders byte-identically
    # from its own census". That one catches a hand-edited .md; nothing caught a
    # hand-edited .json, and MES-57 round 4 was a correction to a reason string
    # that is rendered into five of them — where the tempting shortcut is to patch
    # the artefacts and leave the table.
    #
    # What this proves and what it does NOT. It proves the committed classification
    # blocks were DERIVED from this module: change the table without regenerating,
    # or edit an artefact by hand, and it fails. It proves nothing about whether a
    # reason is TRUE — round 4's defect was a false claim faithfully copied into
    # every artefact, and this test would have been green throughout. Only a reader
    # catches that, which is why S5-24 is a register entry and not a test.
    test "every census in docs/conformance is recognised as one" do
      {censuses, malformed, skipped} = classify_glob_matches()

      assert malformed == [],
             "these files claim to be censuses (they carry census_schema_version) but do " <>
               "not have a top-level \"scenarios\" list — a file claiming to be a census is " <>
               "held to the census contract: #{inspect(malformed)}"

      # The FLOOR, and it is deliberately not the selection. The marker above
      # over-covers safely: a census added later is picked up with no edit here.
      # This list under-covers safely: it can only ever complain that something
      # known has stopped being recognised. MES-63 — neither alone is enough, so
      # the two are used together, and they fail in opposite directions.
      missing = @committed_censuses -- Enum.map(censuses, fn {basename, _} -> basename end)

      assert missing == [],
             "these committed censuses are no longer recognised as censuses — did one lose " <>
               "its census_schema_version marker? A census that stops being detected is " <>
               "silently no longer checked: #{inspect(missing)}. Skipped as non-censuses " <>
               "this run: #{inspect(skipped)}"
    end

    test "every classification block equals what Classification.fetch/1 returns" do
      {censuses, _malformed, _skipped} = classify_glob_matches()

      # Split into two passes deliberately. An assignment clause in a comprehension
      # acts as a FILTER, so writing `entry = Classification.fetch(id)` inline meant
      # a block naming an id the table does not know REMOVED its own row and the
      # census came back clean — a malformed census, silently skipped (MES-63).
      blocks =
        for {basename, scenarios} <- censuses,
            scenario <- scenarios,
            block = scenario["classification"],
            block != nil,
            do: {basename, scenario["id"], block}

      unknown = for {b, id, _} <- blocks, Classification.fetch(id) == nil, do: {b, id}

      assert unknown == [],
             "these committed classification blocks name scenario ids this table does not " <>
               "carry, so nothing checked them — a classification for an unknown scenario " <>
               "is not a passing check, it is an unasked question: #{inspect(Enum.uniq(unknown))}"

      drift =
        for {basename, id, block} <- blocks,
            entry = Classification.fetch(id),
            entry != nil,
            expected = %{
              "class" => to_string(entry.class),
              "why" => entry.why,
              "owner" => entry.owner
            },
            block != expected,
            do: {basename, id}

      assert drift == [],
             "these committed classification blocks are not what this table says today — " <>
               "regenerate the census, do not edit the artefact: #{inspect(Enum.uniq(drift))}"
    end
  end

  # MES-63. The glob is a LOCATION claim and location claims are weak: the first
  # non-census JSON dropped into docs/conformance raised KeyError before the test
  # could assert anything. Selection is by the census's own marker instead, and
  # every match lands in exactly one of three NAMED outcomes — none of them a crash,
  # and none of them a silent skip of something claiming to be a census.
  #
  # Rejected: keying on a top-level "scenarios" key (it classifies A1's in-scope
  # manifest AS a census and compares it against this table); an explicit filename
  # set as the whole rule (a later census not added to the list is never checked
  # and the suite stays green — the wrong failure direction, so it is the floor
  # above, not the selection); a census/ subdirectory (still a location claim, in
  # a smaller room, and it pushes discipline onto every future ticket — which is
  # the thing that just failed); a narrower glob (a tighter name claim is still a
  # name claim: it would close this instance and leave the class open).
  defp classify_glob_matches do
    docs = Path.expand("../../docs/conformance", __DIR__)

    Path.join(docs, "*-2026-07-28*.json")
    |> Path.wildcard()
    |> Enum.reduce({[], [], []}, fn path, {censuses, malformed, skipped} ->
      basename = Path.basename(path)

      case path |> File.read!() |> Jason.decode!() do
        %{"census_schema_version" => v, "scenarios" => scenarios}
        when is_integer(v) and is_list(scenarios) ->
          {censuses ++ [{basename, scenarios}], malformed, skipped}

        %{"census_schema_version" => _} ->
          {censuses, malformed ++ [basename], skipped}

        _ ->
          {censuses, malformed, skipped ++ [basename]}
      end
    end)
  end
end
