# Sprint 6 — procedure defects

Procedure defects found while working Sprint 6 (epic MES-65): things wrong with
**how we work** — the gate set, the briefs, the tooling contract.

Ticket substance does not go here. Findings about the MCP SDK itself, about
conformance results, or about a specific ticket's deliverable belong in comments
on that ticket. This file is for defects a *future* sprint would otherwise hit
again.

Each entry states the **mechanism**, because the mechanism is the transferable
part. "The description tool wouldn't take my content" is not reusable; "the
description writer validates against the `jira_comment` profile, which has no
`heading` node" is.

---

## S6-1 — `jira_set_description` validates against the COMMENT content profile, so a ticket brief cannot carry headings

**Found:** Sprint 6 planning, 2026-08-22, by the PM, amending MES-66 and MES-70
to record a PO ratification. **Status:** open — **for the EMFA project**, not
fixable here. The PO is carrying it upstream at the end of this sprint.

### The defect

`mcp__emfa-wrapper__jira_set_description` is the contract-designated tool for
setting a ticket brief (CLAUDE.md: *"Brief → the ticket body
(`jira_set_description`, PM-only)"*). Its typed content model admits exactly six
block types:

```
block = paragraph | codeBlock | panel | table | bulletList | orderedList
```

There is no `heading`. There is no `blockquote` and no `rule` either.

The tool's own description offers what looks like an escape hatch — *"Raw ADF
nodes are also accepted in `content` and pass through unchanged, converging on
the same validator"* — so the PM tested it rather than assuming. Sending a raw
ADF `heading` node to MES-66:

```
{"error":"UNSUPPORTED_NODE",
 "location":"content[0] (heading)",
 "detail":{"profile":"jira_comment","type":"heading"},
 "message":"Rejected by the content validator: UNSUPPORTED_NODE."}
```

**The escape hatch does not escape the vocabulary.** "Converging on the same
validator" means the raw path is restricted identically; only *node attributes*
pass unchecked.

### The mechanism, which is the transferable part

Read `detail.profile`: **`jira_comment`**. The description writer is validating
against the **comment** content profile.

That is very likely correct for comments — under A13 a brief-sized comment is
split into ~6k-byte parts, and a heading inside a fragment of a split document
is arguably noise. **A description is a different artefact.** It is one whole
document, it is the first thing every seat reads, and every existing MES brief
is structured with `##` headings. Applying the comment profile to it is a
category error rather than a missing feature: the constraint was designed for
one artefact and inherited by another.

### The measured consequence

MES-66 and MES-70 were created through Rovo's `createJiraIssue` with markdown,
so both carry real `##` headings. Re-emitting either through
`jira_set_description` would have **flattened every heading into a bold
paragraph** — a visible downgrade of a document that is 6 KB of structured
brief. The PM therefore amended both through Rovo's `editJiraIssue`, deviating
from the named tool, and disclosed the deviation rather than letting the
formatting quietly degrade.

**So the contract currently names a tool that cannot reproduce the artefacts the
project actually writes.** Any PM amending a brief hits this, and the two
available responses are both bad: degrade the brief, or leave the contract.

### What is NOT wrong, and should be said

- **It fails closed.** The rejection happened before any write: MES-66's
  `updated` timestamp was unchanged (`2026-08-22T06:46:45.796+0100`) and the
  body was intact. No partial write, no corruption.
- **The error is excellent.** It names the offending node, its index
  (`content[0]`), the profile applied, and a machine-readable code. Diagnosing
  this took one call. Most tools would have said "400".
- **The capture-and-return of the previous ADF is a genuine safety net** and has
  no equivalent on the Rovo path. That is a real reason to prefer the wrapper
  where the content model allows it.

### For EMFA

The ask is narrow: **give `jira_set_description` a description profile rather
than the comment profile**, admitting at minimum `heading`. `blockquote` and
`rule` would also be used — MES-66 quotes the ratified ruling as a blockquote.

If the profiles are deliberately shared, that is a defensible answer, and the
fix is then in the *contract* rather than the tool: CLAUDE.md should stop naming
`jira_set_description` as the mechanism for briefs, or should state that briefs
are heading-free. **What cannot stand is the present position, where the named
tool and the actual artefacts disagree and each PM rediscovers it.**

### Transferable form

**A validator profile named for one artefact and applied to another produces a
constraint nobody chose.** The rule was right where it was written and wrong
where it was inherited — and because it arrives as a flat rejection rather than
as a stated policy, the caller experiences it as a bug in their own payload. Ask
which artefact a profile was designed for before reusing it, and name it after
the artefact it validates, not after the one it was first written for.

---

## S6-2 — A ticket ruled into a sprint by the epic's prose is not thereby in the Jira sprint, and nothing reconciles the two

**Found:** Sprint 6 dispatch, 2026-08-22, by the PM, about to dispatch F1.
**Status:** open. **Second confirmed occurrence** — this is a class, not an incident.

### The defect

MES-65's *Composition* section names 28 tickets in six groups and ends with
`Sequencing: F → A → B → C1/C2 → C3 → D → E2/E3`. Group F is enumerated
explicitly: **F1 = MES-63**, **F2 = MES-61**. The epic therefore states, in
writing, that these two are sprint members and that they run *first*.

Both carried `sprint: []` and the trailing line **"Backlog — not Sprint 5."**
They were never added to the Jira sprint. The board showed six tickets
(MES-65..70) for a sprint the epic describes as twenty-eight.

### The mechanism, which is the transferable part

**The same fact is recorded twice, in two systems, and neither can see the
other.**

| record | form | who reads it |
|---|---|---|
| epic body, *Composition* + *Sequencing* | prose | humans planning the sprint |
| `customfield_10020` on each issue | data | the board, JQL, any sprint report |

Prose is where the *reasoning* lives — why F precedes A, what F1 unblocks. The
sprint field is where the *membership* lives. Writing the reasoning does not
write the membership, and there is no check that closes the gap in either
direction. So the discrepancy is invisible from both sides: the board looks
complete because six tickets are genuinely in it, and the epic looks complete
because it genuinely lists twenty-eight.

**It fails toward silence, not toward error.** Nothing raises. The sprint simply
proceeds against a smaller set than was planned, and the shortfall surfaces —
if at all — as "we seem to be finished" at a point where a third of the work was
never on the board.

### Why this one is a class and not a slip

**Sprint 4, MES-24.** Ruled into the sprint at planning; absent from the Jira
sprint. Recorded then as a thing to remember: *the sprint is MES-13…19 plus
MES-24; do not call the sprint done without checking.*

**Sprint 6, MES-63 and MES-61.** Same shape, two tickets, and this time they sit
at the *head* of the declared sequencing rather than the tail — so the omission
was load-bearing rather than merely untidy.

Two occurrences in three sprints, in a project that otherwise reconciles its
numbers obsessively. The remembering did not work, which is the argument for
writing it down as a defect rather than as a habit.

### The measured consequence, this time

F1 (MES-63) is not decorative. `test/conformance/classification_test.exs:161`
globs `docs/conformance/*-2026-07-28*.json` and `Map.fetch!`es `"scenarios"`.
A1's brief (MES-66, scope item 1) requires committing
`docs/conformance/in-scope-2026-07-28.json`. Measured by the PM in a worktree at
`dbcb124`:

| manifest present? | top-level shape | gate 5 |
|---|---|---|
| yes | no `"scenarios"` key | **red** — `KeyError` at `classification_test.exs:161` |
| yes | has a `"scenarios"` array | green |
| no (control) | — | green |

So had the sprint run as the board described it, **A1 would have gone first and
failed gate 5 on a defect raised, understood and scheduled a day earlier.** The
finder would have spent their time on a `KeyError` about a missing key rather
than on the manifest they were writing — which is precisely the cost MES-63's
own brief predicts.

### What is NOT wrong

- **The epic prose was right.** It named F1 and F2, explained why they come
  first, and sequenced them correctly. The planning was sound; only its
  transcription into Jira was incomplete.
- **Nothing was lost.** Both tickets existed, briefed, with their evidence
  intact. This is a bookkeeping gap, not forgotten work — which is exactly why
  it is easy to keep making.

### The ask

**At sprint open, reconcile the epic's composition list against the sprint's
actual membership, and record the result — including a clean one.** The
project already applies this standard to advisories ("checked, and zero" and
"never asked" read identically when only the answer is printed); sprint
membership deserves the same treatment. One JQL against the epic, compared to
the enumeration in the epic body, would have caught both occurrences.

Whether that becomes a step in the End-of-Sprint Procedure — which currently
covers the *closing* boundary but says nothing about the *opening* one — is the
PO's call. It is raised here rather than decided.

### Transferable form

**Prose that assigns work and a field that schedules it are two records of one
fact, and the one a human reads is not the one the tooling obeys.** Anywhere a
plan is written in one system and executed from another, the plan's own
completeness is no evidence that the execution list matches it. State the
membership where the tooling reads it, or check the two against each other on a
cadence — remembering to do it by hand has now failed twice.
