defmodule MCP.Transport.ListenerPortRaceTest do
  @moduledoc """
  MES-215 — the controls for how the test suite binds its listeners.

  The old helper, `free_port/0`, listened on port 0, read the port, closed the
  socket and handed the number to a later `Bandit.start_link(port: port)`. In
  between, the port was free to anyone; on two binding gate-5 seeds something
  took it, and the CG4 canary control in `client_conformance_test.exs` failed with
  `failed to start child: :listener ** (EXIT) :eaddrinuse`.

  The window is forced here rather than waited for: a squatter listens on the
  chosen port after it is chosen and before the bind (RC1, RC2). RC3 holds the
  whole test tree to the replacement, `MCP.Test.Listener.bandit!/2`.
  """
  use ExUnit.Case, async: false

  alias MCP.Test.Listener
  alias MCP.Test.StatelessHandler
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  # RC3's allow-list, the one place it is written: path => the rules that path is
  # exempt from, and why.
  @allowed %{
    # This file: RC1 plants the old pattern, verbatim, in order to show it collide.
    "test/mcp/transport/listener_port_race_test.exs" => [:name, :listen_zero, :bind_port],
    # The one binder. Its port comes from its own pick/0; RC2 holds that pick to 0.
    "test/support/listener.ex" => [:bind_port],
    # W-4: a canary listen(0) socket held open for the whole test, never released.
    "test/mcp/server/json_schema_2020_12_test.exs" => [:listen_zero],
    # N7: a raw listen(0) socket held open and accepted on; it is the server.
    "test/mcp/client_malformed_reply_test.exs" => [:listen_zero]
  }

  @starters [
    {[:Bandit], :start_link},
    {[:ThousandIsland], :start_link},
    {[:MCP, :Test, :Listener], :bandit!},
    {[:Listener], :bandit!}
  ]

  defp opts do
    [
      plug: MCPPlug.new(server_mod: StatelessHandler, enable_json_response: true),
      ip: {127, 0, 0, 1},
      startup_log: false
    ]
  end

  # The forced interleaving: take the port before the listener binds it.
  defp squat(port),
    do: :gen_tcp.listen(port, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

  # The pattern MES-215 removed, verbatim from client_conformance_test.exs at d9aaff1.
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  @tag oc: :none
  @tag oc_reason: "harness-only: how the test suite binds its listeners; no wire behaviour"
  test "RC1: the old pick-then-bind collides when the window is taken" do
    Process.flag(:trap_exit, true)
    port = free_port()
    {:ok, squatter} = squat(port)

    assert {:error, {:shutdown, {:failed_to_start_child, :listener, :eaddrinuse}}} =
             Bandit.start_link(Keyword.put(opts(), :port, port))

    :gen_tcp.close(squatter)
  end

  @tag oc: :none
  @tag oc_reason: "harness-only: how the test suite binds its listeners; no wire behaviour"
  test "RC2: bandit!/2 leaves no port to take before the bind" do
    me = self()

    hook = fn
      0 ->
        send(me, :nothing_to_take)

      port ->
        {:ok, squatter} = squat(port)
        send(me, {:took, port, squatter})
    end

    {_server, port} = Listener.bandit!(Keyword.put(opts(), :port, 0), hook)

    assert_received :nothing_to_take
    refute_received {:took, _, _}
    assert port > 0
    # Bound before its number was known, so the squatter now loses the race.
    assert {:error, :eaddrinuse} = squat(port)
    # And the port is the listener's: Bandit answers on it.
    assert {:ok, %Req.Response{status: status}} =
             Req.get("http://127.0.0.1:#{port}/", retry: false)

    assert is_integer(status)
  end

  @tag oc: :none
  @tag oc_reason: "harness-only: how the test suite binds its listeners; no wire behaviour"
  test "RC3: no test picks a port before it binds it" do
    # Control on the control: the scan finds the old pattern, both by name and
    # by shape, and a bind of a picked port.
    planted = """
    defp free_port do
      {:ok, s} = :gen_tcp.listen(0, [])
    end
    Bandit.start_link(plug: P, port: port)
    """

    assert [{:name, 1}, {:listen_zero, 2}, {:bind_port, 4}] =
             planted |> scan() |> Enum.sort_by(&elem(&1, 1))

    defects =
      for path <- Path.wildcard("test/**/*.{ex,exs}") |> Enum.sort(),
          {rule, line} <- path |> File.read!() |> scan(),
          rule not in Map.get(@allowed, path, []),
          do: "#{path}:#{line} #{rule}"

    assert defects == [], "pick-then-bind in the test tree:\n" <> Enum.join(defects, "\n")
  end

  # Every {rule, line} in `source`:
  #   :name        — the word free_port;
  #   :listen_zero — a :gen_tcp/:ssl listen on port 0, the probe half of a pick;
  #   :bind_port   — a listener start whose :port is not the literal 0.
  defp scan(source) do
    lines = String.split(source, "\n")

    named =
      for {text, n} <- Enum.with_index(lines, 1),
          String.contains?(text, "free_port"),
          do: {:name, n}

    probes =
      for {text, n} <- Enum.with_index(lines, 1),
          Regex.match?(~r/:(gen_tcp|ssl)\.listen\(\s*0\b/, text),
          do: {:listen_zero, n}

    named ++ probes ++ binds(source)
  end

  defp binds(source) do
    {:ok, ast} = Code.string_to_quoted(source, columns: false)

    {_, acc} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, mod}, fun]}, meta, args} = node, acc ->
          if {mod, fun} in @starters,
            do: {node, bind_defect(args, meta, acc)},
            else: {node, acc}

        # A child spec, `{Bandit, opts}`, as start_supervised!/1 takes it.
        {{:__aliases__, meta, [:Bandit]}, kw} = node, acc when is_list(kw) ->
          {node, bind_defect([kw], meta, acc)}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp bind_defect([kw | _], meta, acc) when is_list(kw) do
    if Keyword.keyword?(kw) and Keyword.get(kw, :port) === 0,
      do: acc,
      else: [{:bind_port, meta[:line]} | acc]
  end

  defp bind_defect(_args, meta, acc), do: [{:bind_port, meta[:line]} | acc]
end
