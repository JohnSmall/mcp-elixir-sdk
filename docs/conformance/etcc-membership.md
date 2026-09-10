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

**AMENDED on MES-87 (A2 amendment), Sprint 8, 2026-09-09.** Applying Part A for the first
time — MES-81's sweep of the 579 in-scope units — surfaced three places where the ratified
text did not decide a case it plainly reached. Each had been settled by a **§9 tie-break**,
which binds one ticket and nothing afterwards. MES-87 promotes them into Part A through the
same authored → ratified cycle: **§2.3, §2.4, §6.1, §9.1** and the `inherited_from` line in
§8, all ratified at `26737`. **The MES-67 text above and below is untouched**; every
amendment is a NEW element carrying its own two ids, so what MES-67 ratified and what
MES-87 added remain separable by reading.

**The second ratification record is
[MES-87](https://vidhya-trading.atlassian.net/browse/MES-87)** — plan `26682`–`26686`,
ratification `26736`–`26737`, ticket in Sprint 8. Elements authored at `26684` and `26685`,
all ratified at `26737`.

---

## How to read this file

The file is in **three fenced parts, and the fence is load-bearing.**

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

**Part C is MES-87's own output and is NOT criterion either** — the dispositions, the
priced rejections, the cross-check matrix and the quantification behind the amendments
above. It is a third part rather than an append to Part B because Part B's opening
sentence says Part B is MES-80's working, and appending to it would falsify that sentence.

**Amendments carry `26xxx` ids; MES-67's elements carry `25xxx` ids.** The two-id scheme is
what makes an amendment auditable rather than a silent edit: an element with a `26737`
ratified-at was NOT ratified by MES-67, and nothing here pretends otherwise.

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

### §2.3 The liveness qualifier — *"that produces one"* is RESTRICTIVE

`[authored 26684 | ratified 26737]` **Amended on MES-87 (A2 amendment), Sprint 8,
2026-09-09.**

§2's first clause admits *"the output of the public encode/decode boundary **that
produces one**"*. **The qualifier is restrictive.** An assertion whose bytes are
produced by a `lib/` encode/decode boundary that **no `lib/` call site routes to a
transport** FAILS gate 2: such a boundary does not *produce* a wire artefact, it
produces a value shaped like one. §2.2's question has no NO available where there is no
path to the wire, and §2.1's counterfactual returns YES.

**(a) The boundary is the PRODUCER OF THE ASSERTED BYTES**, never the entry point the
test happened to call. A dead entry point over a live producer does not fail the gate.

**(b) Producers are split BY DIRECTION.** A `defimpl Jason.Encoder` and a `from_map/1`
are different code running in opposite directions; one's liveness never carries the
other. A module producing the asserted artefact in both directions is two boundaries.

**(c) Where a unit asserts bytes from several producers, gate 2 fails only if EVERY one
is dead.**

**(d) Liveness is established by a named procedure, never by reading and never by a
grep.**

- **L1 — the redness proxy.** Mutate the boundary-direction widely, re-run the suite at
  a fixed seed, and count what reddens **outside its own tests and outside the units of
  directions already recorded dead**. At least one such unit means **LIVE**.
- **L2 — direct establishment, in two conjuncts.** **(i)** a byte probe through real
  `lib/` entry points, whose output is diffed against an unmutated baseline; **(ii)** an
  **alias-aware** call-site enumeration — calls, captures and dynamic dispatch — each
  caller followed to a live entry point or to a module `lib/` never uses.
- **L2's trigger is MECHANICAL: it runs on EVERY boundary-direction whose live count is
  zero, and never on a selection.** L1's silence is ambiguous — it means either
  *"nothing routes this to a transport"* or *"something does and no test asserts it"* —
  so a direction whose live count is zero has not been decided until L2 has run on it.
- **DEAD requires BOTH limbs of L2, and requires the mutation to be POTENT** — to have
  reddened at least one of the direction's own units. An impotent mutation establishes
  nothing in either direction.
- **L2 can only turn DEAD into LIVE.** It is an escape hatch from L1's silence, not a
  second route to death.

**(e) Scope.** **This rule reaches every unit satisfying its antecedent, never the
family it is stated over.** A liveness verdict is a claim about the tree **at a named
tip** and **expires when `lib/` moves**.

### §2.4 The reconciling line — is there a wire state this value is the decode of?

`[authored 26685 | ratified 26737]` **Amended on MES-87 (A2 amendment), Sprint 8,
2026-09-09.**

**Does the wire have a state this value is the decode of?** Where a value is handed
back through the public API, that question — not *"is this public-API convenience?"* —
is what gate 2 asks of it. The first is a test; the second describes intent.

**The absence of an *optional* field is a wire CONDITION, and a marker returned for it
is that condition's verbatim decode.** A value the SDK invents, with no wire
counterpart present *or* absent, has no state to be the decode of and fails gate 2.

Worked both ways, and both addresses are in this tree:

| value | wire state it is the decode of | gate 2 |
| --- | --- | --- |
| `%{}` from `Extensions.from_meta(nil)` | **YES** — *"the optional `_meta` field is not present"* is a wire condition, and the marker is its verbatim decode | **passes** |
| `:ready` from `Client.status/1` | **NO** — SDK-invented; there is no wire state, present or absent, for it to decode | **fails** |

**A weakness in an asserted value's STRENGTH is recorded at gate 4, never expressed by
failing gate 2** — see §9.1 clause (5). `%{}` is a thin thing to assert, and §4 is the
mechanism built for saying so.

This line reconciles §11.1 (which rules both `Extensions.from_meta/1` doctests `ET-CC`,
treating an absence marker as a **gate-4** weakness) with the decode-boundary tie-break
of 2026-08-23, which had failed structurally identical values at **gate 2**. Neither is
withdrawn; the distinction between them is stated, which is §9.1 clause (4) applied to
the case that produced it.

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

### §6.1 Inherited assertions are counted, and RECORDED

`[authored 26684 | ratified 26737]` **Amended on MES-87 (A2 amendment), Sprint 8,
2026-09-09.**

**The membership rule is unchanged.** §6's any-assertion rule counts assertions executed
in a `setup` block or a helper the unit calls, exactly as it counts assertions in the
unit's own body: the unit goes red or green whole, so a unit that reddens when the wire
behaviour is wrong **is** a unit that can catch a violation. Narrowing membership here
would reintroduce test-divisibility, which §6's own stated reason rules out.

**What is added is a RECORDING obligation, because the unattractive consequence is about
ATTRIBUTION, not membership.** *"Coverage attributed to a test that does not itself
assert anything about the wire"* is a complaint about the downstream join, not about
§6's gate.

**Where a unit's ONLY gate-2-and-3-passing assertion is inherited rather than its own,
the register records it** — a per-member **`inherited_from`** naming the helper's
`file:line`. **The label is unaffected.** Any downstream artefact that attributes
coverage per unit must read the field: **a member whose claim is wholly inherited is a
real member and a weak attribution, and those are different facts.**

The field is a per-**member** field, like `falsifiable` (§8): a non-member has already
failed a gate, so there is no inherited claim to attribute.


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

**Added by MES-87:** `inherited_from` (ET-CC, and only where §6.1's antecedent holds).
`[authored 26684 | ratified 26737]` The enumeration above is ratified text and is left
verbatim; this line is the amendment, so the two ids say which is which.

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

### §9.1 Precedence, and what a worked example is

`[authored 26685 | ratified 26737]` **Amended on MES-87 (A2 amendment), Sprint 8,
2026-09-09.**

**(1) A ratified worked example carries its RATIO, not only its result.** The reason a
worked example gives decides structurally identical cases the example does not name. **A
table of decided cases is authority of the same rank as a rule.**

**(2) Ratified Part A outranks a §9 tie-break, IN BOTH DIRECTIONS.** A tie-break decides
a case Part A leaves undecided; where Part A *does* decide — by rule **or by worked
example** — a tie-break is **void to the extent of the contradiction** and the case
returns to Part A. This holds **whoever authored the tie-break and whichever way it
cuts**; a precedence rule that only runs in the direction suiting the reader is not a
precedence rule.

**(3) Before a tie-break is issued it is checked against the WORKED EXAMPLES of every
section it lands in**, not only against the rule it fills. Filling a declared gap focuses
attention on the gap's own statement, and the examples that constrain the same class live
elsewhere in the document. *A tie-break written to fill a gap in a document can
contradict that document, because its author is looking at the gap and not at the text
around it.*

**(4) Where a tie-break and a worked example can be RECONCILED by a distinction both
accept, reconciliation is preferred to withdrawal** — and **the reconciling distinction
then becomes Part A text, not a comment.** Withdrawal discards a decided case;
reconciliation keeps both and states the line between them. §2.4 is this clause applied
to the case that produced it.

**(5) A weakness in an assertion's STRENGTH is recorded at gate 4 and is never expressed
by failing gate 2.** §4 exists for exactly that and **never excludes**. Reaching for gate
2 to express a gate-4 concern is a category error, whichever direction it is made in.

**What clause (2) does NOT do: it does not make an undecided family decided.** A
tie-break governing a class Part A is silent on stays a valid gap-filler until Part A is
amended to reach it. That is an **incompleteness**, not an inconsistency — and it is
disclosed rather than left to be discovered: see Part C §C.5.


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

> **MES-87 ADDENDUM to (ii), 2026-09-09** — written by CODE_CREATOR on MES-87, not by
> MES-80, and marked as such because Part B's opening names its author and its ticket.
> Ratified at `26737` (PM ruling `26736`, answering Q2: *"the §0 ratification-record
> header and §B.4(ii)'s enumeration of criterion-carrying comment ids — update both"*).
>
> **The count is now 17.** MES-87's amendments add three ids to the enumeration above:
> `26684` (authors §2.3, §6.1 and §8's `inherited_from` line), `26685` (authors §2.4 and
> §9.1), and `26737` (ratifies all of them). Full set, in order:
> `25596`, `25597`, `25598`, `25600`, `25601`, `25603`, `25604`, `25605`, `25610`,
> `25612`, `25613`, `25614`, `25615`, `25616`, **`26684`**, **`26685`**, **`26737`**.
>
> The two ratification threads stay distinguishable by prefix — `25xxx` is MES-67,
> `26xxx` is MES-87 — which is the property that makes the enumeration worth keeping
> rather than a tally. `match-relation.md:8` is still not corrected here, for MES-80's
> stated reason: it is A3's artefact.

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

---
---

# PART C — MES-87's OWN OUTPUT

**Nothing in Part C is criterion.** No sentence below binds a sweeper. The criterion
MES-87 added is in **Part A** — §2.3, §2.4, §6.1, §9.1 and §8's `inherited_from` line,
each carrying its own two ids. Part C is the working behind them: the dispositions and
their reasons, the rejected alternatives priced, the cross-check matrix, and the
quantification.

**It is a third part rather than an append to Part B**, because Part B's opening sentence
says Part B is *MES-80's own output* and appending MES-87's working to it would falsify
that sentence. Separated by a rule **and** by this paragraph, for the reason Part B gives:
a rule is a layout convention and layout does not survive being quoted or excerpted.

Written by CODE_CREATOR on MES-87, 2026-09-09. Plan `26682`–`26686`; PM ratification
`26736` (the four question rulings and the stop-rules) and `26737` (the ratification of
record). Every measurement below was run in a dedicated worktree.

**On which tip each measurement was taken, because a measurement that outlives its tip is
the S7-1 shape.** The branch base is **`616dd2b`** — `main` at dispatch. The **no-op
control** (§C.7 step 0) was taken at that tip **exactly**, before any file was touched;
that is what makes it a control. Every *post-amendment* measurement — the row-by-row diff,
the helper enumeration, the guard-22 controls and the §C.6 matrix — was taken on the
amended tree that this branch's single commit delivers. **The delivered tip is named in
MES-87's close-out and deliberately not written here, because a commit cannot contain its
own hash.**

**`lib/` and `test/` are byte-unchanged from the base:** the branch's three-dot diff is
six files, all under `docs/` and `conformance/`. So no measurement over the source tree
could have moved between the two tips, and the boundary verdicts §2.3(e) makes
tip-dependent are still claims about a tree that has not moved.

## §C.0 The asymmetry that shapes every disposition

**The delivered register already applies all five MES-81 rulings**, through rounds 2–6.
So **adopting** a ruling into Part A moves **zero** rows, and **rejecting** one is what
costs. That is not a reason to adopt — it is the reason the *rejection branch of each
candidate has to be priced separately*, which §C.1–§C.3 do. Measured from the delivered
register at `616dd2b`, per `adjudication.ruling`:

| ruling | `ET-CC` | `ET-OUT` | rows | what REJECTING it would put back in play |
| --- | ---: | ---: | ---: | --- |
| **A** (candidate 1) | 14 | 66 | 80 | **66 rows**, `ET-CC` 281 → up to 347 — a **23%** move, the largest in the register. All 66 are excluded at **gate 2**. |
| B | 1 | 22 | 23 | not a candidate — upheld as ruled, and not reopened here |
| **C** (candidate 2) | 3 | 0 | 3 | 3 rows |
| D | 1 | 0 | 1 | not a candidate |
| **E** (candidate 3) | 3 | 2 | 5 | 5 rows |

    jq -r '[.rows[]|select(.adjudication)]|group_by(.adjudication.ruling)[]
           | "\(.[0].adjudication.ruling) \(length)"' docs/conformance/etcc-register.json

**On ruling E's 5 against the ticket body's "six rows".** §7 family E says *"6 rows put,
4 moved"* and its own heading note already records why the delivered register carries
**5**: round 4's ruling A took `capabilities_test.exs:79` back out, so that row's
`adjudication` now names ruling **A**. The figure above is the delivered register's, not
family E's, and the two are reconciled rather than one being wrong.

## §C.1 Candidate 1 — §2's *"that produces one"*. **DISPOSITION: AMEND.**

**Adopted in substance; the wording at `26034` is NOT what was promoted.** That
difference is the whole of this disposition. `26034` keys on *"a public encode/decode
boundary"* with **no direction, no producer test, no named procedure and no scope
clause**. Rounds 3–6 added four things to it, each because its absence had already
produced a wrong answer — and promoting `26034` verbatim would have ratified a rule
**weaker than the one the register actually applies**, which is a silent re-label wearing
a ratification.

| element, now §2.3 | why it is in the ratified text | what omitting it would have cost |
| --- | --- | --- |
| **(a)** keyed on the PRODUCER of the asserted bytes, not the entry point called | round 2's refinement; named as mandatory in the brief | the 5 `protocol_test.exs` survivors lose `ET-CC` — their entry point is dead, their encoder live |
| **(b)** split BY DIRECTION | PM ruling `26058`; §6a step 1 | round 4's −9 / +5 unwinds |
| **(c)** several producers → fails only if EVERY one is dead | §6a; already the generator's guard-19 predicate | the 6 rows naming a dead direction beside a live one |
| **(d)** the named procedure — L1 + L2, DEAD needs both limbs **and** potency, L2 at a MECHANICAL trigger | §6a step 2; S7-19; **six of nine DEAD verdicts were wrong without it** | the rule reverts to a reading exercise, and reading fails toward DEAD |
| **(e)** scope — reaches every unit satisfying the antecedent, never the family it was stated over | S7-17(ii); CODE_REVIEWER's F1 | F1 recurs on the next ruling |

**The rejection branch, priced honestly.** The plain reading is not silly, and
`etcc-register.md` §6 records it as the honest counter: *"§2's first clause admits the
public boundary without asking where it leads, and `MCP.Protocol.encode/1` is literally
the public encode boundary."* **What decides it is not the reading, it is the
consequence.** Those 66 rows assert bytes **no live `lib/` path emits**; the official
suite drives a socket; so C1 would pair them against checks that cannot witness them.
That is the overstatement this epic exists to prevent, at **23% of the member count**.

**AC1 requires the counter to be answered, not out-voted.** It is answered by the
amendment's own text rather than by the count: §2.2 asks *"is there an SDK step between
the asserted value and the wire?"*, and where there is no path to the wire that question
**has no NO available**. The plain reading treats the qualifier *"that produces one"* as
decoration. §2.3 is the ruling that it is not — which is what makes this an amendment to
§2 rather than a tie-break beside it, exactly as `etcc-register.md` §6 said the proper
fix would be.

**§2.3(d) and (e) are written as MES-88's contract.** (d) names the two limbs, the
mechanical trigger, the potency requirement and L2's one-way asymmetry; (e) states that a
verdict is a claim about a named tip and **expires when `lib/` moves**, which is MES-88's
whole premise. MES-88 builds its re-runnable sweep against this text and should not have
to re-derive any of it. Per the PM's affirmation at `26737`, if MES-88's execution shows
(d) or (e) needs refinement, that is a MES-88 finding that may re-amend §2.3 through this
same authored → ratified cycle; ratifying it now does not freeze it against evidence
MES-88 has not yet produced.

## §C.2 Candidate 2 — §6's any-assertion rule and shared helpers. **DISPOSITION: AMEND.**

**The MEMBERSHIP rule stands unchanged. What is added is a RECORDING obligation** (§6.1).

**The reason is a distinction the brief does not draw: the unattractive consequence is not
about membership at all, it is about ATTRIBUTION.** §6 is right that a test is
indivisible — a unit that reddens when the wire behaviour is wrong **is** a unit that can
catch a violation, and that is precisely the predicate the crosswalk needs. The complaint
recorded in `etcc-register.md` §7 family C is *"coverage attributed to a test that does
not itself assert anything about the wire"* — and **attribution is C1's join, not §6's
gate.**

- **Narrowing membership** would reintroduce test-divisibility, which §6's own stated
  reason rules out. Priced: it would move the 3 ruling-C rows back to `ET-OUT` and, worse,
  would make the label depend on how an author happened to split an `assert` — the exact
  ground on which the PM declined the same move in ruling D.
- **Recording the fact** costs nothing, moves no label, and gives C1 the distinction it
  actually wants.

The PM adopted this reframing at `26736` as *"a better reading than my brief's"*. It is
recorded here because a disposition that silently improves on its own brief is
indistinguishable from one that misread it.

## §C.3 Candidate 3 — §11.1 versus a later §9 tie-break. **DISPOSITION: AMEND.**

**Ruling E's outcome is adopted unchanged — it is already applied and moves 0 rows. What
was missing from Part A is the general rule**, and the brief named it: *the precedence is
a practice, not a rule.* It was applied twice on MES-81 (families C and E), **both times
against the PM's own tie-break**, and nothing in Part A said it held.

§9.1 states it in five clauses. **Two are new rather than transcribed**, and they are the
two that would have prevented the conflict rather than merely resolving it:

- **Clause (2) — "in BOTH directions."** A precedence rule that only runs in the direction
  suiting the reader is not a precedence rule. This is what makes the two MES-81
  applications *lawful* rather than merely convenient.
- **Clause (4) — reconcile over withdraw, AND the reconciling distinction becomes Part A
  text.** Without the second half, clause (4) would ratify a preference for reconciliation
  while leaving the reconciliation itself living in a register. §2.4 is clause (4)
  discharged on the case that produced it.

Clause (5) — *a gate-4 weakness is never expressed by failing gate 2* — is the
transferable form of the error itself, and §4 already exists for it: **gate 4 never
excludes.**

**The rejection branch, priced.** Rejecting candidate 3 means withdrawing either §11.1 or
the tie-break. Withdrawing §11.1 discards a ratified worked example and moves 5 rows;
withdrawing the tie-break reopens the R1 residual `§B.5` flagged as the boundary B2a
would meet most often. **Reconciliation costs 0 rows and discards neither** — which is
why clause (4) prefers it, stated as a rule rather than as this instance's convenience.

**On the numbering of §2.4, so MES-93 does not collide with it.** My plan proposed §2.4
as the slot for promoting tie-break `26026`; the PM declined that here and raised
**MES-93**. §2.4 in this file is therefore the **reconciling line**, not the declined
promotion. MES-93 will need a different number.

## §C.4 §6.1's `inherited_from`, populated — and the enumeration is EXHAUSTIVE, not a sample

**Result: exactly 3 rows, well inside the 40-row stopping rule.** The rows, and the helper
each inherits from:

| row | label | `inherited_from` |
| --- | --- | --- |
| `MCP.ClientTest` / `"times out a pending request"` (`client_test.exs:366`) | `ET-CC`, `mixed` | `test/mcp/client_test.exs:59` |
| `MCP.ClientTest` / `"notifies pending requests when the transport closes"` (`:373`) | `ET-CC`, `mixed` | `test/mcp/client_test.exs:59` |
| `MCP.ClientTest` / `"handles multiple concurrent requests"` (`:443`) | `ET-CC`, `mixed` | `test/mcp/client_test.exs:59` |

**The field names the HELPER's declaration line (`:59`, `defp do_connect/2`), not the
assertion inside it.** §6.1's ratified words are *"naming the helper's `file:line`"*, and
the declaration is the stable identifier; the inherited assertion itself is
`client_test.exs:62`, `assert discover["method"] == "server/discover"`.

**Why exactly three — established by enumeration over the whole of `test/mcp/`, per epic
ruling 4, not by trusting family C's list.** Three steps, each with its control:

1. **Every asserting helper in `test/mcp/`, from the AST.** A line-oriented scan
   mis-attributes here — a one-line `defp` followed by a `setup` swallows the block — so
   the sweep walks the parsed AST of all 39 files.
   **Result: 1.** `defp do_connect/2`, `client_test.exs:59`. **Zero** `setup`/`setup_all`
   blocks in `test/mcp/` contain an assertion.
2. **The scan is not vacuous — POSITIVE CONTROL.** It reports what it *sees*, not only
   what it selects: **39 files walked, 137 `def`/`defp` reached, 10 `setup`/`setup_all`
   reached.** A scan returning one hit and a scan that walks nothing are indistinguishable
   from the hit count alone.
3. **The scan is LIVE — MUTATION CONTROL.** Injecting `assert 1 == 1` into
   `state_handle_test.exs:6`'s `setup` block moved the count `0 → 1` and the block was
   named in the output. Reverted; tree re-verified clean. *A decoy cannot catch a scan
   that walks nothing; only a positive control can.*

**And `test/support/` was checked rather than assumed.** `grep -rn 'assert\|refute'
test/support/` returns **8** hits, and **all 8 are prose in comments and `@moduledoc`s** —
zero asserting helpers. `test/fixtures/` returns 0.

**So the antecedent population is the callers of `do_connect/2`, and they were re-derived
from the AST at this tip rather than inherited.** 17 call sites, resolved to their
enclosing `test` declarations and joined to the delivered register by `{file, line}`:

- **14 are already `ET-CC` on their own assertions** — §6 lifts nothing that was not
  already lifted, so §6.1's antecedent (*"a unit's ONLY gate-2-and-3-passing assertion is
  inherited"*) is FALSE for them and the field is correctly absent.
- **3 carry `adjudication.ruling: "C"`** — the only three with no wire assertion of their
  own. Those are the three above.

> **S8-2, found doing this and NOT fixed here.** `etcc-register.md` §7 family C cites those
> three rows as `:353`, `:359`, `:425` and their call sites as `143, 166, 184, …`. **None
> of those line numbers resolves any more**: MES-84 (`18df3a6`) inserted `@tag :etcc` lines
> into `client_test.exs`, shifting declarations by up to +18. `:353` and `:141` are now
> **blank lines**; `:359` now lands on `test "close is idempotent"` — **a different real
> test**, which is the dangerous shape, because a stale citation that resolves to something
> plausible reads as correct. The **register JSON is unaffected** — its `evidence` fields
> already carry the current lines (`146, 170, 189, …`), which is what my AST re-derivation
> reproduced exactly. This is prose-vs-data drift in MES-81's document, the same shape as
> S8-1 one document along. **Recorded, not fixed**: it is dozens of citations across a
> document this ticket only amends at one figure, and absorbing it would be the scope
> growth the seat model exists to prevent. Raised for the PM to scope.

**Guard 22 makes the field non-decorative**, and it has been seen to go red on each of its
limbs rather than merely written. **The five mutations are committed to the project's own
guards control**, not run from a scratch script — a run tree in `/tmp` is not evidence
anyone else can re-execute:

    mix run conformance/controls/etcc_register_controls.exs guards
      ... 28/28 guards fired.      (23 before this ticket, + guard 22's five limbs)
      CONTROL: the unmutated decisions file builds cleanly, so the guards above
               are discriminating rather than refusing everything.

| mutation | guard fired on |
| --- | --- |
| `inherited_from` on an `ET-OUT` row | per-MEMBER field (label check) |
| `client_test.exs:99999` | does not resolve at this tip |
| `client_test.exs:62` (the assertion, not the helper) | not a `def`/`defp`/`setup` declaration |
| `client_test.exs:83` (`defp last_after_connect/2` — a real helper with no assertion) | helper contains no assertion |
| `"do_connect/2"` | not a `file:line` |
| **unmutated** | **builds — positive control** |

**Guard 22's limit, stated rather than left to be found:** it checks that the field names a
**real asserting helper**, never that it names the **right** one. Whether a member's own
assertions all fail gates 2 and 3 — which is what makes a claim *wholly* inherited — is
judgement, and no guard in this generator checks judgement.

## §C.5 The 26026 family stays decided OUTSIDE Part A, and MES-93 owns it

**Required by the PM's Q3 ruling (`26736`), and it is the one disclosure that stops Part A
being read as complete when it is not.**

The decode-boundary tie-break of 2026-08-23 (MES-81 comment `26026`) — *an assertion on a
decoded value handed back through the public API passes gate 2 when the asserted VALUE is
the wire value verbatim; the container may change, the value may not* — **governs roughly
90 client-side rows**, the largest family in the register, and is the single largest
reason `ET-CC` came out above the declared 200–260 band. It lives in
**`etcc-register.md` §6**, whose own text says promoting it *"needs its own MES-67-style
ratification and is not done by the back door of a tie-break"*.

**It was NOT promoted here.** The PM declined it as a fourth candidate on a
three-candidate ticket and **raised MES-93**, to run before C1.

**This is an incompleteness, not an inconsistency, and §9.1 clause (2) is why.** Clause (2)
voids a tie-break only **where Part A decides**. Part A does not yet decide that family, so
`26026` remains a valid gap-filler until MES-93 promotes it. **Recorded here so that a
reader of Part A who has just read clause (2) does not conclude the family is decided by
Part A — it is not, it is decided by `etcc-register.md` §6, and MES-93 is the named
owner.** A criterion that lives outside the criterion file is the MES-80 shape; naming the
owner is what keeps it visible instead of silent.

## §C.6 The S7-15 cross-check, run as a PASS and printed per row

**The obligation:** every amendment is checked against the worked examples of **every
section it lands in**, not only against the rule it replaces. Candidate 3 *is* that
failure — a tie-break authored to fill §9's residual class **R1** contradicted §11.1's
worked example three sections away, and R1 is the boundary `§B.5` flagged as the one B2a
would meet most often.

**A no-movement result is printed as a checked result per row, never as silence:**
*"checked and nothing moved"* and *"never asked"* read identically when only the answer is
printed. Every label below was **re-derived from the delivered register at this tip**, not
carried from `etcc-register.md` §5.

### §11's nine worked examples — all eight in-scope labels reproduce, both split figures included

| §11 | unit | ratified | at this tip | verdict |
| --- | --- | --- | --- | --- |
| 1 | `DispatchTest` / `initialize … -32022` | `ET-CC` | `ET-CC` | reproduces |
| 2 | `MethodsTest` / `"request methods"` | `ET-ADJ` | `ET-ADJ` | reproduces |
| 3 | `ClientConformanceTest` / control-on-the-control | `ET-CTRL` | `ET-CTRL` | reproduces |
| 4 | `JsonSchema202012Test`, 47 units | **31 / 16**, 15 at gate 2 + 1 at gate 3 | **47 units, 31 / 16**, gates `%{2 => 15, 3 => 1}` | reproduces, split figures included |
| 5 | the 13 doctests | **6 / 5 / 2** | **13 units, `ET-CC` 6 / `ET-ADJ` 5 / `ET-OUT` 2** | reproduces |
| 6 | `ToolTest` / the 2 generated booleans | `ET-OUT` at gate 3 | **2 units, `ET-OUT`, gate 3 ×2** | reproduces |
| 7 | `RoutingHeadersTest` / `"a request carries the body method"` | `ET-CC`, one unit | `ET-CC` | reproduces |
| 8 | `CensusTest` (`test/conformance/`) | `OUT-OF-SCOPE`, gate 1 | present in `out_of_scope`, gate 1 | reproduces |
| 9 | `CapabilityHonestyTest` | `ET-ADJ` | `ET-ADJ` | reproduces |

**§11 is the register's own control (`etcc-register.md` §5), so a §11 example that stopped
reproducing under an amendment would be a blocking finding, not a note.** None did.

### §11.1's five doctest groups, and §5.2's two cases

| group | n | ratified | at this tip |
| --- | ---: | --- | --- |
| `HeaderMirror.encode_value/1` | 4 | `ET-CC` | `ET-CC` ×4 |
| `Extensions.from_meta/1` | 2 | `ET-CC` | `ET-CC` ×2 |
| `Extensions.normalise/2` | 3 | `ET-ADJ` | `ET-ADJ` ×3 |
| `Extensions.valid_identifier?/1` | 2 | `ET-ADJ` (**§5.2's `ET-ADJ` side**) | `ET-ADJ` ×2 |
| `Extensions.reserved_prefix?/1` | 2 | `ET-OUT` (**§5.2's `ET-OUT` side**) | `ET-OUT` ×2 |

**§5.2's two cases are the last two rows** — they are the same boundary worked from both
sides, and **§2.3 is the rule most likely to have disturbed them**, since both turn on
whether `lib/` consumes the artefact. Neither moved: §5.2 keys on a **consumption** call
site for `ET-ADJ`, §2.3 on the **producer** of asserted bytes for gate 2. They are
adjacent questions, and the amendment does not conflate them.

**§2.4 was checked against §11.1 specifically, because §11.1 is the example it reconciles
with.** `from_meta/1` stays `ET-CC` ×2 with the `from_meta(nil)` one recorded
`falsifiable: undetermined` — gate 4, exactly as §11.1 ruled. That is the outcome §2.4 was
written to preserve, and it is verified rather than intended.

### §6a's 50 boundary-directions, re-decided against §2.3(d) as ratified

Every predicate asked of the **whole table**, not of a sample:

| §2.3(d) predicate, asked of all 50 | violations |
| --- | ---: |
| a DEAD direction with **no** L2 record | **0** |
| a DEAD direction whose L2 record is not marked `ran` | **0** |
| a DEAD direction missing the **byte-probe** limb | **0** |
| a DEAD direction missing the **call-site enumeration** limb | **0** |
| a DEAD direction whose mutation was **impotent** (reddened none of its own units) | **0** |
| a direction with **live count 0** and no L2 record — the MECHANICAL trigger | **0** |
| a DEAD direction whose L2 verdict is `live` — L2 running the wrong way | **0** |

**50 directions, 19 dead, 31 live; 38 rows carry a `direction`, which is §2.3(b) visible
in the data.** **The zeros are self-controlling**: the check reads `l2.byte_probe` and
`l2.call_site_enumeration` by name, so a wrong field name would have returned **19**, not
0. It returned 0 on both.

### §10's nine negative categories — re-decided under the amended text

Categories, not rows, so each is re-decided by reading rather than by a count:

| §10 | category | does an MES-87 amendment change it? |
| --- | --- | --- |
| 1 | instrument tests (gate 1) | **no** — §1 is untouched; no amendment reaches gate 1 |
| 2 | instrument-responsiveness controls | **no** — §5.3 keys on apparatus; unaffected |
| 3 | bare-constant tests | **no**, and checked twice: §2.3 could look like it reaches these, but a bare constant has **no encoder at all**, so it fails gate 2 at §2's first clause before the liveness qualifier is asked. §11 example 2 confirms it — `ET-ADJ`, unmoved |
| 4 | internal-representation tests | **no** — §2.2's step test decides these; §2.3 asks a later question and only of assertions that *survive* §2 |
| 5 | predicates nothing acts on | **no** — §5.2's `ET-OUT` side, verified unmoved above |
| 6 | behaviour outside the spec's domain | **no** — gate 3; no amendment touches gate 3 |
| 7 | dependency-behaviour tests | **no** |
| 8 | operator-facing output, **lifted by §6 when the unit also asserts an encoded message** | **NO LABEL MOVES, but this is the category §6.1 lands in.** §6.1 leaves §6's lift exactly as it is and adds recording. The seven `JsonSchema202012Test` units §10 names are lifted by their **own** second assertion, not an inherited one, so §6.1's antecedent is FALSE for all seven and none takes an `inherited_from`. Verified: example 4 still reads 31/16 |
| 9 | public-API convenience shape (**R1**) | **REFINED, and this is the one that moves substantively.** §2.4 replaces *"is this public-API convenience?"* — which describes intent — with *"is there a wire state this value is the decode of?"*, which is a test. **No label moves**: the delivered register already applies it. What changes is that R1's boundary now carries a worked case on each side **inside Part A**, which `§B.5` recorded as missing and named as *"the one a second sweeper reads differently"* |

## §C.7 AC3 and AC4 — the quantification, with its no-op control first

**AC3 requires every rows-affecting change to be MEASURED by regenerating the register,
never estimated. The measurement is only meaningful if a zero-diff can fail**, so the
no-op control was run first.

**Step 0 — the no-op control.** Regenerate with **nothing** changed:

    md5  ceee665bf77c155336b6388f64ec6108   (committed)
    mix run conformance/build_etcc_register.exs
    md5  ceee665bf77c155336b6388f64ec6108   (regenerated)   git status: clean

**Byte-identical.** So the later zero-diff means *the amendment moved nothing*, not *the
generator does not respond to its inputs*.

**A fact AC3 could be read against, and it is stated rather than assumed:** the generator
does **not** apply the criterion. `conformance/data/etcc-decisions.json` is **579
hand-authored rows**; the generator joins them to MES-83's artefact and fires its guards.
So a rows-affecting amendment is an **edit to the decisions file, re-decided per row** —
the generator then proves the arithmetic. Nothing in this ticket could have re-labelled a
row without a visible edit to that file.

**Step 1 — the measurement, row by row against the pre-amendment register.**

| measured | result |
| --- | --- |
| rows | 579 → 579, key sets equal both ways |
| **rows differing on any PRE-EXISTING field** | **0** |
| **LABEL moves** | **0** |
| **excluding-gate moves** | **0** |
| `out_of_scope` | 428 → 428, **arrays identical** |
| `totals.by_label` | `ET-CC` 281 · `ET-ADJ` 88 · `ET-OUT` 206 · `ET-CTRL` 4 — **every one unchanged** |
| totals changed | **one**: `inherited` `nil → 3` (a new counter) |
| new row field | **one**: `inherited_from`, non-null on **3** rows |

**Predicted 0 and measured 0 — and the two are reported as different things.** The PM's
stop-rule was that *any* nonzero label move is a blocking surprise to hand up rather than
absorb, because a nonzero would mean the amendment says something the register does not.
It did not arise.

**AC4 — regeneration and restatement.** **No label moved, so no restatement of MES-81's
totals is owed**, and that is a measured result rather than a skipped step. §3's tables in
`etcc-register.md` stand unchanged and were verified to stand, not assumed to. The one
figure that *was* restated is the 413 → 428 correction (**S8-1**), which is a
**pre-existing** prose-vs-data defect from MES-84 and not something this ticket caused —
it is marked in place at `etcc-register.md` §2 rather than silently edited, and the `:425`
occurrence was **re-run** through the totality control rather than hand-edited.

**Nothing is deferred.** No part of the quantification is handed to another ticket.

## §C.8 What MES-87 did NOT do, stated so each absence reads as a decision

1. **Did not re-run MES-81's 50-direction mutation sweep.** `git diff --name-only
   85d50fa HEAD -- lib/` returns **0 files**, so every liveness verdict is a claim about a
   tree that has not moved, and §2.3(e) is satisfied at this tip. Re-running it is
   **MES-88's deliverable**, not this ticket's evidence.
2. **Did not re-sweep the 579.** The population is unchanged and §7's invariant closes at
   579 here.
3. **Did not edit `lib/`** (epic ruling 3). No amendment implied a code change; had one, it
   would have been raised for the PM to scope rather than decided here.
4. **Did not promote tie-break `26026`** — PM Q3 ruling; **MES-93** owns it. Disclosed in
   §C.5 rather than left implicit.
5. **Did not fix the `client_test.exs` citation drift in `etcc-register.md` §6/§7**
   (**S8-2**, §C.4). Recorded and raised.
6. **Did not correct §1's ratified 285.** Part A's rule is that drift is reported, never
   corrected in ratified text.
7. **Did not edit the Working Procedure page's Confluence citation register** — PM Q2
   ruling: *"that is not this ticket's."* The two in-repo provenance artefacts **were**
   updated: §0's ratification-record header, and §B.4(ii)'s enumeration (14 → 17 ids).
