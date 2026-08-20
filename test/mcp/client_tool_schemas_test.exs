defmodule MCP.ClientToolSchemasTest do
  @moduledoc """
  MES-18 / CG7 client half — the tool-schema cache, SEP-2243 tool exclusion,
  and the `-32020` recovery.

  ## Evidence posture (A7)

  **All POSITIVE CONTROLS.** None of this existed at `2829769`: the client had
  no schema cache, excluded nothing, and treated `-32020` as an ordinary error.
  Nothing here is a caught regression.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias MCP.Client
  alias MCP.Test.MockTransport

  defp wait_for_sent(transport, count, timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_sent(transport, count, deadline)
  end

  defp do_wait_for_sent(transport, count, deadline) do
    messages = MockTransport.sent_messages(transport)

    cond do
      length(messages) >= count ->
        messages

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Timed out waiting for #{count} messages, got #{length(messages)}")

      true ->
        Process.sleep(5)
        do_wait_for_sent(transport, count, deadline)
    end
  end

  defp start_client(opts \\ []) do
    {:ok, client} = Client.start_link(Keyword.merge([transport: {MockTransport, []}], opts))
    {client, Client.transport(client)}
  end

  defp annotated(name, header) do
    %{
      "name" => name,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"region" => %{"type" => "string", "x-mcp-header" => header}}
      }
    }
  end

  defp invalid_tool(name) do
    %{
      "name" => name,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"a" => %{"type" => "object", "x-mcp-header" => "Bad"}}
      }
    }
  end

  # Drives one list_tools round trip, injecting `result`.
  defp list_tools(client, transport, result, opts \\ []) do
    index = length(MockTransport.sent_messages(transport))
    task = Task.async(fn -> Client.list_tools(client, opts) end)
    sent = wait_for_sent(transport, index + 1)
    request = Enum.at(sent, index)

    MockTransport.inject(transport, %{
      "jsonrpc" => "2.0",
      "id" => request["id"],
      "result" => result
    })

    Task.await(task)
  end

  describe "W6 — SEP-2243 tool exclusion" do
    test "an invalid tool is dropped and the valid ones are kept" do
      {client, transport} = start_client()

      log =
        capture_log(fn ->
          assert {:ok, %{"tools" => tools}} =
                   list_tools(client, transport, %{
                     "tools" => [
                       annotated("good", "Region"),
                       invalid_tool("bad"),
                       %{"name" => "plain", "inputSchema" => %{"type" => "object"}}
                     ]
                   })

          assert Enum.map(tools, & &1["name"]) == ["good", "plain"]
        end)

      # The spec's SHOULD: log the tool name and the reason. Assert the tool
      # name INSIDE the exclusion phrase, not the bare name: `capture_log/1`
      # sees the GLOBAL logger and this file is `async: true`, so `=~ "bad"` is
      # three characters matched anywhere in the whole suite's concurrent
      # output. Measured, so the claim is not hypothetical: make the warning
      # name a different tool (`"bad_other"`) and `=~ "bad"` stays GREEN while
      # this assertion goes red.
      assert log =~ ~s(EXCLUDING tool "bad" from tools/list)
      assert log =~ "only string, integer and boolean are permitted"
    end

    test "excluded_tools/1 keeps the answer queryable, not just logged" do
      {client, transport} = start_client()

      capture_log(fn ->
        list_tools(client, transport, %{
          "tools" => [annotated("good", "Region"), invalid_tool("bad")]
        })
      end)

      assert [{"bad", reason}] = Client.excluded_tools(client)
      assert reason =~ "only string, integer and boolean are permitted"
    end

    test "an excluded tool leaves no annotations behind, so calling it mirrors nothing" do
      {client, transport} = start_client()

      capture_log(fn ->
        list_tools(client, transport, %{"tools" => [invalid_tool("bad")]})
      end)

      capture_log(fn ->
        task = Task.async(fn -> Client.call_tool(client, "bad", %{"region" => "us-west1"}) end)
        [_list, call] = wait_for_sent(transport, 2)

        MockTransport.inject(transport, %{
          "jsonrpc" => "2.0",
          "id" => call["id"],
          "result" => %{"resultType" => "complete"}
        })

        assert {:ok, _} = Task.await(task)
      end)

      assert [] = Enum.at(MockTransport.sent_opts(transport), 1) |> Keyword.get(:headers, [])
    end

    test "a tools/list carrying no tools key is handled rather than crashed on" do
      {client, transport} = start_client()
      assert {:ok, %{"tools" => []}} = list_tools(client, transport, %{"nextCursor" => nil})
    end
  end

  describe "W5 — the cache's reset/merge rule (the pagination trap)" do
    test "a cursor-BEARING page MERGES, so paging does not discard earlier pages" do
      {client, transport} = start_client()

      {:ok, _} =
        list_tools(client, transport, %{
          "tools" => [annotated("page1_tool", "One")],
          "nextCursor" => "c1"
        })

      {:ok, _} =
        list_tools(client, transport, %{"tools" => [annotated("page2_tool", "Two")]},
          cursor: "c1"
        )

      # Both pages' schemas must still be there: `list_all_tools/2` walks
      # nextCursor, so a wholesale replace would leave only the last page and
      # every earlier tool would silently stop mirroring.
      assert headers_for_call(client, transport, "page1_tool") == [{"mcp-param-one", "us-west1"}]
      assert headers_for_call(client, transport, "page2_tool") == [{"mcp-param-two", "us-west1"}]
    end

    test "a cursor-LESS listing RESETS, so a removed tool does not linger" do
      {client, transport} = start_client()

      {:ok, _} = list_tools(client, transport, %{"tools" => [annotated("gone", "Gone")]})
      {:ok, _} = list_tools(client, transport, %{"tools" => [annotated("kept", "Kept")]})

      assert headers_for_call(client, transport, "kept") == [{"mcp-param-kept", "us-west1"}]

      # "gone" is no longer known, so the miss path applies rather than a stale
      # header from a listing the server has moved on from.
      log = capture_log(fn -> assert headers_for_call(client, transport, "gone") == [] end)
      # Names the tool as well as the phrase: `capture_log/1` sees the global
      # logger, so the phrase alone could be another async test's warning.
      assert log =~ ~s(calling tool "gone" with no cached inputSchema)
    end

    test "excluded_tools follows the same reset/merge rule" do
      {client, transport} = start_client()

      capture_log(fn ->
        list_tools(client, transport, %{"tools" => [invalid_tool("bad1")], "nextCursor" => "c1"})
        list_tools(client, transport, %{"tools" => [invalid_tool("bad2")]}, cursor: "c1")
      end)

      assert [{"bad1", _}, {"bad2", _}] = Client.excluded_tools(client)

      capture_log(fn ->
        list_tools(client, transport, %{"tools" => [invalid_tool("bad3")]})
      end)

      assert [{"bad3", _}] = Client.excluded_tools(client)
    end
  end

  describe "C-2 — the cache-miss and staleness policy" do
    test "a miss warns ONCE per tool name, not once per call" do
      {client, transport} = start_client()

      # A name unique to this test. `capture_log/1` captures the GLOBAL logger,
      # so in an async suite it also sees the identical warning emitted by
      # other tests for THEIR tools — counting the generic phrase measured the
      # whole suite's concurrency rather than this client's behaviour, and was
      # seed-dependently red. Counting a name only this test uses measures the
      # property the test is about.
      name = "never_listed_#{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          for _ <- 1..3, do: complete_call(client, transport, name)
        end)

      occurrences = log |> String.split(name) |> length() |> Kernel.-(1)

      assert occurrences == 1
    end

    test "M-2: the warn-once record shares the cache's GENERATION — a reset re-arms it" do
      {client, transport} = start_client()

      # A name only this test uses: `capture_log/1` sees the global logger.
      name = "vanishing_#{System.unique_integer([:positive])}"

      # 1. Cold call → miss → warns. (Control: this half worked at 29297be.)
      log1 = capture_log(fn -> complete_call(client, transport, name) end)
      assert log1 =~ ~s(calling tool #{inspect(name)} with no cached inputSchema)

      # 2. The tool turns up in a listing, so the cache now knows it.
      {:ok, _} = list_tools(client, transport, %{"tools" => [annotated(name, "Region")]})
      assert headers_for_call(client, transport, name) == [{"mcp-param-region", "us-west1"}]

      # 3. The server then drops it from a cursor-less listing, which RESETS
      #    the cache. An ordinary event — a server withdrawing a tool.
      {:ok, _} = list_tools(client, transport, %{"tools" => []})

      # 4. The same call is a miss again, and must be announced again. At
      #    29297be `mirror_misses_warned` outlived the cache it describes, so
      #    this was SILENT: the operator who missed step 1 never got another
      #    line, for a cache generation that had never warned at all.
      log2 = capture_log(fn -> complete_call(client, transport, name) end)
      assert log2 =~ ~s(calling tool #{inspect(name)} with no cached inputSchema)
    end

    test "M-2: a cursor-BEARING page does NOT re-arm it — warn-once still holds per generation" do
      {client, transport} = start_client()
      name = "unlisted_#{System.unique_integer([:positive])}"

      log1 = capture_log(fn -> complete_call(client, transport, name) end)
      assert log1 =~ ~s(calling tool #{inspect(name)} with no cached inputSchema)

      # A page MERGES into the current cache rather than replacing it, so it
      # starts no new generation and must leave the record alone — otherwise
      # `list_all_tools/2` would re-warn once per page walked.
      {:ok, _} =
        list_tools(client, transport, %{"tools" => [annotated("other", "Other")]}, cursor: "c1")

      log2 = capture_log(fn -> complete_call(client, transport, name) end)
      refute log2 =~ ~s(calling tool #{inspect(name)} with no cached inputSchema)
    end

    test "a -32020 triggers a tools/list refresh and ONE retry, which then mirrors" do
      {client, transport} = start_client()

      task = Task.async(fn -> Client.call_tool(client, "t", %{"region" => "us-west1"}) end)

      log =
        capture_log(fn ->
          [call] = wait_for_sent(transport, 1)
          assert call["method"] == "tools/call"

          MockTransport.inject(transport, %{
            "jsonrpc" => "2.0",
            "id" => call["id"],
            "error" => %{"code" => -32_020, "message" => "Header mismatch"}
          })

          # The client's recovery: a cursor-less tools/list.
          [_call, refresh] = wait_for_sent(transport, 2)
          assert refresh["method"] == "tools/list"
          refute Map.has_key?(refresh["params"], "cursor")

          MockTransport.inject(transport, %{
            "jsonrpc" => "2.0",
            "id" => refresh["id"],
            "result" => %{"tools" => [annotated("t", "Region")]}
          })

          # ...then the ORIGINAL call again, now carrying the mirrored header.
          [_call, _refresh, retry] = wait_for_sent(transport, 3)
          assert retry["method"] == "tools/call"
          assert retry["params"]["name"] == "t"

          assert Enum.at(MockTransport.sent_opts(transport), 2)[:headers] ==
                   [{"mcp-param-region", "us-west1"}]

          MockTransport.inject(transport, %{
            "jsonrpc" => "2.0",
            "id" => retry["id"],
            "result" => %{"resultType" => "complete", "content" => []}
          })

          assert {:ok, %{"resultType" => "complete"}} = Task.await(task)
        end)

      assert log =~ "HeaderMismatch"
    end

    test "a SECOND -32020 is surfaced — the recovery is one-shot, not a loop" do
      {client, transport} = start_client()
      task = Task.async(fn -> Client.call_tool(client, "t", %{"region" => "x"}) end)

      capture_log(fn ->
        [call] = wait_for_sent(transport, 1)
        reject_with_header_mismatch(transport, call)

        [_call, refresh] = wait_for_sent(transport, 2)

        MockTransport.inject(transport, %{
          "jsonrpc" => "2.0",
          "id" => refresh["id"],
          "result" => %{"tools" => [annotated("t", "Region")]}
        })

        [_call, _refresh, retry] = wait_for_sent(transport, 3)
        reject_with_header_mismatch(transport, retry)

        assert {:error, %MCP.Protocol.Error{code: -32_020}} = Task.await(task)
        # Exactly three messages: call, refresh, retry. No second refresh.
        assert length(MockTransport.sent_messages(transport)) == 3
      end)
    end

    test "a FAILED refresh surfaces the ORIGINAL -32020, not the refresh's error" do
      {client, transport} = start_client()
      task = Task.async(fn -> Client.call_tool(client, "t", %{}) end)

      capture_log(fn ->
        [call] = wait_for_sent(transport, 1)
        reject_with_header_mismatch(transport, call)

        [_call, refresh] = wait_for_sent(transport, 2)

        MockTransport.inject(transport, %{
          "jsonrpc" => "2.0",
          "id" => refresh["id"],
          "error" => %{"code" => -32_601, "message" => "Method not found"}
        })

        # The caller asked for a tools/call. "tools/list also failed" is a
        # different question's answer.
        assert {:error, %MCP.Protocol.Error{code: -32_020}} = Task.await(task)
      end)
    end

    test "a -32020 on a NON-tools/call request is not retried" do
      {client, transport} = start_client()
      task = Task.async(fn -> Client.list_tools(client) end)
      [request] = wait_for_sent(transport, 1)
      reject_with_header_mismatch(transport, request)

      assert {:error, %MCP.Protocol.Error{code: -32_020}} = Task.await(task)
      assert length(MockTransport.sent_messages(transport)) == 1
    end
  end

  describe "the transport seam" do
    test "a tools/call for a known tool carries :headers; other methods carry none" do
      {client, transport} = start_client()
      {:ok, _} = list_tools(client, transport, %{"tools" => [annotated("t", "Region")]})

      complete_call(client, transport, "t", %{"region" => "us-west1"})

      assert Enum.at(MockTransport.sent_opts(transport), 0) == []

      assert Enum.at(MockTransport.sent_opts(transport), 1)[:headers] ==
               [{"mcp-param-region", "us-west1"}]
    end
  end

  describe "M-1 — a malformed tools/list result fails the REQUEST, not the client" do
    # `protocol.ex:63` classifies any message carrying `id` + the `result` KEY
    # as a Response, so `"result": null` and `"result": "oops"` both decode
    # fine and reach the tools/list clause. At 29297be that clause did an
    # unguarded `Map.get(result, "tools")` and raised BadMapError inside the
    # GenServer — one bad field from a remote peer took the client, every other
    # pending request and the linked transport down.
    test "a null result is reported to the caller and the client survives" do
      {client, transport} = start_client()

      log =
        capture_log(fn ->
          assert {:error, {:malformed_result, nil}} = list_tools(client, transport, nil)
        end)

      assert log =~ "tools/list answered with a non-object result"
      assert Process.alive?(client)

      # Still usable: the failure is scoped to the one request.
      assert {:ok, %{"tools" => [%{"name" => "good"}]}} =
               list_tools(client, transport, %{"tools" => [annotated("good", "Region")]})
    end

    test "a string result likewise, and it leaves the tool caches untouched" do
      {client, transport} = start_client()

      capture_log(fn ->
        {:ok, _} = list_tools(client, transport, %{"tools" => [annotated("t", "Region")]})

        {:ok, _} =
          list_tools(client, transport, %{"tools" => [invalid_tool("bad")], "nextCursor" => "c1"},
            cursor: "c1"
          )

        assert {:error, {:malformed_result, "oops"}} = list_tools(client, transport, "oops")
      end)

      # A garbage listing is not a listing: it must not be read as "the server
      # now has no tools" and wipe what the last good one established.
      assert headers_for_call(client, transport, "t") == [{"mcp-param-region", "us-west1"}]
      assert [{"bad", _}] = Client.excluded_tools(client)
    end
  end

  describe "M-5 — a malformed REFRESH result fails the call, not the client" do
    # The -32020 recovery issues a `tools/list` of its own, and at `145efb7`
    # that clause did the same unguarded `Map.get(result, "tools")` M-1 fixed
    # one clause up — on a path that does not exist on `main` at all. Measured
    # before the fix: the caller got an EXIT, not `{:error, _}`, and
    # `Process.alive?(client)` was false.
    test "a null refresh result returns the ORIGINAL -32020 alongside the malformed term" do
      {client, transport} = start_client()

      # A good listing first, so the malformed refresh can be seen NOT to wipe it.
      {:ok, _} = list_tools(client, transport, %{"tools" => [annotated("t", "Region")]})

      task = Task.async(fn -> Client.call_tool(client, "t", %{"region" => "us-west1"}) end)

      log =
        capture_log(fn ->
          [_list, call] = wait_for_sent(transport, 2)
          reject_with_header_mismatch(transport, call)

          [_list, _call, refresh] = wait_for_sent(transport, 3)
          assert refresh["method"] == "tools/list"

          MockTransport.inject(transport, %{
            "jsonrpc" => "2.0",
            "id" => refresh["id"],
            "result" => nil
          })

          # BOTH facts reach the caller: the refresh was unusable (so this is
          # not the bare -32020 that "the refresh found no tools" ends in), and
          # the true answer to the question they actually asked.
          assert {:error, {:malformed_refresh_result, nil, %MCP.Protocol.Error{code: -32_020}}} =
                   Task.await(task)
        end)

      assert log =~ "refresh after -32020 answered with a non-object result"
      assert Process.alive?(client)

      # The recovery is abandoned, not looped: list, call, refresh and no retry.
      assert length(MockTransport.sent_messages(transport)) == 3

      # A cursor-less refresh RESETS the cache, so absorbing this one would have
      # discarded a good annotation on the strength of an unusable response.
      assert headers_for_call(client, transport, "t") == [{"mcp-param-region", "us-west1"}]
    end
  end

  # --- helpers ---

  defp reject_with_header_mismatch(transport, request) do
    MockTransport.inject(transport, %{
      "jsonrpc" => "2.0",
      "id" => request["id"],
      "error" => %{"code" => -32_020, "message" => "Header mismatch"}
    })
  end

  # Runs a tools/call to completion and returns the :headers opt it carried.
  defp headers_for_call(client, transport, name) do
    index = length(MockTransport.sent_messages(transport))
    complete_call(client, transport, name, %{"region" => "us-west1"})
    Enum.at(MockTransport.sent_opts(transport), index) |> Keyword.get(:headers, [])
  end

  defp complete_call(client, transport, name, arguments \\ %{}) do
    index = length(MockTransport.sent_messages(transport))
    task = Task.async(fn -> Client.call_tool(client, name, arguments) end)
    sent = wait_for_sent(transport, index + 1)
    call = Enum.at(sent, index)

    MockTransport.inject(transport, %{
      "jsonrpc" => "2.0",
      "id" => call["id"],
      "result" => %{"resultType" => "complete", "content" => []}
    })

    Task.await(task)
  end
end
