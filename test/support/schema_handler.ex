defmodule MCP.Test.SchemaHandler do
  @moduledoc """
  Test handler for the SEP-2106 surface: JSON Schema 2020-12 tool schemas and
  structured tool output.

  `handle_list_tools/3` advertises the conformance harness's own
  `json_schema_2020_12` fixture verbatim (from
  `@modelcontextprotocol/conformance@0.2.0-alpha.11`,
  `scenarios/server/json-schema-2020-12`), plus a tool whose `inputSchema`
  `$ref`s a network URI supplied at init — the canary the `$ref` MUST NOT is
  measured against — plus a tool carrying a boolean `outputSchema`.

  `handle_call_tool/4` returns whatever structured content the caller names in
  the arguments, so a single handler can drive every `structuredContent` value
  the schema enumerates (`schema.ts:1819-1821`) including the absent/null
  distinction.
  """
  @behaviour MCP.Server.Handler

  alias MCP.Server.ToolContext

  # The alpha harness's server fixture, verbatim.
  @fixture_schema %{
    "$schema" => "https://json-schema.org/draft/2020-12/schema",
    "type" => "object",
    "$defs" => %{
      "address" => %{
        "$anchor" => "addressDef",
        "type" => "object",
        "properties" => %{
          "street" => %{"type" => "string"},
          "city" => %{"type" => "string"}
        }
      }
    },
    "properties" => %{
      "name" => %{"type" => "string"},
      "address" => %{"$ref" => "#/$defs/address"},
      "contactMethod" => %{"type" => "string", "enum" => ["phone", "email"]},
      "phone" => %{"type" => "string"},
      "email" => %{"type" => "string"}
    },
    "allOf" => [%{"anyOf" => [%{"required" => ["phone"]}, %{"required" => ["email"]}]}],
    "if" => %{
      "properties" => %{"contactMethod" => %{"const" => "phone"}},
      "required" => ["contactMethod"]
    },
    "then" => %{"required" => ["phone"]},
    "else" => %{"required" => ["email"]},
    "additionalProperties" => false
  }

  @doc "The alpha harness's `json_schema_2020_12` inputSchema fixture."
  @spec fixture_schema() :: map()
  def fixture_schema, do: @fixture_schema

  @impl true
  def init(opts), do: {:ok, %{ref_url: Keyword.get(opts, :ref_url)}}

  @impl true
  def handle_list_tools(_cursor, %ToolContext{}, state) do
    {:ok, [fixture_tool(), network_ref_tool(state), boolean_output_tool(), draft_07_tool()], nil,
     state}
  end

  defp fixture_tool do
    %{
      "name" => "json_schema_2020_12_tool",
      "description" => "Tool with a full JSON Schema 2020-12 inputSchema",
      "inputSchema" => @fixture_schema
    }
  end

  # SEP-2106 Security Implications: a `$ref` to a network URI MUST NOT be
  # dereferenced. `ref_url` points at a live canary listener the test owns.
  defp network_ref_tool(%{ref_url: url}) do
    %{
      "name" => "network_ref_tool",
      "description" => "Tool whose inputSchema $refs a network URI",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"payload" => %{"$ref" => url || "https://example.invalid/schema.json"}}
      }
    }
  end

  # 2020-12 boolean schemas are legal at any schema position including the
  # root; `outputSchema` carries no `type: "object"` constraint
  # (`schema.ts:2005`).
  defp boolean_output_tool do
    %{
      "name" => "boolean_output_tool",
      "inputSchema" => %{"type" => "object"},
      "outputSchema" => false
    }
  end

  # `schema.ts:1962-1963` — an explicit non-default dialect is a spec-exampled
  # case, carried verbatim because this SDK implements no dialect at all.
  defp draft_07_tool do
    %{
      "name" => "draft_07_tool",
      "inputSchema" => %{
        "$schema" => "http://json-schema.org/draft-07/schema#",
        "type" => "object",
        "properties" => %{"a" => %{"type" => "number"}, "b" => %{"type" => "number"}},
        "required" => ["a", "b"]
      }
    }
  end

  @impl true
  # Echoes the arguments back as structured content, so a test names the exact
  # JSON value it wants on the wire. `"structured"` absent from the arguments
  # means the extras map omits the key entirely.
  def handle_call_tool("structured", args, %ToolContext{}, state) do
    content = Map.get(args, "content", [])

    extras =
      case Map.fetch(args, "structured") do
        {:ok, value} -> %{structured_content: value}
        :error -> %{}
      end

    extras =
      if Map.has_key?(args, "isError"),
        do: Map.put(extras, :is_error, args["isError"]),
        else: extras

    {:ok, content, extras, state}
  end

  # The pre-SEP-2106 shapes, unchanged, so their continued behaviour is
  # asserted beside the new one.
  def handle_call_tool("plain", _args, %ToolContext{}, state) do
    {:ok, [%{"type" => "text", "text" => "ok"}], state}
  end

  def handle_call_tool("plain_error", _args, %ToolContext{}, state) do
    {:ok, [%{"type" => "text", "text" => "bad"}], true, state}
  end

  # Echoes the arguments it was handed, verbatim, as JSON text — so a test can
  # assert byte-identical delivery rather than "the call did not crash".
  def handle_call_tool("echo_args", args, %ToolContext{}, state) do
    {:ok, [%{"type" => "text", "text" => Jason.encode!(args)}], state}
  end

  # The `$ref` canary tool is CALLABLE, not just listable. Without this clause
  # the call fell to the unknown-tool error below, and a canary that measures
  # an error path cannot see a resolver that runs on a successful one.
  def handle_call_tool("network_ref_tool", args, %ToolContext{}, state) do
    {:ok, [%{"type" => "text", "text" => Jason.encode!(args)}], state}
  end

  # Returns whatever the caller put in `"extras"` as slot 3, VERBATIM — so the
  # five plausible mistakes S4 enumerates (a camelCase key, a string key, a
  # struct, a non-boolean `:is_error`, and — added in round 2 for F-10 — a slot
  # 3 that is not a map at all, such as a keyword list) can be driven through a
  # real `tools/call` rather than asserted about in the abstract. It is
  # deliberately unguarded: a guard here would silently narrow what the tests
  # above can reach, which is the failure they exist to catch.
  def handle_call_tool("raw_extras", args, %ToolContext{}, state) do
    {:ok, Map.get(args, "content", []), Map.get(args, "extras"), state}
  end

  def handle_call_tool(_name, _args, %ToolContext{}, state) do
    {:error, -32_602, "unknown tool", state}
  end
end
