defmodule MCP.Transport.SSELineEndingsTest do
  @moduledoc """
  MES-156: the SSE parser accepts every line ending the SSE specification
  permits — CRLF, CR or LF, mixed within one stream — including a CR and LF
  split across two chunks, and drops a byte-order mark at stream start. Before
  MES-156 it split events only on LF LF, so a conforming server that framed with
  CRLF (the transport spec's own keep-alive example is `:\\r\\n`) delivered
  nothing to our client.

  No official conformance check corresponds: no scenario server frames SSE with
  CR or CRLF (the pinned harness `dist/index.js` holds 0 CR bytes), and the
  client leg's row multiset is identical with and without this fix (MES-156 mx1,
  mx2). Hence every test here is `oc: :none`.
  """
  use ExUnit.Case, async: true

  alias MCP.Transport.SSE
  alias MCP.Transport.StreamableHTTP.Client

  defmodule FramingPlug do
    @moduledoc false
    import Plug.Conn

    @json Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{"ok" => true}})

    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> send_resp(200, body_for(conn.request_path))
    end

    defp body_for("/lf"), do: "event: message\ndata: " <> @json <> "\n\n"
    defp body_for("/crlf"), do: ":\r\nevent: message\r\ndata: " <> @json <> "\r\n\r\n"
    defp body_for("/cr"), do: "event: message\rdata: " <> @json <> "\r\r"
  end

  defp feed_all(chunks) do
    {events, _parser} =
      Enum.reduce(chunks, {[], SSE.new_parser()}, fn chunk, {acc, parser} ->
        {events, parser} = SSE.feed(parser, chunk)
        {acc ++ events, parser}
      end)

    events
  end

  defp bytewise(text), do: for(<<byte <- text>>, do: <<byte>>)

  describe "feed/2 line endings" do
    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a CRLF-framed stream yields each event" do
      assert feed_all(["event: m\r\ndata: a\r\n\r\ndata: b\r\n\r\n"]) ==
               [%{event: "m", data: "a"}, %{data: "b"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a CR-framed stream yields each event" do
      assert feed_all(["event: m\rdata: a\r\rdata: b\r\r"]) ==
               [%{event: "m", data: "a"}, %{data: "b"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a stream mixing LF, CRLF and CR yields each event" do
      assert feed_all(["event: m\ndata: a\r\n\r\ndata: b\rdata: c\n\r"]) ==
               [%{event: "m", data: "a"}, %{data: "b\nc"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a CRLF-framed stream fed byte by byte yields each event" do
      assert feed_all(bytewise("data: a\r\n\r\ndata: b\r\n\r\n")) == [%{data: "a"}, %{data: "b"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a CR-framed stream fed byte by byte yields each event" do
      assert feed_all(bytewise("data: a\r\rdata: b\r\r")) == [%{data: "a"}, %{data: "b"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a CR ending one chunk and an LF opening the next are one line ending" do
      assert feed_all(["data: a\r", "\ndata: b\r", "\n\r\n"]) == [%{data: "a\nb"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "an empty chunk between a CR and its LF does not split the pair" do
      assert feed_all(["data: a\r", "", "\ndata: b\r\n\r\n"]) == [%{data: "a\nb"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "CR CR LF is two line endings, so it ends an event" do
      assert feed_all(["data: a\r\r\ndata: b\r\n\r\n"]) == [%{data: "a"}, %{data: "b"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "LF then CR is two line endings, so it ends an event" do
      assert feed_all(["data: a\n\r"]) == [%{data: "a"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "our own CRLF keep-alive comment followed by an event yields the event" do
      assert feed_all([SSE.comment(), SSE.encode_event(%{data: "a"})]) == [%{data: "a"}]
    end
  end

  describe "feed/2 byte-order mark" do
    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a BOM at stream start is dropped" do
      assert feed_all(["﻿data: a\n\n"]) == [%{data: "a"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a BOM split across chunks is dropped" do
      assert feed_all([<<0xEF>>, <<0xBB, 0xBF>> <> "data: a\n\n"]) == [%{data: "a"}]
      assert feed_all([<<0xEF, 0xBB>>, <<0xBF>>, "data: a\n\n"]) == [%{data: "a"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a BOM after an empty first chunk is dropped" do
      assert feed_all(["", "﻿data: a\n\n"]) == [%{data: "a"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "only the BOM at stream start is dropped" do
      # The second event's field name is "﻿data", an unknown field.
      assert feed_all(["﻿data: a\n\n﻿data: b\n\n"]) == [%{data: "a"}]
    end
  end

  describe "field grammar" do
    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "the field name runs to the first colon, even with no space after it" do
      assert feed_all([~s(data:{"a": 1}\n\n)]) == [%{data: ~s({"a": 1})}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "exactly one space after the colon is dropped" do
      assert feed_all(["data:  a\n\n"]) == [%{data: " a"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a trailing space in a value is kept" do
      assert feed_all(["data: a \n\n"]) == [%{data: "a "}]
    end
  end

  describe "decode_event/1 and the legacy state" do
    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "decode_event/1 splits lines on CRLF, CR and LF" do
      assert SSE.decode_event("event: m\r\nid: 1\rdata: a\ndata: b") ==
               {:ok, %{event: "m", id: "1", data: "a\nb"}}
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
    test "a bare binary state is still accepted as the unparsed remainder" do
      assert {[%{data: "a"}], parser} = SSE.feed("", "data: a\r\n\r\n")
      assert {[%{data: "b"}], _parser} = SSE.feed(parser, "data: b\n\n")
      assert {[%{data: "a"}], _parser} = SSE.feed("data: a\r\n", "\r\n")
    end
  end

  describe "StreamableHTTP client over a text/event-stream response" do
    setup do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(socket)
      :gen_tcp.close(socket)

      {:ok, server} =
        Bandit.start_link(plug: FramingPlug, port: port, ip: {127, 0, 0, 1}, startup_log: false)

      on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :normal) end)
      %{port: port}
    end

    for framing <- ["lf", "crlf", "cr"] do
      @tag oc: :none
      @tag oc_reason:
             "no OC scenario frames SSE with CR or CRLF: pinned dist 0 CR bytes; client leg identical main vs fix (MES-156 mx1/mx2)"
      test "the client delivers a #{framing}-framed response to its owner", %{port: port} do
        {:ok, pid} =
          Client.start_link(owner: self(), url: "http://127.0.0.1:#{port}/#{unquote(framing)}")

        assert :ok = Client.send_message(pid, %{"jsonrpc" => "2.0", "id" => 1})
        assert_receive {:mcp_message, %{"id" => 1, "result" => %{"ok" => true}}}, 2_000
      end
    end
  end
end
