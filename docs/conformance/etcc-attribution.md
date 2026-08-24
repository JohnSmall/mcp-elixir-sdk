# ET-CC × leg × CG1–CG7 — the attribution

**Delivered on MES-82 (B2b), Sprint 7, epic MES-65.** Takes B2a's 281-member
register and adds the two attributes C1 and D1 need and the membership criterion
does not produce: **which leg a member's claim is about**, and **which of
`CG1`–`CG7` it discharges**.

**Repo is source of truth; there is no Confluence mirror of this file.**

**CORRECTION ROUND 1 (review `26096`–`26099`, PM contract `26100`–`26101`).** Three
things in this file moved, and each is marked where it lands rather than only
here. **§2.3's leg discriminator was a WORDING test and a reviewer broke it in one
mutation**; it is replaced by the PM's mechanical rule (both limbs), under which
**one member re-attributes** — the populations are now **145 / 107 / 29**, not
146 / 107 / 28. **§3.3's CG7 count drops 35 → 31**: four rows were held by a
*purposive* basis, and A4's CG7 **gap** statement does not cover them. **§1(b)'s
correlation is demoted** from evidence about the authoring to a display of how
coarse a module-level proxy is, and the proxy rule is now implemented as a control
instead of only described.

| | |
| --- | --- |
| `conformance/data/etcc-attribution.json` | **the one authored source** — 281 rows, `key` + six attributes, nothing else |
| `conformance/lib/mcp/conformance/etcc_attribution.ex` | the builder; joins B2a's register by key, fail-closed |
| `docs/conformance/etcc-attribution.json` | the derived enriched register |
| `conformance/controls/etcc_attribution_controls.exs` | 16 guards each seen to refuse, plus `strip-boundary`, `sweep`, `reproduce`, `proxy`, `figures` |
| `test/conformance/etcc_attribution_test.exs` | AC5's cross-file test, in gate 5 |

---

## §0 What this file adds, and what it must not re-state

The member set is **B2a's**, the row key is **MES-83's**, the CG-side answer is
**A4's** and the token grammar is **MES-77's**. All four are cited and none is
restated: a definition living in two places diverges, which is the whole reason
MES-80 existed.

**This artefact JOINS B2a's register. It does not copy it.** The authored source
carries `key`, `leg`, `leg_reason`, `cg`, `cg_basis`, `tokens` and
`contradicts_oc` — and the builder **refuses** any field name that also names a
register row field. So `label`, `line`, `file`, `boundary` and `evidence` keep
exactly one home. Two registers over one fact is the S5-31 two-indexes hazard,
and here its antecedent is unrepresentable rather than merely discouraged.

---

## §1 `boundary` was not used as a leg proxy, and that claim is checkable

The brief warned that B2a's `boundary` field is not a leg attribution:
`MCP.Client` as a boundary means *"the asserted bytes come from this module's
encoder"*, not *"this member is a client-leg claim"*.

**A promise not to take the shortcut is unfalsifiable, so none is offered.** Two
things stand in its place.

**(a) The build cannot read it.**
`conformance/controls/etcc_attribution_controls.exs strip-boundary` deletes
`boundary` from **all 579** register rows, re-runs the whole build and compares:

    register rows carrying `boundary`: 579 of 579
    md5 with    boundary: f0ed1797b9ad1f6e6516e82b0400b272
    md5 without boundary: f0ed1797b9ad1f6e6516e82b0400b272

**The bound on what that proves, stated rather than left to be assumed.** It
establishes that no *derivation* in this build consults `boundary`. It cannot
establish what a human read while authoring — nothing could, and a control
implying otherwise would be worse than none.

**And the reviewer sharpened the bound further, correctly** (`26098`(a)): the
result was **entailed by the artefact's architecture before the control ran** —
the authored source is a static hand-written file and the builder only joins and
validates, so there is no path by which a derivation *could* read the field. So
this is a **well-formedness property, not a discovery**, and the honest statement
of what it earns is a **localisation**: every leg decision lives in exactly one
place, 281 hand-authored `leg_reason` strings, so an auditor knows the whole of
the judgement is there and nowhere else. That is worth having; "no derivation
consults the field" oversells it.

**(b) The correlation, measured — and DEMOTED in correction round 1 to what it
can actually support.** A boundary-driven rule (`MCP.Client` → client,
`MCP.Server.*`/plug → server, anything else → `none_determinable`) agrees with the
reading on **164 of 281 — 58.4%**:

| boundary proxy says | this file says | n | |
| --- | --- | --- | --- |
| `server` | `server` | 87 | agrees |
| `client` | `client` | 48 | agrees |
| `none_determinable` | `none_determinable` | 29 | agrees |
| `none_determinable` | **`client`** | **59** | disagrees |
| `none_determinable` | **`server`** | **58** | disagrees |

**Reproducible, which it was not before.**
`etcc_attribution_controls.exs proxy` implements the rule and prints this table,
because the reviewer's first attempt at reproducing it got a different number and
**the rule existed only as a parenthetical** (`26098`(b)). Two readings are
permitted by that parenthetical and they do not agree:

| reading | agreement | disagreements NOT of the form *(proxy abstains, file decides)* |
| --- | --- | --- |
| **strict** — every `boundary` entry leg-specific **and** agreeing | 164 / 281 = 58.4% | **0** |
| loose — any leg-specific entry decides | 189 / 281 = 67.3% | **3** |

**§1(b) means the strict reading, and the control now says so rather than leaving
it to be inferred.** The loose reading is printed beside it because it does *not*
have the one-directional property below — which is exactly why the reading has to
be named. The three opposite-direction cells under the loose reading are the
reviewer's finding, reproduced (it measured two; `self_compatibility_test.exs:97`
became a third when §2.3's new rule moved it).

**WHAT THE CORRELATION DOES NOT DO, stated because this file previously implied
otherwise.** It was offered against the hypothesis *"the author took the boundary
shortcut"*, on the reasoning that a shortcut-taker would score 100%. **That is
true only of someone applying the strict proxy mechanically, which nobody would.**
The shortcut actually worth worrying about is *start from `boundary`, then resolve
the residue by reading call sites* — and that produces **exactly the observed
shape**: agreement wherever the boundary is unambiguous, the whole disagreement
mass inside the residue, no crossing cells. **So 58.4% cannot discriminate the
clean method from the shortcut, and no correlation could.** The reviewer's framing
is adopted: read the table as *a display of how coarse a module-level proxy is*.
The claim that bears on the authoring is (a)'s localisation plus the per-function
table below — which a reviewer checked row by row independently and which held.

**Two things in the table are still findings, and neither is the percentage.**

*There is no `client`→`server` or `server`→`client` cell.* Where the boundary
names a leg-specific module the reading never contradicts it — so the
disagreement is not noise, and the two instruments are not simply unrelated.

*Every one of the 117 disagreements is the proxy answering `none_determinable`
where a per-**function** measurement resolves a definite leg.* A shared
`MCP.Protocol.*` module is not shared function-by-function:

| function | only `lib/` call site | leg |
| --- | --- | --- |
| `HeaderMirror.headers_for/2`, `validate_tool/1`, `describe/1` | `client.ex:780,889,894` | client |
| `HeaderMirror.encode_value/1` | `streamable_http/client.ex:379` | client |
| `HeaderMirror.decode_value/1` | `plug.ex:906` | **server** |
| `SSE.encode_event/1`, `encode_message/2`, `comment/0` | `plug.ex:687,713,723,780,1011` | server |
| `SSE.new_parser/0`, `feed/2` (→ `decode_event/1` at `sse.ex:216`) | `streamable_http/client.ex:569` | **client** |
| `Discover.Result.to_map/1` | `dispatch.ex:150` | server |
| `Discover.Result.from_map/1` | `client.ex:539` | **client** |
| `Meta.from_params/1`, `validate_protocol_version/2` | `dispatch.ex:163,165` | server |
| `Messages.Subscriptions.*` (10 functions) | `dispatch.ex`, `subscription.ex` | server |
| `Extensions.normalise/2` | `client.ex:971` **and** `server/config.ex:253` | both |
| `Extensions.from_meta/1` | **none on either leg** | neither |

So the transferable form is **S7-26**: *a module-level attribute cannot answer a
function-level question.* Read as a leg proxy, `boundary` would have put 117 of
281 members — 41.6% — into a residue that is not there.

**The per-function table is the load-bearing measurement, and it survived review
row by row** (`26098`): there is not a single `import` in `lib/`, so a
bare-basename grep here cannot be defeated by an alias — S7-16's failure mode is
closed by construction rather than by care — and the two rows that could only fail
toward a reassuring answer both hold for the right reason (`Extensions.from_meta/1`
has no caller because `extensions.ex:374` is inside a `@doc` block and `:415/:418`
are doctests; `Stdio` greps to zero call sites and is **not** recorded as
callerless, because it is reached through `state.transport_module.send_message/2`
from both `client.ex` and `server/connection.ex`).

---

## §2 Job 1 — the leg, and which way the method fails

**THE RULE — ratified at comment `26100`, and MECHANICAL. It replaces the wording
test this file shipped in round 1, which a reviewer broke with one mutation.**

> A member has a **definite leg** iff it carries **at least one assertion that a
> mutation of that leg's code falsifies and no mutation of the other leg's code
> falsifies**. It is **`none_determinable`** iff **no leg is definite** — every
> assertion it carries is falsified only by code both legs reach, or by code
> neither reaches.
>
> **Second limb.** A decode/parse applied to **our own encoder's output**
> exercises both directions and is a **round-trip**: its assertion is falsified
> from either side, so it makes neither leg definite. A decode/parse applied to a
> **literal** exercises only that direction and is an **independent single-leg
> claim**. *Whose output the decode consumes is checkable by reading the call*,
> which is what keeps this mechanical.

**A member can be definite for BOTH legs, and the rule as ratified does not name
the outcome.** It happens when a member carries one client-definite assertion and
one server-definite assertion — two independent single-leg claims, not a
round-trip. Resolved as **`none_determinable`**, by the precedent already in this
file and unchallenged at review: `capabilities_test.exs:191` (§2.4 class 3). The
argument is the consumer's: C1 asks *which OC checks can this member match*, and a
member whose claims span both legs can match on either — which is what
`none_determinable` means here (§2.4's opening, §7(5)). **Recorded as a gap in the
ratified rule rather than absorbed**, because the third outcome is a real one and
the vocabulary has no word for it.

`server` if only the `MCP.Server.*`/plug path's mutations make it definite;
`client` if only `MCP.Client`'s do; `none_determinable` **with a reason**
otherwise.

**Read in the test body, never in the register's prose.** PM instruction at
comment `26090`: B2a's F13 was a wrong trio propagated because a correction was
checked against a comment rather than against the tree, and the register's
`evidence` field is exactly that kind of secondary copy.

### §2.1 The stated failure signature, and the result against it

A wrong method here fails **toward a definite leg**, because a protocol-level
claim is normally exercised through some server or client entry point. A clean
two-way split with a small residue is what a wrong method produces, and it reads
as success. So an **under-sized third population was named in advance as the
primary failure signature**.

**Result under the ratified mechanical rule: 145 server, 107 client, 29
`none_determinable` — 10.3% residue.**

**What moved, and it is one row.** `transport/self_compatibility_test.exs:97`
(*"REACHABILITY CONTROL: an encoded Mcp-Name is decoded before comparison"*) was
`server` in round 1 and is `none_determinable` now. Round 1's figures were
146 / 107 / 28. **The reviewer expected a wording change rather than a
re-attribution** (`26099`); the rule returned a re-attribution, and the rule wins
(`26100`). Nothing else moved: the re-derivation and its instrument are in §2.3.

### §2.2 The mutation asymmetry, as a design constraint

A mutation of a shared function that reddens members on **both** legs *proves*
the claim is two-legged. One that reddens only one leg's members **does not
prove** single-leg — it only failed to prove shared. **A mutation proves LIVE,
never DEAD** (B2a's S7-19). So a mutation can promote a member **into**
`none_determinable` and can never be cited to move one **out**. The instrument is
built to fail against the tidy answer rather than toward it.

**A BOUND ON THE RATIFIED RULE ITSELF, and it is the same shape.** The rule has
two halves per leg: *some assertion this leg's mutation falsifies* — **positive,
and mutation-checkable** — and *no mutation of the other leg's code falsifies it*
— **negative, and NOT mutation-checkable at all**, because it quantifies over
mutations nobody has run. So the rule is not fully mechanical in the sense of
"decidable by running something": its negative half is discharged by a
**reachability argument** over `lib/` call sites (§1's table), which is the same
instrument, with the same reach, as B2a used. Where the negative half is settled
by a mutation instead, that is because a mutation of the *other* leg reddened the
same assertion — which proves the assertion is not single-leg, LIVE not DEAD, and
so runs in the permitted direction. **Every claim below says which of the two it
rests on.**

### §2.3 The discriminator, re-derived — the wording test a reviewer broke, and the mechanical rule that replaced it

**What round 1 shipped, and why it failed.** It separated
`routing_headers_test.exs:206` from `header_mirror_test.exs:367` on whether the
wording made the decode *"the claim"*. The reviewer showed in one move that this
does not separate the rows it is applied to. The two test names are:

| | test name |
| --- | --- |
| `routing_headers_test.exs:206` | *"a non-ASCII tool name is encoded, **and decodes back to the body value**"* |
| `header_mirror_test.exs:367` | *"**every encoded value decodes back to exactly the body value**"* |

Applied as stated, the round-1 rule puts the first on the second's side. **A test
name is written to describe the scenario, not to identify the implementation under
test** (`26100`), so a wording test was always going to fail here. That is the
corrected **S7-27**.

**The re-derivation, and the instrument.** Two things were run, both at the
delivered tip, both reverted with the tree verified clean:

**(1) The candidate set, bounded and with a positive control.** Every member whose
unit — closed over the file's `setup` blocks and the local helpers it calls — names
a leg-specific function or entry point from **both** legs. **47 members**, of which
**12 were already `none_determinable`** and **35 needed adjudicating**. *Positive
control:* the 7 members this file independently classes as end-to-end must all
appear, and all 7 do — the first version of this sweep read the unit body alone and
found **1 of 7**, because `integration_test.exs` drives both legs inside a
`start_pair/0` helper. **A candidate sweep that finds one of seven is what a
missing positive control looks like**, and it is why the closure exists.

The sweep is deliberately **over**-inclusive: it counts `Bandit.start_link` as a
server marker, which drags in 15 members of `routing_headers_test.exs` and
`client_conformance_test.exs` whose Bandit plug is a **test double**
(`CapturePlug`, `CanaryPlug`) and not our server. Over-inclusion is the safe
direction — a superset of candidates, each then adjudicated — and it is stated
because a reader must not read "47 candidates" as "47 doubtful rows".

**(2) Mutations, on the axis where the round-1 rule broke.** `decode_value/1`
(server-only, sole `lib/` call site `plug.ex:906`) and `encode_value/1`
(client-only, sole `lib/` call site `streamable_http/client.ex:379`), each
neutralised to the identity function:

    decode_value/1 -> identity      994 tests, 6 failures
      header_mirror_test.exs:367, :425
      routing_headers_test.exs:206, :239
      self_compatibility_test.exs:97, :167

    encode_value/1 -> identity      994 tests, 11 failures
      header_mirror_test.exs:31 (x3 of its 4 doctests), :348, :380, :425
      routing_headers_test.exs:206, :239, :307
      self_compatibility_test.exs:97, :167

`decode_value/1 -> identity` reproduces the reviewer's six exactly, which is the
cross-seat check on the instrument itself.

**The row that moves: `self_compatibility_test.exs:97`, `server` → `none_determinable`.**
It is reddened by *both* mutations, and the failure lines say why — two assertions,
one definite on each leg:

| assertion | falsified by | not falsified by | leg |
| --- | --- | --- | --- |
| `:100 assert String.starts_with?(header, "=?base64?")` | `encode_value` mutation — fails **at :100** | any server mutation: `header` is computed before the post, and the recorder never reaches our server | **client-definite** |
| `:109 assert conn.status == 200` | `decode_value` mutation — fails **at :109** | the `encode_value` mutation — **measured**: with `:100` replaced by `_ = header`, the client mutation leaves `self_compatibility_test.exs:97` GREEN and only `self_compatibility_test.exs:173` reddens | **server-definite** |

The second row's negative half is a **measurement, not a reachability argument**:
ExUnit aborts at the first failure, so the only way to see whether `:109` survives
a client mutation is to remove `:100` and re-run. It survives. **Two definite legs
→ `none_determinable`**, per the rule's gap resolution in §2 above.

**The rows that do NOT move, with the reason each stays.**

* **`routing_headers_test.exs:206` and `routing_headers_test.exs:248` stay `client`.** Each carries an assertion about the
  header our client produced (`assert String.starts_with?(header, "=?base64?")`;
  `refute headers["mcp-name"] =~ "\r"` and `refute Map.has_key?(headers, "x-injected")`)
  which no server mutation can reach, because the far end is `CapturePlug`. Their
  decode call is **not** server-definite, and this is measured rather than argued:
  the `decode_value` mutation fails `routing_headers_test.exs:206` at **:216** and `routing_headers_test.exs:248` at **:252**
  — the decode assertions — and the `encode_value` mutation reddens the same two
  members. **The same assertion falsified from both sides is not definite for
  either.** That is the second limb: the decode consumes our own encoder's output.
* **`header_mirror_test.exs:438` stays `none_determinable`, for a DIFFERENT reason than round 1 gave.**
  Round 1 called it a round-trip. It is not: both of its calls take a **literal**
  (`encode_value("=?base64?literal?=")` and
  `decode_value("=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=")`), so neither consumes the
  other's output. It is **two independent single-leg claims on opposite legs** —
  the same class as `capabilities_test.exs:191`, and the reviewer was right that
  round 1's rule needed a third case for it. The label is unchanged; the reason in
  the artefact is corrected.
* **`header_mirror_test.exs:367` stays `none_determinable`, and now by the second limb explicitly.**
  Its `headers` come from `HeaderMirror.headers_for/2` in the `describe`'s own
  `setup`, so the decode is applied to our own encoder's output. Single assertion,
  falsified from either side, neither leg definite.
* **`self_compatibility_test.exs:116`, `:128`, `:140`, `:155` stay `server`** — they name `encode_value`
  but assert nothing about its output, and the `encode_value` mutation **does not
  redden them**, which is the negative half measured rather than argued.
* **`header_mirror_test.exs:450` stays `server`** — `decode_value` applied to two literals, and the
  `encode_value` mutation does not redden it.
* **The 14 `subscriptions_stream_test.exs` rows that parse with `SSE.feed/2`
  (client-only) stay `server`.** Second limb again: the parse is applied to **our
  own server's stream**, so every assertion downstream of it is falsified from
  either side and none is client-definite; the assertions that are *not* downstream
  of the parser (`assert response.status == 200`, `assert_receive`/`refute_receive`
  over the handler) touch no client code at all. Same for the 15 `Bandit`
  false-candidates, whose far end is a double.
* **`capabilities_test.exs:46`, `sse_test.exs:187`, `subscriptions_stream_test.exs:374` stay `none_determinable`** as round-trips under
  the second limb, each a single assertion over a decode of our own encoder's
  output.

### §2.4 The 29 `none_determinable`, enumerated — six classes, no leftovers

**This is a result, not a leftover.** Such a member can match OC checks on
**either** leg, and a crosswalk assuming one leg would silently halve its
candidates.

**(1) End-to-end, both legs in one test — 7.** A mutation on either leg reddens
it, so the assertion constrains the pair.
`integration_test.exs:128,139,160,178,193,204`;
`transport/self_compatibility_test.exs:173`.

**(2) Round-trip — the decode/parse consumes OUR OWN encoder's output, so the one
assertion is falsified from either side — 4.**
`protocol/capabilities_test.exs:46`; `protocol/header_mirror_test.exs:367`;
`transport/sse_test.exs:187`; `transport/subscriptions_stream_test.exs:374`.
This is the rule's second limb; §2.3 names the call each one's decode consumes.

**(3) Two independent single-leg claims on OPPOSITE legs, so the rule makes both
legs definite and neither alone owns the member — 3.**
`protocol/capabilities_test.exs:191` ("neither is emitted when unset", asserted
over `ClientCapabilities` **and** `ServerCapabilities`);
`protocol/header_mirror_test.exs:438` (an `encode_value` literal **and** a
`decode_value` literal — moved here from class 2 in correction round 1, where it
was miscalled a round-trip); `transport/self_compatibility_test.exs:97` (the
client-produced sentinel at `:100` **and** our server's 200 at `:109` — the one
row the ratified rule re-attributed, §2.3).

**(4) A public API with no `lib/` call site on either leg — 7.**
`protocol/extensions_test.exs:35` (×2 doctests), `:386,391,405,423,435`. All
assert `Extensions.from_meta/1`, whose only appearances in `lib/` are its own
definition and doc examples. A mutation changes what a **consumer's handler**
sees, not what either of our implementations puts on or takes off the wire.
**For C1 this is the sharpest of the six**: these members cannot match any OC
check, because the harness drives our server or our client and this code is on
neither path.

**(5) Notification framing, which both legs emit — 3.**
`protocol_test.exs:64,76,125`. `Notification.new/2` is called from `client.ex`
**and** from `server/connection.ex`, `subscription.ex` and
`notification_collector.ex`.

**(6) A leg-agnostic transport — 5.** `transport/stdio_test.exs:28,50,74,93,116`.
`MCP.Transport.Stdio` implements the `MCP.Transport` behaviour and is driven by
`MCP.Client` and by `MCP.Server.Connection` alike — `connection.ex:3` names stdio
as an owner-based transport in as many words.

### §2.5 Per unit, never per file — and seven files prove it was necessary

A file-level label is not one wrong answer, it is a suppressed distribution
(A2's own correction). **Seven of the 30 files split across legs:**

| file | server | client | none_det. |
| --- | --- | --- | --- |
| `transport/sse_test.exs` | 8 | 10 | 1 |
| `protocol/header_mirror_test.exs` | 1 | 17 | 2 |
| `protocol/capabilities_test.exs` | 2 | 6 | 2 |
| `protocol_test.exs` | 2 | 5 | 3 |
| `transport/self_compatibility_test.exs` | 4 | 0 | 2 |
| `protocol/messages/discover_test.exs` | 1 | 1 | 0 |
| `transport/subscriptions_stream_test.exs` | 17 | 0 | 1 |

`sse_test.exs` is the clearest: 19 members in one file, splitting eight
server (the encode side, `plug.ex`-only) from ten client (the parse side,
`streamable_http/client.ex`-only) with one round-trip between them.

---

## §3 Job 2 — the CG join

### §3.1 The scoping fact that decides most of the answer

`CG1`–`CG7` are **the CG *client* series** — `docs/sprint_4_issues.md:4781` heads
Register 2 in exactly those words, and every one of its seven rows (`:4785-4791`)
names a client-side requirement (CG7's own title ends "client side"). Established
by reading that register, not assumed from A4.

**So a server-leg member cannot discharge a CG, and its `none` is a reasoned
result rather than a sweep's silence.** That is why 225 of 281 are `cg: none` —
and why each carries a `cg_basis` saying *which* kind of none it is. The builder
refuses a row with no basis: silence must not encode a decision.

### §3.2 Method: total enumeration. The sweep is only its control.

**The sweep was measured before it was proposed, on a set whose true answer A4
had published.** Over the 12 rows `cg-reconciliation.md` §3 names as CG1's and
CG7's end-to-end discharge, a SEP-number sweep over `spec_anchor` returns **7 of
12** — `:199, :222, :239, :342, :359` anchor to `streamable-http.mdx` line ranges
without naming the SEP. A **42% under-count, every loss in the "none"
direction**. Re-run at the delivered tip by
`etcc_attribution_controls.exs sweep`, which reproduces 7 of 12 exactly.

A check that can only fail toward the conclusion it is testing is not a check. So
the sweep is **disqualified as the method** and demoted to a control that can only
**accuse** the enumeration — it can never confirm it. At the delivered tip it
accuses **nothing**: every sweep hit is already assigned a CG.

**Both directions of HAZARD 2 guarded:**

* **False positive.** Correspondence is established against the check's
  `description` in A1's manifest, never against a scenario title. *Control:* the
  method is run against `ClientCustomHeaderNoMirrorNumber`, which A4 examined and
  **rejected** on the predicate (it asserts an *unannotated* `number` is not
  mirrored; our constraint is that an *annotated* one is rejected outright). **0
  members claim it.** The method agrees with A4's rejection.
* **False negative.** Guarded by the enumeration being total — the only guard
  that does not itself fail toward "none". The sweep's positive control runs
  **first**, gate-6a shape: `/2243/` returns 7, and a 0 there would mean the
  instrument is broken, not that the answer is none.

### §3.3 The assignments, per item

**CG1 — 10** (A4: 9). `routing_headers_test.exs:90,110,125,137,166,186,206,230,248`
(client) + `self_compatibility_test.exs:173` (`none_determinable`; CG1's T-CG1c
sentinel claim asserted end to end).

**CG2 — 14** (A4: 4 units, of which 2 are ET-CC). `client_conformance_test.exs:186,235`;
`client_test.exs:488,500,512,528,556,583,616,644,672`;
`capabilities_test.exs:140,151` (client) and `:181` (`none_determinable`).

**CG3 — 0.** No ET-CC member. Not implemented; owned by MES-38. Agrees with A4.

**CG4 — 1.** `client_conformance_test.exs:116`. Agrees with A4.

**CG5 — 0.** No ET-CC member. `discover_test.exs:37` **mentions** `cacheScope`
and asserts it **parses**; CG5 requires the client to **honour** it. Recorded as
`cg: none` with that basis — carrying `match-relation.md` §6's ratified
exclusion rather than re-deciding it, and agreeing with it.

**CG6 — 0.** No ET-CC member. Owned by MES-32. Agrees with A4.

**CG7 — 31** (A4 named 3 discharge sites). `header_mirror_test.exs:31` (×4
doctests), `:133,205,327,332,340,348,374,380,392,399,410,457,463` (client) and
`:360,425` (`none_determinable`); `routing_headers_test.exs:318,354,372`;
`client_tool_schemas_test.exs:83,125,156,178,235,279,389,427,455`.

**CG7 was 35 in round 1. Four rows left on review finding F2 — see §4.5**, which
reports the check against A4's CG7 **gap** statement either way, as the PM
required. Every one of the 13 `client_tool_schemas_test.exs` rows now carries a
**per-row** `cg_basis` citing its own assertion, replacing one shared string
repeated thirteen times.

**56 members carry a CG and 225 carry an explicit `none`** — `10 + 14 + 1 + 31 = 56`,
and `56 + 225 = 281`. The artefact's `with_cg` is that 56, derived from rows.

**The zeros are reported, not omitted** (A2d): `by_cg` in the artefact always
carries all eight keys, so a consumer never has to tell "zero" from "absent", and
a test asserts `CG3 == 0`, `CG5 == 0`, `CG6 == 0`.

### §3.4 The second question — the 15 unclaimed checks

`cg-reconciliation.md` §9(2) hands the complete claim-level client sweep to B2b,
and §4 records that a non-CG ET-CC member may match the 15 checks it lists as
unclaimed. **So each member was asked two questions, not one.** A member with no
CG but a real OC counterpart is a C1 row, and `cg: none` alone would lose it.

**14 members carry 19 state-1 tokens**, addressing **11 of the 15** checks
(several members carry more than one, and several checks are carried by more than
one member — the relation is many-to-many in both directions and edges are never
collapsed, per `match-relation.md` §1):

| check | members |
| --- | --- |
| `ClientSendsVersionHeader` | `routing_headers_test.exs:269`, `client_defects_test.exs:251,267` |
| `ClientVersionHeaderMatchesMeta` | `routing_headers_test.exs:269`, `client_defects_test.exs:251` |
| `ClientPopulatesMeta` | `client_test.exs:144` |
| `ClientSendsClientInfo` | `client_test.exs:144` |
| `ClientRetrySupportedVersion` | `client_defects_test.exs:289,327,350,367` |
| `ClientDeclaresRootsCapability` | `capabilities_test.exs:88` |
| `ClientDeclaresSamplingCapability` | `capabilities_test.exs:88` |
| `ClientDeclaresElicitationCapability` | `capabilities_test.exs:88` |
| `MRTRClientRequestStateEchoed` | `client_test.exs:270`, `client_defects_test.exs:143` |
| `MRTRClientNoStateOmitted` | `client_defects_test.exs:70,110` |
| `ToolAddNumbers` | `integration_test.exs:139` — **flagged, see below** |

**The four with NO ET-CC member, enumerated rather than left as a silence:**
`MRTRClientJsonRpcIdDifferent`, `MRTRClientParallelIsolation`,
`DefaultResultTypeComplete` and `WireSchemaValid`. 11 matched + 4 unmatched = 15.

* `WireSchemaValid` is **not** assigned, and that is a decision with a reason.
  Its description is *"Every JSON-RPC message the implementation sent is valid
  per the spec JSON schema"* — a **run-wide** property over all traffic, not a
  claim any single member asserts. Assigning it to the per-message encode tests
  in `protocol_test.exs` would be A5's "right count of the wrong question".
* `ToolAddNumbers` **is** assigned to `integration_test.exs:139`, **with the
  caveat carried into `cg_basis`**: the check drives our client against the
  harness's own `add_numbers` fixture, while our member drives our client against
  our own handler's `add`. Same required behaviour, different fixture. Recorded
  as a candidate for C1 to adjudicate, not as a settled edge.

**These are measurements, not bucket-2 entries.** Bucket 2 is C1's set and the
Sprint 7 build list; a wrong entry there schedules work that may already exist.

---

## §4 AC3 — member-side against CG-side, with the disagreements reported

A4 approached this from the CG side; this file approaches it from the member
side. **Where they disagree, no side is preferred** — both answers are recorded
and the reason for the difference is named.

| | A4 says | this file says | reading |
| --- | --- | --- | --- |
| **D1** | CG2 discharge = **4 ET-CC units**, `client_conformance_test.exs:186,211,219,235` | **2** of those are ET-CC (`:184`, `:232`); `:209` and `:217` are **ET-OUT** on gate 2. And the member set is **14**, not 4 | one defect with D2 — see below |
| **D2** | CG7's bucket-1 constraints = **9 ET-CC units**, `header_mirror_test.exs:113,120,134,157,169,195,207,224,233` | only `:133` and `:205` are ET-CC; the other **seven are ET-ADJ**. And CG7's member set is **31** (35 before §4.5's correction) | same defect |
| **D3** | CG7's W6 exclusion unit is `client_tool_schemas_test.exs:81` | **no row at 81.** `81` is the `describe` line; the `test` declaration is **82**, and 82 is ET-CC | S7-23, cross-referenced |
| **D4** | `conformance_request_state_test.exs` is "an obvious candidate" for the unclaimed MRTR five; B2b's sweep decides it | that file has **12 in-scope units, every one ET-OUT** — zero members. **But the sweep finds carriers elsewhere:** `client_defects_test.exs:70,110,143` and `client_test.exs:270` match two of the five | **overturns this file's own pre-measured answer** — see §4.2 |
| **D5** | CG5's mentioning-not-discharging witness is `discover_test.exs:37` (A4 §3) and `:47` (`match-relation.md` §6) | **NOT a disagreement.** Both are right: `35` is the `test` declaration (the register's key) and `47` is the `cache_scope` assertion. See §4.4 — this ticket's own plan got this one wrong | S7-23, cross-referenced |
| **D6** | CG7's gap is *mirror designated parameters / encode unsafe values / exclude invalidly-annotated tools* | round 1 assigned CG7 to **4 rows none of those three limbs reaches**, on a *purposive* basis. **Overturns this file's own round-1 count: CG7 35 → 31** | §4.5 — the second self-overturn, and the only one a reviewer found rather than this ticket |

### §4.1 D1 and D2 are ONE defect, and naming it is worth more than the rows

**It is not a defect in A4.** A4 built and guard-checked all seven CGs validly
against its own question, and it ran **before** the gates had been applied per
unit, so it could not have used B2a's answer.

*A4's discharge layer counts units that **CLOSE THE GAP**. B2a's ET-CC criterion
counts units that **ASSERT A WIRE ARTEFACT** (gate 2). Those are different
questions asked of the same lines.* Neither side is wrong about its own question.
What is wrong is **reading one side's count as the other's member list** — which
is exactly what this Job-2 join would have done had it taken A4's discharge rows
as the member list instead of joining from the member side.

This is **S7-25**, and §5's **two** carrier-less tokens are the third instance of
the same defect rather than a separate residual. (Round 1 said "three" here and
"two" in §5.2 — the 4/3 → 5/2 overturn was applied at one site and missed at the
other. Corrected in round 1 of the review; see §7's internal-consistency note.)

### §4.2 D4 is overturned by this ticket's own sweep

The plan reported, before the sweep ran, that A4's flagged candidate
(`conformance_request_state_test.exs`) has zero members, and expected the honest
output to be *"no ET-CC member matches the MRTR five"*.

**The full sweep disagrees, and the sweep wins** (PM at `26090`: *"report what
the full sweep returns, and if it disagrees with any of them, the sweep wins and
you say why"*). A4's candidate is indeed empty — but the member-side enumeration
finds carriers in two files A4 never had cause to look at:

* `MRTRClientNoStateOmitted` — *"If InputRequiredResult does not contain
  requestState, client MUST NOT include one in the retry"* — is asserted verbatim
  by `client_defects_test.exs:70` and `:108`
  (`refute Map.has_key?(retry["params"], "requestState")`).
* `MRTRClientRequestStateEchoed` — *"Client MUST echo back the exact value of
  requestState when retrying"* — by `client_defects_test.exs:143` and
  `client_test.exs:270`.

**Why the pre-measured answer was wrong, stated plainly:** it inherited A4's
*candidate*, and a candidate-driven answer is an answer about its candidates.
That is `cg-reconciliation.md` §4's own lesson — the one that caught
`ClientKeepsValidTool` — arriving on this ticket's inputs. Three of the five
(`MRTRClientJsonRpcIdDifferent`, `MRTRClientParallelIsolation`,
`DefaultResultTypeComplete`) do remain unmatched, and are enumerated as such in
§3.4.

### §4.3 Where the member side and the CG side AGREE

Reported because a reconciliation that printed only disagreements would read as
though nothing had been checked:

* **CG3, CG5 and CG6 have no ET-CC member** — independently re-derived here from
  the member side, matching `match-relation.md` §6's table and
  `cg-reconciliation.md` §3's three bare `NONE`s.
* **CG5's exclusion survives the hard rule.** `discover_test.exs:37` asserts
  parsing, not honouring — the member-side read reaches §6's answer by §6's own
  argument.
* **`ClientCustomHeaderNoMirrorNumber` is not a counterpart.** A4 rejected it on
  the predicate; this method independently declines it (§3.2's control).
* **CG1's and CG4's discharge sites** are members, exactly as A4 records them.

### §4.4 D5 was not a disagreement, and the plan's version of it was wrong

The plan (comment `26087`) recorded D5 as *"one fact, two addresses, and one of
them is wrong at this tip — the `cache_scope` assertion is at **48**, not 47"*.

**Run literally at the delivered tip, that is false.** `discover_test.exs:49` is
`assert result.cache_scope == "public"`, exactly as `match-relation.md` §6 cites
it; there is no assertion at 48 (`:48` is `assert result.server_info.name`).

So D5 is **not** an AC3 disagreement at all. A4 §3 cites the `test` declaration
line (35, which is the register's key under `etcc-row-key.md` §1); §6 cites the
assertion line (47). Both are correct addresses for one test, differing only by
the decl-versus-assert convention — the distinction the row key fixes at its §2,
and the one B2a met at S7-23.

**Recorded rather than quietly dropped, because the failure is the interesting
part:** the plan's "48" was arrived at by counting from a citation instead of
resolving the address against the tree — which is the same move as checking a
correction against a comment rather than against the code, and the PM's one
standing instruction for this ticket (`26090`) was not to do that. It cost
nothing here only because the address was re-resolved before delivery. **S7-28.**

### §4.5 D6 — CG7's four purposive rows, checked against A4's GAP and dropped

**Raised by the reviewer, not by this ticket** (`26096` F2), and it is the second
self-overturn here — §4.2 is the first. Round 1 gave all **13**
`client_tool_schemas_test.exs` rows `cg: CG7` on **one shared basis string**:
*"…this machinery exists solely to drive CG7's `Mcp-Param-*` mirroring, so its
claims are CG7's."*

**That is an argument from what the machinery is FOR, and it is rejected.** The
brief establishes correspondence against the check's `description` — never a
title, and by the same reasoning never a purpose. It is HAZARD 2's false-positive
shape with a different label on it. **And a per-item field carrying the same string
thirteen times reads as thirteen reasons and is one**, so it could not be audited
per row — epic ruling 4's shape. **S7-30.**

**The check the PM required before dropping anything, run and reported either way.**
The reviewer checked the four against CG7's **29 OC check descriptions**; that is
*one* of A4's three layers, and *"does this member discharge CG7"* is a question
about CG7's **gap**, which may be wider than the checks it happens to correspond
to. So the four were checked against the gap:

> **A4's CG7 gap** (`cg-reconciliation.md`, CG7 table, row `gap`): *"SEP-2243:
> mirror designated tool parameters into `Mcp-Param-*` headers; encode unsafe
> values; exclude tools with invalid `x-mcp-header` annotations."*

Three limbs: **(i)** mirror, **(ii)** encode, **(iii)** exclude. Each of the four
rows against all three, citing the row's own assertion:

| row | its own assertion | (i) mirror | (ii) encode | (iii) exclude |
| --- | --- | --- | --- | --- |
| `:320` | `:339 {:error, %Error{code: -32_020}}`, `:341 length(sent) == 3` | no | no | no |
| `:345` | `:363 {:error, %Error{code: -32_020}}` | no | no | no |
| `:367` | `:373 {:error, %Error{code: -32_020}}`, `:374 length(sent) == 1` | no | no | no |
| `:399` | `:404 {:error, {:malformed_result, nil}}`, `:408 Process.alive?(client)` | no | no | no |

`:320`, `:345` and `:367` are the client's **-32020 recovery policy** — refresh
once, retry once, then surface, and not off the `tools/call` path. `:399` is
**malformed-`tools/list` robustness**. The gap says nothing about recovering from
a peer's rejection or about surviving a malformed result. **So the four leave, and
CG7 goes 35 → 31.**

**The discriminator is in the file itself, which is why this is not a judgement
call.** `:399` and `:415` sit in the same `describe` and make the same kind of
claim — yet `:415` asserts
`headers_for_call(client, transport, "t") == [{"mcp-param-region", "us-west1"}]`
at `:431`, which *is* limb (i), and `:399` asserts nothing about a header. `:415`
stays; `:399` goes. The nine that stay each cite a `Mcp-Param-*`/`:headers`
assertion of their own, or (`:82`, `:123`) the exclusion.

**Where the four went.** `cg: none` with a per-row basis naming the gap check, and
`tokens: []` — the second question was asked and answered too: none of the 15
unclaimed checks (`cg-reconciliation.md` §4) covers -32020 recovery or
malformed-result robustness, so there is no C1 row to lose here. They remain
`ET-CC` members with a `client` leg; only the CG correspondence changed.

---

## §5 AC4 — the bucket-1 tokens, under the PM's amendment

AC4 as amended (`26089`): *bucket-1 candidates inside a matched CG are recorded in
MES-77's claim-slug token **where an ET-CC member carries them**. Where no member
does, `match-relation.md` §6 forbids a token and the candidate is recorded as a
named finding with the label that removed its carrier.*

**The PM's ruling at `26089` (2026-08-24, at the plan hop) was that §6 reaches
claims, not only whole CGs** — its MUST NOT was written in front of CG3/CG5/CG6,
three whole CGs, but its antecedent (*no ET-CC member carries this*) is satisfied
by claims inside CGs that **do** have members. That is S7-17's shape, ruled rather
than applied unilaterally.

**The ruling was made over three candidate claims; two of them turned out to be
carrier-less and one did not** (§5.1's `CG2-absent-yields-nil`, which acquired a
carrier when the member-side sweep ran after the ruling). So *"three"* is the
count at the time of the ruling and **`2` is the count now** — §5.2. Dated here
because round 1 stated the historical figure directly above §5.1's live one, where
it read as a live count (`26097`(iii)).

### §5.1 Five tokens carried — one more than the plan predicted

| token | carrier | B2a label |
| --- | --- | --- |
| `oc:none/no-oc-scenario/CG2-inbound-parse` | `client_conformance_test.exs:186` | ET-CC |
| `oc:none/no-oc-scenario/CG2-outbound-meta` | `client_conformance_test.exs:235` | ET-CC |
| `oc:none/no-oc-scenario/CG2-absent-yields-nil` | **`capabilities_test.exs:140`** | ET-CC |
| `oc:none/no-oc-fixture-case/CG7-integer-safe-range` | `header_mirror_test.exs:134` | ET-CC |
| `oc:none/no-oc-fixture-case/CG7-static-reachability` | `header_mirror_test.exs:207` | ET-CC |

**`CG2-absent-yields-nil` acquires a carrier, and this overturns the plan's
count of four.** The plan looked only at A4's own carrier for that claim
(`client_conformance_test.exs:211`, ET-OUT) and concluded the token had none.
The member-side sweep finds the same claim one layer down, at
`capabilities_test.exs:140` (T7):

    caps = ServerCapabilities.from_map(%{"experimental" => @experimental})
    assert caps.extensions == nil

**Checked against the false-positive guard rather than accepted on the words.**
A4's claim is *"a server declaring NO extensions yields nil, not an invented
map"*. `:133` asserts exactly that at the decoder — and it is **the decoder our
client runs** (`client.ex:539` → `Discover.Result.from_map/1` →
`ServerCapabilities.from_map/1`), so it is the same required behaviour on the same
leg, not a look-alike. Its leg is `client`, consistently.

### §5.2 Two tokens have no carrier — the finding, with the label that removed it

| claim | A4's unit(s) | B2a label | why no ET-CC member |
| --- | --- | --- | --- |
| `CG2-unknown-not-a-fault` | `client_conformance_test.exs:219` | **ET-OUT** (gate 2) | asserts only that nothing is logged — a captured-log claim with no wire artefact |
| `CG7-annotated-number-excluded` | `header_mirror_test.exs:113,120` | **ET-ADJ** ×2 | assert `validate_schema/1` returns an error tuple — an SDK-internal result, no wire artefact |

**Both were re-checked against the whole member set before being called
carrier-less, not inherited from the plan.**

* For `CG2-unknown-not-a-fault`, the nearest candidate is
  `extensions_negotiation_test.exs:285` (T10, *"tools/call succeeds normally; no
  error, no -32021"*). **Rejected:** T10 is our **server** not faulting on an
  unknown **client** extension; the claim is our **client** not faulting on an
  unknown **server** extension. Different implementation under test — the
  false-positive guard doing work.
* For `CG7-annotated-number-excluded`, the nearest candidate is
  `header_mirror_test.exs:402` (*"unannotated parameters are NOT mirrored"*).
  **Rejected on exactly A4's own grounds:** that is the *unannotated* case, which
  is what `ClientCustomHeaderNoMirrorNumber` covers. Our constraint is that an
  *annotated* `number` is rejected outright.

**This is not a defect in A4** — see §4.1. It is the third instance of one defect:
A4 counted units that close the gap, B2a's gate 2 counts units that assert a wire
artefact, and two of A4's seven claims are discharged only by units of the second
kind. Recorded **with** the AC3 disagreements, not beside them.

---

## §6 HAZARD 3 — membership is not correctness, and the join preserves it

**A member that asserts wire behaviour and DISAGREES with the official suite is
still a member.** Correspondence is about **subject matter**, never about who is
right — so no CG correspondence here is recorded as `none` because a member's
assertion looks wrong.

The property is structural rather than promised: **`contradicts_oc` is a field
ORTHOGONAL to `cg`, not a value of it**, so *"corresponds to CG-n"* and
*"disagrees with the check CG-n maps to"* are recorded independently and neither
can overwrite the other. The builder refuses a `contradicts_oc` that names no
check — a contradiction needs something to contradict.

**Two members carry one, and both are named so a reviewer can find the rows the
join was most likely to drop:**

| member | leg | contradicts |
| --- | --- | --- |
| `dispatch_test.exs:82` — *"initialize is removed → -32022"* | server | `oc:server/server-stateless/sep-2575-http-server-method-not-found-404-initialize/HttpServerMethodNotFound404initialize` |
| `streamable_http_stateless_test.exs:88` — *"initialize is gone → -32022; ping/logging.setLevel → -32601"* | server | the same check |

The check requires **404 + -32601**; both members assert **-32022**. They are
`ET-CC` in B2a's register **deliberately** — excluding them would empty bucket 4a
by construction, and 4a is a finding this epic exists to surface.
`etcc-membership.md` §B.4(i-b) records why that rule is not in Part A.

`streamable_http_stateless_test.exs:88` bundles three claims and only the
`initialize` one contradicts; the two `-32601` claims agree. Under
`match-relation.md` §1 that member contributes **three edges**, and C1 preserves
all three verdicts — this file records the contradiction at member granularity
and does not collapse them.

`test/conformance/etcc_attribution_test.exs` asserts the `dispatch_test.exs:82`
row by name, so the one row most likely to be lost cannot be lost silently.

---

## §7 Bounds — what this file does NOT establish

1. **It records no edges.** `cg`, `tokens` and `contradicts_oc` are addresses and
   correspondences; **C1 materialises the edges** (`cg-reconciliation.md` §9(1),
   A3's ownership table). For a CG-matched member the correspondence is carried by
   `cg` and the per-check edge is left to C1 — minting a state-1 token per member
   per check here would be building C1's edges. State-1 tokens appear **only** for
   the 15 unclaimed checks, where the member↔check correspondence is this
   ticket's own finding and has no other home.
2. **`ToolAddNumbers` is flagged, not decided** (§3.4).
3. **Bucket 2 is not populated.** The **four** unmatched checks in §3.4 are
   reported as measurements. Bucket 2 is C1's, and filing here would be this
   epic's one standing prohibition — discovering rather than deciding. (Round 1
   said "five" here against §3.4's four — the same one-site correction as §4.1.)
4. **The leg vocabulary is measured over `lib/` call sites at this tip.** A future
   ticket that gives `Extensions.from_meta/1` a caller, or that makes the client
   consume an SSE stream (CG3/MES-38), moves members between populations. The
   per-function table in §1 is a dated measurement, not a permanent property.

   **A CONCRETE INSTANCE, so the class is not left generic** (`26099`, and the PM
   is adding it to MES-88). `ServerCapabilities.from_map/1` has a **second** `lib/`
   call site at `messages/initialize.ex:72`, inside
   `MCP.Protocol.Messages.Initialize` — a module nothing in `lib/` references under
   stateless core. The four members attributed `client` on that decoder —
   `capabilities_test.exs:8`, `:26`, `:36` and `:133`, the last being §5.1's
   `CG2-absent-yields-nil` carrier — rest on a **reachability** claim,
   *"reached only by our client"*,
   which **holds as written at this tip** and which **reviving `Initialize` would
   silently falsify** — no test would go red, and the leg would simply become
   wrong. This is the reason the bound above is stated as a date rather than a
   property.
5. **`none_determinable` is not "unknown".** Every one of the 29 carries a reason
   naming *why* no single leg owns the claim (§2.4). None is a residue of
   uncertainty.
6. **The strip-boundary control's reach is stated in §1(a)** and is narrower than
   its name suggests.
7. **The S7-24 column reaches figures with an artefact counterpart, and NOT
   figures asserted about another SECTION of this file.** The column added in
   round 1 re-derives each prose figure *from the artefact*, so a figure whose
   referent is another section of prose has nothing to re-derive against — which
   is why both of round 1's surviving stale figures (§4.1's "three", §7(3)'s
   "five") were of exactly that kind, and why the column **could not** have caught
   them by construction. The instrument that does is an **internal-consistency
   check**: every figure stated about another section, re-read against that
   section. Both now run as controls — `etcc_attribution_controls.exs figures`
   re-derives every artefact-backed figure and checks that every counted member is
   cited at its own address — and the internal-consistency read was run over the
   whole file in correction round 1, with its result in the close-out. **This is a
   bound on S7-24's own remedy, not an instance of S7-24** — recorded as
   **S7-29**.

8. **This file adds tests under `test/conformance/`.** They are out of scope by
   gate 1, so the next regeneration of `docs/conformance/etcc-exunit-rows.json`
   will see 992 + the tests in
   `test/conformance/etcc_attribution_test.exs`, all out-of-scope. Nothing in this
   ticket regenerates it, so the committed 992 and B2a's 579/413 split are
   unmoved — stated so a reader can tell expected movement from a finding
   (`etcc-row-key.md` §5.1).
