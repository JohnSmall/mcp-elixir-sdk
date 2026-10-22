defmodule MCP.Conformance.BoundarySweepRowsTest do
  @moduledoc """
  MES-208 (with MES-150 folded in): the sweep keys its red units off the formatter's
  ROWS, never off ExUnit's CLI failure headers, and GUARD 34 refuses any run whose rows
  do not account for every test.

  Until MES-208 the sweep parsed the transcript for failure headers. ExUnit pads the
  counter to width 3 (`with_counter/2`, `formatter.ex:719-729`), so from failure 100 on
  there is no leading space and the header pattern missed it. A `setup_all` failure
  prints a module header with no `test` in it at all, so its invalidated tests were
  never seen. Both drops were silent. The PO ruled (MES-208 `34141`) that every test is
  recorded, so the rows from `MCP.Conformance.ExUnitRows` are the measurement, and
  stdout is read only for ExUnit's own summary line, as the independent witness.

  `read_run/2` and `census/3` are pure, so every census kind is reachable here from a
  synthetic artefact in milliseconds. The real-suite limbs (the positive control and
  the `setup_all` plant) are `conformance/controls/etcc_boundary_sweep_controls.exs
  census-real` and `census-plant`.

  These units are under `test/conformance/`, so the §2.3(d) prefix keeps them out of
  every live count.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.BoundarySweep, as: Sweep
  alias MCP.Conformance.ExUnitRows, as: Rows

  @failing "MCP.FakeFailTest"
  @invalid "MCP.FakeInvalidTest"
  @passing "MCP.FakePassTest"

  # 120 failures (past the old 99 cap), 16 setup_all-invalidated tests and 30 passes.
  # Failures 1-11 share ONE declaration line, as a `for` comprehension's tests do, so
  # the unit key's multiplicity is exercised.
  defp rows do
    failed =
      for i <- 1..120 do
        line = if i <= 11, do: 7, else: 100 + i
        row(@failing, "test fails #{i}", "test/fake/fail_test.exs", line, "failed")
      end

    invalid =
      for i <- 1..16,
          do: row(@invalid, "test invalid #{i}", "test/fake/invalid_test.exs", 20 + i, "invalid")

    passed =
      for i <- 1..30,
          do: row(@passing, "test passes #{i}", "test/fake/pass_test.exs", 10 + i, "passed")

    failed ++ invalid ++ passed
  end

  defp row(module, name, file, line, status) do
    %{
      "key" => module <> "/" <> name,
      "module" => module,
      "name" => name,
      "test_type" => "test",
      "file" => file,
      "line" => line,
      "status" => status
    }
  end

  defp artefact(rows, run_overrides \\ %{}) do
    run =
      Map.merge(
        %{
          "complete" => true,
          "key_collisions" => [],
          "module_cross_check" => %{"disagreements" => []}
        },
        run_overrides
      )

    Rows.artefact(rows, run)
  end

  @summary "0 doctests, 166 tests, 120 failures, 16 invalid"

  defp transcript(summary \\ @summary, extra \\ "") do
    "Running ExUnit with seed: 0, max_cases: 64\n" <>
      extra <> "\nFinished in 1.0 seconds\n" <> summary <> "\n"
  end

  defp coloured(text), do: IO.ANSI.red() <> text <> IO.ANSI.reset()

  defp kinds(violations), do: violations |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  describe "read_run/2 — every red row is a unit" do
    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "120 failures and 16 invalid are all keyed — no cap at 99, no silent invalid" do
      run = Sweep.read_run(transcript(), artefact(rows()))

      assert length(run.units) == 136
      assert run.unlocated == 0
      assert run.rows_total == 166
      assert run.summary == @summary
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "the unit key is FILE:LINE (MODULE), with multiplicity kept" do
      units = Sweep.read_run(transcript(), artefact(rows())).units

      assert Enum.count(units, &(&1 == "test/fake/fail_test.exs:7 (#{@failing})")) == 11
      assert "test/fake/fail_test.exs:220 (#{@failing})" in units
      assert "test/fake/invalid_test.exs:36 (#{@invalid})" in units
      refute Enum.any?(units, &String.contains?(&1, @passing))
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "counters 9/10, 99/100 and beyond carry no special case — nothing is parsed" do
      units = Sweep.read_run(transcript(), artefact(rows())).units

      for i <- [12, 99, 100, 101, 120],
          do: assert("test/fake/fail_test.exs:#{100 + i} (#{@failing})" in units)
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "a header-shaped line printed by a test keys nothing" do
      forged = "101) test printed by a test (Fake.Mod)\n  9) test also printed (Fake.Mod)"
      run = Sweep.read_run(transcript(@summary, forged), artefact(rows()))

      assert length(run.units) == 136
      refute Enum.any?(run.units, &String.contains?(&1, "Fake.Mod"))
      assert Sweep.census(transcript(@summary, forged), artefact(rows()), nil) == []
    end
  end

  describe "census/3 — GUARD 34, one plant per kind" do
    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "POSITIVE: an artefact that accounts for every test passes" do
      assert Sweep.census(transcript(), artefact(rows()), 166) == []
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "no_artefact: the formatter wrote nothing" do
      assert kinds(Sweep.census(transcript(), :missing, nil)) == [:no_artefact]
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "summary: a passed row dropped no longer reconciles with ExUnit's count" do
      dropped = Enum.reject(rows(), &(&1["name"] == "test passes 1"))
      assert :summary in kinds(Sweep.census(transcript(), artefact(dropped), nil))
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "summary: no summary line at all" do
      assert :summary in kinds(Sweep.census("no summary here\n", artefact(rows()), nil))
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "summary_count: a second summary-shaped line printed by a test" do
      forged = transcript(@summary, "1 doctest, 1 test, 0 failures")
      assert kinds(Sweep.census(forged, artefact(rows()), nil)) == [:summary_count]
    end

    # MES-208 correction round 1 (CR F1, `34182`). The reconciliation witness,
    # `ExUnitRows.parse_summary/1`, strips ANSI SGR escapes before it matches; a count
    # that did not would let a COLOURED forgery be read as the summary while the count
    # still saw exactly one.
    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "summary_count: a coloured summary printed by a test BEFORE the genuine one" do
      forged = transcript(@summary, coloured("1 doctest, 1 test, 0 failures"))
      assert kinds(Sweep.census(forged, artefact(rows()), nil)) == [:summary_count]
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "summary_count: a coloured summary printed AFTER the genuine one" do
      forged = transcript() <> coloured("1 doctest, 1 test, 0 failures") <> "\n"
      assert :summary_count in kinds(Sweep.census(forged, artefact(rows()), nil))
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "POSITIVE: a genuine summary that is itself coloured passes, and is recorded plain" do
      out = transcript(coloured(@summary))
      assert Sweep.census(out, artefact(rows()), 166) == []
      assert Sweep.read_run(out, artefact(rows())).summary == @summary
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "incomplete: modules started and finished disagree" do
      a = artefact(rows(), %{"complete" => false})
      assert kinds(Sweep.census(transcript(), a, nil)) == [:incomplete]
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "cross_check: the module_finished witness disagrees" do
      a =
        artefact(rows(), %{
          "module_cross_check" => %{
            "disagreements" => [%{"module" => @failing, "direction" => "missing_from_events"}]
          }
        })

      assert kinds(Sweep.census(transcript(), a, nil)) == [:cross_check]
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "cross_check: a run block that carries no cross-check refuses rather than passes" do
      a = artefact(rows(), %{"module_cross_check" => nil})
      assert kinds(Sweep.census(transcript(), a, nil)) == [:cross_check]
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "collision: two rows on one key" do
      [first | rest] = rows()
      twin = Map.put(hd(rest), "key", first["key"])
      a = artefact([first, twin | tl(rest)])
      assert :collision in kinds(Sweep.census(transcript(), a, nil))
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "unlocated: a red row with no line" do
      planted =
        Enum.map(rows(), fn
          %{"name" => "test fails 120"} = r -> Map.put(r, "line", nil)
          r -> r
        end)

      vs = Sweep.census(transcript(), artefact(planted), nil)
      assert :unlocated in kinds(vs)
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "population: a mutated run whose row total is not the baseline's" do
      assert kinds(Sweep.census(transcript(), artefact(rows()), 167)) == [:population]
    end

    @tag oc: :none
    @tag oc_reason:
           "instrument unit (boundary sweep read_run/census, GUARD 34); no OC counterpart"
    test "census!/3 raises one GUARD 34 line per violation, naming its kind" do
      err =
        assert_raise RuntimeError, fn ->
          Sweep.census!(transcript(), artefact(rows(), %{"complete" => false}), 167)
        end

      lines = String.split(err.message, "\n")
      assert Enum.any?(lines, &String.starts_with?(&1, "GUARD 34: incomplete"))
      assert Enum.any?(lines, &String.starts_with?(&1, "GUARD 34: population"))
    end
  end
end
