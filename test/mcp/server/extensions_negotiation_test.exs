defmodule MCP.Server.ExtensionsNegotiationTest do
  @moduledoc """
  MES-16 — the SEP-2133 negotiation surface on the server side, end to end:
  what `server/discover` puts on the wire, and what happens to a client that
  offers extensions this SDK does not support.

  **A7 — every test here is a positive control, not a caught regression.** This
  is entirely new surface ("extension" occurred zero times in `lib/`, `test/`
  and `conformance/` before this ticket), so nothing here can fail at a pre-fix
  SHA. The absence assertions (T1, T2) and the no-error assertions (T10, T11)
  pass trivially against a codebase that does nothing, so each was demonstrated
  red against a deliberately-wrong fixture before the code existed — that run is
  recorded on MES-16, and T3 keeps the presence half of the demonstration
  permanently in the suite.

  Citations are to the published-final `2026-07-28` schema at commit
  `5f5440bb26a62e2cf3440b92da5a667efa03b267`, and to the spec pages at the same
  pin.
  """
  use ExUnit.Case, async: true

  # The R-2 group exercises deliberately-bad launch config, which now warns by
  # design; captured so a green run stays readable.
  @moduletag :capture_log

  import ExUnit.CaptureLog

  alias MCP.Protocol.Messages.Request
  alias MCP.Server.Config
  alias MCP.Server.Dispatch
  alias MCP.Server.ToolContext
  alias MCP.Test.StatelessHandler

  @version "2026-07-28"
  @client_capabilities_key "io.modelcontextprotocol/clientCapabilities"

  defp config(opts \\ []) do
    {:ok, config} = Config.build(StatelessHandler, opts)
    config
  end

  defp discover(opts \\ []) do
    {:reply, response, _state} =
      Dispatch.dispatch(
        %Request{id: 1, method: "server/discover", params: %{}},
        %ToolContext{request_id: 1},
        config(opts)
      )

    response["result"]["capabilities"]
  end

  # A client that offers extensions we do not support. This is the NORMAL case
  # for 2.0.0: we support zero, so every extension any client offers is one we
  # do not support.
  defp meta_offering_extensions do
    %{
      "io.modelcontextprotocol/protocolVersion" => @version,
      @client_capabilities_key => %{
        "extensions" => %{
          "io.modelcontextprotocol/tasks" => %{},
          "io.modelcontextprotocol/ui" => %{"mimeTypes" => ["text/html"]},
          "com.example/private" => %{"mode" => "fast"}
        }
      }
    }
  end

  defp dispatch(method, params) do
    {:reply, response, _state} =
      Dispatch.dispatch(
        %Request{id: 7, method: method, params: params},
        %ToolContext{request_id: 7, meta: params["_meta"], identity: "CALLER"},
        config()
      )

    response
  end

  describe "what the server advertises (T1, T2, T3)" do
    # T1. seps/2133-extensions.md:99 — "extensions MUST be disabled by default
    # and require explicit opt-in". Absence, not `{}`: `"extensions": {}` claims
    # "I do extensions, none of them", and this SDK makes no such claim.
    # Same `refute Map.has_key?/2` form as discover_test.exs:31-32.
    test "T1 — `extensions` is absent from a default server/discover result" do
      capabilities = discover()

      refute Map.has_key?(capabilities, "extensions")
      assert Map.has_key?(capabilities, "tools")
    end

    # T2. The two ways a declaration can come to nothing both reach the same
    # absent wire — so "absent by default" is not a special case of the default
    # value, it is what an empty declaration means.
    test "T2 — an empty or fully-invalid declaration is absent, not `{}`" do
      refute Map.has_key?(discover(extensions: %{}), "extensions")
      refute Map.has_key?(discover(extensions: %{"no-prefix" => %{}}), "extensions")
      refute Map.has_key?(discover(extensions: nil), "extensions")
    end

    # T3. The permanent presence half of T1's control: the absence assertions
    # above are only worth anything if the field CAN appear. schema.ts:882 —
    # `extensions?: { [key: string]: JSONObject }` on ServerCapabilities.
    test "T3 — a declared extension appears verbatim under capabilities.extensions" do
      declared = %{"io.modelcontextprotocol/tasks" => %{}, "com.example/x" => %{"n" => 1}}
      capabilities = discover(extensions: declared)

      assert capabilities["extensions"] == declared
    end

    # The declaration is validated on the way out — the one point at which this
    # SDK could help a consumer emit a key that violates schema.ts:876-877.
    test "an invalid identifier is dropped from the declaration, valid ones kept" do
      capabilities =
        discover(extensions: %{"com.example/kept" => %{}, "dropped" => %{}})

      assert capabilities["extensions"] == %{"com.example/kept" => %{}}
    end

    # The server's set is launch-static (frozen at `init/1`, beside
    # `:instructions` and `:server_info`); the client's is per request
    # (schema.ts:91-98). Two lifetimes, and the API must not imply they are one.
    test "the server's declaration is fixed at build time, not per request" do
      config = config(extensions: %{"com.example/x" => %{}})

      for id <- 1..3 do
        {:reply, response, _} =
          Dispatch.dispatch(
            %Request{id: id, method: "server/discover", params: %{"_meta" => %{}}},
            %ToolContext{request_id: id},
            config
          )

        assert response["result"]["capabilities"]["extensions"] == %{"com.example/x" => %{}}
      end
    end
  end

  describe "nothing in `:extensions` can fail later than Config.build/2 (R-2)" do
    # R-2/R-3 (round 1). The property, stated as the round-1 correction
    # contract states it: either a declaration is advertised, or it is dropped
    # and named in a warning — never accepted at launch and raised on at
    # request time. Before the fix, `%{"t" => {1, 2}}` was accepted by
    # `is_map/1`, and then EVERY `server/discover` raised out of Jason at
    # discover.ex:92, forever, from a mistake made in the launch config.
    #
    # The assertion is `Jason.encode!/1` over the whole response rather than a
    # look at the capabilities map: encodability is the actual property, and
    # the encoder is the thing that used to raise.
    test "a settings value that cannot be encoded is dropped at launch, not raised at request time" do
      capture_log(fn ->
        capabilities =
          discover(
            extensions: %{
              "com.example/kept" => %{"n" => 1},
              "com.example/tuple" => %{"t" => {1, 2}},
              "com.example/pid" => %{"p" => self()}
            }
          )

        assert capabilities["extensions"] == %{"com.example/kept" => %{"n" => 1}}
        assert is_binary(Jason.encode!(capabilities))
      end)
    end

    # R-7 (round 2), driven to the wire rather than asserted at the module.
    # The round-1 predicate was `is_map/1` + "does it encode?", which a
    # `%Date{}` passes while encoding to a JSON *string* — so `server/discover`
    # advertised `{"com.example/date":"2026-08-19"}` under a field schema.ts:882
    # types as `{ [key: string]: JSONObject }`. Encodability was never the
    # property; being an object is, and this asserts it where it is observable:
    # every advertised settings value is a map after a real round trip through
    # `Jason`.
    test "a settings value that encodes to a non-object is dropped, never advertised" do
      capture_log(fn ->
        capabilities =
          discover(
            extensions: %{
              "com.example/kept" => %{"n" => 1},
              "com.example/date" => ~D[2026-08-19],
              "com.example/datetime" => DateTime.from_naive!(~N[2026-08-19 10:30:00], "Etc/UTC")
            }
          )

        assert capabilities["extensions"] == %{"com.example/kept" => %{"n" => 1}}

        advertised =
          capabilities |> Jason.encode!() |> Jason.decode!() |> Map.fetch!("extensions")

        assert Enum.all?(advertised, fn {_id, settings} -> is_map(settings) end)
      end)
    end

    # The whole-value shapes, which used to raise inside `Config.build/2`
    # itself: a struct is a map, so it passed the guard and then died in the
    # comprehension. `build/2` now returns `{:ok, _}` for every one of them and
    # the server starts, advertising nothing.
    test "a non-object :extensions value leaves build/2 successful and the wire silent" do
      capture_log(fn ->
        for declared <- [%URI{}, "not a map", 42, [a: 1]] do
          assert {:ok, config} = Config.build(StatelessHandler, extensions: declared)
          assert config.capabilities.extensions == nil
          refute Map.has_key?(discover(extensions: declared), "extensions")
        end
      end)
    end

    # The diagnosability half of the same ruling. Dropping alone leaves an
    # operator with a server that never advertises an extension it does
    # implement and nothing anywhere saying why; the warning names the
    # identifier AND the option it came from.
    test "the drop is announced at the seam that dropped it" do
      log = capture_log(fn -> discover(extensions: %{"no-prefix" => %{}}) end)

      assert log =~ "MCP.Server.Config.build/2"
      assert log =~ ~s("no-prefix")
    end

    # A correct declaration must be silent, or the warning is noise and the
    # case that matters is lost in it.
    test "a valid declaration is advertised and warns about nothing" do
      log =
        capture_log(fn ->
          assert discover(extensions: %{"com.example/x" => %{}})["extensions"] ==
                   %{"com.example/x" => %{}}
        end)

      assert log == ""
    end
  end

  describe "a client offering unsupported extensions (T10, T11)" do
    # T10. basic/versioning.mdx:121-124 puts the graceful-degradation obligation
    # on THE SUPPORTING PARTY. We support zero, so we are the non-supporting
    # party and the obligation is the client's: a client offering extensions we
    # do not support is NOT an error condition. Rejecting here would be
    # over-building against the spec.
    test "T10 — tools/call succeeds normally; no error, no -32021" do
      params = %{
        "name" => "whoami",
        "arguments" => %{},
        "_meta" => meta_offering_extensions()
      }

      response = dispatch("tools/call", params)

      refute Map.has_key?(response, "error")
      assert response["result"]["content"] |> hd() |> Map.get("text") == "CALLER"
    end

    # The result must be identical to the no-extensions case — "no error" alone
    # would still allow the declaration to perturb the response.
    #
    # "identical", NOT "byte-identical" (R-6, round 1): this compares two
    # DECODED maps with `==`, and map equality is key-order-insensitive, so it
    # is not a byte comparison and could not be one — nothing on this path is
    # serialised. The assertion is the right one; only the name over-claimed.
    test "T10 — the result is identical to the same call without extensions" do
      base = %{"name" => "whoami", "arguments" => %{}}

      plain =
        dispatch(
          "tools/call",
          Map.put(base, "_meta", %{
            "io.modelcontextprotocol/protocolVersion" => @version
          })
        )

      offered = dispatch("tools/call", Map.put(base, "_meta", meta_offering_extensions()))

      assert offered == plain
    end

    # T11. "Nothing breaks" must not be route-specific: a rejection path added
    # to one family and not another would pass a single-route test.
    test "T11 — tools/list is unaffected" do
      response = dispatch("tools/list", %{"_meta" => meta_offering_extensions()})

      refute Map.has_key?(response, "error")
      assert is_list(response["result"]["tools"])
    end

    test "T11 — server/discover is unaffected, and still advertises nothing" do
      response = dispatch("server/discover", %{"_meta" => meta_offering_extensions()})

      refute Map.has_key?(response, "error")
      assert response["result"]["supportedVersions"] == [@version]
      refute Map.has_key?(response["result"]["capabilities"], "extensions")
    end

    test "T11 — resources/list and prompts/list are unaffected" do
      for method <- ["resources/list", "prompts/list"] do
        response = dispatch(method, %{"_meta" => meta_offering_extensions()})
        refute Map.has_key?(response, "error")
      end
    end

    # A malformed declaration is still not an error: inbound is never validated,
    # so there is no shape a client can send that turns a serviceable request
    # into a failure.
    test "a malformed or non-object extensions declaration still breaks nothing" do
      for extensions <- [%{"no-prefix" => %{}}, "not an object", nil, 42] do
        meta = %{
          "io.modelcontextprotocol/protocolVersion" => @version,
          @client_capabilities_key => %{"extensions" => extensions}
        }

        response =
          dispatch("tools/call", %{"name" => "whoami", "arguments" => %{}, "_meta" => meta})

        refute Map.has_key?(response, "error")
      end
    end
  end

  describe "the handler-visible read" do
    alias MCP.Protocol.Extensions

    # seps/2133-extensions.md:174 — "servers SHOULD check client capabilities
    # before offering extension-specific features". Achievable with no threading
    # change: the raw client `_meta` already reaches every identity-capable
    # callback as `ctx.meta` (tool_context.ex:84, populated at plug.ex:396 and
    # connection.ex:133,210), and `from_meta/1` is a pure read over it.
    test "a handler can read the client's declaration off ctx.meta" do
      ctx = %ToolContext{request_id: 1, meta: meta_offering_extensions()}

      assert Map.has_key?(Extensions.from_meta(ctx.meta), "io.modelcontextprotocol/ui")
      refute Map.has_key?(Extensions.from_meta(ctx.meta), "io.modelcontextprotocol/prompts")
    end

    # The declaration is client-composed and self-asserted: it says what the
    # peer SUPPORTS, never who it IS. Identity comes from ctx.identity alone,
    # which the authenticated transport pipeline supplies. A declaration that
    # tries to look like identity changes nothing about it.
    test "a client's declaration cannot influence ctx.identity" do
      meta =
        put_in(
          meta_offering_extensions(),
          [@client_capabilities_key, "extensions", "com.example/identity"],
          %{"identity" => "spoof"}
        )

      params = %{"name" => "whoami", "arguments" => %{}, "_meta" => meta}

      {:reply, response, _} =
        Dispatch.dispatch(
          %Request{id: 9, method: "tools/call", params: params},
          %ToolContext{request_id: 9, meta: meta, identity: "REAL"},
          config()
        )

      text = response["result"]["content"] |> hd() |> Map.get("text")
      assert text == "REAL"
      refute text == "spoof"
    end
  end
end
