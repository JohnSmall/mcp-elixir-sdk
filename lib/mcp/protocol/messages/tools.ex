defmodule MCP.Protocol.Messages.Tools do
  @moduledoc """
  Message types for `tools/list` and `tools/call`.
  """

  defmodule ListParams do
    @moduledoc """
    Parameters for `tools/list`.
    """

    @derive Jason.Encoder
    defstruct [:cursor, :meta]

    @type t :: %__MODULE__{
            cursor: String.t() | nil,
            meta: map() | nil
          }

    @spec from_map(map()) :: t()
    def from_map(map) when is_map(map) do
      %__MODULE__{
        cursor: Map.get(map, "cursor"),
        meta: Map.get(map, "_meta")
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = params) do
      %{}
      |> maybe_put("cursor", params.cursor)
      |> maybe_put("_meta", params.meta)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, val), do: Map.put(map, key, val)
  end

  defmodule ListResult do
    @moduledoc """
    Result of `tools/list`.
    """

    alias MCP.Protocol.Types.Tool

    @derive Jason.Encoder
    defstruct [:tools, :next_cursor, :meta]

    @type t :: %__MODULE__{
            tools: [Tool.t()],
            next_cursor: String.t() | nil,
            meta: map() | nil
          }

    @spec from_map(map()) :: t()
    def from_map(map) when is_map(map) do
      %__MODULE__{
        tools: map |> Map.fetch!("tools") |> Enum.map(&Tool.from_map/1),
        next_cursor: Map.get(map, "nextCursor"),
        meta: Map.get(map, "_meta")
      }
    end

    defimpl Jason.Encoder, for: __MODULE__ do
      def encode(struct, opts) do
        map = %{tools: struct.tools}

        map = if struct.next_cursor, do: Map.put(map, :nextCursor, struct.next_cursor), else: map
        map = if struct.meta, do: Map.put(map, :_meta, struct.meta), else: map

        Jason.Encode.map(map, opts)
      end
    end
  end

  defmodule CallParams do
    @moduledoc """
    Parameters for `tools/call`.
    """

    @derive Jason.Encoder
    defstruct [:name, :arguments, :meta]

    @type t :: %__MODULE__{
            name: String.t(),
            arguments: map() | nil,
            meta: map() | nil
          }

    @spec from_map(map()) :: t()
    def from_map(map) when is_map(map) do
      %__MODULE__{
        name: Map.fetch!(map, "name"),
        arguments: Map.get(map, "arguments"),
        meta: Map.get(map, "_meta")
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = params) do
      %{"name" => params.name}
      |> maybe_put("arguments", params.arguments)
      |> maybe_put("_meta", params.meta)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, val), do: Map.put(map, key, val)
  end

  defmodule CallResult do
    @moduledoc """
    Result of `tools/call`.

    ## `structuredContent` is any JSON value, and absent is not `null`

    `schema.ts:1821` (`CallToolResult`) and `schema.ts:2469` (`ToolResultContent`)
    both type the field `structuredContent?: unknown`, and the doc comment at
    `schema.ts:1819-1821` enumerates what that means: "any JSON value (object,
    array, string, number, boolean, or null)". So this struct types
    `:structured_content` as `t:term/0`, not `map()`, and its encoder keys off
    **presence**, never truthiness — `false`, `0`, `""`, `[]` and `%{}` are all
    values a tool may legitimately return.

    Because JSON `null` is one of the enumerated legal values, "absent" and
    "present and null" are *different* results and `nil` cannot stand for both.
    The third state is carried by the field's default, the atom
    `:absent`:

        %CallResult{content: []}                        # -> no structuredContent key
        %CallResult{content: [], structured_content: nil}   # -> "structuredContent": null
        %CallResult{content: [], structured_content: false} # -> "structuredContent": false

    An atom other than `nil`/`true`/`false` is not producible by JSON decoding,
    so the sentinel can never collide with a decoded value. `from_map/1` reads
    the same distinction off key presence in the incoming map, so the two
    directions agree.

    `:is_error` and `:meta` need no sentinel — `isError?: boolean` at
    `schema.ts:1826` admits no null — but they key off presence too, so a peer's
    explicit `"isError": false` survives a decode/encode round trip.
    """

    alias MCP.Protocol.Types.Content

    @absent :absent

    @derive Jason.Encoder
    defstruct content: nil, structured_content: @absent, is_error: nil, meta: nil

    @type t :: %__MODULE__{
            content: [Content.content_block()],
            structured_content: term(),
            is_error: boolean() | nil,
            meta: map() | nil
          }

    @doc """
    The sentinel this struct uses for "field absent from the wire", as
    distinct from a present JSON `null`. It is the default of
    `:structured_content`.
    """
    @spec absent() :: :absent
    def absent, do: @absent

    @spec from_map(map()) :: t()
    def from_map(map) when is_map(map) do
      %__MODULE__{
        content: map |> Map.fetch!("content") |> Enum.map(&Content.from_map/1),
        structured_content: fetch_or_absent(map, "structuredContent"),
        is_error: Map.get(map, "isError"),
        meta: Map.get(map, "_meta")
      }
    end

    defp fetch_or_absent(map, key) do
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> @absent
      end
    end

    defimpl Jason.Encoder, for: __MODULE__ do
      @absent :absent

      def encode(struct, opts) do
        %{content: struct.content}
        |> put_present(:structuredContent, struct.structured_content)
        |> put_present(:isError, struct.is_error)
        |> put_present(:_meta, struct.meta)
        |> Jason.Encode.map(opts)
      end

      # Presence, not truthiness: `false`, `0`, `""`, `[]` and `%{}` are all
      # legitimate `structuredContent` values (schema.ts:1819-1821).
      defp put_present(map, _key, @absent), do: map

      defp put_present(map, :structuredContent, value),
        do: Map.put(map, :structuredContent, value)

      defp put_present(map, _key, nil), do: map
      defp put_present(map, key, value), do: Map.put(map, key, value)
    end
  end
end
