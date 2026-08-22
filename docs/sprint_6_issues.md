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
