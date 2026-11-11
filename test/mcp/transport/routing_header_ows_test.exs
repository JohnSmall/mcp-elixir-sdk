defmodule MCP.Transport.StreamableHTTP.RoutingHeaderOwsTest do
  @moduledoc """
  MES-232 — the Streamable HTTP Plug compares a routing-header value
  (`Mcp-Name`, `Mcp-Method`, `MCP-Protocol-Version`) without its leading and
  trailing OWS (SP / HTAB, RFC 9110 §5.5 and §5.6.3), whatever the adapter
  passes through. SEP-2243's `sep-2243-server-accepts-whitespace-header-value`
  check says a server MUST accept such a value.

  Every request here is built with `Plug.Test` and the padded value put
  straight into `req_headers`, so no adapter runs. That is the point: under
  bandit 1.14.1 HTTP/1 the adapter trims trailing OWS itself, and the official
  check went green on main through that alone while the plug still compared the
  raw value.

  ## Evidence posture (A7)

  The `accept` units are regressions: they are red at `ae5d6f1` (HTTP 400,
  -32020 `Header mismatch`) and green at the fix. The `reject` units are
  controls that pin the edges of the fix: a value that still differs after
  trimming, an interior-whitespace difference, padding that is not OWS, and a
  Base64 sentinel whose decoded payload is padded (trimming happens before the
  decode and never after).
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MCP.Test.StatelessHandler
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @meta %{
    "io.modelcontextprotocol/protocolVersion" => @version,
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  defp post(message, headers) do
    conn =
      :post
      |> conn("http://localhost/", Jason.encode!(message))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("origin", "http://localhost")

    conn =
      headers
      |> Enum.reduce(conn, fn {k, v}, c -> put_req_header(c, k, v) end)
      |> MCPPlug.call(MCPPlug.init(server_mod: StatelessHandler, enable_json_response: true))

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp call(name),
    do: %{
      "jsonrpc" => "2.0",
      "id" => 7,
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => %{}, "_meta" => @meta}
    }

  defp list,
    do: %{
      "jsonrpc" => "2.0",
      "id" => 7,
      "method" => "tools/list",
      "params" => %{"_meta" => @meta}
    }

  defp call_headers(name),
    do: [{"mcp-protocol-version", @version}, {"mcp-method", "tools/call"}, {"mcp-name", name}]

  defp sentinel(text), do: "=?base64?" <> Base.encode64(text) <> "?="

  defp mismatch(data),
    do:
      {400,
       %{
         "jsonrpc" => "2.0",
         "id" => 7,
         "error" => %{"code" => -32_020, "message" => "Header mismatch", "data" => data}
       }}

  # Past the header check: HTTP 200 and no -32020. A name the handler does not
  # know is answered -32602 `unknown tool` at HTTP 200, which is still past it.
  defp past_headers?({200, %{"error" => %{"code" => -32_020}}}), do: false
  defp past_headers?({200, %{"jsonrpc" => "2.0", "id" => 7}}), do: true
  defp past_headers?(_), do: false

  describe "accept: surrounding OWS is not part of the value" do
    @tag oc:
           "oc:server/http-header-validation/sep-2243-server-accepts-whitespace-header-value/ServerAcceptsWhitespaceHeaderValue"
    test "Mcp-Name padded with SP on both sides, as the official check sends it" do
      assert {200, %{"result" => %{}}} = post(call("whoami"), call_headers("  whoami  "))
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "Mcp-Name padded with HTAB, and with SP and HTAB mixed" do
      assert {200, %{"result" => %{}}} = post(call("whoami"), call_headers("\twhoami\t"))
      assert {200, %{"result" => %{}}} = post(call("whoami"), call_headers(" \t whoami\t "))
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "Mcp-Method padded" do
      headers = [{"mcp-protocol-version", @version}, {"mcp-method", " \ttools/list "}]
      assert {200, %{"result" => %{"tools" => [_ | _]}}} = post(list(), headers)
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "MCP-Protocol-Version padded, compared with the body's _meta version" do
      headers = [{"mcp-protocol-version", "\t" <> @version <> " "}, {"mcp-method", "tools/list"}]
      assert {200, %{"result" => %{"tools" => [_ | _]}}} = post(list(), headers)
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "a padded Base64 sentinel is trimmed, then decoded" do
      name = "café"
      assert past_headers?(post(call(name), call_headers("  " <> sentinel(name) <> "\t")))
    end
  end

  describe "reject: the trim does not widen what matches" do
    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "a padded value that differs after trimming is still -32020" do
      assert post(call("whoami"), call_headers(" other ")) ==
               mismatch(~s(Mcp-Name other != "whoami"))

      headers = [{"mcp-protocol-version", @version}, {"mcp-method", " prompts/list "}]

      assert post(list(), headers) ==
               mismatch(~s(Mcp-Method prompts/list != "tools/list"))
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "interior whitespace is significant" do
      assert post(call("whoami"), call_headers("who ami")) ==
               mismatch(~s(Mcp-Name who ami != "whoami"))

      assert post(call("my tool"), call_headers("my  tool")) ==
               mismatch(~s(Mcp-Name my  tool != "my tool"))
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "padding that is not OWS (VT, NBSP) is part of the value" do
      assert post(call("whoami"), call_headers("\vwhoami")) ==
               mismatch(~s(Mcp-Name \vwhoami != "whoami"))

      assert post(call("whoami"), call_headers("whoami ")) ==
               mismatch(~s(Mcp-Name whoami  != "whoami"))
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "a whitespace-only Mcp-Name is an empty value, not a match" do
      assert post(call("whoami"), call_headers(" \t ")) ==
               mismatch(~s(Mcp-Name  != "whoami"))
    end

    @tag oc: :none
    @tag oc_reason:
           "no in-scope OC check sends this header value; ServerAcceptsWhitespaceHeaderValue pads Mcp-Name with SP only; searched in-scope-2026-07-28.json and the pinned dist (a10085d0)"
    test "a Base64 sentinel whose decoded payload is padded is not trimmed after decoding" do
      assert post(call("whoami"), call_headers(sentinel(" whoami "))) ==
               mismatch(~s(Mcp-Name  whoami  != "whoami"))
    end
  end
end
