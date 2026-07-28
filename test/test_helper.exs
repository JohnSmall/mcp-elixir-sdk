# Test ledger — retired-with-owner (Ruling 3: no silent deletions).
#
# MES-9 closed all three :mes9_retired lines (the old per-session server shell,
# the old Streamable-HTTP transport, and the client↔server handshake
# integration): those suites were rewritten stateless or deleted with a ledger
# line (see the MES-9 implementation notes). No :mes9_retired files remain.
#
#   :mes10_retired — the MES-3/MES-5 handshake-time handler_opts identity
#                    criteria (streamable_http_ac_test.exs AC1–AC6/AC8). Owner:
#                    MES-10 (identity seam v2), which re-anchors them per-request
#                    (PO Comment B) and ports them onto the stateless transport.
#                    AC7 (localhost/Origin enforcement) is re-homed now in
#                    test/mcp/transport/streamable_http_stateless_test.exs.
#
# Stateless protocol behaviour is covered by test/mcp/server/dispatch_test.exs;
# the stateless transport + client↔server integration by
# streamable_http_stateless_test.exs and integration_test.exs.
ExUnit.start(exclude: [:mes10_retired])
