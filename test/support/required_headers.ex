defmodule MCP.Test.RequiredHeaders do
  @moduledoc """
  The Streamable HTTP standard request headers a message requires —
  `MCP-Protocol-Version`, `Mcp-Method` and, for a name-bearing method,
  `Mcp-Name` (`streamable-http.mdx:252-253`, `:280-293`) — derived by the SDK
  client's own `build_headers/2`, so a test posts exactly what our client
  sends on the wire.
  """

  alias MCP.Transport.StreamableHTTP.Client

  @required ~w(mcp-protocol-version mcp-method mcp-name)

  @doc "The required headers for `message`, as `{name, value}` pairs."
  @spec for_message(map()) :: [{String.t(), String.t()}]
  def for_message(message) do
    %Client{protocol_version: "2026-07-28"}
    |> Client.build_headers(message)
    |> Enum.filter(fn {k, _} -> k in @required end)
  end

  @doc "As `for_message/1`, for a JSON-encoded body."
  @spec for_body(String.t()) :: [{String.t(), String.t()}]
  def for_body(body), do: body |> Jason.decode!() |> for_message()

  @doc """
  `explicit` with the required headers for `message` placed first, so an
  explicit header of the same name — a deliberate mismatch — is applied last.
  """
  @spec merge(map(), [{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def merge(message, explicit), do: for_message(message) ++ explicit

  @doc "Puts `message`'s required headers and `content-type: application/json` on a test conn."
  @spec put_json(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def put_json(conn, message) do
    [{"content-type", "application/json"} | for_message(message)]
    |> Enum.reduce(conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
  end

  @doc "The required headers for `body` as raw HTTP/1.1 lines, `Content-Type: application/json` first."
  @spec raw(String.t()) :: String.t()
  def raw(body) do
    Enum.map_join([{"Content-Type", "application/json"} | for_body(body)], fn {k, v} ->
      "#{k}: #{v}\r\n"
    end)
  end

  @doc "`Req.post!/2` with `body`'s required headers appended to `opts[:headers]`."
  @spec post!(String.t(), keyword()) :: Req.Response.t()
  def post!(url, opts) do
    body = Keyword.fetch!(opts, :body)
    Req.post!(url, Keyword.update(opts, :headers, for_body(body), &(&1 ++ for_body(body))))
  end
end
