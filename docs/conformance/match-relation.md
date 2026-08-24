# The ET-CC × OC match relation, and the check-key ↔ test-name convention

**Ratified on MES-68 (A3), Sprint 6, 2026-08-22.** This file is the rule. C1
(the crosswalk builder) consumes it; nothing downstream should have to
reconstruct it from Jira comments.

That is not a stylistic preference. A2's membership criterion ended up spread
across nine comments, and a sweeper reconstructing a rule from a conversation
will reconstruct a slightly different rule. **C1's input is a file.**

| owns | what |
| --- | --- |
| **A3** (this file) | the **form** — the relation, the edge record, the bucket function, the token |
| **C1** | the **edges** — the crosswalk, recorded as data |
| **B4** | **membership** only — the `:etcc` tag and `mix test.etcc` |

One artefact, one owner. Two tickets owning one artefact is the MES-24
two-censuses defect, and when the two disagree nothing detects it.

Executable form: `MCP.Conformance.MatchKey`
(`conformance/lib/mcp/conformance/match_key.ex`), proved in
`test/conformance/match_key_test.exs`. The module emits **no** edges.

---

## 1. The unit of matching is a CLAIM, not a test

An ExUnit `test` is neither a scenario nor a check. It can carry several claims,
or be one of several tests carrying one claim. So the atom of matching is a
**claim** — a single assertion about one required behaviour — finer than a
`test`, coarser than an `assert`.

MES-67's **ET-CC member is still the test**, keyed on `{module, test name}`.
The match **edge** is

    (member, OC check, claim-within-member, verdict pair, axes)

and a member bundling claims contributes **several edges**.

**Cardinality is many-to-many in both directions, and edges are never
collapsed.**

| case | resolves to |
| --- | --- |
| `streamable_http_stateless_test.exs:88` — one test asserting `initialize → -32022`, `ping → -32601`, `logging/setLevel → -32601` | **3 edges**, three verdicts preserved |
| CG4 — two tests, one check (`json-schema-ref-no-deref`) | **1 edge**: the `:133` case is ET-CTRL under MES-67 and contributes none, so "2 tests, 1 check" is "1 claim, 1 control, 1 edge" |

**Chains do not exist, by construction.** The relation is **bipartite** — edges
run only member ↔ check, never member → member or check → check — so there is
no same-side edge to compose. That closes S5-21 by argument rather than by
review rounds.

**Order-freeness.** Every predicate in this procedure is a lookup in A1's
manifest or a read of one test body. No edge's classification depends on
another edge having been classified, so there is no traversal order for a
result to depend on.

---

## 2. The axis model

An OC check's predicate is a **conjunction of axes**. Against each axis, an ET
claim is exactly one of `agrees` / `contradicts` / `silent`. The edge's
**shape** follows, in **stated precedence**:

    any axis contradicts  ->  :contradicting
    else any axis silent  ->  :partial        (covered and uncovered axes named)
    else                  ->  :full

The precedence is stated rather than left to whichever axis an implementation
happens to test first. It is what makes buckets 4a and 4b exclusive **by
construction** rather than by adjudication — the S5-20/S5-21 move applied at
definition time.

It is load-bearing because **partial and contradiction are not mutually
exclusive**. The `:83` `initialize` edge is both: our test asserts `-32022`
where the check requires `-32601` (contradicts, on the code axis) *and* says
nothing about the HTTP 404 (silent, on the status axis). The epic files that
very case as its worked **contradiction**. A rule reading "has an uncovered
axis ⇒ 4b" would put the epic's own 4a example in 4b.

### AXES COME FROM THE PREDICATE, NEVER FROM THE DESCRIPTION

A check's `description` is prose *about* the requirement. Its predicate is the
requirement *as scored*. They are different artefacts and they disagree:

    HttpServerUnsupportedVersion400
      description: "...MUST respond with 400 Bad Request AND an
                    UnsupportedProtocolVersionError listing its supported versions."
      predicate:   S.status === 400            <- ONE axis

Reading axes off descriptions would invent a second axis here and then score us
against it. That is *a proxy for a rule is not the rule*, living inside the OC
artefact rather than in our own sweep.

**The axes are committed as data**, not left derivable from an uncommitted
build: `docs/conformance/oc-axes-2026-07-28.json`, with the harness
`dist/index.js` sha256 recorded as provenance alongside — the same sha both
legs of A1's manifest carry, so the axes come from the exact build behind the
accepted runs. Each axis is a **verbatim substring** of the evaluator excerpt
it was read from, and each excerpt is addressed by a byte span in that build.

**Residual.** Committed axes are a **reading of a predicate at one build**. A
harness bump invalidates them exactly as A1's residual R3 says it invalidates
keys. The sha lets a reader tell whether that has happened; nothing detects it
automatically.

**Scope of the committed axes: 13 of 175.** The 12 `server-stateless` FAILURE
checks whose own `errorMessage` carries an HTTP status (the R2 class), plus the
CG4 counterpart. The other 162 have no committed decomposition and C1 must
extract them by the procedure recorded in that file before bucketing an edge
onto them. Decomposing all 175 here would be A3 building C1's artefact, and
162 of them before anyone knows which have an ET counterpart at all.

### What the axis ruling actually moves: 7, not 12 — PROVISIONAL

MES-65 says *"A3's partial-axis ruling alone moves 12 checks between buckets"*.
Read from the predicates, it moves **at most 7**, and the other **5 move the
other way**.

| | checks | predicate |
| --- | --- | --- |
| **two-axis** (status ∧ code) | the six `method-not-found-404*`, `header-mismatch-400` = **7** | `r.status!==404 \|\| i?.error?.code!==-32601` |
| **single-axis** (status only) | the three `meta-invalid-400`, `unsupported-version-400`, `missing-capability-http-400` = **5** | `n.status===400` |

For a **single-axis** check, "we assert the code but not the status" is **no
match, not a partial one**. Covering zero of one axis has nothing partial about
it, and the code assertion is evidence about a *different* check
(`RequestMetaInvalid`, `ServerUnsupportedVersionError`,
`ServerRejectsUndeclaredCapability`) — which is exactly why those three also
appear among `server-stateless`'s 17 failures. Recording it as partial would
credit us with coverage that is filed elsewhere. Those 5 are **bucket-2
candidates** — "write the test", not "extend the assertion".

**This is PROVISIONAL pending B2a.** The OC side is measured; the ET side is
not swept until B2a. Stated as provisional because a figure that reads as
settled when it is contingent is the S5-24 shape. The epic's 12 is superseded
and the PM corrects the epic body once B2a confirms.

---

## 3. `bucket = f(verdict pair, edge shape)`

**The verdict pair alone cannot decide the bucket, because 4a and 4b share it:**

    4a | red OC / green ET-CC — contradiction   | D4a
    4b | red OC / green ET-CC — incompleteness  | D4b

Any rule of the form `bucket = f(verdict pair)` narrows to `{4a, 4b}` and
stops. The shape is what finishes the job. Equally, `partial ⇒ 4b` is false: a
partial edge over a **green** check is bucket 5.

| pair (OC, ET-CC) | shape | bucket |
| --- | --- | --- |
| red, green | `:contradicting` | **4a** |
| red, green | `:partial` | **4b** |
| red, green | `:full` | **escalates** — see below |
| green, green | `:full` | **5** |
| green, green | `:partial` | **5**, carrying a `partial` sub-count |
| green, green | `:contradicting` | **escalates** — see below |
| green, red | any | **3** |
| red, red | any | **6** |

`partial` is therefore **carried alongside** the bucket, with its covered and
uncovered axes named, and bucket 5's arithmetic carries a partial sub-count —
those are genuine coverage weaknesses and they feed the vacuity sweep (D5a/D5b).

**Buckets 0, 1 and 2 are not functions of an edge** and the code does not return
them. Bucket 1 is an ET-CC member with **no** edge; bucket 2 an OC check with no
edge; bucket 0 is A5's out-of-denominator set. All three are complements over
the whole edge set — C1's to compute, and the reason C1 owns the edge set.

### The two escalations, and why they are escalations rather than buckets

**`(red, green)` with a `:full` edge.** Our claim agrees with the check on every
axis, our test passes, and the harness still fails the SDK. Nothing is
contradicted and nothing is silent, so the test cannot be exercising the
behaviour the check exercises. That is a coverage defect of a different kind —
D4b's to disposition — but it is **flagged, not counted silently**.
*This case was implicit in the ratified table and is made explicit here; it is
a completion of the rule, not a departure from it.*

**`(green, green)` with a `:contradicting` edge.** Our claim contradicts the
check on some axis, yet both passed. Against one build that is impossible, so
the *input* is wrong — mismatched provenance, or a mis-recorded axis. Bucketing
it would launder a data defect into a finding.

---

## 4. The edge record — what C1 stores

```elixir
%{
  member:   %{module: "MCP.Transport.StreamableHTTPStatelessTest",
              test:   "initialize is gone → -32022; ping/logging.setLevel → -32601"},
  claim:    "ping → -32601",
  oc_key:   ["server", "server-stateless", "sep-2575-...-404-ping",
             "HttpServerMethodNotFound404ping", "<description>", ""],
  tag:      "oc:server/server-stateless/sep-2575-...-404-ping/HttpServerMethodNotFound404ping",
  verdicts: %{oc: :red, et: :green},
  axes:     [%{axis: "jsonrpc_error_code", verdict: :agrees},
             %{axis: "http_status",        verdict: :silent}],
  shape:    :partial
}
```

`shape` and `tag` are **derived**, never accepted from the caller, so a stored
edge cannot lie about its own axes or address a key it does not encode.
`validate_edge/1` re-derives both — that is what a reader checks a
round-tripped edge with before counting it.

`member` is MES-67's unit: **module AND test name**. Not the name alone (nine
tests share `"round-trips through JSON"`), and not `file:line` (generated tests
share a line).

---

## 5. The naming convention

    oc:<leg>/<scenario>/<check_id>/<name>[#<discriminator>]
    oc:none/<reason-slug>/<native-id>

    oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/
       HttpServerMetaInvalid400#missing-protocol-version
    oc:client/json-schema-ref-no-deref/sep-2106-no-network-ref-deref/
       NoNetworkRefDereference

**`<native-id>` names a CLAIM, and its contents are §6's** —
`<origin-id>-<claim-slug>`, e.g. `CG7-annotated-number-excluded`. Stated here
as a pointer rather than a second description: §5 and §6 describing one slot in
two places is the two-indexes hazard inside a single file.

In today's unaligned suite a match is **recorded data** — an explicit edge. In
Sprint 7's aligned suite the **name is the key**
(`test "[oc:...] the server answers ping with -32601"`), a regex lifts the
token out, and the drift guard fails on an unresolvable one. Only the second
makes matching a pure lookup; this convention is written so the same token
serves both.

### Reversible THROUGH A1, not lexically

A1's key is **six** fields and the fifth is `description`, a sentence
("Rejections of requests missing required `_meta` fields use HTTP 400 Bad
Request."). A test name cannot carry it. All 63 field subsets were enumerated
against the 175 rows: **every unique projection contains the discriminator**,
and the shortest that avoids `description` is
`(scenario, check_id, name, discriminator)`.

So the token carries five short fields and A1 supplies the sixth. The claim is
that a token is an **injection into the frozen 175 whose inverse is a lookup** —
not that it is lexically reversible. Claiming the stronger property would be
claiming a bound the artefact does not have.

**Neither `check_id` nor `name` works without the other, and each fails on a
different leg** — which is why either alone reads as adequate to someone
looking at one leg. Measured over all 175 rows, counting **rows lost** (rows
that disappear when the projection is deduplicated), which is A1's measure:

    (leg, scenario, name, discriminator)         2 rows lost   (RequestMetaInvalid x3)
    check_id alone, client leg                  29 rows lost   in 7 groups
    check_id alone, server leg                  35 rows lost   in 2 groups
    (scenario, check_id, name, discriminator)    0 rows lost   <- what the token carries

*Rows lost, not rows involved.* The client-leg groups involve 36 rows and lose
29. Both are true of different questions; two tickets using one phrase for two
measures is how a figure drifts, so the measure is named wherever the number is.

**Charset.** Measured over all 175 rows, every carried field draws only on
`[A-Za-z0-9_-]` — no slash, hash, whitespace or bracket — so the token parses
unambiguously. `encode/1` asserts that charset and **refuses** rather than
emitting an ambiguous token if a future harness breaks it (A1 residual R3).
Longest token today: 138 characters.

**The discriminator is `details.fieldIssue`, not an ordinal.** The contributed
page's worked example said the three `HttpServerMetaInvalid400` records "keep
their `#1/#2/#3`". They have no ordinals: A1 separated them by rule 2, giving
`missing-meta`, `missing-protocol-version`, `missing-client-capabilities`.
A1's own tally is `rows_by_discriminator_source: {unique: 172, field_issue: 3,
ordinal: 0}` — **rule 3 has zero members.**

---

## 6. The four-state guard, decided lexically before any lookup

The "name by OC check key" rule only works for **matched** coverage. A bucket-1
member — ET-CC with no OC counterpart — has no OC key to be named by. If it
were simply left untagged, *"nobody has adjudicated this yet"* and *"we looked
and there is no counterpart"* would be the same state, and a register in which
those are indistinguishable **cannot report bucket 1 at all**. Silence must not
encode a decision.

Hence the reserved `oc:none/<reason-slug>/<native-id>` form. `none` is safe to
reserve as a leg because the leg vocabulary is **measured-exhaustive** at
`{server, client}` over all 175 rows.

| state | tag | outcome |
| --- | --- | --- |
| 1 | `oc:<leg>/…` that **resolves** in A1 | a matched edge |
| 2 | `oc:<leg>/…` that **does not resolve** | **FAIL** — a typo, or a key gone stale against a harness bump |
| 3 | `oc:none/…` | a declared bucket-1 member; the guard asserts it does **not** resolve as an oc key, and that the native id is registered with D1 |
| 4 | an ET-CC member carrying **neither** | **FAIL** — the completeness half |

Separating the four **lexically, before any lookup** is what makes a stale key
and a declared non-match fail *differently and for stated reasons*, rather than
both arriving as "not found".

**State 4 failing has a cost, and it was ratified with the cost named:** the
Sprint 7 drift guard blocks on any ET-CC member nobody has adjudicated. That is
the price of not letting silence encode a decision, and it is the right price.

### The native-id slot names a CLAIM, not a requirement heading

**Corrected at MES-77 (2026-08-23), executing A4's recommendation.** A3 first
said A4's `CG` number survives as the native identifier as it stands, with a
matched CG becoming a state-1 alias. A4 used that rule, and found it incomplete
in the paragraph written for it. Both halves inherit the assumption **§1
rejects** — that a CG is a unit of matching. It is not: a CG is a requirement
heading over a set of claims.

**A bare `CG` number is NOT admissible in the slot**, because a requirement
heading can be *matched and bucket-1 at the same time*. CG7 is exactly that: it
corresponds to **29 OC checks** (`http-custom-headers` 18 +
`http-invalid-tool-headers` 11) **and** carries **3 constraint families over 9
ET-CC units** that the suite's fixture never exercises. A slot holding `CG7`
names all three of those claims at once, and a register keyed on it cannot tell
them apart — the S5-31 two-indexes hazard, arriving through the slot that
exists to prevent it.

So the slot carries:

    oc:none/<reason-slug>/<origin-id>-<claim-slug>

    oc:none/no-oc-scenario/CG2-inbound-parse
    oc:none/no-oc-fixture-case/CG7-annotated-number-excluded

`<origin-id>` is the identifier of the scope the claim comes from in whatever
private taxonomy already names it — a `CG` number where one exists, a **ticket
key** where none does. `<claim-slug>` names the claim within that scope. Both
stay inside the **measured** `[A-Za-z0-9_-]` charset (re-measured at MES-77:
875 carried values over the 175 rows, 0 outside; positive control —
`description` is outside it on 175 of 175), so the builder **refuses** rather
than emitting a token `decode/1` would mis-split.

**A4's seven tokens were already written this way** (`cg-reconciliation.md`
§5) and all seven guard-check to state 3. MES-77 makes the shape a rule with an
enforcement point; it changes no byte A4 published.

**A4 recommended both of this section's rules and executed neither** — its §7
is headed "RECOMMENDED, NOT EXECUTED", which is an accurate record of what
*that ticket* did and is left standing. **They were executed here, at MES-77.**
The pointer goes this way deliberately: the live document names the archive,
the archive does not chase the live document. Editing A4's artefact to say a
later ticket happened is how one fact acquires two homes.

| enforcement point | what it refuses |
| --- | --- |
| `native_id/2` at build | an empty or missing part, a non-binary part, a part outside the charset |
| `declared_claim_index/1` at register assembly | **one native id naming two different claims** |
| `none/3` | composes both — the sanctioned builder |

**`none/2` keeps its open contract, deliberately.** It cannot know the caller's
taxonomy: a unit-level id like `T-CG1a` is *already* claim-level and has no
heading part to suffix, so refusing an unsuffixed id there would produce false
refusals rather than safety.

**Repeats of one native id with the SAME claim are legal, and that is not a
leniency.** The atom is a claim, and a claim can be asserted by several
members: CG7's 3 constraint families are discharged by **9** ET-CC units, so
nine members legitimately share three native ids. A rule of the form *"no two
members carry the same native id"* would reject correct data — the same
category error this rule exists to fix, one level down. The enforceable form is
the converse, and it is what `declared_claim_index/1` checks.

**The token is NOT lexically decomposable back into its two parts, by choice.**
Reserving the first `-` as a separator would require origin ids to contain
none — true of `CG1`–`CG7`, false of every Jira key, and a bucket-1 claim
belonging to no CG has a ticket key as its natural origin. A rule forbidding
the identifiers the next ticket needs is a rule that will be broken within the
sprint. So rollup from a native id to its origin is **a lookup in D1's
register, not a parse** — the same stance §5 already takes on `description`.

**Demonstrated, not asserted** (MES-77 AC4, run at `d9e6d82`):
`conformance/controls/native_id_collision.exs` drives A4's real seven claims
through both schemes. **Old: 7 claims → 2 distinct tokens, 5 rows lost**, the
three CG7 tokens byte-identical and `guard_state/2` returning one answer for
all three; driven on CG7 alone, `declared_claim_index/1` refuses with
`{:native_id_names_two_claims, "CG7", [...]}`. **New: 7 claims → 7 tokens, 0
rows lost.** *Rows lost* is A1's measure and §5's, so the two schemes are
compared in the unit this document already uses.

### A requirement with NO ET-CC member is OUT of the tag system, by rule

**State 3 is a property of a MEMBER.** It says *"this member was adjudicated and
there is no OC counterpart"*. A requirement that nothing implements has no
member to carry it, so it has no token of either kind — and the
"matched → alias, unmatched → native id" split has no cell for it. Left
unstated, such a requirement reads as adjudicated when it was never in this
system's domain.

**The rule: such a requirement gets NO token, and MUST NOT be given a
placeholder member to carry one.** A placeholder would assert state 3 — "we
looked and there is no counterpart" — where the truth is "nothing is
implemented"; and the Sprint 7 drift guard would then fail it as **state 4**, a
correct guard firing on a case nobody intended it to cover. These are
outstanding requirements, tracked on the board. They are not coverage, and
counting them as bucket 1 would count an absence as an asset.

**Membership as of 2026-08-23, and it is NOT STABLE.** Established at MES-77 by
re-measurement rather than inherited from A4:

| CG | requirement | owner |
| --- | --- | --- |
| **CG3** | client-side `subscriptions/listen` stream consumption | **MES-38** |
| **CG5** | client honours `ttlMs` / `cacheScope` (SEP-2549) | **MES-39** |
| **CG6** | client writes trace-context `_meta` (SEP-414) | **MES-32** |

Owner and status are `docs/sprint_4_issues.md` Register 2's to state; they are
cited here, not restated, so one fact keeps one home.

**When MES-38, MES-39 or MES-32 lands, that CG acquires a member and LEAVES
this class.** The three names above are a dated measurement, not a permanent
property — without this sentence the first ticket to land turns the table into
a stale list that still reads as a rule. **To re-derive:** the class is *a
requirement with no ET-CC member **discharging** it*, and the qualifier is
load-bearing. It is **not** *no test mentioning it*: CG5 has a mentioning test
— `test/mcp/protocol/messages/discover_test.exs:49` asserts
`result.cache_scope == "public"` — which asserts **parsing** where CG5 requires
**honouring**. A mention-based sweep would call CG5 covered and silently empty
this class of its hardest member. That is §2's same-words-different-subject
rule, turned on our own side of the relation.

**The EXCLUSION edge was held to the same standard, not assumed.** CG5 above is
the worked case for deciding a CG *into* the class; the four CGs kept *out* of
it were tested by the same hard rule — does a member exist whose assertion is
about the requirement's own observable. The witness is
`docs/conformance/cg-reconciliation.md` §3, whose per-CG **discharge** row
carries the members for **CG1**, **CG2**, **CG4** and **CG7** and a bare
**NONE** for **CG3**, **CG5** and **CG6**. Cited, not restated, so the
membership keeps one home — and so a reader cannot conclude the rule was
applied in one direction only.

---

## 7. What this rule cannot decide — routed to the PM (AC5)

1. **Semantic sameness — narrower than it looks.** MES-67 gate 3 already obliges
   every ET-CC member to name a spec anchor at `5f5440bb` or a SEP number. So
   the question is not "do the words match" but **"do the member's anchor and
   the check's predicate govern the same requirement"**. Still a judgement where
   the anchor is coarser than the check. **Escalates per case.**
2. **A `SHOULD`-only uncovered axis.** Whether a `partial` edge whose uncovered
   axis is a spec **SHOULD** rather than a **MUST** is a divergence at all.
   **Escalates per case.**
3. **The `(red, green, :full)` and `(green, green, :contradicting)` edges** —
   §3. Both escalate by construction rather than being bucketed.
4. **Axis staleness against a harness bump** — §2. Detectable by comparing the
   recorded sha; not detected automatically.
5. **A native id's registration with D1 is asserted, not checked** (MES-77).
   §6 state 3 says the guard asserts the native id "is registered with D1", and
   `declared_claim_index/1` checks the property D1 needs — that one id does not
   name two claims — but **nothing checks that a declared id is registered at
   all**, because D1 does not exist yet. Recorded so the document does not imply
   a check that is not there. It falls to whoever builds D1.

**Negatives are stated, not omitted (A2d).** Where this rule returns nothing —
no ambiguous resolution on the 175, no ordinal-sourced discriminator, no chain
to compose — the question asked is written down above rather than left as a
silence a reader must interpret.

---

## 8. What a green `match_key_test.exs` does NOT establish

It establishes that a token addresses **at most one row of the committed
manifest**, and that five specific wrong answers are refused rather than
returned. It says **nothing** about whether a matched test asserts the same
required behaviour as the check it names — residual 1 — and nothing about the
axis decomposition being a correct reading of the harness: the test checks the
axis data's internal consistency and its provenance sha, which is a different
claim from correctness.

A relation that cannot return NO is the F2 defect, so most of that file asserts
NO. Three mutation controls were run to show the assertions discriminate:
dropping the discriminator from resolution (5 failures), inverting the
`contradicts`-beats-`silent` precedence (2), and collapsing 4a into 4b — the
withdrawn `f(verdict pair)` rule — (2).
