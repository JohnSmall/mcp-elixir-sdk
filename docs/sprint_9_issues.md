# Sprint 9 — procedure defects

Procedure defects found while working Sprint 9 (epics MES-65 and MES-96): things
wrong with **how we work** — the gate set, the briefs, the tooling contract.

Ticket substance does not go here. Findings about the MCP SDK itself, about
conformance results, or about a specific ticket's deliverable belong in comments
on that ticket. This file is for defects a *future* sprint would otherwise hit
again.

Each entry states the **mechanism**, because the mechanism is the transferable
part.

---

## S9-1 — A prose worked-example table and the register it describes diverged for a month, and nothing went red

**Found:** MES-93, 2026-09-20, by CODE_CREATOR, while promoting the decode-boundary
tie-break (`26026`) into Part A. **Not fixed here** — the instrument is **MES-102**,
raised by the PM at `27821` (Q5).

**The defect.** `docs/conformance/etcc-register.md` §6 lists six worked cases with
their labels. One of them — `client_test.exs:353`, `MCP.ClientTest` /
`lifecycle times out a pending request` — is recorded there as `ET-OUT`. **PM ruling C
(`26035`) overturned that cell on the same day the tie-break was issued**, 2026-08-23,
and MES-87 made ruling C's reasoning ratified Part A (§6.1) on 2026-09-09. At the
delivered tip the unit is `ET-CC`, `mixed: true`, `inherited_from
test/mcp/client_test.exs:59`. The stale cell sat there for four weeks.

**The mechanism, and it is the transferable part.** A label written in **prose** and the
same label held in a **generated artefact** are two copies of one fact with no relation
between them that anything checks. The generator's guards (`etcc_register.ex`) validate
the artefact against the decisions file; **nothing validates prose against the
artefact.** So a ruling that moves a row updates the artefact and leaves every prose
table that names that row silently wrong. It is S8-1's shape — *a figure transcribed out
of a derived artefact goes stale the moment the artefact is regenerated* — but at the
level of a **label** rather than a count, which is worse: a wrong count looks like a
wrong count, and a wrong label reads as a decision.

**Why it nearly did real damage.** MES-93's job was to promote §6's table into Part A.
Under §9.1(1) *a ratified worked example carries its ratio*, so promoting the table
verbatim would have given a **superseded** result the rank of a rule, contradicting
§6.1 three sections away — the exact S7-15 shape MES-87 was raised to close, committed
by the ticket closing it.

**What caught it** was §C.6's method, applied literally: *re-derive every label from the
delivered register at this tip, never transcribe it from the prose*. Nothing else would
have. The check that would have caught it **mechanically** is a build guard resolving
each prose table's `{module, test name}` keys against `etcc-register.json` and refusing
a label mismatch — guards 21, 22 and 27's shape. That is **MES-102**.

**Interim obligation for anyone citing a label in prose:** re-derive it from
`etcc-register.json` at the tip you are delivering, and say that you did. A transcribed
label is not evidence.

---

## S9-2 — A ratified-provenance enumeration went stale silently, because keeping it current is a manual obligation with no instrument

**Found:** MES-93, 2026-09-20, by CODE_CREATOR. **Corrected here**, on the PM's Q6
ruling (`27821`).

**The defect.** `docs/conformance/etcc-membership.md` §B.4(ii) enumerates the Jira
comment ids that carry ratified criterion text. It read **17** and ended at MES-87's
`26737`. MES-88 then added a ratified Part A element — §2.3(e)'s extension, carrying
`[authored 26988 | ratified 26995]` — and did not add either id. So the enumeration had
been an **undercount since 2026-09-10**: an omission of ratified elements, not a
miscount. Now **21**, and regrouped by ticket.

**The mechanism.** The enumeration is a **derived set** — *the ids cited in Part A* —
maintained by hand. Every amendment must remember to update a section in a different
part of the same file, and **nothing fails if it does not**. MES-87 updated it because
its brief's Q2 asked; MES-88's brief did not ask, and MES-88 did not.

A second-order effect worth naming: MES-87's addendum justified keeping the enumeration
on the grounds that *"the two ratification threads stay distinguishable by prefix —
`25xxx` is MES-67, `26xxx` is MES-87"*. **That property is now false** — `26xxx` spans
MES-87 and MES-88 — so the enumeration was not only incomplete, its stated reason for
being a list rather than a tally had quietly expired. It is grouped by ticket now, which
does not expire.

**The transferable part.** *A derived set maintained by hand is a promise, not a
mechanism.* This one is cheap to mechanise — the ids in Part A are greppable
(`\[authored (\d+) \| ratified (\d+)\]`) and §B.4(ii)'s table is the set they should
equal — and the same argument as S9-1 applies: it belongs with **MES-102**'s guard work,
not in a promotion ticket. Until then, **any ticket adding a Part A element must update
§B.4(ii) in the same commit**, and its brief should say so rather than relying on the
seat noticing.

---

## S9-3 — "Roughly 90 rows" was a round-1 estimate carried forward through three documents as though it were measured

**Found:** MES-93, 2026-09-20, by CODE_CREATOR. **Corrected in the place MES-93 owns**
(`etcc-membership.md` §E.3 and `etcc-register.md` §6's superseding note), on the PM's Q3
ruling (`27820`). **Deliberately not corrected at source.**

**The defect.** The `26026` decode-boundary family is described as *"roughly 90
client-side rows"* in `etcc-register.md` §6, in `etcc-membership.md` §C.5, and in
MES-93's own ticket body. Measured at the delivered tip:

| predicate | measured |
| --- | --- |
| `ET-CC` rows whose recorded `boundary` includes `MCP.Client` | **57** |
| `ET-CC` rows in the five client-side test modules | **59** |
| rows whose `evidence` cites `26026` | **52** |
| rows whose `evidence` cites `client.ex:868` | **37** |

**The mechanism.** The figure was taken in **round 1**, when `ET-CC` stood at **340**;
it is **281** now. Three later rounds of adjudication moved 66 rows out. §6 says in terms
that they came out of *other* families and *"not out of this family"* — and on the
register's own attribution of rows to the `MCP.Client` boundary, that is not what
happened. **Nothing re-measured it, because a round number in prose does not look like a
measurement that could expire.**

**The transferable part, and it is why Part A carries no count at all.** *A criterion
that states a measurement goes stale as soon as the tree moves, and a criterion cannot
be corrected in place — it is ratified text.* So a figure written into Part A would be
permanently wrong and permanently uncorrectable. The promoted §2.5 states the **rule**
and no size. Figures belong in the register and in the working parts, where they can be
re-measured and restated.

**A secondary lesson about the predicate.** *"The client-side family"* has no single
definition, and the four predicates above give four different answers (37, 52, 57, 59) —
all correct, for four different questions. A figure cited without its predicate cannot be
reproduced, and was not.
