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
# The exclude list is EMPTY: every test runs.
ExUnit.start()
