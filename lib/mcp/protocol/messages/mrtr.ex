defmodule MCP.Protocol.Messages.MRTR do
  @moduledoc """
  Multi Round-Trip Requests (MRTR) for the MCP 2026-07-28 stateless core
  (SEP-2322).

  The stateless core removes the held-open SSE server→client request path
  (sampling/elicitation). Instead, when a server handler needs client-provided
  input mid-request, it returns an **`InputRequiredResult`** — a normal
  JSON-RPC *result* with `resultType: "input_required"` — carrying the input
  requests and an opaque `requestState` continuation token. The client fulfils
  the inputs and **retries the original request**, passing back `inputResponses`
  and `requestState` (SEP-2260 is satisfied by construction: the input-required
  reply *is* the response to an active client request).

  ## Wire shape — verified against the pinned draft schema

  Commit `7634684382c3d14cf7e9f14073fe40a2d8ace3fa`, `schema/draft/schema.ts`:

    * `Result` (schema.ts:658) requires `resultType: ResultType`
      (`"complete" | "input_required" | string`, schema.ts:651).
    * `InputRequiredResult extends Result` (schema.ts:1253) adds
      **`inputRequests?: InputRequests`** and **`requestState?: string`**
      (schema.ts:1268); at least one must be present.
    * On retry the client sends `InputResponseRequestParams` (schema.ts:1284)
      carrying **`inputResponses?`** and **`requestState?`** on the request
      **params** (not `_meta`).
  """

  @result_type "input_required"

  @doc "The `resultType` marker for an input-required result."
  def result_type, do: @result_type

  @doc """
  Builds the wire map for an `InputRequiredResult`.

  `input_requests` is the list of input-request objects (opaque here);
  `request_state` is the opaque continuation token the client echoes on retry.
  At least one of the two is emitted.
  """
  @spec input_required(list() | nil, binary() | nil) :: map()
  def input_required(input_requests, request_state) do
    base = %{"resultType" => @result_type}
    base = if input_requests, do: Map.put(base, "inputRequests", input_requests), else: base
    if request_state, do: Map.put(base, "requestState", request_state), else: base
  end

  @doc """
  Extracts the MRTR continuation from a request's `params`, or `nil` when the
  request is a first attempt.

  Returns `%{request_state: binary(), responses: term()}` when `requestState`
  is present.
  """
  @spec continuation_from_params(map() | nil) ::
          %{request_state: binary(), responses: term()} | nil
  def continuation_from_params(params) when is_map(params) do
    case Map.get(params, "requestState") do
      nil -> nil
      state -> %{request_state: state, responses: Map.get(params, "inputResponses")}
    end
  end

  def continuation_from_params(_), do: nil
end
