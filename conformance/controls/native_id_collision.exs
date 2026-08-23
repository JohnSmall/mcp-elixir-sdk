#!/usr/bin/env elixir
# MES-77 NATIVE-ID COLLISION CONTROL — the demonstration behind AC4.
#
#     mix run conformance/controls/native_id_collision.exs
#
# ## What this exists to establish
#
# MES-77 changes a token scheme. A scheme change is the easiest kind of work to
# assert and the easiest to get wrong invisibly: both schemes emit strings, both
# look plausible in a document, and nothing about reading them tells you which
# one loses information. So the old scheme is RUN and SEEN TO FAIL here, on the
# real bucket-1 claims, before the new one is credited with fixing anything.
#
# The measure is A1's own and this document's: ROWS LOST — rows that disappear
# when the projection is deduplicated. `match-relation.md` §5 states every other
# key-projection result in that unit, so the two schemes are compared in the unit
# the artefact already uses rather than in one invented for the comparison.
#
# ## The claims are REAL, not illustrative
#
# All seven are A4's, read from `docs/conformance/cg-reconciliation.md` §5 at the
# tip this runs against — four from CG2, three from CG7. Two synthesised claims
# would demonstrate the arithmetic of deduplication and nothing about this tree.
#
# ## What it does NOT establish
#
# That the seven claims are the right seven, or that CG2 and CG7 are the only
# CGs with bucket-1 members — those are A4's measurements (MES-69), re-verified
# under MES-77's AC2, not re-derived here. This file establishes exactly one
# thing: that the ratified slot cannot distinguish claims the new slot can.
#
# ## S7-2 discipline, and its bound
#
# This control MUTATES NOTHING. It builds tokens in memory and reads the
# manifest read-only, so the restore-per-run rule does not bind. The manifest's
# md5 is recorded before and after anyway, so "did not mutate" is a measurement
# rather than an assurance — the rule is stated as not binding, then verified
# where verification is free.

alias MCP.Conformance.MatchKey

manifest_path = "docs/conformance/in-scope-2026-07-28.json"

md5 = fn path ->
  path |> File.read!() |> then(&:crypto.hash(:md5, &1)) |> Base.encode16(case: :lower)
end

md5_before = md5.(manifest_path)

# A4's seven, cg-reconciliation.md §5. {origin_id, claim_slug, reason_slug}
claims = [
  {"CG2", "inbound-parse", "no-oc-scenario"},
  {"CG2", "absent-yields-nil", "no-oc-scenario"},
  {"CG2", "unknown-not-a-fault", "no-oc-scenario"},
  {"CG2", "outbound-meta", "no-oc-scenario"},
  {"CG7", "annotated-number-excluded", "no-oc-fixture-case"},
  {"CG7", "integer-safe-range", "no-oc-fixture-case"},
  {"CG7", "static-reachability", "no-oc-fixture-case"}
]

rows = manifest_path |> File.read!() |> Jason.decode!() |> MatchKey.rows_from_manifest()

banner = fn text ->
  IO.puts("\n" <> text)
  IO.puts(String.duplicate("-", String.length(text)))
end

IO.puts("MES-77 AC4 — native-id collision control")
IO.puts("manifest md5 before: #{md5_before}   (#{length(rows)} rows)")

# --------------------------------------------------------------------------
# OLD — §6 as ratified: "the CG number in the <native-id> slot".
# --------------------------------------------------------------------------
banner.("OLD SCHEME — the CG number in the native-id slot")

old_tokens =
  Enum.map(claims, fn {origin_id, _claim_slug, reason} ->
    {:ok, token} = MatchKey.none(reason, origin_id)
    token
  end)

Enum.zip(claims, old_tokens)
|> Enum.each(fn {{_o, claim_slug, _r}, token} ->
  IO.puts("  #{String.pad_trailing(claim_slug, 26)} -> #{token}")
end)

old_distinct = old_tokens |> Enum.uniq() |> length()
old_lost = length(old_tokens) - old_distinct

IO.puts(
  "\n  #{length(claims)} claims -> #{old_distinct} distinct tokens    #{old_lost} ROWS LOST"
)

# The three CG7 claims are byte-identical, so the guard cannot separate them.
cg7_old = old_tokens |> Enum.slice(4, 3)
IO.puts("  the 3 CG7 tokens byte-identical: #{length(Enum.uniq(cg7_old)) == 1}")

cg7_states = Enum.map(cg7_old, &MatchKey.guard_state(&1, rows))
IO.puts("  guard_state/2 returns one answer for all three: #{length(Enum.uniq(cg7_states)) == 1}")
[state | _] = cg7_states
IO.puts("    #{inspect(state)}")

# THE RED HALF — the register-assembly check, driven by the old scheme.
old_index =
  claims
  |> Enum.zip(old_tokens)
  |> Enum.map(fn {{_o, claim_slug, _r}, token} ->
    {:ok, %{native_id: native_id}} = MatchKey.decode(token)
    {native_id, claim_slug}
  end)
  |> MatchKey.declared_claim_index()

IO.puts("\n  declared_claim_index/1 -> #{inspect(old_index)}")

old_red? = match?({:error, {:native_id_names_two_claims, _, _}}, old_index)
IO.puts("  OLD SCHEME REFUSED: #{old_red?}")

# The refusal above names CG2 because it is lexically first. AC4 names CG7, so
# CG7 is driven ALONE — otherwise "the old scheme cannot distinguish two CG7
# members" would rest on a refusal that fired for a different CG.
cg7_old_index =
  claims
  |> Enum.zip(old_tokens)
  |> Enum.filter(fn {{origin_id, _c, _r}, _t} -> origin_id == "CG7" end)
  |> Enum.map(fn {{_o, claim_slug, _r}, token} ->
    {:ok, %{native_id: native_id}} = MatchKey.decode(token)
    {native_id, claim_slug}
  end)
  |> MatchKey.declared_claim_index()

IO.puts("  CG7 alone -> #{inspect(cg7_old_index)}")
cg7_old_red? = match?({:error, {:native_id_names_two_claims, "CG7", _}}, cg7_old_index)
IO.puts("  CG7 ALONE REFUSED, naming CG7: #{cg7_old_red?}")

# --------------------------------------------------------------------------
# NEW — the claim-level slot.
# --------------------------------------------------------------------------
banner.("NEW SCHEME — <origin-id>-<claim-slug>")

new_tokens =
  Enum.map(claims, fn {origin_id, claim_slug, reason} ->
    {:ok, token} = MatchKey.none(reason, origin_id, claim_slug)
    token
  end)

Enum.each(new_tokens, &IO.puts("  #{&1}"))

new_distinct = new_tokens |> Enum.uniq() |> length()
new_lost = length(new_tokens) - new_distinct

IO.puts(
  "\n  #{length(claims)} claims -> #{new_distinct} distinct tokens    #{new_lost} ROWS LOST"
)

new_index =
  claims
  |> Enum.zip(new_tokens)
  |> Enum.map(fn {{_o, claim_slug, _r}, token} ->
    {:ok, %{native_id: native_id}} = MatchKey.decode(token)
    {native_id, claim_slug}
  end)
  |> MatchKey.declared_claim_index()

new_ok? = match?({:ok, _}, new_index)
{:ok, index} = new_index
IO.puts("  declared_claim_index/1 -> {:ok, index of #{map_size(index)}}   accepted: #{new_ok?}")

# AC1's round-trip, on the new form: builder -> decode/1 -> identical native id.
round_trips? =
  Enum.zip(claims, new_tokens)
  |> Enum.all?(fn {{origin_id, claim_slug, reason}, token} ->
    {:ok, expected} = MatchKey.native_id(origin_id, claim_slug)
    {:ok, decoded} = MatchKey.decode(token)
    decoded.native_id == expected and decoded.reason == reason and decoded.kind == :none
  end)

IO.puts("  builder -> decode/1 round-trips all #{length(claims)}: #{round_trips?}")

# Every new token is still state 3 — the scheme change must not move the guard.
new_states = Enum.map(new_tokens, &MatchKey.guard_state(&1, rows))
all_state_3? = Enum.all?(new_states, &match?({:declared_unmatched, _}, &1))
IO.puts("  all #{length(claims)} still guard to state 3: #{all_state_3?}")

# --------------------------------------------------------------------------
# NEGATIVE CONTROLS — a scheme that refuses nothing has proved nothing.
# --------------------------------------------------------------------------
banner.("NEGATIVE CONTROLS — native_id/2 must REFUSE, not emit an unparseable token")

negatives = [
  {"empty claim slug", fn -> MatchKey.native_id("CG7", "") end},
  {"nil claim slug", fn -> MatchKey.native_id("CG7", nil) end},
  {"empty origin id", fn -> MatchKey.native_id("", "annotated-number-excluded") end},
  {"slash in claim slug", fn -> MatchKey.native_id("CG7", "a/b") end},
  {"hash in claim slug", fn -> MatchKey.native_id("CG7", "a#b") end},
  {"space in claim slug", fn -> MatchKey.native_id("CG7", "a b") end},
  {"slash in origin id", fn -> MatchKey.native_id("CG/7", "x") end},
  {"none/3 propagates the refusal", fn -> MatchKey.none("no-oc-scenario", "CG7", "a/b") end}
]

negative_results =
  Enum.map(negatives, fn {label, f} ->
    result = f.()
    refused? = match?({:error, _}, result)

    IO.puts(
      "  #{String.pad_trailing(label, 32)} #{if refused?, do: "REFUSED", else: "EMITTED"}  #{inspect(result)}"
    )

    refused?
  end)

# The positive control ON the negative controls: a well-formed pair must be
# ACCEPTED, or "refuses everything" would read identically to "refuses the
# right things".
positive = MatchKey.native_id("MES-38", "listen-stream-consumed")
IO.puts("  #{String.pad_trailing("positive control (a Jira key)", 32)} #{inspect(positive)}")

# --------------------------------------------------------------------------
# CHARSET — re-measured over all 175 rows, not taken from the brief.
# --------------------------------------------------------------------------
banner.("CHARSET — re-measured over all #{length(rows)} manifest rows")

carried = MatchKey.carried_fields()
key_fields = MatchKey.key_fields()

carried_values =
  Enum.flat_map(rows, fn row ->
    fields = key_fields |> Enum.zip(row) |> Map.new()
    Enum.map(carried, &Map.get(fields, &1))
  end)

charset = ~r/\A[A-Za-z0-9_-]*\z/
outside = Enum.reject(carried_values, &Regex.match?(charset, &1))

IO.puts("  #{length(carried_values)} carried values over #{length(carried)} fields")
IO.puts("  outside [A-Za-z0-9_-]: #{length(outside)}")

# POSITIVE CONTROL on the charset check: `description` is the field that
# contains spaces. If it does not come back outside the charset, the check is
# not checking.
descriptions =
  Enum.map(rows, fn row ->
    key_fields |> Enum.zip(row) |> Map.new() |> Map.get("description")
  end)

desc_outside = Enum.reject(descriptions, &Regex.match?(charset, &1))

IO.puts(
  "  positive control — `description` outside the charset: #{length(desc_outside)} of #{length(descriptions)}"
)

# --------------------------------------------------------------------------
# encode/1's refusals — re-measured, expected UNCHANGED by this ticket.
# --------------------------------------------------------------------------
banner.("encode/1 REFUSALS — re-measured, this ticket touches the state-1 half not at all")

sample = hd(rows)
base = key_fields |> Enum.zip(sample) |> Map.new()

encode_checks = [
  {"a real row encodes", MatchKey.encode(sample), :ok},
  {"leg `none` is refused", MatchKey.encode(%{base | "leg" => "none"}), :error},
  {"leg `sever` is refused", MatchKey.encode(%{base | "leg" => "sever"}), :error},
  {"a slash in `name` is refused", MatchKey.encode(%{base | "name" => "a/b"}), :error},
  {"an empty `check_id` is refused", MatchKey.encode(%{base | "check_id" => ""}), :error},
  {"a non-string field is refused", MatchKey.encode(%{base | "name" => 7}), :error},
  {"a short list is refused", MatchKey.encode(["a", "b"]), :error}
]

encode_results =
  Enum.map(encode_checks, fn {label, result, expected} ->
    actual = if match?({:ok, _}, result), do: :ok, else: :error
    ok? = actual == expected

    IO.puts(
      "  #{String.pad_trailing(label, 32)} #{if ok?, do: "as expected", else: "CHANGED"}  #{inspect(result) |> String.slice(0, 60)}"
    )

    ok?
  end)

# --------------------------------------------------------------------------
banner.("VERDICT")

md5_after = md5.(manifest_path)

results = [
  {"old scheme loses rows (>0)", old_lost > 0},
  {"old scheme: 3 CG7 tokens byte-identical", length(Enum.uniq(cg7_old)) == 1},
  {"old scheme: one guard answer for three claims", length(Enum.uniq(cg7_states)) == 1},
  {"old scheme REFUSED by declared_claim_index/1", old_red?},
  {"old scheme REFUSED on CG7 ALONE, naming CG7", cg7_old_red?},
  {"new scheme loses 0 rows", new_lost == 0},
  {"new scheme accepted by declared_claim_index/1", new_ok?},
  {"new scheme round-trips through decode/1", round_trips?},
  {"new scheme still guards to state 3", all_state_3?},
  {"all #{length(negatives)} negative controls refused", Enum.all?(negative_results)},
  {"positive control on them accepted", match?({:ok, _}, positive)},
  {"charset holds over all #{length(rows)} rows", outside == []},
  {"charset control — `description` violates it", length(desc_outside) > 0},
  {"encode/1 refusals unchanged", Enum.all?(encode_results)},
  {"manifest unmutated", md5_before == md5_after}
]

Enum.each(results, fn {label, ok?} ->
  IO.puts("  [#{if ok?, do: "PASS", else: "FAIL"}] #{label}")
end)

IO.puts("\nmanifest md5 after:  #{md5_after}")
IO.puts("OLD: #{length(claims)} claims -> #{old_distinct} tokens, #{old_lost} rows lost")
IO.puts("NEW: #{length(claims)} claims -> #{new_distinct} tokens, #{new_lost} rows lost")

if Enum.all?(results, fn {_l, ok?} -> ok? end) do
  IO.puts("\nAC4 CONTROL: all #{length(results)} checks pass.")
else
  IO.puts("\nAC4 CONTROL FAILED.")
  System.halt(1)
end
