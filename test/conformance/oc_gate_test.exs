defmodule MCP.Conformance.OcGateTest do
  # Gate 7's judgement (MES-160), on synthesised check sheets keyed by the
  # ratified discriminator rule. None of these asserts SDK behaviour an OC check
  # measures, so each declares oc: :none.
  use ExUnit.Case, async: true

  alias MCP.Conformance.{HarnessHost, InScope, OcGate}
  alias MCP.Conformance.OcGateDeclarations, as: D

  @meta_id "sep-2575-http-server-meta-invalid-400"
  @meta "HttpServerMetaInvalid400"

  defp sheet do
    server =
      InScope.key_checks("server", "server-stateless", [
        %{"id" => "ok-1", "name" => "Fine", "description" => "d", "status" => "SUCCESS"},
        %{"id" => "red-1", "name" => "Red", "description" => "d", "status" => "FAILURE"},
        %{"id" => "warn-1", "name" => "Warn", "description" => "d", "status" => "WARNING"},
        %{"id" => "skip-1", "name" => "Skip", "description" => "d", "status" => "SKIPPED"},
        meta("missing-meta", "SUCCESS"),
        meta("missing-protocol-version", "FAILURE"),
        meta("missing-client-capabilities", "FAILURE")
      ])

    %{"server" => {:ok, %{rows: server, threw: %{"boom" => "it threw"}, run_dir: nil}}}
  end

  defp meta(issue, status) do
    %{
      "id" => @meta_id,
      "name" => @meta,
      "description" => "same",
      "status" => status,
      "details" => %{"fieldIssue" => issue}
    }
  end

  defp decl(oc, reason \\ {:absent}) do
    %{
      file: "test/x_test.exs",
      line: 1,
      describe: nil,
      name: "t",
      id: "t",
      change: :new,
      fingerprint: nil,
      oc: oc,
      oc_reason: reason,
      suite_level_oc: []
    }
  end

  defp judge(oc, measurements \\ sheet()) do
    [v] = OcGate.judge([decl({:literal, oc})], measurements)
    v
  end

  defp tok(check, name), do: "oc:server/server-stateless/#{check}/#{name}"

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "a token naming a SUCCESS check passes, and records the status" do
    v = judge(tok("ok-1", "Fine"))
    assert v.outcome == :pass
    assert [%{status: "SUCCESS", outcome: :pass}] = v.checks
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "FAILURE, WARNING and SKIPPED are all refused as not_success (Q1)" do
    for {id, name, status} <- [
          {"red-1", "Red", "FAILURE"},
          {"warn-1", "Warn", "WARNING"},
          {"skip-1", "Skip", "SKIPPED"}
        ] do
      v = judge(tok(id, name))
      assert {v.outcome, v.class} == {:refuse, :not_success}
      assert v.detail =~ "is #{status} in the live run"
    end
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "the three-row fieldIssue tie is refused as ambiguous, naming the discriminators" do
    v = judge(tok(@meta_id, @meta))
    assert {v.outcome, v.class} == {:refuse, :ambiguous}

    assert v.detail =~
             "matches 3 rows; add one of #missing-meta, #missing-protocol-version, #missing-client-capabilities"
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "a discriminated token resolves to its own row's status" do
    assert judge(tok(@meta_id, @meta <> "#missing-meta")).outcome == :pass
    v = judge(tok(@meta_id, @meta <> "#missing-protocol-version"))
    assert {v.outcome, v.class} == {:refuse, :not_success}

    v = judge(tok(@meta_id, @meta <> "#typo"))
    assert {v.outcome, v.class} == {:refuse, :unresolved}
    assert v.detail =~ "no row carries that discriminator; rows are #missing-meta"
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "a check the live run does not have is unresolved; a scenario it lacks, not observed" do
    assert %{outcome: :refuse, class: :unresolved} = judge(tok("nope", "Nope"))

    assert %{outcome: :refuse, class: :not_observed, detail: d} =
             judge("oc:server/absent-scenario/x/Y")

    assert d =~ "not in the live run"

    assert %{class: :not_observed, detail: "scenario boom threw: it threw"} =
             judge("oc:server/boom/x/Y")
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "a leg that could not be measured refuses every token that needed it" do
    for {class, m} <- [
          harness_unavailable: {:error, :harness_unavailable, "no node"},
          run_not_accepted: {:error, :run_not_accepted, "COMMIT_MISMATCH"}
        ] do
      v = judge(tok("ok-1", "Fine"), %{"server" => m})
      assert {v.outcome, v.class} == {:refuse, class}
    end

    assert %{class: :not_measured} = judge("oc:client/s/C/N")
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "a token list passes only when every named check is SUCCESS (Q4)" do
    assert judge([tok("ok-1", "Fine"), tok(@meta_id, @meta <> "#missing-meta")]).outcome == :pass

    v = judge([tok("ok-1", "Fine"), tok("red-1", "Red")])
    assert {v.outcome, v.class} == {:refuse, :not_success}
    assert Enum.map(v.checks, & &1.outcome) == [:pass, :not_success]
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "declared nones pass as none, and static refusals pass through unmeasured" do
    [none, untagged] =
      OcGate.judge([decl({:literal, :none}, {:literal, "why"}), decl({:absent})], %{})

    assert {none.outcome, none.detail} == {:none, "oc: none — why"}
    assert {untagged.outcome, untagged.class} == {:refuse, :untagged}
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "legs/1 names only the legs the check tokens need" do
    decls = [
      decl({:literal, ["oc:server/s/C/N", "oc:client/s/C/N"]}),
      decl({:literal, :none}, {:literal, "r"}),
      decl({:literal, "oc:none/slug/id"})
    ]

    assert OcGate.legs(decls) == ["client", "server"]
    assert OcGate.legs(Enum.drop(decls, 1)) == []
    assert D.classify(Enum.at(decls, 2)) == {:none, "slug"}
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "rows/3 keys every read scenario's checks.json and records thrown scenarios" do
    dir = Path.join(System.tmp_dir!(), "oc-gate-rows-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    File.mkdir_p!(Path.join(dir, "s1-ts"))

    File.write!(
      Path.join([dir, "s1-ts", "checks.json"]),
      Jason.encode!([
        meta("missing-meta", "SUCCESS"),
        meta("missing-protocol-version", "FAILURE")
      ])
    )

    census = %{
      "scenarios" => [
        %{"id" => "s1", "artefact_dir" => "s1-ts", "checks_source" => "artefacts"},
        %{
          "id" => "s2",
          "artefact_dir" => nil,
          "checks_source" => "console_thrown",
          "threw" => "x"
        }
      ]
    }

    got = OcGate.rows("server", dir, census)

    assert Enum.map(got.rows, & &1["discriminator"]) == [
             "missing-meta",
             "missing-protocol-version"
           ]

    assert got.threw == %{"s2" => "x"}
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "HarnessHost refuses an install root with no harness in it" do
    empty = Path.join(System.tmp_dir!(), "oc-gate-empty-#{System.unique_integer([:positive])}")
    reason = HarnessHost.unavailable_reason(empty)

    # On a host without node the first condition answers instead; either way it
    # is a reason, never nil.
    assert is_binary(reason)
    assert reason =~ "no harness at #{empty}" or reason =~ "no `node` on PATH"
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "the harness pin is one constant, shared with BucketZero's citation (B2)" do
    assert MCP.Conformance.BucketZero.harness().sha256 == HarnessHost.pinned_dist_sha256()
    assert MCP.Conformance.BucketZero.harness().version == HarnessHost.pinned_version()
    assert HarnessHost.pinned_dist_sha256() =~ ~r/\A[0-9a-f]{64}\z/
  end

  @tag oc: :none
  @tag oc_reason: "gate unit; no OC counterpart"
  test "a runner that raises, exits, throws or returns a wrong shape is an error, not a crash (N1, N5)" do
    assert OcGate.guard_runner(fn -> {:ok, %{}, "/run"} end) == {:ok, "/run"}
    assert {:error, "boom"} = OcGate.guard_runner(fn -> raise "boom" end)
    assert {:error, "exit: :gone"} = OcGate.guard_runner(fn -> exit(:gone) end)
    assert {:error, "throw: :up"} = OcGate.guard_runner(fn -> throw(:up) end)
    assert {:error, "no match of right hand side" <> _} = OcGate.guard_runner(fn -> :huh end)
  end
end
