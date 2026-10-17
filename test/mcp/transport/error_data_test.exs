defmodule MCP.Transport.StreamableHTTP.ErrorDataTest do
  @moduledoc """
  MES-198 — the `data` of every JSON-RPC error the Streamable HTTP Plug writes
  for a body it refuses is a plain string naming the rule, never `inspect/1` of
  an Elixir term. Before MES-198 the -32600 replies carried
  `%MCP.Protocol.Error{…}` as text, the -32700 reply carried
  `%Jason.DecodeError{…, data: <the whole request body>}`, and a -32020 text
  rendered a non-string body value in Elixir term syntax (`nil`, `%{…}`,
  `<<…>>`).

  Each unit asserts the whole reply: the HTTP status and the whole JSON body,
  so `code`, `message`, `id` and `data` together.

  OC: `HttpServerHeaderMismatch400` drives the `MCP-Protocol-Version` vs `_meta`
  comparison and checks HTTP 400 with -32020, so the two units on that path
  name it. No in-scope OC check POSTs invalid JSON, a non-request body or a
  mismatched `Mcp-Method`/`Mcp-Name` to the server, so the others are
  `oc: :none`.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test
  import Plug.Conn

  alias MCP.Test.{StatelessHandler, UnreadableBodyAdapter}
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @pv "io.modelcontextprotocol/protocolVersion"
  @cc "io.modelcontextprotocol/clientCapabilities"
  @full %{@pv => @version, @cc => %{}}
  @std [{"mcp-protocol-version", @version}, {"mcp-method", "tools/list"}]

  defp base_conn(body) do
    :post
    |> conn("http://localhost/", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> put_req_header("origin", "http://localhost")
  end

  defp call(conn, headers) do
    conn =
      headers
      |> Enum.reduce(conn, fn {k, v}, c -> put_req_header(c, k, v) end)
      |> MCPPlug.call(MCPPlug.init(server_mod: StatelessHandler, enable_json_response: true))

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp post_raw(body, headers), do: body |> base_conn() |> call(headers)
  defp post(message, headers), do: post_raw(Jason.encode!(message), headers)

  defp reply(id, code, message, data),
    do: %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message, "data" => data}
    }

  defp invalid(id, data), do: {400, reply(id, -32_600, "Invalid request", data)}
  defp mismatch(id, data), do: {400, reply(id, -32_020, "Header mismatch", data)}

  describe "-32700 (plug.ex:347)" do
    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check POSTs invalid JSON to the server; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "invalid JSON: the data names the rule and does not echo the body" do
      assert post_raw("{not json", @std) ==
               {400, reply(nil, -32_700, "Parse error", "the request body is not valid JSON")}
    end
  end

  describe "-32600 with a readable id (plug.ex:371)" do
    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check POSTs a JSON-RPC response to the server; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "a client-sent response: the data is the Error's own rule text" do
      message = %{"jsonrpc" => "2.0", "id" => 7, "result" => %{}}

      assert post(message, [{"mcp-protocol-version", @version}]) ==
               invalid(7, "a client must not send a JSON-RPC response")
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check POSTs a malformed JSON-RPC error member; searched the pinned dist (a10085d0)"
    test "a malformed error member: the data is the Error's own rule text" do
      message = %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => "x", "message" => "m"}}

      assert post(message, []) ==
               invalid(
                 1,
                 "a JSON-RPC error member must be an object with an integer code and a string message"
               )
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check POSTs a wrong jsonrpc version to the server; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "jsonrpc \"1.0\": the data is the Error's own rule text" do
      message = %{
        "jsonrpc" => "1.0",
        "id" => 7,
        "method" => "tools/list",
        "params" => %{"_meta" => @full}
      }

      assert post(message, @std) == invalid(7, "Missing or invalid jsonrpc version")
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check POSTs an object with neither a method nor a result or error; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "an id and no method: the Error has no data, so the rule is named here" do
      message = %{"jsonrpc" => "2.0", "id" => 7}

      assert post(message, [{"mcp-protocol-version", @version}]) ==
               invalid(7, "a JSON-RPC message must carry a method, or a result or an error")
    end
  end

  describe "-32600 with no readable id (plug.ex:380)" do
    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check POSTs a batch to the server; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "an array (batch) body" do
      body = Jason.encode!([%{"jsonrpc" => "2.0", "id" => 7, "method" => "tools/list"}])

      assert post_raw(body, @std) ==
               invalid(
                 nil,
                 "the request body must be a single JSON-RPC request or notification object"
               )
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check POSTs a bare JSON value to the server; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "a bare string body" do
      assert post_raw(~s("x"), @std) ==
               invalid(
                 nil,
                 "the request body must be a single JSON-RPC request or notification object"
               )
    end

    @tag oc: :none
    @tag oc_reason:
           "a body read failure is adapter-level; no OC check can provoke one; searched the pinned dist (a10085d0)"
    test "an unreadable body: a fixed text on the wire, the reason in the log" do
      {result, log} =
        with_log(fn ->
          "{}" |> base_conn() |> UnreadableBodyAdapter.with_unreadable_body() |> call(@std)
        end)

      assert result == invalid(nil, "the request body could not be read")
      assert log =~ "MCP Plug: could not read the request body: :timeout"
    end
  end

  describe "-32020 renders a body value as JSON (plug.ex:933, :936, :1223)" do
    @tag oc: :none
    @tag oc_reason:
           "HttpServerHeaderMismatch400 drives only the MCP-Protocol-Version comparison; no OC check sends a mismatched Mcp-Method; searched the pinned dist (a10085d0)"
    test "Mcp-Method: a string as before, and an object as JSON" do
      message = %{"jsonrpc" => "2.0", "id" => 7, "params" => %{"_meta" => @full}}
      headers = [{"mcp-protocol-version", @version}, {"mcp-method", "prompts/list"}]

      assert post(Map.put(message, "method", "tools/list"), headers) ==
               mismatch(7, ~s(Mcp-Method prompts/list != "tools/list"))

      assert post(Map.put(message, "method", %{"a" => 1}), headers) ==
               mismatch(7, ~s(Mcp-Method prompts/list != {"a":1}))
    end

    @tag oc: :none
    @tag oc_reason:
           "HttpServerHeaderMismatch400 drives only the MCP-Protocol-Version comparison; no OC check sends a mismatched Mcp-Name; searched the pinned dist (a10085d0)"
    test "Mcp-Name: a string as before, and an object as JSON" do
      params = %{"arguments" => %{}, "_meta" => @full}

      headers = [
        {"mcp-protocol-version", @version},
        {"mcp-method", "tools/call"},
        {"mcp-name", "other"}
      ]

      call = fn name ->
        %{
          "jsonrpc" => "2.0",
          "id" => 7,
          "method" => "tools/call",
          "params" => Map.put(params, "name", name)
        }
      end

      assert post(call.("echo"), headers) == mismatch(7, ~s(Mcp-Name other != "echo"))
      assert post(call.(%{"a" => 1}), headers) == mismatch(7, ~s(Mcp-Name other != {"a":1}))
    end

    @tag oc:
           "oc:server/server-stateless/sep-2575-http-server-header-mismatch-400/HttpServerHeaderMismatch400"
    test "MCP-Protocol-Version: a printable version as before" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/list",
        "params" => %{"_meta" => Map.put(@full, @pv, "2025-11-25")}
      }

      assert post(message, @std) ==
               mismatch(7, ~s(MCP-Protocol-Version #{@version} != "2025-11-25"))
    end

    @tag oc:
           "oc:server/server-stateless/sep-2575-http-server-header-mismatch-400/HttpServerHeaderMismatch400"
    test "MCP-Protocol-Version: a control character is a JSON escape, not <<…>>" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/list",
        "params" => %{"_meta" => Map.put(@full, @pv, "20\u0001")}
      }

      assert post(message, @std) ==
               mismatch(7, ~s(MCP-Protocol-Version #{@version} != "20\\u0001"))
    end
  end

  describe "correction round 1: an adapter read failure is classified where the body is read (F1)" do
    # The adapter contract allows any term as the reason, so each of these is a
    # read failure, whatever it looks like: never decoder output, never data.
    defp unreadable(reason) do
      with_log(fn ->
        "{}"
        |> base_conn()
        |> UnreadableBodyAdapter.with_unreadable_body(reason)
        |> call(@std)
      end)
    end

    @tag oc: :none
    @tag oc_reason:
           "a body read failure is adapter-level; no OC check can provoke one; searched the pinned dist (a10085d0)"
    test "a reason that is an %MCP.Protocol.Error{} is a read failure, and is logged" do
      {result, log} = unreadable(%MCP.Protocol.Error{code: -32_600, message: "m", data: "decoy"})

      assert result == invalid(nil, "the request body could not be read")
      assert log =~ "MCP Plug: could not read the request body: %MCP.Protocol.Error{"
      assert log =~ "decoy"
    end

    @tag oc: :none
    @tag oc_reason:
           "a body read failure is adapter-level; no OC check can provoke one; searched the pinned dist (a10085d0)"
    test "a reason shaped like the Plug's own {:invalid_request, id, error} is a read failure" do
      {result, log} =
        unreadable({:invalid_request, 77, %MCP.Protocol.Error{code: -32_600, data: "decoy"}})

      assert result == invalid(nil, "the request body could not be read")
      assert log =~ "MCP Plug: could not read the request body: {:invalid_request, 77,"
    end

    @tag oc: :none
    @tag oc_reason:
           "a body read failure is adapter-level; no OC check can provoke one; searched the pinned dist (a10085d0)"
    test "the same shape with data that is not UTF-8 does not raise" do
      {result, log} =
        unreadable({:invalid_request, 77, %MCP.Protocol.Error{code: -32_600, data: <<255>>}})

      assert result == invalid(nil, "the request body could not be read")
      assert log =~ "MCP Plug: could not read the request body: {:invalid_request, 77,"
      assert log =~ "<<255>>"
    end
  end

  describe "correction round 1: error data that is not UTF-8 never raises (F1, defence in depth)" do
    @tag oc: :none
    @tag oc_reason:
           "invalid_detail/1 is a unit-level guard; no OC check reaches it with such data; searched the pinned dist (a10085d0)"
    test "invalid_detail/1 passes only a valid UTF-8 binary, else names the rule" do
      fallback = "a JSON-RPC message must carry a method, or a result or an error"

      assert MCPPlug.invalid_detail(%MCP.Protocol.Error{data: "a rule"}) == "a rule"
      assert MCPPlug.invalid_detail(%MCP.Protocol.Error{data: <<255>>}) == fallback
      assert MCPPlug.invalid_detail(%MCP.Protocol.Error{data: %{"a" => 1}}) == fallback
      assert MCPPlug.invalid_detail(%MCP.Protocol.Error{data: nil}) == fallback
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a header value that is not UTF-8; searched the pinned dist (a10085d0)"
    test "an Mcp-Method header that is not UTF-8: 400 / -32020, invalid bytes as U+FFFD" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/list",
        "params" => %{"_meta" => @full}
      }

      headers = [{"mcp-protocol-version", @version}, {"mcp-method", <<255>>}]

      assert post(message, headers) ==
               mismatch(7, ~s(Mcp-Method � != "tools/list"))
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends an Mcp-Name that decodes to bytes that are not UTF-8; searched the pinned dist (a10085d0)"
    test "an Mcp-Name sentinel decoding to bytes that are not UTF-8: 400 / -32020" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/call",
        "params" => %{"name" => "echo", "arguments" => %{}, "_meta" => @full}
      }

      headers = [
        {"mcp-protocol-version", @version},
        {"mcp-method", "tools/call"},
        {"mcp-name", "=?base64?" <> Base.encode64(<<255>>) <> "?="}
      ]

      assert post(message, headers) == mismatch(7, ~s(Mcp-Name � != "echo"))
    end

    @tag oc: :none
    @tag oc_reason:
           "HttpServerHeaderMismatch400 sends a UTF-8 header version only; no OC check sends one that is not UTF-8; searched the pinned dist (a10085d0)"
    test "an MCP-Protocol-Version header that is not UTF-8: 400 / -32020" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/list",
        "params" => %{"_meta" => @full}
      }

      headers = [{"mcp-protocol-version", <<255>>}, {"mcp-method", "tools/list"}]

      assert post(message, headers) ==
               mismatch(7, ~s(MCP-Protocol-Version � != "#{@version}"))
    end
  end

  describe "correction round 1: a printable string with an interpolation marker (F2)" do
    @tag oc: :none
    @tag oc_reason:
           "HttpServerHeaderMismatch400 drives only the MCP-Protocol-Version comparison; no OC check sends a mismatched Mcp-Method; searched the pinned dist (a10085d0)"
    test "a body method containing \#{ renders as JSON, which does not escape it" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "a\#{b}",
        "params" => %{"_meta" => @full}
      }

      headers = [{"mcp-protocol-version", @version}, {"mcp-method", "tools/list"}]

      assert post(message, headers) == mismatch(7, ~S(Mcp-Method tools/list != "a#{b}"))
    end
  end
end
