defmodule MCP.Protocol.Messages.ToolsTest do
  use ExUnit.Case, async: true

  alias MCP.Protocol.Messages.Tools

  describe "ListParams" do
    test "from_map/1 parses with cursor" do
      params = Tools.ListParams.from_map(%{"cursor" => "page2"})
      assert params.cursor == "page2"
    end

    test "from_map/1 handles empty map" do
      params = Tools.ListParams.from_map(%{})
      assert params.cursor == nil
    end

    test "to_map/1 omits nil cursor" do
      params = %Tools.ListParams{cursor: nil}
      assert Tools.ListParams.to_map(params) == %{}
    end

    test "to_map/1 includes cursor" do
      params = %Tools.ListParams{cursor: "abc"}
      assert Tools.ListParams.to_map(params) == %{"cursor" => "abc"}
    end
  end

  describe "ListResult" do
    test "from_map/1 parses tool list" do
      map = %{
        "tools" => [
          %{
            "name" => "weather",
            "inputSchema" => %{"type" => "object"}
          }
        ],
        "nextCursor" => "page2"
      }

      result = Tools.ListResult.from_map(map)

      assert length(result.tools) == 1
      assert hd(result.tools).name == "weather"
      assert result.next_cursor == "page2"
    end

    test "round-trips through JSON" do
      map = %{
        "tools" => [
          %{"name" => "t1", "inputSchema" => %{"type" => "object"}}
        ]
      }

      result = Tools.ListResult.from_map(map)
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert length(decoded["tools"]) == 1
      assert hd(decoded["tools"])["name"] == "t1"
      refute Map.has_key?(decoded, "nextCursor")
    end
  end

  describe "CallParams" do
    test "from_map/1 parses call params" do
      params =
        Tools.CallParams.from_map(%{"name" => "weather", "arguments" => %{"city" => "NYC"}})

      assert params.name == "weather"
      assert params.arguments == %{"city" => "NYC"}
    end

    test "to_map/1 omits nil arguments" do
      params = %Tools.CallParams{name: "ping"}
      map = Tools.CallParams.to_map(params)
      assert map == %{"name" => "ping"}
    end
  end

  describe "CallResult" do
    test "from_map/1 parses call result" do
      map = %{
        "content" => [%{"type" => "text", "text" => "72F, sunny"}],
        "isError" => false
      }

      result = Tools.CallResult.from_map(map)
      assert length(result.content) == 1
      assert hd(result.content).text == "72F, sunny"
      assert result.is_error == false
    end

    test "from_map/1 parses with structuredContent" do
      map = %{
        "content" => [%{"type" => "text", "text" => "result"}],
        "structuredContent" => %{"temperature" => 72}
      }

      result = Tools.CallResult.from_map(map)
      assert result.structured_content == %{"temperature" => 72}
    end

    test "round-trips through JSON with camelCase" do
      map = %{
        "content" => [%{"type" => "text", "text" => "ok"}],
        "structuredContent" => %{"val" => 1},
        "isError" => true
      }

      result = Tools.CallResult.from_map(map)
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert decoded["structuredContent"] == %{"val" => 1}
      assert decoded["isError"] == true
    end
  end

  # --- MES-17 / SEP-2106: structuredContent is any JSON value (D-1, D-2) ---
  #
  # `schema.ts:1819-1821` enumerates what `structuredContent?: unknown` means:
  # "any JSON value (object, array, string, number, boolean, or null)". The old
  # encoder used `if struct.structured_content`, which is falsy on `false`, and
  # the old typespec said `map() | nil`. Both are fixed here; `false` is the
  # case that discriminates, because it is the only enumerated value Elixir's
  # `if` treats as absent.

  describe "CallResult — structuredContent may be any JSON value" do
    defp encoded(struct), do: struct |> Jason.encode!() |> Jason.decode!()

    for {label, value} <- [
          {"false", false},
          {"true", true},
          {"zero", 0},
          {"a float", 1.5},
          {"an empty string", ""},
          {"a string", "str"},
          {"an empty array", []},
          {"an array", [1, 2]},
          {"an empty object", %{}},
          {"an object", %{"a" => 1}}
        ] do
      test "encodes #{label}" do
        value = unquote(Macro.escape(value))
        result = encoded(%Tools.CallResult{content: [], structured_content: value})

        assert Map.has_key?(result, "structuredContent")
        assert result["structuredContent"] == value
      end

      test "from_map/1 decodes #{label} and it survives a full round trip" do
        value = unquote(Macro.escape(value))
        map = %{"content" => [], "structuredContent" => value}
        struct = Tools.CallResult.from_map(map)

        assert struct.structured_content == value
        assert encoded(struct)["structuredContent"] == value
      end
    end
  end

  describe "CallResult — absent is not null, in both directions" do
    test "the default is the absent sentinel, and it emits no key" do
      struct = %Tools.CallResult{content: []}

      assert struct.structured_content == Tools.CallResult.absent()
      refute Map.has_key?(encoded(struct), "structuredContent")
    end

    test "an explicit nil emits JSON null" do
      encoded = encoded(%Tools.CallResult{content: [], structured_content: nil})

      assert Map.has_key?(encoded, "structuredContent")
      assert encoded["structuredContent"] == nil
    end

    test "from_map/1 distinguishes an absent key from a present null" do
      absent = Tools.CallResult.from_map(%{"content" => []})
      null = Tools.CallResult.from_map(%{"content" => [], "structuredContent" => nil})

      assert absent.structured_content == Tools.CallResult.absent()
      assert null.structured_content == nil
      refute absent.structured_content == null.structured_content
    end

    test "both directions agree: absent round-trips absent, null round-trips null" do
      absent = %{"content" => []}
      null = %{"content" => [], "structuredContent" => nil}

      assert absent
             |> Tools.CallResult.from_map()
             |> encoded()
             |> Map.has_key?("structuredContent") == false

      assert null |> Tools.CallResult.from_map() |> encoded() |> Map.has_key?("structuredContent") ==
               true
    end
  end

  describe "CallResult — isError keys off presence too" do
    test "an explicit false survives a decode/encode round trip" do
      # `isError?: boolean` (schema.ts:1826) admits no null, so nil alone is
      # unambiguously "absent" here and needs no sentinel — but the old falsy
      # guard still dropped a peer's explicit `"isError": false`.
      struct = Tools.CallResult.from_map(%{"content" => [], "isError" => false})

      assert struct.is_error == false
      assert encoded(struct)["isError"] == false
    end

    test "nil isError is omitted" do
      refute Map.has_key?(encoded(%Tools.CallResult{content: []}), "isError")
    end
  end
end
