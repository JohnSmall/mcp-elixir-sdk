defmodule MCP.Protocol.Types.Tool do
  @moduledoc """
  An MCP tool definition.

  Tools are functions that can be called by an LLM via the MCP client.

  ## Schema fields are carried verbatim, and the two are not symmetric

  `:input_schema` and `:output_schema` are transported exactly as the tool
  author wrote them. This SDK does not parse, resolve, interpret or validate
  either one, and in particular it never dereferences a `$ref` — see
  `MCP.Server.Handler` for the stated policy.

  The two fields have different shapes at the wire, and flattening the
  asymmetry would be wrong in both directions:

  * `inputSchema` (`schema.ts:1997`) is `{ $schema?: string; type: "object";
    [key: string]: unknown }` — `type: "object"` is **required at the root**
    (`schema.ts:1985-1986`), so an input schema is always a JSON object and
    `:input_schema` is typed `map()`.
  * `outputSchema` (`schema.ts:2005`) is `{ $schema?: string; [key: string]:
    unknown }` — no `type: "object"` constraint, which is SEP-2106's second
    implementation obligation ("allow any valid JSON Schema (remove the
    `type: \"object\"` constraint)").

  `:output_schema` is typed `map() | boolean() | nil` rather than `map() | nil`.
  **That widening is a permissive typespec on a pass-through field, not a claim
  that MCP admits a boolean schema here** (R-7, MES-17 round 1, which had it
  the other way round). Generic JSON Schema 2020-12 does admit the boolean
  schemas `true` and `false` at any position; the MCP schema does not admit one
  in *this* field — `schema.ts:2005` is an **object** type, to which `false` is
  not assignable, and its doc comment opens "An optional JSON Schema **object**"
  (`schema.ts:2000`). The same comment then says "This can be any valid JSON
  Schema 2020-12" (`:2001`), which is where the wider reading came from; the TS
  type is the narrower and more specific of the two, and it governs.

  The widening is kept because a permissive typespec on a field this SDK only
  copies costs nothing and pins a future narrowing — the same defect D-2 was.
  It is **not** conformance evidence that a boolean `outputSchema` is
  well-formed MCP, and the test that puts one on the wire says so.

  Beyond `type`, **any** JSON Schema 2020-12 keyword may appear in either
  schema — composition (`oneOf`, `anyOf`, `allOf`, `not`), conditional
  (`if`/`then`/`else`), reference (`$ref`, `$defs`, `$anchor`) and any other
  standard validation or annotation keyword (`schema.ts:1985-1989`). 2020-12 is
  the *default* dialect when no `$schema` is given (`schema.ts:1995`, `:2003`),
  not the only one: an explicit older dialect is a spec-exampled case
  (`schema.ts:1962-1963`, "With explicit draft-07 input schema"). Since this
  SDK implements no dialect, it neither honours nor refuses one — every
  dialect, including one that does not exist, is carried through untouched.
  """

  alias MCP.Protocol.Types.{Icon, ToolAnnotations}

  @derive Jason.Encoder
  defstruct [
    :name,
    :title,
    :description,
    :input_schema,
    :output_schema,
    :annotations,
    :icons,
    :meta
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          input_schema: map(),
          output_schema: map() | boolean() | nil,
          annotations: ToolAnnotations.t() | nil,
          icons: [Icon.t()] | nil,
          meta: map() | nil
        }

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      name: Map.fetch!(map, "name"),
      title: Map.get(map, "title"),
      description: Map.get(map, "description"),
      input_schema: Map.fetch!(map, "inputSchema"),
      output_schema: Map.get(map, "outputSchema"),
      annotations: map |> Map.get("annotations") |> parse_annotations(),
      icons: map |> Map.get("icons") |> parse_icons(),
      meta: Map.get(map, "_meta")
    }
  end

  defp parse_annotations(nil), do: nil
  defp parse_annotations(map), do: ToolAnnotations.from_map(map)

  defp parse_icons(nil), do: nil
  defp parse_icons(icons), do: Enum.map(icons, &Icon.from_map/1)

  defimpl Jason.Encoder, for: __MODULE__ do
    def encode(struct, opts) do
      struct
      |> Map.from_struct()
      |> Enum.reduce(%{}, fn
        {_key, nil}, acc -> acc
        {:input_schema, val}, acc -> Map.put(acc, :inputSchema, val)
        {:output_schema, val}, acc -> Map.put(acc, :outputSchema, val)
        {:meta, val}, acc -> Map.put(acc, :_meta, val)
        {key, val}, acc -> Map.put(acc, key, val)
      end)
      |> Jason.Encode.map(opts)
    end
  end
end
