defmodule MCP.Transport.SubscriptionsStreamTest do
  @moduledoc """
  MES-15 — `subscriptions/listen` over real HTTP (Bandit), driven by a raw
  `:gen_tcp` client.

  The client is raw on purpose. `Req` returns a *complete* body, so it cannot
  observe a second message on a held-open stream at all, and it gives no control
  over FIN timing — both of which are exactly what these tests are about. The
  SDK's own `MCP.Client` has the same limitation (it parses a whole SSE body
  from a blocking call); consuming a listen stream client-side is MES-18.

  Covers T-8 (keep-alive frames, both directions), T-9 (cancellation and
  teardown), T-10 (the multi-instance boundary, with its positive control),
  T-12 (graceful close vs abrupt drop) and — from correction round 1 — the two
  listen exits that ran no teardown at all (review F1/F2).

  ## A7/A7b honesty

  These are **positive controls**, not caught regressions: nothing here existed
  before this ticket. Where a claim could pass vacuously — the multi-instance
  boundary above all — the test carries an explicit positive control so that
  "did not arrive" cannot be satisfied by a stream that never worked.

  The two round-1 tests (`describe "every exit from a listen runs teardown"`)
  are new seams too, so A7b applies to them as well: **the failing direction was
  demonstrated against the unfixed tree** at `145f4cb` — the refusal test failed
  on `handle_listen_closed/3` never being called, and the raise test failed on
  the sink still answering `:ok` after the stream process had died. That is a
  positive control shown capable of failing, not a caught regression.

  **The two round-3 tests are the exception, and are A7 in its ordinary form:**
  `describe "the obligation is armed off the decoded message"` covers review
  **R4**, a defect that exists at `0f12936` and is reachable from the wire with
  no buggy handler required. Both were **demonstrated failing against `0f12936`**
  — a caught regression, not a control. They are kept in their own `describe`
  so they cannot be read as part of the positive-control set above.
  """
  use ExUnit.Case, async: false

  alias MCP.Test.SubscribingHandler
  alias MCP.Transport.SSE

  @version "2026-07-28"
  @sub_id_key "io.modelcontextprotocol/subscriptionId"

  # --- harness ---

  setup do
    owner = self()
    %{a: start_instance(owner), b: start_instance(owner)}
  end

  defp start_instance(owner, extra \\ []) do
    port = free_port()

    opts =
      Keyword.merge(
        [
          server_mod: SubscribingHandler,
          handler_opts: [owner: owner, identity: "alice"],
          keepalive_interval: 150,
          max_stream_lifetime: :timer.seconds(30)
        ],
        extra
      )

    {:ok, bandit} =
      Bandit.start_link(
        plug: {MCP.Transport.StreamableHTTP.Plug, opts},
        port: port,
        ip: {127, 0, 0, 1}
      )

    on_exit(fn -> Process.exit(bandit, :normal) end)
    port
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # Opens a listen stream over a raw socket and returns it once the
  # acknowledgment has arrived, so every test starts from a stream that is
  # provably live.
  defp open_listen(port, notifications, opts \\ []) do
    id = Keyword.get(opts, :id, "listen-1")

    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => "subscriptions/listen",
        "params" => %{
          "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
          "notifications" => notifications
        }
      })

    {:ok, sock} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw], 2_000)

    request =
      "POST / HTTP/1.1\r\n" <>
        "Host: localhost\r\n" <>
        "Content-Type: application/json\r\n" <>
        "Accept: text/event-stream\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n\r\n" <> body

    :ok = :gen_tcp.send(sock, request)
    %{socket: sock, raw: "", parser: SSE.new_parser(), pending: [], headers: nil}
  end

  # Returns the next SSE event, or `:timeout` / `:closed`. Events already
  # decoded but not yet consumed are queued: Bandit is free to coalesce the
  # acknowledgment and a following notification into one TCP read, and a helper
  # that returned the first and discarded the rest would make an ordering test
  # pass by losing the evidence.
  defp next_event(stream, timeout \\ 2_000)

  defp next_event(%{pending: [event | rest]} = stream, _timeout) do
    {:ok, event, %{stream | pending: rest}}
  end

  defp next_event(stream, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    pump(stream, deadline)
  end

  defp pump(stream, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:timeout, stream}
    else
      case :gen_tcp.recv(stream.socket, 0, remaining) do
        {:ok, data} -> take_or_pump(absorb(stream, data), deadline)
        {:error, :timeout} -> {:timeout, stream}
        {:error, :closed} -> {:closed, stream}
      end
    end
  end

  defp take_or_pump(%{pending: [event | rest]} = stream, _deadline),
    do: {:ok, event, %{stream | pending: rest}}

  defp take_or_pump(stream, deadline), do: pump(stream, deadline)

  # Feeds raw socket bytes through HTTP header stripping, chunked-transfer
  # de-framing and the SSE parser, in that order. Decoding the chunk framing
  # properly rather than heuristically matters here: a keep-alive is a bare
  # `:\r\n`, which a "strip anything that looks like a size line" shortcut can
  # silently eat — and eating it would make the keep-alive assertion below
  # untestable rather than failing.
  defp absorb(stream, data) do
    stream = %{stream | raw: stream.raw <> data}
    {body, stream} = strip_headers(stream)
    {payload, rest} = dechunk(body, "")
    {events, parser} = SSE.feed(stream.parser, payload)
    %{stream | raw: rest, parser: parser, pending: stream.pending ++ events}
  end

  defp strip_headers(%{headers: nil} = stream) do
    case String.split(stream.raw, "\r\n\r\n", parts: 2) do
      [headers, rest] -> {rest, %{stream | headers: headers, raw: rest}}
      [_incomplete] -> {"", stream}
    end
  end

  defp strip_headers(stream), do: {stream.raw, stream}

  # Minimal HTTP/1.1 chunked-transfer decoder: `<hex-size>\r\n<data>\r\n`,
  # repeated. Returns the decoded payload and whatever tail is still incomplete.
  defp dechunk(buffer, acc) do
    case String.split(buffer, "\r\n", parts: 2) do
      [size_line, rest] ->
        case Integer.parse(size_line, 16) do
          {0, _} ->
            {acc, ""}

          {size, _} when byte_size(rest) >= size + 2 ->
            <<chunk::binary-size(size), "\r\n", tail::binary>> = rest
            dechunk(tail, acc <> chunk)

          _ ->
            {acc, buffer}
        end

      [_incomplete] ->
        {acc, buffer}
    end
  end

  # The raw bytes the server wrote over `duration`, decoded out of the chunk
  # framing but NOT through the SSE parser — which discards comment lines by
  # design, so it is the wrong instrument for asserting a keep-alive was sent.
  defp collect_raw(stream, duration) do
    deadline = System.monotonic_time(:millisecond) + duration
    collect_raw(stream, deadline, "")
  end

  defp collect_raw(stream, deadline, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {acc, stream}
    else
      case :gen_tcp.recv(stream.socket, 0, remaining) do
        {:ok, data} ->
          stream = %{stream | raw: stream.raw <> data}
          {body, stream} = strip_headers(stream)
          {payload, rest} = dechunk(body, "")
          collect_raw(%{stream | raw: rest}, deadline, acc <> payload)

        {:error, :timeout} ->
          {acc, stream}

        {:error, :closed} ->
          {acc, stream}
      end
    end
  end

  defp decode(event), do: Jason.decode!(event.data)

  defp close(%{socket: sock}), do: :gen_tcp.close(sock)

  # A one-shot POST over the raw client, returning `{status, body}` only once
  # the server has CLOSED the connection. `Req` returns as soon as the response
  # body is complete, which on the refusal path is strictly before the driver
  # runs teardown — so anything the driver logs during teardown may land after
  # a `capture_log/1` block that wrapped the `Req` call has already ended. That
  # is a race in the test, not in the SDK, and it made the R3 assertion below
  # fail on roughly two seeds in three. `Connection: close` makes the socket's
  # EOF a signal that the plug has RETURNED, which is after teardown.
  defp post_until_closed(port, body) do
    {:ok, sock} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw], 2_000)

    request =
      "POST / HTTP/1.1\r\n" <>
        "Host: localhost\r\n" <>
        "Origin: http://localhost\r\n" <>
        "Content-Type: application/json\r\n" <>
        "Connection: close\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n\r\n" <> body

    :ok = :gen_tcp.send(sock, request)
    raw = recv_until_closed(sock, "")
    [headers, response_body] = String.split(raw, "\r\n\r\n", parts: 2)
    [status_line | _] = String.split(headers, "\r\n")
    [_http, status | _] = String.split(status_line, " ")
    {String.to_integer(status), response_body}
  end

  defp recv_until_closed(sock, acc) do
    case :gen_tcp.recv(sock, 0, 2_000) do
      {:ok, data} -> recv_until_closed(sock, acc <> data)
      {:error, :closed} -> acc
      {:error, :timeout} -> acc
    end
  end

  # --- the acknowledgment ---

  describe "the stream opens with its acknowledgment" do
    test "the first message is notifications/subscriptions/acknowledged", %{a: port} do
      stream = open_listen(port, %{"toolsListChanged" => true, "promptsListChanged" => true})

      assert {:ok, event, _stream} = next_event(stream)
      ack = decode(event)

      assert ack["method"] == "notifications/subscriptions/acknowledged"
      assert ack["params"]["_meta"][@sub_id_key] == "listen-1"

      # The honoured subset, not the requested set: this handler never honours
      # promptsListChanged, and the client is told so on the first frame.
      assert ack["params"]["notifications"] == %{"toolsListChanged" => true}

      close(stream)
    end

    test "the response carries the SSE headers the spec SHOULDs", %{a: port} do
      stream = open_listen(port, %{"toolsListChanged" => true})
      assert {:ok, _ack, stream} = next_event(stream)
      headers = String.downcase(stream.headers)

      assert headers =~ "content-type: text/event-stream"
      assert headers =~ "x-accel-buffering: no"
      assert headers =~ "cache-control: no-cache"
      # Resumption is explicitly not supported in this revision.
      refute headers =~ "last-event-id"

      close(stream)
    end

    test "nothing bearing this subscription's id precedes its acknowledgment", %{a: port} do
      # SubscribingHandler emits INSIDE handle_listen/3 for the id "eager" —
      # i.e. strictly before the acknowledgment can have been written. Emitting
      # from the test after handle_listen/3 returned would race the ack rather
      # than order against it, and would pass whether or not the ordering held.
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "eager")

      assert {:ok, first, stream} = next_event(stream)
      assert decode(first)["method"] == "notifications/subscriptions/acknowledged"

      assert {:ok, second, _stream} = next_event(stream)
      assert decode(second)["method"] == "notifications/tools/list_changed"
      assert decode(second)["params"]["_meta"][@sub_id_key] == "eager"

      close(stream)
    end
  end

  # --- delivery and filtering, end to end ---

  describe "delivery over the wire" do
    test "an opted-in notification arrives, stamped with the subscription id", %{a: port} do
      stream = open_listen(port, %{"toolsListChanged" => true})
      assert {:ok, _ack, stream} = next_event(stream)

      assert_receive {:listen_opened, _id, _honoured, sink, _identity}, 2_000
      assert :ok = sink.("notifications/tools/list_changed", %{})

      assert {:ok, event, _stream} = next_event(stream)
      frame = decode(event)

      assert frame["method"] == "notifications/tools/list_changed"
      assert frame["params"]["_meta"][@sub_id_key] == "listen-1"

      close(stream)
    end

    test "an unrequested type never reaches the wire", %{a: port} do
      stream = open_listen(port, %{"toolsListChanged" => true})
      assert {:ok, _ack, stream} = next_event(stream)

      assert_receive {:listen_opened, _id, _honoured, sink, _identity}, 2_000

      # Refused: not opted in. Request-scoped: never mappable to a filter key.
      sink.("notifications/prompts/list_changed", %{})
      sink.("notifications/progress", %{"progress" => 1})
      sink.("notifications/message", %{"level" => "info", "data" => "x"})
      # Then one that IS opted in, so the test cannot pass by nothing arriving.
      sink.("notifications/tools/list_changed", %{})

      assert {:ok, event, _stream} = next_event(stream)
      assert decode(event)["method"] == "notifications/tools/list_changed"

      close(stream)
    end
  end

  # --- T-8: keep-alive frames, both directions ---

  describe "T-8 keep-alive comment lines" do
    test "the encoder emits a bare comment line" do
      assert SSE.comment() == ":\r\n"
      # encode_event/1 cannot produce one — it always appends a data: line —
      # which is why comment/0 exists rather than a flag on it.
      refute SSE.encode_event(%{}) == SSE.comment()
      assert SSE.encode_event(%{}) =~ "data:"
    end

    test "our parser ignores a comment line arriving between two events" do
      first = SSE.encode_message(%{"jsonrpc" => "2.0", "method" => "one"})
      second = SSE.encode_message(%{"jsonrpc" => "2.0", "method" => "two"})

      {events, _rest} = SSE.feed(SSE.new_parser(), first <> ":\n\n" <> second)

      methods = Enum.map(events, &Jason.decode!(&1.data)["method"])
      assert methods == ["one", "two"]
    end

    test "an idle stream actually emits comment frames, and stays open", %{a: port} do
      # keepalive_interval is 150ms in this harness, so ~500ms of silence should
      # produce several. Read the RAW payload rather than parsed events: the SSE
      # parser discards comment lines by design, so asserting through it would
      # pass identically whether or not a single keep-alive was ever written.
      stream = open_listen(port, %{"toolsListChanged" => true})
      assert {:ok, _ack, stream} = next_event(stream)

      {raw, stream} = collect_raw(stream, 500)

      keepalives = raw |> String.split("\r\n", trim: true) |> Enum.count(&(&1 == ":"))
      assert keepalives >= 2, "expected keep-alive comment lines, got: #{inspect(raw)}"

      # And the stream is still usable afterwards.
      assert_receive {:listen_opened, _id, _honoured, sink, _identity}, 2_000
      assert :ok = sink.("notifications/tools/list_changed", %{})

      assert {:ok, event, _stream} = next_event(stream)
      assert decode(event)["method"] == "notifications/tools/list_changed"

      close(stream)
    end
  end

  # --- T-9: cancellation and teardown ---

  describe "T-9 closing the stream is cancellation" do
    test "the client closing tears the subscription down within a bounded window", %{a: port} do
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "cancel-me")
      assert {:ok, _ack, _stream} = next_event(stream)
      assert_receive {:listen_opened, "cancel-me", _honoured, sink, _identity}, 2_000

      close(stream)

      # Bounded by one keep-alive interval plus a round trip — asserted as a
      # window rather than an exact write count, because "the first write
      # fails" is a loopback measurement and a real network adds an RTT.
      assert_receive {:listen_closed, "cancel-me", "alice"}, 2_000

      # And after teardown the sink refuses rather than silently pretending.
      assert {:error, :closed} = sink.("notifications/tools/list_changed", %{})
    end

    test "the handler's teardown callback runs exactly once", %{a: port} do
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "once")
      assert {:ok, _ack, _stream} = next_event(stream)
      assert_receive {:listen_opened, "once", _, _, _}, 2_000

      close(stream)
      assert_receive {:listen_closed, "once", _}, 2_000
      refute_receive {:listen_closed, "once", _}, 500
    end
  end

  # --- T-12: graceful close vs abrupt drop ---

  describe "T-12 the close asymmetry a client depends on" do
    test "lifetime expiry sends the listen response, then closes" do
      # A 400ms lifetime, so expiry is the teardown reason rather than a
      # disconnect. This is the graceful path.
      port = start_instance(self(), max_stream_lifetime: 400, keepalive_interval: 100)
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "expires")

      assert {:ok, ack, stream} = next_event(stream)
      assert decode(ack)["method"] == "notifications/subscriptions/acknowledged"

      assert {:ok, event, _stream} = next_event(stream, 3_000)
      response = decode(event)

      # Exactly the pinned SubscriptionsListenResultResponse shape.
      assert response == %{
               "jsonrpc" => "2.0",
               "id" => "expires",
               "result" => %{
                 "resultType" => "complete",
                 "_meta" => %{@sub_id_key => "expires"}
               }
             }

      assert_receive {:listen_closed, "expires", _}, 2_000
      close(stream)
    end

    test "the close-frame decision refuses to write after a peer close" do
      # The half of the asymmetry end-to-end testing CANNOT reach: once the peer
      # is gone, "sent nothing" and "tried and failed" are indistinguishable
      # from outside, because the write fails either way. So the decision itself
      # is asserted, at the one place it is a value rather than an effect.
      sub = MCP.Server.Subscription.new("s-1", %{"toolsListChanged" => true})

      assert :none == MCP.Server.Subscription.close_frame(sub, :peer_closed)

      assert {:send, %{"id" => "s-1", "result" => %{"resultType" => "complete"}}} =
               MCP.Server.Subscription.close_frame(sub, :lifetime_expired)

      assert {:send, _} = MCP.Server.Subscription.close_frame(sub, :shutdown)
    end

    test "an abrupt client drop still tears the subscription down", %{a: port} do
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "dropped")
      assert {:ok, _ack, _stream} = next_event(stream)
      assert_receive {:listen_opened, "dropped", _, sink, _}, 2_000

      close(stream)
      assert_receive {:listen_closed, "dropped", _}, 2_000

      # MUST NOT send further messages for a cancelled request: the sink is
      # dead, so nothing further can be produced for it either.
      assert {:error, :closed} = sink.("notifications/tools/list_changed", %{})
    end
  end

  # --- T-10: the multi-instance boundary (Ruling 1), with its positive control ---

  describe "T-10 the documented multi-instance boundary" do
    test "a change on instance B does not reach a stream held by instance A", %{a: a, b: b} do
      stream = open_listen(a, %{"toolsListChanged" => true}, id: "on-a")
      assert {:ok, _ack, stream} = next_event(stream)
      assert_receive {:listen_opened, "on-a", _, sink_a, _}, 2_000

      # Drive a change through instance B by opening — and immediately
      # abandoning — a subscription there, which is the only way to obtain B's
      # emitter. B's sink is not A's.
      other = open_listen(b, %{"toolsListChanged" => true}, id: "on-b")
      assert {:ok, _ack_b, _} = next_event(other)
      assert_receive {:listen_opened, "on-b", _, sink_b, _}, 2_000

      sink_b.("notifications/tools/list_changed", %{})

      # THE BOUNDARY: nothing emitted on B appears on A's stream. There is no
      # fan-out seam and no broadcast dependency, and that is deliberate.
      assert {:timeout, stream} = next_event(stream, 500)

      # THE POSITIVE CONTROL, without which the assertion above passes just as
      # happily on a completely broken stream: the same notification emitted on
      # A's own sink DOES arrive.
      sink_a.("notifications/tools/list_changed", %{})
      assert {:ok, event, _stream} = next_event(stream, 2_000)
      assert decode(event)["method"] == "notifications/tools/list_changed"

      close(stream)
      close(other)
    end
  end

  # --- MC-6: clean failure when the stream cannot be started ---

  describe "MC-6 a stream that cannot start fails cleanly" do
    test "controlled -32603, nothing streamed, and the handler is told" do
      # The failure is injected through the :stream_start seam, for the same
      # reason MES-14 made the collector start injectable: a chunked-response
      # start cannot be made to fail from outside, so without a seam this
      # guarantee would rest on inspection rather than on a test.
      port =
        start_instance(self(),
          stream_start: fn _conn -> {:error, %RuntimeError{message: "socket gone"}} end
        )

      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => "wont-start",
          "method" => "subscriptions/listen",
          "params" => %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
            "notifications" => %{"toolsListChanged" => true}
          }
        })

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          response =
            Req.post!("http://127.0.0.1:#{port}/",
              body: body,
              headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}]
            )

          assert response.status == 500
          assert response.body["error"]["code"] == -32_603
          # The server-side detail stays server-side.
          assert response.body["error"]["data"] == "subscription stream unavailable"
          refute response.body["error"]["data"] =~ "socket gone"
        end)

      assert log =~ "could not start the subscription stream"

      # The handler ran handle_listen/3 and is holding a sink for a stream that
      # will never exist; it is told so, rather than left believing the
      # subscription is open.
      assert_receive {:listen_opened, "wont-start", _, sink, _}, 2_000
      assert_receive {:listen_closed, "wont-start", _}, 2_000
      assert {:error, :closed} = sink.("notifications/tools/list_changed", %{})
    end
  end

  # --- Correction round 1 (review F4): the collector/stream lifetime property ---

  describe "the collector's lifetime ends strictly before the stream's" do
    test "the collector is gone by the time the stream is live", %{a: port} do
      # Replaces the T-7 case that could not fail. The claim it guarded — "the
      # listen path starts no NotificationCollector" — was false: the driver
      # starts one for every POST, a listen included. What is true is the
      # ordering, and the ordering is what the driver relies on, so that is
      # what this asserts.
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          stream = open_listen(port, %{"toolsListChanged" => true}, id: "collector-probe")

          # The ack means the stream is open — i.e. we are strictly after the
          # point where the driver drains and stops the collector.
          assert {:ok, ack, _stream} = next_event(stream)
          assert decode(ack)["method"] == "notifications/subscriptions/acknowledged"

          assert_receive {:listen_reply_sink, "collector-probe", reply_sink}, 2_000

          # THE PROPERTY: the collector this sink pushes to is already dead.
          # Not "returns an error" — there is no live process to answer.
          #
          # Recorded, not fixed (review round 2, L4): this assertion couples
          # the test to `NotificationCollector.push/3` being a `call`. If push
          # ever became a `cast` this would go red while the ordering property
          # it guards still held. Brittle in the safe direction — a false red
          # on a refactor, never a false green — so it stays as written.
          assert {:noproc, _} =
                   catch_exit(reply_sink.("notifications/message", %{"level" => "info"}))

          close(stream)
        end)

      # THE POSITIVE CONTROL, without which the exit above is satisfied just as
      # happily by a collector that never worked: the same sink DID reach a live
      # collector during handle_listen/3, and the driver drained exactly one
      # notification out of it and said so.
      assert log =~ "discarded 1 request-scoped notification"
    end
  end

  # --- Correction round 1 (found while fixing K1, reported to the PM) ---

  describe "the teardown context has no channels" do
    test "a handler emitting from handle_listen_closed/3 is dropped, not exited", %{a: port} do
      # `notify_listen_closed/4` rescues but does not catch exits, and
      # `:reply_sink` used to still be bound here — to a collector the driver
      # had already stopped, so an `Agent.update` against a dead pid exited with
      # :noproc and took the request process with it. On the refusal exit added
      # by K1 that would land BEFORE the refusal response is written, turning a
      # clean error response into a dropped connection. Demonstrated against the
      # unfixed sink: `right: {:exit, {:noproc, {GenServer, :call, ...}}}`.
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "teardown-emits")
      assert {:ok, _ack, _stream} = next_event(stream)
      assert_receive {:listen_opened, "teardown-emits", _, _, _}, 2_000

      close(stream)

      assert_receive {:listen_closed_emit, "teardown-emits", emitted, reply_sink}, 2_000
      assert is_nil(reply_sink)
      # Dropped on the reply side, and told there is no stream on the other.
      assert {:returned, :ok, {:error, :no_stream}} = emitted
    end
  end

  # --- Correction round 1 (review F1/F2): teardown on every exit ---

  describe "every exit from a listen runs teardown" do
    test "a REFUSED listen tells the handler and kills the sink (F1)" do
      # The handler is handed a live sink and then refuses. Before the fix
      # `release_stream/1` and `notify_listen_closed/4` were reachable only from
      # inside `open_stream/7`, so this path ran neither: the refusal response
      # was correct on the wire while the handler was left holding a sink that
      # went on answering `:ok` for the life of the connection.
      port = start_instance(self(), handler_opts: [owner: self(), identity: "denied"])

      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => "refuse-me",
          "method" => "subscriptions/listen",
          "params" => %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
            "notifications" => %{"toolsListChanged" => true}
          }
        })

      response =
        Req.post!("http://127.0.0.1:#{port}/",
          body: body,
          headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}]
        )

      # The refusal itself, on the wire and unchanged by this fix.
      assert response.status == 200
      {[event], _parser} = SSE.feed(SSE.new_parser(), response.body)
      refusal = Jason.decode!(event.data)
      assert refusal["id"] == "refuse-me"
      assert refusal["error"]["code"] == -32_603

      # Both halves of K1, on the one path that had neither.
      assert_receive {:listen_refusing, "refuse-me", sink, "denied"}, 2_000
      assert_receive {:listen_closed, "refuse-me", "denied"}, 2_000
      assert {:error, :closed} = sink.("notifications/tools/list_changed", %{})
    end

    test "a RAISE inside the stream loop tells the handler and kills the sink (F2)", %{a: port} do
      # Non-map params reach `Subscription.frame/3` and raise there, killing the
      # process that holds the stream. The wire side of that is defensible — an
      # abrupt drop with no close response is exactly what the asymmetry means —
      # but the handler side was not: it was never told, and the sink went on
      # answering `:ok` for a stream whose owner was dead.
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "raises")
      assert {:ok, _ack, _stream} = next_event(stream)
      assert_receive {:listen_opened, "raises", _honoured, sink, _identity}, 2_000

      ExUnit.CaptureLog.capture_log(fn ->
        # The sink only posts a message, so this call itself succeeds; the raise
        # happens in the stream owner when the message becomes a frame.
        sink.("notifications/tools/list_changed", "not-a-map")

        assert_receive {:listen_closed, "raises", _}, 2_000
      end)

      assert {:error, :closed} = sink.("notifications/tools/list_changed", %{})

      close(stream)
    end

    test "teardown still runs exactly once when an exit tears down and then unwinds", %{a: port} do
      # `close_stream/7` tears down explicitly and `open_stream/7`'s `after`
      # tears down again on the way out. The claim slot is what makes that two
      # calls and one notification.
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "once-only")
      assert {:ok, _ack, _stream} = next_event(stream)
      assert_receive {:listen_opened, "once-only", _, _, _}, 2_000

      close(stream)
      assert_receive {:listen_closed, "once-only", _}, 2_000
      refute_receive {:listen_closed, "once-only", _}, 500
    end
  end

  # --- Correction round 2 (review R1/R3): teardown is established around the
  #     lifecycle, not per branch ---

  describe "the exits that raise before a branch is chosen" do
    test "a RAISE inside handle_listen/3 tells the handler and kills the sink (R1)" do
      # PROBE A from the re-review. The handler captured the sink and then
      # raised, so the request died before `Dispatch.dispatch/3` returned a
      # value for the driver to branch on — which is why counting branches
      # could never have reached it. Both halves are asserted: the sink refuses,
      # AND the handler is told, because a handler that raised after capturing
      # the sink still ran and may hold a registration nothing else will reap.
      port = start_instance(self())

      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => "raise-in-listen",
          "method" => "subscriptions/listen",
          "params" => %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
            "notifications" => %{"toolsListChanged" => true}
          }
        })

      ExUnit.CaptureLog.capture_log(fn ->
        response =
          Req.post!("http://127.0.0.1:#{port}/",
            body: body,
            headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}],
            retry: false
          )

        # The wire side is unchanged and is not what this fixes: a crashed
        # request is a 500 with no body. What changes is what it leaves behind.
        assert response.status == 500
      end)

      assert_receive {:listen_raising, "raise-in-listen", sink, "alice"}, 2_000
      assert_receive {:listen_closed, "raise-in-listen", "alice"}, 2_000
      assert {:error, :closed} = sink.("notifications/tools/list_changed", %{})
    end

    test "a :stream_start that RAISES tells the handler and kills the sink (R1)" do
      # PROBE B. `start_chunked/1` rescues into `{:error, exception}`, but the
      # seam is injectable and a custom one is free to raise — and before this
      # round that got half the property: `release_stream/1` ran on the way out,
      # `handle_listen_closed/3` did not.
      port =
        start_instance(self(),
          stream_start: fn _conn -> raise "socket gone while starting the stream" end
        )

      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => "start-raises",
          "method" => "subscriptions/listen",
          "params" => %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
            "notifications" => %{"toolsListChanged" => true}
          }
        })

      ExUnit.CaptureLog.capture_log(fn ->
        response =
          Req.post!("http://127.0.0.1:#{port}/",
            body: body,
            headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}],
            retry: false
          )

        assert response.status == 500
      end)

      assert_receive {:listen_opened, "start-raises", _honoured, sink, _identity}, 2_000
      assert_receive {:listen_closed, "start-raises", _identity}, 2_000
      assert {:error, :closed} = sink.("notifications/tools/list_changed", %{})
    end

    test "a listen answered ABOVE the handler is owed no teardown callback" do
      # The other half of the same property, and the only reason the obligation
      # is ever disarmed: a malformed filter never reaches `handle_listen/3`, so
      # telling the handler its subscription closed would be the same false
      # claim pointed the other way. Without this the round-2 fix could pass by
      # simply always notifying.
      port = start_instance(self())

      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => "no-filter",
          "method" => "subscriptions/listen",
          "params" => %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version}
          }
        })

      response =
        Req.post!("http://127.0.0.1:#{port}/",
          body: body,
          headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}]
        )

      assert response.status == 200
      {[event], _parser} = SSE.feed(SSE.new_parser(), response.body)
      assert Jason.decode!(event.data)["error"]["code"] == -32_602

      # The positive control is the pair of tests above: the same assertion
      # shape DOES receive on the paths where the handler ran.
      refute_receive {:listen_closed, "no-filter", _}, 500
    end

    test "a handler-side exit in teardown does not replace the refusal response (R3)" do
      # The residue of c4b6578: `notify_listen_closed/4` rescued but did not
      # catch exits, and on the refusal exit teardown ran BEFORE the response —
      # so a handler whose own teardown faulted turned a clean -32xxx into a
      # bare 500 with an empty body.
      port = start_instance(self(), handler_opts: [owner: self(), identity: "denied"])

      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => "exit-in-teardown",
          "method" => "subscriptions/listen",
          "params" => %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
            "notifications" => %{"toolsListChanged" => true}
          }
        })

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          # `post_until_closed/2` rather than `Req`: the line this test asserts
          # on is logged during teardown, which the driver runs AFTER writing
          # the response. Waiting for the connection to close keeps that inside
          # the capture window; `Logger.flush/0` then drains what was queued
          # before the block ends.
          {status, response_body} = post_until_closed(port, body)

          # THE PROPERTY: what the client receives is decided by the request,
          # not by whether the handler's teardown callback worked.
          assert status == 200
          {[event], _parser} = SSE.feed(SSE.new_parser(), response_body)
          refusal = Jason.decode!(event.data)
          assert refusal["id"] == "exit-in-teardown"
          assert refusal["error"]["code"] == -32_603

          Logger.flush()
        end)

      # THE POSITIVE CONTROL, without which a callback that quietly succeeded
      # would satisfy the assertions above just as happily: the callback ran and
      # really did exit, and the driver said so.
      assert_receive {:listen_closed, "exit-in-teardown", "denied"}, 2_000
      assert log =~ "handle_listen_closed/3 exit:"
      assert log =~ ":noproc"
    end
  end

  # --- R4: what arms the teardown obligation ---

  describe "the obligation is armed off the decoded message" do
    # A7 IN ITS ORDINARY FORM — these two are caught regressions, not positive
    # controls. Both fail at 0f12936, where `listen_request?/1` read
    # `Map.get(raw_message, "method")`: `Protocol.decode_message/1` classifies
    # by SHAPE and tests Response before Request, so `id` + `result` + `method`
    # decodes as a `%Response{}`, which `MCP.Server.Dispatch` has no clause for.
    # The message armed the obligation, raised above every routing decision,
    # and paid teardown with an id the client chose.

    test "a Response-shaped message naming the method is not a listen (R4)" do
      port = start_instance(self())

      crafted = fn id, method ->
        Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => %{}, "method" => method})
      end

      ExUnit.CaptureLog.capture_log(fn ->
        # The probe, and its control: the ONLY difference between the two is
        # the method string. Nothing else about either is a listen — not the
        # shape, not the routing, not the handler — so they must be treated
        # alike, and at 0f12936 they were not.
        for {id, method} <- [
              {"crafted-listen", "subscriptions/listen"},
              {"crafted-other", "tools/list"}
            ] do
          response =
            Req.post!("http://127.0.0.1:#{port}/",
              body: crafted.(id, method),
              headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}],
              retry: false
            )

          # The wire side is not what this fixes: an unroutable message is a
          # 500 either way (MES-31 covers the non-map body's 500 separately).
          # What changes is what it leaves behind.
          assert response.status == 500
        end
      end)

      refute_receive {:listen_closed, "crafted-listen", _}, 500
      refute_receive {:listen_closed, "crafted-other", _}, 100

      # THE POSITIVE CONTROL for the two refutations above, without which they
      # could pass on a handler that never reports anything: a genuine listen
      # on this same instance, torn down, does reach this test.
      ExUnit.CaptureLog.capture_log(fn ->
        Req.post!("http://127.0.0.1:#{port}/",
          body:
            Jason.encode!(%{
              "jsonrpc" => "2.0",
              "id" => "raise-in-listen",
              "method" => "subscriptions/listen",
              "params" => %{
                "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
                "notifications" => %{"toolsListChanged" => true}
              }
            }),
          headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}],
          retry: false
        )
      end)

      assert_receive {:listen_closed, "raise-in-listen", "alice"}, 2_000
    end

    test "a second client cannot tear down a live subscription it does not own (R4)", %{a: port} do
      # THE REACH, and why R4 was blocking rather than an over-approximation:
      # the id is whatever the client put in the message, so it can name a
      # subscription that is currently open — on someone else's connection.
      stream = open_listen(port, %{"toolsListChanged" => true}, id: "sub-A")
      assert {:ok, ack, stream} = next_event(stream)
      assert decode(ack)["method"] == "notifications/subscriptions/acknowledged"

      assert_receive {:listen_opened, "sub-A", _honoured, sink, _identity}, 2_000
      assert :ok = sink.("notifications/tools/list_changed", %{})
      assert {:ok, _frame, stream} = next_event(stream)

      # Client B, a separate connection to the same instance, naming A's id.
      ExUnit.CaptureLog.capture_log(fn ->
        response =
          Req.post!("http://127.0.0.1:#{port}/",
            body:
              Jason.encode!(%{
                "jsonrpc" => "2.0",
                "id" => "sub-A",
                "result" => %{},
                "method" => "subscriptions/listen"
              }),
            headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}],
            retry: false
          )

        assert response.status == 500
      end)

      # THE PROPERTY: B's request said nothing about A's subscription, and the
      # SDK does not disagree with itself about whether sub-A is open.
      refute_receive {:listen_closed, "sub-A", _}, 500
      assert :ok = sink.("notifications/tools/list_changed", %{})
      assert {:ok, event, stream} = next_event(stream)
      assert decode(event)["params"]["_meta"][@sub_id_key] == "sub-A"

      # THE POSITIVE CONTROL: teardown for this very id is not merely absent —
      # it arrives when A itself closes, which is the only thing that may cause
      # it.
      close(stream)
      assert_receive {:listen_closed, "sub-A", "alice"}, 2_000
    end
  end

  # --- JSON mode ---

  describe "JSON mode refuses the method" do
    test "subscriptions/listen returns -32601 rather than an empty stream" do
      port = start_instance(self(), enable_json_response: true)

      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "subscriptions/listen",
          "params" => %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
            "notifications" => %{"toolsListChanged" => true}
          }
        })

      response =
        Req.post!("http://127.0.0.1:#{port}/",
          body: body,
          headers: [{"content-type", "application/json"}, {"origin", "http://localhost"}]
        )

      assert response.status == 200
      assert response.body["error"]["code"] == -32_601
    end
  end
end
