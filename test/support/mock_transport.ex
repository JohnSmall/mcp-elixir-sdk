defmodule MCP.Test.MockTransport do
  @moduledoc """
  In-memory transport for unit testing MCP client/server.

  Collects sent messages and allows injecting incoming messages.

  ## Options

    * `:send_result` — what `send_message/2,3` returns. Defaults to `:ok`;
      set `{:error, reason}` to drive the client's send-failure path (D-2).
      A failed send records nothing in `sent`, exactly as a transport that
      never put the message on the wire.
  """

  use GenServer

  @behaviour MCP.Transport

  defstruct [:owner, :sent, :closed, :send_result, :sent_opts]

  @impl MCP.Transport
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl MCP.Transport
  def send_message(pid, message) do
    GenServer.call(pid, {:send_message, message, []})
  end

  @impl MCP.Transport
  def send_message(pid, message, opts) do
    GenServer.call(pid, {:send_message, message, opts})
  end

  @impl MCP.Transport
  def close(pid) do
    GenServer.call(pid, :close)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Inject a message as if it came from the remote side.
  """
  def inject(pid, message) do
    GenServer.cast(pid, {:inject, message})
  end

  @doc """
  Returns all messages sent through this transport.
  """
  def sent_messages(pid) do
    GenServer.call(pid, :sent_messages)
  end

  @doc """
  Returns the last message sent through this transport, or nil.
  """
  def last_sent(pid) do
    GenServer.call(pid, :last_sent)
  end

  @doc """
  Returns whether close has been called.
  """
  def closed?(pid) do
    GenServer.call(pid, :closed?)
  end

  @doc """
  Changes what subsequent sends return, so a transport can be made to fail
  part-way through an exchange (D-2's MRTR-retry clause).
  """
  def set_send_result(pid, result) do
    GenServer.call(pid, {:set_send_result, result})
  end

  @doc """
  Returns the per-message opts (CG7's `send_message/3` seam) recorded for each
  sent message, oldest first — `[]` for a message sent through `send_message/2`.
  """
  def sent_opts(pid) do
    GenServer.call(pid, :sent_opts)
  end

  # --- GenServer callbacks ---

  @impl GenServer
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)

    {:ok,
     %__MODULE__{
       owner: owner,
       sent: [],
       sent_opts: [],
       closed: false,
       send_result: Keyword.get(opts, :send_result, :ok)
     }}
  end

  @impl GenServer
  def handle_call({:send_message, message, opts}, _from, %{send_result: :ok} = state) do
    {:reply, :ok, %{state | sent: state.sent ++ [message], sent_opts: state.sent_opts ++ [opts]}}
  end

  def handle_call({:send_message, _message, _opts}, _from, state) do
    {:reply, state.send_result, state}
  end

  def handle_call(:close, _from, state) do
    send(state.owner, {:mcp_transport_closed, :normal})
    {:reply, :ok, %{state | closed: true}}
  end

  def handle_call(:sent_messages, _from, state) do
    {:reply, state.sent, state}
  end

  def handle_call(:last_sent, _from, state) do
    {:reply, List.last(state.sent), state}
  end

  def handle_call(:closed?, _from, state) do
    {:reply, state.closed, state}
  end

  def handle_call(:sent_opts, _from, state) do
    {:reply, state.sent_opts, state}
  end

  def handle_call({:set_send_result, result}, _from, state) do
    {:reply, :ok, %{state | send_result: result}}
  end

  @impl GenServer
  def handle_cast({:inject, message}, state) do
    send(state.owner, {:mcp_message, message})
    {:noreply, state}
  end
end
