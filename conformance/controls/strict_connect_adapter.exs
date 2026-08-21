#!/usr/bin/env elixir
# MES-57 DRIVE-POLICY PROBE — not a control, and not the measurement.
#
# ## What this exists to establish, and why reading the code could not
#
# Sprint 4's client figure carries two discounts, and this file re-derives the
# first of them BY MEASUREMENT on the tree under test rather than inheriting it
# from a ticket comment.
#
# The claim under test:
#
#   > `request-metadata` passes only because the measurement adapter keeps
#   > driving after `MCP.Client.connect/1` has errored.
#
# The mechanism behind the claim is documented in `client_adapter.exs`: the mock
# rejects the FIRST request with -32022, and
# `sep-2575-client-retry-supported-version` starts as WARNING and only becomes
# SUCCESS when a LATER request carries 2026-07-28 in both the header and
# `_meta`. Our client does **not** retry — the transport discards a JSON-RPC
# error body carried on a 400 — so the SUCCESS comes from the fixture's
# re-evaluation rule firing on the NEXT call the adapter makes. A WARNING fails
# a scenario under `client_summary`. So on this leg, 8/8 is contingent on a
# policy of ours, not on a property of the SDK.
#
# That is an argument. This file turns it into a measurement: run the SAME
# scenario, against the SAME fixture, at the SAME tree, changing exactly one
# thing — halt the moment `connect/1` errors — and read the verdict off the
# harness. If `request-metadata` goes red here and stays green under the
# measurement adapter, the discount holds ON THIS TREE. If it stays green, the
# discount has lapsed, and that is a finding worth more than the number.
#
# ## Why it is NARROW, deliberately
#
# It drives ONE scenario: `request-metadata`. Every other scenario takes the
# not-driven path and exits 0, exactly as the measurement adapter's does.
#
# Reading any other row of this run's sheet is a category error, and the census
# files it as role `probe` so that no classification paperwork and no control
# subtraction is computed over it (`MCP.Conformance.Adapters`). The report quotes
# exactly one cell from this run.
#
# ## Why it duplicates a clause instead of importing the measurement adapter
#
# The alternative — an environment-variable policy switch threaded through
# `client_adapter.exs` — was rejected. The measurement instrument must not
# acquire a second mode mid-sprint: a run's result would then depend on an
# environment variable that its own manifest does not record, and comparability
# with Sprint 4 would rest on that variable having been unset. Here the
# difference between the two adapters is one `case` in one function, in a file
# short enough to read whole.
#
# The cost is real and is stated rather than hidden: the drive list below is a
# COPY of the measurement adapter's `request-metadata` clause, and a change
# there would not propagate here. `MCP.Conformance.RunIndexTest` holds the two
# lists equal so the copy cannot drift silently.
#
# ## Exit code discipline — inherited verbatim, and load-bearing
#
# The harness's reducer fails a scenario on `exitCode !== 0` INDEPENDENTLY of
# every check. A non-zero exit would therefore replace the measurement with a
# note about this file. Halting means "stop driving", never "exit non-zero":
# the whole point is to let the fail-closed checks say what a strict client
# would have scored.

defmodule MCP.Conformance.StrictConnectProbe do
  @moduledoc false

  alias MCP.Client

  alias MCP.Protocol.Capabilities.{
    ClientCapabilities,
    ElicitationCapabilities,
    RootCapabilities,
    SamplingCapabilities
  }

  # The single scenario this probe drives, read from the ADAPTER REGISTRY rather
  # than spelled here. Two consumers need this list — this file, and
  # `MCP.Conformance.Discounts`, which must read every OTHER row of this run's
  # sheet as meaningless rather than as a failure — and a second spelling is a
  # second thing to forget. Declaring it in one place is the same move
  # `MCP.Conformance.Adapters` exists for.
  @driven MCP.Conformance.Adapters.scope(:client, "strict_connect")

  # The call labels the measurement adapter drives for `request-metadata`, in
  # order. Kept as data for the same reason.
  @request_metadata_calls ["server/discover", "tools/list", "tools/call any_tool"]

  @doc false
  def driven, do: @driven

  @doc false
  def request_metadata_calls, do: @request_metadata_calls

  def run do
    server_url = List.last(System.argv()) || raise "Server URL required as last argument"
    scenario = System.get_env("MCP_CONFORMANCE_SCENARIO") || ""

    IO.puts("Scenario: #{scenario}")
    IO.puts("Server URL: #{server_url}")
    IO.puts(:stderr, "DRIVE POLICY: strict — halt on a connect/1 error")

    if scenario in @driven do
      run_scenario(scenario, server_url)
      IO.puts("Scenario '#{scenario}' completed")
    else
      not_driven(scenario)
    end
  end

  # Byte-for-byte the measurement adapter's clause, with `drive/2` replaced by
  # `connect/2` on the first call. That first call is the only difference
  # between the two adapters, which is what makes the comparison a measurement
  # of the policy rather than of two different clients.
  defp run_scenario("request-metadata", url) do
    with_client(url, fn client ->
      connect(client, fn ->
        drive("tools/list", fn -> Client.list_tools(client) end)
        drive("tools/call any_tool", fn -> Client.call_tool(client, "any_tool", %{}) end)
      end)
    end)
  end

  defp not_driven(scenario) do
    IO.puts(:stderr, """
    NOT DRIVEN: scenario #{inspect(scenario)} is outside this PROBE's one scenario.

    This file is not the measurement adapter and not a null control. It drives
    `request-metadata` alone, under a strict connect policy, to establish
    whether that scenario's pass depends on the measurement adapter's carry-on
    policy. Every other row of this run's sheet is meaningless and the census
    files the run as role `probe` so that nothing is computed over it.

    Exiting 0 on purpose, as the measurement adapter does: the harness reducer
    fails a scenario on a non-zero exit independently of every check, which
    would hide what the checks would have said.
    """)
  end

  # --- Plumbing ------------------------------------------------------------

  # THE ONE DIFFERENCE. Where the measurement adapter's `drive/2` logs an error
  # and carries on, this stops the drive dead: no later call is made, so no
  # later request can re-trigger the fixture's re-evaluation rule, and the
  # checks that would have been satisfied by a later request stay unsatisfied.
  #
  # It returns normally rather than raising: a raise exits non-zero, and a
  # non-zero exit fails the scenario on the reducer's exit-code disjunct
  # INSTEAD of on its checks — which would make this probe measure its own
  # crash rather than the strict policy.
  defp connect(client, continue) do
    case Client.connect(client) do
      {:ok, value} ->
        IO.puts(:stderr, "DRIVE ok    server/discover")
        continue.()
        value

      {:error, reason} ->
        IO.puts(
          :stderr,
          "DRIVE ERROR server/discover: #{inspect(reason, limit: 10)} — HALTING (strict policy)"
        )

        nil

      other ->
        IO.puts(:stderr, "DRIVE ok    server/discover -> #{inspect(other, limit: 5)}")
        continue.()
        other
    end
  end

  defp drive(label, fun) do
    case fun.() do
      {:ok, value} ->
        IO.puts(:stderr, "DRIVE ok    #{label}")
        value

      {:error, reason} ->
        IO.puts(:stderr, "DRIVE ERROR #{label}: #{inspect(reason, limit: 10)}")
        nil

      other ->
        IO.puts(:stderr, "DRIVE ok    #{label} -> #{inspect(other, limit: 5)}")
        other
    end
  end

  defp with_client(url, fun) do
    {:ok, client} = start_client(url)

    try do
      fun.(client)
    after
      Client.close(client)
    end
  end

  # Identical to the measurement adapter's, including the three declared
  # capabilities: `request-metadata` scores each SKIPPED when absent and SUCCESS
  # when present-and-an-object, so a probe that declared fewer would differ from
  # the measurement in a SECOND way and the comparison would establish nothing.
  defp start_client(url) do
    Client.start_link(
      transport: {MCP.Transport.StreamableHTTP.Client, url: url, headers: []},
      client_info: %{name: "mcp_elixir_sdk_conformance", version: "1.0.0"},
      client_capabilities: %ClientCapabilities{
        roots: %RootCapabilities{},
        sampling: %SamplingCapabilities{},
        elicitation: %ElicitationCapabilities{}
      }
    )
  end
end

# MES-51 beacon, same call site and same guarantees as the measurement
# adapter's: a no-op unless the runner set MCP_CONFORMANCE_BEACON, writes to a
# file and never to stdout, stderr or the wire, cannot raise or change an exit
# code. It names THIS file, which is how `MCP.Conformance.Census` tells a probe
# run from a measurement run without taking the manifest's word for it.
if Code.ensure_loaded?(MCP.Conformance.Beacon) do
  MCP.Conformance.Beacon.emit(:adapter, __ENV__.file)
end

MCP.Conformance.StrictConnectProbe.run()
