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

## S9-14 — "6 of 13 check ids do not occur in the harness at all" is wrong twice, and the true 6 belongs to a different predicate

**Found on MES-97 (C1a), measured against the build at `a10085d0…`.**

The sentence *"states the 6-of-13 check ids that do not occur in the harness build at
all"* appears in **MES-97's ticket body**, in **MES-96**, in **MES-65**, and the PM's
own dispatch restated it. It fuses three different measurements into one figure and is
wrong on two of them:

| predicate | over A3's 13 rows | over the 173 |
| --- | --- | --- |
| the check_id **occurs at all** | **5** rows do not (5 distinct ids) | 8 rows do not |
| a bare grep **reaches the emitting site** | **6** rows do not | 30 rows do not |
| **distinct** check ids | 11, not 13 | 110 |

So the 6 is real and it is *reach-the-site*, not *occur-at-all*; its denominator is
**rows**, not **ids**; and the id count of those 13 rows is 11. Its source says exactly
this and was not misquoted so much as compressed: `oc-axes-2026-07-28.json`
`provenance.reverse_lookup_procedure.direction` reads *"a grep on the check_id reaches
the emitting site for only 7 of the 13 rows"*.

**Independently re-derived rather than re-read.** `mix conformance.locator` implements
the traversal mechanically and its ladder puts 7 of A3's 13 rows on a rung a bare grep
reaches — the same 7, arrived at from the build rather than from the sentence.

**The mechanism.** *A brief restates a figure and loses its predicate.* The restatement
is shorter and reads better, and there is nothing in a number to say which question it
answered. The remedy is not to correct the sentence in four places — the PM ruled
against editing the epic bodies — but to make the artefact print **each number next to
its own predicate**: `oc-emitting-sites-2026-07-28.json` `predicates` has one block per
question, each carrying its own denominator, and it supersedes all four prose sites.

---

## S9-15 — An AC that quantifies over both sides and checks the arithmetic is satisfied perfectly by an empty relation

**Found on MES-97 (C1a), at the plan hop, before the generator was written.**

MES-97's AC3 read: *"every one of the 173 in-scope OC checks appears exactly once as a
match target; every ET-CC member appears; the unmatched-on-each-side sets are
enumerated"*. A crosswalk with **zero edges** satisfies it in every particular: all 173
fall into bucket 2, all 281 into bucket 1, both sets enumerate exactly, and the
arithmetic reconciles to the row. An AC a wrong artefact satisfies is not an AC
(ruling 8).

**The strengthening** (PM-approved as D3): the artefact declares its `population`; A3
§6's state-4 guard runs **over that population**; and bucket 1 and bucket 2 — which are
complements, and a complement is meaningless without a universe — are **refused**
outside it. Emptiness is then what the guard fires on.

**And it did not work the first time, which is the part worth recording.** The
refusal was written into `Crosswalk.project/2` — and the generator computed both
buckets inline and never called it. The `vacuum` control built an empty crosswalk and
it came out **green**, reporting `0 members, 0 checks, bucket 2: CHECKED, AND ZERO`.
The fix was to route both projections through `project/2` and add an explicit
emptiness refusal on the path the generator actually takes.

**The mechanism, and it is not about vacuity.** *A guard on a path the caller does not
take protects nothing.* The function existed, was correct, was unit-tested, and was
dead. Only a control that drove the **whole generator** rather than the function could
show it — which is why the vacuum case is in
`conformance/controls/crosswalk_controls.exs` and not only in
`test/conformance/crosswalk_test.exs`.

---

## S9-16 — The emitting site of a check is not always where its verdict is decided, and MES-76's traversal stops at the emitting site

**Found on MES-97 (C1a).**

`reverse_lookup_procedure` travels `check_id -> emitting site -> predicate -> axes`, and
its second hop assumes the predicate is *at* the site. For
`sep-2575-client-retry-supported-version` it is not. The emitting call writes a
constant:

    this.addOrUpdateCheck({id:`sep-2575-client-retry-supported-version`,…,status:`WARNING`,…})

and the verdict is decided **221 bytes later**, at a site that carries no id literal in
an emitting position at all:

    let p=this.checks.find(e=>e.id===`sep-2575-client-retry-supported-version`);
    if(p&&(o===`2026-07-28`&&a===`2026-07-28`?p.status=`SUCCESS`:p.status=`WARNING`,…

A consumer who follows the locator to the emitting site and stops reads
`` status:`WARNING` `` and finds **no predicate**, from which the available wrong
conclusions are "this check has no axes" and "this check's axis is the literal
WARNING". Both are worse than an admitted gap.

**Recorded, not fixed.** The locator finds emitters, which is what it says it finds;
`oc-axes-c1.json` carries the mutation site as an addressed `context_excerpt` for this
check and states in `emitting_site_is_not_the_predicate` why. How many of the other 172
rows are `addOrUpdateCheck`-plus-mutation is **not measured here** — it is C1b's and
C1c's to find, and is stated as locator residual **L1** rather than left for them to
trip over.

---

## S9-17 — A test named for the behaviour it does not assert: "the retry re-stamps the version" asserts the version on the request BEFORE the retry

**Found on MES-97 (C1a), while decomposing the ET side of the crosswalk.**

`test/mcp/client_defects_test.exs` "D-3 … **the retry re-stamps the version chosen from
`supported`**" asserts the protocol version on `first` — the request sent *before* the
server's rejection — and then asserts only that the call completes. The retry's own
`_meta` version is never asserted.

It cannot fail for the reason its name gives. And the fixture hides it: the client is
started with `protocol_version: "2026-07-28"` and the server offers `["2026-07-28"]`, so
the first request and the retry carry the same version, and asserting the first *looks*
like asserting the re-stamp.

**Its sibling covers the behaviour.** "a -32022 naming a version we support is retried
exactly once" does assert `retry["params"]["_meta"][…protocolVersion]`, so the SDK's
behaviour is tested; what is missing is that *this* test tests it. That is why it is a
finding and not a defect: a **vacuity**, which is D5a/D5b's subject, reached from the
crosswalk rather than from a vacuity sweep.

**Not fixed here** (epic ruling 3: a discrepancy the crosswalk surfaces is recorded and
routed, never fixed). It is visible in the artefact rather than only here: the edge's
`evidence` in `conformance/data/crosswalk-edges.json` says which line the only version
assertion is on, and the edge escalates as `no_axis_contact` rather than being counted
as coverage.

---

## S9-18 — A prefix search that drops segments until it hits will always hit, and the hit it settles for can be 70 KB away

**Found on MES-97 (C1a), building the locator's template rung.**

MES-76's TEMPLATE case says: where the check id does not occur, *"grep instead for the
LONGEST LITERAL PREFIX of the id (drop trailing segments until the grep hits)"*. Run
mechanically over the whole denominator, that rule resolves **ten** rows onto the
prefix **`sep`** — three hits inside the harness CLI's own scaffolding
(`` check:`sep-${e}-todo` ``, a `sep-${n}.yaml` path, an error format string), none of
them a check-emitting site, all of them ~70 KB from the code in question.

The rule is sound as MES-76 used it, because A3 applied it by hand to five rows whose
prefix stopped at a real loop. Automated, its termination condition is *"the grep
returned something"* — and a short enough prefix always returns something. **A search
whose stopping rule is "a hit" cannot fail**; it can only return progressively worse
answers.

**The fix** is a structural test rather than a length floor: a prefix hit counts only
when it sits at an **emitting position** — the first argument of a call, or an `id:`
property followed by `,name:`. With it, the eight genuinely template-built rows resolve
on `sep-2575-request-meta-invalid` and `sep-2575-http-server-method-not-found-404`, and
the ten `x-mcp-header` rows fall through to the lookup-table rung, which is where they
belong. A length floor would have been the wrong fix: it tunes a number against today's
ids instead of asking what a resolution *is*.

**The same shape, one rung up.** An id literal followed by `` ,` `` looks like a call
argument, and in `Ha=[`a`,`b`,`c`]` it is an **array element** — five check ids that
read as five emitting sites. Both are guarded by asking `enclosing/2` what the nearest
unclosed delimiter actually is. Both mutations are committed in
`conformance/controls/crosswalk_controls.exs` (`locator`) and as units in
`test/conformance/locator_test.exs`.

---

## S9-19 — A pin recorded per RUNG when the level is per ROW: the artefact claimed a row-specific address for six rows whose own metadata refuted it

**Found by CODE_REVIEWER on MES-97 (C1a)** — comment 27864 — and corrected under the PM
correction contract at comment 27866. Recorded here rather than only in Jira because the
shape generalises well past this artefact.

The locator's ladder records, per row, which rung resolved it and **what that rung pins**
— the row, the check, or the loop. `rung_pins` was computed as a function of the **rung
alone**. For four of the five rungs that is right. For `id_table_value` it is not: the
rung's site is a loop over the whole table (`for(let[e,t]of Object.entries(Ua))`, emitting
`` `ClientRejectsInvalidTool_${e}` ``), so the site is the same 1162 bytes for every row
the table carries and names none of them. What pins a row is a **second and different
address** — the table entry `` key:`check-id` `` — and only when that entry's key is the
row's own name suffix.

**Six of the ten rows resolved through a sibling's key** and were nonetheless recorded as
row-level pins, resolving to the broad `getChecks()` span `[714697, 715859]` whose
committed bytes do not contain the row's own case suffix. The artefact asserted an
address it did not have, which is ruling 7 read backwards.

**The field that would have caught it was already there.** `row_key_matches` was computed
on every one of those rows, sat in the artefact saying `false`, and **nothing acted on
it** — and the unit at `locator_test.exs:82-89` explicitly asserted the false case was
fine. This is S9-15's lesson arriving from the other side: there, a correct guard sat on a
path the caller never took; here, a correct *measurement* sat in a field no guard ever
read. A computed value that nothing refuses on is a comment with a JSON key.

**The correction.** `Locator.pin_level/2` takes the rung **and its metadata**; the six
read `loop` and the four read `row`. A row-level table pin now carries
`rung_detail.table_entry` — the entry's span **and its bytes** — because the site's bytes
cannot support the claim and an address without its bytes is not evidence. The generator
**refuses** any row claiming `row` while `row_key_matches` is false, and the control
(`crosswalk_controls.exs pins`) proves the refusal by recompiling `pin_level/2` in the VM
to make that exact claim and driving the whole generator, with the unmutated run as the
positive control. Nothing on disk is mutated, so a death mid-run cannot leave the shared
clone dirty (S8-14).

**A second figure fell out of it.** Residual L3 said *"21 rows"* resolve to their check's
or loop's address rather than their own. It was hard-coded, counted two of the four
non-row rungs, and missed `id_bound_variable`'s 12 as well as these six. The true figure
is **39 of 173**, and it is computed from the rows now rather than written down.

**Routed, not fixed** (epic ruling 3). All ten `id_table_value` rows *do* have an entry
keyed by their own name suffix in `Ua` — measured, not assumed. The resolver takes the
**first** occurrence of the id literal, which for an id shared by several rows is a
sibling's entry; selecting the row-keyed entry instead would pin all ten at row level.
That is a better locator and it is not this ticket's to build: the PM ratified
reclassification, and the coarser level is a true statement about what was resolved. It is
recorded as locator residual L5 so C1b/C1c can take it.

---

## S9-20 — A population derived from the file being validated cannot be falsified by dropping a row: three of the brief's four falsification classes built cleanly

**Found:** MES-99 (C3), 2026-09-20, by CODE_CREATOR, **before** planning — by running the
brief's falsification classes against the real generator rather than reasoning about them.
**Fixed here**, in the ticket ruling 5 designed to do exactly this.

**This is not a defect that slipped C1a's merge gate,** and framing it as one would be
wrong: C1a's (MES-97) acceptance criteria never required the generator to refuse a
falsified input. Ruling 5 assigns that to C3, which is precisely why the crosswalk carried
`trust_status: UNFALSIFIED` and why nothing downstream was allowed to build on it. The
transferable finding is the *mechanism*, not a missed gate.

**The mechanism.** Four probes through `mix conformance.crosswalk` at `559eda8`, with only
the edges file swapped (temp copies; nothing written into the repo):

```
A  unmutated (positive control)      built — 21 members, 23 edges, {4a:2, 4b:2, 5:15}
B  an edge duplicated verbatim       BUILT CLEANLY — edges 23->24, bucket 5: 15->16
C  an edge dropped                   BUILT CLEANLY — members 21->20, edges 22, bucket 5: 15->14
D  a declared_unmatched member       BUILT CLEANLY — members 21->20, unmatched 5->4
   dropped
```

One cause behind C and D: `population!/4` derived the declared population by unioning the
`register_key`s of `edges` and `declared_unmatched` — **the very file under validation**.
So a dropped row did not violate the universe, it **shrank** it, and every downstream
reconciliation still held: the edge equation, the member equation, and *both* directions of
`set_compare`. The artefact stayed internally perfect while being about less than it
claimed.

**The general shape, and it has bitten this project before.** *If the universe a totality
check quantifies over is read out of the artefact being checked, the check is vacuous* —
totality holds by construction, and drop and duplicate both pass. It is the same failure as
S9-15 (an AC an empty relation satisfies) with the quantifier moved one level out, and the
remedy is the same: the population must be denoted from an **external anchor**, compared by
**set** in both directions, never by count.

**The one genuine S9-15-shaped observation against C1a.** C1a *did* test the duplicate-key
condition — in `crosswalk_controls.exs keying`, against the committed **output**. A check on
the artefact is not a refusal on the generator's path: it says what *was* built, and is
silent about what *can* be built. That is the seam C3 closes (now G14, on the generator's
path), and the distinction between the two is the part worth carrying forward.

**The correction.** Three new generator refusals, each with its mutation committed:

- **G14** — no two edges may share the `(register_key, claim, tag)` triple the join is keyed
  on, and no member may be declared unmatched twice.
- **G15** — the population must equal the set a machine-readable `selector` denotes, by set
  comparison in **both** directions, *and* must match the four counts the edges file
  declares about itself (which C1a read for their `rule` string and never checked). The
  selector names `docs/conformance/etcc-attribution.json` — B2b's register, **a different
  file** — and the generator refuses a selector that is absent, that names a source this run
  was not given, that uses a test the evaluator does not implement, or whose source carries
  duplicate keys. Counts and sets are kept as *separate* limbs: neither subsumes the other.
- **G16** — A1's manifest and A5's bucket-0 artefact must carry the same 175 keys and the
  same per-check status.

**Two things the fix does not claim.** G15's `extra` direction and C1a's A3 §6 state-4 guard
coincide on *this* data, because the selector's 21 and the attribution register's tagged 21
are the same set; they are different predicates that happen to agree here, and on C1b's and
C1c's populations they need not. And G16 is a **consistency** pin, not a correctness one
(ruling 9): both artefacts descend from the same accepted harness run, so a wrong run is
wrong in both and the pin agrees just as firmly.

**Instrument:** `conformance/controls/crosswalk_falsification_controls.exs`, modes
`refusals | drift | second_source | exit_status | all`. Fifteen refusals, each shown firing
on a mutated input with the unmutated build as the negative control **in the same run**, and
the unmutated build re-run **after** them. Each refusal asserts *which* guard the
generator's message names — without that, fifteen green `refused` lines would pass on a
generator that refused everything for one unrelated reason (S9-18's shape), and the
`wrong_reason` mode is that matcher's own control, driven as a subprocess and required to
exit 1 on a real refusal asserted against the wrong guard — C1a's `guards` mode ran its positive control
only *before* its thirteen, so "restored green" was never established for it; that mode now
re-runs the committed build at the end, and `refusals` drives it as a subprocess so the
whole set of twenty-eight carries an after-restoration.

---

## S9-21 — A partition claim that does not name what it partitions: "every ET-CC member in exactly one bucket" is falsified by a member with three edges

**Found:** MES-98 (C2), 2026-09-20, by CODE_CREATOR, while rendering C1a's crosswalk into
the ten bucket views. **Not fixed here** — the wording is on the subject master page
(276594833) and belongs to the E group (epic ruling 3). Recorded, routed to **E2**, and
carried on the roll-up as residual `C2-R2`.

**The claim.** The master page states E2's target as *"every ET-CC member appears in
exactly one of buckets {1, 3, 4a, 4b, 5a, 5b, 6}"*.

**It is already false on the declared slice.** `MCP.Transport.StreamableHTTPStatelessTest`
(*"initialize is gone → -32022; ping/logging.setLevel → -32601"*) carries **three** edges,
and they land in **4a, 4b and 4b**. One member, two buckets. Four other members carry 2–3
edges each; those happen to land in one bucket apiece, so this is the only witness on this
slice — and "the only witness today" is exactly the state in which a wording gets ratified
and then falsified by the next population.

**The mechanism, which is the transferable part.** The ET-CC × OC relation is
**many-to-many**: one ET-CC member may make several claims, each against a different OC
check, each with its own verdict pair and edge shape. The bucket function is
`f(verdict pair, edge shape)` — a function of an **edge**, not of a member. So the
partition is exact **per edge** and is merely *usually* exact per member. A partition claim
must name the universe it partitions, and "member" and "edge" are different universes here
even though the rows read alike.

This is the same shape as MES-98's seam 1 (the ten buckets partition **three** universes —
edges, declared members, declared checks — so "the sum of the ten equals the crosswalk row
count" adds three kinds of thing and totals a number that counts nothing) and as
S9-14's *rows vs ids*. The register of it: **whenever a document says "exactly one", read
the next noun and ask whether the code quantifies over that noun.**

**Instrument.** The roll-up's `C2-R2` residual **derives** its witness by grouping the
committed cells by member and reporting every member whose edges span more than one bucket,
so the residual cannot go stale against the data it describes — if a future population adds
a second witness, the text names it without anyone editing the text. A hand-written "one
member does this" would have been the S9-11 shape: a figure nothing re-derives.

---

## S9-22 — A fail-closed guard whose exit status does not correspond to its verdict: the GREEN case exits 1

**Found:** MES-100, 2026-09-20, by CODE_CREATOR, while measuring the D7 PM-alone lane
guard on a throwaway fixture before writing it into `CLAUDE.md`. **Not fixed here** — the
guard is D7's canonical text on 250052681, and a repo copy that silently diverged from it
is the exact defect MES-100 exists to prevent. Remedy owned by **MES-106** (PM-raised),
which carries the D7 §3 amendment to the PO.

**The measurement.** The guard is a pipeline joined to its refusal by `&&`:

```bash
git diff --name-only main...{TICKET_KEY} \
  | grep -Eq '^(lib/|test/|conformance/lib/|conformance/controls/|docs/conformance/)' \
  && { echo "REFUSE PM-alone: ..."; exit 1; }
```

Same fixture, same clean docs-only branch, two runs:

| the guard is… | exit | stdout |
|---|---|---|
| the last command of the script | `1` | *(empty)* |
| followed by one more command | `0` | that command's |
| refusing a `lib/` branch | `1` | the REFUSE line |

So **the clean case and the refusal exit alike**, and the only thing that separates them is
the message.

**The mechanism.** When `grep -q` matches nothing it exits 1; the `&&` is not taken, so the
list's status *is* grep's, and the script's status is its last command's. A trailing command
resets it, which is why the behaviour disappears the moment anyone tests the snippet
interactively with something after it.

**Why it matters more than it looks.** `guard.sh && git merge …` reads a clean PM Task as
refused, and a `set -e` merge script aborts on a lane that is fine — a **fail-closed guard
failing closed on the good case**, which trains people to bypass it. This is the
*piped gate exit code is tail's* register entry in another costume: **a status that is
produced by plumbing rather than by a decision is not a verdict.**

**What MES-100 did instead of touching the string.** Every control in
`conformance/controls/pm_alone_lane_guard_controls.exs` adjudicates on the REFUSE message,
never on the status; the status is printed as an observation. `E1`/`E2` are the measurement
above, run. The `CLAUDE.md` merge-gate item says so in the checklist line itself, so a
reviewer cannot reach for the status by accident.

---

## S9-23 — The same guard is fail-OPEN on an unresolvable ref: a check that cannot determine its input answers "fine"

**Found:** MES-100, 2026-09-20, by CODE_CREATOR, same fixture session. **Not fixed here**,
same reason as S9-22; remedy owned by **MES-106**.

**The measurement.** On a fixture whose branch really does touch `lib/` — the honest verdict
is REFUSE — the guard run with a key that does not resolve:

```
$ git diff --name-only main...MES-NOSUCH
fatal: ambiguous argument 'main...MES-NOSUCH': unknown revision or path not in the working tree.
```

`fatal:` goes to **stderr**; **stdout is empty**; `grep` matches nothing; the `&&` is not
taken; the guard falls through **green**. A mistyped key, a branch someone already deleted,
or a run from the wrong directory all read as *touched nothing reviewable*. D7 §3 heads this
section *Guarded fail-closed*; on this input it is not.

**The mechanism, which is the transferable part.** The guard's negative — "nothing matched"
— is carried by an **empty stdout**, and an empty stdout is also what every failure of the
producing command looks like. Wherever a check's PASS is *the absence of output*, the
check's failure mode and its success look identical, and the check must establish that its
input was determined before reading the absence. Exactly the shape of
*ls-remote exits 0 on a missing ref*: what could not be established came back as *fine*.

**Cost, stated plainly.** The two limbs compound. A PM Task mistyped as `MES-1O0` gets a
green guard (S9-23) and, by S9-22, a green guard is indistinguishable by status from a red
one — so the instrument that is supposed to keep unreviewed code off `main` can be defeated
by a typo, silently, in the direction that admits.

**Controlled as observed, not asserted fixed.** `X1` in
`conformance/controls/pm_alone_lane_guard_controls.exs` drives exactly this input and
requires **both** halves — that git said `fatal:`, and that the guard allowed anyway — so
the hole is pinned rather than described. If MES-106's amendment closes it, `X1` goes red
and names what changed.
