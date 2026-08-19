defmodule MCP.Protocol.Messages.Subscriptions do
  @moduledoc """
  Wire shapes for `subscriptions/listen` — the 2026-07-28 replacement for both
  the removed GET SSE endpoint and the removed `resources/subscribe` /
  `resources/unsubscribe` pair.

  Pure functions over plain wire maps: nothing here talks to a transport, holds
  a stream, or knows what a driver is. `MCP.Server.Subscription` is the
  server-side counterpart that decides what a live stream may carry.

  ## Provenance (A4)

  Derived from the pinned schema at commit
  `5f5440bb26a62e2cf3440b92da5a667efa03b267`, path `schema/2026-07-28/schema.ts`
  — symbol names given alongside line numbers so a citation survives a shift:

    * `SubscriptionFilter` :1270-1288 — `toolsListChanged` :1274,
      `promptsListChanged` :1278, `resourcesListChanged` :1282,
      `resourceSubscriptions` :1287.
    * `SubscriptionsListenRequestParams` :1295-1302 — `notifications` :1301.
    * `SubscriptionsListenRequest` :1313-1317 — method literal :1315.
    * `SubscriptionsAcknowledgedNotificationParams` :1371-1379 —
      `notifications` :1378 carries "the subset of requested notification types
      the server agreed to honor" :1372-1377.
    * `SubscriptionsAcknowledgedNotification` :1398-1401, with the
      first-message and per-subscription-id ordering rule at :1386-1392.
    * `SubscriptionsListenResultMetaObject` :1326-1335 — required
      `subscriptionId` :1334.
    * `SubscriptionsListenResult` :1349-1351; envelope
      `SubscriptionsListenResultResponse` :1362-1364; `resultType` required by
      the `Result` base :223-236 (field at :234).
    * `NotificationMetaObject` :120-133 — `subscriptionId` key at :133.

  Normative prose at the same commit:
  `docs/specification/2026-07-28/basic/patterns/subscriptions.mdx` (opt-in
  :14-16, acknowledgment :54-62, graceful closure :128-153) and
  `.../transports/streamable-http.mdx` (request-scoped notifications never on
  the listen stream :130-134).

  ## The filter is a wire map, not a struct

  `SubscriptionFilter` is carried as its wire map with camelCase string keys —
  the same convention the rest of this SDK uses for handler-facing data (tool
  arguments, resources, prompts). Keeping it in wire shape means the honoured
  subset, the acknowledgment's `notifications`, and the set the stream enforces
  are all literally the same value, so "the ack reflects what the stream will
  actually do" needs no translation step in which they could drift apart.

  A requested flag is normalised to **presence**: `"toolsListChanged" => false`
  is dropped, because "explicitly requested" (:1272-1273) and "requested and
  set to false" are the same thing — nothing may be sent either way — and
  collapsing them lets every downstream check be a key lookup.
  """

  alias MCP.Protocol.Messages.Notification
  alias MCP.Protocol.Meta
  alias MCP.Protocol.Methods

  @tools_list_changed "toolsListChanged"
  @prompts_list_changed "promptsListChanged"
  @resources_list_changed "resourcesListChanged"
  @resource_subscriptions "resourceSubscriptions"

  @flag_keys [@tools_list_changed, @prompts_list_changed, @resources_list_changed]
  @filter_keys @flag_keys ++ [@resource_subscriptions]

  @typedoc "A `SubscriptionFilter` in wire shape, restricted to known keys."
  @type filter :: %{optional(String.t()) => boolean() | [String.t()]}

  @doc "The four `SubscriptionFilter` keys (schema.ts:1270-1288)."
  @spec filter_keys() :: [String.t()]
  def filter_keys, do: @filter_keys

  @doc "The `SubscriptionFilter` key for per-URI resource watching."
  @spec resource_subscriptions_key() :: String.t()
  def resource_subscriptions_key, do: @resource_subscriptions

  @doc """
  Maps a `SubscriptionFilter` key to the notification method it opts in to.

  The mapping is the schema's own (`@link` targets at :1273, :1277, :1281,
  :1286), and it is total over `filter_keys/0` — which is what makes
  `allowed_methods/1` an exhaustive statement of what a stream may carry.
  """
  @spec method_for(String.t()) :: String.t() | nil
  def method_for(@tools_list_changed), do: Methods.tools_list_changed()
  def method_for(@prompts_list_changed), do: Methods.prompts_list_changed()
  def method_for(@resources_list_changed), do: Methods.resources_list_changed()
  def method_for(@resource_subscriptions), do: Methods.resources_updated()
  def method_for(_), do: nil

  @doc """
  Parses and normalises `params.notifications` from a `subscriptions/listen`
  request.

  `notifications` is **required** (:1301 — no `?`), even though every field
  inside it is optional. An empty object is legal and means "subscribe to
  nothing"; an absent one is a malformed request. Returns:

    * `{:ok, filter}` — normalised to known keys, `true` flags only, and a
      `resourceSubscriptions` list of binaries with duplicates removed.
    * `{:error, :missing_notifications}` — no `notifications` key.
    * `{:error, :invalid_notifications}` — present but not an object.

  Unknown keys are dropped rather than rejected: an unrecognised opt-in cannot
  be honoured, and dropping it means the acknowledgment (which reports only
  what is honoured) tells the client so.
  """
  @spec parse_filter(map() | nil) ::
          {:ok, filter()} | {:error, :missing_notifications | :invalid_notifications}
  def parse_filter(params) when is_map(params) do
    case Map.fetch(params, "notifications") do
      {:ok, requested} when is_map(requested) -> {:ok, normalise(requested)}
      {:ok, _not_an_object} -> {:error, :invalid_notifications}
      :error -> {:error, :missing_notifications}
    end
  end

  def parse_filter(_params), do: {:error, :missing_notifications}

  defp normalise(requested) do
    flags =
      for key <- @flag_keys, Map.get(requested, key) == true, into: %{}, do: {key, true}

    case Map.get(requested, @resource_subscriptions) do
      uris when is_list(uris) ->
        case uris |> Enum.filter(&is_binary/1) |> Enum.uniq() do
          [] -> flags
          kept -> Map.put(flags, @resource_subscriptions, kept)
        end

      _ ->
        flags
    end
  end

  @doc """
  Narrows `requested` to the keys present in `permitted`.

  Used to compose the honoured subset out of three independent narrowings —
  what the client asked for, what the handler agreed to, and what the server
  advertises — so that no single one of them can widen it. For
  `resourceSubscriptions` the narrowing is per-URI, not all-or-nothing: a
  handler may honour two of three requested URIs.
  """
  @spec intersect(filter(), filter()) :: filter()
  def intersect(requested, permitted) do
    flags =
      for key <- @flag_keys,
          Map.get(requested, key) == true and Map.get(permitted, key) == true,
          into: %{},
          do: {key, true}

    requested_uris = Map.get(requested, @resource_subscriptions, [])
    permitted_uris = Map.get(permitted, @resource_subscriptions, [])

    case Enum.filter(requested_uris, &(&1 in permitted_uris)) do
      [] -> flags
      kept -> Map.put(flags, @resource_subscriptions, kept)
    end
  end

  @doc """
  The filter a set of advertised server capabilities permits.

  Turns `ServerCapabilities` back into a `SubscriptionFilter` so the honoured
  subset can be intersected with it — which is what makes "the acknowledgment
  never claims more than `server/discover` advertised" a property of
  construction rather than a rule someone has to remember.
  """
  @spec permitted_by(map() | struct() | nil) :: filter()
  def permitted_by(nil), do: %{}

  def permitted_by(capabilities) do
    %{}
    |> put_if(@tools_list_changed, list_changed?(Map.get(capabilities, :tools)))
    |> put_if(@prompts_list_changed, list_changed?(Map.get(capabilities, :prompts)))
    |> put_if(@resources_list_changed, list_changed?(Map.get(capabilities, :resources)))
    |> then(fn filter ->
      if subscribe?(Map.get(capabilities, :resources)) do
        # Advertising `resources.subscribe` permits the KEY; which URIs are
        # honoured is a per-request, per-principal decision the handler makes.
        # `:any` is the identity element for the per-URI narrowing below.
        Map.put(filter, @resource_subscriptions, :any)
      else
        filter
      end
    end)
  end

  defp list_changed?(nil), do: false
  defp list_changed?(cap), do: Map.get(cap, :list_changed) == true

  defp subscribe?(nil), do: false
  defp subscribe?(cap), do: Map.get(cap, :subscribe) == true

  defp put_if(map, _key, false), do: map
  defp put_if(map, key, true), do: Map.put(map, key, true)

  @doc """
  Narrows `requested` by an advertised-capability filter from `permitted_by/1`.

  Distinct from `intersect/2` only in its treatment of `resourceSubscriptions`:
  a capability advertisement permits the key wholesale (`:any`), whereas a
  handler's honoured subset names specific URIs.
  """
  @spec restrict_to_advertised(filter(), filter()) :: filter()
  def restrict_to_advertised(requested, advertised) do
    flags =
      for key <- @flag_keys,
          Map.get(requested, key) == true and Map.get(advertised, key) == true,
          into: %{},
          do: {key, true}

    case {Map.get(requested, @resource_subscriptions),
          Map.get(advertised, @resource_subscriptions)} do
      {uris, :any} when is_list(uris) and uris != [] ->
        Map.put(flags, @resource_subscriptions, uris)

      _ ->
        flags
    end
  end

  @doc """
  The set of notification methods a stream carrying `filter` may deliver.

  Everything not in this set is refused by `MCP.Server.Subscription.frame/3`,
  which is how BOTH stream MUST NOTs hold by construction: an unrequested type
  is absent because the client did not ask for it (subscriptions.mdx:14-16),
  and a request-scoped type — `notifications/progress`, `notifications/message`
  — is absent because no `SubscriptionFilter` key maps to it, so it can never
  enter an honoured set at all (streamable-http.mdx:130-134).
  """
  @spec allowed_methods(filter()) :: MapSet.t(String.t())
  def allowed_methods(filter) do
    filter
    |> Map.keys()
    |> Enum.map(&method_for/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @doc """
  Builds the `notifications/subscriptions/acknowledged` wire map.

  MUST be the first message the server sends carrying this subscription's id
  (schema.ts:1386-1392), and its `notifications` reports the honoured subset —
  not what was requested.
  """
  @spec acknowledgment(term(), filter()) :: map()
  def acknowledgment(subscription_id, honoured) do
    Methods.subscriptions_acknowledged()
    |> Notification.new(%{
      "_meta" => %{Meta.subscription_id_key() => subscription_id},
      "notifications" => honoured
    })
    |> encode()
  end

  @doc """
  Builds the `SubscriptionsListenResultResponse` that signals a **graceful**
  end of the subscription (schema.ts:1349-1351, :1362-1364).

  The result is "otherwise empty" (:1343) — meaning empty apart from the two
  fields the schema requires: `resultType` (`Result` base :234) and the
  `subscriptionId` `_meta` (:1334). It is deliberately NOT `{}`; the pinned
  example `SubscriptionsListenResultResponse/listen-closed-response.json` is
  pinned in a test so a later reader does not "simplify" it away.

  Sent only on a server-initiated teardown. An abrupt transport close carries
  **no** response, and that asymmetry is exactly how a client tells a clean
  close from a drop (subscriptions.mdx:128-153) — so nothing may send this
  after the peer has gone.
  """
  @spec close_response(term()) :: map()
  def close_response(subscription_id) do
    %{
      "jsonrpc" => "2.0",
      "id" => subscription_id,
      "result" => %{
        "resultType" => "complete",
        "_meta" => %{Meta.subscription_id_key() => subscription_id}
      }
    }
  end

  @doc """
  Stamps a notification wire map with this stream's `subscriptionId`.

  Required on **every** message delivered via a listen stream
  (schema.ts:120-133), so clients can demultiplex concurrent subscriptions
  sharing one channel (subscriptions.mdx:107-114).
  """
  @spec stamp(map(), term()) :: map()
  def stamp(notification, subscription_id) do
    params = Map.get(notification, "params") || %{}

    meta =
      params
      |> Map.get("_meta", %{})
      |> Map.put(Meta.subscription_id_key(), subscription_id)

    Map.put(notification, "params", Map.put(params, "_meta", meta))
  end

  defp encode(struct), do: Jason.decode!(Jason.encode!(struct))
end
