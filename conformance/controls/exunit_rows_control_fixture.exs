# MES-83 (B3) CONTROL FIXTURE — the five states, from a REAL ExUnit run.
#
# Driven by `conformance/controls/exunit_rows_controls.exs`. NOT part of gate 5:
# this file is outside `test_paths`, so `mix test` never reaches it, and it is
# named by explicit path only. `mix test <path>` accepts a path outside
# `test_paths` and still loads `test/test_helper.exs` first — which is what
# attaches the formatter.
#
# ## Why this is COMMITTED rather than written to /tmp per run
#
# S7-1: the script that produced a reported table was not committed and no
# longer existed, so a bad reconstruction and a changed tree were
# indistinguishable. The rows in MES-83's close-out come from THIS file; anyone
# can re-run it and get them back.
#
# ## Why nothing here is a mutation of the tree
#
# S7-2 asks that whatever is mutated be restored per run, hash-verified. The
# obligation is better discharged by having nothing to restore: the deliberate
# failure lives in a file gate 5 never runs, so it can be committed as-is
# rather than injected into the suite and removed afterwards. The runner still
# asserts `git status --porcelain` is empty before and after — that is the
# check that would catch this reasoning being wrong.
defmodule MES83.ControlFixture do
  use ExUnit.Case, async: false

  # A doctest, so the control shows hazard 3 (S6-6) as well: four runtime rows
  # from ONE `doctest` declaration, each with its own key.
  doctest MCP.Protocol.HeaderMirror

  test "passes" do
    assert 1 + 1 == 2
  end

  test "fails deliberately" do
    assert 1 == 2
  end

  @tag :skip
  test "is skipped by tag" do
    flunk("a skipped test must not run")
  end

  # Excluded by `--exclude mes83_control_excluded`, and PASSES when it is not
  # excluded. That is the `flip` control: the same test, the same bytes, two
  # runs, two statuses — so the status is a function of the run rather than of
  # the reporter.
  @tag :mes83_control_excluded
  test "is excluded by filter" do
    assert :ok == :ok
  end
end
