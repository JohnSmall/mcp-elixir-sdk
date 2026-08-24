# MES-84 (B4) PROBE FIXTURE — the BASELINE numbering, with no options at all.
#
# Driven by `conformance/controls/etcc_tags_controls.exs doctest_options`. Outside
# `test_paths`, so `mix test` never reaches it and gate 5 never runs it; it is
# named by explicit path only, and `mix test <path>` still loads
# `test/test_helper.exs` first, which is what attaches the row formatter.
#
# Committed rather than written to /tmp per run (S7-1): the table in MES-84's
# close-out comes from THESE files, and a probe whose script no longer exists
# cannot be told apart from a bad reconstruction of it.
#
# One module per file, three files, because the three runs must be three separate
# ExUnit modules — the example index `doctest` assigns is a MODULE-WIDE counter
# over the selected set, which is the whole finding.
defmodule MES84.DoctestAllFixture do
  use ExUnit.Case, async: false

  doctest MCP.Conformance.DoctestOptionSubject
end
