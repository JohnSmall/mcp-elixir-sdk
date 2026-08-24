# The ET-CC membership register

**Produced on MES-81 (B2a), Sprint 7, 2026-08-23/24, in four rounds.** The register
itself is [`etcc-register.json`](etcc-register.json); this file records how it was
produced, demonstrates the invariants, and carries the escalations, the PM tie-break
and the PM adjudications that re-decided 92 of the 112 escalated rows
(MES-81 comments `26033`-`26037`, `26047`-`26049` and `26058`-`26060`). Every figure
below is the **round-4** figure unless it says otherwise, and the earlier round's is
shown wherever a count moved.

**Round 4 is the same question asked at a MECHANICAL trigger instead of at a
selection, plus the granularity that question turns on.** Round 3 added L2 — direct
byte establishment where L1's redness proxy is silent — and then ran it on three of
the twelve boundaries whose antecedent held, because those were the three the sweep
suspected (F6, CODE_REVIEWER at `26055`). That is S7-17 clause (ii) landing on the
limb added to fix S7-17 clause (ii), and the PM's ruling is that **L2's trigger is
mechanical: it runs on every boundary whose live count is zero, never on a
selection**, with **guard 20** — *no boundary may be recorded DEAD without an L2
record* — making it checkable rather than promised (`26058`, `26059` item 4).

The PM also ruled the granularity the answer turns on: **a boundary is the PRODUCER
of the asserted bytes, so a `defimpl Jason.Encoder` and a `from_map/1` are different
boundaries** and one's liveness may not carry the other. That split is **§6a Step 1**,
and it cuts both ways — 9 rows return to `ET-CC` and 5 leave.

**Round 3 is one question asked of the whole population instead of a subset of it.**
Ruling A was stated over "family A" — a set drawn in round 1 around the rows the
sweep happened to escalate — and the review found 33 further rows that satisfy its
antecedent identically and were never put to it (F1, CODE_REVIEWER at `26044`). The
PM ruled the scope of a ruling is its **antecedent**, not the family it was stated
over (`26047`), and ordered a **total** sweep: partition every `ET-CC` row by the
encode/decode boundary its asserted bytes come from, run the named procedure once
per distinct boundary, and publish the whole table including the boundaries that
came back live. That is **§6a**, and it is the round's main deliverable — more so
than the count it moves.

**Repo is source of truth; there is no Confluence mirror of this file at the time
of writing.**

---

## §0 The two authorities — CITED, never restated

| what | where | this file's relation to it |
| --- | --- | --- |
| the membership criterion — gates, labels, precedence, totality, the residual | [`etcc-membership.md`](etcc-membership.md) (MES-80, landed at `ffc1a2f`) | **applies** it |
| the row key, the artefact and the join rules | [`etcc-row-key.md`](etcc-row-key.md) (MES-83, landed at `1a0fe5c`) | **adopts** it verbatim |

Neither is reproduced here, and that is deliberate: a definition living in two
places diverges, which is S7-6 and S6-5 before it. MES-80 exists **because** of
exactly that, and a second copy made one hop downstream of the ticket that fixed it
would be the same defect again. Section references below (`§2.2`, `§5.2`, `§11`)
are to `etcc-membership.md` unless another file is named.

**One line for the next adopter of `split_key/1`** (`etcc-row-key.md` §1.1):
splitting on the **first** `/` is load-bearing, not incidental — test names
routinely contain slashes, and
`MCP.ClientTest/test connect/1 (server/discover) returns error on discover failure`
is a real key in this register with three of them.

---

## §1 How the register was produced

**One authored source, one derived artefact.**

    conformance/data/etcc-decisions.json      <- AUTHORED. 579 entries, one per unit.
              +                                  label, excluding_gate, spec_anchor,
    docs/conformance/etcc-exunit-rows.json       falsifiable, mixed, consumed_at, controls,
              |                                  escalated, question, evidence, adjudication
              v
    conformance/lib/mcp/conformance/etcc_register.ex  (the generator)
              |
              v
    docs/conformance/etcc-register.json       <- DERIVED. Never hand-edited.

Every judgement lives in the decisions file and nowhere else. Every other field on
a register row — `module`, `name`, `file`, `line`, `test_type`, `describe` — is
**joined** from MES-83's artefact and is never re-derived, so the population is
never re-counted from source and HAZARD 1 is discharged by the join rather than by
care.

    mix run conformance/build_etcc_register.exs                       # rebuild
    mix run conformance/controls/etcc_register_controls.exs reproduce # rebuild and diff

**Provenance is content hashes, not a tip.** `provenance.artefact_rows_md5` and
`provenance.decisions_md5` are functions of the bytes alone. `etcc-row-key.md` §5.2
is why: the branch commit a measurement was taken at is left **unreferenced** by the
PM's squash-merge, so a recorded tip is not a handle anyone can resolve afterwards.

    ROUND 6, the delivered figures:
      artefact rows_md5  05f7b2d2b5a6948981d67d331cb40a5f   (UNCHANGED across all six
                                                             rounds — the population
                                                             never moved)
      decisions md5      d6d463b391f2c13ff232913f81613b97   (round 4: f82c43168e...,
                                                             round 2: d18775bf0c...)
      register md5       cc9504f8e483170bceda2a6c3d84830b   (round 4: e99e28b812...,
                                                             round 2: 80827129e9...,
                                                             round 1: 76ef01e91e...)

    All three are UNCHANGED from round 5, and that is a result rather than an
    oversight: round 6 corrected two prose figures and added one clause, and touched
    no generator input. `etcc-decisions.json` is byte-identical, and the only edit to
    `etcc-boundaries.json` is inside `the_direction_split`, a prose field the
    generator never reads — it consumes `.boundaries` alone (`etcc_register.ex:90`).
    A round that moved a label and left these hashes standing would be the defect;
    a round that moved neither is why they are printed.

The artefact hash is unchanged because no round changed **any test file or any `lib/`
file** — only judgements, and the measurements behind them. That is the property the
whole design is for: the register is a function of a tree that did not move
underneath it. Round 4's mutations are the same discipline — every one applied,
measured and reverted, with `git status --porcelain` clean and `979/0` re-verified
after the last of them.

**The L2 byte probe is committed, not ephemeral.** `conformance/etcc_l2_probe.exs` is
the instrument the round's central verdicts rest on, and S7-1 is the record of what
happens when the number survives and the thing that produced it does not.

### The generator fails closed, both ways

It **refuses to write** on any of **twenty-one** conditions — an in-scope unit with no
decision; a decision naming a key the artefact does not have (checked both ways);
the four labels not summing to the enumerated population; an `ET-CC` row with no
`spec_anchor`; a member carrying an excluding gate; a non-member carrying none; an
`ET-ADJ` row with no `consumed_at`; an `ET-CTRL` row controlling a unit that does
not exist; `falsifiable` on a non-member or missing from a member; `OUT-OF-SCOPE`
used as a fifth label; `escalated: true` with no question; a row with no evidence;
**an `adjudication` on a row that is no longer `escalated`**; and **`excluding_gate: 4`
anywhere**. Amendment 2 is made *unrepresentable* rather than promised.

The fourteenth was added in round 2 and enforces the PM's contract item 2 (`26037`):
an answered escalation must stay visible **as** one. A row that silently became an
ordinary decision would lose the evidence that a human had to decide it, and the
register would read as though the sweep had settled its hard cases by itself.

**Five more were added in round 3, and a twentieth in round 4.** One enforces `adjudication.raised_by` being
`sweep` or `PM` (`26046`/`26047`) — `escalated` says a human decided the row, only
`raised_by` says who found it hard. The other four make **ruling A** unrepresentable
the way amendment 2 already was: an `ET-CC` row with **no** boundary; a boundary on a
row that is **not** `ET-CC`; a boundary naming an id the boundaries file does not
record (*an unmeasured boundary is not a verdict*); and the one the PM asked for by
name (`26048` item 5) — **an `ET-CC` row every one of whose boundaries §6a records
`dead`**. That last is F1 made impossible to re-commit rather than promised not to
recur.

**Guard 21 was added in round 5** (PM ruling `26070`), and it closes the fourth and
last place this register's central shape had left to live: **attribution** — which rows
a verdict is applied to. The other guards check that a named boundary exists, that a
non-member names none, and that not every named one is dead; **none of them checks that
the set named is the RIGHT set**, which is why F9 survived four rounds and three seats.
Guard 21 reads the member's **own test body** and refuses a member that calls a split
module's decode-side producer without naming its `(decode)` direction. It is
alias-aware, because a qualified-name grep can only fail toward *"it does not"*
(S7-16), and it **raises rather than skipping** a body it cannot delimit — a guard that
quietly scans nothing reports a false green.

**Its reach is stated, not assumed: the six `ET-CC` doctest rows are OUTSIDE it.** A
doctest's body is the `@doc` in `lib/`, not the test file at that line, so scanning
there would scan the wrong bytes. That is a residual, and naming it is the point.

**Guard 20 was added in round 4** and it is the one that would have caught F6:
**a boundary the boundaries file records `dead` with no `l2` record beside it.** It is
a condition on the *measurement*, not on a label, so it is the only guard whose
control mutates `etcc-boundaries.json` rather than the decisions file — and it is
exercised in three forms (`l2` absent, `l2.ran: false`, `l2.verdict: "live"` under a
`dead` boundary), because a guard that only catches the null case would pass a
boundary carrying an L2 record that says the opposite of the verdict.

**Each of the twenty-one has been seen to fire.** `guards` mutates a copy of the
decisions file (or, for guard 20, the boundaries file) once per condition and prints
the refusal, then rebuilds the unmutated file to show the guards discriminate rather
than refusing everything:

    mix run conformance/controls/etcc_register_controls.exs guards     # 23/23 fired
                                                                      # (21 conditions,
                                                                      #  guard 20 in 3 forms)
    mix run conformance/controls/etcc_register_controls.exs totality
    mix run conformance/controls/etcc_register_controls.exs keysets
    mix run conformance/controls/etcc_register_controls.exs spec /tmp/spec2026full

### Why a control script and not an ExUnit test

Any test file added for this would land in the very suite the register enumerates:
under `test/mcp/` it would add members to the population it validates, and under
`test/conformance/` it would still move the artefact's 992 and so the out-of-scope
enumeration. **An instrument that changes its own denominator by existing is a
perturbation, not a test.** Same idiom as MES-83's
`conformance/controls/exunit_rows_controls.exs`.

---

## §2 The population, and that it reproduced

**579 units, in 39 files** — filtered from MES-83's artefact on `file` under
`test/mcp/`, never re-derived. `566 test + 13 doctest`, matching §7's ratified
figure. The remaining **413** rows are `test/conformance/` and are enumerated
separately (§9).

**Declared before the run, and it held.** `git diff --name-only 1a0fe5c..94f4d2a`
returns exactly one path (`docs/conformance/etcc-row-key.md`), `node v24.13.0` is
on PATH, and §5.1's three host-movable rows are all under `test/conformance/`. So
regenerating had to reproduce `rows_md5` byte for byte:

    MCP_ETCC_ROWS=/tmp/mes81_repro.json mix test --seed 0   at 94f4d2a
      13 doctests, 979 tests, 0 failures
      rows_md5  05f7b2d2b5a6948981d67d331cb40a5f   == the committed artefact's
      rows      identical, 992 == 992

Verified against `rows_md5`, not against `run.tip 8a305d3`, which the squash-merge
left unreferenced (`etcc-row-key.md` §5.2).

**One figure in the brief moved at this tip and is reported rather than carried.**
`test/conformance/` is **413** units here, not §1's ratified **285**: Sprint 7 has
been adding to it, which is §B.3's own mechanism showing again. The in-scope 579 is
unmoved, because gate 1 scopes on `test/mcp/`.

---

## §3 The result

**These are the ROUND-4 figures**, after the direction split and L2 at its own
trigger (`26058`-`26060`), and **round 5 left every one of them standing except the
last row**: it moved *attribution* — which boundaries a row names — and no label. The
earlier rounds are shown beside them, because a count that changed silently is a count
nobody can audit.

| label | count | share | round 3 | round 2 | round 1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ET-CC` | **281** | 48.5% | 277 | 307 | 340 |
| `ET-ADJ` | 88 | 15.2% | 88 | 88 | 90 |
| `ET-OUT` | **206** | 35.6% | 210 | 180 | 145 |
| `ET-CTRL` | 4 | 0.7% | 4 | 4 | 4 |
| **total** | **579** | | 579 | 579 | 579 |

| attribute | count |
| --- | ---: |
| `mixed: true` (§6 precedence) | 93 |
| `escalated: true` (§9) | 112 |
| `adjudication` recorded (§7) | 112 — **75 raised by the sweep, 37 raised by the PM** |
| `falsifiable: yes` / `no` / `undetermined` (ET-CC only) | 276 / 1 / 4 |
| excluded at gate 1 / 2 / 3 | 0 / 250 / 48 |
| excluded at **gate 4** | **0**, and the generator cannot represent one |
| distinct boundary ids carried by `ET-CC` rows | **34** of the 50 measured (§6a) |

**The direction of round 4 is the opposite of rounds 2 and 3, and that is the point
CODE_REVIEWER made at `26057` and the PM recorded at `26060`.** Two axes were moving
at once under one counter. The *rule's reach* widening drove 340 → 307 → 277
**downward**. The *instrument's bias* improving pushes the other way every time —
qualified-name grep (S7-16) → narrow mutation (S7-19) → wide mutation → direct byte
establishment — because every one of those was a proxy whose **silence was read as
death**. F6 is the instrument axis, so round 4 goes **up**. It is not the sweep
oscillating; it is two different corrections sharing a counter.

**`adjudication.raised_by` is new in round 3** (CODE_REVIEWER at `26046`, adopted at
`26047`). Guard 14 makes `escalated` mean *"a human had to decide this"*, which is
the predicate B2b wants; what it lost was the other reading, *"the sweep flagged this
as hard"*, which became false the moment a re-decision pulled in rows the sweep never
flagged — 2 under ruling E in round 2, 21 under ruling A in round 3 and 14 under the
direction split in round 4. The field separates the two readings and leaves guard 14
intact. **75 / 37 is the split**, re-derived from `adjudication.raised_by` at this tip
rather than carried: it read *"75 / 33"* — the round-3 figure, with the round-3
per-ruling breakdown beside it — until round 5, while the table above had been
re-derived to 112 in round 4. Found while executing the round-5 contract and reported
as **F12**, because it is F10's shape one section along: a figure in prose whose source
moved under it.

### What moved between round 1 and round 2, per ruling

| ruling | rows put | rows that moved | effect on `ET-CC` |
| --- | ---: | ---: | ---: |
| **A** — dead-path boundary (`26034`) | 45 | **40** | −40 |
| **B** — identity (`26035`) | 23 | 0, upheld as ruled | 0 |
| **C** — inherited assertions (`26035`) | 3 | 3 | +3 |
| **D** — `meta_test.exs:47` (`26035`) | 1 | 1 | +1 |
| **E** — absence markers (`26036`) | 6 | 4 | +3 |
| | **78** | **48** | **−33** |

### What moved in ROUND 4 — the direction split, and L2 at its own trigger (`26058`)

| | rows |
| --- | ---: |
| `ET-CC` at round 3 | 277 |
| rows ruling A had moved out on a boundary whose **encode** direction is LIVE — gate 2 re-decided per row and passing | **+9** |
| rows kept in on a boundary whose **decode** direction is DEAD once the split stops the encode side carrying it | **−5** |
| `ET-CC` at round 4 | **281** |

**The nine that returned.** All nine assert the bytes a struct's own
`Jason.Encoder` produced, and L2 shows those bytes on the wire through a real
`Dispatch.dispatch/3` (§6a). Ruling A's antecedent is therefore **false** for them,
so its ground for failing gate 2 disappears; gate 2 is then re-decided on its own
terms and **passes** (the asserted artefact is the output of a public encode boundary
a `lib/` call site routes to a transport, which is §2's first clause), and each row
recovers the gate-3 anchor it carried before ruling A moved it.

| file | rows | boundary that came back live |
| --- | ---: | --- |
| `types/tool_test.exs` | 4 | `MCP.Protocol.Types.Tool (encode)` |
| `types/content_test.exs` | 4 | `ImageContent` / `AudioContent` / `ResourceLink` / `EmbeddedResource` **(encode)** |
| `types/resource_test.exs` | 1 | `MCP.Protocol.Types.Resource (encode)` |

**The twelve that did NOT return, and this is what the split is for.** CODE_REVIEWER
put the upper bound at **21** rows sitting on boundaries shown live (`26056`), and
the PM restated it as an upper bound rather than a target (`26059` item 3). Twelve of
the 21 are `from_map/1` rows — they assert the **decoded struct's fields**, produced
by the DECODE direction, which is dead. They stay `ET-OUT`. **9 of 21 is the measured
answer**, and the difference between 21 and 9 is exactly the granularity ruling doing
its work.

**The five that left, reported because the ruling cuts both ways.**

| unit | why |
| --- | --- |
| `capabilities_test.exs:64`, `:75`, `:161` — `ClientCapabilities` `from_map/1` ×2 and the T9 decode half | `ClientCapabilities.from_map/1` has exactly **one** `lib/` call site, `initialize.ex:28`, inside `MCP.Protocol.Messages.Initialize` — a module `lib/` never uses. The server keeps `io.modelcontextprotocol/clientCapabilities` as a **raw map** (`meta.ex:105`) and never decodes it into this struct |
| `content_test.exs:15`, `:24` — `TextContent` `from_map/1` ×2 | the PM named these in advance (`26058`): they were `ET-CC` on `TextContent`'s **encode** liveness, and under the split they must be re-established on the **decode** side's own verdict. They are not; `TextContent.from_map/1` is reached only through the `Content.from_map/1` dispatcher, dead |

**All five go to `ET-OUT` with excluding gate 2** and carry
`adjudication.raised_by: "PM"`, so the register says a human decided them rather than
letting `escalated: true` imply the sweep flagged them.

### What moved in ROUND 3 — ruling A, applied to the whole population (`26048`)


| | rows |
| --- | ---: |
| `ET-CC` at round 2 | 307 |
| partitioned into **31 boundary groups** over **29 distinct boundaries** (§6a) | 307 |
| rows every one of whose boundaries came back **dead** | **−30** |
| `ET-CC` at round 3 | **277** |

**The review's expectation was 33 and the sweep returned 30**, and the contract said
*"if it disagrees with 33 the sweep wins"*. The whole of the difference is one
boundary: the review mutated `Types.Content` as a single unit and got DEAD; split per
subtype and mutated wider, `TextContent` is **live** and its three rows stay. Four of
the review's five modules reproduce exactly. The disagreement is not a disagreement
about a fact — it is what a wider mutation finds that a narrower one cannot, which is
**S7-19**.

| boundary | rows moved |
| --- | ---: |
| `MCP.Protocol.Types.Tool` | 9 |
| `MCP.Protocol.Messages.Resources` | 5 |
| `MCP.Protocol.Messages.Sampling` | 4 |
| `MCP.Protocol.Types.Resource` | 4 |
| `MCP.Protocol.Types.Content` + `ImageContent` / `AudioContent` / `EmbeddedResource` / `ResourceLink` | 8 |
| | **30** |

All 30 go to `ET-OUT` with excluding gate **2**, by §5 way (i): with no wire-producing
path there is no `lib/` call site for `ET-ADJ`'s second conjunct to name. Every one
carries `adjudication.raised_by: "PM"` — not one of them was escalated by the sweep,
and the register says so rather than letting `escalated: true` imply otherwise.

**The PM's sketch was `340 − 45 + 3 + up to 6`; the measured answer is 307**, and
the instruction was *"if it disagrees with that sketch the number wins."* The whole
of the difference is ruling A: it was expected to move all 45 and it moved 40. The
five it does not move are established per row in §7 below, which is what the ruling
itself asked for — *"establish that per row; do not apply it as a family sweep."*

Ruling E is 6 rows put and 4 moved because the ratified `from_meta/1 (9)` doctest
keeps its label (the ruling upholds it) and `extensions_test.exs:414` keeps its
label while its **excluding gate** moves 2 → 3.

### Against the prior declared before the sweep

The plan declared a coarse prior so the outcome could be wrong-footed. The prior is
scored against **round 3**, since that is the delivered register; the earlier rounds
are shown so the adjudications' effect on the verdict is visible rather than hidden.

| | declared | round 1 | round 2 | round 3 | round 4 | verdict |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `ET-CC` | 200–260 | 340 | 307 | 277 | **281** | **above the band, and it stopped closing** |
| `ET-ADJ` | 150–220 | 90 | 88 | 88 | **88** | **below the band, further** |
| `ET-OUT` | 100–170 | 145 | 180 | 210 | **206** | **above the band** — was within in round 1 |
| `ET-CTRL` | under 20 | 4 | 4 | 4 | **4** | within |
| rows with excluding gate 4 | zero | 0 | 0 | 0 | **0** | held |
| `ET-CC` rows with no anchor | zero | 0 | 0 | **0** | held |

**Three of the four bands are missed, not two, and the third miss is the
adjudications' doing.** `ET-OUT` was inside the band in round 1 and left it when
ruling A began moving rows into it — 40 in round 2 and 30 more in round 3. Reported
rather than re-drawn: a prior that is re-fitted after the fact has stopped being a
prior. **The direction is worth naming, though.** Each round of applying ruling A
more widely moves `ET-CC` toward the declared band and `ET-OUT` away from it, which
says the prior was closer to right about *members* than the round-1 sweep was, and
wrong about where the excess would land.

**The two original misses are one miss.** The prior was built expecting §10 category 4
(internal-representation tests, "the largest and least obvious") to dominate; the
PM's decode-boundary tie-break (§6 below) moves most of that family the other way,
because a value read back through the public decode boundary **unchanged** is a
wire artefact and not an internal representation. Applying the tie-break uniformly
is what produced round 1's 340, and the PM anticipated this in the ruling itself: *"If
applying it uniformly makes ET-CC come out at the top of your prior or above it,
that is the rule working, not the prior failing."* It is reported here as a number
and a rule together, per that instruction. Ruling A then took 40 of those rows back
out, which is the same principle working in the other direction: a boundary nothing
routes to a transport does not *produce* a wire artefact — and round 3's total sweep
took 30 more, on the same principle applied to the whole population rather than to
one family of it (§6a).

`ET-ADJ` did **not** swallow the tree, so §9 R2's escalation condition ("if B2a
finds `ET-ADJ` swallowing the tree, that is an A1 escalation with data") is **not**
triggered. Stated as a checked result, because "we did not escalate" and "we never
asked" print identically.

---

## §4 The totality invariant, demonstrated

    mix run conformance/controls/etcc_register_controls.exs totality

    ET-CC    281
    ET-CTRL  4
    ET-ADJ   88
    ET-OUT   206
    --------------
    sum      579
    in_scope 579   (the enumerated population)
    rows     579

    every row has exactly one label: true
    no key appears twice:            true
    sum == in_scope == rows:         true

    OUT-OF-SCOPE is held apart (§1) and is NOT in the sum: 413 units

**Recomputed from the committed register's own rows**, not from the generator's
counters — a hand-edited total would be red. And the key sets are checked **both
ways** against the artefact:

    ok  register rows == artefact rows under test/mcp/
    ok  register + out_of_scope == the whole artefact
    ok  register and out_of_scope are disjoint

This is what a bucket count cannot answer: **was the procedure applied to
everything.**

---

## §5 The ratified worked examples, used as a control

§11 pre-decides 22 units against the same gates. They were swept from source as
ordinary units and compared **afterwards**, never during. A control you correct
yourself against has stopped being a control.

| §11 | unit | ratified | this sweep |
| --- | --- | --- | --- |
| 1 | `DispatchTest` / `initialize … -32022` | `ET-CC` | `ET-CC`, gate 3 anchored at `schema.ts:450` + `changelog.mdx:14` |
| 2 | `MethodsTest` / `"request methods"` | `ET-ADJ`, `mixed` | `ET-ADJ`, `mixed` |
| 3 | `ClientConformanceTest` / control-on-the-control | `ET-CTRL` | `ET-CTRL` |
| 4 | `JsonSchema202012Test`, 47 units | **31 / 16**, 15 by gate 2 + 1 by gate 3 | **31 / 16**, 15 by gate 2 + 1 by gate 3 |
| 5 | the 13 doctests | **6 / 5 / 2** | **6 / 5 / 2** |
| 6 | `ToolTest` / the 2 generated booleans | `ET-OUT`, gate 3 | `ET-OUT`, gate 3 |
| 7 | `RoutingHeadersTest` / `"a request carries the body method"` | `ET-CC`, one unit | `ET-CC`, one unit |
| 9 | `CapabilityHonestyTest` | `ET-ADJ` | `ET-ADJ`, same call site |

**All eight labels agree, including both split figures.** Example 8 is
`test/conformance/` and is `OUT-OF-SCOPE` here, as §1 requires.

**Re-checked at round 2 (PM item 7: *"§11 stays a control: report any ratified label
that stops reproducing"*): all eight still reproduce, and none of the 48 rows the
adjudications moved is a §11 unit.** `dispatch_test.exs:82` `ET-CC`;
`methods_test.exs:6` `ET-ADJ`; `client_conformance_test.exs:134` `ET-CTRL`;
`JsonSchema202012Test` **31/16** with **15** at gate 2 and **1** at gate 3;
the 13 doctests **6/5/2**; `tool_test.exs`'s two generated units `ET-OUT` at gate 3;
`routing_headers_test.exs:90` `ET-CC`; `capability_honesty_test.exs:25` `ET-ADJ`.
Stated as a checked result, not as an absence of news.

**Re-checked at round 4** (PM `26059` item 8 — §11 stays the control). **All eight
still reproduce, and none of the 14 rows round 4 moved is a §11 unit**: the 14 sit in
`capabilities_test.exs`, `types/content_test.exs`, `types/resource_test.exs` and
`types/tool_test.exs`, none is a doctest, and none is one of `ToolTest`'s two
generated booleans. Re-derived from the delivered register rather than carried:
`dispatch_test.exs:82` `ET-CC`; `methods_test.exs:6` `ET-ADJ`;
`client_conformance_test.exs:134` `ET-CTRL`; `JsonSchema202012Test` **47 units,
31/16, 15 at gate 2 and 1 at gate 3**; the 13 doctests **6 `ET-CC` / 5 `ET-ADJ` /
2 `ET-OUT`**; `tool_test.exs`'s two generated units `ET-OUT` at gate 3;
`routing_headers_test.exs:90` `ET-CC`; `capability_honesty_test.exs:25` `ET-ADJ`.
`tool_test.exs` is the one to look at twice, since four rows returned to `ET-CC` in
that very file — but §11 example 6 names the two `boolean outputSchema` units, which
are `ET-OUT` by **gate 3** and were never ruling A's to move.

**Re-checked at round 5** (PM `26071` item 7). **All eight still reproduce, and round
5 moved no label at all**: the round-5 diff against the round-4 register is exactly
four rows' `boundary` and `evidence` fields and nothing else, so no §11 unit could
have moved — but the eight were re-derived rather than argued from that.
`dispatch_test.exs:82` `ET-CC`; `methods_test.exs:6` `ET-ADJ`, `mixed`;
`client_conformance_test.exs:134` `ET-CTRL`; `MCP.Server.JsonSchema202012Test`
**47 units, 31/16, 15 at gate 2 and 1 at gate 3**; the 13 doctests **6 `ET-CC` /
5 `ET-ADJ` / 2 `ET-OUT`**; `tool_test.exs:111`'s two generated units `ET-OUT` at gate
3; `routing_headers_test.exs:90` `ET-CC`; `capability_honesty_test.exs:25` `ET-ADJ`.
`tool_test.exs` is again the file to look at twice — two of the four rows round 5
touched are in it (`:73`, `:84`) — and again example 6's units are the two at `:109`,
which round 5 did not touch and whose labels did not move.

### Two sub-figures inside §11 do NOT reproduce at `94f4d2a`

Neither changes a label. Reported because §B.4(ii) records a third instance of a
figure in this thread not reproducing, and a fourth is worth naming.

1. **§11 example 2 says "11 of those constants **are** consumed on a wire path".
   It is 9 of 12.** `grep -rn "Methods.<name>()" lib/` returns zero for
   `initialize`, `ping` and `logging_set_level`; the other nine have call sites
   (`client.ex:314,324,330,333,336,339,342,346`, `dispatch.ex:126`). The
   `ET-ADJ, mixed` label is unaffected — one consumed constant is enough for §6.
2. **§11 example 4 says "two bind the response to `_result` and discard it". It is
   four** — `json_schema_2020_12_test.exs:321`, `:340`, `:439`, `:451`. The 15/1
   gate split and the 31/16 total both reproduce exactly.

### S7-13 — where this register carried one fact under two labels, and how it was answered

**Round 1 shipped the inconsistency deliberately, and round 2 removed it.** The
conflict: `§11.1` rules **both** `Extensions.from_meta/1` doctests `ET-CC`, calling
the `from_meta(nil)` one *"the weaker: `falsifiable: undetermined`"* — i.e. it
treats an absence marker as a **gate-4** weakness. The PM's decode-boundary
tie-break of 2026-08-23 (§6) ruled the opposite for structurally identical values:
a value with *"no wire counterpart at all"* fails **gate 2**, and `%{}` returned for
an input of `nil` has none.

Round 1 carried §11.1's ratified label for the unit §11.1 **names** and the
tie-break's answer for the five it does not, so one fact carried two labels, on
purpose — picking a side would have produced a tidy register and destroyed the only
evidence that the conflict existed.

**ANSWERED by PM ruling E, MES-81 comment `26036`, 2026-08-23.** §11.1's **ratio**
governs all six rows, not only the unit it names, and the two rulings are
*reconciled* rather than one withdrawn. The line:

> **Does the wire have a state this value is the decode of?**

| value | wire state it decodes | gate 2 |
| --- | --- | --- |
| `%{}` from `from_meta(nil)` | **YES** — *"the optional field is not present"* is a wire **condition**, and the marker is its verbatim decode | **passes**, `falsifiable: undetermined` |
| `:ready` from `Client.status/1` | **NO** — SDK-invented, with no wire counterpart present *or* absent. There is no state for it to be the decode of | **fails** |

So §6's worked cases stand and §11.1 stands. The weakness §11.1 saw is real — an
absence marker is a thin thing to assert — and **§4 is the mechanism built for
exactly that: gate 4 never excludes, it records.** Reaching for gate 2 to express a
gate-4 concern is what the tie-break did wrong here. The PM recorded it as their own
error and stated the transferable form: *a tie-break written to fill a gap in a
document can contradict that document, because the author is looking at the gap and
not at the text around it — so a tie-break must be checked against the worked
examples of the section it lands in, not only against the rule it replaces.*

**Gate 2 passing is not membership.** Each of the six still faced gate 3 alone, and
the outcomes are reported rather than assumed — see §7 family E. They split
**3 `ET-CC` / 2 `ET-OUT` / 1 unchanged**, which is why the ruling that answered six
rows moved four.

---

## §6 PM TIE-BREAK under §9 — the decode-boundary principle

**Ruled by the PM on 2026-08-23, MES-81 comment `26026`, in answer to a §9
escalation raised at the plan hop.** Recorded here rather than left in a Jira
comment thread, because a rule that lives only in a comment on a closed ticket is
the MES-80 shape and the reason that ticket existed. It is recorded **here and not
in `etcc-membership.md`**: promoting it into the criterion would be re-opening a
ratified document, which needs its own MES-67-style ratification and is not done by
the back door of a tie-break.

**What it answers.** §9's residual class **R1** — the gate-2 boundary between
spec-mandated wire shape and our own public-API shape — is *decided* (ruled out of
`ET-CC` by default) but carries **no worked case on either side** in the ratified
text; `§B.5` flags that as the boundary B2a would meet most often. This section
fills it with six, all real keys in one file, so the boundary is drawn between
neighbours rather than across the tree.

### The rule

> **An assertion on a decoded value handed back through the public API passes
> gate 2 when the ASSERTED VALUE is the wire value verbatim.** The container may
> change — JSON object to struct, string key to atom, a GenServer hop, a return
> tuple. **The VALUE may not.** If the SDK computes, defaults, renames or reshapes
> the value itself between the wire and the assertion, that is a §2.2 step and
> gate 2 fails.

It turns on the **value**, not on the number of hops: a hop transports a value, it
does not transform it. A gate that counted hops would exclude every integration
test in the tree and admit every unit test that happened to sit close to a socket,
which is the opposite of what gate 2 is for.

### The six worked cases — three each side

All in `test/mcp/client_test.exs`.

| unit | asserted artefact | label | why |
| --- | --- | --- | --- |
| `:141` per-request `_meta` | `req["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"]` on the encoded map | **`ET-CC`** | already a wire artefact — `client.ex:868` encodes every send |
| `:182` `call_tool` sends name and arguments | `req["method"]`, `req["params"]["name"]`, `["arguments"]` | **`ET-CC`** | same |
| `:124` returns error on discover failure | `{:error, error}` **and** `error.code == -32_603` | **`ET-CC`, `mixed: true`** | the `%Error{}` build **re-containers** `"code" => -32603` as `:code => -32603`; `-32603` is unchanged and it is the thing asserted. The `{:error, _}` tuple is our convention with no wire counterpart, so §6 records `mixed` |
| `:89` starts ready by default | `Client.status(client) == :ready` | **`ET-OUT`** | `:ready` is SDK-invented — **no wire counterpart at all**, so there is nothing for it to be verbatim to |
| `:347` close is idempotent | a second `close/1` returning `:ok` | **`ET-OUT`** | same |
| `:353` times out a pending request | `{:error, :timeout}` | **`ET-OUT`** | same |

**The line the six draw** is *"is there a wire value for this to be verbatim to?"*,
not *"is this public-API convenience?"* — the latter describes intent, the former is
a test. Precedent: `§11.1` rules `from_meta/1` `ET-CC` on exactly this ground (the
input literal is a wire `_meta` fragment and the function is the whole of the
interpretation); §9's tie-break route is what made the escalation the right move
rather than a sweeper's judgement call.

### Applied uniformly, and what it cost

The same principle from the other end explains the encode side:
`client.ex:868` is `defp encode(struct), do: Jason.decode!(Jason.encode!(struct))`
and it wraps **every** send (`:839` requests, `:864` notifications), so what
`MockTransport` records is an already-encoded string-keyed map with any hand-written
`Jason.Encoder` already applied. Roughly 90 client-side units assert that map. Both
families pass gate 2 on the value; each still faces gate 3 alone. This is the single
largest reason `ET-CC` came out at round 1's 340 rather than in the declared 200–260
band, and it still is at round 4's **281** (§3) — ruling A takes 66 rows back out
across rounds 2 to 4, but it takes them out of `Messages.Tools`, `Protocol.encode/1`,
`%Response{}` and the message/type modules of §6a, not out of this family: the ~90
`MockTransport` units assert what `client.ex:868` produces on the **live** send path,
and §6a measures `MCP.Client` at 12 live-path units reddened.

### The rule's OTHER edge, added by PM ruling A (`26034`, 2026-08-23)

The tie-break above says when a value handed back through the public API **is** a
wire artefact. Ruling A says when a public boundary **does not produce one at all**:

> **An assertion on the output of a public encode/decode boundary that NO `lib/`
> call site routes to a transport FAILS gate 2.** §2's first clause admits *"the
> output of the public encode/decode boundary **that produces one**"*, and the
> qualifier is ratified text doing work: a boundary nothing calls does not
> *produce* a wire artefact, it produces a value shaped like one. §2.2 asks *"is
> there an SDK step between the asserted value and the wire?"* — where there is no
> path to the wire, that question has no NO available, and §2.1's counterfactual
> returns YES.

**The worked pair, in §5.2's style — both addresses in this tree, separated by one
grep and confirmed by one mutation.**

| unit | path to the wire | gate 2 |
| --- | --- | --- |
| `client_test.exs:144` — asserts `req["params"]["_meta"][…]` | `client.ex:868` encodes it, `:839` sends it | **SURVIVES** |
| `tools_test.exs` on `Messages.Tools` (36 rows) | **NONE.** `grep -rn "\bTools\b" lib/` returns `messages/tools.ex` itself plus two lines of doc prose. Mutating the module's `from_map`/encoder keys reddened **18 units, all in `ToolsTest`; 0 of the other 961** | **FAILS** |

It is the same separation §5.2 already draws between `valid_identifier?/1` and
`reserved_prefix?/1` — two doctests of one module, same shape, same spec
neighbourhood, split by whether `lib/` consumes the artefact. Family A is that pair
at message scale.

**Why it matters beyond the label**, since B2b and B4 join on this key: the official
suite drives a live server over a socket, so no official check can reach
`Messages.Tools`. Leaving those rows in `ET-CC` would let the crosswalk pair them
against checks they cannot witness and overstate coverage — the precise
overstatement this epic exists to prevent.

**The honest counter, recorded rather than argued away.** On a plain reading §2's
first clause admits the public boundary without asking where it leads, and
`MCP.Protocol.encode/1` is literally the public encode boundary. The ambiguity is in
ratified text and the proper fix is an amendment to §2, not a tie-break; the PM
recorded this as the strongest candidate for the Part A amendment ticket, alongside
families C and E. **Until that ticket runs, this ruling governs B2a, B2b and B4.**

---

## §6a THE TOTAL BOUNDARY SWEEP — ruling A asked of the whole population

**PM correction contract `26048` items 1-5 (round 3) and `26058`-`26059` (round 4),
executed 2026-08-24.** §6's last subsection states ruling A. This section is the
measurement that decides which rows it reaches, run over **every** `ET-CC` row rather
than over the family the ruling was stated in front of.

**Why the whole population and not the review's 33.** F1 showed that ruling A was
applied to a set drawn around what the sweep escalated. Applying it instead to *the
rows the reviewer happened to look at* would move the boundary from one arbitrary
set to another — *"the same defect, one iteration later"* (`26047`). So the unit of
work here is the **partition**, not a list of modules someone thought to check.

**Round 4 applies that same sentence to the SECOND LIMB of the procedure, which is
where it had not been applied.** L2 was added in round 3 to remove the ambiguity in
L1's silence, and then run on the three boundaries the sweep suspected rather than on
the twelve whose live count was zero — *a limb applied to the rows someone thought to
look at, not to every row satisfying its antecedent*, which is S7-17 clause (ii)
landing on the limb added to fix S7-17 clause (ii). Six of the nine boundaries
recorded DEAD without an L2 record are wrong. The remedy is a **mechanical trigger**
and a **guard** at the moment a limb is introduced, not after: see **S7-20**.

### Step 1 — the partition, and the granularity ruling that re-cut it in round 4

Every `ET-CC` row is assigned the set of `lib/` encode/decode boundaries the bytes it
asserts are **produced by**. **Round 4 re-cuts that partition by DIRECTION**, on the
PM's ruling (`26058`):

> A boundary is the **PRODUCER of the asserted bytes**, and a `defimpl Jason.Encoder`
> and a `from_map/1` are different code running in opposite directions. Letting one's
> liveness carry the other is the same category error as letting a family's boundary
> carry a row outside it — F1 again, one level down.

**The antecedent, and its reach as a measured result rather than an intention.** A
boundary splits when its `lib/` module produces the asserted artefact in **both**
directions — a decode-side producer (`from_map/1`, `decode_*`, `parse_*`) and an
encode-side producer (`defimpl`/`@derive Jason.Encoder`, `to_map/1`, `encode_*`).
That test is applied **mechanically to every boundary in the partition**, not to the
Content family the ruling was stated in front of: applying a new limb only to the
cases that motivated it is precisely F6, and repeating it inside the round that fixes
F6 would be indefensible.

**The reach is 18 / 12 / 2, and those three categories account for all 32 module
names in the partition.**

* **18 satisfy it and are split** — 36 direction rows.
* **12 do not and are carried single-direction**, with no direction in the row id:
  `MCP.Client`, `Messages.Notification` and `Messages.Request` (hand-written encoder,
  no `from_map`), `Meta` and `decode_message/1` (decode only), `Extensions`
  (predicates and a normaliser, no wire codec), and the six that are **paths rather
  than codecs**: `Server.Dispatch`, `Server.Connection`,
  `Server.NotificationCollector`, `Server.Subscription`, `Transport.Stdio`,
  `Transport.StreamableHTTP.Plug`.
* **2 produce the asserted artefact in ONE direction only and are recorded with that
  direction named** — `Types.Content (decode)`, whose `from_map/1` dispatches by
  `"type"` (`content.ex:32-36`) and which has no encoder of its own, and
  `Messages.Response (encode)`, which has `@derive Jason.Encoder` and a `defimpl`
  (`response.ex:10`, `:30`) and no `from_map`. Neither satisfies the antecedent, so
  neither is split; both are named with a direction anyway because that is the only
  direction their bytes come from.

`2×18 + 12 + 2 = 50`, the boundaries file's own row count, and `36 + 2 = 38`
direction-carrying rows — **19 `(encode)` and 19 `(decode)`**. Every one of the **19**
boundary-directions this file records `dead` is among those 38 (6 `(encode)`,
13 `(decode)`); no undirected row is dead.

**(F14, corrected in round 6.** Rounds 4 and 5 said *"17 modules satisfy it and are
split (38 directions); 12 do not"*. Three things were wrong with it and each is worth
stating. It **accounted for 29 of the 32 names** — `Content` and `Response` were in
neither list, which is epic ruling 4 unmet in the one sentence that states the limb's
reach. It was **internally inconsistent before anyone touched the tree**: 17 split
modules is 34 directions, and the same sentence said 38; the 38 is right. And it was
**never right rather than stale** — the boundaries file has carried 18 both-direction
modules since `e27ca65`, so the sentence was wrong on the commit that wrote it.
**Guard 21 derives its split set from that same file** — `split_modules/1`
(`etcc_register.ex:396-405`) takes the ids carrying both directions, and it is the 18
that reached exactly the four rows round 5 corrected. So the executable code and the
prose about the same antecedent disagreed, in the field named *"reach stated as a
result"*. Found by CODE_REVIEWER at round 5; the third category is CODE_REVIEWER's
too, ruled in by the PM at `26080`. **No verdict, label, count or `ET-CC` total
moves: nothing keys on this sentence** — the row set, the guards and
`et_cc_by_boundary` all key on the boundary ids themselves.**)**

**And the wider reach changed exactly two verdicts.** Beyond the Content family,
every direction is live on **both** sides — `HeaderMirror`, `SSE`,
`ServerCapabilities`, `Discover` and `Messages.Subscriptions` all split into two live
halves, so for those the single round-3 verdict was sound. The two it does move are
`ClientCapabilities (decode)` and `Error (encode)`, and both are outside the family
the ruling was stated over. **That is the answer to whether the wider reach was worth
running: it is reported as a measurement, not argued.**

**Where a row asserts values from more than one producer its group names them all,
and ruling A moves the row only if EVERY one is dead.** That is the conservative
direction and it is deliberate.

**Round 5 applies that rule LITERALLY, on the PM's ruling (`26070`), and attribution
stops being the one step done by eye.** A row names every producer whose correctness
is **load-bearing** for what it asserts, and a decode-side producer is load-bearing
whenever the asserted value **passed through it**. The test is discrimination, not the
intent of the call: *"fixture builder"* is a fact about how a line reads, not about
what the unit can catch, and a criterion turning on it would not be runnable by a
second reader. Four rows under-named on that reading and now name their `(decode)`
direction — and each was established by **mutation**, which is §6a step 2's discipline
applied to attribution rather than to a boundary:

| row | mutation of the DECODE producer | reddened |
| --- | --- | ---: |
| `capabilities_test.exs:46` | `server_capabilities.ex:30` `Map.get("tools")` → `Map.get("toolsX")` | this unit + `:7` |
| `capabilities_test.exs:88` | `client_capabilities.ex:26` `Map.get("roots")` → `Map.get("rootsX")` | this unit + `:60` |
| `tool_test.exs:74` | `tool.ex:84` `Map.fetch!(map, "inputSchema")` → `Map.get(map, "inputSchemaX", %{})` | this unit + `:20`, `:131` |
| `tool_test.exs:86` | `tool.ex:88` `Map.get(map, "_meta")` → `Map.get(map, "_meta") \|\| %{}` | **this unit alone**, 1 of the file's 11 |

**(F15, corrected in round 6.** The first cell read *"this unit + `:29`"*. **There is
no unit at `capabilities_test.exs:31`** — the file's `test` declarations are `:7`,
`:26`, `:36`, `:42`, `:60`, `:75`, `:83`, `:115`, `:133`, `:143`, `:161`, `:171`,
`:181`, and the register has no row at `:29` either, so the address resolved to
nothing at all. `:29` is `assert caps.tools == nil`, an assertion **inside** the unit
declared at `:7`, which is the co-reddened unit. CODE_REVIEWER re-ran that exact
mutation over the whole suite at seed 0 and located it (`26078`); the other three
cells reproduced exactly. **No verdict moves and no label moves.** The row's own
`evidence` field says only — and correctly — that dropping the `tools` read *reddens
this unit*, which is the whole of what makes the decode direction load-bearing; only
the table cell was wrong.

**The column, not the cell (S7-24), and what the column actually reaches.** Every
**fully-qualified** `*_test.exs:NN` address in this document was re-resolved at the
delivered tip against the `test`/`describe`/`doctest` declarations in the file it
names — **99 occurrences**, machine-checked. **22 of them, 12 distinct, land on a
line that is not a declaration**, and every one of those was then read by hand: eleven
cite an **assertion** on purpose and each carries the bytes claimed for it —
`client_test.exs:62`, `self_compatibility_test.exs:126`,
`streamable_http_stateless_test.exs:84`, `:85`, `:278`, `dispatch_test.exs:84`,
`subscriptions_stream_test.exs:869`, `:857`, `:1011`, `client_conformance_test.exs:131`
(assertions) and `tool_order_test.exs:8` (the `server/tools.mdx` md5 the file records
for itself). The twelfth is `capabilities_test.exs:31`, and it appears now only in
this note, which cites it *as* the line that is not a unit.

**The bare `:NN` continuations are NOT machine-checkable here, and that is why F15
survived five rounds.** There are **127** of them, and a bare `:NN` takes its file
from whatever the prose last named — which is a `lib/` file as often as a test file
(`client.ex:839` → `:864`; `server_capabilities.ex:30`, then `:29` meaning
`capabilities_test.exs:31`). **The antecedent is carried by the sentence, not by the
notation**, so no resolver reads them without a rule the document does not state.
The four cells of the table above were therefore resolved by hand against each row's
own test file, which is what surfaced this one. **The general form is MES-85's and
MES-88's**, per `26080`'s stopping rule: extractable prose figures and re-runnable
addresses, with the antecedent rule written down rather than inferred.**)**

**`tool_test.exs:86` was put to the test separately, because it asserts only ABSENCES
— the S7-19 shape — and the answer has a boundary worth stating.** A `from_map/1` that
**wrongly populates** an absent optional fails it, and that is the whole fault class
the row exists to catch: *an unset optional must be ABSENT on the wire, not null*. A
`from_map/1` that merely **drops** a read does not — `tool.ex:86`
`Map.get("annotations")` → `Map.get("annotationsX")` leaves this unit green and
reddens `:29` instead. So the decode direction is load-bearing for exactly what this
row asserts, which is why it names it, and the negative half is reported rather than
rounded off.

**What that moves.** Three DEAD directions appear in `totals.et_cc_by_boundary` —
`Types.Tool (decode)` on 4 surviving members, `Types.Resource (decode)` on 1 and
`ClientCapabilities (decode)` on 1 — and `ET-CC` rows carry **34** distinct boundary
ids. A dead boundary appearing there is not a contradiction: those rows name both
directions and a row survives if **any** one is live. The generator's guard is written
on the right predicate — it refuses a member **all** of whose boundaries are dead, not
one that merely mentions a dead one — and **guard 21** now refuses the converse.

### Step 2 — the named procedure, with L2 at a MECHANICAL trigger

Seed 0, dedicated worktree, and an **unmutated control first**:
`13 doctests, 979 tests, 0 failures`, `node v24.13.0` on PATH. Every mutation was
applied, measured and **reverted**, and the tree re-verified clean; **no `lib/` or
`test/` file is changed by this ticket**.

* **L1 — the redness proxy.** Mutate the boundary-**direction**, re-run the suite,
  count what reddens outside its own tests and outside the units of directions this
  table records dead. At least one such unit means **live**. **L1's silence is
  ambiguous** — it means either *"nothing routes this to a transport"* or *"something
  does and no test asserts it"*.
* **L2 — direct establishment, in two conjuncts, and DEAD needs both.**
  **(a) the byte probe.** `mix run conformance/etcc_l2_probe.exs` drives **15 real
  `lib/` entry points** — `server/discover`, `tools/list`, `resources/list`,
  `resources/read`, `prompts/list`, `prompts/get`, five `tools/call` content shapes,
  an error response, an SSE frame and two `decode_message/1` inputs — and prints the
  bytes each produces. The direction's mutation is applied and the output diffed
  against the unmutated baseline. **A scenario that MOVES is a `lib/` call site
  routing the boundary to a transport**, so the antecedent is FALSE and the verdict is
  live. **(b) the call-site enumeration.** Every `lib/` reference to the boundary is
  listed — calls, `&Mod.fun/1` **captures** and dynamic dispatch included, and
  **alias-aware** per S7-16 — and each caller followed to a live entry point or to a
  module `lib/` never uses.
* **(a) alone cannot establish DEAD.** The probe is server-side and its silence is
  another proxy — reading it as death is the exact failure this round exists to close.
  Every DEAD verdict below therefore carries (b) as well, and the boundaries file
  records both.

**L2's trigger is MECHANICAL: it runs on every boundary-direction whose live count is
zero. Never on a selection.** Round 3 stated the trigger as *"where L1 is silent"*,
`reddened_outside_own_and_dead == 0` held for **twelve** boundaries, and L2 was run on
**three** — the three the sweep suspected. Nine were recorded DEAD with no L2 record
at all, and six of those nine are wrong. **Guard 20** now makes that unrepresentable:
*no boundary may be recorded DEAD without an L2 record.*

A **DEAD** verdict additionally requires the mutation to be **potent** — to have
reddened at least one of that direction's own units. It does for all 19.

**The live column's exclusion set, and the hole round 4 closed.** A unit is excluded
from a direction's live count when it lies in the own-tests of a direction recorded
DEAD. The exclusion is **file-level** where every direction on that file is dead and
**unit-level** where the file is shared with a live one — otherwise excluding
`tool_test.exs` for the dead decode side would silence the live encode side too.
Both sets are enumerated in `etcc-boundaries.json` rather than described (27 units
at unit level; at file level:

* `test/mcp/protocol/messages/initialize_test.exs` — every boundary-direction on it is dead
* `test/mcp/protocol/messages/resources_test.exs` — every boundary-direction on it is dead
* `test/mcp/protocol/messages/sampling_test.exs` — every boundary-direction on it is dead
* `test/mcp/protocol/messages/tools_test.exs` — every boundary-direction on it is dead

**The unit-level form is new at round 4, and `initialize_test.exs` is why.** A module
`lib/` never uses acquires no `ET-CC` row, so it never becomes a boundary, so its
own-tests are never excluded — and its redness then reads as **live-path evidence for
whatever it happens to call**. `MCP.Protocol.Messages.Initialize` is such a module
(the 2026-07-28 core has no handshake, SEP-2575/2567), and both of L1's two "live"
units for `ClientCapabilities (decode)` were in its test file. **All 21 test files
contributing to a live count were checked for this shape and `initialize_test.exs` is
the only one that was missing** — a checked result over the whole set, not a spot fix.
`Messages.Initialize`, `Messages.Tools` and `Messages.Response` are now recorded as
boundaries in their own right, so guard 20 reaches them. See **S7-21**.

### Step 3 — the whole table, live boundaries included

Epic ruling 4: negatives enumerated. **50 boundary-directions, 19 dead.** `outside`
excludes the direction's own tests; **`live`** additionally applies the exclusion set
above and is the column ruling A turns on. The `L2` column says what the byte probe
did: *moved N* means N of the 15 scenarios changed under the mutation, so the
direction is live; *silent* means none did, and for a DEAD row the verdict then rests
on the call-site enumeration recorded beside it in `etcc-boundaries.json`. A dash is a
direction live by L1 with a wide margin, where L2's trigger never fired.

| boundary-direction | reddened | outside | live | verdict | L2 | ET-CC rows still naming it |
| --- | ---: | ---: | ---: | --- | --- | ---: |
| `MCP.Protocol.Capabilities.ClientCapabilities (decode)` | 5 | 2 | **0** | **DEAD** | L2 silent | 1 |
| `MCP.Protocol.Error (encode)` | 3 | 1 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Initialize (decode)` | 5 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Initialize (encode)` | 2 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Resources (decode)` | 5 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Resources (encode)` | 1 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Response (encode)` | 2 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Sampling (decode)` | 4 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Sampling (encode)` | 2 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Tools (decode)` | 20 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Messages.Tools (encode)` | 27 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Types.Content (decode)` | 13 | 7 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Types.Content.AudioContent (decode)` | 1 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Types.Content.EmbeddedResource (decode)` | 1 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Types.Content.ImageContent (decode)` | 2 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Types.Content.ResourceLink (decode)` | 1 | 0 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Types.Content.TextContent (decode)` | 10 | 7 | **0** | **DEAD** | L2 silent | 0 |
| `MCP.Protocol.Types.Resource (decode)` | 5 | 1 | **0** | **DEAD** | L2 silent | 1 |
| `MCP.Protocol.Types.Tool (decode)` | 13 | 2 | **0** | **DEAD** | L2 silent | 4 |
| `MCP.Client` | 34 | 12 | **12** | live | — | 57 |
| `MCP.Protocol.Capabilities.ClientCapabilities (encode)` | 8 | 6 | **5** | live | L2 silent | 3 |
| `MCP.Protocol.Capabilities.ServerCapabilities (decode)` | 11 | 7 | **6** | live | L2 silent | 6 |
| `MCP.Protocol.Capabilities.ServerCapabilities (encode)` | 12 | 9 | **9** | live | L2 moved 1 | 5 |
| `MCP.Protocol.Error (decode)` | 20 | 18 | **18** | live | L2 moved 15 | 3 |
| `MCP.Protocol.Extensions` | 4 | 1 | **1** | live | — | 7 |
| `MCP.Protocol.HeaderMirror (decode)` | 6 | 4 | **4** | live | L2 silent | 12 |
| `MCP.Protocol.HeaderMirror (encode)` | 33 | 16 | **16** | live | L2 silent | 40 |
| `MCP.Protocol.Messages.Discover (decode)` | 33 | 32 | **32** | live | L2 silent | 1 |
| `MCP.Protocol.Messages.Discover (encode)` | 21 | 20 | **20** | live | L2 moved 1 | 2 |
| `MCP.Protocol.Messages.Notification` | 15 | 14 | **14** | live | — | 2 |
| `MCP.Protocol.Messages.Request` | 37 | 34 | **34** | live | — | 3 |
| `MCP.Protocol.Messages.Subscriptions (decode)` | 42 | 22 | **22** | live | L2 silent | 2 |
| `MCP.Protocol.Messages.Subscriptions (encode)` | 12 | 6 | **6** | live | L2 silent | 9 |
| `MCP.Protocol.Meta` | 99 (+36 unlocated) | 98 | **98** | live | — | 2 |
| `MCP.Protocol.Types.Content.AudioContent (encode)` | 1 | 0 | **0** | live | L2 moved 1 | 1 |
| `MCP.Protocol.Types.Content.EmbeddedResource (encode)` | 1 | 0 | **0** | live | L2 moved 1 | 1 |
| `MCP.Protocol.Types.Content.ImageContent (encode)` | 2 | 0 | **0** | live | L2 moved 1 | 1 |
| `MCP.Protocol.Types.Content.ResourceLink (encode)` | 1 | 0 | **0** | live | L2 moved 1 | 1 |
| `MCP.Protocol.Types.Content.TextContent (encode)` | 1 | 0 | **0** | live | L2 moved 2 | 1 |
| `MCP.Protocol.Types.Resource (encode)` | 1 | 0 | **0** | live | L2 moved 1 | 1 |
| `MCP.Protocol.Types.Tool (encode)` | 5 | 1 | **0** | live | L2 moved 1 | 4 |
| `MCP.Protocol.decode_message/1` | 69 | 64 | **64** | live | — | 5 |
| `MCP.Server.Connection` | 0 | 0 | **0** | live | L2 silent | 6 |
| `MCP.Server.Dispatch` | 99 (+8 unlocated) | 86 | **86** | live | — | 85 |
| `MCP.Server.NotificationCollector` | 1 | 0 | **0** | live | L2 silent | 1 |
| `MCP.Server.Subscription` | 6 | 5 | **5** | live | — | 22 |
| `MCP.Transport.SSE (decode)` | 31 | 20 | **20** | live | L2 silent | 12 |
| `MCP.Transport.SSE (encode)` | 25 | 20 | **20** | live | L2 moved 1 | 25 |
| `MCP.Transport.Stdio` | 5 | 0 | **0** | live | L2 silent | 5 |
| `MCP.Transport.StreamableHTTP.Plug` | 33 | 6 | **6** | live | — | 29 |

### The seven encode directions L2 brought back, with the bytes

Every one is a handler returning the struct through a **real
`MCP.Server.Dispatch.dispatch/3`**, then `Jason.encode!` on the response map —
reproducible with `mix run conformance/etcc_l2_probe.exs`.

| direction | the bytes on the wire |
| --- | --- |
| `Types.Tool (encode)` | `{"tools":[{"name":"t","description":"d","inputSchema":{"type":"object"}}]}` |
| `Types.Resource (encode)` | `{"resources":[{"name":"a","uri":"file:///a","mimeType":"text/plain"}]}` |
| `Content.TextContent (encode)` | `{"content":[{"type":"text","text":"hello"}],"resultType":"complete"}` |
| `Content.ImageContent (encode)` | `{"content":[{"data":"AAA","type":"image","mimeType":"image/png"}],…}` |
| `Content.AudioContent (encode)` | `{"content":[{"data":"BBB","type":"audio","mimeType":"audio/wav"}],…}` |
| `Content.ResourceLink (encode)` | `{"content":[{"name":"x","type":"resource_link","uri":"file:///x"}],…}` |
| `Content.EmbeddedResource (encode)` | `{"content":[{"type":"resource","resource":{"text":"z","uri":"file:///r"}}],…}` |

Six of the seven are CODE_REVIEWER's F6 findings (`26055`) **re-established at this
seat rather than taken** — every byte string above was produced by this ticket's own
probe run and matches CR's character for character. The seventh, `TextContent`, was
already live at round 3, and round 4 **narrows its warrant rather than widening it**:
L1's single live unit there was `json_schema_2020_12_test.exs:488`, which reddens
because `dispatch.ex:662` pattern-matches `type: "text", text: text` on the
**struct's fields**, not on encoded bytes. A struct-field match is neither encode nor
decode, so that signal is **not** cited (PM, `26058`). The encode direction now rests
on the bytes alone — which is why it survives the split at all.

### The three path boundaries carried from round 3

`MCP.Server.Connection`, `MCP.Server.NotificationCollector` and `MCP.Transport.Stdio`
are single-direction paths whose round-3 L2 records stand unchanged and are carried
verbatim in `etcc-boundaries.json`; CODE_REVIEWER re-opened all three call sites and
upheld them (`26057`).

### What this table does NOT establish

It answers **gate 2's reachability question and nothing else.** A direction coming
back live does not make its rows members — each still faces gate 3 alone. Nor does a
live verdict mean the official suite can reach the boundary; that is C1's
match-relation question.

**And one scope question no instrument here touches, ruled out of scope by
CODE_REVIEWER at `26057` and recorded by the PM at `26060` so nobody reopens it
casually:** L2 establishes *"`lib/` **can** put these bytes on the wire"*, which is
what ruling A's antecedent asks. It does **not** ask whether anything a real caller
does actually reaches it. Left alone until an answer turns on it.

---

## §7 Escalations — 112 rows, five families plus rounds 3 and 4's total sweep, all adjudicated

§9's tie-break route: an undecidable case is an **A1 escalation to the PM**, never a
sweeper's judgement call. Each escalated row carries `escalated: true`, **the
question**, and — since round 2 — an **`adjudication`** naming the ruling, its Jira
comment id and its date. Both sets are queryable from the register itself:

    jq '[.rows[] | select(.escalated)] | length'            docs/conformance/etcc-register.json   # 112
    jq '[.rows[] | select(.adjudication)] | length'         docs/conformance/etcc-register.json   # 112
    jq '.totals.adjudications_raised_by'                    docs/conformance/etcc-register.json   # 75 sweep / 37 PM
    jq '[.rows[] | select(.adjudication.ruling=="A")] | length' docs/conformance/etcc-register.json   # 80
    jq '[.rows[] | select(.adjudication.comment=="26058")] | length' docs/conformance/etcc-register.json   # 14

**An answered escalation stays escalated.** The generator refuses to write an
adjudicated row that is no longer `escalated` (§1, guard 14), because a row that
quietly became an ordinary decision would lose the evidence that a human had to
decide it.

**Round 1 escalated 75 rows, round 2 carries 78, round 3 carries 108 and round 4
carries 112.** Every row
added after round 1 carries `adjudication.raised_by: "PM"`, so the two readings of
`escalated` stay distinguishable (§3). Ruling E named six rows and three
of them (`meta_test.exs:29`, `capabilities_test.exs:28`, `:75`) had been decided
without escalation in round 1, so they are now escalated and adjudicated alongside
the three that were.

| # | family | rows | provisional (round 1) | PM ruling | outcome | moved |
| --- | --- | ---: | --- | --- | --- | ---: |
| A | the dead-path question | 45 | `ET-CC` | **A** (`26034`) | **overturned**, per row | 40 |
| B | the identity family | 23 | `ET-OUT` | **B** (`26035`) | **upheld as ruled** | 0 |
| C | inherited assertions | 3 | `ET-OUT` | **C** (`26035`) | **overturned** | 3 |
| D | `meta_test.exs:47` | 1 | `ET-ADJ` | **D** (`26035`) | gate 2 passes; gate 3 applied | 1 |
| E | the absence markers | 6 | mixed | **E** (`26036`) | **reconciled with §11.1** | 4 |

---

**Round 3 added 30 rows to this section** — the rows ruling A reaches once its
antecedent, rather than the round-1 family, decides its scope. They are adjudicated
under ruling A at comment `26048` and carry `raised_by: "PM"`; the measurement that
decided each one is **§6a**, and the per-row evidence names its boundary's row of
that table. Family A below is the round-2 record and is left as it stood.

**Round 4 adds 4 more and re-decides 14** — the 9 that return to `ET-CC` because
ruling A's antecedent turns out FALSE for the encode direction their bytes come from,
and the 5 that leave because the split stops a live encode side carrying a dead decode
side. All 14 are adjudicated under ruling A at comment `26058` and carry
`raised_by: "PM"`; 4 of them were not escalated before, which is the +4.

### Family A — the dead path. Ruling A (`26034`). 45 rows put, **40 moved, 5 did not.**

**The ruling was applied per row, exactly as it required** — *"establish that per
row; do not apply it as a family sweep"* — and the establishment was done by
**mutating the encoder that produces each row's asserted bytes and re-running the
whole 979-unit suite**, not by a grep alone. A grep on the fully-qualified module
name is not sufficient here, and that is not a hypothetical: see the correction at
the end of this section.

**The 40 that moved → `ET-OUT`, excluding gate 2** (§5 way (i): no `lib/` call site
consumes the artefact, so `ET-ADJ` is unreachable).

| rows | asserted boundary | mutation, and what reddened |
| ---: | --- | --- |
| 36 | `Messages.Tools` (`ListParams`, `CallParams`, `CallResult`, `ListResult`) | broke the `cursor` / `content` / `isError` keys and the `structuredContent` encoder key → **18 units, all `ToolsTest`; 0 of the other 961** |
| 2 | `%MCP.Protocol.Error{}`'s derived `Jason.Encoder` (`error_test.exs:84`, `:94`) | replaced it with one emitting `codeX/messageX/dataX` → **3 units, all on dead paths; 0 live**. The outbound error object is built **by hand** at `dispatch.ex:724-728` and `plug.ex:1019-1023` |
| 2 | `%Response{}`'s `defimpl Jason.Encoder` (`protocol_test.exs:39`, `:48`) | `idX/errorX/resultX` → **exactly 2 units, both `ProtocolTest`; 0 of the other 977** |

**The 5 that did NOT move, and this is reported rather than absorbed.** `ET-CC`
stands on `protocol_test.exs:16`, `:26`, `:171` (`%Request{}`) and `:61`, `:72`
(`%Notification{}`), because **ruling A's antecedent is not satisfied for them**: a
`lib/` call site *does* route those encoders' output to a transport.

| mutation | reddened |
| --- | --- |
| `%Request{}`'s hand-written `defimpl` (`request.ex:25`, `method:` → `methodX:`) | **37 units across 8 modules** — 18 `ClientTest`, 8 `IntegrationTest`, 3 `ProtocolTest`, 3 `RoutingHeadersTest`, 2 `ClientToolSchemasTest`, 1 each `ClientDefectsTest` / `ClientConformanceTest` / `SelfCompatibilityTest`; every one of the 18 `ClientTest` units on `assert discover["method"] == "server/discover"`. The live emit path is `client.ex:839` → `:868` `Jason.encode!(Request.new(…))`, through this same `defimpl`. **(F2, corrected in round 3.** Round 2 said *"3 in `ProtocolTest` AND 21 in `ClientTest`"* and presented that as the whole reddened set. It is 18, not 21, and six further modules redden. Measured twice at seed 0 by CODE_REVIEWER (`26045`) and reproduced independently here: **37 both times**. The error ran **toward more live-path evidence**, so no label moves — the survivors' case is stronger than round 2 claimed. Corrected in the three rows that state it as well as here.**)** |
| `%Notification{}`'s `defimpl` (`notification.ex:24`, then `:29`) | the unit **and 14 (resp. 13) live-path units** across `NotificationCollectorTest`, `SubscriptionsDispatchTest`, `SubscriptionsStreamTest` and `ClientTest`. Live emit paths: `connection.ex:203`, `notification_collector.ex:49` |

So §2.1's counterfactual returns **NO** for these five: an SDK that got this wire
behaviour arbitrarily wrong does not still pass them, and it breaks the emitting
path at the same time. **This disagrees with the ruling's stated expectation of
"all 45", and it is handed up rather than smoothed over.** It is overturnable in one
hop if the PM reads ruling A as keyed on the **entry point** (`Protocol.encode/1`,
0 `lib/` call sites) rather than on the **encoder the asserted bytes come from**
(live). Both readings are on all five rows.

**CORRECTION to round 1's evidence, and to the PM's own verification at `26033`.**
Round 1 stated that `MCP.Protocol.Messages.Response` is *"used NOWHERE in `lib/`"*,
on `grep -rn "Messages.Response" lib/` returning only its own file; the PM
reproduced that grep and recorded `Messages.Response -> 1 (its own defmodule file)`.
**The grep is on the fully-qualified name and misses the alias.** `lib/mcp/protocol.ex:7`,
`lib/mcp/client.ex:98` and `lib/mcp/server/connection.ex:35` all `alias
MCP.Protocol.Messages.{… Response}`, and `%Response{}` **is** constructed at
`protocol.ex:98` and pattern-matched at `client.ex:363,415,435,449,463,538,563,582,597,640,656,665`
and `connection.ex:112`.

**The ruling is unaffected, and the narrower claim that survives is the one that
matters:** every one of those uses is **INBOUND** — `decode_response/1` builds the
struct and the client consumes it — and no `lib/` path ever re-encodes a
`%Response{}`. `Response.success/2` and `Response.error/2` have **zero** `lib/` call
sites (`grep -rnE 'Response\.(success|error|new)\(' lib/`), and the mutation above
is the direct evidence: breaking the encoder arbitrarily left all 977 other units
green. **Recorded as S7-16:** a call-site grep on a fully-qualified module name
answers a *different* question in a codebase that aliases, and the answer it gives
is always the reassuring one. It also corrects `docs/sprint_7_issues.md` S7-10's own
table, which is append-only and so is corrected there rather than edited.

---

### Family B — identity. Ruling B (`26035`). 23 rows, **0 moved. Upheld as ruled.**

These assert an identity string threaded from `ToolContext.identity` out through a
spec-defined response envelope. Gate 2 passes. Gate 3 is where they die, on §10
category 6: no 2026-07-28 requirement governs what a tool returns, nor says a
model-supplied `identity` argument must not become the caller principal — that is
CLAUDE.md critical rule 6, this project's design spec, **not** the pinned revision.
The nearest spec text (`schema.ts:85-88`, `clientInfo` *"is not verified by the
protocol"*) is about a different field, and naming it would be the AC7 error of
claiming a bound that does not hold. The PM: *"declining to name one is the harder
and better call."* The counter-reading — that the envelope field names are
load-bearing and §3 asks only whether an anchor can be **produced** — is real, and
is on all 23 rows.

---

### Family C — inherited assertions. Ruling C (`26035`). 3 rows, **all 3 moved to `ET-CC`, `mixed`.**

**§6 governs and it is ratified Part A: a test is indivisible.**
`assert discover["method"] == "server/discover"` (`client_test.exs:62`, inside
`do_connect/2`) executes as part of `:353`, `:359` and `:425`; misspell the method
and all three go red — **measured**, in the `%Request{}` mutation above, where every
one of the 21 reddened `ClientTest` units failed on exactly that assertion.

Round 1 cited the PM tie-break's naming of `:353` against §6. The PM corrected that
reading of their own ruling: `:353` was named to decide its **own**
`{:error, :timeout}` assertion, and inherited assertions were never put to them.
**Ratified Part A outranks a §9 tie-break** — the same precedence round 1 itself
applied to §11.1 in family E, *"and a precedence rule that only runs in the
direction that suits the sweeper is not a precedence rule."*

Anchor: `schema.ts:665-666` (`DiscoverRequest.method: "server/discover"`).
`falsifiable: yes` (measured, above). `mixed: true` — each unit's own body asserts an
SDK-invented value that earns `ET-OUT`, and §6 takes the highest.

**"Exactly three and nothing else" — established by enumeration, per epic ruling 4.**
`do_connect/2` has **17** call sites in `client_test.exs`: lines 143, 166, 184, 204,
221, 240, 265, 301, 320, 334, 355, 361, 375, 388, 417, 427, 473. Their enclosing
declarations and labels:

| enclosing test | label before ruling C |
| --- | --- |
| `:141`, `:164`, `:182`, `:202`, `:219`, `:238`, `:261`, `:299`, `:318`, `:330`, `:373`, `:386`, `:415`, `:469` (**14**) | already `ET-CC` **on their own assertions** — §6 lifts nothing that was not already lifted |
| `:353`, `:359`, `:425` (**3**) | `ET-OUT` — the only three with no wire assertion of their own |

So the ruling moves exactly these three. The consequence the PM accepted — *every*
test sharing an asserting setup helper becomes a member — is a reason to **amend**
§6, not to decide against it here, and it is on the Part A amendment candidate list.

---

### Family D — `meta_test.exs:47`. Ruling D (`26035`). 1 row, moved to `ET-CC`, `mixed`.

The asserted value `{:error, {:unsupported, "2025-11-25"}}` carries the
wire-supplied version string **verbatim** inside an SDK-invented container. Round 1
separated it from the ratified `:124` case on the ground that `:124` has a
*separate* assertion isolating the wire value; the PM declined to add that
criterion, because it would make membership depend on how an author happened to
split an `assert` — a property of typing, not of what is claimed. The container is
precisely what §6's `mixed` records.

**Gate 3 was applied here and its outcome is reported, not assumed.** It **passes**:
`schema.ts:69-75` makes it a MUST that a server not supporting the requested version
returns an `UnsupportedProtocolVersionError` (`:450`, `-32022`; `:483-488`), and this
unit asserts the classification that MUST is conditioned on. `falsifiable: yes` — an
SDK that treated `2025-11-25` as supported returns `:ok` and reddens the equality.

---

### Family E — the absence markers. Ruling E (`26036`). 6 rows put, **4 moved.**

**Family E is the round-2 record and is left as it stood — and unlike Family A, one
of its `result` cells no longer matches the delivered label.** `capabilities_test.exs:79`
reads `ET-OUT` → **`ET-CC`** below; **at the delivered tip that row is `ET-OUT`**.
Round 4's ruling A took it back out (`26058`) — it is one of the F13 trio `:60`,
`:75`, `:161` — so its `adjudication` in the register now names ruling **A**, and
`etcc-register.json` carries **5** rows under ruling E against this heading's **6**.
Of the four rows ruling E moved, **three still stand**: `extensions_test.exs:393` and
`capabilities_test.exs:28` are `ET-CC`, `meta_test.exs:29` is `ET-OUT`; the fourth,
`:75`, was moved back. The table below records **what ruling E decided in round 2**,
not what the delivered labels are — §3 and the register are the current statement.
(Raised by CODE_REVIEWER at round 5 as F13's shape one section along, ruled in by the
PM at `26080`.)

The ruling and its reconciliation with §11.1 are in §5. **Gate 2 passes for all six;
gate 3 was applied per row and the outcome reported.**

| row | gate 3 | anchor, or why none | result |
| --- | --- | --- | --- |
| `extensions_test.exs:35` — `from_meta/1 (9)` doctest | **passes** | `schema.ts:98`, `:785` | `ET-CC` **unchanged**, now for a reason that generalises |
| `extensions_test.exs:393` — `%{}` for nil / absent key / absent field | **passes** | `schema.ts:98`, `:95-96` (*"an empty object means the client supports no optional capabilities"*), `:785` (`extensions?:`) | `ET-OUT` → **`ET-CC`**, `falsifiable: undetermined` |
| `capabilities_test.exs:28` — `ServerCapabilities.from_map(%{})` all nil | **passes** | `schema.ts:799`+`:808` (*"Present if the server supports sending log messages"*), `:810`+`:815`, `:825`, `:846`, `:865` — absence **means** unsupported | `ET-OUT` → **`ET-CC`**, `falsifiable: undetermined` |
| `capabilities_test.exs:79` — `ClientCapabilities.from_map(%{})` all nil | **passes** | `schema.ts:95-96` states it in words | `ET-OUT` → **`ET-CC`**, `falsifiable: undetermined` |
| `extensions_test.exs:414` — `%{}` when the shape is **wrong** | **FAILS** | the four shapes asserted are states `schema.ts:785` **forbids**, and no 2026-07-28 line requires a particular recovery from a peer that violates it | `ET-OUT` **unchanged**, excluding gate **2 → 3** (§5 way (ii)) |
| `meta_test.exs:29` — absent `_meta` yields an empty struct | **FAILS** | `schema.ts:179-181` types `RequestParams._meta` as `_meta: RequestMetaObject;` with **no `?`** — an absent `_meta` is forbidden, not an optional field's admissible absence | `ET-ADJ` → **`ET-OUT`**, gate 3 |

**`meta_test.exs:29` changes label as well as gate, and the reason is structural:**
§5's `ET-ADJ` positive test requires **failing gate 2**. Once ruling E makes gate 2
pass, `ET-ADJ` is unreachable whatever the call site, and §5 way (ii) gives
`ET-OUT`. Its call site `dispatch.ex:163` (→ `:165` → the `-32022` reply at `:167`)
is still recorded in the row's evidence for B2b, but it no longer earns the label.

**The two gate-3 failures are the ruling's own guard working.** The PM wrote *"gate
2 passing does not make them members — each still faces gate 3 alone, and gate 3 is
yours to apply. Report the outcome per row; do not assume `ET-CC`."* Two of six do
not survive it.

---

## §8 AC6 — the 7/5 split, settled from the ET side

`oc-axes-2026-07-28.json` carries `provisional_pending: "B2a"` and the claim:

> A3's partial-axis ruling moves **at most 7** of the 12, not 12. The other **5**
> move the OTHER way — into bucket 2, "write the test", not "extend the assertion".

The OC side was measured on MES-68. **The ET side is measured here**, per check,
against the register's `ET-CC` members only — a non-member is not an ET claim.

### The decisive measurement

**The string `404` does not occur anywhere under `test/mcp/`** — `grep -rn "404" test/mcp/`
returns **0** lines. So the `http_status` axis of all **six** `method-not-found-404`
checks is **SILENT** on the ET side, by exhaustive search rather than by sampling.

*(Round 1 stated this grep as `grep -rc "404" test/mcp/**/*.exs`. That form depends
on the shell's `globstar` and does not recurse without it; the recursive `-rn` form
above is what was actually run, and it is the form stated here so a reader can run
the sentence. The result is the same: zero.)*

And the HTTP status assertions in the tree are enumerable — `grep -rn "\.status ==" test/mcp/`
returns **27**, of which only **four** assert a 400: `self_compatibility_test.exs:126`,
`:136` and `:163` (all `Mcp-Name` mismatch, each also asserting `-32020`), plus
`streamable_http_stateless_test.exs:292` (a parse error, `-32700`, not one of the 13).
**No 400 is asserted for a missing `_meta`, an unsupported version, or a missing
capability.**

**F4 — that grep UNDER-COUNTS by construction, and the limit is stated here rather
than left implicit.** Found by CODE_REVIEWER (`26045`) in answer to a request to
sweep for checks that can only fail toward their own conclusion; folded into round 3
per `26048` item 7. Requiring the dot misses a status bound to a bare variable, and
there is one: `subscriptions_stream_test.exs:873` asserts `status == 200`, bound at
`:853` by `{status, response_body} = post_until_closed(port, body)`. So the true
count is **at least 28**, and the miss is **directional** — under-counting always
returns the reassuring *"no ET coverage here"*. Reproduced at this tip: the dotted
grep returns 27, and `grep -rn "status ==" test/mcp/ | grep -v "\.status =="` returns
exactly that one line.

**Why the decisive half survives it anyway, which is the part worth stating.** The
verdicts above turn on 404s and on four 400s. `grep -rn "404" test/mcp/` returns
**0** for the literal **anywhere in the tree, comments included** — so a 404 cannot
be asserted through a variable without the literal appearing somewhere, and the
variable-binding blind spot cannot hide one. The 400 half is a positive claim about
four named lines, which a grep that under-counts cannot inflate. **No cell moves.**

*(**Corrected in round 2**, per PM item 4. Round 1 said 28; the stated command
returns **27** at the PM's seat and at this one. The four 400s and the zero 404s
reproduce exactly, so the argument and every verdict below are untouched — this is
this ticket's own S7-12 shape landing on its own new text, and unlike §11's examples
this section is not ratified, so it is simply corrected rather than left as errata.)*

### Per check

| # | OC check | axes | ET coverage | lands in |
| --- | --- | --- | --- | --- |
| 1-3 | `meta-invalid-400` ×3 (missing-meta / -protocol-version / -client-capabilities) | status 400 | **none** — `-32022` is asserted (`streamable_http_stateless_test.exs:84`) but no status | **bucket 2** |
| 4 | `unsupported-version-400` | status 400 | **none** | **bucket 2** |
| 5 | `missing-capability-http-400` | status 400 | **none** — `-32021` appears only as a bare constant (`error_test.exs:15`, `ET-ADJ`) | **bucket 2** |
| 6 | `header-mismatch-400` | status 400 **+** code `-32020` | **BOTH** (`self_compatibility_test.exs:116`, `:128`, `:155`) | **FULL, not partial** — see the caveat below |
| 7 | `mnf-404-initialize` | status 404 + code `-32601` | status silent; code **CONTRADICTS** (we answer `-32022`, `dispatch_test.exs:84`) | partial-with-contradiction |
| 8 | `mnf-404-ping` | status 404 + code `-32601` | status silent; code **agrees** (`streamable_http_stateless_test.exs:90`) | **partial** |
| 9 | `mnf-404-logging-setlevel` | status 404 + code `-32601` | status silent; code **agrees** (`:86`) | **partial** |
| 10 | `mnf-404-resources-subscribe` | status 404 + code `-32601` | **neither** — the only ET claims are absence-of-constants (`methods_test.exs:21`, `resources_test.exs:85`), both `ET-OUT` | **bucket 2** |
| 11 | `mnf-404-resources-unsubscribe` | as above | **neither** | **bucket 2** |
| 12 | `mnf-404` (generic) | status 404 + code `-32601` | code **agrees** (`subscriptions_stream_test.exs:1029`); status **CONTRADICTS** (we answer 200, `:1010`) | partial-with-contradiction |
| 13 | `sep-2106-no-network-ref-deref` (client leg, AC3's example) | canary counter stays 0 | **covered** — `client_conformance_test.exs:131` asserts `Agent.get(hits, & &1) == 0` | **FULL** |

**Caveat on #6, stated rather than resolved.** The axes file's `requires` gloss
says *"HTTP 400 on a header/`_meta` **VERSION** mismatch"*, while the check's own
description and predicate are generic (*"If the values do not match…"*,
`T.status!==400||E?.error?.code!==-32020`). Our ET claim is about an **`Mcp-Name`**
mismatch. Whether that covers the check is a **match-relation** question and
therefore C1's, not B2a's. **It does not affect the verdict**: read on the
predicate, #6 is a FULL match; read on the gloss, it is bucket 2. Either way it is
**never a partial**, which is what the claim under test asserts.

### Verdict, against the refutation shapes declared before the run

The plan declared, before sweeping: *both axes covered on a two-axis check is a
FULL match not a partial; neither covered is bucket 2; a single-axis check where we
do assert the status is a full match, which would refute the 5.* The first two
fired.

* **"At most 7 of the 12" — HOLDS, and is loose.** It is an upper bound, and the
  measured partial count is **2** (checks 8 and 9), or **4** if the two
  contradicting cases are counted as partial coverage. Nowhere near 7.
* **"The other 5 move into bucket 2" — CONFIRMED for those 5, REFUTED as
  exhaustive.** All five single-axis checks do land in bucket 2, for exactly the
  reason the file gives (covering zero of one axis is no match, not a partial one).
  But **checks 10 and 11 land there too**, so bucket 2 takes **7** of the 12 on the
  predicate reading and **8** on the gloss reading — not 5.
* **Check 6 is the one that could not be partial either way**, and check 7 is
  HAZARD 2's own example landing exactly where the hazard says it must: a member
  whose assertion **contradicts** the official suite is still a member, and
  excluding it would empty bucket 4a by construction.

`provisional_pending: "B2a"` is discharged. The correction to the epic body is the
PM's.

### Re-run against the ROUND-4 register — **no cell moved, and the live risk this time was the other direction**

Round 4 moves 14 rows, and **9 of them move INTO `ET-CC`** — so unlike round 3 the
risk is not a cited unit losing its label but a cell recorded as *"none"* silently
acquiring coverage. It was re-run, not assumed (PM `26059` item 8).

**The 14 rows leave four files** — `types/tool_test.exs` (4 in),
`types/content_test.exs` (4 in, 2 out), `types/resource_test.exs` (1 in) and
`protocol/capabilities_test.exs` (3 out). **§8 cites a unit in none of the four**, and
the intersection with the eight files it does cite is empty:

    files touched by round 4 ∩ files §8 cites  ->  {}   (computed from the register's own rows)

And the returning rows cannot supply an axis, checked literally rather than argued:

    grep -rn "404\|\.status ==\|status ==" \
      test/mcp/protocol/types/tool_test.exs \
      test/mcp/protocol/types/resource_test.exs \
      test/mcp/protocol/types/content_test.exs \
      test/mcp/protocol/capabilities_test.exs        ->  rc=1, no match

The two decisive greps also reproduce at the round-4 tip: `grep -rn "404" test/mcp/`
returns **0**, `grep -rn "\.status ==" test/mcp/` returns **27**, and the one
bare-variable status assertion F4 named is still
`subscriptions_stream_test.exs:873`. **All 13 cells stand.**

### Re-run against the ROUND-5 register — **no cell moved, and no cell could have**

Round 5 moved **no label**: the diff against the round-4 register is exactly four
rows' `boundary` and `evidence` and nothing else (`et_cc_by_boundary` follows from the
first). Every unit §8 cites therefore keeps the label it was cited with, and that was
re-derived from the delivered register rather than inferred — `dispatch_test.exs:82`
`ET-CC`, `streamable_http_stateless_test.exs:82`/`:83` `ET-CC`,
`self_compatibility_test.exs:116`/`:128`/`:155` `ET-CC`, `error_test.exs:15` `ET-ADJ`,
`methods_test.exs:21` and `messages/resources_test.exs:85` `ET-OUT`.

The three decisive greps reproduce at this tip: `grep -rn "404" test/mcp/` returns
**0**, `grep -rn "\.status ==" test/mcp/` returns **27**, and F4's one bare-variable
status assertion is still `subscriptions_stream_test.exs:873`. **All 13 cells stand.**

### Re-run against the ROUND-3 register — **no cell moved, and it was re-run not assumed**

Ruling A's total sweep moved 30 further rows out of `ET-CC`, so AC6 was queried again
against the delivered register rather than carried from round 2. **The 30 rows leave
five files — `types/tool_test.exs` (9), `types/content_test.exs` (8),
`messages/resources_test.exs` (5), `messages/sampling_test.exs` (4),
`types/resource_test.exs` (4) — and §8 cites a unit in none of them.** Every cell's
cited unit re-checked at the round-3 tip:

| cited as | unit | round-3 label |
| --- | --- | --- |
| coverage | `streamable_http_stateless_test.exs:82`, `:83` | `ET-CC` |
| coverage | `self_compatibility_test.exs:116`, `:128`, `:155` | `ET-CC` |
| coverage | `dispatch_test.exs:82` | `ET-CC` |
| coverage | `subscriptions_stream_test.exs:1008` | `ET-CC` |
| coverage | `client_conformance_test.exs:116` | `ET-CC` |
| **non**-coverage | `error_test.exs:15` | `ET-ADJ` |
| **non**-coverage | `methods_test.exs:21`, `resources_test.exs:85` | `ET-OUT` |

`resources_test.exs:85` is the one to look at twice, since ruling A moved five rows
out of that very file — but the five are `:7`, `:21`, `:33`, `:51` and `:67`, and
`:85` was already `ET-OUT` before this round and still is. **All 13 cells stand.**

### Re-run against the ROUND-2 register — **no cell moved**

AC6 is scoped to `ET-CC` members, so 48 rows changing label could in principle move
a cell. It was re-run rather than assumed (PM item 6: *"an expectation is not a
result"*). **Every one of the 13 cells is unchanged.** Checked both directions:

**Nothing left.** Every unit this table cites as coverage is still `ET-CC` at round
2 — `streamable_http_stateless_test.exs:82`(→`:80`), `self_compatibility_test.exs:116`,
`:128`, `:155`, `dispatch_test.exs:82`(→`:83`), `streamable_http_stateless_test.exs:88`
(→`:85`,`:86`), `subscriptions_stream_test.exs:1008`(→`:1010`,`:1011`),
`client_conformance_test.exs:116`(→`:130`) — and the two units cited as evidence of
**non**-coverage are still non-members: `error_test.exs:15` `ET-ADJ`,
`methods_test.exs:21` and `resources_test.exs:85` `ET-OUT`. None of the three files
ruling A moved (`tools_test.exs`, `protocol_test.exs`, `error_test.exs:84`/`:94`) is
cited by any cell.

**Nothing arrived.** The **7** rows that became `ET-CC` in round 2 assert no HTTP
status and no `-32601`: the three `client_test.exs` rows assert the `server/discover`
method name, and the `meta_test`/`extensions_test`/`capabilities_test` rows assert
decoded `_meta` and capability values. *(**F5, corrected in round 3.** Round 2 said
**10** here. Rulings C + D + E moved 3 + 1 + 3 = **7** rows INTO `ET-CC`, which is
what §3's own table says and what the register returns when queried; **10** is how
many rows C, D and E were **put over**. Found by CODE_REVIEWER at `26045`; the
enumeration that follows the number was already the right 7, so no verdict moves.)* The nearest miss is worth naming —
`meta_test.exs:47` is now an `ET-CC` member **about an unsupported protocol
version**, which is check #4's subject — but check #4's single axis is
`http_status: 400` and that row asserts no status, so #4 stays **bucket 2**. And the
decisive fact is a property of the tree, not of the labelling: `404` still occurs
**0** times under `test/mcp/`.

---

## §9 Out of scope — the 413, enumerated rather than omitted

`test/conformance/` fails **gate 1**, which yields `OUT-OF-SCOPE` — **not one of the
four labels** (§1). The register carries all **413** in a separate `out_of_scope`
array, one row each (`key`, `file`, `label`, `gate`), so a later reader can tell
*"excluded by rule"* from *"never looked at"* — the S6-9 shape — and so the two
arrays' key sets together equal the artefact's, checkable both ways (§4).

**And the mirror image, which gate 1 does not catch.**
`test/mcp/conformance_request_state_test.exs` is **12 in-scope units testing the
conformance server FIXTURE's `requestState` token** (`conformance/request_state.ex`).
Gate 1 scopes on **location**, so they are in the 579 and are excluded at gate 2 or
3 instead. All 12 are `ET-OUT`, and `ET-ADJ` is unreachable by construction: §5
requires a call site that is a `file:line` in **`lib/`**, and `grep -rn
"RequestState" lib/` returns nothing. One of them (`:48`, token url-safety) reaches
gate **3** and dies there on the schema's own words — `schema.ts:591-592`, *"The
client must treat this as an **opaque blob**; it must not interpret it in any
way"*. A requirement that a value is opaque is precisely a requirement that its
format is ungoverned.

---

## §10 Spec anchors, and the checksums that keep them verifiable

Every `ET-CC` row carries a `spec_anchor` — a `file:line` at the pinned commit
`5f5440bb26a62e2cf3440b92da5a667efa03b267`, or a SEP number — and the generator
refuses to write a member without one (§1). Eight spec files are cited across the
**281** members; **their md5s are in the register's own `provenance.spec_files` block**,
not merely in a close-out, so an anchor stays verifiable by anyone who re-fetches
the spec. `/tmp` is ephemeral and this project has already been bitten by evidence
that lived only in a run tree.

| md5 | file | anchors |
| --- | --- | ---: |
| `48a009165e07f6732e38baf91291de87` | `schema/2026-07-28/schema.ts` | **194** |
| `63f792fddd2a9d81026ebafe6930ff87` | `basic/transports/streamable-http.mdx` | 81 |
| `f01270882fe8e2d0c2632c19ab8242ba` | `basic/patterns/subscriptions.mdx` | 12 |
| `6b2476585e9e10e1b4c3706a832f5fb5` | `basic/versioning.mdx` | 11 |
| `c302125aae381e9be1feb96305341d4b` | `server/tools.mdx` | 10 |
| `b50a3e1ca27476c1da2b920a10e4b076` | `basic/transports/stdio.mdx` | 5 |
| `5ced9bc596491383397e0637242b746e` | `changelog.mdx` | 4 |
| `1b680a56e96533ff28f6eac07bd51bdc` | `basic/index.mdx` | 2 |

**One figure in this table was stale and is corrected here, found by re-deriving all
eight rather than by carrying them.** The `schema.ts` count read **220**, which is the
**round-2** figure (307 members). Round 3 moved 30 members out and the count should
have gone to **190**; it was never re-derived. Round 4's is **194**. The other seven
rows were unchanged between rounds 2 and 3 and are unchanged now, which is why only
this one drifted — and is exactly why re-deriving the whole column is the check, not
re-checking the ones that look likely. Same shape as S7-12. All eight are recomputed
from the delivered register's own rows:

    jq -r '[.rows[] | select(.label=="ET-CC") | .spec_anchor]
           | map(select(contains("schema/2026-07-28/schema.ts"))) | length' \
      docs/conformance/etcc-register.json                                        # 194

    mix run conformance/controls/etcc_register_controls.exs spec <dir>   # re-md5 and diff

**Three of the eight corroborate independently.** `schema.ts` matches the pin
recorded at `docs/sprint_4_issues.md:1288-1289`; `server/tools.mdx` matches the md5
`test/mcp/server/tool_order_test.exs:8` records for itself; and
`streamable-http.mdx` matches the value `etcc-membership.md` §B.2 states while
recording that it **has no md5 anywhere in this repository**. **That stated limit is
now closed** — a bound another ticket declared and could not close, closed by the
ticket that needed it.

---

## §11 What this register does NOT do

* **It does not judge whether an assertion is CORRECT.** Gates 1–3 ask about scope,
  subject and referent; none asks whether a claim is right. A test that asserts wire
  behaviour and **contradicts the official suite is still a member** —
  `dispatch_test.exs:82` (`initialize` → `-32022`, against
  `sep-2575-http-server-method-not-found-404-initialize`) is `ET-CC` here, and
  excluding it would empty bucket 4a by construction. No correctness test was added
  by this sweep.
* **It records no official-suite mapping per member.** That relation is A3's and the
  crosswalk is C1's, computed once (§8 is the one place this file touches it, and
  only to settle a figure A3 marked `provisional_pending: "B2a"`).
* **It does not validate its own labels.** The generator checks **form and
  completeness** — it would have caught none of A2's own defects, since a wrong
  whole-file label satisfies every one of these assertions. The part with real
  value is an **INDEPENDENT** checker written by another seat against the committed
  register, and that is precisely the part this ticket cannot supply. It is MES-85.
* **It is a reading of one tree at one tip.** `provenance` records the content
  hashes that make that reading checkable; detecting drift between the register and
  a later suite is **MES-84's**.
* **It does not establish that a live boundary is REACHED, only that `lib/` CAN put
  its bytes on the wire.** L2 answers ruling A's antecedent as ruled; whether any
  real caller path arrives there is a different question, ruled out of scope at
  `26057`/`26060` and left alone until an answer turns on it.
* **The boundary partition is a MEASURED fact about `lib/`, and it goes stale when
  `lib/` moves.** Nothing here detects that; MES-88 owns the re-runnable sweep, and
  round 4 adds one clause to its scope — **L2's trigger is mechanical**, so a re-run
  that only re-runs L1 reintroduces the defect L2 exists to prevent.
* **It does not amend `etcc-membership.md`, and round 2 did not either.** The three
  ambiguities the adjudications surfaced — §2's *"that produces one"*, §6's
  helper-inheritance consequence, and §11.1-vs-a-later-tie-break — are recorded as
  Part A **amendment candidates** in `docs/sprint_7_issues.md` S7-14, not applied
  here. Neither are §11's two non-reproducing sub-figures (S7-12): correcting the
  working of a ratified worked example is still editing a ratified document.
