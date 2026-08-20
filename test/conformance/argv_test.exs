defmodule MCP.Conformance.ArgvTest do
  @moduledoc """
  The property, for both CLI tasks at once:

  > **No invalid operator input may produce exit 0.**

  Six invocations reached exit 0 ACCEPTED on a good run before this: `--bogus`,
  the retired `--allow-dirty`, a value-less `--expect-commit`, a misspelled
  `--expect-comit`, a misspelled `--expect-requirement-md5`, and
  `--diagnose=maybe`. Each is a check the operator asked for and did not get,
  returning the tool's only success signal — the same class as B2 (absence in
  the artefacts) and the nil audit (absence in the manifest), now in the
  operator's own input.

  Every rejection case here is paired with a **control**: the correctly spelled
  form of the same flag, which must still do what it always did. A validator
  that rejected everything would satisfy the rejection half alone.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.Argv

  @switches [
    expect_commit: :string,
    expect_requirements_md5: :string,
    diagnose: :boolean
  ]

  defp parse(argv, opts \\ []) do
    spec =
      Keyword.merge(
        [strict: @switches, positional: 1, usage: "mix t RUN_DIR", retired: %{}],
        opts
      )

    Argv.parse!("t", argv, spec)
  catch
    :exit, {:shutdown, n} -> {:usage_error, n}
  end

  defp silently(fun) do
    ExUnit.CaptureIO.capture_io(:stderr, fun)
  end

  defp status(argv, opts \\ []) do
    parent = self()
    silently(fn -> send(parent, {:r, parse(argv, opts)}) end)
    assert_received {:r, result}
    result
  end

  defp message(argv, opts \\ []) do
    silently(fn -> parse(argv, opts) end)
  end

  describe "the six invocations that reached exit 0" do
    for {label, argv} <- [
          {"an unknown switch", ["/d", "--bogus"]},
          {"a retired switch", ["/d", "--allow-dirty"]},
          {"a switch missing its value", ["/d", "--expect-commit"]},
          {"a misspelled pin", ["/d", "--expect-comit", "0000"]},
          {"a misspelled instrument pin", ["/d", "--expect-requirement-md5", "bad"]},
          {"a value given to a flag", ["/d", "--diagnose=maybe"]}
        ] do
      test "#{label} exits #{Argv.usage_exit()}, not 0 — #{Enum.join(argv, " ")}" do
        assert status(unquote(argv), retired: %{"--allow-dirty" => "it waived WORKTREE_DIRTY"}) ==
                 {:usage_error, Argv.usage_exit()}
      end
    end

    test "an unexpected positional argument is rejected too" do
      assert status(["/d", "/another-dir"]) == {:usage_error, Argv.usage_exit()}
    end
  end

  describe "the control — valid input still parses" do
    test "the correctly spelled forms of every rejected flag are accepted" do
      assert {opts, ["/d"]} =
               parse([
                 "/d",
                 "--expect-commit",
                 "abc",
                 "--expect-requirements-md5",
                 "bad",
                 "--diagnose"
               ])

      assert opts[:expect_commit] == "abc"
      assert opts[:expect_requirements_md5] == "bad"
      assert opts[:diagnose] == true
    end

    test "the bare positional form is accepted" do
      assert {[], ["/d"]} = parse(["/d"])
    end

    test "no positional at all is accepted — the task decides if it needs one" do
      assert {[diagnose: true], []} = parse(["--diagnose"])
    end
  end

  describe "why strict: and not the invalid list" do
    # The mechanism matters, not just the outcome. Keeping
    # `OptionParser.parse/2`'s third element under `switches:` — the obvious
    # fix — would have caught two of the six: an unknown switch is not reported
    # invalid there, it is discarded along with the value behind it. This test
    # is the measurement, so the reason the code uses `strict:` cannot rot into
    # a comment nobody rechecks.
    test "switches: reports 2 of the 6 invalid; strict: reports 6 of 6" do
      cases = [
        ["/d", "--bogus"],
        ["/d", "--allow-dirty"],
        ["/d", "--expect-commit"],
        ["/d", "--expect-comit", "0000"],
        ["/d", "--expect-requirement-md5", "bad"],
        ["/d", "--diagnose=maybe"]
      ]

      lenient =
        Enum.count(cases, fn argv ->
          {_, _, invalid} = OptionParser.parse(argv, switches: @switches)
          invalid != []
        end)

      strict =
        Enum.count(cases, fn argv ->
          {_, _, invalid} = OptionParser.parse(argv, strict: @switches)
          invalid != []
        end)

      assert lenient == 2
      assert strict == 6
    end
  end

  describe "the message earns its line" do
    test "a misspelling names the switch that was probably meant" do
      assert message(["/d", "--expect-comit", "0000"]) =~ "did you mean --expect-commit?"
    end

    test "a retired switch says it was removed, not that it is a typo" do
      out = message(["/d", "--allow-dirty"], retired: %{"--allow-dirty" => "it waived DIRTY"})

      assert out =~ "was removed, not renamed"
      assert out =~ "it waived DIRTY"
      refute out =~ "did you mean"
    end

    test "a rejection says nothing was adjudicated or run" do
      assert message(["/d", "--bogus"]) =~ "Nothing was adjudicated and nothing was run"
    end
  end

  describe "the exit status is chosen, not fallen into" do
    # A usage error is not a refusal. 1 means "this run is inadmissible", a
    # verdict reached by adjudicating it; a usage error adjudicated nothing. 2
    # is --diagnose's. The only property that must hold is "not 0", and the
    # separation is what lets a caller tell "fix your command line" from
    # "re-run the measurement".
    test "usage_exit is not 0, not 1 (refusal) and not 2 (diagnosis)" do
      refute Argv.usage_exit() in [0, 1, 2]
      assert Argv.usage_exit() == 64
    end
  end
end
