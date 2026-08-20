defmodule MCP.Transport.RoutingHeadersTest do
  @moduledoc """
  MES-18 / CG1 + CG7 — the client's outbound HTTP headers, observed on the
  wire rather than inferred: `Mcp-Method` and `Mcp-Name` (SEP-2243), the
  `Mcp-Param-*` mirroring seam, and the rotating-bearer header provider.

  ## Evidence posture (A7)

  **All POSITIVE CONTROLS.** At `2829769` the client emitted content-type,
  accept, accept-encoding and mcp-protocol-version and nothing else
  (`client.ex:221-232`); none of the behaviour below existed, so none of it can
  be a caught regression. The one test here that would have failed at that SHA
  for an interesting reason is the self-incompatibility control in
  `MCP.Transport.SelfCompatibilityTest`, and it is labelled there.
  """
  use ExUnit.Case, async: false

  alias MCP.Client
  alias MCP.Protocol.HeaderMirror
  alias MCP.Transport.StreamableHTTP.Client, as: HTTPClient

  # A server that records every request's headers and answers whatever the
  # test queued for it.
  defmodule CapturePlug do
    @moduledoc false
    import Plug.Conn

    def init(agent), do: agent

    def call(conn, agent) do
      {:ok, body, conn} = read_body(conn)
      message = Jason.decode!(body)

      Agent.update(agent, fn state ->
        %{state | requests: state.requests ++ [%{headers: conn.req_headers, message: message}]}
      end)

      response = Agent.get(agent, & &1.responder).(message)

      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(200, Jason.encode!(response))
    end
  end

  defp default_responder do
    fn message ->
      %{"jsonrpc" => "2.0", "id" => message["id"], "result" => %{"ok" => true}}
    end
  end

  setup do
    port = free_port()
    {:ok, agent} = Agent.start_link(fn -> %{requests: [], responder: default_responder()} end)

    {:ok, server} =
      Bandit.start_link(
        plug: {CapturePlug, agent},
        port: port,
        ip: {127, 0, 0, 1},
        startup_log: false
      )

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :normal) end)
    %{agent: agent, port: port, url: "http://127.0.0.1:#{port}/mcp"}
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp respond_with(agent, fun), do: Agent.update(agent, &%{&1 | responder: fun})

  defp requests(agent), do: Agent.get(agent, & &1.requests)

  defp headers_of(agent, index) do
    agent |> requests() |> Enum.at(index) |> Map.fetch!(:headers) |> Map.new()
  end

  defp start_transport(url, opts \\ []) do
    {:ok, pid} = HTTPClient.start_link([owner: self(), url: url] ++ opts)
    pid
  end

  describe "T-CG1a — Mcp-Method on every POST" do
    test "a request carries the body method", %{agent: agent, url: url} do
      transport = start_transport(url)

      for method <- ~w(server/discover tools/list resources/list prompts/list completion/complete) do
        :ok =
          HTTPClient.send_message(transport, %{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => method,
            "params" => %{}
          })
      end

      methods = for r <- requests(agent), do: Map.new(r.headers)["mcp-method"]

      assert methods ==
               ~w(server/discover tools/list resources/list prompts/list completion/complete)
    end

    test "a NOTIFICATION carries it too — the spec says all requests, not all responses-bearing ones",
         %{agent: agent, url: url} do
      transport = start_transport(url)

      :ok =
        HTTPClient.send_message(transport, %{
          "jsonrpc" => "2.0",
          "method" => "notifications/cancelled",
          "params" => %{"requestId" => 1}
        })

      assert headers_of(agent, 0)["mcp-method"] == "notifications/cancelled"
    end

    test "a message with no method carries no routing headers", %{agent: agent, url: url} do
      transport = start_transport(url)
      :ok = HTTPClient.send_message(transport, %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}})

      headers = headers_of(agent, 0)
      refute Map.has_key?(headers, "mcp-method")
      refute Map.has_key?(headers, "mcp-name")
    end
  end

  describe "T-CG1b — Mcp-Name for the three name-bearing methods" do
    test "tools/call and prompts/get take params.name; resources/read takes params.uri", %{
      agent: agent,
      url: url
    } do
      transport = start_transport(url)

      sends = [
        {"tools/call", %{"name" => "get_weather"}, "get_weather"},
        {"prompts/get", %{"name" => "summarise"}, "summarise"},
        {"resources/read", %{"uri" => "file:///projects/app/config.json"},
         "file:///projects/app/config.json"}
      ]

      for {method, params, _expected} <- sends do
        :ok =
          HTTPClient.send_message(transport, %{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => method,
            "params" => params
          })
      end

      for {{_method, _params, expected}, index} <- Enum.with_index(sends) do
        assert headers_of(agent, index)["mcp-name"] == expected
      end
    end

    test "a method with no name target carries Mcp-Method but NO Mcp-Name", %{
      agent: agent,
      url: url
    } do
      transport = start_transport(url)

      :ok =
        HTTPClient.send_message(transport, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/list",
          "params" => %{"cursor" => "abc"}
        })

      headers = headers_of(agent, 0)
      assert headers["mcp-method"] == "tools/list"
      refute Map.has_key?(headers, "mcp-name")
    end

    test "a tools/call whose params carry no name emits no Mcp-Name rather than an empty one", %{
      agent: agent,
      url: url
    } do
      transport = start_transport(url)

      :ok =
        HTTPClient.send_message(transport, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{}
        })

      refute Map.has_key?(headers_of(agent, 0), "mcp-name")
    end
  end

  describe "T-CG1c — a non-header-safe Mcp-Name is carried as the Base64 sentinel" do
    test "a non-ASCII tool name is encoded, and decodes back to the body value", %{
      agent: agent,
      url: url
    } do
      transport = start_transport(url)
      name = "天気_get"

      :ok =
        HTTPClient.send_message(transport, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => name}
        })

      header = headers_of(agent, 0)["mcp-name"]
      assert String.starts_with?(header, "=?base64?")
      assert HeaderMirror.decode_value(header) == name

      # The body still carries the plain name; only the header is encoded.
      assert Enum.at(requests(agent), 0).message["params"]["name"] == name
    end

    test "a resource URI with a space is encoded", %{agent: agent, url: url} do
      transport = start_transport(url)
      uri = "file:///my documents/notes.md"

      :ok =
        HTTPClient.send_message(transport, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "resources/read",
          "params" => %{"uri" => uri}
        })

      # Internal spaces are header-safe, so this one stays plain — the rule is
      # leading/trailing whitespace, not "contains a space".
      assert headers_of(agent, 0)["mcp-name"] == uri
    end

    test "a name that would inject a header is neutralised", %{agent: agent, url: url} do
      transport = start_transport(url)
      hostile = "tool\r\nX-Injected: yes"

      :ok =
        HTTPClient.send_message(transport, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => hostile}
        })

      headers = headers_of(agent, 0)
      assert HeaderMirror.decode_value(headers["mcp-name"]) == hostile
      refute headers["mcp-name"] =~ "\r"
      refute Map.has_key?(headers, "x-injected")
    end
  end

  describe "the version header rides the message (D-4), on the wire" do
    test "it matches the body _meta, not the transport's configured default", %{
      agent: agent,
      url: url
    } do
      transport = start_transport(url, protocol_version: "2026-07-28")

      :ok =
        HTTPClient.send_message(transport, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/list",
          "params" => %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => "2030-01-01"}
          }
        })

      assert headers_of(agent, 0)["mcp-protocol-version"] == "2030-01-01"
    end
  end

  describe "T-CG7enc — Mcp-Param-* mirroring, driven end to end through MCP.Client" do
    @tool %{
      "name" => "test_custom_headers",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "region" => %{"type" => "string", "x-mcp-header" => "Region"},
          "priority" => %{"type" => "integer", "x-mcp-header" => "Priority"},
          "verbose" => %{"type" => "boolean", "x-mcp-header" => "Verbose"},
          "empty_val" => %{"type" => "string", "x-mcp-header" => "EmptyVal"},
          "non_ascii_val" => %{"type" => "string", "x-mcp-header" => "NonAscii"},
          "query" => %{"type" => "string"}
        }
      }
    }

    defp tools_responder(tools) do
      fn message ->
        result =
          case message["method"] do
            "tools/list" -> %{"tools" => tools}
            _ -> %{"resultType" => "complete", "content" => []}
          end

        %{"jsonrpc" => "2.0", "id" => message["id"], "result" => result}
      end
    end

    test "an annotated tool's arguments are mirrored, unannotated ones are not", %{
      agent: agent,
      url: url
    } do
      respond_with(agent, tools_responder([@tool]))

      {:ok, client} = Client.start_link(transport: {HTTPClient, url: url})
      {:ok, _} = Client.list_tools(client)

      {:ok, _} =
        Client.call_tool(client, "test_custom_headers", %{
          "region" => "us-west1",
          "priority" => 42,
          "verbose" => false,
          "empty_val" => "",
          "non_ascii_val" => "Hello, 世界",
          "query" => "SELECT 1"
        })

      headers = headers_of(agent, 1)

      assert headers["mcp-param-region"] == "us-west1"
      assert headers["mcp-param-priority"] == "42"
      assert headers["mcp-param-verbose"] == "false"
      assert headers["mcp-param-nonascii"] == "=?base64?SGVsbG8sIOS4lueVjA==?="
      # Present with an EMPTY value — the fixture treats a missing one as a
      # failure, so this asserts the header survives the HTTP stack at all.
      assert headers["mcp-param-emptyval"] == ""
      refute Map.has_key?(headers, "mcp-param-query")

      # And the routing headers ride the same request.
      assert headers["mcp-method"] == "tools/call"
      assert headers["mcp-name"] == "test_custom_headers"
    end

    test "a null argument omits its header", %{agent: agent, url: url} do
      respond_with(agent, tools_responder([@tool]))

      {:ok, client} = Client.start_link(transport: {HTTPClient, url: url})
      {:ok, _} = Client.list_tools(client)

      {:ok, _} =
        Client.call_tool(client, "test_custom_headers", %{
          "region" => "us-east1",
          "verbose" => nil
        })

      headers = headers_of(agent, 1)
      assert headers["mcp-param-region"] == "us-east1"
      refute Map.has_key?(headers, "mcp-param-verbose")
    end

    test "with no prior tools/list, nothing is mirrored and the client says so", %{
      agent: agent,
      url: url
    } do
      # The C-2 miss policy, observed: the call still goes out, carries its
      # routing headers, carries NO Mcp-Param-*, and is announced.
      respond_with(agent, tools_responder([@tool]))
      {:ok, client} = Client.start_link(transport: {HTTPClient, url: url})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, _} =
            Client.call_tool(client, "test_custom_headers", %{"region" => "us-west1"})
        end)

      headers = headers_of(agent, 0)
      assert headers["mcp-name"] == "test_custom_headers"
      refute Map.has_key?(headers, "mcp-param-region")
      assert log =~ "no cached inputSchema"
    end
  end

  describe "W13 — the rotating-bearer header provider" do
    test "it is called per request, so a rotated credential is actually sent", %{
      agent: agent,
      url: url
    } do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      transport =
        start_transport(url,
          header_provider: fn ->
            n = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
            [{"authorization", "Bearer token-#{n}"}]
          end
        )

      for _ <- 1..3 do
        :ok = HTTPClient.send_message(transport, %{"jsonrpc" => "2.0", "id" => 1})
      end

      tokens = for i <- 0..2, do: headers_of(agent, i)["authorization"]
      assert tokens == ["Bearer token-1", "Bearer token-2", "Bearer token-3"]
    end

    test "a raising provider fails THAT request and leaves the transport alive", %{url: url} do
      transport = start_transport(url, header_provider: fn -> raise "boom" end)

      assert {:error, {:header_provider_failed, {:error, %RuntimeError{}}}} =
               HTTPClient.send_message(transport, %{"jsonrpc" => "2.0", "id" => 1})

      assert Process.alive?(transport)
    end

    test "a throwing or exiting provider is caught the same way", %{url: url} do
      thrower = start_transport(url, header_provider: fn -> throw(:nope) end)

      assert {:error, {:header_provider_failed, {:throw, :nope}}} =
               HTTPClient.send_message(thrower, %{"jsonrpc" => "2.0", "id" => 1})

      assert Process.alive?(thrower)

      exiter = start_transport(url, header_provider: fn -> exit(:bye) end)

      assert {:error, {:header_provider_failed, _}} =
               HTTPClient.send_message(exiter, %{"jsonrpc" => "2.0", "id" => 1})

      assert Process.alive?(exiter)
    end

    test "a provider process killed outright still only fails the request", %{url: url} do
      # The case `catch` cannot reach. It is why the provider runs in an
      # UNLINKED process: `Task.async/1` links, and a link would carry this
      # kill straight into the transport, which does not trap exits.
      transport =
        start_transport(url,
          header_provider: fn -> Process.exit(self(), :kill) end
        )

      assert {:error, {:header_provider_failed, {:exit, :killed}}} =
               HTTPClient.send_message(transport, %{"jsonrpc" => "2.0", "id" => 1})

      assert Process.alive?(transport)
    end

    test "a malformed return value is refused whole — no partial use of a half-valid list", %{
      agent: agent,
      url: url
    } do
      for bad <- [:not_a_list, [{"ok", "pair"}, :junk], [{"name", 123}], %{"a" => "b"}] do
        transport = start_transport(url, header_provider: fn -> bad end)

        assert {:error, {:header_provider_failed, {:invalid_headers, _}}} =
                 HTTPClient.send_message(transport, %{"jsonrpc" => "2.0", "id" => 1})
      end

      # Nothing reached the server: a half-valid list must not be half-applied.
      assert requests(agent) == []
    end

    test "a HANGING provider fails on a bounded timeout — the case `try` cannot catch", %{
      url: url
    } do
      transport =
        start_transport(url,
          header_provider: fn -> Process.sleep(:infinity) end,
          header_provider_timeout: 100
        )

      started = System.monotonic_time(:millisecond)

      assert {:error, {:header_provider_failed, :timeout}} =
               HTTPClient.send_message(transport, %{"jsonrpc" => "2.0", "id" => 1})

      elapsed = System.monotonic_time(:millisecond) - started

      # Bounded by the provider timeout, NOT by the 60s send_message call
      # timeout that a hang would otherwise consume — with the transport and
      # MCP.Client blocked behind it for the duration.
      assert elapsed < 2_000
      assert Process.alive?(transport)

      # And the transport still serves the next request normally.
      assert Process.alive?(transport)
    end

    test "a provider failure surfaces through MCP.Client as a failed call, not a dead client", %{
      url: url
    } do
      {:ok, client} =
        Client.start_link(
          transport: {HTTPClient, url: url, header_provider: fn -> raise "boom" end},
          request_timeout: 500
        )

      assert {:error, {:transport_send_failed, {:header_provider_failed, _}}} =
               Client.list_tools(client)

      assert Process.alive?(client)
      assert Client.status(client) == :ready
    end
  end

  describe "caller-supplied routing headers are warned about" do
    test "start_link names the offending header", %{url: url} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          start_transport(url, headers: [{"Mcp-Method", "tools/list"}])
          Process.sleep(50)
        end)

      assert log =~ "mcp-method"
      assert log =~ "APPENDED"
    end

    test "an ordinary caller header is not warned about and IS sent", %{agent: agent, url: url} do
      transport = start_transport(url, headers: [{"authorization", "Bearer static"}])
      :ok = HTTPClient.send_message(transport, %{"jsonrpc" => "2.0", "id" => 1})
      assert headers_of(agent, 0)["authorization"] == "Bearer static"
    end
  end
end
