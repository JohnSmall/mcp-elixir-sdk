defmodule MCP.Conformance.RequestState do
  @moduledoc """
  Tamper-evident `requestState` continuation tokens for the conformance
  server fixture (SEP-2322 / MRTR).

  ## Why this exists here and not in the SDK

  The 2026-07-28 core is **stateless**: any request must be serviceable by any
  instance behind a round-robin balancer (Critical rule 2). So an MRTR
  continuation cannot live in handler state — it has to ride entirely inside
  the opaque `requestState` string the client echoes back. And the
  `input-required-result-tampered-state` scenario requires the server to
  **detect** a modified one, which a self-contained token that is not
  authenticated cannot do.

  `MCP.Protocol.Messages.MRTR` offers `input_required/2` and
  `continuation_from_params/1` and **nothing for minting or verifying** such a
  token, so every stateless MRTR server must invent this. That is recorded as
  a handler-shaped finding against the SDK (MES-24 adversarial item 4b, carried
  by MES-43); this module is the **fixture's** answer to it, not the product
  answer, and it is deliberately minimal.

  ## Shape

      base64url(payload_json) <> "." <> base64url(hmac_sha256(key, payload_json))

  The key is minted once at launch (`new_key/0`) and never leaves the server
  process, so a token is unforgeable by a client and verifiable by any request
  handled by the same launch. A multi-instance deployment would share the key
  out of band; the fixture is single-instance and says so rather than implying
  a distribution story it does not have.

  ## What this is NOT

  Not encryption: the payload is signed, not hidden, and `peek/1` will read it
  without the key. The scenario asks for integrity, not confidentiality, and a
  token whose contents are readable is the honest description of what an HMAC
  buys. Nothing secret goes in it.
  """

  @separator "."

  @doc "Mints a fresh 256-bit signing key. Called once per server launch."
  @spec new_key() :: binary()
  def new_key, do: :crypto.strong_rand_bytes(32)

  @doc """
  Mints a token carrying `payload` (any JSON-encodable term).

  The returned string is what a handler puts in an `InputRequiredResult`'s
  `requestState`.
  """
  @spec mint(binary(), term()) :: binary()
  def mint(key, payload) when is_binary(key) do
    json = Jason.encode!(payload)
    encode(json) <> @separator <> encode(tag(key, json))
  end

  @doc """
  Verifies a token and returns its payload.

  Returns `{:error, :malformed}` when the token is not two base64url segments
  separated by a `.`, and `{:error, :bad_tag}` when the payload does not match
  its tag under `key` — the two are distinguished because they are different
  bugs (a client that mangled the token vs. one that edited it).

  The tag comparison is constant-time (`:crypto.hash_equals/2`).
  """
  @spec verify(binary(), term()) :: {:ok, term()} | {:error, :malformed | :bad_tag}
  def verify(key, token) when is_binary(key) and is_binary(token) do
    with [payload_b64, tag_b64] <- String.split(token, @separator, parts: 2),
         {:ok, json} <- decode(payload_b64),
         {:ok, presented} <- decode(tag_b64),
         {:ok, payload} <- json_decode(json) do
      expected = tag(key, json)

      if byte_size(presented) == byte_size(expected) and
           :crypto.hash_equals(presented, expected) do
        {:ok, payload}
      else
        {:error, :bad_tag}
      end
    else
      _ -> {:error, :malformed}
    end
  end

  def verify(_key, _token), do: {:error, :malformed}

  @doc """
  Reads a token's payload **without verifying it**.

  Exists so a caller can say plainly that it is doing so; `verify/2` is what
  every code path in the fixture actually uses. Returns `:error` on a token
  that is not well-formed.
  """
  @spec peek(binary()) :: {:ok, term()} | :error
  def peek(token) when is_binary(token) do
    with [payload_b64, _tag] <- String.split(token, @separator, parts: 2),
         {:ok, json} <- decode(payload_b64),
         {:ok, payload} <- json_decode(json) do
      {:ok, payload}
    else
      _ -> :error
    end
  end

  def peek(_), do: :error

  defp tag(key, json), do: :crypto.mac(:hmac, :sha256, key, json)

  defp encode(bin), do: Base.url_encode64(bin, padding: false)

  defp decode(bin), do: Base.url_decode64(bin, padding: false)

  defp json_decode(json) do
    case Jason.decode(json) do
      {:ok, payload} -> {:ok, payload}
      {:error, _} -> :error
    end
  end
end
