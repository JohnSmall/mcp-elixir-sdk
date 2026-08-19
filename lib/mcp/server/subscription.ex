defmodule MCP.Server.Subscription do
  @moduledoc """
  A live `subscriptions/listen` subscription: its id, the filter the server
  agreed to honour, and the acknowledgment to put on the wire first.

  `MCP.Server.Dispatch` builds one of these and hands it to the driver as
  `{:stream, subscription, state}`. The driver holds the stream open and calls
  `frame/3` for every notification offered to it.

  ## Why the filter is enforced here rather than in the emitter

  `frame/3` is the single place a message can become a stream frame, for every
  transport. Both of the spec's stream MUST NOTs therefore hold by
  construction rather than by handler discipline:

    * **Never an unrequested type** (subscriptions.mdx:14-16) — a method with
      no key in the honoured filter is refused.
    * **Never a request-scoped type** (streamable-http.mdx:130-134) —
      `notifications/progress` and `notifications/message` are refused by the
      *same* rule, because no `SubscriptionFilter` key maps to them, so they
      can never enter an honoured set in the first place. There is no separate
      check to forget.

  A handler that emits the wrong thing gets it dropped; it cannot leak onto the
  wire by being careless. Sprint 3's cross-request identity leak (evidence-log
  I10) came from plumbing that trusted its callers, which is why this does not.

  ## Lifetime

  The subscription's id is the JSON-RPC id of the `subscriptions/listen`
  request that opened it (schema.ts:1330-1334), so it is unique per client
  connection and needs no separate allocation — and on stdio, where every
  subscription shares one channel, it is what lets a client demultiplex
  (subscriptions.mdx:107-114).
  """

  alias MCP.Protocol.Messages.Notification
  alias MCP.Protocol.Messages.Subscriptions

  @enforce_keys [:id, :honoured, :ack]
  defstruct [:id, :honoured, :ack, :allowed]

  @type t :: %__MODULE__{
          id: term(),
          honoured: Subscriptions.filter(),
          ack: map(),
          allowed: MapSet.t(String.t())
        }

  @doc """
  Builds a subscription from its request id and the honoured filter.

  The acknowledgment and the allowed-method set are derived here, once, from
  the same `honoured` value — so the message that tells the client what it will
  receive and the rule that decides what it receives cannot disagree.
  """
  @spec new(term(), Subscriptions.filter()) :: t()
  def new(id, honoured) do
    %__MODULE__{
      id: id,
      honoured: honoured,
      ack: Subscriptions.acknowledgment(id, honoured),
      allowed: Subscriptions.allowed_methods(honoured)
    }
  end

  @doc """
  Turns a notification into a stream frame, or refuses it.

  Returns `{:ok, wire_map}` with this subscription's id stamped into
  `params._meta` (schema.ts:120-133), or `:drop`.

  A `notifications/resources/updated` is additionally checked against the
  honoured URI list: opting in to one resource does not opt in to every
  resource. The URI is compared exactly, and is read under **either key
  style** — `%{"uri" => …}` and `%{uri: …}` are the same notification, because
  they encode to the same wire bytes and nothing else about a notification
  cares which one a handler wrote. The schema notes an update MAY concern
  a sub-resource of the one subscribed to (schema.ts:1411-1413); resolving that
  containment is resource-scheme-specific knowledge the SDK does not have, so a
  handler wanting sub-resource semantics emits the URI the client subscribed
  to. Stated here because an unstated narrowing is the failure mode, not the
  narrowing itself.
  """
  @spec frame(t(), String.t(), map()) :: {:ok, map()} | :drop
  def frame(%__MODULE__{} = sub, method, params) do
    if MapSet.member?(sub.allowed, method) and uri_allowed?(sub, method, params) do
      {:ok,
       method
       |> Notification.new(params)
       |> encode()
       |> Subscriptions.stamp(sub.id)}
    else
      :drop
    end
  end

  @typedoc """
  Why a subscription stream ended.

    * `:peer_closed` — the client went away (closing the stream is cancellation,
      streamable-http.mdx:236-243).
    * `:lifetime_expired` — `:max_stream_lifetime` elapsed.
    * `:shutdown` — the server tore the subscription down on its own initiative.
  """
  @type close_reason :: :peer_closed | :lifetime_expired | :shutdown

  @doc """
  What, if anything, to write when a stream ends.

  A **server-initiated** teardown SHOULD send the listen response before closing
  (subscriptions.mdx:128-153). A client that has gone away gets **nothing** —
  and that asymmetry is load-bearing, not cosmetic: response-then-close versus
  close-with-no-response is the only signal by which a client can tell a clean
  end from a drop. The spec independently forbids sending anything further for a
  cancelled request (streamable-http.mdx:236-243).

  The decision lives here, as a function of the reason alone, because it is the
  one part of the asymmetry a test can actually observe. End to end it cannot
  be: when the peer is fully gone the write would simply fail, so "sent nothing"
  and "tried and failed" look identical from outside. Making the choice explicit
  and total is what turns a MUST NOT into something checkable rather than
  something merely believed.
  """
  @spec close_frame(t(), close_reason()) :: {:send, map()} | :none
  def close_frame(%__MODULE__{}, :peer_closed), do: :none
  def close_frame(%__MODULE__{id: id}, _reason), do: {:send, Subscriptions.close_response(id)}

  defp uri_allowed?(%__MODULE__{} = sub, method, params) do
    if method == MCP.Protocol.Methods.resources_updated() do
      uris = Map.get(sub.honoured, Subscriptions.resource_subscriptions_key(), [])
      is_list(uris) and uri_of(params) in uris
    else
      true
    end
  end

  # The URI under either key style (review F6). This used to read only
  # `Map.get(params, "uri")`, which made ONE notification type silently
  # key-sensitive: an atom-keyed `%{uri: …}` was dropped here while
  # `ToolContext.stream/3` answered `:ok`, and every other notification type
  # was indifferent because `Jason` encodes both key styles to identical wire
  # bytes. That asymmetry is the footgun, not the strictness — so the fix is to
  # make the filter as indifferent as the encoder rather than to reject atom
  # keys on one type. An emission that is not delivered must not be reported as
  # delivered.
  #
  # `fetch` then `get`, not `get(params, "uri") || get(params, :uri)`: a URI is
  # never a falsy value, but a rule written with `||` stops being about
  # presence the moment somebody reuses it for a field that can be.
  defp uri_of(params) do
    case Map.fetch(params, "uri") do
      {:ok, uri} -> uri
      :error -> Map.get(params, :uri)
    end
  end

  defp encode(struct), do: Jason.decode!(Jason.encode!(struct))
end
