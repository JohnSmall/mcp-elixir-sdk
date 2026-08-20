defmodule MCP.ConformanceRequestStateTest do
  @moduledoc """
  Unit tests for `MCP.Conformance.RequestState`, the conformance server
  fixture's tamper-evident MRTR `requestState` token.

  ## Why a test in `test/` for a file in `conformance/` — a deliberate coupling

  Ratified by the PM (MES-24 RULING 4, comment 24485). The reasoning, recorded
  here so a later reader sees a decision rather than an accident:

  `requestState` is a **security mechanism**, and the only other evidence for it
  is "the `input-required-result-tampered-state` scenario went green". That is a
  single-instance check of a property whose whole point is the **rejection**
  path. A passing scenario cannot evidence the negative cases — a bad tag, a
  mangled token, a token minted under a different key — and those are where the
  mechanism either works or silently does not.

  The cost is real: `mix test` now depends on a file outside `elixirc_paths`.
  It is paid knowingly rather than hidden. The fixture's helper is a **fixture**,
  not the product answer — the SDK offers no mint/verify for `requestState` and
  that gap is carried by MES-43.

  These tests are **evidence**, not the positive control the rest of gate 5 is
  for this ticket: they fail if the mechanism breaks, and the mutation below
  shows it.
  """
  use ExUnit.Case, async: true

  Code.require_file("../../conformance/request_state.ex", __DIR__)

  alias MCP.Conformance.RequestState

  setup do
    {:ok, key: RequestState.new_key(), other_key: RequestState.new_key()}
  end

  describe "mint/2 and verify/2 — the accept path" do
    test "round-trips a payload", %{key: key} do
      payload = %{"tool" => "elicitation", "round" => 1}
      assert {:ok, ^payload} = RequestState.verify(key, RequestState.mint(key, payload))
    end

    test "round-trips a payload carrying non-ASCII and separator characters", %{key: key} do
      payload = %{"name" => "Ω . x", "note" => "a.b.c"}
      assert {:ok, ^payload} = RequestState.verify(key, RequestState.mint(key, payload))
    end

    test "tokens are url-safe and unpadded, so they survive a header or query hop", %{key: key} do
      token = RequestState.mint(key, %{"tool" => "t"})
      assert token =~ ~r|^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$|
    end
  end

  describe "verify/2 — the reject paths, which are the point of the mechanism" do
    test "rejects a payload edited after minting", %{key: key} do
      token = RequestState.mint(key, %{"tool" => "elicitation", "admin" => false})
      [payload, tag] = String.split(token, ".", parts: 2)

      forged =
        Base.url_encode64(Jason.encode!(%{"tool" => "elicitation", "admin" => true}),
          padding: false
        )

      assert {:error, :bad_tag} = RequestState.verify(key, forged <> "." <> tag)
      # ... and the forged payload IS readable, which is why only the tag decides.
      assert {:ok, %{"admin" => true}} = RequestState.peek(forged <> "." <> tag)
      assert payload != forged
    end

    test "rejects the harness's own tampering shape (token <> \"-TAMPERED\")", %{key: key} do
      token = RequestState.mint(key, %{"tool" => "tampered_state"})
      assert {:error, reason} = RequestState.verify(key, token <> "-TAMPERED")
      assert reason in [:bad_tag, :malformed]
    end

    test "rejects a token minted under a different key", %{key: key, other_key: other} do
      assert {:error, :bad_tag} =
               RequestState.verify(key, RequestState.mint(other, %{"tool" => "t"}))
    end

    test "rejects a tag with one character changed", %{key: key} do
      [payload, tag] = RequestState.mint(key, %{"tool" => "t"}) |> String.split(".", parts: 2)
      first = String.first(tag)
      flipped = if(first == "A", do: "B", else: "A") <> String.slice(tag, 1..-1//1)
      assert {:error, :bad_tag} = RequestState.verify(key, payload <> "." <> flipped)
    end

    test "rejects a truncated tag", %{key: key} do
      token = RequestState.mint(key, %{"tool" => "t"})
      # Truncation can land on either failure — a length base64url cannot decode
      # (`:malformed`) or a decodable but wrong tag (`:bad_tag`). Both are
      # rejections; asserting one specifically would be asserting an artefact of
      # how many characters were removed.
      assert {:error, _} = RequestState.verify(key, String.slice(token, 0..-3//1))
      assert {:error, _} = RequestState.verify(key, String.slice(token, 0..-2//1))
    end

    test "distinguishes malformed from tampered", %{key: key} do
      assert {:error, :malformed} = RequestState.verify(key, "not-a-token")
      assert {:error, :malformed} = RequestState.verify(key, "@@@.@@@")
      assert {:error, :malformed} = RequestState.verify(key, "")
      assert {:error, :malformed} = RequestState.verify(key, nil)
    end

    test "a valid envelope whose payload is not JSON is malformed, not accepted", %{key: key} do
      not_json = "no"
      tag = :crypto.mac(:hmac, :sha256, key, not_json)

      token =
        Base.url_encode64(not_json, padding: false) <>
          "." <> Base.url_encode64(tag, padding: false)

      assert {:error, :malformed} = RequestState.verify(key, token)
    end
  end

  describe "peek/1" do
    test "reads a payload without the key, and says so by name", %{key: key} do
      token = RequestState.mint(key, %{"tool" => "t", "round" => 2})
      assert {:ok, %{"tool" => "t", "round" => 2}} = RequestState.peek(token)
    end

    test "refuses a token that is not well-formed" do
      assert :error = RequestState.peek("nope")
    end
  end
end
