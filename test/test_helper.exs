# MES-8 test ledger — retired-with-owner (Ruling 3: no silent deletions).
#
# These tag-excluded suites exercise the 2025-11-25 handshake/session flow that
# the stateless core removes. They are NOT deleted — they stay in-tree, visible
# and restorable, and are re-homed by the owning ticket:
#
#   :mes9_retired  — old per-session server shell + old Streamable-HTTP transport
#                    + client↔server handshake integration. Owner: MES-9
#                    (transport rewrite wires the transport to MCP.Server.Dispatch;
#                    the @deprecated MCP.Server shell is deleted then).
#   :mes10_retired — the MES-3 handshake-time handler_opts identity tests.
#                    Owner: MES-10 (identity seam v2; superseded by the D4 ported
#                    ACs / AC3′).
#
# Stateless equivalents are covered now by test/mcp/server/dispatch_test.exs.
# See the MES-8 implementation notes for the full re-homing table + ledger.
ExUnit.start(exclude: [:mes9_retired, :mes10_retired])
