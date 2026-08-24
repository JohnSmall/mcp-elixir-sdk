# The ET-CC membership criterion

**Ratified on MES-67 (A2), Sprint 6, 2026-08-22. Relocated to this file, unchanged,
by MES-80 (A5), Sprint 7, 2026-08-23.** This file is the criterion. B2a (`MES-81`),
B2b (`MES-82`) and D1 apply it; nothing downstream should have to reconstruct it from
a Jira comment thread.

**Repo is source of truth; the Confluence page is the mirror**
(`docs/conformance/report-2026-07-28.md:14-17`). There is no Confluence mirror of this
file at the time of writing.

**The ratification record is [MES-67](https://vidhya-trading.atlassian.net/browse/MES-67)**
— 21 comments, ids `25596`–`25616`, ticket Done. This file transcribes it; it does not
revisit it.

---

## How to read this file

The file is in **two fenced parts, and the fence is load-bearing.**

**Part A is the ratified criterion.** Every element carries the two Jira comment ids it
came from, written `[authored 25xxx | ratified 25xxx]`:

- **authored-at** — the comment that first states the element.
- **ratified-at** — the comment in which the PM rules it in.

The two differ often, and not always by seat. Gate 2's decision procedure (§2) was
authored by **CODE_REVIEWER** at `25610` as a review recommendation and ruled in by the
PM at `25612`; a single-id citation would either attribute a ratified rule to a review
recommendation or lose where it came from.

**An element with an authored-at and no ratified-at is a PROPOSAL and is not in Part A.**
That is the difference between transcribing the ratification and transcribing the
conversation.

**Part B is MES-80's own output and is NOT criterion** — see its own opening statement.

**Addresses in Part A are verbatim as ratified.** Where the tree has moved under one, the
drift is reported in Part B §B.2 and is *not* corrected here: correcting it would be
editing ratified text, after which the transcription could no longer be checked.

---

# PART A — THE RATIFIED CRITERION

## §0 The unit, and the register key

**The unit of ET-CC membership is one runtime ExUnit test.** A `doctest` is one unit. A
`for`-generated test is **one unit per generated test**, not one per declaration.
`[authored 25598 §0 | ratified 25601]`, restated in the ratified close-out at `25603 §0`.

**The register key is `{module, test name}` — never the name alone, and never
`file:line`.** `[authored 25598 §0 | ratified 25601]`

- Never the name alone: the 537 declarations under `test/mcp/` carry only **524 distinct
  names**; nine separate tests are named `"round-trips through JSON"`. Keying on the name
  silently merges rows.
- Never `file:line`: generated tests share one line and have interpolated names.

This section is the one B2a and B2b **must** inherit identically. A membership criterion
that does not state its unit yields one number from B2a and a different one from B2b,
and both look internally consistent.

## §1 Gate 1 — SCOPE. Defines the population; it does not label.

**Is the unit under `test/mcp/`?** `[authored 25598 | ratified 25601]`

The population is **579** units. `test/conformance/` (285 units) is the Sprint-5
instrument — it tests our tooling, not the protocol — and is out **by rule**, not
re-derived. `[authored 25597, 25598 | ratified 25601]`

**A gate-1 failure yields `OUT-OF-SCOPE`, which is NOT one of the four labels.**
`[authored 25603 | ratified 25612]` The partition in §7 is over the 579 only. Had gate 1
emitted a label, the ratified invariant would have summed to 864 rather than 579.

## §2 Gate 2 — SUBJECT

**Is the artefact the assertion is *about* a wire artefact** — a JSON-RPC message or
error, a transport header or status, or the output of the public encode/decode boundary
that produces one? **The gate is on what is asserted, not on where the test sits.**
`[authored 25598 | ratified 25601]`

### §2.1 The decision procedure

**Would an SDK that got this wire behaviour arbitrarily wrong still pass this test? If
yes, gate 2 fails.** `[authored 25610 (CODE_REVIEWER) | ratified 25612 (PM: "I am ruling
it in")]`

This is an **addition** to the text ratified at `25601`, not a restatement of it. It is
what turns gate 2 from a classification into a procedure that returns NO.

### §2.2 The usable form, and what counts as a step

**Is there an SDK step between the asserted value and the wire?** One step is enough to
fail the gate, because that step is free to be arbitrarily wrong under a passing test.
`[authored 25614 | ratified 25616]`

**Generic serialisation of an already-JSON-shaped value is not such a step; a
hand-written encoder that renames or drops fields is.** `[authored 25614 | ratified
25616]`

Worked both ways, and both addresses are in this tree:

| | address | verdict |
| --- | --- | --- |
| **not a step** | `plug.ex:1005` — `Jason.encode!(response)` over a map `dispatch.ex:724-728` already built string-keyed | gate 2 survives |
| **a step** | `server_capabilities.ex:47-49` — `defimpl Jason.Encoder ... {_key, nil}, acc -> acc` | gate 2 fails |

## §3 Gate 3 — REFERENT

**Can the sweeper *name* a 2026-07-28 spec anchor for the asserted behaviour** — a
`file:line` at the pinned commit `5f5440bb`, or a SEP number? **The referent is the spec,
never the official suite.** A requirement OC declines to score is still a requirement.
`[authored 25598 | ratified 25601]`

**If no anchor can be named, gate 3 FAILS — fail-closed, by construction.** That is
deliberate: the sweeper must **produce** the anchor, not assert that one exists.
`[authored 25603 | ratified 25612]`

## §4 Gate 4 — recorded as an attribute. It NEVER excludes.

**Gates 1–3 decide membership. Gate 4 does not.** `[authored 25596 (PM amendment 1) |
ratified 25601]`

Recorded per member as **`falsifiable: yes | no | undetermined`** and handed to D5a/D5b.
`[authored 25598 | ratified 25601]`

**`undetermined` is a real third value, not a hedge — it is the answer when deciding
would require running a mutation, which is D5's job and not this ticket's.**
`[authored 25598 | ratified 25601]`

Two reasons it is an attribute rather than an excluder, both ratified:

1. Excluding on gate 4 makes bucket 5's vacuity finding unmeasurable. `[authored 25596 |
   ratified 25601]`
2. It makes the register **non-monotonic under test repair**: if a vacuous test is later
   fixed so that a spec-violating SDK can redden it, gate-4-as-excluder *adds* a member —
   so the ET-CC count moves for a reason that has nothing to do with what the suite
   claims, and no diff of the criterion explains it. `[authored 25598 | ratified 25601,
   "use that framing in the artefact"]`

## §5 The four labels, each with a POSITIVE test

`[labels proposed 25598 | ratified 25601 — conditionally on ET-ADJ receiving a positive
test; positive tests authored 25603 | ratified 25612; the condition itself withdrawn at
25612 as "the weaker formulation"]`

| label | positive test | recorded field |
| --- | --- | --- |
| **`ET-CC`** | passes gates 2 **and** 3 | `spec_anchor` |
| **`ET-CTRL`** | fails 2 or 3, **and** asserts the responsiveness of an instrument (canary, probe, counter, fixture) that a **named in-scope unit** depends on to be capable of failing | `controls: {module, name}` |
| **`ET-ADJ`** | fails gate 2 because its asserted artefact is not itself a wire artefact, **and** that artefact is consumed by a **named in-tree call site** (a `file:line` in `lib/`) on a path that produces one | `consumed_at` |
| **`ET-OUT`** | in scope and none of the above | — |

`ET-OUT` has **two** ways in: (i) no `lib/` call site consumes the artefact on a
wire-producing path; (ii) it *does* reach the wire but gate 3 fails — no spec anchor can
be named.

### §5.1 ET-ADJ is keyed on the CODE PATH, not on a downstream ET-CC test

`[authored 25603 | ratified 25612]` The PM's ratification condition at `25601` phrased the
second conjunct as *"a wire-affecting artefact that an ET-CC **test** consumes"*. Keyed on
a downstream ET-CC test, no unit can be labelled until the unit it feeds has been
labelled — so the answer depends on **sweep order** and two sweepers legitimately differ.
Keyed on the call site it is a `grep`: order-free, and a second person gets the same
answer. The PM withdrew the original phrasing at `25612` as "the weaker formulation".

### §5.2 The ET-ADJ / ET-OUT boundary, worked on both sides

`[authored 25603 | ratified 25612]`

| unit | consumed at | label |
| --- | --- | --- |
| `Extensions.valid_identifier?/1` doctests (2). Artefact: a boolean. | `extensions.ex:332` — `not valid_identifier?(key) ->` drops the key inside `normalise/2`, deciding wire presence. | `ET-ADJ` |
| `Extensions.reserved_prefix?/1` doctests (2). Artefact: a boolean. | **NOTHING.** Grep of `lib/` returns only doc cross-references. Its own doc: *"Informational only. Nothing in this SDK acts on the result … never what goes on the wire."* | `ET-OUT` |

Two doctests of the same module, same shape, same spec neighbourhood, separated by one
grep.

### §5.3 ET-CTRL keys on APPARATUS, not on rhetorical role

**A claim about the product is never a control.** `[authored 25615 | ratified 25616]`

Example 3's canary is apparatus — it touches no SDK code at all. A test that asserts the
SDK's own behaviour (for instance, that it does *not* warn on correct input) is a claim
about the product and is therefore never `ET-CTRL`, whatever the source calls it. Without
this line `ET-CTRL` absorbs every negative and silence test in the tree, which is the
residual-bin failure the `ET-ADJ` ratification condition was written to prevent, arriving
in the bin next door.

## §6 Precedence, and `mixed`

**Any-assertion rule:** a test is `ET-CC` if **any** of its assertions passes gates 2 and
3; record `mixed: true`. A test is indivisible — it goes red or green whole — so
membership is a property of the whole test, and **a test that asserts a requirement
asserts it whatever else it also does.** `[authored 25598 | ratified 25601]`

**Precedence rule (generalised):** a unit's label is the **highest** its assertions earn,
ordered `ET-CC > ET-CTRL > ET-ADJ > ET-OUT`; record `mixed: true`. Ordering is by strength
of contribution to the conformance argument, so max-over-assertions can never hide a
claim. `[authored 25603 | ratified 25612]` Without it the partition is not well-defined,
and a partition that is not well-defined cannot support §7.

## §7 The totality invariant

**Every one of the 579 in-scope units gets exactly one label from the closed set.**
`[authored 25598 | ratified 25601]`

```
ET-CC + ET-CTRL + ET-ADJ + ET-OUT == 579
```

`579` is `566 tests + 13 doctests` from `mix test test/mcp`, measured at `9661ef8`
`[authored 25597 | ratified 25601, PM verifying at their own seat]`. **The sum is over the
579, not the 864-unit whole suite**, because gate 1 yields `OUT-OF-SCOPE` rather than a
label (§1). `[authored 25603 | ratified 25612]`

This is what a bucket count cannot answer: **was the procedure applied to everything.**

## §8 Per-member recorded fields

`[authored 25605 | ratified 25612]`

`key {module, name}` · `label` · `spec_anchor` (ET-CC) · `falsifiable` (ET-CC → D5a/D5b) ·
`mixed` · `consumed_at` (ET-ADJ) · `controls` (ET-CTRL) · `escalated`.

**The spec anchor is recorded; the official-suite mapping is NOT.** `[authored 25596 (PM
amendment 2) | ratified 25601]` That relation is A3's and the crosswalk is C1's, computed
once. Recording an OC mapping per test would force every sweeper to hold A1's manifest
open and re-apply its in-scope rule per row — S6-5's shape, and two tickets independently
producing one mapping is the MES-24 two-censuses defect.

## §9 The residual, and the tie-break route

`[authored 25600, 25605 | ratified 25601, 25612]`

**R1 — the gate-2 convenience boundary.** Spec-mandated wire shape vs our own public-API
shape (return-tuple conventions, option handling). Ruled **out of ET-CC by default**.
Default `ET-OUT`, or `ET-ADJ` where §5's call-site test is met.

**R2 — how many steps from the wire is still ADJ?** The call-site test is **transitive and
deliberately unbounded**: any number of steps, provided *each* is a named `lib/` call site
on a wire-producing path. A deep chain will make `ET-ADJ` large. Large and honest was
preferred to bounded by an arbitrary number. **If B2a finds `ET-ADJ` swallowing the tree,
that is an A1 escalation with data** — a better place to set a bound than here with none.

**R3 — gate 3 when the test cites no anchor.** Resolved fail-closed by construction, not
left open. The residual is the *cost*: a genuine claim whose author left no citation is
demoted. That is the safe direction — it under-counts `ET-CC` rather than inventing
members — and it is recoverable by escalation.

**TIE-BREAK ROUTE.** An undecidable case is an **A1 escalation to the PM**, never a
sweeper's judgement call. B2a/B2b record `escalated: true` **and the question, on the
row**, carry the provisional label, and hand it up. A deferred decision stays visible in
the register instead of dissolving into a number.

## §10 The nine negative categories

`[authored 25605 | ratified 25612; category 8 corrected 25613 | ratified 25616]`

1. **Instrument tests** — the 285 under `test/conformance/`. Gate 1. `OUT-OF-SCOPE`.
2. **Instrument-responsiveness controls** — assert that a canary/probe/counter can
   register at all. `ET-CTRL`.
3. **Bare-constant tests** — a name or code compared to a literal with no encode step.
   Gate 2. `ET-ADJ` if a `lib/` call site consumes it on a wire path, `ET-OUT` if not.
4. **Internal-representation tests** — assert a struct field or intermediate value that a
   later mechanical step translates to the wire. Gate 2. `ET-ADJ`. **The largest and least
   obvious category.**
5. **Predicates nothing acts on** — informational helpers with no consumer. `ET-OUT`.
6. **Behaviour outside the spec's domain** — reaches the wire, but the spec does not
   govern the value being exercised. Gate 3. `ET-OUT`. *The one that looks most like a
   member and is not.*
7. **Dependency-behaviour tests** — assert Bandit/Req/Jason/Agent, not our code. Gates 2
   and 3. `ET-CTRL` if it controls a named unit, else `ET-OUT`.
8. **Operator-facing output** — log lines, warning text, rejection sentences. Never on the
   wire, no spec anchor. `ET-OUT` — **unless the same unit also asserts an encoded
   message**, in which case §6's precedence rule lifts it to `ET-CC` with `mixed: true`.
   In `JsonSchema202012Test` that describes **seven** units (the R-3, F-9, F-10
   declarations asserting both a warning and a decoded response) — **not** the fifteen
   log-only units, which have no wire assertion for the rule to lift.
9. **Public-API convenience shape** — return-tuple conventions, option handling, error
   tuples that never leave the process. `ET-OUT` by default; this is R1.

## §11 The nine worked examples, at their corrected values

`[examples 1,2,3,6,7,8,9 authored 25604 | ratified 25612; example 5 authored 25605,
corrected 25614 | ratified 25616; example 4 authored 25604, corrected 25613 | ratified
25616]`

The re-check of examples 1, 2, 3, 6, 7, 8 and 9 against §2.1's decision question — which
moved none of them — and example 1's "no SDK step hides here" working are
`[authored 25614 | ratified 25616]`.

| # | unit (key = module + test name) | label + deciding gate |
| --- | --- | --- |
| 1 | `DispatchTest` / `"initialize is removed → UnsupportedProtocolVersion (-32022)"` (decl line 81) | `ET-CC`. Asserts `resp["error"]["code"] == -32_022` — a JSON-RPC error on the wire (gate 2); SEP-2575 removes `initialize` (gate 3). `falsifiable: yes`. No SDK step hides between the assertion and the wire: `dispatch.ex:724-728` builds already-string-keyed JSON and `plug.ex:1005` does `Jason.encode!` with no reshaping. |
| 2 | `MethodsTest` / `"request methods"` — decl line 6, 12 assertions | `ET-ADJ`, `mixed: true`. All 12 compare a bare constant from `Methods.*/0` — nothing encoded — so gate 2 fails on every one. 11 of those constants **are** consumed on a wire path (`client.ex:314` passes `Methods.tools_list()` straight to `send_rpc` as the `method` field). **Decided against membership.** |
| 3 | `ClientConformanceTest` / `"CONTROL ON THE CONTROL: the canary really does count a fetch"` (decl 133) | `ET-CTRL`. Starts a Bandit canary, `Req.get`s it, asserts the counter is 1. **Touches no SDK code at all** — fails 2 and 3 independently. `controls` the `$ref`-is-not-dereferenced test above it. **Decided against membership.** |
| 4 | `JsonSchema202012Test` — 37 declarations, **47 units** (one decl × 11) | **31 `ET-CC` / 16 `ET-OUT`** — *not* 47/0. **15** decided by **gate 2** (every assertion is on the captured log; two bind the response to `_result` and discard it); **1** decided by **gate 3** — `W-5`, which passes gate 2 cleanly (asserts `tool["outputSchema"] == false` off the round-tripped response) and dies at gate 3 because `schema.ts:2005` types `outputSchema` as an object, so the spec does not govern `false` there. Invariant closes: 31 + 16 = 47. |
| 5 | the 13 doctests | **A three-way split: 6 `ET-CC` / 5 `ET-ADJ` / 2 `ET-OUT`.** See §11.1. |
| 6 | `ToolTest` / the 2 generated `"a boolean outputSchema of {true\|false} round-trips as a value, not an absence"` | `ET-OUT`. Gate 2 **passes** — it does `Jason.encode!\|>decode!` and asserts the decoded map. **Gate 3 fails**: `schema.ts:2005` types `outputSchema` as an object, so no anchor can be named. **Decided against membership.** |
| 7 | `RoutingHeadersTest` / `"a request carries the body method"` (decl 89) | `ET-CC`. Reads `mcp-method` off a capture plug's observed request headers (gate 2); SEP-2243 (gate 3). `falsifiable: yes`. Its `for` is **inside** the test body, so it is **one** unit — the contrast with example 6 is the whole S6-6 point. |
| 8 | `CensusTest` / `"builds a census, once every non-pass is classified"` (`test/conformance/census_test.exs:313`) | `OUT-OF-SCOPE` at gate 1 — **not** `ET-OUT` (§1). Carried so the procedure is shown returning NO at gate 1 as well as at 2 and 3. **Decided against membership.** |
| 9 | `CapabilityHonestyTest` / `"a handler with list callbacks but no handle_listen/3 advertises no listChanged"` | `ET-ADJ`, `consumed_at: tool_capabilities.ex:26`. Asserts `caps.tools.list_changed == nil` — a **struct field**, not an encoded message. `tool_capabilities.ex:20-31` renames `list_changed` to `:listChanged` and drops nils, so **an SDK whose encoder emitted `"listChanged": false` regardless would pass this test**. **Decided against membership.** |

**Six of the nine are decided against `ET-CC` membership** (2, 3, 5-in-part, 6, 8, 9),
against AC2's bar of two.

### §11.1 Example 5 worked out — the 13 doctests, individually

| function | n | label, and why |
| --- | --- | --- |
| `HeaderMirror.encode_value/1` | 4 | `ET-CC`. The expected output **is** the header value — e.g. `"=?base64?SGVsbG8sIOS4lueVjA==?="` — placed verbatim at both consumers (`client.ex:379`, `header_mirror.ex:140`). No step between. Anchor: `streamable-http.mdx:490-492` (SEP-2243). `falsifiable: yes`. |
| `Extensions.from_meta/1` | 2 | `ET-CC`. The input literal is a wire `_meta` fragment under `io.modelcontextprotocol/clientCapabilities` — the decode side, where the function is the whole of the interpretation. The `from_meta(nil)` one is the weaker: `falsifiable: undetermined`, handed to D5. *Recorded fact: `from_meta/1` has no consumer in `lib/` at all, only doc references — it is offered to handler authors. This does not touch gate 2.* |
| `Extensions.normalise/2` | 3 | `ET-ADJ`, `consumed_at: config.ex:253` (server), `client.ex:971` (client). **Corrected from `ET-CC` in the correction round.** The step not counted first time: the normalised value lands in a **struct field**, and `server_capabilities.ex:43-52` / `client_capabilities.ex:37-47` are hand-written encoders that drop nils. An SDK emitting `"extensions": {}` for `nil`, or keeping a key `normalise/2` dropped, passes all three doctests. |
| `Extensions.valid_identifier?/1` | 2 | `ET-ADJ`. §5.2's boundary case. `consumed_at: extensions.ex:332`. |
| `Extensions.reserved_prefix?/1` | 2 | `ET-OUT`. No `lib/` call site consumes it — the other side of the same boundary. |

## §12 What a sweeper inherits

`[authored 25615 | ratified 25616]`

1. **A file is not a labelling unit**, and a moduledoc's universal claim is not evidence
   for one. The strongest whole-file candidate in the tree splits 31/16.
2. **A proxy for a gate is not the gate.** "Reaches a round trip" is on the *path*; gate 2
   is about the artefact *asserted*. §2.1's decision question removes the proxy by
   construction — it cannot be answered by looking at what a test calls, only at what it
   would still pass over.
3. **A wrong file-level label is a suppressed distribution, not a wrong answer**, and the
   shape of the distribution is not predictable from the gate that caught the first
   counterexample. Fifteen units failed gate 2 and one failed gate 3, and no check aimed
   at the first route could ever have found the second. **A sweeper who corrects a
   file-level label at the gate that caught it is not finished.**

A fourth, from §11's own history: **assert-the-struct is the commonest near-miss in this
tree, and it will not look like a near-miss while you are sweeping.** `[authored 25604 |
ratified 25612]`

---
---

# PART B — MES-80's OWN OUTPUT

**Nothing in Part B is criterion.** No sentence below was decided by MES-67; none of it
binds B2a, B2b or D1. It is this ticket's own working — the mechanisation ruling AC5
asked for, the re-verification of Part A's addresses, and observations. It is separated
from Part A by a rule *and* by this sentence, because a rule is a layout convention and
layout does not survive being quoted, excerpted, or mirrored.

Written by CODE_CREATOR on MES-80, 2026-08-23. Every measurement below was run in a
dedicated worktree at the tip named in each claim.

## §B.1 AC5 — is the criterion expressible as a machine-checkable predicate?

**RULING: NO — not as a membership predicate over the test tree. Two limbs, and each is
independently sufficient. But the reasoning is NOT the one declared in advance at the plan
hop, and the difference is reported rather than re-aligned.**

### B.1.1 Gate 3 — the deciding bytes are in another repository. CONFIRMED, and measured.

Gate 3 asks whether a **spec anchor can be named** for the asserted behaviour. The anchor
is not a property of the test tree, so no predicate over that tree can compute it.

Measured at `5a53a65`, in the worktree:

```
files under test/mcp/                                        39
  citing a SEP number                                        12
  citing schema.ts:NNN or *.mdx:NNN                          15
  citing NEITHER                                             20
runtime units in those 20 anchor-less files                 183   (of 579 = 31.6%)
```

A predicate that extracts anchors from the source finds none for **183 of the 579 units**
and, under §3's fail-closed rule, must return `gate 3 fails` for every one. The ratified
gate asks something different — whether *the sweeper* can name an anchor — and a sweeper
may name one the test does not itself cite. So the mechanised gate and the ratified gate
disagree on up to 183 units, in the direction that silently under-counts `ET-CC`.

Nor does adding the spec repository rescue it. Example 6 and `W-5` both turn on
`outputSchema` being **typed as an object** at `schema.ts:2005`, so `false` is ungoverned:
the judgement is whether a requirement *governs the value exercised*, which is reading, not
lookup.

### B.1.2 Gate 2 — the declared limb is WEAKER than declared. Reported, not re-aligned.

**Declared at the plan hop:** gate 2's procedure is a counterfactual over implementations
that do not exist, so deciding it mechanically means deciding whether *some* perturbation
of the SDK leaves the test green — a mutation over an unbounded space — and the criterion
already routes that question elsewhere, to gate 4's `undetermined`.

**The citation checks out, verbatim.** §4's `undetermined` is ratified as *"the answer
when deciding would require running a mutation, which is D5's job and not this ticket's"*
(`25598`, ratified `25601`), restated at `25603`. So for the **counterfactual** form
(§2.1) the limb holds: mechanising it needs exactly what the criterion defers.

**But the limb does not transfer to the form B2a will actually apply.** `25616` ratifies
§2.2 — *"is there an SDK step between the asserted value and the wire?"* — as *"the usable
form of the question I ruled in, and it is what B2a will actually apply"*. That is a
**static dataflow** question, not a mutation question, and it is not obviously
unmechanisable. My declared limb does not reach it.

**What actually defeats it is narrower and is the thing worth recording.** §2.2 ratifies a
**distinction** — generic serialisation is not a step, a hand-written encoder is — but no
**decision procedure** for applying it, and the two sides are not separable at the call
site. Both addresses in §2.2's table are "Jason encodes this value":

- `plug.ex:1005` — `Jason.encode!(response)` over a plain map. **Not** a step.
- `server_capabilities.ex:47-49` — `defimpl Jason.Encoder` dropping nils. **A** step.

Distinguishing them requires resolving the **runtime type** of the encoded value and
asking whether a hand-written `defimpl` exists for it. In easy cases that is a grep; in
general the type at an assertion site is not statically known in Elixir, and the value in
example 1 reaches the wire across a `Plug`/`GenServer` boundary that no analysis in this
repository follows. `dialyzer` (gate 4 of the DoD) does success typing, not value
provenance, so **the gate that would have to establish it does not compute it.**

**So the ruling stands and the reason changes:** gate 2 is not mechanisable because its
ratified *usable* form needs value-provenance analysis the toolchain does not have, not
because it is a mutation question. Gate 3 defeats mechanisation on its own regardless.

### B.1.3 What IS mechanisable — stated, because "not mechanisable" alone is unfalsifiable

- **Enumerating the 579 units under a joinable key.** Mechanisable, and **already owned**:
  MES-83 (B3) is one JSON row per runtime test, doctests included, keyed joinably to B2a.
  Proposing a ticket for owned work would create the MES-24 two-owners defect.
- **A form-and-totality checker over B2a's register.** Mechanisable; **no owner at the
  time of writing.** It would assert: label sum equals the enumerated population; every
  `ET-CC` row has a non-empty `spec_anchor`; every `ET-ADJ` row a `consumed_at`; every
  `ET-CTRL` row's `controls` names a unit that exists; and the register's key set equals
  the enumeration's, **both ways**.

  **Its honest limit: it validates FORM and COMPLETENESS, never LABEL CORRECTNESS.** It
  would have caught **none** of A2's own defects — the whole-file label passed every one
  of those assertions (47 rows, all with anchors, summing correctly) while **16 of the 47
  were wrong**.

  Ruled by the PM at `25999` to be **its own backlog ticket**, not Sprint 7 and not B2a's
  DoD by default, with one bounded exception: if at B2a's plan hop it turns out to be a
  handful of assertions in a test file rather than a deliverable, that is a proposal to
  make at the plan hop.

## §B.2 Part A's addresses, re-opened at `5a53a65`

Part A carries every address **verbatim as ratified**. This table records what is at each
one **at the delivered tip**, so that drift is visible rather than silent. **Drift is
reported here; it is never corrected in Part A.**

CODE_REVIEWER verified these addresses at `1d79ae4` (`= 9661ef8` + one docs-only commit,
so `lib/` and `test/` are identical at the two). `main` has moved **12 commits** since.

**Result: every cited file is byte-identical between `9661ef8` and `5a53a65`
(`git diff --quiet 9661ef8 HEAD -- <path>` for all 19). Zero drift.**

**On the tip this table names.** The measurements were taken at `5a53a65`, and committing
this file moved the branch tip past it — a measurement that outlives the tip it was taken
at is the S7-1 shape. It is discharged rather than waved away: `git diff --name-only
5a53a65 <delivered tip>` returns **only the two files this ticket adds**, so no `lib/` or
`test/` path moved between the two, and the table holds at the delivered tip unchanged. The
delivered tip is named in MES-80's close-out; it is deliberately not written here, because a
commit cannot contain its own hash.

| address as ratified | resolved path | bytes at `5a53a65` | verdict |
| --- | --- | --- | --- |
| `extensions.ex:332` | `lib/mcp/protocol/extensions.ex` | `not valid_identifier?(key) ->` | agrees |
| `tool_capabilities.ex:26` | `lib/mcp/protocol/capabilities/tool_capabilities.ex` | `{:list_changed, val}, acc -> Map.put(acc, :listChanged, val)` | agrees |
| `tool_capabilities.ex:20-31` | as above | `defimpl Jason.Encoder` … through `end` | agrees |
| `client.ex:379` | **`lib/mcp/transport/streamable_http/client.ex`** | `target when is_binary(target) -> [{"mcp-name", HeaderMirror.encode_value(target)}]` | agrees |
| `header_mirror.ex:140` | `lib/mcp/protocol/header_mirror.ex` | `[{header_name(name), encode_value(string)}]` | agrees |
| `dispatch.ex:724-728` | `lib/mcp/server/dispatch.ex` | `defp error_response/2`, ending `%{"jsonrpc" => "2.0", "id" => id, "error" => error}` | agrees |
| `plug.ex:1005` | `lib/mcp/transport/streamable_http/plug.ex` | `\|> Plug.Conn.send_resp(200, Jason.encode!(response))` | agrees |
| `config.ex:253` | `lib/mcp/server/config.ex` | ``Extensions.normalise(declared, source: "MCP.Server.Config.build/2 `:extensions`")`` | agrees — see note (a) |
| `client.ex:971` | **`lib/mcp/client.ex`** | `Extensions.normalise(capabilities.extensions,` | agrees — see note (a) |
| `client.ex:314` | **`lib/mcp/client.ex`** | `Methods.tools_list(),` | agrees |
| `server_capabilities.ex:43-52` / `:47-49` | `lib/mcp/protocol/capabilities/server_capabilities.ex` | `defimpl Jason.Encoder` …; `:48` is `{_key, nil}, acc -> acc` | agrees |
| `client_capabilities.ex:37-47` | `lib/mcp/protocol/capabilities/client_capabilities.ex` | `defimpl Jason.Encoder` …; `:42` is `{_key, nil}, acc -> acc` | agrees |
| `dispatch_test.exs:82` | `test/mcp/server/dispatch_test.exs` | `test "initialize is removed → UnsupportedProtocolVersion (-32022)" do` | agrees |
| `methods_test.exs:6` | `test/mcp/protocol/methods_test.exs` | `test "request methods" do` (`:7` is the first assertion) | agrees |
| `client_conformance_test.exs:134` | `test/mcp/client_conformance_test.exs` | `test "CONTROL ON THE CONTROL: the canary really does count a fetch" do` | agrees |
| `tool_test.exs:110` / `:109` | `test/mcp/protocol/types/tool_test.exs` | `:108` `for value <- [true, false] do`; `:109` the `test` declaration | agrees |
| `routing_headers_test.exs:90` | `test/mcp/transport/routing_headers_test.exs` | `test "a request carries the body method", %{agent: agent, url: url} do` | agrees |
| `census_test.exs:313` | `test/conformance/census_test.exs` | `test "builds a census, once every non-pass is classified" do` | agrees |
| `capability_honesty_test.exs:25` | `test/mcp/server/capability_honesty_test.exs` | `test "a handler with list callbacks but no handle_listen/3 advertises no listChanged" do` | agrees |
| `json_schema_2020_12_test.exs:49/:56/:64` | `test/mcp/server/json_schema_2020_12_test.exs` | `defp round_trip(method, params, opts \\ []) do`; the two wrappers | agrees |
| `json_schema_2020_12_test.exs:195` | as above | `for {label, value} <- [` — the ×11 generator | agrees |
| `messages/tools_test.exs:131` | `test/mcp/protocol/messages/tools_test.exs` | `for {label, value} <- [` | agrees |

**Note (a) — a precision limit, present at ratification and NOT drift.** `25614` quotes
`%{capabilities | extensions: normalised}` against `config.ex:253` / `client.ex:971`. At
`5a53a65` those lines are the `Extensions.normalise(...)` call; the quoted struct-update is
two lines further on, at `:255` and `:975`. Both are inside the same function
(`declare_extensions/2`, `build_client_capabilities/1`) and the addresses were the same at
`9661ef8`, so this is a citation pointing at the consumption site rather than at the quoted
line — it was true when ratified and it is true now.

**Note (b) — `client.ex` is ambiguous in this tree and the criterion uses it for two
different files.** `client.ex:379` is `lib/mcp/transport/streamable_http/client.ex`;
`client.ex:314` and `client.ex:971` are `lib/mcp/client.ex`. Both resolve correctly on
inspection, and the resolved paths are in the table above so no future reader has to
re-derive them.

### Spec anchors, at the pinned commit `5f5440bb`

Verified against the local pinned tree at `/tmp/spec2026`, whose
`schema/2026-07-28/schema.ts` has md5 `48a009165e07f6732e38baf91291de87` — **matching the
pin recorded at `docs/sprint_4_issues.md:1288-1289`**, which is what establishes the tree
is the pinned one.

| anchor | bytes | verdict |
| --- | --- | --- |
| `schema.ts:2005` | `outputSchema?: { $schema?: string; [key: string]: unknown };` | agrees — an object type, so `false` is ungoverned |
| `schema.ts:779-780` | ``Keys MUST follow the {@link MetaObject \| `_meta` key naming rules}, with a`` / `mandatory prefix.` | agrees |
| `schema.ts:876-877` | identical two lines | agrees |
| `streamable-http.mdx:490-492` | ``The same encoding rule applies to the `Mcp-Name` header value. Tool and`` / `prompt names are only **SHOULD**-constrained to header-safe characters, so a` / `name (or resource URI) outside the safe set is carried as:` | agrees |

**Two stated limits on this half.** `basic/transports/streamable-http.mdx` has **no md5
recorded anywhere in this repository**, so its pin rests on it sitting in the same tree as
the schema file rather than on its own checksum; its md5 at the time of writing is
`63f792fddd2a9d81026ebafe6930ff87`. And `/tmp/spec2026` is **not committed** — it is a
scratch tree, so anyone re-checking these four anchors on a fresh container must fetch the
spec at `5f5440bb` first.

## §B.3 The denominator, re-measured at the delivered tip

§7's invariant contains a literal figure — `579` — measured at `9661ef8`, twelve commits
back. A figure inside a ratified invariant does not re-measure itself, so it was checked
rather than transcribed on trust.

```
mix test test/mcp   at 5a53a65  ->  13 doctests, 566 tests, 0 failures
                                    566 + 13 = 579
ratified figure     at 9661ef8  ->  579                     [agrees]
```

**Three seats have now measured 579 independently** — CODE_CREATOR and CODE_REVIEWER at
`9661ef8`/`1d79ae4`, the PM at `5a53a65` before dispatch, and this run at `5a53a65`. It
still holds. Had it not, transcribing `579` verbatim would have carried a number past the
run that produced it.

**And the check was not vacuous, which is worth showing rather than asserting.** Over the
same span the **whole suite** moved from `13 doctests, 851 tests` at `9661ef8` to
`13 doctests, 935 tests` at `5a53a65` — Sprint 7's tickets adding to `test/conformance/`.
So a suite count measured at the ratification tip *would* now be wrong by 84; §7's `579` is
stable because gate 1 scopes it to `test/mcp/`, not because nothing moved.

## §B.4 Observations

**(i) What was deliberately NOT transcribed, and why.** MES-67 also ratified a body of
findings about ExUnit **tagging mechanisms** — `@tag` over `doctest` and over a
`for`-wrapped `test` reaching only the first generated unit, `doctest Mod, tags:` reaching
all, an unrecognised `doctest` option being ignored silently, and `mix test --only`
exiting 0 on a partial selection (`25606`, confirmed independently at `25611`). **That is
not membership criterion** — it is a B4 finding about how a tag is applied. It is recorded
as `S6-6` in `docs/sprint_6_issues.md` and routed to B4. It is named here so its absence
from Part A reads as a decision rather than an omission.

**(i-b) The membership/correctness separation is NOT in Part A, and that is a PM
ruling rather than an oversight.** `25596` states it — *membership asks whether a test is
a conformance CLAIM; whether the claim is RIGHT is a separate question answered
downstream, so a wrong conformance claim is still a conformance claim* — and warns that a
criterion excluding tests which contradict the official suite would empty bucket 4a by
construction. **It is not transcribed, because no ratifying comment states it as a rule.**
Under §0's own two-id scheme that makes it a proposal, and Part A admits only elements
carrying both ids. Bending that rule for a rule the PM authored and agrees with is exactly
the failure the scheme exists to prevent, so it is not bent here.

**The rule is embodied in the criterion without being stated by it.** Gates 1-3 ask about
scope, subject and referent; none of them asks whether an assertion is correct, so a
sweeper applying Part A literally already cannot exclude on correctness. What Part A does
not do is *forbid* a sweeper from adding that test themselves — which is the residual
risk, and it is why this paragraph exists rather than the absence being left silent.
**The obligation is discharged in the consuming briefs, not here:** MES-81 carries it as a
named hazard, and MES-82 the same. Raised by CODE_REVIEWER at MES-80's review and ruled by
the PM; recorded so the absence reads as a decision.

**(ii) The "nine comments" figure does not reproduce.** `25616` says the criterion "lives
across nine comments", and `docs/conformance/match-relation.md:8` repeats it. Counting the
comments that carry ratified criterion text — the ids cited in Part A — gives **14**:
`25596`, `25597`, `25598`, `25600`, `25601`, `25603`, `25604`, `25605`, `25610`, `25612`,
`25613`, `25614`, `25615`, `25616`. This is reported, not corrected: `match-relation.md` is
A3's artefact and MES-80 does not touch it. The figure is not load-bearing for anything —
but MES-80's own brief carried a wrong count of the same thread (`nine`, corrected to `21`
before dispatch), which makes a third instance worth naming.

**(iii) Example 4's corrected figure has a narrower ratification than the rest of the
correction round.** `25616` confirms the correction round, verifies the **16th** unit at
source, and merged it. It does not itself restate `31`. The `31 / 16` split is
`25613`'s measurement, ratified by the round's acceptance rather than by an independent
re-count. Anyone who needs `31` to be exact should re-derive it from `47 − 16`, or from
`25613`'s enumeration of the fifteen.

## §B.5 The architecture-session page, read as a completeness prompt

Confluence page `278265861`, *"MES-67 · Suggested ET-CC membership criterion"*, is a
**pre-ratification proposal to MES-67**. It was **not a source** for Part A — MES-67 then
ran, and what it ratified is the outcome; transcribing from the proposal would reconstruct
the criterion from its input instead of its result. The page's own header says so: *"It is
not the ratified criterion."*

It was opened **after** Part A was complete, for one permitted use: as a completeness
prompt over the five hard cases and the residual class it names. For each: **did the
ratified criterion decide this?**

| # | the page's case | decided by MES-67? | where |
| --- | --- | --- | --- |
| 1 | `dispatch_test.exs:82`, `initialize → -32022` | **yes** — same verdict (`ET-CC`) | §11 ex. 1 |
| 2 | `methods_test.exs:7`, `Methods.initialize() == "initialize"` | **yes** — decided against membership | §11 ex. 2 |
| 3 | `client_conformance_test.exs:134`, control on the control | **yes** — same verdict (`ET-CTRL`) | §11 ex. 3 |
| 4 | `json_schema_2020_12_test.exs` | **yes** — decided **differently** | §11 ex. 4 |
| 5 | a doctest (13 exist) | **yes** — decided **differently** | §11 ex. 5, §11.1 |
| — | the residual class: gate 2's spec-mandated-wire-shape / public-API-convenience boundary | **yes** — ruled out of `ET-CC` by default, tie-break named | §9 R1 |

**All six decided. Nothing is escalated under AC4 from this page.** That is stated as a
result rather than left as silence, because "checked and found nothing" and "never asked"
read identically when only the answer is printed.

Two were decided differently and the ratified answer wins, so the difference is not
reported here beyond naming it: case 4 (the page labels the whole file `ET-CC`; §11 splits
it 31/16 over 47 units) and case 5 (the page says *"not by default"*; §11.1 is a three-way
split). The page's four-gate structure, in which falsifiability is an **excluding** fourth
gate, and its proposal to record an official-scenario mapping per member, were both
overridden before ratification by PM amendments 1 and 2 (§4, §8).

**One observation that is NOT a gap, and is flagged rather than filled.** R1 *is* decided —
the boundary is named and ruled out of `ET-CC` by default. But unlike §5.2's
`ET-ADJ`/`ET-OUT` boundary, which is worked on both sides with an address on each, **R1
carries no worked case on either side** in the ratified text; the plan comment that
proposed it offered "2–3 worked cases each side" (`25600`) and the ratified close-out
states the rule without them. This changes no decision, and MES-80 does not fill it. It is
recorded because R1 is the boundary B2a will meet most often, and a rule with no worked
case is the one a second sweeper reads differently.
