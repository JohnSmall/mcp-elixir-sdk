# MES-84 (B4) PROBE FIXTURE — the SILENT-IGNORE case, and the reason AC4 exists.
#
# See `etcc_doctest_all_fixture.exs` for why these fixtures are committed and why
# `mix test` never reaches them.
#
# `tagz:` is a misspelling of `tags:`. ExUnit.DocTest's documented option
# vocabulary is `:only`, `:except`, `:import`, `:tags`, `:inspect_opts` — and an
# option outside it produces NO error, NO warning, and NO tag. The suite stays
# green over a mark that was never applied.
#
# The whole tagging mechanism rests on that misspelling being caught somewhere,
# since it cannot be caught here: `mix conformance.etcc_tags --check` catches it
# in the source, and the runtime guard catches it in what ExUnit actually reports.
defmodule MES84.DoctestTypoFixture do
  use ExUnit.Case, async: false

  doctest MCP.Conformance.DoctestOptionSubject, only: [c: 1], tagz: [:etcc]
end
