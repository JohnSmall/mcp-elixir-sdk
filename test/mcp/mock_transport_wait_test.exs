defmodule MCP.Test.MockTransportWaitTest do
  @moduledoc """
  MES-191 correction round 1 (CR 33096 F1, PM 33097) — controls on
  `MockTransport.await_sent/3`, the event-driven wait every client test now goes
  through.

  A wait that times out must leave nothing parked in the transport, a send that
  arrives after it must not touch it, and a timed-out wait must not cancel another
  live wait on the same count. A caller that dies while parked must not stay parked
  either.

  ## Evidence posture (A7)

  The first four tests are CAUGHT DEFECTS: at `ffca5e5` the transport kept every
  timed-out (and every dead) waiter until the awaited count was reached, so each of
  them was observed to FAIL there on its waiter count. The last test is a POSITIVE
  CONTROL on the atomic check-and-park, green at `ffca5e5` and after.

  The waiter table is read through `:sys.get_state/1` and counted with
  `Enum.count/1`, so the same assertion reads the list kept at `ffca5e5` and the
  map kept after the fix.
  """
  use ExUnit.Case, async: true

  alias MCP.Test.MockTransport

  setup do
    {:ok, transport} = MockTransport.start_link(owner: self())
    %{transport: transport}
  end

  defp waiters(transport),
    do: transport |> :sys.get_state() |> Map.fetch!(:waiters) |> Enum.count()

  # Parked state has no event to wait on, so this one observation polls, every
  # millisecond, under the same generous 30 s bound as the helper it controls.
  defp eventually(fun, deadline \\ System.monotonic_time(:millisecond) + 30_000) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("condition not reached in 30 s")

      true ->
        Process.sleep(1)
        eventually(fun, deadline)
    end
  end

  # Parks `count` from a separate process, and returns once the transport holds it.
  defp park(transport, count, timeout \\ 30_000) do
    before = waiters(transport)
    task = Task.async(fn -> MockTransport.await_sent(transport, count, timeout) end)
    eventually(fn -> waiters(transport) == before + 1 end)
    task
  end

  @tag oc: :none
  @tag oc_reason: "a test-double instrument (MockTransport waiters): no OC check exercises it"
  test "a timed-out wait leaves no waiter behind", %{transport: transport} do
    assert {:timeout, 0} = MockTransport.await_sent(transport, 2, 50)
    assert waiters(transport) == 0
  end

  @tag oc: :none
  @tag oc_reason: "a test-double instrument (MockTransport waiters): no OC check exercises it"
  test "a send after a cancelled wait answers only the live wait", %{transport: transport} do
    assert {:timeout, 0} = MockTransport.await_sent(transport, 1, 50)
    live = park(transport, 2)
    assert waiters(transport) == 1

    assert :ok = MockTransport.send_message(transport, %{"n" => 1})
    assert Process.alive?(transport)
    assert Task.yield(live, 0) == nil
    assert waiters(transport) == 1

    assert :ok = MockTransport.send_message(transport, %{"n" => 2})
    assert {:ok, [%{"n" => 1}, %{"n" => 2}]} = Task.await(live, :infinity)
    assert waiters(transport) == 0
    assert {:messages, []} = Process.info(self(), :messages)
  end

  @tag oc: :none
  @tag oc_reason: "a test-double instrument (MockTransport waiters): no OC check exercises it"
  test "a timed-out wait does not cancel a live wait on the same count",
       %{transport: transport} do
    live = park(transport, 1)
    assert {:timeout, 0} = MockTransport.await_sent(transport, 1, 50)
    assert waiters(transport) == 1

    assert :ok = MockTransport.send_message(transport, %{"n" => 1})
    assert {:ok, [%{"n" => 1}]} = Task.await(live, :infinity)
    assert waiters(transport) == 0
  end

  @tag oc: :none
  @tag oc_reason: "a test-double instrument (MockTransport waiters): no OC check exercises it"
  test "a caller that dies while parked leaves no waiter behind", %{transport: transport} do
    caller = spawn(fn -> MockTransport.await_sent(transport, 5, 30_000) end)
    eventually(fn -> waiters(transport) == 1 end)

    ref = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^caller, :killed}, 30_000

    eventually(fn -> waiters(transport) == 0 end)
    assert Process.alive?(transport)
  end

  @tag oc: :none
  @tag oc_reason: "a test-double instrument (MockTransport waiters): no OC check exercises it"
  test "the count is checked and the wait parked in one call", %{transport: transport} do
    assert :ok = MockTransport.send_message(transport, %{"n" => 1})
    assert {:ok, [%{"n" => 1}]} = MockTransport.await_sent(transport, 1)
    assert waiters(transport) == 0

    live = park(transport, 2)
    assert :ok = MockTransport.send_message(transport, %{"n" => 2})
    assert {:ok, [%{"n" => 1}, %{"n" => 2}]} = Task.await(live, :infinity)
    assert waiters(transport) == 0
  end
end
