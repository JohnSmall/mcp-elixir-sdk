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

---

## S9-4 — A mechanical re-addresser moved the EXPLICIT citations and left the bare ones, so one document carried two numberings at once

**Found:** MES-94, 2026-09-20, by CODE_CREATOR, at the plan hop and again in execution.
**Fixed here** — the form is gone from `etcc-register.md` and guard 29 stops it coming
back.

**The defect.** `S8-2` recorded that MES-84's `@tag :etcc` inserts broke line citations
in `docs/conformance/etcc-register.md`. The mechanism is sharper than that, and it is
the transferable part. MES-84 **did** re-address citations — 738 of them across ten
files, its own commit message says so — but only the ones written in full,
`file.exs:NN`. The **bare `:NN` continuations** were left at MES-81's numbering, because
a bare `:NN` has no file in it and therefore nothing for a resolver to key on. From that
commit the document carried **two numberings simultaneously, sometimes inside one
sentence**: F15's own correction note gave `capabilities_test.exs:31` (post-insert)
beside a bare `:29` (pre-insert), meaning the same line.

**Measured, not inferred.** 289 citations in the file: 148 explicit, 141 bare. Of the
110 in-tree bare continuations, **55** resolve to a `test`/`doctest` declaration only at
`85d50fa`, and land on a blank line, an `@tag :etcc` or a stray `end` at the commit that
last touched their own prose line.

**Why the form cannot be fixed, only removed.** A bare `:NN` takes its file from the
sentence, not from the notation — and the sentence's referent is not syntactic. At
`etcc-register.md` the trailing `:7` of a three-column table row means the file in
**column 1**, not the nearer one in column 2. In the `tool_test.exs:86` paragraph the
bare `:29` means a **test file** while the nearest file named on its own line is
`tool.ex`, a `lib/` file where line 29 is not a unit at all. **A first mechanical pass at
re-keying this ticket bound that one to the wrong file** — to `capabilities_test.exs`,
which the *preceding* paragraph last named — and it was caught by reading, not by the
scanner. Both the defect and the near-miss are the same fact: *nearest-file binding is
unsound, and its failures are silent.*

**The rule.** Cite the **stable key**, never the line: `{module, test name}` for a unit,
`Module.fun/arity` for `lib/`, a `§` for a section of the same document. A key is
self-contained, so it cannot be mis-bound by its neighbours, and it does not move when
the file does. Enforced by **guard 29** (`MCP.Conformance.Citations`, gate 5).

---

## S9-5 — A self-citation by line is stale on arrival: the edit that writes it moves the lines it names

**Found:** MES-94, 2026-09-20, by CODE_CREATOR. **Fixed here** — the five are now named
by section.

**The defect.** MES-87's S8-1 correction note in `etcc-register.md` §2 says the document
said `413` *"in five places"* and gives them as `:197`, `:214`, `:425`, `:1411`,
`:1414` — line numbers **into the same file the note is being written into**. Three of
the five were **already wrong at the commit that wrote them**. `git show
7e935c2:docs/conformance/etcc-register.md` puts a blank line at `:425` and unrelated
prose at `:1411` and `:1414`; those are the line numbers of the parent tree `616dd2b`,
and MES-87's own 23-line insertion above §2 had already shifted everything below it.

**The mechanism, and why it is worse than S8-2.** S8-2 is *a later commit invalidates a
citation*, which at least has a window in which the citation is true. A self-citation by
line has **no such window**: the commit that introduces it is the commit that invalidates
it. Nothing can be measured to make it right, because the measurement and the edit are
the same act. Reviewers do not catch it because at review time the note reads exactly
like a note that was checked.

**The rule.** **Never cite your own document by line.** Name the section, the heading, or
the sentence. This holds even for an append-only file, because an insert anywhere above
the cited line is enough.

---

## S9-6 — Two adjacent units, one character apart as line numbers, were merged into one clause by a correction note

**Found:** MES-94, 2026-09-20, by CODE_CREATOR, **while re-keying the sentence** — not
by looking for it. **Fixed here** (`F16` in `etcc-register.md` §6a).

**The defect.** Round 6's F15 note explains a wrong table cell by saying the erroneous
address was *"an assertion inside the unit declared at `:7`, which is the co-reddened
unit"*. Those are two different units. `assert caps.tools == nil` sits inside
`MCP.Protocol.CapabilitiesTest/test ServerCapabilities from_map/1 handles missing
capabilities` — the **next** declaration down — while the co-reddened unit is
`… from_map/1 parses full capabilities`. The corrected cell names the right one, so no
verdict, label or count moves; what was wrong was the sentence explaining it.

**The mechanism.** Under line addresses the two units are `:7` and `:26` in a list of
thirteen two-digit numbers. Nothing in that notation carries what the units **are**, so
an author holding both in mind can write one and mean the other and re-read it without
noticing. Under keys they are visibly *parses full capabilities* and *handles missing
capabilities*, and the merge could not have been written down.

**The transferable part.** *Re-keying is not cosmetic.* A notation that carries the
subject makes a class of error unwriteable; a notation that carries only an address makes
that class invisible. This one survived a correction note whose whole purpose was to
re-examine that address.

---

## S9-7 — Renumbering a citation is not merely fragile, it is ambiguous: the same token meant two different tests in adjacent table rows

**Found:** MES-94, 2026-09-20, by CODE_CREATOR, at the plan hop. **Not applicable after
this ticket** — the form is gone — but recorded because it is the argument against the
obvious remedy.

**The defect.** The tempting fix for a stale line citation is to renumber it. In
`etcc-register.md` §7 family C that produces a collision. The table lists 14
already-`ET-CC` units under MES-81's numbering, one of which is `:373`. `:373` is **also**
the post-MES-84 line of `MCP.ClientTest/test lifecycle notifies pending requests when the
transport closes` — one of the three units in the row **immediately below**. Renumber
only the three and one token means two different tests in adjacent rows of one table,
with nothing to say which numbering each row is in.

**The mechanism.** A line number is an address in a coordinate system that is not
recorded anywhere. Two rows of the same table can sit in different coordinate systems and
look identical. Re-keying removes the coordinate system; renumbering just moves everything
into a new one that will itself expire at the next insert.

---

## S9-8 — An enumeration of call sites was carrying no weight its enumeration of units did not

**Found:** MES-94, 2026-09-20, by CODE_CREATOR. **Retired here.**

**The defect.** `etcc-register.md` §7 family C established *"exactly three and nothing
else"* by listing **17 `do_connect/2` call-site lines** and then **17 enclosing
declaration lines** — 34 line numbers, all pre-MES-84. The declarations re-key cleanly.
The call sites are lines **inside test bodies** and have no stable key at all: ExUnit
names units, not statements.

**The mechanism, and the rule.** The claim being established was *"17 call sites, one per
listed unit"*. Once the units are enumerated, the call-site list adds nothing — it was
the *same* seventeen facts written in a notation that cannot be checked. **An enumeration
whose elements have no key should be replaced by one whose elements do, not re-resolved.**
Where prose genuinely needs to point inside a body, the form is the enclosing unit's key
plus the expression quoted verbatim; the expression is what the sentence was pointing at
anyway.

---

## S9-9 — A frozen provenance table disclosed its own staleness 45 lines away from the table

**Found:** MES-94, 2026-09-20, by CODE_CREATOR. **Answered here** with one adjacent
pointer, on the PM's D1 ruling.

**The defect.** MES-93 correctly froze `etcc-register.md` §6's six worked cases as a
provenance record and disclosed, in a superseding note at the **head of §6**, that their
line addresses had drifted and that one now reads a different real test. The disclosure
is complete and correct. It is also **45 lines above the table**, and a reader who
deep-links or scrolls to the table sees six stale addresses with nothing beside them
saying so.

**The mechanism.** A freeze and a disclosure are different obligations and they want
different placements. The freeze belongs to the whole section; the disclosure belongs
**where the frozen bytes are read**. Putting both at the head satisfies the first and
quietly fails the second, because nothing makes a reader arrive at the head first.

**The rule.** *Mark the artefact, not only the section.* A frozen block keeps its bytes
and gains an adjacent, clearly separated note — a blockquote above the table, never an
edit inside it — pointing at the superseding text. That is what was added here: MES-81's
six rows are byte-identical and the pointer sits immediately above them.

---

## S9-10 — 40 citations point outside this tree, so neither the defect nor its guard applies to them, and saying so is the deliverable

**Found:** MES-94, 2026-09-20, by CODE_CREATOR, at the plan hop. **Ruled out of scope by
the PM (D2) and stated in the document.**

**The defect that is not one.** `etcc-register.md` carries 40 `schema.ts` and
`changelog.mdx` citations into the pinned `2026-07-28` spec. An acceptance criterion
reading *"no bare-line citation resolves to the wrong test or a blank line"* is **total on
its face** and would sweep them in.

**Why they are different in kind.** Those files are not in this tree. **No commit of ours
moves them**, so the S8-2 failure mode cannot arise; and no guard here can verify them
without vendoring the spec, so a guard that claimed to cover them would be claiming a
bound that does not hold (`AC7`). The compensating control that does exist is `§10`'s
**md5 per spec file**, recorded in the register's own `provenance.spec_files`: an anchor
stays checkable against the pin even though its line is not checkable here.

**The rule.** When an AC's wording is total and a subset of the population is out of its
reach, **get the boundary ruled and write it into the artefact**, next to the form it
excepts. A silently-excluded subset and a forgotten one read identically. `§0.1`'s table
names the exception in the same table that states the rule, and guard 29's
`line_citations/1` excludes spec anchors in code, so the exception is executable rather
than remembered.

---

## S9-11 — §1's three "delivered figures" have been stale since MES-84, in the block whose own text says a stale hash would be the defect

**Found:** MES-94, 2026-09-20, by CODE_CREATOR, while reading `etcc-register.md` for
citations. **NOT fixed here** — out of this ticket's scope, which is citations. Raised so
it is on the board rather than in a close-out.

**The defect.** `etcc-register.md` §1 prints a block headed *"ROUND 6, the delivered
figures"* with three content hashes. All three were correct at `85d50fa` and all three
moved at `18df3a6`:

| figure | prose says | at the delivered tip |
| --- | --- | --- |
| artefact `rows_md5` | `05f7b2d2b5a6948981d67d331cb40a5f` | `dbc5673f3dca98b7e51de85ce90801f6` |
| `decisions md5` | `d6d463b391f2c13ff232913f81613b97` | `4548ad291a551f4aea75c6539cd5efdf` |
| `register md5` | `cc9504f8e483170bceda2a6c3d84830b` | `dde16982330c5d3f04b5b137969b0a67` |

§2's transcript block carries the same `05f7b2d2…` with the claim *"== the committed
artefact's"*, which is now false.

**Why it matters more than an ordinary stale figure.** These hashes are `§1`'s stated
**provenance mechanism** — the thing `etcc-row-key.md` §5.2 tells a later reader to verify
against, *because* a recorded tip stops resolving after the squash-merge. And the
paragraph beneath them says, in terms: *"A round that moved a label and left these hashes
standing would be the defect."* Three rounds of regeneration later, they are standing.

**The mechanism.** It is `S8-1` and `S9-1` exactly — a figure transcribed out of a derived
artefact goes stale the moment the artefact is regenerated — landing on the block whose
purpose is to make regeneration detectable. MES-87 corrected the `413`→`428` **count**
instance of this in the same document and did not re-derive the **hashes**, because the
Q1 ruling it worked to named the count. *A correction scoped to the instance that was
noticed leaves the others.*

**What would catch it:** the same shape as guard 29 and MES-102 — a guard that re-derives
each hash printed in the prose from the artefact it names and refuses a mismatch. Worth a
ticket alongside MES-102, which is already building the prose-vs-artefact guard for
labels.

---

## S9-12 — A correction that says "corrected in the three rows that state it" cannot be checked, and it missed a fourth

**Found:** MES-94, 2026-09-20, by CODE_CREATOR. **NOT fixed here** — a pointer was added
in place, MES-81's sentence left standing, on the §6/S8-1 precedent.

**The defect.** `etcc-register.md` §7 family A's F2 note corrects a reddened-unit count
from **21** to **18** and closes *"Corrected in the three rows that state it as well as
here."* Family C, two sections later, still reads *"every one of the 21 reddened
`ClientTest` units failed on exactly that assertion."*

**The mechanism.** *"The three rows that state it"* is a claim about a population the
note does not enumerate and nothing can re-derive: there is no key on which "places that
state this figure" is a queryable set. So the correction is unfalsifiable at the moment
it is written and uncheckable afterwards. The same sentence would have read the same way
if it had found two, or five.

**The rule.** A correction must **enumerate its sites**, by an address a later reader can
re-resolve — a section, a key, a quoted sentence — or state the predicate it swept with so
the sweep can be re-run. *"Corrected everywhere it appears"* is a promise, not a result;
`S8-1`'s note did it the right way by listing the five places, and `S9-5` is the separate
defect of having listed them by line.

---

## S9-13 — An exception list keyed on the offending STRING grandfathers the string, not the occurrence, so the exception re-admits the thing it excepts

**Found:** MES-94, 2026-09-20, by CODE_REVIEWER, in review of MES-94's own guard, before
it merged. **Fixed here**, in the same ticket.

**The defect.** Guard 29's limb B is the ratchet that stops the bare-line citation form
returning after MES-94 converted the document to row keys. As first delivered, its
allow-list was keyed on the citation **text** alone — the 38 surviving strings — and the
decision was *"is this string one of the 38?"*. CODE_REVIEWER appended a synthetic
**live** citation to the document using each of three grandfathered strings and ran the
guard: all three returned `ok?: true`, `unpermitted 0`. A new bare line citation could
therefore be written anywhere in the document, indefinitely, provided it borrowed its
digits from a historical one — which is exactly the erosion limb B exists to prevent.

**The mechanism, and it generalises past this guard.** An exception list has two
plausible keys and they are not equivalent. Keyed on the **value** that offends, it
says *"this string is allowed"* — a licence that travels with the string, into every
future occurrence of it, including ones nobody has written yet. Keyed on the
**occurrence** — the value **and** where it stands, and how many times — it says *"this
instance is allowed"*, which is what a grandfather clause means. The first reads
naturally, tests green against the population it was built from, and is silently
unbounded: the population it actually permits is *every document that will ever exist*,
not the one that was surveyed. **A guard whose exception list is keyed on the value can
only ratchet against strings that were never used before.**

**Why it survived its own controls.** The guard shipped with two controls, a positive
and a mutation, and both passed. But the mutation perturbed a **row key**, so it
reddened **limb A** — it demonstrated that *a* predicate could fire, and was read as
demonstrating that *the* predicate could. Two limbs are two predicates, and a limb with
no mutation of its own has no evidence at all, however green the file is. *Every limb of
a guard needs its own mutation* — the `S8-3` rule, applied at the granularity of the
limb rather than of the guard.

**The fix.** The allow-list is keyed on the pair *(§ section, citation text)* and valued
with the permitted multiplicity, so the same string in another section is refused as
`UNLISTED` and a fourth occurrence where three are permitted is refused as `OVER-COUNT`,
naming both counts. The anchor is the document's own stable self-address — its `§`
number, the form §0.1 requires of the prose — so **no line number enters the allow-list**
and the exception cannot itself drift. `limb-b` in
`conformance/controls/etcc_citation_controls.exs` is CODE_REVIEWER's probe, committed:
it reproduces both shapes against a throwaway root and requires the unmutated document
to pass in the same invocation.

**What the fix does NOT close, stated rather than left to be found.** The bound is per
section, so **deleting** a grandfathered occurrence and writing a live citation with the
same text into the same section keeps the count and passes. Narrowing that would mean
anchoring an exception to a line, which is the disease this document was re-keyed to
cure.
