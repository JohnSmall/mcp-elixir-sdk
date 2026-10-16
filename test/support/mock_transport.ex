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

  defstruct [:owner, :sent, :closed, :send_result, :sent_opts, waiters: %{}]

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

  # Waiting for a send (MES-191). The transport replies to a parked
  # `{:await_sent, n, timeout}` caller in the same turn that records the n-th
  # message, so the wait is event-driven: no polling, no sleeping, and no deadline
  # a correct client can miss under host load. The only bound is @wait_timeout per
  # wait, under ExUnit's 60 s per-test timeout, so a client that never sends fails
  # the test and never hangs the suite.
  #
  # The transport owns that deadline (correction round 1, CR 33096 F1). Each wait
  # is parked under its own ref, with its expiry timer and a monitor on its caller,
  # and leaves the table exactly once: released by the n-th send, expired by its
  # timer, or dropped when its caller dies. Nothing outlives its wait.
  import ExUnit.Assertions, only: [flunk: 1]

  @wait_timeout 30_000

  @doc """
  Waits until at least `count` messages have been sent and returns them all,
  oldest first. Flunks the calling test if that has not happened within
  #{@wait_timeout} ms, with the same message the per-file helpers it replaces
  used.
  """
  def wait_for_sent(pid, count) do
    case await_sent(pid, count) do
      {:ok, sent} -> sent
      {:timeout, got} -> flunk("Timed out waiting for #{count} messages, got #{got}")
      :exited -> flunk("Timed out waiting for #{count} messages: the transport exited")
    end
  end

  @doc """
  As `wait_for_sent/2`, without flunking: `{:ok, sent}`, `{:timeout, sent_count}`,
  or `:exited` when the transport is not alive (its owner may have died with it).
  """
  def await_sent(pid, count, timeout \\ @wait_timeout) do
    # The transport always answers by `timeout`, so the call itself need not time out.
    GenServer.call(pid, {:await_sent, count, timeout}, :infinity)
  catch
    :exit, _ -> :exited
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
    state = %{state | sent: state.sent ++ [message], sent_opts: state.sent_opts ++ [opts]}
    {:reply, :ok, release_waiters(state)}
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

  # Checked and parked in one call, so no send can fall between the two.
  def handle_call({:await_sent, count, timeout}, {caller, _} = from, state) do
    if length(state.sent) >= count do
      {:reply, {:ok, state.sent}, state}
    else
      ref = make_ref()
      timer = Process.send_after(self(), {:wait_expired, ref}, timeout)
      waiter = %{count: count, from: from, timer: timer, monitor: Process.monitor(caller)}
      {:noreply, %{state | waiters: Map.put(state.waiters, ref, waiter)}}
    end
  end

  @impl GenServer
  def handle_cast({:inject, message}, state) do
    send(state.owner, {:mcp_message, message})
    {:noreply, state}
  end

  # A timer already fired for a wait the n-th send released finds no ref: a no-op.
  @impl GenServer
  def handle_info({:wait_expired, ref}, state) do
    case Map.pop(state.waiters, ref) do
      {nil, _} ->
        {:noreply, state}

      {waiter, waiters} ->
        Process.demonitor(waiter.monitor, [:flush])
        GenServer.reply(waiter.from, {:timeout, length(state.sent)})
        {:noreply, %{state | waiters: waiters}}
    end
  end

  def handle_info({:DOWN, monitor, :process, _caller, _reason}, state) do
    {gone, waiters} = Map.split_with(state.waiters, fn {_, w} -> w.monitor == monitor end)
    Enum.each(gone, fn {_, w} -> Process.cancel_timer(w.timer) end)
    {:noreply, %{state | waiters: waiters}}
  end

  defp release_waiters(state) do
    sent = length(state.sent)
    {ready, waiting} = Map.split_with(state.waiters, fn {_, w} -> sent >= w.count end)

    Enum.each(ready, fn {_, w} ->
      Process.cancel_timer(w.timer)
      Process.demonitor(w.monitor, [:flush])
      GenServer.reply(w.from, {:ok, state.sent})
    end)

    %{state | waiters: waiting}
  end
end
