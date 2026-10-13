defmodule MCP.Transport.SSEDispatchTest do
  # WHATWG HTML §9.2.6 "Interpreting an event stream": how parsed fields become
  # dispatched events (MES-170, G10-G14).
  use ExUnit.Case, async: true

  alias MCP.Transport.SSE

  defp feed(bytes) do
    {events, _parser} = SSE.feed(SSE.new_parser(), bytes)
    events
  end

  describe "G10: a field line with no colon is a field with an empty value" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "a bare data line dispatches an empty data value" do
      assert feed("data\n\n") == [%{data: ""}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "a bare data line between data lines adds an empty line" do
      assert feed("data: a\ndata\ndata: b\n\n") == [%{data: "a\n\nb"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "decode_event/1 reads a bare data line as an empty value" do
      assert SSE.decode_event("data") == {:ok, %{data: ""}}
    end
  end

  describe "G11: a block with no data field is not dispatched" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an id-only block dispatches nothing" do
      assert feed("id: 7\n\n") == []
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an event-only block dispatches nothing" do
      assert feed("event: ping\n\n") == []
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "a retry-only block dispatches nothing" do
      assert feed("retry: 100\n\n") == []
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an empty data: line still dispatches" do
      assert feed("data:\n\n") == [%{data: ""}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an empty data: line before a data line with content still dispatches" do
      assert feed("data:\ndata: x\n\n") == [%{data: "\nx"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "the pinned harness priming event still dispatches" do
      assert feed("id: event-1\nretry: 500\ndata: \n\n") ==
               [%{id: "event-1", retry: 500, data: ""}]
    end
  end

  describe "G12: the last event ID persists across events" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "a later event without an id carries the last id" do
      assert feed("id: 1\ndata: a\n\ndata: b\n\n") == [
               %{data: "a", id: "1"},
               %{data: "b", id: "1"}
             ]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "the last id persists across feed/2 calls" do
      {first, parser} = SSE.feed(SSE.new_parser(), "id: 1\ndata: a\n\n")
      assert first == [%{data: "a", id: "1"}]
      {second, _parser} = SSE.feed(parser, "data: b\n\n")
      assert second == [%{data: "b", id: "1"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an id-only block sets the id of the next event" do
      assert feed("id: 9\n\ndata: b\n\n") == [%{data: "b", id: "9"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "a bare id line resets the last id" do
      assert feed("id: 1\ndata: a\n\nid\ndata: b\n\n") == [%{data: "a", id: "1"}, %{data: "b"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an empty id: line resets the last id" do
      assert feed("id: 1\ndata: a\n\nid:\ndata: b\n\n") == [%{data: "a", id: "1"}, %{data: "b"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an empty last event ID omits :id" do
      assert feed("id:\ndata: x\n\n") == [%{data: "x"}]
    end
  end

  describe "G13: an id containing NUL is ignored" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an id with NUL is not set" do
      assert feed("id: a\0b\ndata: x\n\n") == [%{data: "x"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an id with NUL leaves the previous id in force" do
      assert feed("id: 1\ndata: a\n\nid: 2\0\ndata: b\n\n") ==
               [%{data: "a", id: "1"}, %{data: "b", id: "1"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an id without NUL is kept" do
      assert feed("id: abc\ndata: x\n\n") == [%{data: "x", id: "abc"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "decode_event/1 ignores an id with NUL" do
      assert SSE.decode_event("id: a\0b\ndata: x") == {:ok, %{data: "x"}}
    end
  end

  describe "G14: retry takes ASCII digits only" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "a retry with a plus sign is ignored" do
      assert feed("retry: +5\ndata: x\n\n") == [%{data: "x"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "a retry with a minus sign is ignored" do
      assert feed("retry: -5\ndata: x\n\n") == [%{data: "x"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "a retry of ASCII digits is kept" do
      assert feed("retry: 5\ndata: x\n\n") == [%{data: "x", retry: 5}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an empty retry is ignored" do
      assert feed("retry:\ndata: x\n\n") == [%{data: "x"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "decode_event/1 ignores a signed retry" do
      assert SSE.decode_event("retry: +5\ndata: x") == {:ok, %{data: "x"}}
    end
  end

  describe "decode_event/1 applies field rules only, not dispatch rules" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an id-only block still decodes" do
      assert SSE.decode_event("id: 7") == {:ok, %{id: "7"}}
    end
  end

  describe "end of stream: an unterminated event is not dispatched" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an event with no line ending is held, then dispatched by a blank line" do
      {events, parser} = SSE.feed(SSE.new_parser(), "data: x")
      assert events == []
      {events, _parser} = SSE.feed(parser, "\n\n")
      assert events == [%{data: "x"}]
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends this byte shape: the pinned dist (a10085d0) writes only well-formed SSE events, and sse-retry is not in the 2026-07-28 client census"
    test "an event with one line ending and no blank line is not dispatched" do
      assert feed("data: x\n") == []
    end
  end
end
