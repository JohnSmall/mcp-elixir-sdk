defmodule MCP.Conformance.ClassificationTest do
  @moduledoc """
  The classification table is data, so these are the properties data has to
  hold. The *enforcement* — that a non-pass must have an entry and a pass must
  not — lives in `MCP.Conformance.CensusTest`, because it is the census's job.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.{Classification, RequirementSet, TestHarness}

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

    test "the merged table holds every entry its three sources contribute" do
      # 2 ours + 9 extension + 2 pending. A collision cannot change this number
      # in the safe direction: any overlap makes the table SMALLER, so a count
      # is a sufficient oracle here even though a count usually is not.
      assert map_size(Classification.table()) == 13

      by_class = Enum.frequencies_by(Map.values(Classification.table()), & &1.class)
      assert by_class == %{real_gap: 2, extension: 9, pending: 2}
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
end
