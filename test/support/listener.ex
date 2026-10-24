defmodule MCP.Test.Listener do
  @moduledoc """
  MES-215. Starts a Bandit listener on port 0 and reads back the port the OS
  assigned at bind, so no test ever picks a port before it binds it.

  The pattern this replaces, a per-file helper that listened on port 0, read the
  port, closed the socket and returned the number for a later bind, left a window
  between the close and the bind in which anything else could take the port. It
  surfaced as `failed to start child: :listener ** (EXIT) :eaddrinuse` at
  the CG4 canary control in `client_conformance_test.exs` on two binding gate-5
  seeds. Here the port number does not exist until the listener holds it.

  Call sites spell `port: 0` themselves, so the absence of a picked port is
  visible where the listener is started; anything else is refused.
  `test/mcp/transport/listener_port_race_test.exs` holds the whole test tree to
  this (RC3) and shows the window, forced, for the old pattern and the new (RC1,
  RC2).
  """

  @doc """
  Starts `Bandit.start_link(opts)` on port 0 and returns `{pid, port}`, the port
  read back from the bound listener with `ThousandIsland.listener_info/1`.

  `before_bind` is the controls' seam (RC2): it is called with the port about to
  be bound, after it is chosen and before the bind. Here that port is always 0,
  so there is no number for anything to take.
  """
  @spec bandit!(keyword(), (non_neg_integer() -> any())) :: {pid(), :inet.port_number()}
  def bandit!(opts, before_bind \\ fn _port -> :ok end) do
    case Keyword.fetch(opts, :port) do
      {:ok, 0} -> :ok
      other -> raise ArgumentError, "bandit!/2 binds port 0 only; got port #{inspect(other)}"
    end

    port = pick()
    before_bind.(port)
    {:ok, pid} = Bandit.start_link(Keyword.put(opts, :port, port))
    {:ok, {_ip, bound}} = ThousandIsland.listener_info(pid)
    {pid, bound}
  end

  # The OS chooses at bind. A pick that returns a real port number here
  # reopens the window (mutant M1).
  defp pick, do: 0
end
