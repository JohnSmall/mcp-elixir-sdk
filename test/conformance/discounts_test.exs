defmodule MCP.Conformance.DiscountsTest do
  @moduledoc """
  The headline figure's derivation.

  Every test here is over a hand-built census SHAPE rather than a run, because
  what is under test is the arithmetic of the subtractions and not the
  measurement. The measurement's own fidelity is `RunIndexTest`'s and the
  adjudicator's problem.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.{Adapters, Discounts}

  defp scenario(id, scored, pass) do
    %{
      "id" => id,
      "scored" => scored,
      "passes" => %{
        "server_summary_or_client_summary" => pass,
        # Deliberately the OPPOSITE, on every fixture. If anything in
        # `Discounts` ever reads `requirements_exit` instead of the leg's own
        # summary reducer, every assertion here inverts rather than drifting
        # quietly — which is the leg-dependence that made Sprint 4 quote two
        # different numbers for one run.
        "requirements_exit" => not pass,
        "client_summary" => pass
      }
    }
  end

  defp census(role, scenarios, passed \\ 0) do
    %{
      "run" => %{
        "role" => role,
        "commit" => "abc123",
        "harness_version_reported" => "0.2.0-alpha.11",
        "requirements_revision" => "2026-07-28"
      },
      "scenarios" => scenarios,
      "totals" => %{
        "by_reducer" => %{
          "client_summary" => %{"scored" => %{"passed" => passed, "total" => 32}}
        }
      }
    }
  end

  # Seven in-scope scenarios and two auth ones, one of which PASSES — the shape
  # the real run has, and the shape that catches a table-driven in-scope
  # derivation.
  defp measurement do
    census(
      "measurement",
      [
        scenario("tools_call", true, true),
        scenario("request-metadata", true, true),
        scenario("sep-2322-client-request-state", true, true),
        scenario("http-standard-headers", true, true),
        scenario("http-custom-headers", true, true),
        scenario("http-invalid-tool-headers", true, true),
        scenario("json-schema-ref-no-deref", true, true),
        scenario("auth/resource-mismatch", true, true),
        scenario("auth/dpop-nonce", true, false),
        scenario("json-schema-2020-12-preservation", false, true)
      ]
    )
  end

  defp weak_null do
    census(
      "control",
      [
        scenario("http-standard-headers", true, true),
        scenario("auth/resource-mismatch", true, true),
        scenario("tools_call", true, false),
        scenario("request-metadata", true, false)
      ],
      2
    )
  end

  defp strict_null do
    census(
      "control",
      [
        scenario("http-standard-headers", true, false),
        scenario("auth/resource-mismatch", true, true),
        scenario("tools_call", true, false)
      ],
      1
    )
  end

  defp probe do
    census("probe", [scenario("request-metadata", true, false)])
  end

  defp derive(opts \\ []) do
    Discounts.derive(
      [
        measurement: measurement(),
        nulls: %{"weak" => weak_null(), "strict" => strict_null()},
        probe: probe(),
        probe_scope: ["request-metadata"]
      ]
      |> Keyword.merge(opts)
    )
  end

  describe "the in-scope denominator" do
    test "is the scored scenarios NOT in the auth/ namespace" do
      d = derive()

      assert length(d.in_scope) == 7
      refute Enum.any?(d.in_scope, &String.starts_with?(&1, "auth/"))
    end

    test "EXCLUDES a scored auth scenario that PASSES and carries no classification" do
      # The case a table-driven derivation gets wrong while looking right. The
      # census refuses a classification entry for a scenario that passes, so
      # `auth/resource-mismatch` has none — and "no entry" would read as
      # "nothing excludes it".
      d = derive()

      refute "auth/resource-mismatch" in d.in_scope
      assert "auth/resource-mismatch" in d.excluded_auth
      assert "auth/resource-mismatch" in d.raw.scored_passed
    end

    test "the raw figure exceeds the in-scope numerator by exactly the passing auth scenarios" do
      d = derive()

      assert length(d.raw.scored_passed) == 8
      assert length(d.as_driven) == 7
      assert d.raw.scored_passed -- d.as_driven == ["auth/resource-mismatch"]
    end

    test "a not-scored scenario is outside the denominator even when it passes" do
      d = derive()

      refute "json-schema-2020-12-preservation" in d.in_scope
      refute "json-schema-2020-12-preservation" in d.raw.scored_passed
    end
  end

  describe "the two discounts are separate subtractions over DIFFERENT sets" do
    test "each removes one scenario, and they are not the same scenario" do
      d = derive()

      assert d.drive_policy_removed == ["request-metadata"]
      assert d.null_passable_removed == ["http-standard-headers"]

      # The whole reason the intermediate rows are published. Two "6 of 7"s that
      # are not the same 6.
      assert length(d.after_drive_policy) == 6
      assert length(d.after_null_passable) == 6
      assert d.after_drive_policy != d.after_null_passable
    end

    test "surviving BOTH is 5 of 7, and is named rather than counted" do
      d = derive()

      assert length(d.surviving_both) == 5

      assert d.surviving_both == [
               "http-custom-headers",
               "http-invalid-tool-headers",
               "json-schema-ref-no-deref",
               "sep-2322-client-request-state",
               "tools_call"
             ]
    end

    test "with no probe, the drive-policy discount is EMPTY and not silently zero-effect" do
      d = derive(probe: nil, probe_scope: nil)

      assert d.drive_policy_removed == []
      assert d.probe_scope == []
      assert length(d.after_drive_policy) == 7
    end
  end

  describe "null-passable takes the UNION, because a stricter null scores lower" do
    test "a scenario only the WEAK null passes is still subtracted" do
      d = derive()

      # `http-standard-headers` passes under the weak null and FAILS under the
      # strict one. Taking the union is the reading least flattering to the SDK;
      # taking only the strict null would have published 6 of 7.
      assert "http-standard-headers" in d.null_passable_removed
      assert "http-standard-headers" in d.per_null["weak"].passed_in_scope
      refute "http-standard-headers" in d.per_null["strict"].passed_in_scope
    end

    test "each null is reported separately so the choice is visible" do
      d = derive()

      assert d.per_null["weak"].scored == %{"passed" => 2, "total" => 32}
      assert d.per_null["strict"].scored == %{"passed" => 1, "total" => 32}
    end

    test "a null that passes nothing in scope subtracts nothing" do
      d = derive(nulls: %{"strict" => strict_null()})

      assert d.null_passable_removed == []
      assert length(d.surviving_both) == 6
    end
  end

  describe "the probe's SCOPE, which is the difference between 5 of 7 and 0 of 7" do
    test "a probe with no scope is REFUSED rather than read as a wide instrument" do
      # Measured before it was guarded: the probe drives one scenario and takes
      # the not-driven path for the other 38, so reading its whole sheet
      # subtracted 6 of 7 and reported "0 of 7" — a catastrophic-looking headline
      # manufactured entirely by reading a narrow instrument as a wide one.
      assert_raise ArgumentError, ~r/without an explicit :probe_scope/, fn ->
        derive(probe_scope: nil)
      end

      assert_raise ArgumentError, ~r/without an explicit :probe_scope/, fn ->
        derive(probe_scope: :all)
      end
    end

    test "outside its scope the probe says nothing, and nothing is not failure" do
      # `tools_call` is absent from the probe census entirely. Under a scoped
      # read that is silence; under an unscoped one it would be a failure.
      d = derive()

      assert "tools_call" in d.surviving_both
      refute "tools_call" in d.drive_policy_removed
      refute Map.has_key?(d.probe, "tools_call")
    end

    test "the scope comes from the registry the probe itself reads" do
      # One declaration, two consumers. If these ever diverge, the probe drives
      # one set and the derivation interprets another.
      assert Adapters.scope(:client, "strict_connect") == ["request-metadata"]
      assert Adapters.role(:client, "strict_connect") == :probe
      assert Adapters.scope(:client, "sdk") == :all
    end
  end

  describe "the rendered Markdown is a projection of the derivation" do
    test "every figure in the table comes from the derived sets" do
      d = derive()
      md = Discounts.to_markdown(d, measurement()["run"])

      assert md =~ "| as driven | **7 of 7** |"
      assert md =~ "| after drive-policy only | **6 of 7** |"
      assert md =~ "| after null-passable only | **6 of 7** |"
      assert md =~ "| **surviving BOTH** | **5 of 7** |"
      assert md =~ "`request-metadata`"
      assert md =~ "`http-standard-headers`"
    end

    test "the raw rate never appears without the exclusion beside it" do
      md = Discounts.to_markdown(derive(), measurement()["run"])

      # 9 scored scenarios in this fixture, not the real run's 32: the shape is
      # under test, not the measurement.
      assert md =~ "**8 of 9**"
      assert md =~ "ADR-003"
      assert md =~ "never as a bare pass rate"
      assert md =~ "`auth/resource-mismatch`"
    end

    test "the probe section shows only the scenarios the probe drove" do
      md = Discounts.to_markdown(derive(), measurement()["run"])

      assert md =~ "| `request-metadata` | PASS | FAIL |"
      refute md =~ "| `tools_call` | PASS |"
    end
  end
end
