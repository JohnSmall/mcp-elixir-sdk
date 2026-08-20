defmodule MCP.ClientConformanceTest do
  @moduledoc """
  MES-18 — the two client conformance items that need evidence rather than code:
  CG4 (`$ref` must not be dereferenced) and CG2 (extensions negotiation, the
  inbound half).

  ## Evidence posture (A7)

  Both are **POSITIVE CONTROLS**, and CG4's is a control of an unusual kind —
  a **guard on an unguarded property**. It cannot be a caught regression
  because the property already held at `2829769`; what it catches is the
  future day someone adds a `$ref` resolver. That is worth writing precisely
  because nothing in the code enforces the property today.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MCP.Client
  alias MCP.Protocol.Capabilities.ClientCapabilities
  alias MCP.Test.MockTransport
  alias MCP.Transport.StreamableHTTP.Client, as: HTTPClient

  describe "CG4 / T-CG4 — the client MUST NOT dereference a network $ref" do
    # `basic/index.mdx:299-310` at the pinned commit: "Implementations MUST NOT
    # automatically dereference $ref values that resolve to a network URI."
    # The scored scenario `json-schema-ref-no-deref` (check
    # `sep-2106-no-network-ref-deref`) inverts on a canary counter: FAILURE iff
    # the canary was hit at all.
    #
    # We pass BY CONSTRUCTION, of an ABSENCE: nothing in `lib/` walks a schema,
    # `Jason` is a pure codec with no socket, and `Req` only fetches the URL it
    # is given — which is only ever `state.url`. That is not luck (no
    # coincidence is doing the work) but it is UNGUARDED: the property holds
    # because a feature is missing, and nothing stops someone adding it.
    defmodule CanaryPlug do
      @moduledoc false
      import Plug.Conn

      def init(agent), do: agent

      def call(conn, agent) do
        Agent.update(agent, &(&1 + 1))
        send_resp(conn, 200, ~s({"type":"string"}))
      end
    end

    defmodule ToolServerPlug do
      @moduledoc false
      import Plug.Conn

      def init(canary_url), do: canary_url

      def call(conn, canary_url) do
        {:ok, body, conn} = read_body(conn)
        message = Jason.decode!(body)

        result =
          case message["method"] do
            "tools/list" ->
              %{
                "tools" => [
                  %{
                    "name" => "with_ref",
                    "inputSchema" => %{
                      "$schema" => "https://json-schema.org/draft/2020-12/schema",
                      "type" => "object",
                      "properties" => %{"profile" => %{"$ref" => canary_url}}
                    }
                  }
                ]
              }

            _ ->
              %{"resultType" => "complete", "content" => []}
          end

        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(
          200,
          Jason.encode!(%{"jsonrpc" => "2.0", "id" => message["id"], "result" => result})
        )
      end
    end

    setup do
      {:ok, hits} = Agent.start_link(fn -> 0 end)
      canary_port = free_port()
      server_port = free_port()

      {:ok, canary} =
        Bandit.start_link(
          plug: {CanaryPlug, hits},
          port: canary_port,
          ip: {127, 0, 0, 1},
          startup_log: false
        )

      {:ok, server} =
        Bandit.start_link(
          plug: {ToolServerPlug, "http://127.0.0.1:#{canary_port}/schema.json"},
          port: server_port,
          ip: {127, 0, 0, 1},
          startup_log: false
        )

      on_exit(fn ->
        for pid <- [canary, server], Process.alive?(pid), do: Process.exit(pid, :normal)
      end)

      %{hits: hits, url: "http://127.0.0.1:#{server_port}/mcp", canary_port: canary_port}
    end

    test "listing and calling a tool whose inputSchema $refs a network URI never fetches it", %{
      hits: hits,
      url: url
    } do
      {:ok, client} = Client.start_link(transport: {HTTPClient, url: url})

      capture_log(fn ->
        assert {:ok, %{"tools" => [tool]}} = Client.list_tools(client)
        # The $ref survives as inert data — we neither fetch it nor rewrite it.
        assert %{"$ref" => ref} = tool["inputSchema"]["properties"]["profile"]
        assert ref =~ "http://127.0.0.1:"

        assert {:ok, _} = Client.call_tool(client, "with_ref", %{"profile" => "anything"})
      end)

      assert Agent.get(hits, & &1) == 0
    end

    test "CONTROL ON THE CONTROL: the canary really does count a fetch" do
      # A canary that cannot register a hit would make the test above pass for
      # the wrong reason — the "silently no-ops" failure the gap register
      # confessed to. This proves the instrument works.
      {:ok, hits} = Agent.start_link(fn -> 0 end)
      port = free_port()

      {:ok, canary} =
        Bandit.start_link(
          plug: {CanaryPlug, hits},
          port: port,
          ip: {127, 0, 0, 1},
          startup_log: false
        )

      on_exit(fn -> if Process.alive?(canary), do: Process.exit(canary, :normal) end)

      {:ok, _} = Req.get("http://127.0.0.1:#{port}/schema.json")
      assert Agent.get(hits, & &1) == 1
    end
  end

  describe "CG2 / T-CG2 — extensions negotiation, both directions" do
    # The gap register records CG2's inbound half as absent, on the strength of
    # a grep of `discover.ex`. The grep is true and the conclusion does not
    # follow: `Discover.Result.from_map/1` delegates capability parsing to
    # `ServerCapabilities.from_map/1` (`server_capabilities.ex:36`), which does
    # parse `extensions`. CG2 was functionally CLOSED and evidentially OPEN;
    # this is the evidence.
    defp discover(client, transport, capabilities) do
      task = Task.async(fn -> Client.connect(client) end)
      Process.sleep(20)
      [request] = MockTransport.sent_messages(transport)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => request["id"],
        "result" => %{
          "supportedVersions" => ["2026-07-28"],
          "capabilities" => capabilities,
          "resultType" => "complete",
          "_meta" => %{
            "io.modelcontextprotocol/serverInfo" => %{"name" => "s", "version" => "1"}
          }
        }
      })

      {{:ok, result}, request} = {Task.await(task), request}
      {result, request}
    end

    test "the client can read what the server declared, with the settings map intact" do
      {:ok, client} = Client.start_link(transport: {MockTransport, []})
      transport = Client.transport(client)

      extensions = %{
        "io.modelcontextprotocol/tasks" => %{},
        "com.example/thing" => %{"mimeTypes" => ["text/html"], "nested" => %{"depth" => 2}}
      }

      {result, _request} =
        discover(client, transport, %{"tools" => %{}, "extensions" => extensions})

      assert result.server_capabilities.extensions == extensions
      assert Client.server_capabilities(client).extensions == extensions

      # An extension we do not implement is neither rejected, nor rewritten,
      # nor reported as a fault — the posture `extensions.ex:56-61` commits to
      # in prose and nothing tested.
      assert get_in(result.server_capabilities.extensions, [
               "com.example/thing",
               "nested",
               "depth"
             ]) == 2
    end

    test "a server declaring NO extensions yields nil, not a crash or an invented map" do
      {:ok, client} = Client.start_link(transport: {MockTransport, []})
      transport = Client.transport(client)

      {result, _request} = discover(client, transport, %{"tools" => %{}})
      assert result.server_capabilities.extensions == nil
    end

    test "an unknown extension is not logged as a fault" do
      {:ok, client} = Client.start_link(transport: {MockTransport, []})
      transport = Client.transport(client)

      log =
        capture_log(fn ->
          discover(client, transport, %{
            "extensions" => %{"com.unknown/whatever" => %{"a" => 1}}
          })
        end)

      refute log =~ "[error]"
      refute log =~ "[warning]"
    end

    test "the OUTBOUND half (MES-16) still rides every request's _meta" do
      {:ok, client} =
        Client.start_link(
          transport: {MockTransport, []},
          client_capabilities: %ClientCapabilities{
            extensions: %{"com.example/ext" => %{"setting" => true}}
          }
        )

      transport = Client.transport(client)
      {_result, request} = discover(client, transport, %{"tools" => %{}})

      assert request["params"]["_meta"]["io.modelcontextprotocol/clientCapabilities"][
               "extensions"
             ] == %{"com.example/ext" => %{"setting" => true}}
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
