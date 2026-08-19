defmodule MCP.Server.SubscriptionsDispatchTest do
  @moduledoc """
  MES-15 — `subscriptions/listen` at the dispatch and protocol layer.

  Covers T-1 (wire shapes pinned against the schema's own example JSONs), T-2
  (ack-first and honoured-subset), T-3/T-4 (the two stream MUST NOTs), T-5's
  ack ⊆ advertised invariant and the JSON-mode refusal, T-6/T-7 (sink
  separation), and T-11's driver-opt-in half.

  ## A7/A7b honesty

  Every test in this file is a **positive control**, not a caught regression:
  `subscriptions/listen` did not exist before this ticket, so there is no
  pre-fix SHA at which these could fail for the right reason. Where the failing
  direction matters, it is exercised by asserting the *refusal* path (a stream
  that drops what it must drop, an ack that omits what was not honoured)
  against the same code — not by claiming a regression was caught.

  The one exception is `MCP.Server.CapabilityHonestyTest`, which IS a
  regression suite; it is kept in its own file for exactly that reason.
  """
  use ExUnit.Case, async: true

  alias MCP.Protocol.Messages.Subscriptions
  alias MCP.Protocol.Meta
  alias MCP.Protocol.Methods
  alias MCP.Server.{Config, Dispatch, Subscription, ToolContext}
  alias MCP.Test.SubscribingHandler

  @version "2026-07-28"
  @sub_id_key "io.modelcontextprotocol/subscriptionId"

  # --- harness ---

  defp config(opts \\ []) do
    {:ok, config} =
      Config.build(
        SubscribingHandler,
        Keyword.merge([streaming: true, handler_opts: [owner: self()]], opts)
      )

    config
  end

  defp listen_request(notifications, opts \\ []) do
    params =
      %{"_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version}}
      |> then(fn p ->
        if notifications == :omitted, do: p, else: Map.put(p, "notifications", notifications)
      end)

    %MCP.Protocol.Messages.Request{
      id: Keyword.get(opts, :id, "listen-1"),
      method: "subscriptions/listen",
      params: params
    }
  end

  defp ctx(opts \\ []) do
    %ToolContext{
      request_id: Keyword.get(opts, :id, "listen-1"),
      identity: Keyword.get(opts, :identity, "alice"),
      stream_sink: Keyword.get(opts, :stream_sink, fn _m, _p -> :ok end)
    }
  end

  defp open(notifications, opts \\ []) do
    Dispatch.dispatch(
      listen_request(notifications, opts),
      ctx(opts),
      config(Keyword.take(opts, [:streaming]))
    )
  end

  # --- T-1: wire shapes, pinned against the schema's own examples ---

  describe "T-1 wire shapes (pinned to schema/2026-07-28 examples)" do
    test "the request parses as the pinned SubscriptionsListenRequest example" do
      # schema/2026-07-28/examples/SubscriptionsListenRequest/listen-for-list-changes.json
      params = %{
        "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
        "notifications" => %{
          "toolsListChanged" => true,
          "resourceSubscriptions" => ["file:///project/config.json"]
        }
      }

      assert {:ok, filter} = Subscriptions.parse_filter(params)

      assert filter == %{
               "toolsListChanged" => true,
               "resourceSubscriptions" => ["file:///project/config.json"]
             }
    end

    test "the acknowledgment matches the pinned SubscriptionsAcknowledgedNotification example" do
      # schema/2026-07-28/examples/SubscriptionsAcknowledgedNotification/listen-acknowledged.json
      honoured = %{
        "toolsListChanged" => true,
        "resourceSubscriptions" => ["file:///project/config.json"]
      }

      assert Subscriptions.acknowledgment("listen-1", honoured) == %{
               "jsonrpc" => "2.0",
               "method" => "notifications/subscriptions/acknowledged",
               "params" => %{
                 "_meta" => %{@sub_id_key => "listen-1"},
                 "notifications" => honoured
               }
             }
    end

    test "the graceful-close response matches the pinned example exactly" do
      # schema/2026-07-28/examples/SubscriptionsListenResultResponse/
      #   listen-closed-response.json — NOT `result: {}`. The prose calls it
      # "the empty response" (subscriptions.mdx:124), meaning empty apart from
      # the two REQUIRED fields. Pinned here so a later reader cannot "simplify"
      # it into a schema violation.
      assert Subscriptions.close_response("listen-1") == %{
               "jsonrpc" => "2.0",
               "id" => "listen-1",
               "result" => %{
                 "resultType" => "complete",
                 "_meta" => %{@sub_id_key => "listen-1"}
               }
             }
    end

    test "a resources/updated frame matches the pinned notification example" do
      sub =
        Subscription.new("listen-1", %{"resourceSubscriptions" => ["file:///project/src/main.rs"]})

      assert {:ok, frame} =
               Subscription.frame(sub, Methods.resources_updated(), %{
                 "uri" => "file:///project/src/main.rs"
               })

      assert frame == %{
               "jsonrpc" => "2.0",
               "method" => "notifications/resources/updated",
               "params" => %{
                 "_meta" => %{@sub_id_key => "listen-1"},
                 "uri" => "file:///project/src/main.rs"
               }
             }
    end

    test "the id is echoed, never coerced — RequestId is string OR integer" do
      # The pinned examples use a string id; the mdx prose uses an integer. Both
      # are legal RequestIds, so the implementation must echo what it was given.
      assert %{"id" => 7} = Subscriptions.close_response(7)

      assert %{"params" => %{"_meta" => %{@sub_id_key => 7}}} =
               Subscriptions.acknowledgment(7, %{})

      assert %{"id" => "listen-1"} = Subscriptions.close_response("listen-1")
    end

    test "notifications is required; {} is legal and means subscribe to nothing" do
      assert {:ok, %{}} = Subscriptions.parse_filter(%{"notifications" => %{}})
      assert {:error, :missing_notifications} = Subscriptions.parse_filter(%{})

      assert {:error, :invalid_notifications} =
               Subscriptions.parse_filter(%{"notifications" => []})
    end

    test "an absent notifications object is -32602, not a silently empty stream" do
      assert {:reply, %{"error" => error}, _} = open(:omitted)
      assert error["code"] == -32_602
    end

    test "an empty filter opens a real stream that carries nothing" do
      assert {:stream, %Subscription{} = sub, _} = open(%{})
      assert sub.honoured == %{}
      assert MapSet.size(sub.allowed) == 0
      assert Subscription.frame(sub, Methods.tools_list_changed(), %{}) == :drop
    end
  end

  # --- T-2: ack first, and the honoured subset rather than the requested one ---

  describe "T-2 the acknowledgment reports what was honoured" do
    test "a requested-but-refused type is absent from the ack" do
      requested = %{
        "toolsListChanged" => true,
        "promptsListChanged" => true,
        "resourcesListChanged" => true
      }

      assert {:stream, %Subscription{} = sub, _} = open(requested)

      # SubscribingHandler never honours promptsListChanged.
      assert sub.honoured == %{"toolsListChanged" => true, "resourcesListChanged" => true}
      assert sub.ack["params"]["notifications"] == sub.honoured
      refute Map.has_key?(sub.ack["params"]["notifications"], "promptsListChanged")
    end

    test "the ack is built from the same value the stream enforces" do
      assert {:stream, %Subscription{} = sub, _} = open(%{"toolsListChanged" => true})

      # Not merely equal by inspection: every method the ack promises is a
      # method the stream accepts, and nothing else is accepted.
      promised = Subscriptions.allowed_methods(sub.ack["params"]["notifications"])
      assert MapSet.equal?(promised, sub.allowed)
    end

    test "the ack carries this subscription's id in _meta" do
      assert {:stream, %Subscription{} = sub, _} = open(%{"toolsListChanged" => true}, id: 42)
      assert sub.id == 42
      assert sub.ack["params"]["_meta"][Meta.subscription_id_key()] == 42
      assert sub.ack["method"] == Methods.subscriptions_acknowledged()
    end
  end

  # --- T-3 / T-4: the two stream MUST NOTs ---

  describe "T-3 MUST NOT send an unrequested notification type" do
    test "only the opted-in types are framed" do
      assert {:stream, sub, _} = open(%{"toolsListChanged" => true})

      assert {:ok, _} = Subscription.frame(sub, Methods.tools_list_changed(), %{})
      assert :drop == Subscription.frame(sub, Methods.prompts_list_changed(), %{})
      assert :drop == Subscription.frame(sub, Methods.resources_list_changed(), %{})
      assert :drop == Subscription.frame(sub, Methods.resources_updated(), %{"uri" => "mem://x"})
    end

    test "a resource URI outside the honoured list is dropped" do
      allowed = SubscribingHandler.allowed_uri_prefix() <> "a.txt"
      other = SubscribingHandler.allowed_uri_prefix() <> "b.txt"

      assert {:stream, sub, _} = open(%{"resourceSubscriptions" => [allowed]})

      assert {:ok, _} = Subscription.frame(sub, Methods.resources_updated(), %{"uri" => allowed})
      assert :drop == Subscription.frame(sub, Methods.resources_updated(), %{"uri" => other})
    end

    test "the URI filter reads either key style, so nothing is dropped for writing %{uri: ...}" do
      # Review F6: this filter used to read only the string key, so an
      # atom-keyed emission was dropped while the sink answered :ok — the one
      # notification type that was key-sensitive, in an SDK where every other
      # type is not. Both directions are asserted: an atom-keyed allowed URI is
      # framed, and an atom-keyed disallowed one is still dropped, so the fix
      # cannot have widened the filter into "atom keys bypass the check".
      allowed = SubscribingHandler.allowed_uri_prefix() <> "a.txt"
      other = SubscribingHandler.allowed_uri_prefix() <> "b.txt"

      assert {:stream, sub, _} = open(%{"resourceSubscriptions" => [allowed]})

      assert {:ok, wire} = Subscription.frame(sub, Methods.resources_updated(), %{uri: allowed})
      assert wire["params"]["uri"] == allowed
      assert :drop == Subscription.frame(sub, Methods.resources_updated(), %{uri: other})
    end
  end

  describe "T-4 MUST NOT send request-scoped notifications on the listen stream" do
    test "progress and message are refused by the same rule, on any filter" do
      # Not a separate check that could be forgotten: no SubscriptionFilter key
      # maps to either method, so neither can ever enter an honoured set.
      every_type = %{
        "toolsListChanged" => true,
        "promptsListChanged" => true,
        "resourcesListChanged" => true,
        "resourceSubscriptions" => [SubscribingHandler.allowed_uri_prefix() <> "a.txt"]
      }

      assert {:stream, sub, _} = open(every_type)

      assert :drop == Subscription.frame(sub, Methods.progress(), %{"progress" => 1})
      assert :drop == Subscription.frame(sub, Methods.logging_message(), %{"level" => "info"})
    end

    test "no filter key maps to a request-scoped method" do
      request_scoped = [Methods.progress(), Methods.logging_message()]
      mapped = Enum.map(Subscriptions.filter_keys(), &Subscriptions.method_for/1)

      assert Enum.all?(request_scoped, &(&1 not in mapped))
    end
  end

  # --- T-5: ack ⊆ advertised, and the JSON-mode refusal ---

  describe "T-5 the ack never claims more than server/discover advertised" do
    test "a type the server does not advertise is not honoured, even if the handler returns it" do
      # A config whose capabilities advertise tools only. The handler would
      # honour resourcesListChanged; the advertised-capability narrowing is what
      # stops the ack claiming it.
      base = config()

      tools_only = %{
        base.capabilities
        | resources: %MCP.Protocol.Capabilities.ResourceCapabilities{
            list_changed: nil,
            subscribe: nil
          }
      }

      narrowed = %{base | capabilities: tools_only}

      assert {:stream, sub, _} =
               Dispatch.dispatch(
                 listen_request(%{"toolsListChanged" => true, "resourcesListChanged" => true}),
                 ctx(),
                 narrowed
               )

      assert sub.honoured == %{"toolsListChanged" => true}
    end

    test "resourceSubscriptions is refused unless resources.subscribe is advertised" do
      base = config()

      no_subscribe = %{
        base
        | capabilities: %{
            base.capabilities
            | resources: %MCP.Protocol.Capabilities.ResourceCapabilities{
                list_changed: true,
                subscribe: nil
              }
          }
      }

      uri = SubscribingHandler.allowed_uri_prefix() <> "a.txt"

      assert {:stream, sub, _} =
               Dispatch.dispatch(
                 listen_request(%{"resourceSubscriptions" => [uri]}),
                 ctx(),
                 no_subscribe
               )

      refute Map.has_key?(sub.honoured, "resourceSubscriptions")
    end

    test "every honoured key is advertised, for the full filter" do
      every_type = %{
        "toolsListChanged" => true,
        "promptsListChanged" => true,
        "resourcesListChanged" => true,
        "resourceSubscriptions" => [SubscribingHandler.allowed_uri_prefix() <> "a.txt"]
      }

      config = config()
      assert {:stream, sub, _} = Dispatch.dispatch(listen_request(every_type), ctx(), config)

      advertised = Subscriptions.permitted_by(config.capabilities)

      for {key, _} <- sub.honoured do
        assert Map.has_key?(advertised, key), "ack claims #{key}, which is not advertised"
      end
    end
  end

  describe "T-5 JSON mode refuses the method outright" do
    test "a non-streaming driver gets -32601, never a silent black hole" do
      json_mode = config(streaming: false)

      assert {:reply, %{"error" => error}, _} =
               Dispatch.dispatch(listen_request(%{"toolsListChanged" => true}), ctx(), json_mode)

      assert error["code"] == -32_601
    end

    test "and that deployment advertises no subscription capability, so the refusal is honest" do
      json_mode = config(streaming: false)

      assert json_mode.capabilities.tools.list_changed == nil
      assert json_mode.capabilities.resources.list_changed == nil
      assert json_mode.capabilities.resources.subscribe == nil
      assert Subscriptions.permitted_by(json_mode.capabilities) == %{}
    end

    test "a handler with no handle_listen/3 also gets -32601" do
      {:ok, no_listen} = Config.build(MCP.Test.StatelessHandler, streaming: true)

      assert {:reply, %{"error" => %{"code" => -32_601}}, _} =
               Dispatch.dispatch(listen_request(%{"toolsListChanged" => true}), ctx(), no_listen)
    end
  end

  # --- T-6 / T-7: sink separation, in both directions ---

  describe "T-6 the two sinks cannot cross-contaminate" do
    test "a non-listen request's context has no stream sink at all" do
      # Not "has one that refuses" — has none. Dispatch strips it for every
      # method other than subscriptions/listen, so a tool handler has nothing
      # to emit through.
      request = %MCP.Protocol.Messages.Request{
        id: 1,
        method: "tools/call",
        params: %{
          "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
          "name" => "emit_request_scoped",
          "arguments" => %{}
        }
      }

      leaky_sink = fn method, params ->
        send(self(), {:leaked_to_stream, method, params})
        :ok
      end

      assert {:reply, response, _} =
               Dispatch.dispatch(request, ctx(stream_sink: leaky_sink), config())

      # The handler tried to emit onto a stream and was told there is no stream.
      assert [%{"text" => text}] = response["result"]["content"]
      assert text == inspect({:error, :no_stream})
      refute_received {:leaked_to_stream, _, _}
    end

    test "the stripping is per-method, not per-route — a notification is stripped too" do
      notification = %MCP.Protocol.Messages.Notification{
        method: "notifications/cancelled",
        params: %{}
      }

      leaky_sink = fn _m, _p -> send(self(), :leaked) end

      assert {:noreply, _} =
               Dispatch.dispatch(notification, ctx(stream_sink: leaky_sink), config())

      refute_received :leaked
    end

    test "the listen open callback DOES receive the stream sink" do
      sink = fn _m, _p -> :ok end
      assert {:stream, _sub, _} = open(%{"toolsListChanged" => true}, stream_sink: sink)
      assert_received {:listen_opened, "listen-1", _honoured, received_sink, "alice"}
      assert received_sink == sink
    end
  end

  describe "T-7 a listen stream cannot be drained-and-stopped by the request path" do
    # REMOVED in correction round 1 (review F4): "the listen path starts no
    # NotificationCollector, so there is nothing to drain". The claim was false
    # — the HTTP driver starts a collector for every POST, a listen included —
    # and the test could not fail: `refute is_pid(sub.honoured)` on a filter
    # map, `assert %Subscription{} = sub` after it had already matched, and an
    # `assert_raise FunctionClauseError` on `NotificationCollector.drain(sub.id)`
    # that asserted a fact about the collector's own guard, not about the listen
    # path. All three pass unchanged against an implementation that starts a
    # collector, which is the implementation.
    #
    # Its replacement asserts the property that IS true — the collector's
    # lifetime ends strictly before the stream's — where that property actually
    # lives, in the driver: `MCP.Transport.SubscriptionsStreamTest`, "the
    # collector is gone by the time the stream is live". Recorded here rather
    # than deleted silently, so the ledger shows a test moved and why.

    test "a stream sink is not a collector push — it never accumulates for a response" do
      collected = fn method, params -> send(self(), {:pushed, method, params}) end
      assert {:stream, _sub, _} = open(%{"toolsListChanged" => true}, stream_sink: collected)

      assert_received {:listen_opened, _, _, sink, _}
      sink.("notifications/tools/list_changed", %{})

      # It went straight out, rather than into anything a later drain could
      # sweep into some other request's response.
      assert_received {:pushed, "notifications/tools/list_changed", %{}}
    end
  end

  # --- Authorization at open time ---

  describe "open-time authorization via the honoured subset" do
    test "a URI this principal may not observe is absent from the ack" do
      allowed = SubscribingHandler.allowed_uri_prefix() <> "a.txt"

      assert {:stream, sub, _} =
               open(%{"resourceSubscriptions" => [allowed]}, identity: "restricted")

      refute Map.has_key?(sub.honoured, "resourceSubscriptions")
      assert sub.ack["params"]["notifications"] == %{}
    end

    test "the same request from a permitted principal is honoured" do
      allowed = SubscribingHandler.allowed_uri_prefix() <> "a.txt"

      assert {:stream, sub, _} = open(%{"resourceSubscriptions" => [allowed]}, identity: "alice")
      assert sub.honoured["resourceSubscriptions"] == [allowed]
    end

    test "a handler may refuse the subscription outright" do
      # `{:listen_refused, ...}`, NOT `{:reply, ...}`: the response is an
      # ordinary error, but the handler ran and holds a live sink, so the driver
      # owes it a teardown. A `{:reply, ...}` here would be indistinguishable
      # from the two refusals that never reach the handler (review F1).
      assert {:listen_refused, %{"error" => error}, _} =
               open(%{"toolsListChanged" => true}, identity: "denied")

      assert error["code"] == -32_603
    end

    test "the two refusals that never reach the handler stay {:reply, ...}" do
      # A malformed filter, and a deployment that cannot stream. Neither ran
      # `handle_listen/3`, so neither handler is holding a sink and neither is
      # owed a teardown — telling it a subscription closed would be a claim
      # about something that never opened.
      assert {:reply, %{"error" => %{"code" => -32_602}}, _} = open(:omitted)

      assert {:reply, %{"error" => %{"code" => -32_601}}, _} =
               Dispatch.dispatch(
                 listen_request(%{"toolsListChanged" => true}),
                 ctx(),
                 config(streaming: false)
               )
    end

    test "identity reaches handle_listen/3 from the context, never from params" do
      params_spoof = %{"toolsListChanged" => true, "identity" => "mallory"}
      assert {:stream, _, _} = open(params_spoof, identity: "alice")
      assert_received {:listen_opened, _, _, _, "alice"}
    end
  end

  # --- T-11 (driver opt-in half; the per-driver clause is covered elsewhere) ---

  describe "T-11 a driver that does not opt in can never receive {:stream, ...}" do
    test "streaming: false yields only the two original shapes" do
      json_mode = config(streaming: false)

      for method <- ["subscriptions/listen", "tools/list", "resources/list"] do
        request = %MCP.Protocol.Messages.Request{
          id: 1,
          method: method,
          params: %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version},
            "notifications" => %{"toolsListChanged" => true}
          }
        }

        assert {:reply, _, _} = Dispatch.dispatch(request, ctx(), json_mode)
      end
    end

    test "MCP.Server.Connection declares streaming: false" do
      # The stdio/in-process driver's opt-out, asserted rather than assumed:
      # this is what makes its {:stream, ...} clause unreachable rather than
      # merely unlikely. MES-29 flips it.
      {:ok, pid} =
        MCP.Server.Connection.start_link(
          transport: {MCP.Test.MockTransport, []},
          handler: {SubscribingHandler, [owner: self()]}
        )

      state = :sys.get_state(pid)
      assert state.config.streaming == false
      assert Subscriptions.permitted_by(state.config.capabilities) == %{}

      MCP.Server.Connection.close(pid)
    end
  end
end
