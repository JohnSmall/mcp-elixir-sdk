#!/usr/bin/env elixir
# MCP Conformance Server Adapter — protocol revision 2026-07-28 (stateless core).
#
#   mix run --no-halt conformance/server_adapter.exs [port]      # default 3001
#
# then, in another shell:
#
#   conformance server --url http://127.0.0.1:3001/mcp \
#     --requirements 2026-07-28 -o <dir>
#
# Measured against @modelcontextprotocol/conformance@0.2.0-alpha.11.
#
# ## The rule this adapter follows
#
# The adapter is a TRANSLATOR. It configures this SDK the way a consumer would
# and starts it; it never post-processes a response to satisfy a check. Every
# option below is here for a stated protocol reason, not because a scenario
# went red without it:
#
#   * `enable_json_response: false` — SSE mode. This is the only mode in which
#     `MCP.Server.Config` can honestly advertise `listChanged`, because it is
#     the only one in which the driver can hold a `subscriptions/listen` stream
#     open (`MCP.Server.Config.detect_capabilities/2`). A JSON-mode run would
#     advertise nothing and the `server-stateless` subscription checks would
#     report "not applicable" rather than a measurement.
#   * no `protocol_version:` override — the default is the stateless core's own
#     `2026-07-28`. The previous revision of this file pinned `"2025-11-25"`,
#     which is what made every request here fail the per-request version gate.
#   * default `cache_defaults` — `{0, "public"}`, i.e. no-store. The `caching`
#     scenario requires `ttlMs`/`cacheScope` to be PRESENT and well-formed, not
#     to be non-zero; raising the TTL to make a number look better would be
#     changing behaviour for a scenario.
#
# `handler_opts` is a static keyword list, so `ToolContext.identity` is `nil`
# for every request: this fixture has no authenticated transport in front of it
# and says so, rather than inventing a principal from the request body (MC-2).

Code.require_file("request_state.ex", Path.dirname(__ENV__.file))
Code.require_file("server_handler.ex", Path.dirname(__ENV__.file))

port =
  case System.argv() do
    [port_str | _] -> String.to_integer(port_str)
    _ -> 3001
  end

# Created HERE, before the plug is built, so the launch-owned ETS table belongs
# to this long-lived script process rather than to whichever process happens to
# call `Plug.init/1`.
MCP.Conformance.ServerHandler.ensure_store()

plug =
  MCP.Transport.StreamableHTTP.Plug.new(
    server_mod: MCP.Conformance.ServerHandler,
    server_opts: [
      server_info: %{name: "mcp_elixir_sdk_conformance_server", version: "2.0.0-dev"}
    ],
    handler_opts: [],
    enable_json_response: false
  )

{:ok, _} = Bandit.start_link(plug: plug, port: port, ip: {127, 0, 0, 1})

IO.puts("MCP conformance server (2026-07-28) listening on http://127.0.0.1:#{port}/mcp")

Process.sleep(:infinity)
