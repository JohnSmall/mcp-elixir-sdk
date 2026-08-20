defmodule MCP.Protocol.HeaderMirror do
  @moduledoc """
  `x-mcp-header` — mirroring annotated tool parameters into `Mcp-Param-*` HTTP
  headers, and the tool-definition validation that gates it (SEP-2243).

  Derived from the normative spec at the pinned commit
  `5f5440bb26a62e2cf3440b92da5a667efa03b267`:

    * `server/tools.mdx:346-368` — the six constraints on an `x-mcp-header`
      value, and the client's obligation to **exclude** an offending tool from
      `tools/list` while keeping the valid ones.
    * `basic/transports/streamable-http.mdx:371-545` — static reachability,
      header extraction by property path, type conversion, and the Base64
      sentinel.

  The rules here are taken from that text, **not** from the conformance
  fixtures: the alpha.11 fixture exercises four of the six annotation
  constraints, so a fixture-derived implementation would be narrower than the
  spec (this is MES-35's finding, confirmed first-hand).

  ## What this module decides

  `validate_tool/1` answers one question — may this tool be offered to a
  caller? A tool whose `inputSchema` carries **any** invalid `x-mcp-header`
  annotation is rejected whole; the annotation being invalid makes the tool
  definition invalid, wherever in the schema it sits.

  `headers_for/2` answers the other — which headers does this call carry? It
  reads each annotated property's value at its exact property path and encodes
  it, omitting the header when no value is present.

  ## The encoder is the safety boundary

  Tool arguments are model-controlled and reach the transport by design, so the
  boundary is made structural rather than left to a filter: a value is
  converted to a string, tested for header safety, and **either** emitted
  as-is **or** replaced wholesale by the Base64 sentinel. There is no branch on
  which an unsafe octet — CR, LF, a control character — reaches the transport,
  so header injection and request splitting are closed by construction rather
  than by a check that a later edit could reorder. This module does not rely on
  the HTTP library rejecting a bad value.

  Header **names** are validated at `tools/list` time and an invalid one
  excludes the whole tool, so a hostile name never reaches header assembly.
  """

  require Logger

  # RFC 9110 §5.1 tchar: "!#$%&'*+-.^_`|~" / DIGIT / ALPHA.
  @tchar ~c"!#$%&'*+-.^_`|~"

  # The three primitive types an annotation may be applied to. `number` is
  # excluded by the spec in terms; a missing or non-string `type` never
  # establishes primitiveness, so it is rejected too.
  @primitive_types ~w(string integer boolean)

  # IEEE 754 double-precision safe integer range (−2^53+1 .. 2^53−1).
  @max_safe_integer 9_007_199_254_740_991
  @min_safe_integer -9_007_199_254_740_991

  @sentinel_prefix "=?base64?"
  @sentinel_suffix "?="

  @typedoc """
  One validated annotation: the `Mcp-Param-{name}` name portion, the exact
  property path to read the value from, and the schema type it was declared
  with.
  """
  @type annotation :: %{name: String.t(), path: [String.t()], type: String.t()}

  @typedoc "Why a tool definition was rejected. Carries the offending value."
  @type reason ::
          {:empty_header_name, String.t()}
          | {:invalid_header_name, String.t()}
          | {:control_character_in_header_name, String.t()}
          | {:duplicate_header_name, String.t()}
          | {:non_primitive_type, String.t(), term()}
          | {:not_statically_reachable, String.t()}
          | {:annotation_not_on_a_property, String.t()}
          | {:invalid_annotation_value, term()}

  @doc """
  Validates a tool definition's `x-mcp-header` annotations.

  Returns `{:ok, annotations}` — possibly `[]` for an unannotated tool, which
  is valid and mirrors nothing — or `{:error, reason}` naming the first
  violation found. A tool with no `inputSchema`, or one whose `inputSchema` is
  not an object, is valid and carries no annotations.
  """
  @spec validate_tool(map()) :: {:ok, [annotation()]} | {:error, reason()}
  def validate_tool(tool) when is_map(tool) do
    tool
    |> Map.get("inputSchema")
    |> validate_schema()
  end

  @doc """
  Validates an `inputSchema` in isolation. See `validate_tool/1`.
  """
  @spec validate_schema(term()) :: {:ok, [annotation()]} | {:error, reason()}
  def validate_schema(schema) when is_map(schema) do
    schema
    |> collect([], true)
    |> validate_all()
  end

  def validate_schema(_not_an_object), do: {:ok, []}

  @doc """
  Builds the `Mcp-Param-*` headers for a `tools/call`, given the tool's
  validated annotations and the call arguments.

  A header is omitted when no value is present at the annotated path — the
  spec's own rule — and when the value cannot be mirrored (an integer outside
  the IEEE 754 safe range, or a value whose runtime type is not one of
  string/integer/boolean). Both omissions are logged: an operator who cannot
  see a header that did not happen has the same problem as one who cannot see
  a tool that was dropped.
  """
  @spec headers_for([annotation()], map()) :: [{String.t(), String.t()}]
  def headers_for(annotations, arguments) when is_list(annotations) do
    args = if is_map(arguments), do: arguments, else: %{}

    Enum.flat_map(annotations, &header_for(&1, args))
  end

  defp header_for(%{name: name, path: path}, args) do
    case fetch_path(args, path) do
      # `:error` is "no value at that path"; an explicit JSON null says the
      # same thing. Both omit the header, which is the spec's own rule.
      :error -> []
      {:ok, nil} -> []
      {:ok, value} -> encode_or_omit(value, name, path)
    end
  end

  defp encode_or_omit(value, name, path) do
    case convert(value) do
      {:ok, string} ->
        [{header_name(name), encode_value(string)}]

      {:error, why} ->
        Logger.warning(
          "MCP header mirroring: omitting Mcp-Param-#{name} for argument path " <>
            "#{inspect(Enum.join(path, "."))} — #{why}. The request is sent WITHOUT " <>
            "this header; a server that requires it will reject with -32020."
        )

        []
    end
  end

  @doc """
  Encodes a value for a header field, applying the Base64 sentinel when the
  value cannot be carried as plain ASCII.

  This is the same rule for `Mcp-Param-*` and for `Mcp-Name`
  (`streamable-http.mdx:490-492`), so both callers share one encoder.

      iex> MCP.Protocol.HeaderMirror.encode_value("us-west1")
      "us-west1"

      iex> MCP.Protocol.HeaderMirror.encode_value("Hello, 世界")
      "=?base64?SGVsbG8sIOS4lueVjA==?="

      iex> MCP.Protocol.HeaderMirror.encode_value(" padded ")
      "=?base64?IHBhZGRlZCA=?="

      iex> MCP.Protocol.HeaderMirror.encode_value("=?base64?literal?=")
      "=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?="
  """
  @spec encode_value(String.t()) :: String.t()
  def encode_value(value) when is_binary(value) do
    if header_safe?(value), do: value, else: sentinel(value)
  end

  @doc """
  Decodes a Base64-sentinel header value, or returns a plain value unchanged.

  Servers **MUST** decode before comparing a header to the corresponding body
  value (`streamable-http.mdx:501-504`). A sentinel-shaped value whose payload
  is not valid Base64 is returned unchanged, so a malformed value fails the
  comparison it was going to fail anyway rather than becoming an exception.
  """
  @spec decode_value(String.t()) :: String.t()
  def decode_value(value) when is_binary(value) do
    with true <- sentinel_shaped?(value),
         payload <-
           binary_part(
             value,
             byte_size(@sentinel_prefix),
             byte_size(value) - byte_size(@sentinel_prefix) - byte_size(@sentinel_suffix)
           ),
         {:ok, decoded} <- Base.decode64(payload) do
      decoded
    else
      _ -> value
    end
  end

  @doc """
  Renders a rejection reason as a sentence for a log line or an operator-facing
  `excluded_tools/1` entry.
  """
  @spec describe(reason()) :: String.t()
  def describe({:empty_header_name, _}), do: "x-mcp-header value is empty (MUST NOT be empty)"

  def describe({:invalid_header_name, value}),
    do:
      "x-mcp-header value #{inspect(value)} is not an HTTP field-name token " <>
        "(RFC 9110 §5.1 `1*tchar`)"

  def describe({:control_character_in_header_name, value}),
    do: "x-mcp-header value #{inspect(value)} contains a control character (CR/LF or other)"

  def describe({:duplicate_header_name, value}),
    do:
      "x-mcp-header value #{inspect(value)} is duplicated in the inputSchema " <>
        "(MUST be case-insensitively unique)"

  def describe({:non_primitive_type, value, type}),
    do:
      "x-mcp-header #{inspect(value)} is applied to a property of type #{inspect(type)}; " <>
        "only string, integer and boolean are permitted (`number` is excluded)"

  def describe({:not_statically_reachable, value}),
    do:
      "x-mcp-header #{inspect(value)} is not statically reachable from the schema root — " <>
        "the path must consist solely of `properties` keys, never `items`, " <>
        "`oneOf`/`anyOf`/`allOf`/`not`, `if`/`then`/`else` or `$ref`"

  def describe({:annotation_not_on_a_property, value}),
    do: "x-mcp-header #{inspect(value)} is on the schema root, which is not a property"

  def describe({:invalid_annotation_value, value}),
    do: "x-mcp-header value #{inspect(value)} is not a string"

  # --- Collection ---

  # Walks the WHOLE schema, not only its reachable part: an annotation in an
  # unreachable position does not get ignored, it invalidates the tool
  # ("An x-mcp-header annotation anywhere else makes the annotation — and thus
  # the tool definition — invalid", streamable-http.mdx:396-397).
  defp collect(schema, path, reachable?) when is_map(schema) do
    here =
      case Map.fetch(schema, "x-mcp-header") do
        {:ok, value} ->
          [%{value: value, path: path, reachable?: reachable?, type: Map.get(schema, "type")}]

        :error ->
          []
      end

    here ++ Enum.flat_map(schema, fn {key, value} -> descend(key, value, path, reachable?) end)
  end

  defp collect(list, path, _reachable?) when is_list(list) do
    # Anything inside a list (a `oneOf` branch, a tuple-form `items`) is by
    # definition not reached through a chain of `properties` keys.
    Enum.flat_map(list, &collect(&1, path, false))
  end

  defp collect(_scalar, _path, _reachable?), do: []

  # A `properties` map is the only keyword that preserves reachability, and
  # only for the sub-schemas directly under it.
  defp descend("properties", properties, path, reachable?) when is_map(properties) do
    Enum.flat_map(properties, fn {name, subschema} ->
      collect(subschema, path ++ [name], reachable?)
    end)
  end

  defp descend("x-mcp-header", _value, _path, _reachable?), do: []

  defp descend(_key, value, path, _reachable?) when is_map(value) or is_list(value),
    do: collect(value, path, false)

  defp descend(_key, _value, _path, _reachable?), do: []

  # --- Validation ---

  defp validate_all(found) do
    Enum.reduce_while(found, {:ok, [], MapSet.new()}, fn annotation, {:ok, acc, seen} ->
      case validate_one(annotation, seen) do
        {:ok, validated} ->
          {:cont, {:ok, [validated | acc], MapSet.put(seen, String.downcase(validated.name))}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, acc, _seen} -> {:ok, Enum.reverse(acc)}
      {:error, _} = error -> error
    end
  end

  defp validate_one(%{value: value}, _seen) when not is_binary(value),
    do: {:error, {:invalid_annotation_value, value}}

  defp validate_one(%{value: ""}, _seen), do: {:error, {:empty_header_name, ""}}

  defp validate_one(%{value: value, path: path, reachable?: reachable?, type: type}, seen) do
    cond do
      control_character?(value) -> {:error, {:control_character_in_header_name, value}}
      not token?(value) -> {:error, {:invalid_header_name, value}}
      MapSet.member?(seen, String.downcase(value)) -> {:error, {:duplicate_header_name, value}}
      path == [] -> {:error, {:annotation_not_on_a_property, value}}
      not reachable? -> {:error, {:not_statically_reachable, value}}
      type not in @primitive_types -> {:error, {:non_primitive_type, value, type}}
      true -> {:ok, %{name: value, path: path, type: type}}
    end
  end

  defp token?(value), do: value != "" and value |> to_charlist() |> Enum.all?(&tchar?/1)

  defp tchar?(c) when c in ?a..?z when c in ?A..?Z when c in ?0..?9, do: true
  defp tchar?(c), do: c in @tchar

  # Control characters are a subset of what the token rule already rejects;
  # they are checked FIRST so the operator is told the security-relevant fact
  # ("this name carried a CR") rather than the generic grammar one.
  defp control_character?(value) do
    value
    |> to_charlist()
    |> Enum.any?(fn c -> c < 0x20 or c == 0x7F end)
  end

  # --- Extraction and encoding ---

  # Reads the instance value at the EXACT property path. A non-map at any step
  # means the path is not present — never an error.
  defp fetch_path(value, []), do: {:ok, value}

  defp fetch_path(value, [key | rest]) when is_map(value) do
    case Map.fetch(value, key) do
      {:ok, next} -> fetch_path(next, rest)
      :error -> :error
    end
  end

  defp fetch_path(_value, _path), do: :error

  defp convert(value) when is_binary(value), do: {:ok, value}
  defp convert(true), do: {:ok, "true"}
  defp convert(false), do: {:ok, "false"}

  defp convert(value) when is_integer(value) do
    if value >= @min_safe_integer and value <= @max_safe_integer do
      {:ok, Integer.to_string(value)}
    else
      {:error,
       "the integer #{value} is outside the IEEE 754 double-precision safe range " <>
         "(#{@min_safe_integer}..#{@max_safe_integer}), which the spec requires mirrored " <>
         "integers to be within"}
    end
  end

  defp convert(value) when is_float(value),
    do: {:error, "the value is a number (#{value}); `number` parameters may not be mirrored"}

  defp convert(value),
    do:
      {:error,
       "the value #{inspect(value, limit: 3, printable_limit: 60)} is not a string, integer " <>
         "or boolean"}

  # Safe iff every octet is visible ASCII or space, with no leading/trailing
  # whitespace and no collision with the sentinel. Horizontal tab is inside
  # RFC 9110's field-value set but is treated as unsafe here: a tab in a value
  # is not "safely represented as a plain ASCII header value", and encoding it
  # costs nothing.
  defp header_safe?(value) do
    plain_ascii?(value) and not padded?(value) and not sentinel_shaped?(value)
  end

  defp plain_ascii?(value) do
    for(<<c <- value>>, do: c) |> Enum.all?(&(&1 >= 0x20 and &1 <= 0x7E))
  end

  defp padded?(value) do
    String.starts_with?(value, " ") or String.ends_with?(value, " ")
  end

  defp sentinel_shaped?(value) do
    String.starts_with?(value, @sentinel_prefix) and
      String.ends_with?(value, @sentinel_suffix) and
      byte_size(value) >= byte_size(@sentinel_prefix) + byte_size(@sentinel_suffix)
  end

  defp sentinel(value), do: @sentinel_prefix <> Base.encode64(value) <> @sentinel_suffix

  defp header_name(name), do: "mcp-param-" <> String.downcase(name)
end
