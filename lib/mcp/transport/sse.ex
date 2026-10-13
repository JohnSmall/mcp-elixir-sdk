defmodule MCP.Transport.SSE do
  @moduledoc """
  Server-Sent Events (SSE) encoding and decoding utilities.

  Used by the Streamable HTTP transport for streaming JSON-RPC messages
  over SSE connections.

  ## SSE Format

  SSE events consist of field lines separated by newlines, with events
  separated by blank lines:

      event: message
      id: 1
      data: {"jsonrpc":"2.0",...}

  Fields:
    * `event:` — event type (default: "message")
    * `id:` — event ID for resumability
    * `data:` — event payload (JSON-RPC message)
    * `retry:` — reconnection interval in milliseconds
  """

  @type event :: %{
          optional(:event) => String.t(),
          optional(:id) => String.t(),
          optional(:data) => String.t(),
          optional(:retry) => non_neg_integer()
        }

  @doc """
  Encodes an SSE event map into a string suitable for streaming.

  ## Examples

      iex> MCP.Transport.SSE.encode_event(%{event: "message", data: ~s({"jsonrpc":"2.0"})})
      "event: message\\ndata: {\\"jsonrpc\\":\\"2.0\\"}\\n\\n"

      iex> MCP.Transport.SSE.encode_event(%{id: "42", data: "hello"})
      "id: 42\\ndata: hello\\n\\n"
  """
  @spec encode_event(event()) :: String.t()
  def encode_event(event) when is_map(event) do
    lines =
      []
      |> maybe_add_field("event", Map.get(event, :event))
      |> maybe_add_field("id", Map.get(event, :id))
      |> maybe_add_field("retry", encode_retry(Map.get(event, :retry)))
      |> add_data_field(Map.get(event, :data))

    IO.iodata_to_binary([Enum.join(lines, "\n"), "\n\n"])
  end

  @doc """
  Encodes a JSON-RPC message as an SSE event.

  Convenience function that JSON-encodes the message and wraps it in
  an SSE event with the "message" event type.

  ## Options

    * `:id` — event ID for resumability
    * `:event` — event type (default: "message")
  """
  @spec encode_message(map(), keyword()) :: String.t()
  def encode_message(message, opts \\ []) when is_map(message) do
    event = %{
      event: Keyword.get(opts, :event, "message"),
      data: Jason.encode!(message)
    }

    event =
      case Keyword.get(opts, :id) do
        nil -> event
        id -> Map.put(event, :id, to_string(id))
      end

    encode_event(event)
  end

  @doc """
  Returns a bare SSE **comment line** — the keep-alive frame.

  Per the SSE specification any line beginning with a colon is a comment
  carrying no event data, and clients must ignore it rather than treat it as
  malformed input. The 2026-07-28 transport encourages emitting one
  periodically on long-lived streams — in particular a `subscriptions/listen`
  response stream — so intermediaries and client idle timeouts do not close a
  connection during a quiet period (streamable-http.mdx:145-155, whose own
  example is `:\r\n`).

  This exists because `encode_event/1` **cannot** produce one: it always
  appends a `data:` line (see `add_data_field/2`), which is correct for an
  event and wrong for a comment. Our own parser already ignores comments —
  `parse_field(":" <> _rest, acc)` — so the two directions agree.

      iex> MCP.Transport.SSE.comment()
      ":\r\n"
  """
  @spec comment() :: String.t()
  def comment, do: ":\r\n"

  @doc """
  Decodes one SSE event block into an event map: the field rules only, not dispatch (`feed/2`).
  Lines may end in CRLF, CR or LF, and multiple `data:` lines are joined with newlines.
  A line with no colon is a field with an empty value; an `id` containing NUL, and a
  `retry` that is not all ASCII digits, are ignored. An id-only block still decodes.

  Returns `{:ok, event}` or `{:error, reason}`.
  """
  @spec decode_event(String.t()) :: {:ok, event()} | {:error, term()}
  def decode_event(text) when is_binary(text) do
    lines = String.split(text, ["\r\n", "\r", "\n"])

    event =
      Enum.reduce(lines, %{}, fn line, acc ->
        parse_field(line, acc)
      end)

    if map_size(event) == 0 do
      {:error, :empty_event}
    else
      {:ok, event}
    end
  end

  @doc """
  Creates a new stream parser for incrementally parsing SSE events
  from chunked data.

  Returns an initial parser state. Feed data to it using `feed/2`.

  ## Example

      parser = MCP.Transport.SSE.new_parser()
      {events, parser} = MCP.Transport.SSE.feed(parser, chunk1)
      {events, parser} = MCP.Transport.SSE.feed(parser, chunk2)
  """
  @spec new_parser() :: parser()
  def new_parser, do: %{buffer: "", cr: false, bom: "", last_id: ""}

  @doc """
  Feeds data to a stream parser and returns any complete events.

  Returns `{events, new_parser_state}`. Per WHATWG dispatch, a block with no `data:` field
  is not dispatched, and the last event `id` persists into later events (absent while empty).

  Lines may end in CRLF, CR or LF, mixed within one stream, as the SSE
  specification allows. A CR that ends one chunk and an LF that starts the
  next are one line ending, and a byte-order mark at the start of the stream
  is dropped, even when it arrives split across chunks.

  A bare binary state (the pre-MES-156 form) is still accepted; `""` is a fresh parser.
  """
  @spec feed(parser() | binary(), binary()) :: {[event()], parser()}
  def feed(parser, data) when is_binary(data), do: feed_chunk(parser, data)

  # --- Private helpers ---

  defp maybe_add_field(lines, _field, nil), do: lines
  defp maybe_add_field(lines, _field, ""), do: lines
  defp maybe_add_field(lines, field, value), do: lines ++ ["#{field}: #{value}"]

  defp encode_retry(nil), do: nil
  defp encode_retry(ms) when is_integer(ms), do: Integer.to_string(ms)

  defp add_data_field(lines, nil), do: lines ++ ["data: "]
  defp add_data_field(lines, ""), do: lines ++ ["data: "]

  defp add_data_field(lines, data) do
    # Multi-line data is split into multiple `data:` lines
    data_lines =
      data
      |> String.split("\n")
      |> Enum.map(fn line -> "data: #{line}" end)

    lines ++ data_lines
  end

  defp parse_field(":" <> _rest, acc), do: acc
  defp parse_field("", acc), do: acc

  # The field name runs to the FIRST colon, and exactly one space after it is
  # dropped; the rest of the value is kept as sent (no trim).
  defp parse_field(line, acc) do
    case String.split(line, ":", parts: 2) do
      [field, " " <> value] -> process_field(field, value, acc)
      [field, value] -> process_field(field, value, acc)
      [field] -> process_field(field, "", acc)
    end
  end

  defp apply_field("event", value, acc), do: Map.put(acc, :event, value)
  defp apply_field("id", value, acc), do: Map.put(acc, :id, value)

  defp apply_field("retry", value, acc) do
    case ascii_digits?(value) and Integer.parse(value) do
      {ms, ""} -> Map.put(acc, :retry, ms)
      _ -> acc
    end
  end

  defp apply_field("data", value, acc) do
    case Map.get(acc, :data) do
      nil -> Map.put(acc, :data, value)
      existing -> Map.put(acc, :data, existing <> "\n" <> value)
    end
  end

  defp apply_field(_unknown, _value, acc), do: acc

  defp extract_events(buffer, events) do
    # Events are separated by blank lines (\n\n)
    case String.split(buffer, "\n\n", parts: 2) do
      [event_text, rest] ->
        case decode_event(event_text) do
          {:ok, event} ->
            extract_events(rest, events ++ [event])

          {:error, _} ->
            extract_events(rest, events)
        end

      [_incomplete] ->
        {events, buffer}
    end
  end

  # --- Stream parser state (MES-156) ---
  #
  # Kept below extract_events/2 so that the lines above it do not move: its
  # decode_event/1 call is cited by line elsewhere in the repository.

  # buffer: normalised (LF-only) text not yet ending in a blank line.
  # cr: the last byte fed was CR, so an LF opening the next chunk is its pair.
  # bom: the bytes held while they are still a proper prefix of a UTF-8 BOM at
  #      stream start, or :done once the start of the stream has been passed.
  @opaque parser :: %{
            buffer: binary(),
            cr: boolean(),
            bom: binary() | :done,
            last_id: binary()
          }

  @bom <<0xEF, 0xBB, 0xBF>>

  defp feed_chunk("", data), do: feed_chunk(new_parser(), data)

  defp feed_chunk(buffer, data) when is_binary(buffer),
    do: feed_chunk(%{new_parser() | bom: :done}, buffer <> data)

  # An empty chunk changes nothing, so a carried CR survives it.
  defp feed_chunk(parser, ""), do: {[], parser}

  defp feed_chunk(%{bom: :done} = parser, data), do: take_lines(parser, data)

  defp feed_chunk(%{bom: held} = parser, data) do
    case held <> data do
      @bom <> rest ->
        feed_chunk(%{parser | bom: :done}, rest)

      partial
      when byte_size(partial) < 3 and binary_part(@bom, 0, byte_size(partial)) == partial ->
        {[], %{parser | bom: partial}}

      other ->
        feed_chunk(%{parser | bom: :done}, other)
    end
  end

  defp take_lines(%{buffer: buffer, cr: cr} = parser, data) do
    data = if cr, do: drop_leading_lf(data), else: data
    {blocks, rest} = extract_events(buffer <> String.replace(data, ["\r\n", "\r"], "\n"), [])
    {events, last_id} = dispatch(blocks, parser.last_id, [])
    {events, %{parser | buffer: rest, cr: String.ends_with?(data, "\r"), last_id: last_id}}
  end

  # WHATWG dispatch: the last event ID persists across events until an `id`
  # field sets it again (G12), and a block with no `data` field is not
  # dispatched, though its `id` still takes effect (G11).
  defp dispatch([], last_id, events), do: {Enum.reverse(events), last_id}

  defp dispatch([block | blocks], last_id, events) do
    last_id = Map.get(block, :id, last_id)

    case block do
      %{data: _} -> dispatch(blocks, last_id, [stamp_id(block, last_id) | events])
      _no_data -> dispatch(blocks, last_id, events)
    end
  end

  defp stamp_id(event, ""), do: Map.delete(event, :id)
  defp stamp_id(event, last_id), do: Map.put(event, :id, last_id)

  # An `id` value containing NUL is ignored (G13); every other field goes
  # straight to apply_field/3.
  defp process_field("id", value, acc) do
    if String.contains?(value, <<0>>), do: acc, else: apply_field("id", value, acc)
  end

  defp process_field(field, value, acc), do: apply_field(field, value, acc)

  # `retry` takes ASCII digits only: no sign, no space (G14).
  defp ascii_digits?(""), do: false
  defp ascii_digits?(value), do: value |> :binary.bin_to_list() |> Enum.all?(&(&1 in ?0..?9))

  defp drop_leading_lf("\n" <> rest), do: rest
  defp drop_leading_lf(data), do: data
end
