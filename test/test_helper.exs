# Test ledger — retired-with-owner (Ruling 3: no silent deletions).
#
# EMPTY as of MES-10. Both Sprint-3 ledger lines are now CLOSED:
#
#   :mes9_retired  — closed by MES-9 (old per-session server shell, old
#                    Streamable-HTTP transport, client↔server handshake
#                    integration): rewritten stateless or deleted with a
#                    ledger line. No files remain.
#
#   :mes10_retired — closed by MES-10. The MES-3/MES-5 handshake-time
#                    handler_opts identity criteria (streamable_http_ac_test.exs
#                    AC1–AC6/AC8) are PORTED, per-request, onto the stateless
#                    transport as real-HTTP acceptance tests in
#                    streamable_http_ac_test.exs (AC1–AC8 + AC3′), and the
#                    deleted streamable_http_handler_opts_test.exs (content @
#                    9a6150a) is closed per-case (see the MES-10 impl notes).
#                    No :mes10_retired files remain.
#
# Coverage map (post-MES-10):
#   * Stateless protocol behaviour   — test/mcp/server/dispatch_test.exs
#   * Stateless transport (plug-unit)— streamable_http_stateless_test.exs
#   * Identity ACs + spoof sweep     — streamable_http_ac_test.exs (real HTTP)
#   * Client ↔ server integration    — integration_test.exs
#
# The exclude list is EMPTY *of retired tests*: every test in the ledger runs.
#
# One conditional exclusion remains, and it is conditional on the HOST rather
# than on anything about the code: three conformance tests shell out to `node`
# to cross-check our parsing against the live harness's own rendering. Where
# `node` or the pinned harness is absent they cannot run, and the choice is
# between a red that means "wrong host", a silent skip, and this: an EXCLUSION
# that prints its reason and visibly shortens the suite.
#
# The silent skip is the one option that is not available. MES-56 round 1 found
# two of these tests guarding themselves with `if File.exists?(yaml)`, which
# passed green on a host that had checked nothing — absence read as
# satisfaction, in the test suite, on the ticket about exactly that.
#
# A complete gate-5 run therefore requires `node` on PATH and the harness
# installed at MCP.Conformance.TestHarness.install_dir/0. A run reporting
# "3 excluded" is NOT a complete gate 5.
case MCP.Conformance.TestHarness.unavailable_reason() do
  nil ->
    ExUnit.start()

  why ->
    IO.puts(:stderr, """

    EXCLUDING :requires_live_harness — #{why}.
    These tests drive the real conformance harness and cross-check its output
    against our parser; nothing else in the suite covers that. The excluded
    count below is the evidence they did not run. This is NOT a complete gate 5.
    """)

    ExUnit.start(exclude: [:requires_live_harness])
end
