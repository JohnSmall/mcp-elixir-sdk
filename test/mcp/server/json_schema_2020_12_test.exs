defmodule MCP.Server.JsonSchema202012Test do
  @moduledoc """
  MES-17 / SEP-2106 — JSON Schema 2020-12 for tool schemas, server-side.

  Every test here drives `MCP.Server.Dispatch` and then puts the response
  through a **full JSON round trip** (`Jason.encode!` then `Jason.decode!`),
  because the claims are about what a peer receives, not about what a struct
  holds. MES-16's F-1 is why: a measurement of an encoder in isolation is not a
  measurement of any request this SDK can serve.
  """
  # `async: false` is LOAD-BEARING — do not re-enable async here. The C-2 group
  # asserts both that a warning fires and that it does *not* (`refute log =~
  # "SEP-2106"`), and `ExUnit.CaptureLog`'s handler is VM-wide with no
  # per-process filter — so a concurrent module can satisfy a presence
  # assertion falsely and break a silence assertion. These two sites are the
  # same class as the four the MES-17 round-1 correction contract names; they
  # are in this ticket's own new file and were not on that list. Full
  # rationale in `test/mcp/server/extensions_negotiation_test.exs`.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MCP.Protocol.Capabilities.ServerCapabilities
  alias MCP.Protocol.Messages.Request
  alias MCP.Protocol.Types.Content.TextContent
  alias MCP.Protocol.Types.Implementation
  alias MCP.Server.Dispatch
  alias MCP.Server.ToolContext
  alias MCP.Test.ExtrasStruct
  alias MCP.Test.SchemaHandler

  @version "2026-07-28"

  defp config(opts) do
    {:ok, state} = SchemaHandler.init(opts)

    %{
      handler_module: SchemaHandler,
      handler_state: state,
      server_info: %Implementation{name: "mcp_elixir_sdk", version: "2.0.0"},
      capabilities: %ServerCapabilities{},
      instructions: nil
    }
  end

  defp meta, do: %{"io.modelcontextprotocol/protocolVersion" => @version}

  # Dispatch, then serialise and re-parse: the assertion is about the wire.
  defp round_trip(method, params, opts \\ []) do
    req = %Request{id: 1, method: method, params: Map.put(params, "_meta", meta())}
    {:reply, resp, _state} = Dispatch.dispatch(req, %ToolContext{request_id: 1}, config(opts))
    resp |> Jason.encode!() |> Jason.decode!()
  end

  defp list_tools(opts) do
    round_trip("tools/list", %{}, opts)["result"]["tools"]
  end

  defp tool(name, opts \\ []) do
    opts |> list_tools() |> Enum.find(&(&1["name"] == name))
  end

  defp call(name, args) do
    round_trip("tools/call", %{"name" => name, "arguments" => args})["result"]
  end

  # --- W-3: keyword preservation, checked at the width of the claim ---
  #
  # The claim is "any JSON Schema 2020-12 keyword survives to the peer". A
  # single `assert schema == fixture` would be the same width, but says nothing
  # about *which* keyword was lost when it fails, so each of the twelve
  # keywords the alpha harness names is asserted by name as well.

  describe "W-3 — 2020-12 keyword preservation through a real tools/list" do
    setup do
      %{schema: tool("json_schema_2020_12_tool")["inputSchema"]}
    end

    # "arrives intact", NOT "byte-identical" (R-5): this compares two DECODED
    # maps, and map equality is key-order-insensitive. The assertion is the
    # right one and a byte comparison would be the WRONG one — JSON key order
    # is not semantic and number formatting is an encoder detail, so a byte
    # check would fail on changes that lose nothing while catching nothing a
    # map comparison misses. Only the name over-claimed. Same slip as MES-16's
    # R-6, which is why the reason is written down rather than just fixed.
    test "the whole fixture arrives intact — decoded-map equality, not bytes", %{schema: schema} do
      assert schema == SchemaHandler.fixture_schema()
    end

    test "reference keywords survive: $schema, $defs, $anchor, $ref", %{schema: schema} do
      assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
      assert schema["$defs"]["address"]["type"] == "object"
      assert schema["$defs"]["address"]["$anchor"] == "addressDef"
      assert schema["properties"]["address"]["$ref"] == "#/$defs/address"
    end

    test "composition keywords survive: allOf, anyOf", %{schema: schema} do
      assert [%{"anyOf" => any_of}] = schema["allOf"]
      assert any_of == [%{"required" => ["phone"]}, %{"required" => ["email"]}]
    end

    test "conditional keywords survive: if, then, else", %{schema: schema} do
      assert schema["if"]["required"] == ["contactMethod"]
      assert schema["then"] == %{"required" => ["phone"]}
      assert schema["else"] == %{"required" => ["email"]}
    end

    test "validation keywords survive: enum, const, additionalProperties", %{schema: schema} do
      assert schema["properties"]["contactMethod"]["enum"] == ["phone", "email"]
      assert schema["if"]["properties"]["contactMethod"]["const"] == "phone"
      assert schema["additionalProperties"] == false
    end

    test "an explicit non-default dialect is carried, not coerced or refused" do
      # schema.ts:1962-1963 — "With explicit draft-07 input schema". This SDK
      # implements no dialect, so it neither honours nor refuses one.
      assert tool("draft_07_tool")["inputSchema"]["$schema"] ==
               "http://json-schema.org/draft-07/schema#"
    end
  end

  # --- W-5: a boolean `outputSchema` survives the encoder as `false`, not as an
  # absence. This measures THIS SDK's pass-through and the `Types.Tool` encoder's
  # nil-versus-false handling — the same defect shape as D-1 on the other field.
  #
  # NOT CONFORMANCE EVIDENCE, and MES-19 must not cite it as such (R-7).
  # `schema.ts:2005` types `outputSchema` as an object (`{ $schema?: string;
  # [key: string]: unknown }`), to which `false` is not assignable, and its doc
  # opens "An optional JSON Schema **object**" (`:2000`). Generic 2020-12 admits
  # boolean schemas; MCP does not admit one in this field. What this test pins
  # is that the SDK does not silently drop a value a consumer put there — a
  # `false` that vanished would be indistinguishable from an absent field.

  test "W-5 — a boolean outputSchema reaches the wire as false, not as an absence" do
    tool = tool("boolean_output_tool")
    assert Map.has_key?(tool, "outputSchema")
    assert tool["outputSchema"] == false
  end

  # --- W-4: the $ref MUST NOT, checked against a live canary ---

  test "W-4 — no $ref is ever dereferenced: a canary listener is never connected to" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    url = "http://127.0.0.1:#{port}/schema.json"

    # Drive both directions: listing a tool whose inputSchema $refs the canary,
    # and calling THAT tool with arguments.
    #
    # Round 1 called `"echo_args"` here — a tool that is not advertised and
    # whose schema contains no `$ref` — so the `tools/call` half of the canary
    # controlled nothing: the reviewer added a resolver on the call path and
    # the test stayed green. It is `"network_ref_tool"`, and the mutation has
    # now been run against the corrected test (it goes red). One string, and
    # it is this ticket's own rule landing on it: a stated discriminating
    # mutation is not evidence until it has been run.
    assert tool("network_ref_tool", ref_url: url)["inputSchema"]["properties"]["payload"] ==
             %{"$ref" => url}

    req = %Request{
      id: 1,
      method: "tools/call",
      params: %{
        "name" => "network_ref_tool",
        "arguments" => %{"payload" => %{"any" => "thing"}},
        "_meta" => meta()
      }
    }

    {:reply, resp, _state} =
      Dispatch.dispatch(req, %ToolContext{request_id: 1}, config(ref_url: url))

    # The call must SUCCEED, or the canary measures a short-circuit rather than
    # a non-dereference: an error return before the handler runs would let a
    # resolver on a later line pass unnoticed.
    refute Map.has_key?(resp, "error")
    assert resp["result"]["content"] != []

    # SEP-2106 Security Implications, and `basic/index.mdx:301-302` at the same
    # pin: a `$ref` that resolves to a network URI MUST NOT be dereferenced.
    assert {:error, :timeout} = :gen_tcp.accept(listen, 200)
    :gen_tcp.close(listen)
  end

  # --- W-1 / D-2: structuredContent is any JSON value ---

  describe "W-1 — a handler can emit structuredContent, and it may be any JSON value" do
    for {label, value} <- [
          {"false", false},
          {"true", true},
          {"zero", 0},
          {"float", 1.5},
          {"empty string", ""},
          {"string", "str"},
          {"empty array", []},
          {"array", [1, 2]},
          {"empty object", %{}},
          {"object", %{"a" => 1}},
          {"null", nil}
        ] do
      test "#{label} survives to the wire", _ctx do
        value = unquote(Macro.escape(value))
        # A TextContent block carrying the serialized JSON, so the array and
        # primitive cases satisfy SEP-2106's backward-compatibility MUST and
        # this test measures emission only.
        content = [%{"type" => "text", "text" => Jason.encode!(value)}]
        result = call("structured", %{"structured" => value, "content" => content})

        assert Map.has_key?(result, "structuredContent")
        assert result["structuredContent"] == value
      end
    end

    test "an absent key omits the field entirely — absent is not null" do
      result = call("structured", %{"content" => []})
      refute Map.has_key?(result, "structuredContent")
    end

    test "a present nil key emits JSON null — null is not absent" do
      result = call("structured", %{"structured" => nil, "content" => []})
      assert Map.has_key?(result, "structuredContent")
      assert result["structuredContent"] == nil
    end

    test "the extras map also carries isError, and false does not become absent" do
      assert call("structured", %{"isError" => true, "content" => []})["isError"] == true
      refute Map.has_key?(call("structured", %{"isError" => false, "content" => []}), "isError")
    end

    test "the pre-SEP-2106 return shapes still work unchanged" do
      assert call("plain", %{})["content"] == [%{"type" => "text", "text" => "ok"}]
      refute Map.has_key?(call("plain", %{}), "structuredContent")
      assert call("plain_error", %{})["isError"] == true
    end
  end

  # --- C-2: the TextContent backwards-compatibility fallback ---

  describe "C-2 — SEP-2106's TextContent fallback is noticed, not injected" do
    test "array structured content with no serialized-JSON text block warns" do
      log = capture_log(fn -> call("structured", %{"structured" => [1, 2], "content" => []}) end)
      assert log =~ "[warning]"
      assert log =~ "structuredContent"
    end

    test "the warning names the tool and cites the MUST" do
      log = capture_log(fn -> call("structured", %{"structured" => 42, "content" => []}) end)
      assert log =~ ~s("structured")
      assert log =~ "SEP-2106"
      assert log =~ "MUST"
    end

    test "a prose text block does not satisfy the MUST — the check is exact, not a proxy" do
      content = [%{"type" => "text", "text" => "Found 2 users: Alice and Bob."}]

      log =
        capture_log(fn -> call("structured", %{"structured" => [1, 2], "content" => content}) end)

      assert log =~ "SEP-2106"
    end

    test "a text block carrying the serialized JSON is silent" do
      content = [%{"type" => "text", "text" => "[1,2]"}]

      log =
        capture_log(fn -> call("structured", %{"structured" => [1, 2], "content" => content}) end)

      refute log =~ "SEP-2106"
    end

    test "object structured content is outside the MUST and never warns" do
      log =
        capture_log(fn -> call("structured", %{"structured" => %{"a" => 1}, "content" => []}) end)

      refute log =~ "SEP-2106"
    end

    @tag capture_log: true
    test "the content list is never modified — the SDK notices, it does not inject" do
      result = call("structured", %{"structured" => [1, 2], "content" => []})
      assert result["content"] == []
      assert result["structuredContent"] == [1, 2]
    end
  end

  # --- R-3: the extras map is dropped AND named, never silently, never raised ---
  #
  # MES-16 settled this posture on `:extensions` — an unhonourable declaration
  # is dropped *and named*, so a consumer's typo is never a silent nothing.
  # The extras map is a new consumer-supplied surface and follows it. Each of
  # the four shapes below produced a successful, silently empty result at
  # `e9806c4`: no error, no warning, and no dialyzer complaint (the type is
  # all-`optional()`, so a misspelled key is not a mismatch).

  describe "R-3 — an unusable extras map is named in a warning, and never raises" do
    test "a camelCase key is named, and the call still succeeds" do
      {result, log} =
        with_log(fn -> call("raw_extras", %{"extras" => %{structuredContent: 1}}) end)

      assert log =~ "unrecognised key(s) IGNORED"
      assert log =~ ":structuredContent"
      assert log =~ ~s("raw_extras")
      refute Map.has_key?(result, "structuredContent")
      assert result["content"] == []
    end

    test "a string key is named" do
      {_result, log} =
        with_log(fn -> call("raw_extras", %{"extras" => %{"structured_content" => 1}}) end)

      assert log =~ "unrecognised key(s) IGNORED"
      assert log =~ ~s("structured_content")
    end

    test "a struct in slot 3 is named by its module, and nothing is raised" do
      {result, log} = with_log(fn -> call("raw_extras", %{"extras" => %URI{}}) end)

      assert log =~ "URI"
      assert log =~ "struct in slot 3"
      # `%URI{}` has neither field, so nothing IS read off it — and the line
      # says that, rather than the universal claim it used to make (F-9).
      assert log =~ "has none of"
      assert log =~ "every field is IGNORED"
      refute Map.has_key?(result, "structuredContent")
      assert result["resultType"] == "complete"
    end

    test "a non-boolean :is_error is named, and no isError reaches the wire" do
      {result, log} = with_log(fn -> call("raw_extras", %{"extras" => %{is_error: "true"}}) end)

      assert log =~ "`:is_error` is not a boolean"
      refute Map.has_key?(result, "isError")
    end

    # The discriminating control. A warning that also fires on a correct extras
    # map is noise, and then the case that matters is lost in it — which is the
    # same argument C-2's exactness rests on. `%{}` in particular MUST be
    # silent: it is what a handler that adds keys conditionally returns when
    # neither applies, and `SchemaHandler` itself does exactly that.
    test "a correct extras map, and an empty one, warn about nothing" do
      for extras <- [
            %{},
            %{structured_content: %{"a" => 1}},
            %{is_error: true},
            %{is_error: false},
            %{structured_content: %{"a" => 1}, is_error: true}
          ] do
        {_result, log} = with_log(fn -> call("raw_extras", %{"extras" => extras}) end)
        assert log == "", "expected silence for #{inspect(extras)}, got: #{log}"
      end
    end
  end

  # --- F-9 / F-10 / F-11: round 2. Each is a claim made wider than its check,
  # or a check narrower than the shapes that reach it. The R-3 group above is
  # the same posture; these are the cases it did not reach.

  describe "F-9 — the struct warning describes what the code did, not the opposite" do
    # The discriminating case. R-3's struct test used `%URI{}`, which carries
    # neither field, so the old sentence ("structuredContent and isError are
    # IGNORED") happened to read true and could not be falsified there. A
    # struct IS a map: dispatch reads both fields off it and both reach the
    # wire, and at `209999e` the log asserted the exact opposite while doing so.
    test "a struct that DOES carry the fields has them read, and the warning says so" do
      extras = %ExtrasStruct{structured_content: [1, 2], is_error: true}
      {result, log} = with_log(fn -> call("raw_extras", %{"extras" => extras}) end)

      # The behaviour is the good one and is deliberately unchanged.
      assert result["structuredContent"] == [1, 2]
      assert result["isError"] == true

      # The sentence is what was wrong. It must name what could not be used.
      refute log =~ "structuredContent and isError are IGNORED"
      assert log =~ "MCP.Test.ExtrasStruct"
      assert log =~ "struct in slot 3"
      assert log =~ "ARE read"
      assert log =~ ":structured_content"
      assert log =~ ":is_error"
      assert log =~ "every OTHER field is IGNORED"
    end

    test "a struct carrying one of the two fields names that one, and only that one" do
      extras = %ExtrasStruct{structured_content: nil, is_error: true}
      {result, log} = with_log(fn -> call("raw_extras", %{"extras" => extras}) end)

      # `:structured_content` is a FIELD of this struct even when its value is
      # nil, so presence-keying puts an explicit JSON null on the wire — the
      # same absent-vs-null rule a plain map gets, which is exactly what "read
      # exactly as a plain extras map's would be" has to mean to be true.
      assert Map.has_key?(result, "structuredContent")
      assert result["structuredContent"] == nil
      assert result["isError"] == true
      assert log =~ "ARE read"
    end
  end

  describe "F-10 — a slot 3 that is neither a map nor a boolean is dropped AND named" do
    # S4 ruled "dropped and named" over five plausible mistakes; four were
    # covered. The dispatch clause is guarded `when is_map(extras)`, so these
    # fall through to the legacy boolean clause and are dropped by
    # `maybe_error/2` without `warn_unusable_extras/2` ever running. At
    # `209999e` every one of them logged the empty string. A keyword list is
    # the shape that matters: it is the idiomatic Elixir spelling of an options
    # map, and newly plausible precisely because this ticket made slot 3 a map.
    test "a keyword list, an empty list, an atom and a string are each named" do
      for extras <- [[structured_content: %{"a" => 1}], [], :structured_content, "true"] do
        {result, log} = with_log(fn -> call("raw_extras", %{"extras" => extras}) end)

        assert log =~ "in slot 3", "expected a warning for #{inspect(extras)}, got: #{log}"
        assert log =~ "IGNORED in full"
        assert log =~ ~s("raw_extras")

        # The drop itself is inherited behaviour and must not have changed.
        refute Map.has_key?(result, "structuredContent")
        refute Map.has_key?(result, "isError")
        assert result["content"] == []
        assert result["resultType"] == "complete"
      end
    end

    # The control that keeps the new clause from swallowing the legacy shape:
    # `boolean()` was slot 3's only meaning before SEP-2106 and stays silent.
    test "the legacy boolean slot 3 still works, in both directions, and warns about nothing" do
      {errored, error_log} = with_log(fn -> call("raw_extras", %{"extras" => true}) end)
      {plain, plain_log} = with_log(fn -> call("raw_extras", %{"extras" => false}) end)

      assert errored["isError"] == true
      assert error_log == ""
      refute Map.has_key?(plain, "isError")
      assert plain_log == ""
    end
  end

  describe "F-11 — the unrecognised-key list is capped, and says how many it elided" do
    # The count is unbounded, Logger truncates at ~8 KB, and at `209999e` 5000
    # keys cost 7.567 ms/call building a string Logger provably discarded. A
    # cap alone would be the silent-drop class again, so the elided count is in
    # the line.
    test "more than ten keys are truncated, and the line says how many are missing" do
      extras = Map.new(1..25, &{:"unrecognised_key_#{&1}", 1})
      {_result, log} = with_log(fn -> call("raw_extras", %{"extras" => extras}) end)

      assert log =~ "25 unrecognised key(s) IGNORED"
      assert log =~ "and 15 more"

      # Sorted, the first ten are _1, _10..._18; _19 is the first elided one.
      assert log =~ ":unrecognised_key_10"
      refute log =~ ":unrecognised_key_19"
    end

    test "ten or fewer are listed in full, with no elision claimed" do
      extras = Map.new(1..10, &{:"unrecognised_key_#{&1}", 1})
      {_result, log} = with_log(fn -> call("raw_extras", %{"extras" => extras}) end)

      assert log =~ "10 unrecognised key(s) IGNORED"
      refute log =~ "more"

      for n <- 1..10, do: assert(log =~ ":unrecognised_key_#{n}")
    end
  end

  # --- R-8: "never on a compliant result" is only true if the match is as wide
  # as the wire. `dispatch.ex` matched string-keyed content maps only, so a
  # handler returning a `%TextContent{}` — public, `Jason.Encoder`-derived,
  # encoding to exactly the right JSON — was warned at while being compliant.

  describe "R-8 — the fallback check recognises every spelling of a text block" do
    test "a %TextContent{} struct carrying the serialized JSON is silent" do
      content = [%TextContent{text: "[1,2]"}]

      log =
        capture_log(fn -> call("structured", %{"structured" => [1, 2], "content" => content}) end)

      refute log =~ "SEP-2106"
    end

    test "an atom-keyed content map carrying the serialized JSON is silent" do
      content = [%{type: "text", text: "[1,2]"}]

      log =
        capture_log(fn -> call("structured", %{"structured" => [1, 2], "content" => content}) end)

      refute log =~ "SEP-2106"
    end

    # The other direction, so "recognises the struct" cannot pass by
    # recognising every struct: a struct whose text is prose is still not the
    # serialized JSON.
    test "a %TextContent{} carrying prose is still not compliance" do
      content = [%TextContent{text: "Found 2 users: Alice and Bob."}]

      log =
        capture_log(fn -> call("structured", %{"structured" => [1, 2], "content" => content}) end)

      assert log =~ "SEP-2106"
    end
  end

  # --- The cheap gate in front of the decode must not change what the check
  # decides. It is a performance change, so every test here is about semantics.

  describe "the first-byte gate rejects only what the decode would have rejected" do
    test "leading JSON whitespace does not make a compliant block non-compliant" do
      content = [%{"type" => "text", "text" => "  \n[1,2]"}]

      log =
        capture_log(fn -> call("structured", %{"structured" => [1, 2], "content" => content}) end)

      refute log =~ "SEP-2106"
    end

    test "a large non-matching JSON block is still not compliance" do
      big = Jason.encode!(Map.new(1..2_000, &{"k#{&1}", &1}))
      content = [%{"type" => "text", "text" => big}]

      log =
        capture_log(fn -> call("structured", %{"structured" => [1, 2], "content" => content}) end)

      assert log =~ "SEP-2106"
    end

    test "every enumerated JSON value's own serialization still counts as compliance" do
      for value <- [false, true, 0, -1, 1.5, "", "str", [], [1, 2], nil] do
        content = [%{"type" => "text", "text" => Jason.encode!(value)}]

        log =
          capture_log(fn ->
            call("structured", %{"structured" => value, "content" => content})
          end)

        refute log =~ "SEP-2106", "expected silence for #{inspect(value)}, got: #{log}"
      end
    end
  end

  # --- Adversarial item 1: a valid call still delivers byte-identical arguments ---

  test "arguments reach the handler unchanged — nothing is coerced, defaulted or expanded" do
    args = %{
      "name" => "Ada",
      "address" => %{"street" => "1 Main St", "city" => "Zurich"},
      "contactMethod" => "phone",
      "phone" => "555",
      "extra" => [1, %{"deep" => nil}]
    }

    seen = call("echo_args", args)["content"] |> hd() |> Map.get("text") |> Jason.decode!()
    assert seen == args
  end
end
