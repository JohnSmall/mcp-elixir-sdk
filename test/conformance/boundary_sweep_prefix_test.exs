defmodule MCP.Conformance.BoundarySweepPrefixTest do
  @moduledoc """
  The live column's directory exclusion — `etcc-membership.md` §2.3(d) as amended on
  MES-137, `[authored 29618 | ratified 29619]` — unit by unit.

  `excluded_by_prefix?/2` and `live_column_prefixes!/1` are pure, so both directions of
  the rule are reachable here cheaply: a unit under the directory IS excluded, and a unit
  outside it — including one in a sibling directory whose name merely shares the prefix —
  is NOT. A predicate that excluded everything would pass the first half and fail the
  second; one that excluded nothing would do the reverse.

  The end-to-end limbs — the three real units excluded at the tip, and removing the
  prefix bringing the `Error (encode)` drift back — need the suite run under a mutation,
  so they are `conformance/controls/etcc_boundary_sweep_controls.exs prefix`, not units.

  These units are themselves under `test/conformance/`, so the rule they test keeps them
  out of every live count.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.BoundarySweep, as: Sweep

  @prefixes ["test/conformance/"]

  describe "excluded_by_prefix?/2" do
    test "a unit under test/conformance/ is excluded — the unit MES-137 found" do
      assert Sweep.excluded_by_prefix?(
               "test/conformance/adjudications_test.exs:1715 (MCP.Conformance.AdjudicationsTest)",
               @prefixes
             )
    end

    test "a unit under test/mcp/ is kept" do
      refute Sweep.excluded_by_prefix?(
               "test/mcp/integration_test.exs:128 (MCP.IntegrationTest)",
               @prefixes
             )
    end

    test "a sibling directory sharing the prefix's letters is kept" do
      refute Sweep.excluded_by_prefix?(
               "test/conformance_x/foo_test.exs:1 (Foo)",
               @prefixes
             )
    end

    test "a file whose name starts like the directory is kept" do
      refute Sweep.excluded_by_prefix?("test/conformance.exs:1 (Foo)", @prefixes)
    end

    test "no prefixes exclude nothing" do
      refute Sweep.excluded_by_prefix?(
               "test/conformance/adjudications_test.exs:1715 (MCP.Conformance.AdjudicationsTest)",
               []
             )
    end
  end

  describe "live_column_prefixes!/1" do
    test "reads the committed entries, and an absent key is no exclusion" do
      assert Sweep.live_column_prefixes!(%{"live_column_excluded_prefixes" => @prefixes}) ==
               @prefixes

      assert Sweep.live_column_prefixes!(%{}) == []
    end

    for bad <- ["test/conformance", "", "/", nil, 7] do
      test "refuses the entry #{inspect(bad)}, naming the rule" do
        assert_raise RuntimeError, ~r/REFUSING live_column_excluded_prefixes entry/, fn ->
          Sweep.live_column_prefixes!(%{
            "live_column_excluded_prefixes" => [unquote(Macro.escape(bad))]
          })
        end
      end
    end

    # The pin. The prefix set is data, and it is the only thing between a citation check
    # and a live verdict. Widening it silences L1 for every unit it newly covers, so a
    # change to it must be a change to this test too, which puts it in front of review.
    test "the committed prefix set is exactly [\"test/conformance/\"]" do
      doc = Sweep.paths().boundaries |> File.read!() |> Jason.decode!()
      assert Sweep.live_column_prefixes!(doc) == ["test/conformance/"]
    end
  end
end
