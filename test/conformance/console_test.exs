defmodule MCP.Conformance.ConsoleTest do
  @moduledoc """
  Controls for the console parser — the only non-guessing key from a scenario to
  its artefact directory.

  The tests that matter here are the ones about what the parser **refuses**.
  A parser that returns a plausible mapping from a console it cannot actually
  read would mis-attribute results silently, and every per-scenario figure in
  MES-56, MES-57 and MES-58 is attributed through this map.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.Console

  @server """
  Running requirements 2026-07-28 (3 scenarios) against http://127.0.0.1:3001/mcp

  === Running scenario: tools-list ===
  Running client scenario 'tools-list' against server: http://127.0.0.1:3001/mcp
  Results saved to /tmp/run/server-tools-list-2026-08-21T00-00-00-000Z

  === Running scenario: tools-call-simple-text ===
  Results saved to /tmp/run/server-tools-call-simple-text-2026-08-21T00-00-01-000Z

  === Running scenario: tasks-lifecycle ===
  Results saved to /tmp/run/server-tasks-lifecycle-2026-08-21T00-00-02-000Z


  === SUMMARY ===
  ✓ tools-list: 5 passed, 0 failed
  ✗ tools-call-simple-text: 1 passed, 2 failed
  ✗ tasks-lifecycle: 1 passed, 8 failed

  Total: 7 passed, 10 failed

  Not scored for 2026-07-28: 1 scenario(s) run, 1 failing. These do not affect conformance.
    ✗ tasks-lifecycle (extension)
  """

  describe "the server leg" do
    test "maps every scenario to its artefact directory" do
      parsed = Console.parse(@server)

      assert Console.ran(parsed) == ["tools-list", "tools-call-simple-text", "tasks-lifecycle"]
      assert parsed.faults == []
    end

    test "relativises the directories so they can be compared with the disk walk" do
      parsed = Console.parse(@server)

      assert Console.dirs_relative(parsed, "/tmp/run") == [
               "server-tasks-lifecycle-2026-08-21T00-00-02-000Z",
               "server-tools-call-simple-text-2026-08-21T00-00-01-000Z",
               "server-tools-list-2026-08-21T00-00-00-000Z"
             ]
    end

    test "reads the harness's own per-scenario verdict, which is what we check ours against" do
      parsed = Console.parse(@server)

      assert Map.new(parsed.marks, &{&1.scenario, &1.pass}) == %{
               "tools-list" => true,
               "tools-call-simple-text" => false,
               "tasks-lifecycle" => false
             }
    end

    test "reads the scored/not-scored split, which exists nowhere in the artefact tree" do
      parsed = Console.parse(@server)

      assert parsed.not_scored == [
               %{scenario: "tasks-lifecycle", pass: false, reason: "extension"}
             ]
    end

    test "reads the check-level totals" do
      assert Console.parse(@server).totals == %{"passed" => 7, "failed" => 10}
    end
  end

  describe "faults — the parser must refuse rather than produce a plausible map" do
    test "a scenario announced and never saved is a fault, not a dropped row" do
      truncated =
        String.replace(
          @server,
          "Results saved to /tmp/run/server-tasks-lifecycle-2026-08-21T00-00-02-000Z\n",
          ""
        )

      parsed = Console.parse(truncated)

      assert [fault] = parsed.faults
      assert fault =~ "tasks-lifecycle"
      assert fault =~ "cannot be attributed"
    end

    test "the same scenario mapped twice is a fault" do
      doubled =
        @server <>
          """

          === Running scenario: tools-list ===
          Results saved to /tmp/run/server-tools-list-SECOND
          """

      assert [fault] = Console.parse(doubled).faults
      assert fault =~ "2 artefact directories"
    end

    test "a clean console has no faults — the accept half" do
      assert Console.parse(@server).faults == []
    end
  end

  # MEASURED on the null-control run, not imagined: when a scenario raises, the
  # harness catches it, synthesises a FAILURE check into its own summary, and
  # writes NO artefact directory. A census built from the artefact tree alone
  # would omit it — and omit a FAILING scenario, which biases the flattering way.
  describe "a scenario that threw (S5-13)" do
    @thrown """
    Running requirements 2026-07-28 (2 scenarios) against http://127.0.0.1:3002/mcp

    === Running scenario: tools-list ===
    Results saved to /tmp/run/server-tools-list-A

    === Running scenario: tasks-capability-negotiation ===
    Running client scenario 'tasks-capability-negotiation' against server: http://127.0.0.1:3002/mcp
    Failed to run scenario tasks-capability-negotiation: Tt [JsonRpcError]: Method not found
        at l (file:///tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js:1128:6776)

    === SUMMARY ===
    ✓ tools-list: 3 passed, 0 failed
    ✗ tasks-capability-negotiation: 0 passed, 1 failed

    Total: 3 passed, 1 failed
    """

    test "is a mapping with no directory, carrying the harness's message" do
      parsed = Console.parse(@thrown)

      assert Console.ran(parsed) == ["tools-list", "tasks-capability-negotiation"]
      assert parsed.faults == []

      assert [%{scenario: "tasks-capability-negotiation", dir: nil, threw: threw}] =
               Console.thrown(parsed)

      assert threw =~ "Method not found"
    end

    test "contributes no directory to the disk comparison" do
      assert Console.dirs_relative(Console.parse(@thrown), "/tmp/run") ==
               ["server-tools-list-A"]
    end

    test "a header closed by NEITHER a save nor a failure is still a fault" do
      truncated =
        String.replace(
          @thrown,
          "Failed to run scenario tasks-capability-negotiation: Tt [JsonRpcError]: Method not found\n",
          ""
        )

      assert [fault] = Console.parse(truncated).faults
      assert fault =~ "tasks-capability-negotiation"

      assert Console.parse(@thrown).faults == [],
             "accepting the thrown case must not turn the truncation check off"
    end

    test "a failure line naming a DIFFERENT scenario does not close the open one" do
      crossed =
        String.replace(
          @thrown,
          "Failed to run scenario tasks-capability-negotiation:",
          "Failed to run scenario some-other-scenario:"
        )

      assert [fault] = Console.parse(crossed).faults
      assert fault =~ "tasks-capability-negotiation"
    end
  end

  # S5-12, measured on the client leg at alpha.11 rather than assumed.
  # MES-56 correction round 2. `duplicate_faults/1` has always faulted a scenario
  # mapped to two directories; every OTHER block in this file that names
  # scenarios had no such guard, and a consumer keying on the scenario id
  # collapses a duplicate silently. These are the sibling guards.
  describe "one scenario, one line — in every block that names scenarios" do
    defp with_summary(extra) do
      String.replace(@server, "✓ tools-list: 5 passed, 0 failed", extra)
    end

    test "REFUSES two contradictory SUMMARY marks for one scenario, and says they conflict" do
      body = with_summary("✗ tools-list: 0 passed, 5 failed\n✓ tools-list: 5 passed, 0 failed")
      parsed = Console.parse(body)

      # Both are parsed; it is the KEYING that collapses them, so the fault has
      # to come from the parser rather than from the consumer that keys.
      assert length(parsed.marks) == 4
      assert [fault] = parsed.faults
      assert fault =~ "tools-list"
      assert fault =~ "2 SUMMARY marks"
      assert fault =~ "CONTRADICT"
      assert fault =~ "✗ 0 passed, 5 failed then ✓ 5 passed, 0 failed"
    end

    test "REFUSES an identical repeat too, because a repeat is still unattributable" do
      body = with_summary("✓ tools-list: 5 passed, 0 failed\n✓ tools-list: 5 passed, 0 failed")

      assert [fault] = Console.parse(body).faults
      assert fault =~ "2 SUMMARY marks"
      refute fault =~ "CONTRADICT"

      # "refuse only when they disagree" would make the guard depend on the very
      # comparison it exists to protect, so this half is not an oversight.
      assert fault =~ "no single harness verdict"
    end

    test "REFUSES a mark for a scenario that never ran — the mirror of a missing mark" do
      body = with_summary("✓ tools-list: 5 passed, 0 failed\n✓ invented: 9 passed, 0 failed")

      assert [fault] = Console.parse(body).faults
      assert fault =~ "invented"
      assert fault =~ "never announced"
    end

    test "a scenario announced and never closed faults ONCE, as unterminated" do
      # It has a mark and no mapping, so an orphan check keyed on completed
      # mappings called it un-announced — a second fault whose sentence was
      # false. The orphan check keys on the header instead.
      body =
        String.replace(
          @server,
          "Results saved to /tmp/run/server-tools-list-2026-08-21T00-00-00-000Z\n",
          ""
        )

      assert [fault] = Console.parse(body).faults
      assert fault =~ "was announced"
      refute fault =~ "never announced"
    end

    test "REFUSES the same scenario twice in the not-scored block" do
      # The repeat keeps the ✗ of the SUMMARY mark. Flipping it to ✓ would be a
      # second, different defect — two blocks stating two verdicts — and it
      # faults separately below. One defect, one fault.
      body =
        String.replace(
          @server,
          "  ✗ tasks-lifecycle (extension)",
          "  ✗ tasks-lifecycle (extension)\n  ✗ tasks-lifecycle (pending)"
        )

      assert [fault] = Console.parse(body).faults
      assert fault =~ "tasks-lifecycle"
      assert fault =~ "2 times in the not-scored block"
    end

    # MES-56 correction round 4, C1. The MEMBERSHIP half of the not-scored
    # block: `duplicate_not_scored_faults/1` above guarded multiplicity from
    # round 2, and nothing checked that a not-scored line names a scenario the
    # console announced — the third time this file implemented one half of a
    # paired concept.
    test "REFUSES a not-scored line for a scenario that never ran" do
      body = @server <> "  ✓ ghost-scenario (extension)\n"

      assert [fault] = Console.parse(body).faults
      assert fault =~ "ghost-scenario"
      assert fault =~ "never announced"
      assert fault =~ "harness reason"

      # It is parsed either way; what changes is that the run is now refused
      # rather than the ghost reaching an IR that MES-57 and MES-58 read.
      assert Enum.any?(Console.parse(body).not_scored, &(&1.scenario == "ghost-scenario"))
    end

    # Opened by completing the block × guarantee table rather than reported:
    # both blocks carry a ✓/✗ for the same scenario and nothing compared them.
    test "REFUSES a not-scored line whose verdict contradicts the SUMMARY mark" do
      body =
        String.replace(
          @server,
          "  ✗ tasks-lifecycle (extension)",
          "  ✓ tasks-lifecycle (extension)"
        )

      assert [fault] = Console.parse(body).faults
      assert fault =~ "tasks-lifecycle"
      assert fault =~ "marked ✗ in the SUMMARY block and ✓ in the not-scored block"
      assert fault =~ "two verdicts"
    end

    test "a scenario with two marks is NOT also reported as contradicting its not-scored line" do
      # `mark_faults/3` already refuses the duplicate. Comparing the not-scored
      # line against whichever of the pair a keying kept would emit a second
      # fault derived from the collapse the first fault exists to report.
      body =
        String.replace(
          @server,
          "✗ tasks-lifecycle: 1 passed, 8 failed",
          "✗ tasks-lifecycle: 1 passed, 8 failed\n✓ tasks-lifecycle: 9 passed, 0 failed"
        )

      assert [fault] = Console.parse(body).faults
      assert fault =~ "2 SUMMARY marks"
      refute fault =~ "two verdicts"
    end

    test "REFUSES two Total lines, and a Total line that repeats a label" do
      two =
        String.replace(
          @server,
          "Total: 7 passed, 10 failed",
          "Total: 7 passed, 10 failed\nTotal: 99 passed, 0 failed"
        )

      assert [fault] = Console.parse(two).faults
      assert fault =~ "2 `Total:` lines"

      repeated =
        String.replace(
          @server,
          "Total: 7 passed, 10 failed",
          "Total: 7 passed, 10 failed, 99 passed"
        )

      assert [fault] = Console.parse(repeated).faults
      assert fault =~ ~s("passed" 2 times)

      # Only the first line is read, so the second value is the one silently
      # dropped — stated here so the fault's claim is checkable.
      assert Console.parse(two).totals == %{"passed" => 7, "failed" => 10}
    end

    test "an ABSENT Total line does NOT fault, and the difference is the point" do
      # Multiplicity means two contradictory values with one silently chosen —
      # the B2 shape. Absence means no value, and an empty map is visibly empty
      # to whoever reads it. Nothing quotes `totals` today; when MES-58 does, it
      # will see %{} rather than a number it cannot tell was invented.
      body = String.replace(@server, "Total: 7 passed, 10 failed\n", "")

      assert Console.parse(body).faults == []
      assert Console.parse(body).totals == %{}
    end

    test "the accept half: the fixture every refusal above is one edit away from" do
      assert Console.parse(@server).faults == []
    end
  end

  # MES-56 correction round 5, C1. The block × guarantee table above is closed
  # over `parse/1`'s four blocks, and this is the join it cannot state: the
  # `Total:` line and the SUMMARY marks are two reducers over ONE run, and the
  # harness computes the first by summing the second. Measured before it was
  # guarded — a console whose marks say 1 passed / 0 failed and whose `Total:`
  # line says 0 passed / 1 failed parsed with `faults: []` and the census
  # ACCEPTED it.
  describe "the `Total:` line against the marks it is the sum of" do
    defp with_total(new), do: String.replace(@server, "Total: 7 passed, 10 failed", new)

    test "REFUSES a total that overstates the marks" do
      assert [fault] = Console.parse(with_total("Total: 8 passed, 10 failed")).faults
      assert fault =~ "sum to 7 passed"
      assert fault =~ "states 8"
      assert fault =~ "cannot disagree with itself"
    end

    test "REFUSES a total that understates them, so the guard is not one-sided" do
      assert [fault] = Console.parse(with_total("Total: 7 passed, 3 failed")).faults
      assert fault =~ "sum to 10 failed"
      assert fault =~ "states 3"
    end

    test "REFUSES a warnings column no mark accounts for" do
      # The client leg's `Total:` line carries `warnings`, and the marks carry
      # the per-scenario number it sums. The server leg's printer emits neither,
      # so a server console stating one is a console the harness did not print.
      parsed = Console.parse(with_total("Total: 7 passed, 10 failed, 4 warnings"))

      assert [fault] = parsed.faults
      assert fault =~ "sum to 0 warnings"
      assert fault =~ "states 4"
    end

    test "a duplicated mark is reported ONCE, as a duplicate, not also as a bad sum" do
      # The sum over a block that repeats a mark is not the harness's sum, so
      # reporting the disagreement would describe the symptom of a defect whose
      # cause `mark_faults/3` has already named. The console is refused either
      # way; what is protected is the diagnosis.
      body =
        String.replace(
          @server,
          "✓ tools-list: 5 passed, 0 failed",
          "✓ tools-list: 5 passed, 0 failed\n✓ tools-list: 5 passed, 0 failed"
        )

      assert [fault] = Console.parse(body).faults
      assert fault =~ "2 SUMMARY marks"
      refute fault =~ "cannot disagree with itself"
    end

    test "a malformed Total line is reported ONCE too, for the same reason" do
      # A total read off a line that repeats a label is not the harness's total.
      body = with_total("Total: 7 passed, 10 failed, 99 passed")

      assert [fault] = Console.parse(body).faults
      assert fault =~ ~s("passed" 2 times)
      refute fault =~ "cannot disagree with itself"
    end

    test "an ABSENT Total line still does not fault — there is no sum to disagree with" do
      body = String.replace(@server, "Total: 7 passed, 10 failed\n", "")

      assert Console.parse(body).faults == []
    end

    test "the accept half, which is the six delivered consoles' shape" do
      assert Console.parse(@server).faults == []
      assert Console.parse(@thrown).faults == []
    end
  end

  # MES-56 correction round 5, C2. Round 4 called this block's membership cell
  # vacuous because it keys on status labels rather than scenario ids. The
  # review measured that the labels are still a domain someone can leave:
  # `total_parts/1` accepts any lowercase word, so `Total: 3 widgets` parsed
  # faultlessly, and a part matching neither shape was dropped in silence.
  describe "the `Total:` line's labels are a domain, not free text" do
    test "REFUSES a label the harness never prints" do
      assert [fault] = Console.parse(with_total("Total: 7 passed, 10 failed, 3 widgets")).faults
      assert fault =~ ~s("widgets")
      assert fault =~ "passed, failed, warnings, skipped"
      assert fault =~ "contributes nothing and says nothing"
    end

    test "REFUSES a part that is not `N label` at all, which was dropped in silence" do
      assert [fault] = Console.parse(with_total("Total: 7 passed, 10 failed, garbage")).faults
      assert fault =~ ~s("garbage")
      assert fault =~ "dropped without a word"

      # The drop is the defect: the map is the same either way, so nothing
      # downstream could have noticed.
      assert Console.parse(with_total("Total: 7 passed, 10 failed, garbage")).totals ==
               Console.parse(@server).totals
    end

    test "ACCEPTS every label the harness's own printers emit" do
      # `skipped` has no mark to sum against and is bounded rather than checked,
      # so it must parse without faulting on that account. Read off
      # @modelcontextprotocol/conformance 0.2.0-alpha.11 `dist/index.js`, whose
      # client printer emits `N passed, M failed, K warnings[, J skipped]`.
      body = with_total("Total: 7 passed, 10 failed, 0 warnings, 4 skipped")

      assert Console.parse(body).faults == []
      assert Console.parse(body).totals["skipped"] == 4
    end
  end

  describe "the client leg is refused outright (S5-12)" do
    @client """
    Running requirements 2026-07-28 (39 scenarios) in parallel...

    Starting scenario: auth/scope-from-www-authenticate
    Starting scenario: auth/scope-retry-limit
    Results saved to /tmp/run/auth/scope-retry-limit-2026-08-21T00-29-23-813Z
    Results saved to /tmp/run/auth/scope-from-www-authenticate-2026-08-21T00-29-23-812Z

    === SUITE SUMMARY ===

    ✗ auth/scope-from-www-authenticate: 0 passed, 1 failed
    ✗ auth/scope-retry-limit: 0 passed, 1 failed, 2 warnings

    Total: 0 passed, 2 failed, 2 warnings
    """

    test "produces NO mapping, and says why" do
      parsed = Console.parse(@client)

      assert parsed.mappings == []
      assert [fault] = parsed.faults
      assert fault =~ "Promise.all"
      assert fault =~ "server-leg only"
    end

    test "the saves arrive in completion order, which is why positional pairing was refused" do
      # Documented as a test so the reasoning is checkable rather than asserted:
      # `scope-retry-limit` STARTS second and SAVES first.
      lines = String.split(@client, "\n")
      first = fn prefix -> Enum.find(lines, &String.starts_with?(&1, prefix)) end

      assert first.("Starting scenario: ") ==
               "Starting scenario: auth/scope-from-www-authenticate"

      assert first.("Results saved to ") =~ "scope-retry-limit"
    end

    test "the client summary mark's warnings suffix is read, not made to shift the columns" do
      parsed = Console.parse(@client)

      assert Map.new(parsed.marks, &{&1.scenario, {&1.passed, &1.failed}}) == %{
               "auth/scope-from-www-authenticate" => {0, 1},
               "auth/scope-retry-limit" => {0, 1}
             }
    end

    test "the client Total line's extra fields are named rather than positional" do
      assert Console.parse(@client).totals == %{
               "passed" => 0,
               "failed" => 2,
               "warnings" => 2
             }
    end

    # MES-56 correction round 5, C1. The warnings suffix is now CAPTURED rather
    # than skipped over, because the client leg's `Total:` line states a
    # warnings column and there is nothing to check it against otherwise.
    test "the per-scenario warnings count is read, not just stepped over" do
      assert Map.new(Console.parse(@client).marks, &{&1.scenario, &1.warnings}) == %{
               "auth/scope-from-www-authenticate" => 0,
               "auth/scope-retry-limit" => 2
             }
    end

    test "the sum check is not scoped to a leg: the client fixture's own columns agree" do
      # The console is refused whole for want of a scenario -> directory key, so
      # the ONLY fault must be that one. A second fault here would mean the sum
      # check false-reds every client console it will ever see.
      assert [fault] = Console.parse(@client).faults
      assert fault =~ "Promise.all"
    end

    test "and a client total that disagrees with its marks is faulted on top of the refusal" do
      # Two faults, not one, and that is the point: the leg finding says the
      # mapping cannot be read, which is not a reason to stop reading the
      # columns that CAN be.
      body =
        String.replace(
          @client,
          "Total: 0 passed, 2 failed, 2 warnings",
          "Total: 0 passed, 2 failed, 5 warnings"
        )

      faults = Console.parse(body).faults

      assert Enum.any?(faults, &(&1 =~ "sum to 2 warnings"))
      assert Enum.any?(faults, &(&1 =~ "Promise.all"))
    end
  end
end
