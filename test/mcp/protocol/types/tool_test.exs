defmodule MCP.Protocol.Types.ToolTest do
  use ExUnit.Case, async: true

  alias MCP.Protocol.Types.Tool

  @tool_map %{
    "name" => "get_weather",
    "title" => "Get Weather",
    "description" => "Get current weather for a city",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{
        "city" => %{"type" => "string"}
      },
      "required" => ["city"]
    }
  }

  describe "from_map/1" do
    test "parses a tool with required fields" do
      tool = Tool.from_map(@tool_map)

      assert tool.name == "get_weather"
      assert tool.title == "Get Weather"
      assert tool.description == "Get current weather for a city"
      assert tool.input_schema["type"] == "object"
    end

    test "parses a tool with annotations" do
      map =
        Map.put(@tool_map, "annotations", %{
          "readOnlyHint" => true,
          "destructiveHint" => false,
          "title" => "Weather Lookup"
        })

      tool = Tool.from_map(map)
      assert tool.annotations.read_only_hint == true
      assert tool.annotations.destructive_hint == false
      assert tool.annotations.title == "Weather Lookup"
    end

    test "parses a tool with outputSchema" do
      map =
        Map.put(@tool_map, "outputSchema", %{
          "type" => "object",
          "properties" => %{"temp" => %{"type" => "number"}}
        })

      tool = Tool.from_map(map)
      assert tool.output_schema["type"] == "object"
    end

    test "parses a tool with icons" do
      map =
        Map.put(@tool_map, "icons", [
          %{"src" => "https://example.com/icon.png", "mimeType" => "image/png"}
        ])

      tool = Tool.from_map(map)
      assert length(tool.icons) == 1
      assert hd(tool.icons).src == "https://example.com/icon.png"
    end

    test "parses a tool with _meta" do
      map = Map.put(@tool_map, "_meta", %{"custom" => "value"})
      tool = Tool.from_map(map)
      assert tool.meta == %{"custom" => "value"}
    end
  end

  describe "JSON encoding" do
    test "round-trips through JSON with camelCase keys" do
      tool = Tool.from_map(@tool_map)
      json = Jason.encode!(tool)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "get_weather"
      assert decoded["inputSchema"]["type"] == "object"
      refute Map.has_key?(decoded, "input_schema")
      refute Map.has_key?(decoded, "outputSchema")
    end

    test "omits nil fields" do
      tool = Tool.from_map(@tool_map)
      json = Jason.encode!(tool)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "annotations")
      refute Map.has_key?(decoded, "icons")
      refute Map.has_key?(decoded, "_meta")
    end
  end

  # --- MES-17 / SEP-2106: outputSchema is carried, whatever it holds ---
  #
  # SEP-2106's second implementation obligation removes the `type: "object"`
  # constraint from `outputSchema` (`schema.ts:2005`). `false` is used here as
  # the discriminating value because it is the one a nil-check flattens — the
  # same shape as D-1 — not because MCP admits a boolean schema in this field.
  # It does not: `schema.ts:2005` is an object type and its doc opens "An
  # optional JSON Schema **object**" (`:2000`). Generic 2020-12 admits boolean
  # schemas anywhere; this field is narrower (R-7). These tests measure the
  # SDK's pass-through, and are NOT conformance evidence — see
  # `MCP.Protocol.Types.Tool`'s moduledoc.

  describe "outputSchema is carried verbatim, and false is not an absence" do
    for value <- [true, false] do
      test "a boolean outputSchema of #{value} round-trips as a value, not an absence" do
        value = unquote(value)
        tool = Tool.from_map(Map.put(@tool_map, "outputSchema", value))

        assert tool.output_schema == value

        decoded = tool |> Jason.encode!() |> Jason.decode!()
        assert Map.has_key?(decoded, "outputSchema")
        assert decoded["outputSchema"] == value
      end
    end

    test "an absent outputSchema is still absent" do
      tool = Tool.from_map(@tool_map)

      assert tool.output_schema == nil
      refute tool |> Jason.encode!() |> Jason.decode!() |> Map.has_key?("outputSchema")
    end
  end

  # --- MES-17 / SEP-2106: any 2020-12 keyword survives, in either schema ---

  test "inputSchema keywords beyond `type` are carried verbatim, including `not` and `$anchor`" do
    schema = %{
      "type" => "object",
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "$defs" => %{"x" => %{"$anchor" => "xDef", "type" => "string"}},
      "properties" => %{"a" => %{"$ref" => "#/$defs/x"}},
      "not" => %{"required" => ["forbidden"]},
      "oneOf" => [%{"required" => ["a"]}],
      "if" => %{"required" => ["a"]},
      "then" => %{"required" => ["a"]},
      "else" => %{},
      "unevaluatedProperties" => false
    }

    decoded =
      @tool_map
      |> Map.put("inputSchema", schema)
      |> Tool.from_map()
      |> Jason.encode!()
      |> Jason.decode!()

    assert decoded["inputSchema"] == schema
  end
end
