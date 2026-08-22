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

---

## S6-5 — A field that records why something FAILED is null for everything that succeeds, so a scope rule derived from it is systematically wrong about passes — and wrong in the flattering direction

**Found:** MES-66 (Sprint 6, A1), 2026-08-22, by CODE_CREATOR, re-deriving the
in-scope denominator from the accepted censuses rather than inheriting the
brief's figures. **Status:** open — narrowed, not closed. The manifest is now
the single place the scope rule is written down, but the censuses still carry no
in-scope flag, so a consumer that does not read the manifest can still
re-implement the rule and get a plausible wrong answer.

### The defect

The committed censuses record, per scenario, a `classification` block naming the
class of a non-passing result (`real_gap`, `extension`, `pending`,
`out_of_scope_adr_003`, …). They record **nothing at all** about whether a
scenario is inside the published denominator. There is no `in_scope` field.

So every consumer that needs the denominator re-implements the rule, and the
most natural re-implementation reads the field that is *there*: "in scope =
scored, and not classified `out_of_scope_adr_003`". Measured on the committed
client census, that yields **8 scenarios / 57 checks**. The published, ratified
figure is **7 / 56**.

The extra scenario is `auth/resource-mismatch`. It is scored. It is in the
`auth/` namespace that ADR-003 puts out of 2.0.0. And it **passes** — so the
census refuses it a classification entry, because the classification table
exists to explain failures. Filtering on that field therefore readmits exactly
the auth scenarios we happen to pass.

### The mechanism, which is the transferable part

**A field populated only on the failure path is `null` on the success path, and
`null` is indistinguishable from "does not have this property".** Any predicate
of the form *"…and not classified X"* silently becomes *"…and not classified X,
**or passing**"*. The rule does not fail loudly on the passes; it admits them.

Two properties make this worse than an ordinary off-by-one:

* **It is directional.** The rows wrongly readmitted are, by construction, the
  ones that PASS. A denominator inflated only by passes moves the numerator and
  the denominator together, so the resulting rate looks *better*, not worse.
  Here it would have turned 7/7 in-scope into a figure computed over 8.
* **It is plausible.** `out_of_scope_adr_003` is a field whose literal name is
  the exclusion being applied. Reading it is not a careless shortcut; it is the
  obvious thing to do, and it is what the field appears to be for.

### Not one instance — four, across both legs

The shape is not a quirk of one scenario. Every scenario in the censuses that
carries `classification: null` while being excluded from the in-scope set is an
instance of it:

| leg | scenario | scored | passes | `classification.class` |
|---|---|---|---|---|
| client | `auth/resource-mismatch` | yes | yes | `null` |
| client | `json-schema-2020-12-preservation` | no | yes | `null` |
| server | `tasks-status-notifications` | no | yes | `null` |
| server | `json-schema-2020-12` | no | yes | `null` |

Three of the four are excluded by a second, independent mechanism (the frozen
requirement set does not score them), so a classification-keyed rule that also
checks `scored` gets those three right **by luck** — the two mechanisms happen
to agree. `auth/resource-mismatch` is the one where they disagree, and it is the
one that moves the number.

This is why the same table is the right place to look for the *reason* an
excluded scenario is excluded and the wrong place to look for the *fact* that it
is. The reasons this manifest publishes come from the frozen requirement set's
own `harness_reason`, which is populated for every not-scored scenario
regardless of whether it passed.

### What is NOT wrong, and should be said

The published figure is correct and the published derivation is correct.
`client-2026-07-28-discounts.md` already states the rule as *"the scored client
scenarios not in the `auth/` namespace"*, names all 25 exclusions, and says in
so many words that the raw 8/32 exceeds the in-scope numerator "by exactly the
auth scenarios that pass: `auth/resource-mismatch`". `MCP.Conformance.Discounts`
implements the namespace rule and carries a module-doc paragraph explaining why
the table-driven derivation would be wrong.

So nothing shipped a wrong number, and the hazard was already known to the one
module that had to get it right. The defect is that **the knowledge lives in the
consumer rather than in the artefact**: every *new* consumer must rediscover it,
and the way to rediscover it is to get the wrong answer first.

### Transferable form

**Do not derive a category from a field that only speaks about one outcome.**
Before keying a rule on a field, ask what that field holds for the rows where
nothing went wrong — if the answer is "nothing", the rule has a silent second
clause admitting every such row, and it will be wrong in whichever direction
success points.

**And the artefact should carry the classification the consumers need, not
merely the evidence they could compute it from.** When N consumers each derive
the same category from raw fields, the derivation is N times as likely to be
wrong somewhere as it is to be wrong once, and there is no single place to fix
it. Emitting the derived flag beside the evidence costs one field and converts
"everyone re-implements it" into "everyone reads it, and one place is
authoritative".

---

## S6-6 — One source construct compiles to N runtime tests, so every mechanism that addresses tests by their source — a tag, a grep, a count — covers a subset and reports success

**Found:** MES-67 (Sprint 6, A2), 2026-08-22, by CODE_CREATOR, while defining
the ET-CC membership criterion. **Status:** open as a class; both known
instances have measured remedies, and the remedies share the failure mode.

### The defect

ET-CC membership — and any per-test property we will ever record — is a
property of a **runtime test**. Every mechanism we have for naming a test
addresses a **source construct**: an ExUnit `test` declaration, a `doctest`
declaration, a `file:line` citation, a `grep` pattern. In this tree that map is
one-to-many in two places, and *both* mechanisms that traverse it fail the same
way: they cover a subset and return a success signal.

**Instance 1 — the denominator.** MES-67's brief, and MES-65's epic prose,
scope the sweep as "the 537 tests under `test/mcp/`". Measured at `9661ef8`:

```
grep -c '^\s*test "' over test/mcp/    ->  537   source declarations
mix test test/mcp                      ->  566 tests + 13 doctests = 579 runtime units
mix test test/conformance              ->  285   (the brief said 236)
```

537 is exactly the grep. The 29-test gap is fully accounted for by four `test`
declarations wrapped in a `for` comprehension, each compiling to one test per
value:

```
test/mcp/protocol/messages/tools_test.exs:131      2 decls x 10 values -> 20  (+18)
test/mcp/server/json_schema_2020_12_test.exs:188   1 decl  x 11 values -> 11  (+10)
test/mcp/protocol/types/tool_test.exs:108          1 decl  x  2 values ->  2   (+1)
                                                                  total  +29
537 declarations - 4 expanded + 33 generated = 566 tests   (+13 doctests = 579)
```

Ruled out as the cause: `node` on PATH, which accounts for 3 excluded tests in
the whole-suite run, not 29.

**Instance 2 — the tag.** Measured on a throwaway three-doctest module and a
three-value `for`, under Elixir 1.19.5:

| mechanism | what it actually reaches |
|---|---|
| `@tag :x` before `doctest Mod` | the **first generated doctest only** — 1 of 3; the other 2 silently excluded |
| `@moduletag :x` | the **whole module** — every doctest *and* every ordinary test in the file |
| `@tag :x` before a `for`-wrapped `test` | the **first generated test only** — 1 of 3 |

The second row is not a hypothetical over-reach. Both `doctest` declarations in
this tree sit in files dense with ordinary tests (`extensions_test.exs`, 41
units; `header_mirror_test.exs`), so `@moduletag` sweeps unrelated tests in
while `@tag` reaches at most 2 of the 13 doctests.

### The mechanism, which is the transferable part

**A construct that expands is invisible to the thing that addresses it.** The
`for` and the `doctest` macro both run at compile time; by the time ExUnit has
tests, the expansion has already happened and the one-to-many step left no
record at the address the caller used. `@tag` is a module attribute consumed and
cleared by the *next* `test` call, so an expansion that emits N `test` calls
consumes it once. `grep` never sees the expansion at all.

**Both failure modes return success.** A sweep whose denominator is 537 visits
every row it knows about and reports complete. `mix test --only etcc` over a
subset-tagged suite exits 0 and prints a green. Neither prints the question, and
from where the caller stands 537 and 566 read identically as "all of them". This
is the S5-7 / S6-5 shape — absence read as satisfaction — arriving through the
*address* rather than through a field.

### The remedies exist, and they have the same failure mode one level up

Measured, same session:

| remedy | reach |
|---|---|
| `@tag :x` **inside** the `for`, before `test` | all N generated tests |
| `doctest Mod, tags: [:x]` | all doctests of that declaration; ordinary tests untouched |
| `doctest Mod, only: [f: 1], tags: [:x]` | that function's doctests only |
| two `doctest Mod, only: [...]` declarations in one module, one tagged | composes cleanly — no name clash, no error |

So the granularity floor is `{function, arity}`: **no `doctest` option separates
two doctests of the same function.** In this tree at `9661ef8` that floor is
sufficient — the 13 doctests come from 5 functions and no function's doctests
split across labels — but that is a measured contingency, not a guarantee.

**And the remedy fails silently if the toolchain drifts.** Measured: an
unrecognised option to `doctest` is **ignored with no warning and no error** —
`doctest Sub, tags: [:meas], no_such_option_xyz: [:meas]` compiles clean and runs.
`mix.exs` declares `elixir: "~> 1.17"`; the measurements above are on 1.19.5. On
any Elixir predating the `:tags` option, `doctest Mod, tags: [:etcc]` therefore
compiles clean, tags nothing, and the suite goes green — the same defect, now in
the fix.

**The one thing that fails closed is also the one that cannot help.** `mix test
--only etcc` exits **1** when *zero* tests match ("The --only option was given to
`mix test` but no test was executed"). That catches the total miss. It does
nothing for the partial miss — 1 tagged of 13 exits 0 — which is the actual
failure mode here.

### Transferable form

**Count the thing you are going to act on, not the thing you can grep.** Before
adopting a denominator, run the tool that produces the population and compare.
If a brief states a figure, establish it; `grep -c` over declarations and
`mix test` over the same path answer different questions, and the difference is
invisible in the smaller answer.

**When a mechanism selects a subset, the exit code cannot tell you.** A
selection mechanism's green means "everything selected passed", never
"everything intended was selected". The only evidence that separates them is the
**count**, asserted against an independently-derived expected count. Any design
that tags a population and then runs `--only` needs that assertion as a positive
control, or it is asserting nothing.

**An unrecognised option that is ignored is a silent-subset mechanism.** Before
relying on an option to carry a property, check what happens when it is *not*
understood. If the answer is "nothing, quietly", the option's presence in the
source is not evidence that it took effect, and the version that introduced it
must be pinned or asserted rather than assumed.

---

## S6-7 — The seat launch prompt says "hand the baton back" but never names the role, and `jira_handoff` forces the seat to choose one

**Found:** MES-67 (Sprint 6, A2), 2026-08-22, by the PM, when CODE_CREATOR's
close-out arrived with CODE_REVIEWER already reviewing it. **Status:** open —
**for the EMFA project**, not fixable here. It is a defect in how seats are
instructed, not in any ticket's deliverable.

### The defect

The flow is `PM→CC→PM→CR→PM` — **mediated**. CLAUDE.md states it, and the
Confluence working procedure is its source. A seat acts only when the assignee
is its own service account, so the assignee *is* the baton.

The seat launch prompt (from `../wp_scripts/`, visible in the process table)
says:

```
Hand the baton back with the jira_handoff tool on the emfa-wrapper, which posts
the comment and moves the assignee in one call. Never use a Rovo comment tool
for a hop: it posts the comment without moving the assignee, so the turn
silently does not pass.
```

That instruction is precise about the *tool* and silent about the *destination*.
`jira_handoff` requires `next_role`, so the seat must supply one — and
**"back" is not a role**. A seat reading only its launch prompt has to infer
the destination, and "the next seat in the pipeline" is a defensible reading:
it is the reading under which work moves forward.

CODE_CREATOR handed A2's close-out directly to CODE_REVIEWER. CR's polling loop
picked it up **four seconds later**.

### Why the mediated hop is not ceremony — the measured cost

The PM hop exists so the PM adjudicates a close-out before review: verifies
claims, rules on deviations, and tells the reviewer where to aim.

A2's close-out declared **three deviations from the ratification it was
executing** — an `ET-ADJ` test re-keyed onto a `lib/` call site (CC's own words:
"a real deviation, not a paraphrase"), gate 1 yielding `OUT-OF-SCOPE` rather
than a label, and a label-precedence rule in neither the plan nor the
ratification.

**All three reached the reviewer before they reached the seat that set the
terms.** CR spent its review confirming a ratification whose terms had moved,
without being told they had. It rated all three improvements — and it was right,
all three were adopted — but that was luck about the content, not a property of
the routing. Had one been wrong, the reviewer would have been the only check on
a deviation from a rule it did not know had changed.

### The mechanism, which is the transferable part

**A rule stated where the decision is *described* but not where the decision is
*made*.** The mediation rule lives in CLAUDE.md and on Confluence. The
`next_role` argument is supplied at a tool call, in a context where neither is
quoted. Between the two sits a launch prompt that names the tool, warns about a
different failure mode, and stops one word short.

The instruction is not wrong. It is **incomplete in exactly the place the
caller must act**, and incompleteness there reads as latitude rather than as an
omission — so the seat does not experience itself as guessing.

### What is NOT wrong, and should be said

- **CC declared all three deviations plainly, at the top of its close-out**, and
  did not bury them. A seat that flags its own departures has done its job; the
  flag went to the wrong reader first.
- **The guard the prompt *does* carry is the right one** — "never use a Rovo
  comment tool for a hop" prevents a silent non-pass, which is the worse
  failure. This is a gap beside a good rule, not a bad rule.
- **Nothing was lost.** CR reviewed well, the PM adjudicated afterwards, and the
  ticket merged. The cost was a check performed out of order, not a check
  skipped.

### For EMFA

The ask is one clause: **name the destination role in the launch prompt**, or
state the mediation rule there. Something of the shape *"hand back to PM;
PM routes to CR"* would have closed it.

If seat prompts are meant to be project-agnostic and the flow is a project
concern, that is a defensible answer — and the fix then belongs in the
project's own instructions, quoted where the seat will read it at hand-off
time, not only where the procedure is described.

### Transferable form

**An instruction that names a tool but not its destination will be completed by
whoever calls it, and they will complete it plausibly.** Where a rule must
survive into a specific argument of a specific call, state it at that call —
a rule that lives only in the document describing the process is not available
at the moment the process executes.

---

## S6-8 — A classifier keyed on too few inputs still returns an answer for every case, and two candidate rules that agree on the whole sample in front of you are not the same rule

**Found:** MES-68 (Sprint 6, A3), 2026-08-22, by CODE_CREATOR while executing
the PM's ratification, and upheld by the PM the same day. **Status:** closed —
the rule shipped in `docs/conformance/match-relation.md` is the corrected one.

### The defect

MES-68's brief carried a PM amendment: *"Bucket is a function of the verdict
pair; `partial` is carried alongside."* It was written against a contributed
architecture page that said the opposite (*"partial edges land in bucket 4b"*),
and its reasoning was right — a `partial` edge over a **green** OC check is
bucket 5, so `partial ⇒ 4b` is false.

But the replacement does not work either, and the epic's own bucket table is
what settles it:

```
4a | red OC / green ET-CC — contradiction   | D4a
4b | red OC / green ET-CC — incompleteness  | D4b
```

**Identical verdict pair.** Any rule of the form `bucket = f(verdict pair)`
narrows to `{4a, 4b}` and then stops — and it stops *silently*, because a
partial function over pairs still returns something for every pair it does
handle. The domain is too small to separate two of the eight output buckets,
and nothing in the shape of the rule says so.

### Why nobody caught it, and this is the transferable part

**On the sample in front of both of us, the two rules agree.** The case that
motivated the amendment is the R2 class — 12 `server-stateless` checks where
our tests assert a JSON-RPC code and the check also requires an HTTP status.
Every one of those 12 is **OC-red**. Over an OC-red population, "bucket from the
pair" and "bucket from the pair plus the edge shape" return the same answer for
every row. The disagreement lives entirely in a case the worked example does not
contain: a partial edge whose check is **green**.

So the rule was checked against the instance that prompted it, agreed with the
alternative on every row of that instance, and was wrong about the rest of the
space. **A rule validated on the case that motivated it has been validated
against the one sample guaranteed not to discriminate.**

### The second instance, same ticket: the artefact's prose is not the artefact's rule

The same shape appeared one system over. An OC check's `description` is prose
about the requirement; its predicate is the requirement as scored. They
disagree:

```
HttpServerUnsupportedVersion400
  description: "...MUST respond with 400 Bad Request AND an
                UnsupportedProtocolVersionError listing its supported versions."
  predicate:   S.status === 400        <- ONE axis
```

Decomposing checks into axes by reading their descriptions agrees with the
predicate on most checks and invents an axis here — and then scores us against
an obligation the suite never checks. Read from the predicates, the ruling the
epic sized at **12 checks** moves at most **7**; the other **5** are single-axis
and move the other way, into "write the test" rather than "extend the
assertion". The epic's figure was superseded by measurement, not by argument.

### What was done

- `bucket = f(verdict pair, edge shape)`, with **stated precedence** —
  contradicts beats silent — so 4a and 4b are exclusive *by construction*
  rather than by adjudication. Without the precedence the `:83` `initialize`
  edge, which is **both** contradicting and partial, files under whichever axis
  an implementation happens to test first, and the epic's own worked 4a example
  lands in 4b.
- Two `(pair, shape)` combinations that should not occur **escalate** instead of
  bucketing — one of which was implicit in the ratified table and is now
  explicit, because an implicit case in a total-looking function is this same
  defect in miniature.
- The axis decomposition is **committed as data** with the harness build's
  sha256 alongside, so the inputs to the rule are auditable rather than
  derivable only from a `/tmp` tree.
- Three **mutation controls** on the test suite, each restoring a rejected rule
  and showing which assertions catch it: dropping the discriminator from
  resolution (5 failures), inverting the precedence (2), and collapsing 4a into
  4b — the withdrawn `f(verdict pair)` rule — (2).

### Transferable form

**Check a classification rule against its own output vocabulary, not against
its worked example.** If two outputs can be produced from the same inputs, the
inputs are not the rule's domain — and the example that motivated the rule is
the one sample least able to tell you so. The question to ask is not *"does this
give the right answer here?"* but *"is there a pair of outputs this rule cannot
tell apart, and what in the space would separate them?"*

The corollary, from the second instance: **when a rule reads a field of someone
else's artefact, establish which field is the one the artefact acts on.** A
human-readable description and an executable predicate are two records of one
requirement, and the one a reader reaches for first is not the one the tool
obeys — the same shape as S6-2, one system further out.
