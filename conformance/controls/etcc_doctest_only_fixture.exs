# MES-84 (B4) PROBE FIXTURE — `only:` plus `tags:`, the mechanism the ticket uses.
#
# See `etcc_doctest_all_fixture.exs` for why these fixtures are committed and why
# `mix test` never reaches them.
#
# Two things are measured here at once, and they pull in opposite directions:
#
#   * `tags:` WORKS, and reaches every example of the selected `{function, arity}`
#     — which is what makes `doctest Mod, tags: [:etcc]` a usable mechanism at
#     `test/mcp/protocol/header_mirror_test.exs:31`.
#
#   * `only:` RENUMBERS. `b?/1` is examples (3) and (4) of a full run and becomes
#     (1) and (2) here. The number is inside the row key, and the row key is the
#     authored join key of `conformance/data/etcc-decisions.json` — which is why
#     E1 was ruled "do not split".
defmodule MES84.DoctestOnlyFixture do
  use ExUnit.Case, async: false

  doctest MCP.Conformance.DoctestOptionSubject, only: [b?: 1], tags: [:etcc]
end
