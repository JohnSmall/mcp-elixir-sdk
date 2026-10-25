# The SDK's own stdio server, for MES-210's subprocess tests: an
# MCP.Server.Connection over MCP.Transport.Stdio in :server mode, answering
# with MCP.Test.StatelessHandler.
#
# Logs go to standard_error, so stdout carries protocol lines only.
# The server stops when stdin reaches EOF.
#
# Usage: MIX_ENV=test mix run --no-start test/support/stdio_server.exs

# A running logger_std_h cannot change its device, so the default handler is
# replaced by one on standard_error, keeping its level, filters and formatter.
{:ok, default} = :logger.get_handler_config(:default)
:ok = :logger.remove_handler(:default)

:ok =
  :logger.add_handler(
    :default,
    :logger_std_h,
    default
    |> Map.take([:level, :filter_default, :filters, :formatter])
    |> Map.put(:config, %{type: :standard_error})
  )

{:ok, pid} =
  MCP.Server.Connection.start_link(
    transport: {MCP.Transport.Stdio, [mode: :server]},
    handler: {MCP.Test.StatelessHandler, []}
  )

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
