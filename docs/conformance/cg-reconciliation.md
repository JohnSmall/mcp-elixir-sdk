# CG1–CG7 × OC — the reconciliation

**INPUT TO C1. NOT THE CROSSWALK.** This file records, for each of Sprint 4's
seven client gaps, *which* OC check keys correspond and at what cardinality. It
does **not** materialise edges. C1 owns the edge set (`match-relation.md`,
ownership table), and a second artefact carrying edges is the MES-24
two-censuses defect — when the two disagree, nothing detects it.

**Produced on MES-69 (A4), Sprint 6, 2026-08-22**, against `main` at `d9beae6`.
Every token below was emitted by `MCP.Conformance.MatchKey` and guard-checked;
none was typed by hand. A4 builds **no** naming mechanism of its own — A3 §6
already reserved the form this ticket needs.

---

## 0. Instruments, and their provenance checked rather than assumed

| instrument | what it is | provenance |
| --- | --- | --- |
| `docs/conformance/in-scope-2026-07-28.json` | A1's frozen manifest — 175 rows, 175 distinct keys, **56 on the client leg**. The only source of check keys. | — |
| `dist/index.js` @ `0.2.0-alpha.11` | the harness. **Predicates are read from here.** | sha256 `a10085d0…f268aae`, re-checked at execution and **equal to all three recorded shas**: manifest `provenance.client`, manifest `provenance.server`, and `oc-axes-2026-07-28.json` |
| `oc-axes-2026-07-28.json` | A3's committed axis decompositions, 13 of 175 — including the CG4 counterpart | same sha |
| the three null controls + `client-2026-07-28-discounts.md` | discrimination | — |

**A predicate read from an unverified build is worth less than no predicate,
because it reads as measured.** The `/tmp` tree is ephemeral; the sha was
re-checked before a single predicate was read.

**Descriptions decide nothing on their own** (A3 §2). Where a pairing was
accepted or rejected, the predicate is quoted.

---

## 1. The unit is a CLAIM, so a CG is not a unit of matching

A3 §1 fixes the atom as a **claim**. A CG is neither a claim nor a test: it is a
requirement heading over a set of claims discharged by a set of tests. So
"CG4 ↔ `json-schema-ref-no-deref`" is shorthand for a rollup, and the record
underneath is per claim.

**The consequence is not cosmetic: a CG can be matched and bucket-1 at the same
time.** CG7 is exactly that — 29 client checks correspond to it, *and* three
annotation constraints inside it earn no harness credit at all. A per-CG
match/none answer cannot express that, which is why the deliverable is a
claim-level record with a CG rollup on top, never the rollup alone.

### The three layers, held apart

    gap        the required behaviour, anchored to a SPEC line at 5f5440bb or a
               SEP number.  Source: docs/sprint_4_issues.md:4785-4791
               ("Register 2 — the CG client series", 7 rows).

    discharge  the ET unit(s) that close it, keyed {module, test name} per
               MES-67, cited file:line, each labelled by A2's gates 1-3.

    oc         check keys under A3's relation, cardinality stated — or none,
               with the search that found none.

Held apart per MES-67 amendment 2. The layers answer different questions and a
CG can score differently in each: **CG5 is undischarged (layer 2) *and*
`oc:none` (layer 3)**, and collapsing them would report that as one "partial" —
which is not what A3's `partial` means. A3's `partial` is a property of an
**edge**, over an OC check's axes. Where there is no edge there is nothing to be
partial about.

### Labels come from A2's gates, applied PER UNIT

Gates 1–3 decide membership (scope, subject, referent); **gate 4
(falsifiability) is a recorded attribute, not an exclusion** — PM amendment 1 on
MES-67. `ET-CTRL` is the sibling set for controls.

**Per unit, never per file.** That is A2's own hard-won correction: a file-level
label is not one wrong answer, it is a suppressed distribution.

**S6-6 checked, and it does not bite here.** Every `for` in the CG discharge
files is *inside* a test body, not wrapping a `test` declaration, so in these
files one declaration is one runtime unit. Established by reading, not assumed:
`header_mirror_test.exs:53,88,100,170,183`, `routing_headers_test.exs:93,150,160,409,461`
are all in-body; `client_conformance_test.exs` and `client_tool_schemas_test.exs`
contain none.

---

## 2. Evidence classes — six, and only one of them is "the words mean the same thing"

    E1  driven + discriminating   driven by our client in the accepted run AND
                                  no null control scores it
    E2  driven, null-passable     driven, but a null scores it too: the pairing
                                  is real, the CREDIT is not
    E3  mutation                  a recorded mutation of our code moved the
                                  check's verdict (MES-18 / MES-24)
    E4  shared anchor             the CG's spec anchor and the check's OWN
                                  specReferences resolve to the same SEP,
                                  read from the dist
    E5  semantic only             nothing but "these words mean the same thing"
    E0  none                      no counterpart; the search that found none is
                                  recorded alongside

**E4 turned out to be mechanical and it carried most of the weight.** Harness
checks carry a `specReferences` field (404 occurrences in the dist). Resolved
from the build:

| CG | our anchor | the check's own `specReferences` | same? |
| --- | --- | --- | --- |
| CG1 | SEP-2243 | `SEP-2243-Standard-Headers` → `transports#standard-mcp-request-headers` | **yes** |
| CG4 | SEP-2106 security MUST NOT | `SEP-2106` → `2106-json-schema-2020-12#security-implications` | **yes, and to the section** |
| CG7 | SEP-2243 | `SEP-2243-Custom-Headers`, `SEP-2243-Value-Encoding`, `SEP-2243-x-mcp-header` | **yes** |

**No CG pairing in this file rests on E5.** That is a result, not a policy: the
three matched CGs each carry a shared anchor read out of the build, so the
semantic-sameness residual (A3 §7.1) is not load-bearing for any of them.

---

## 3. The seven, across the three layers

### CG1 — client transport omits `Mcp-Method`/`Mcp-Name` on POST

| layer | |
| --- | --- |
| **gap** | SEP-2243: a client MUST send `Mcp-Method` on all POSTs, and `Mcp-Name` on the three name-bearing methods, so a gateway can route without body inspection. |
| **discharge** | **9 ET-CC units**, all `MCP.Transport.RoutingHeadersTest`: `routing_headers_test.exs:90,110,125` (T-CG1a), `:133,161,180` (T-CG1b), `:199,222,239` (T-CG1c). Gate 1 in scope, gate 2 wire assertions, gate 3 SEP-2243. |
| **oc** | **MATCHED — 11 check keys**, all `http-standard-headers`. 9 SUCCESS + **2 SKIPPED** at the accepted run. |

**Evidence: E2 + E3 + E4 — and E2 needs a precision the scenario-level figure
hides.** Discount 2 removes `http-standard-headers` as null-passable: both
`null-connect` and `null-exit0` pass the scenario. **But at check level the null
scores zero of the 11** — it passes by emitting `SKIPPED: 11`, and the harness's
severity map is `{FAILURE:3, WARNING:2, SUCCESS:1, INFO:1, SKIPPED:0}`, so
SKIPPED is free.

So: **the scenario-level credit is null-passable; the nine check-level claims are
not.** A4's unit is the check, not the scenario, and the discount was computed at
scenario granularity. The measure is named wherever the number is: **E2 for the
scenario, E1 for the nine driven checks.** Falsifiability is additionally ours,
from MES-18's reverting mutation (E3).

**The 2 SKIPPED keys — `ClientMcpMethodHeader_initialize` and
`…_notifications_initialized` — are A5 bucket-0 candidates, FLAGGED not decided.**
Read from the predicate, not inferred: `getChecks()` emits a SKIPPED entry for
any of its eight methods the client never sent. Our client never sends either —
both are gone under stateless core (SEP-2575/2567). Bucket 0 is A5's set and the
ratified match-target rule is A5's to apply; this is the evidence, not a ruling.

### CG2 — client-side wiring of extensions negotiation

| layer | |
| --- | --- |
| **gap** | SEP-2133: the client must parse, store and expose a server's declared extensions, and treat an unknown extension as data rather than a fault. |
| **discharge** | **4 ET-CC units**, `MCP.ClientConformanceTest`: `client_conformance_test.exs:186,211,219,235`. |
| **oc** | **`oc:none` — E0. Measured: `/extension/i` over all 175 descriptions returns 0, on both legs.** Widened to the whole key (scenario + check_id + name + description): still **0**. |

**A genuine bucket-1 CG: our coverage exceeds the suite's, permanently.** Agrees
with register row J1, which records the same zero from the server end.

**One thing a reader will trip over, so it is stated.** The census carries
`"reason": "extension"` on seven `not_scored` scenarios (`auth/dpop`,
`tasks-lifecycle`, …). That is *protocol-extension packaging* — scenarios outside
the frozen set — and **not** SEP-2133 extensions negotiation. Different sense of
one word; it is not a counterpart, and a grep that treats it as one would report
a match that is not there.

### CG3 — client-side `subscriptions/listen` stream consumption

| layer | |
| --- | --- |
| **gap** | SEP: `subscriptions/listen` replaces the GET SSE endpoint. The **client** must consume the held-open stream. |
| **discharge** | **NONE.** Not implemented — `streamable_http/client.ex:120-129` POSTs synchronously inside the GenServer, so a held-open stream would block the whole transport. Nothing is asserted because nothing exists. |
| **oc** | **`oc:none` — E0.** Sweep `/subscri\|listen\|stream/i`: **9 hits over 175, every one on the SERVER leg** (`server-sse-multiple-streams` ×2, `server-stateless` ×7). |

**The false-positive guard doing work.** All 9 hits drive **our server** — a
different implementation under test. Excluded by subject, not by name.

**NOT bucket 1, and the distinction matters.** Bucket 1 is an *ET-CC member with
no edge*; CG3 has **no member at all**. It is an outstanding requirement owned by
**MES-38**, not coverage. Filing it as bucket 1 would count an absence as an
asset.

### CG4 — `$ref` never dereferenced

| layer | |
| --- | --- |
| **gap** | `basic/index.mdx:299-310` at `5f5440bb` — "Implementations MUST NOT automatically dereference `$ref` values that resolve to a network URI." SEP-2106 security implications. |
| **discharge** | **1 ET-CC unit** — `client_conformance_test.exs:116`. **`:133` is ET-CTRL** ("CONTROL ON THE CONTROL: the canary really does count a fetch") and contributes **no edge** — MES-67's ruling, applied, not re-decided. |
| **oc** | **MATCHED — exactly 1 check key, 1 edge.** |

    oc:client/json-schema-ref-no-deref/sep-2106-no-network-ref-deref/NoNetworkRefDereference

**"2 tests, 1 check" resolves to 1 claim, 1 control, 1 edge.** Recording the
control as a second edge would double-count our coverage of one check.

**Axes: 1, and taken from A3's committed decomposition rather than re-derived.**
`oc-axes-2026-07-28.json` records a single axis `canary_not_fetched`
(`this.canaryRequests.length>0`), with `this.toolsListed` recorded as a
**precondition on evaluability, not a second required behaviour**. Our unit
satisfies the precondition (it calls `list_tools`) and **agrees** on the one
axis (`assert Agent.get(hits, & &1) == 0`). Shape `:full` — for C1 to
materialise.

**Evidence E4** (both sides cite SEP-2106, ours to the security section, the
check's `specReferences` to `#security-implications`).

**E3 is IMPOSSIBLE here, not merely absent, and that is recorded rather than
left blank.** The check is negative — SUCCESS iff a counter stayed at 0 — so no
mutation of our `$ref` handling can turn it red; a client with no `$ref`
handling at all scores the same SUCCESS. The property holds because a feature is
missing. (A mutation stopping our client calling `tools/list` *would* turn it
red, but that falsifies the precondition, not the requirement.)

### CG5 — client honours `ttlMs` / `cacheScope`

| layer | |
| --- | --- |
| **gap** | SEP-2549: a client that receives caching hints must honour them — reuse within `ttlMs`, respect `cacheScope`. |
| **discharge** | **NONE — and this OVERTURNS the provisional plan.** |
| **oc** | **`oc:none` — E0.** Sweep `/ttlms\|cachescope\|cach/i`: **7 description hits, 8 over the whole key, all SERVER leg**, all in the `caching` scenario. |

**The overturn, reported as an overturn.** The plan asked a conditional: *if the
parse half has ET-CC members, CG5 is partially discharged.* The parse half does
have a member — `discover_test.exs:37` asserts `result.cache_scope == "public"`
— **but it does not discharge CG5.** CG5's requirement is *honouring*; that unit
asserts *parsing*. Citing it as CG5's discharge would be the CG5↔`caching` error
one level down: **same words, different subject** — applied to our own side of
the relation, not just OC's.

Established by measurement, not by reading the register: every `ttl_ms` /
`cache_scope` site in `lib/` is either the server **emitting** hints
(`dispatch.ex:494-501`, `plug.ex:967-975`) or the client **parsing** them
(`discover.ex:82-83`). **No store exists**, so nothing can honour anything. The
register agrees — row CG5 is marked **OUTSTANDING** — and owner **MES-39** can
act.

**The adversarial pairing, run and rejected.** CG5 ↔ `sep-2549-tools-list-caching-hints`
and its 7 siblings: **rejected.** Server leg — a different implementation under
test — and the direction is inverted: the checks assert the server **emits**
hints; CG5 requires the client **honours** them. One of the 8 whole-key hits
(`caching/WireSchemaValid`) matched only because the *scenario name* contains
`cach`; it is about JSON-RPC wire validity and is not a candidate at all.

### CG6 — client writes trace-context `_meta` (SEP-414)

| layer | |
| --- | --- |
| **gap** | SEP-414: the client should write `traceparent` / `tracestate` / `baggage` into per-request `_meta`. |
| **discharge** | **NONE.** The three keys appear in **exactly one file in the tree** — `lib/mcp/protocol/meta.ex:54-57`, which *defines* them — and in **no test file at all**. The write side is `with_meta/2`'s closed three-key map, which is MES-32's defect. |
| **oc** | **`oc:none` — E0.** Sweep `/trace\|tracestate\|traceparent\|baggage\|w3c/i` over all 175: **0**, description-only and whole-key alike. |

**The false-NEGATIVE guard applied to its strongest candidate.** `request-metadata`
is the scenario most about `_meta`, so a name-driven "none" would be unsafe.
Read from the predicate: `ClientPopulatesMeta` requires exactly
`io.modelcontextprotocol/protocolVersion` **and**
`io.modelcontextprotocol/clientCapabilities` — `let l = a && c` — and touches no
trace key. The "none" survives the candidate most likely to overturn it.

**Not bucket 1** — no member. An outstanding requirement, **MES-32**.

### CG7 — `x-mcp-header` / `Mcp-Param-*` mirroring, client side

| layer | |
| --- | --- |
| **gap** | SEP-2243: mirror designated tool parameters into `Mcp-Param-*` headers; encode unsafe values; exclude tools with invalid `x-mcp-header` annotations. |
| **discharge** | `header_mirror_test.exs` — 34 units across 5 `describe`s; `routing_headers_test.exs:318,354,372` (T-CG7enc, end-to-end through `MCP.Client`); `client_tool_schemas_test.exs:81` (W6, exclusion). |
| **oc** | **MATCHED — 29 check keys**: `http-custom-headers` 18 + `http-invalid-tool-headers` 11. All 29 SUCCESS. |

**Evidence E1 + E3 + E4.** Both scenarios survive **both** discounts (they are
among the surviving 5 of 7), so the credit is discriminating, not merely driven.
MES-24 drove `http-invalid-tool-headers` 11/11 → **1/11 FAILED** with CG7's
exclusion switched off.

**AND simultaneously bucket-1 — 3 constraint families, 9 ET-CC units, 0 OC
checks.** `header_mirror_test.exs:109` — a `describe` whose own title names the
condition — holds 9 units over three constraints the suite's fixture never
exercises:

| constraint | spec anchor | units |
| --- | --- | --- |
| `number` is excluded though it is a JSON Schema scalar | `tools.mdx:355` | `:113`, `:120` |
| integer outside the IEEE 754 safe range is not mirrored | value-level rule | `:133` |
| static reachability — the chain must be solely `properties` keys | `streamable-http.mdx:389-397` | `:156,168,194,205,222,231` |

Established **by enumeration of all 29**, not by a term: the fixture's ten
invalid classes are `invalid_{empty,object,array,null}_header`,
`invalid_duplicate_{same,diff}_case`, `invalid_{space,colon,non_ascii,control_char}_in_name`.
None is a `number`-typed annotated parameter, a safe-range value, or a
misplaced annotation.

**The adversarial pairing, run and rejected — on the predicate, and descriptions
would have got it wrong.** `ClientCustomHeaderNoMirrorNumber` *looks* like the
number-exclusion claim. It is not:

    let n = e.headers[`mcp-param-floatval`];
    status: n === void 0 ? `SUCCESS` : `FAILURE`
    description: "...number-typed float_val is served UNANNOTATED per SEP-2243"

The check asserts an **unannotated** `number` is not mirrored. Our constraint is
that an **annotated** `number` is *rejected outright*. Different requirements,
one word apart, sharing a name. **The register stands** — this is A3 §2 arriving
on the client leg.

---

## 4. Total assignment — all 56, because a candidate-driven sweep answers about its candidates

**A name-driven sweep silently drops checks.** `/mcp-param|x-mcp-header/i`
returns **28**; CG7's two scenarios hold **29**. The missing one is
**`ClientKeepsValidTool`** — *"Client MUST keep valid tools while excluding
invalid ones"* — whose text names neither term. It is unambiguously CG7 (its
predicate is `this.calledTools.has('valid_tool')`, the positive half of the
exclusion rule) and a term-driven sweep loses it without saying so.

So every one of the 56 is assigned — to a CG, or explicitly to "no CG, and why".

| scenario | checks | CG |
| --- | --- | --- |
| `http-standard-headers` | 11 | **CG1** |
| `http-custom-headers` | 18 | **CG7** |
| `http-invalid-tool-headers` | 11 | **CG7** |
| `json-schema-ref-no-deref` | 1 | **CG4** |
| `request-metadata` | 8 | *no CG* |
| `sep-2322-client-request-state` | 5 | *no CG* |
| `tools_call` | 2 | *no CG* |
| | **56** | claimed **41**, unclaimed **15** |

Machine-checked: 41 + 15 = 56, 0 duplicate rows, no check claimed by two CGs.

### The 15 unclaimed — "no CG", and explicitly NOT bucket 2

Enumerated, never a bare count:

    request-metadata (8)               ClientSendsVersionHeader, ClientPopulatesMeta,
                                       ClientSendsClientInfo, ClientVersionHeaderMatchesMeta,
                                       ClientDeclaresRootsCapability,
                                       ClientDeclaresSamplingCapability,
                                       ClientDeclaresElicitationCapability,
                                       ClientRetrySupportedVersion
    sep-2322-client-request-state (5)  MRTRClientRequestStateEchoed, MRTRClientJsonRpcIdDifferent,
                                       MRTRClientParallelIsolation, MRTRClientNoStateOmitted,
                                       DefaultResultTypeComplete
    tools_call (2)                     ToolAddNumbers, WireSchemaValid

**These are "no CG". They are NOT bucket 2, and A4 does not record them as
such.** A non-CG ET-CC member may well match them — `conformance_request_state_test.exs`
is an obvious candidate for the MRTR five — and establishing that is **B2b's
sweep**, which has not run. Bucket 2 is the Sprint 7 build list, so a wrong entry
there schedules work that may already exist.

Two adjacencies worth naming, since both are near-misses rather than matches:
`ClientSendsVersionHeader` is a *header* check but `MCP-Protocol-Version`, not
CG1's `Mcp-Method`/`Mcp-Name` (ours is `routing_headers_test.exs:269`, labelled
D-4, not CG1); and `ClientPopulatesMeta` is a `_meta` check but not CG6's, per §3.

---

## 5. The tokens — emitted by `MatchKey`, never typed

**41 state-1 tokens.** Every claimed check was encoded with `MatchKey.encode/1`
and put through `guard_state/2`: **41 built, 41 resolved, 0 not state 1.**
Longest emitted here: 121 chars.

    oc:client/json-schema-ref-no-deref/sep-2106-no-network-ref-deref/NoNetworkRefDereference
    oc:client/http-standard-headers/sep-2243-client-includes-standard-headers/ClientMcpMethodHeader_tools_list
    oc:client/http-custom-headers/sep-2243-client-supports-custom-headers/ClientSupportsCustomHeaders
    oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-charset/ClientRejectsInvalidTool_invalid_control_char_name

**7 state-3 tokens**, each built with `none/2` and confirmed
`{:declared_unmatched, _}` — the guard asserts they do **not** resolve as OC keys:

    oc:none/no-oc-scenario/CG2-inbound-parse
    oc:none/no-oc-scenario/CG2-absent-yields-nil
    oc:none/no-oc-scenario/CG2-unknown-not-a-fault
    oc:none/no-oc-scenario/CG2-outbound-meta
    oc:none/no-oc-fixture-case/CG7-annotated-number-excluded
    oc:none/no-oc-fixture-case/CG7-integer-safe-range
    oc:none/no-oc-fixture-case/CG7-static-reachability

**Two reason-slugs, because the two absences are not the same absence.**
`no-oc-scenario` — the suite contains no scenario or check for this requirement
anywhere (CG2: measured 0 of 175). `no-oc-fixture-case` — the scenario exists
*and is matched*, but its fixture holds no case that would exercise this
constraint (CG7's three). Collapsing them would report "the suite cannot measure
this" and "the suite's fixture happens not to" as one thing.

**CG3, CG5 and CG6 get no token of either kind** — see §7(b).

---

## 6. What passing rules out — four mechanisms, all four fired

**1 — Token resolution, in both directions.** Every state-1 token must resolve
against A1's 175; every `oc:none` token must come back state 3, which *asserts*
it does not resolve. Both are refusals, not lookups. **Instrument controls run:**

| control | result |
| --- | --- |
| an OC token with one character corrupted | `{:error, {:unresolved, …}}` — **state 2, fails** |
| `none/2` with a `/` in the native id | `{:error, {:charset, "native_id"}}` — **refused, not emitted ambiguously** |
| a member carrying no tag | `{:error, :untagged}` — **state 4, fails** |

**2 — Total-assignment arithmetic.** claimed + unclaimed must be exactly 56. A
check claimed twice, or dropped, surfaces as a mismatch rather than as a
plausible table. **41 + 15 = 56, 0 duplicates.**

**3 — Adversarial pairings, run and rejected rather than hypothesised.** CG5 ↔
`caching` (rejected: server leg, and emit-vs-honour); CG7 ↔
`ClientCustomHeaderNoMirrorNumber` (rejected on the predicate: unannotated vs
annotated). Both recorded with the rule that rejected them, because a reader who
sees only the accepted pairings learns nothing about how hard they were to accept.

**4 — Sweep positive controls, run FIRST.** A term known to hit that returns 0
means the instrument is broken, not that the answer is none — the gate-6a
sentinel shape.

    /deref/i                      expect 1   -> 1   OK
    /mcp-param|x-mcp-header/i     expect 28  -> 28  OK

**So this reconciliation cannot return "all seven matched", and not as a matter
of taste — mechanism 2 makes it arithmetically impossible.** Once CG1, CG4 and
CG7 take 41 of the 56, the 15 that remain are `request-metadata`, MRTR
client-state and `tools_call` — none of which is about extensions negotiation,
cache honouring, trace context or client-side `listen`. **At least four CGs must
come back `oc:none` or the sum breaks.** That is what makes a "none" here a
result rather than a shrug.

---

## 7. The CG-numbering recommendation — RECOMMENDED, NOT EXECUTED

Epic ruling 3: nothing is renamed here. A3 and D1 own the mechanism.

### Matched CGs → retire with a pointer

**CG1, CG4 and CG7 become aliases recorded in the crosswalk** (`CG4 ≡
json-schema-ref-no-deref`), **not live `describe` titles.** Keeping the CG name
as a title would be a second index over one thing — the **S5-31 "two `totals`"
hazard**. Retiring it entirely would lose the provenance CGs carry in `docs/` and
in MES-38/MES-39; the pointer keeps it as data.

### Bucket-1 claims → the CG number survives, because OC gives them none

This is A3 §6's reserved state 3, and it needs no new mechanism.

### The finding against A3 §6 — a two-way split over a three-way space

§6 says a matched CG is a state-1 alias and an unmatched one is state 3 with "the
CG number in the `<native-id>` slot". Both halves inherit the assumption §1
rejects — that a CG is a unit of matching. Measured here:

**(a) A CG number is not unique in the native-id slot.** CG2 yields **4**
bucket-1 members and CG7 **3** bucket-1 constraint families. All 7 would carry
native id `CG2` or `CG7`, so D1's register could not tell them apart — the
S5-31 two-indexes hazard arriving through the slot meant to prevent it.

**Recommended:** a suffix convention within A3's **measured** `[A-Za-z0-9_-]`
charset, so `encode/1` still refuses ambiguity — `CG7-annotated-number-excluded`.
The 7 tokens in §5 are written that way and all 7 guard-check to state 3.

**(b) Three of seven CGs get no token of either kind.** **CG3, CG5 and CG6 have
no ET-CC member at all** — nothing is implemented, so nothing asserts it — and
**state 3 is a property of a member**. They are outstanding requirements owned by
MES-38, MES-39 and MES-32, not coverage. The "matched → alias, unmatched → native
id" split has no cell for them, and left as-is they read as adjudicated.

**Recommended:** record (b) as **out of the tag system by rule**, with its owner
ticket, rather than as an untagged member — which the Sprint 7 drift guard would
fail as state 4, correctly by the letter and uselessly in substance.

**Both are recommendations to A3/D1. This ticket does not execute either**, and
does not edit `match-relation.md`.

---

## 8. Known-limits cross-check (AC4)

Report §7 records seven Known limits, of which **the official suite does not
speak to five**: the 4xx-discard, server-side `Mcp-Param-*` validation, the
`subscriptions/listen` transport bound, HTTP/2 exposure, and `accept-encoding:
identity`.

**Exactly ONE CG is among them: CG3**, via *"`subscriptions/listen`
server-HTTP-only"* — the same limit stated from the client end.

**CG7 is adjacent to "no server-side `Mcp-Param-*` validation" but is NOT it.**
That limit is the **server** twin — register row D1, owned by **MES-45**. CG7 is
the client side and is implemented. Adjacency is not membership.

**CG2, CG5 and CG6 are unmeasured by the suite but are NOT among the seven.**
They are a different unmeasured set. Saying "three more CGs are unmeasured"
without this sentence would silently widen §7's list.

**And the two registers are not nested, in either direction.** Limit 2 — *"4xx
JSON-RPC error discarded by the client"* — is a **client-side** limit that is
**not** in the CG taxonomy. A reader who assumes every client limit is a CG, or
every CG a limit, is wrong both ways.

---

## 9. Bounds — what this file does NOT establish

1. **It records no edges.** Cardinality, check keys, claim decomposition,
   evidence class and axes are recorded; **C1 materialises the edges**, and the
   per-claim edge structs for CG1's 11 and CG7's 29 are deliberately not built
   here (A3's ownership table).
2. **The bucket-1 candidates named are those visible from the CGs' own discharge
   sites.** A complete claim-level sweep of the client leg is **B2b's**, and a
   non-CG ET-CC member may match checks this file records as unclaimed.
3. **CG1's two SKIPPED keys are flagged, not decided.** Bucket 0 is **A5's** set
   and the ratified match-target rule is A5's to apply.
4. **The 15 unclaimed are "no CG", not bucket 2** — §4.
5. **Axes are a reading of predicates at one build.** A harness bump invalidates
   them exactly as A1's residual R3 says it invalidates keys; the sha lets a
   reader tell whether that has happened, and nothing detects it automatically.
6. **The frozen 175 is the accepted run's key set, not the suite's capability** —
   see **S6-9**. This bounds every `oc:none` in this file: it means "no key in
   A1's 175", which is the right denominator for A3's relation and is *not* the
   same claim as "the suite could never score this". The two are separated by
   reason-slug in §5 wherever the evidence supports separating them.
