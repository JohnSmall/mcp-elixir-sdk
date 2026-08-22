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

---

## S6-3 — An assignment clause in a comprehension is a FILTER, so a lookup returning `nil` silently deletes the row it was supposed to check

**Found:** MES-63 (F1), 2026-08-22 — the misdiagnosis by CODE_CREATOR, the
mechanism by the PM, both on the same three lines. **Status:** the instance is
fixed in `test/conformance/classification_test.exs`; the *class* is recorded
here because nothing prevents the next one.

### The defect

`classification_test.exs` checked that every committed classification block
still equals what `Classification.fetch/1` returns. It was written as one
comprehension:

```elixir
for path <- Path.wildcard(...),
    scenario <- ... |> Map.fetch!("scenarios"),
    block = scenario["classification"],
    block != nil,
    entry = Classification.fetch(scenario["id"]),   # <-- returns nil for an unknown id
    expected = %{...entry.why...},
    block != expected,
    do: {Path.basename(path), scenario["id"]}
```

`fetch/1` is `Map.get/2`: it returns `nil` for an id the table does not carry.
A reader — including the seat that raised this — reads the next line's
`entry.why` and concludes that an unknown id **crashes**. It does not. In a
comprehension, `entry = ...` is a generator-position assignment, and an
assignment clause acts as a **filter**: a falsy binding drops the row and the
clauses after it never run for it.

```elixir
for x <- [1, 2], m = (if x == 2, do: nil, else: %{k: x}), out = m.k, do: out
#=> [1]        # no BadMapError — row 2 was filtered out before `m.k`
```

**Measured** in a worktree at `276b22e`, by mutating `server-2026-07-28.json`:

| shape | result |
|---|---|
| untouched tree (control) | green, 11 tests 0 failures |
| id **known**, `why` mutated | **red** — drift reported, names file and scenario |
| id renamed to `bogus-scenario-not-in-table`, block set to `class: "nonsense"` | **green, 0 failures** |

So arbitrary nonsense could sit in a classification block indefinitely, provided
the scenario id was one the table did not carry, and the guard whose entire
purpose is to catch hand-edited artefacts stayed green and said nothing.

### The mechanism, which is the transferable part

**A filter and a lookup look identical at the point of use, and the language
resolves the ambiguity in the direction that produces no output.** The author's
intent — "look this up so I can compare it" — and the language's reading —
"skip this row if the lookup is falsy" — differ only in what happens when the
lookup fails, which is the case nobody writes a test for.

The failure is a **false green**, not a crash, and that is the whole cost. A
crash is loud, lands on the person who caused it, and gets fixed. A row that
deletes itself removes exactly the input that would have failed the check, so
the check reports success **because** it was given something wrong.

### Why the misdiagnosis mattered more than the defect

The obvious remedy for the crash-that-does-not-exist is to guard the `nil` —
add `entry != nil` as a filter clause. **That is a no-op: it is already the
behaviour.** It would change nothing, pass every test, and convert an accidental
false-green into a *designed* one — thereafter the skip would look deliberate
and reviewed, and the next reader would have no reason to question it.

**A wrong mechanism does not merely fail to fix the defect; it selects a fix
that makes the defect permanent and invisible.** This is the argument for
probing the mechanism directly — two lines in `iex` settled it — rather than
reasoning from what the code looks like it does.

### The fix, and the control that proves it

Selection is now two passes: collect the blocks, then assert separately that no
block names an unknown id, then check drift over the blocks that remain. An
unknown id **fails, naming the file and the id** — the same standard applied to
a file that claims to be a census and is not, and for the same reason: a file
claiming to be a census is held to the census contract.

The proving control (S7 in MES-63's matrix) is the mutation above: green before,
red after. **Without it the evidence is compatible with the fix not having
happened**, because every other shape in the matrix asks the test to stop
failing and this is the one that asks it to start.

### Transferable form

**Where a language lets a lookup double as a filter, a failed lookup does not
raise — it removes the evidence.** Before trusting a guard that iterates, ask
what it does with an input it cannot resolve, and *measure* the answer: the
mechanism that produces silence is the one least visible from reading the code,
and a check that skips its own hardest input reports success for it.

---

## S6-4 — An artefact regenerated from the WRONG input is internally consistent, so every semantic check passes; only reproduction against the committed bytes discriminates

**Found:** MES-61 (Sprint 6, F2), 2026-08-22, by CODE_CREATOR, planning the
census regeneration the ticket asks for.
**Status:** closed by amendment — the defective acceptance criterion it
falsified was rewritten by the PM before any work was done against it.

### The defect

MES-61's AC3 required that the regenerated census differ from the committed one
in the reason string alone, and named the way to show it: *"no count, no bucket,
no per-scenario verdict moves, and the headline stays 35/37 with 29
discriminating."*

The ticket's own hazard section warned that `/tmp` holds **many** MES-56-era
server-stateless runs — null controls, a mutation control, several superseded
rounds — and that regenerating from the wrong one would produce a census that is
wrong but internally consistent. AC3 was the criterion standing between the
ticket and that outcome.

**It could not fail.** Four decoy runs — `mes56r2-sdk`, `mes56r4-final-sdk`,
`mes56r5-final-sdk`, `mes56r5-tip-sdk` — were each put through the census
builder. Every one was **accepted by the adjudicator and built a census with
exit 0**. Measured against the committed census, all four gave:

| property AC3 names | decoy result |
|---|---|
| totals | **identical** (all four) |
| per-scenario passes / scored / checks | **identical** (all four) |
| headline 35/37, 29 discriminating | **identical** (all four) |
| `Classification` projection guard | **would be green** (all four) |

The only fields that moved were the `run` block — `run_dir`, `commit`,
`started_at`, `console_sha256` and `manifest_sha256` in every case, plus
`adapter_command` in three of the four — and each scenario's `artefact_dir`
timestamp. That is 216 diff lines for `mes56r2-sdk` and 220 for the other three:
pure provenance, and not one line of substance.

Note what the last row means. The projection guard compares each committed
classification block against `Classification.fetch/1`, so it is green for a
decoy census **for the same reason it is green for the right one** — the block
is a copy of the table either way. Re-measured at this ticket's own tip, the
*corrected* sub-cause (d) text appears in all four decoy censuses too. Fixing
the reason string does not make the artefact self-identifying; nothing in the
projection ever will.

### The mechanism, which is the transferable part

**A census is a projection of a run, and every check AC3 named reads the
projection.** Runs of the same SDK at the same commit against the same frozen
requirement set project to the same numbers *by construction* — that is what it
means for the measurement to be reproducible. So the numbers cannot distinguish
between them, and a check built out of numbers inherits that blindness no matter
how many numbers it looks at.

Provenance is not in the projection. It is in the *correspondence* between the
artefact and the bytes of one specific run — and the only instrument that reads
correspondence is regeneration compared byte-for-byte against what is committed.

**Adding more semantic checks does not help.** Each one is another reading of
the same projection. The checks were not too few; they were the wrong kind.

### Why this one generalises past its own ticket

MES-61 exists because a classification `why` restated the harness's *generic*
error wording as an observation — a claim never tested against the case it was
supposed to exclude. **AC3 was the same defect, one level up:** a set of
plausible-sounding checks written as an oracle, by an author explicitly trying
to be rigorous, and still unable to fail.

That is the part worth carrying. The AC was not sloppy. It named four distinct
properties, quoted exact figures, and demanded they be *shown* rather than
asserted. None of that helped, because every one of those properties is
invariant across the very inputs the criterion existed to tell apart. **The
question a criterion must answer is not "is this hard to satisfy?" but "what
does its passing rule out?"** — and that is answerable only by constructing the
case it is meant to exclude and running it.

### The remedy, as applied

AC3 was amended mid-ticket by the PM to require, **first**, that the
unedited-table reproduction come back byte-identical to the committed artefact
*before any edit is made*. That baseline is what converts the semantic checks
from detectors into attributors: once the pipeline is known to be deterministic
over these inputs at this commit, any post-edit delta is attributable to the
edit and nothing else. Without it, a clean-looking diff proves nothing.

Executed on MES-61: three artefacts, **0 diff lines**, md5
`9db0e67a…` / `f72c05e2…` / `55f5fe35…`, before the reason string was touched.

### The standing fragility this rests on, stated because it is not fixed

Every regeneration claim above depends on two directories in `/tmp`
(`mes56r3-sdk`, `mes56r3-null`) that **no commit holds** — only the censuses are
committed. A container restart destroys the ability to prove provenance for any
artefact in `docs/conformance/`, and by this entry's own argument no substitute
run could be detected as a substitute. The window is one restart wide and it is
open now. Not fixed here; recorded so that the next ticket needing a
regeneration knows it may open, find the provenance gone, and have to stop.

### One consequence of MES-61's scope, routable rather than fixed

`docs/conformance/report-2026-07-28.md` and its published Confluence snapshot
`docs/conformance/confluence/report-2026-07-28.json` carry a correction
paragraph describing the census's *defective* sub-cause (d) — correctly, as the
thing they were reporting. After MES-61 merges, that paragraph describes a
census state `main` no longer has. Both were left untouched deliberately: they
quote the defect as evidence, and the report is a dated MES-58 deliverable whose
Confluence twin MES-61 may not write, so editing the local copy alone would
desynchronise a pair that is currently consistent. **A reader of the report has
no reason to open this file**, so the desync is flagged to the PM as a routable
backlog item rather than left to this register alone.

### The correction rounds: not one false claim but every claim in the sentence

MES-61 was raised to correct **one** sub-cause. Two PM-ordered correction rounds
later, the count is different, and the difference is the finding.

The sentence as it stood at `6fe529d` named four sub-causes and claimed "four
distinct defects". Audited claim by claim against the accepted run's own check
sheet, **all four were wrong**, and one of the four ways is only visible once
the other three are:

| sub-cause, as written | what the run shows | found by |
|---|---|---|
| (a) "a request whose `_meta` is **absent or invalid**" | only absence is exercised — no `_meta`, no `protocolVersion`, no `clientCapabilities`. No malformed-but-present case exists in the scenario | round 2 |
| (b) "the supported-versions payload **does not have the shape** the check reads" | there is no payload. The probe is answered HTTP 200 with a normal `result` and **no `error` object at all** | round 2 |
| (c) "the JSON-RPC code **is already right**, the HTTP status is not" | true of five checks; `initialize` observes `-32022`, not `-32601` | round 1 |
| (d) "`error.data.requiredCapabilities` **is an array** where the schema defines an object" | there is no `error.data`. The error object's keys are exactly `['code', 'message']` | the original ticket |

Plus the coverage error S5-30 caught independently: "four distinct defects"
covered 16 of the 17 failing checks. Four false claims and one arithmetic gap,
in one sentence, none of which any gate, test or reviewer had caught.

### Why "three more" is a different finding from "one"

A single false claim is a mistake. **Four, all failing the same way, is evidence
that the sentence was never checked against the run at all** — and the shared
failure mode says what it was checked against instead:

* (d) — harness: *"...is not a ClientCapabilities object naming 'sampling'... not
  an array"*. Census: *"is an array where the schema defines an object."*
* (b) — harness: *"Returned supported versions data layout does not correlate to
  active server metrics: undefined"*. Census: *"does not have the shape the check
  reads."*
* (c) — harness: *"Expected HTTP 404 and code -32601 for removed methods, got
  HTTP 200 and code ..."*. Census: *"the code is already right, the status is
  not."*

Every one is a faithful paraphrase of the **harness's error string** and a false
statement about the **server**. That is the whole mechanism. A generic
diagnostic states what the check *required*, parameterised by whatever it found;
it reads like an observation and is not one. Paraphrasing it produces prose that
is fluent, specific, plausible, and unrelated to the response on disk — and
which no reader can tell from a real observation, because a real observation
would be worded identically.

The tell, once you know to look for it, is that these messages describe the
*schema* in the present tense. "Is an array", "does not have the shape", "is
already right" are claims about a value. If the check had actually read that
value it would normally print it — and where it does, the printed value is the
refutation: (b)'s message ends in the literal token `undefined`, which is the
harness echoing back `JSON.stringify(undefined)` after finding nothing at
`error.data.supported`.

### How (b) was established when the check saved no response

Worth recording as a method, because the obvious route was closed.
`sep-2575-server-unsupported-version-error` stores `details: {}` — the harness
does not save the response on that branch, so the claim could not be settled by
reading it. It was settled by arithmetic instead:

* The scenario's last check, `sep-2575-http-server-error-jsonrpc-id`, records
  `errorResponsesObserved: 7`. That counter is incremented once per probe whose
  response body carries an `error` key.
* Exactly seven checks in the sheet quote an observed error code: `-32021`
  (undeclared capability), `-32022` (`initialize`), and `-32601` five times
  (`ping`, `logging/setLevel`, `resources/subscribe`, `resources/unsubscribe`,
  generic unknown method).
* Seven counted, seven named, none left over — so **no other probe returned an
  error at all**, and the unsupported-version probe is not among them.

The same arithmetic independently confirms (e): the header-mismatch probe also
returned no error object, which is what its `code undefined` means.
**A saved artefact can carry the answer to a question it does not answer
directly.** Counters, totals and invariants elsewhere in the same file
constrain what the missing value can have been, sometimes to a single
possibility.

### The cost asymmetry that decided all of this

Each correction cost one round on an unmerged branch while `/tmp` still held the
run. Finding the same claims after merge would cost something categorically
different: editing the table makes `ClassificationTest`'s drift guard go red,
and the only legitimate way to clear it is to regenerate from the run — which by
then may not exist. **The window is not merely expensive to lose; losing it
makes the fix unavailable.** That is why the second and third false claims were
ruled into this ticket rather than routed, against the ordinary presumption that
new scope routes.

### Transferable form

**An artefact rebuilt from the wrong source is not corrupt — it is coherent, and
coherence is what every semantic check measures.** Before trusting a
regeneration, reproduce the *existing* committed bytes from the source you
believe produced them, unedited, and require byte equality. Then edit. A check
that reads only the output can tell you the output is well-formed; it can never
tell you which input it came from, and no number of such checks adds up to one
that can.

**And the second, which this entry acquired by being corrected twice: a generic
diagnostic message is not an observation.** When a tool reports that X "is not a
Y", it has told you what it required, not what it saw. Attribute a cause to the
response the run actually saved — or, where the run saved nothing, to an
invariant that constrains it — and where neither is available, say that you
could not establish it. A paraphrase of the requirement, written in the past
tense, is indistinguishable from a finding and carries none of its content.
