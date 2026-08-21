# Sprint 5 — procedure defects

Procedure defects found while working Sprint 5 (epic MES-55): things wrong with
**how we work** — the gate set, the briefs, the tooling contract.

Ticket substance does not go here. Findings about the MCP SDK itself, about
conformance results, or about a specific ticket's deliverable belong in comments
on that ticket. This file is for defects a *future* sprint would otherwise hit
again.

Each entry states the **mechanism**, because the mechanism is the transferable
part. "Gate 3 missed a file" is not reusable; "credo's bundled default carries a
hardcoded `files.included` and never reads `elixirc_paths`" is.

---

## S5-1 — Gate 3 (`mix credo`) was blind to `conformance/`, and `elixirc_paths` could not fix it

**Found:** MES-51, 2026-08-20.
**Status:** fixed for `conformance/lib/` by a root `.credo.exs` (MES-51, ratified as E1).
**Still open:** the rest of `conformance/` — see the residual below.

### The defect

MES-46 established that gates 1 (`mix format --check-formatted`) and 2
(`mix compile --warnings-as-errors`) are blind to the `conformance/` directory,
and the MES-51 brief repeated that pair. **Gate 3 is blind too, and the brief did
not say so.** Anything placed in `conformance/` was unchecked by three of the six
DoD gates, not two.

Worse, the obvious fix does not work. Gates 1, 2 and 4 are all reachable from
project configuration that already exists:

| Gate | How it reaches `conformance/lib/` |
|------|-----------------------------------|
| 1 `mix format --check-formatted` | add the glob to `.formatter.exs` `inputs` |
| 2 `mix compile --warnings-as-errors` | add the path to `elixirc_paths/1` in `mix.exs` |
| 3 `mix credo` | **neither of the above works — needs a `.credo.exs`** |
| 4 `mix dialyzer` | follows from gate 2 (the modules become app beams) |

### The mechanism

With no `.credo.exs` present, credo loads its **bundled default config**, whose
`files.included` is a hardcoded list:

```
["lib/**/*.{ex,exs}", "src/", "test/**/*.{ex,exs}", "web/",
 "apps/*/lib/", "apps/*/src/", "apps/*/test/", "apps/*/web/"]
```

Credo **never reads `elixirc_paths`**. The two are unrelated mechanisms. So
extending `elixirc_paths` — which is what brings gates 2 and 4 onto a new
directory — does not drag credo along with it, and a "the gates now cover it"
claim would ship with credo silently absent.

### Measured, both directions

On `main @ ae0e922`, before the fix:

```
$ mix credo --debug | grep Checking
Checking 121 source files (this might take a while) ...
```

`lib/` + `test/` contain exactly 121 `.ex`/`.exs` files; the 4 files under
`conformance/` are not among them.

The control that matters is the same defect judged twice. A module with no
`@moduledoc` was placed in `conformance/lib/`:

```
with    .credo.exs   ->  exit 4, "Modules should have a @moduledoc tag", 128 files checked
without .credo.exs   ->  exit 0, "found no issues",                      121 files checked
```

The identical defect is invisible in one configuration and caught in the other.
That is the mechanism demonstrated rather than asserted.

### The fix, and its one trap

A root `.credo.exs` that **restates credo's default `files.included` verbatim
and appends one entry**. `checks:` is deliberately **omitted**: naming checks
there would freeze the enabled-check set at whatever credo's default happened to
be on the day the file was written, so the project would stop tracking credo's
defaults without anyone noticing.

Verify by the **list, not the count** — 121 can equal 121 while membership has
swapped:

```
$ comm -23 files_before.txt files_after.txt   # removed from credo's set
(empty)
$ comm -13 files_before.txt files_after.txt   # added
conformance/lib/mcp/conformance/beacon.ex
conformance/lib/mcp/conformance/manifest.ex
conformance/lib/mcp/conformance/provenance.ex
conformance/lib/mcp/conformance/runner.ex
conformance/lib/mix/tasks/conformance.adjudicate.ex
conformance/lib/mix/tasks/conformance.run.ex
$ diff checks_before.txt checks_after.txt      # 57 enabled checks, unchanged
(empty)
```

### Residual — what is still unchecked

The fix is scoped to `conformance/lib/`, **not** all of `conformance/`. These
four files remain outside gates 1, 2, 3 and 4:

- `conformance/server_adapter.exs`
- `conformance/client_adapter.exs`
- `conformance/server_handler.ex`
- `conformance/request_state.ex`

That is deliberate. MES-46 measured that adding `conformance/` wholesale to
`elixirc_paths` makes gate 2 **exit 1** on those pre-existing adapters. Pulling
them in would be a different ticket's remediation smuggled into MES-51, and
would put MES-51's gates at the mercy of code it did not write.

**They are the measurement instrument for MES-56 and MES-57.** Bringing them
under the gates is worth its own ticket.

---

## S5-2 — `mix credo --debug` leaves an untracked file at the repo root

**Found:** MES-51, 2026-08-20. **Status:** fixed (`/credo-debug-log.html` in `.gitignore`).

`mix credo --debug` writes `credo-debug-log.html` to the repository root. Before
MES-51 this was untidy. After MES-51 it is a **false-red**: a dirty worktree is
now a refusal condition for a conformance run, so running a diagnostic command
would cause the adjudicator to refuse an otherwise good run.

The general shape is worth keeping in mind: **once "clean worktree" becomes a
gate, every command that drops a stray file becomes a gate failure.** A false-red
is not the lesser failure — a gate that fails spuriously teaches people to bypass
it, and a bypassed gate gives exactly the assurance of no gate while still
looking like one.

---

## S5-3 — `plt_add_apps` did not carry `:mix`, so gate 4 could not see Mix tasks

**Found:** MES-51, 2026-08-20. **Status:** fixed (`plt_add_apps: [:ex_unit, :mix]`).

The moment gate 4 (`mix dialyzer`) reached a directory containing Mix tasks, it
reported 9 errors that were nothing to do with the code:

```
Function Mix.shell/0 does not exist.
Function Mix.raise/1 does not exist.
Function Mix.env/0 does not exist.
conformance/lib/mix/tasks/conformance.run.ex:1:callback_info_missing
```

`:mix` was not in the PLT because, until MES-51, no module under `elixirc_paths`
had ever called into `Mix.*` at runtime. Any future ticket that adds a Mix task
to a gate-covered path hits this on its first `mix dialyzer` and can lose time
reading it as a defect in its own code. It is a PLT contents problem, not a type
problem.

---

## S5-4 — The A12 role table still assigns PM-only transitions to CODE_CREATOR

**Found:** MES-51 dispatch (raised by the PM, recorded here for the PO).
**Status:** open — PO's to correct.

The A12 table assigns the *To Do → In Planning* transition to CODE_CREATOR. That
row predates the seat cutover (MES-27, 2026-08-16). `jira_transition` is PM-only
and **server-enforced from the bearer**, so a CODE_CREATOR call is refused before
anything is requested: the row describes an action no CC seat can perform.

The transferable point: **a role table that predates a permissions change becomes
a set of instructions that cannot be followed**, and a seat trying to follow it
burns a turn discovering that. Any procedure table naming an actor and an action
needs re-reading whenever enforcement moves.

---

## S5-5 — Conformance artefacts nest suite scenarios, so a top-level count understates by 4x

**Found:** MES-51, 2026-08-20. **Status:** fixed in MES-51's tooling; **relevant to MES-56/57's denominator.**

The harness's `-o` tree is **not flat**. Most scenarios get a top-level directory,
but a *suite* scenario gets one directory holding all of its members:

```
$ ls /tmp/run | wc -l                                  # top-level entries
39   -> reported as 9 before this was noticed
$ find /tmp/run -name checks.json | wc -l              # actual scenario dirs
39
$ find /tmp/run/auth -name checks.json | wc -l         # inside ONE entry
31
```

A top-level `ls` of a client run returns 9 entries, of which `auth/` alone
contains 31 checks-bearing directories. Counting the top level reports 9 where
the truth is 39 — **understating by a factor of four.**

The transferable point: **any script that enumerates conformance artefacts must
walk recursively and key on the presence of `checks.json`**, which is the
harness's own unit of a scored scenario. MES-49's scratch adjudicator used a
single-level `os.listdir`, so it silently omitted every `auth/*` scenario.

This is a denominator question, and the denominator is the headline of both
MES-56 and MES-57.

---

## S5-6 — The harness exits non-zero on scenario failures, so its exit code cannot be a gate

**Found:** MES-51, 2026-08-20. **Status:** recorded; the field is provenance-only by design.

`conformance server|client` exits **1** whenever any scenario fails. For this SDK
that is the *normal* state of a run, so a provenance check of the form "refuse a
run whose harness exit code is non-zero" would refuse every real run.

MES-51 records `result.harness_exit_code` and explicitly does **not** judge it.
The general shape is worth stating because it nearly went the other way: **a
signal that is non-zero in the healthy case cannot be used as a failure gate**,
and wiring it up anyway produces a control that refuses everything — which fails
exactly as badly as one that never fires, while looking much more diligent.

---

## S5-7 — A check reading a decoded-JSON operand passes when the operand is absent

**Found:** MES-51 review round 1, 2026-08-20. **Status:** fixed in the adjudicator
(`MANIFEST_INCOMPLETE`); the *mechanism* is general and unfixed everywhere else.

The mechanism, which is the transferable part: **in Elixir, a missing key in a
decoded JSON map arrives as `nil`, and `nil` reads as SATISFIED by every operator
a check is likely to use.**

```elixir
nil == 0        # false -> `if count == 0, do: refuse` never fires
nil > 0         # true  -> term order puts every atom above every number
if nil, do: ...  # falsy -> the branch that refuses is skipped
nil or false     # ** (BadBooleanError) -- a crash, not a refusal
```

Only the last of those four is loud. The other three make a check that **passes
because it could not see**, which is indistinguishable, from the output alone,
from a check that ran and found nothing.

Measured on the MES-51 adjudicator before the fix: of the 54 fields its manifest
carries, **47 could be deleted outright and `judge/3` still returned `:ok`** —
one raised instead. Three of those were reported as separate findings; they were
one defect with three visible faces, and fixing the three would have left the
other forty-four.

**What to do instead.** Do not harden the comparisons one at a time — that is the
fix-the-instance-not-the-class trap, and there is no point at which you know you
are done. Establish *completeness of the record* as a precondition, once, before
any comparison runs, and drive it off an enumeration the tests already pin to
what the writer actually writes. Then state the guarantee as a property
("no comparison can be reached with an absent operand"), because a property is
checkable by enumeration over every field and a list of patched instances is not.

**How to test it.** Enumerate. One test that removes *every* field in turn and
requires a refusal each time; one that nulls every judged field and requires a
refusal; and — the half that is easy to forget — one that nulls every
*unjudged* field and requires ACCEPTANCE. Without that third test, "refuse
everything" satisfies the suite, and a control that refuses everything is as
useless as one that never fires.

**Where else this applies.** Anywhere a gate reads structured input it did not
construct in the same process: `checks.json`, harness JSON output, cached
advisory data, a manifest, a config file. The DoD gate-6 false-green on absent
advisory data (see `CLAUDE.md`, "Known limitation 1") is the same shape at a
different layer — a lookup returning `nil` for a missing key, and `nil` read as
"no advisory".

---

## S5-8 — Narrowing a check to cure a false-red can manufacture a false-green

**Found:** MES-51 review round 1, 2026-08-20. **Status:** fixed
(`DIRTY_EXCLUSION_COVERS_ROOT`, plus the collector refusing to apply a covering
exclusion).

The sequence, which recurs whenever a control is tuned:

1. A control fires on a good run (`WORKTREE_DIRTY` refused every run whose
   artefacts landed inside the repository — the run dirtied the tree it was
   measuring). A real false-red, correctly reported.
2. The fix **narrows the control's input**: exclude the run directory from the
   dirty computation.
3. The narrowing has no upper bound. Exclude a path that *equals or contains*
   the repository root and the control is not narrowed but **switched off** —
   measured: `collect_git(root, [root])` returned `dirty: false` on a worktree
   with a modified tracked file.

**A false-red and a false-green are not symmetric, and the asymmetry is the whole
point.** A false-red is loud, blocks, and gets investigated within the hour. A
false-green is silent, and its output gets published. Trading one for the other
is a regression even though the defect count is unchanged.

**The rule.** When a fix narrows a check's scope, the narrowing needs its own
stated bound, and the bound needs its own control. Ask directly: *what is the
largest exclusion this accepts, and what does the check still guarantee at that
size?* If the answer is "nothing", the bound is missing. Both directions must
then be demonstrated — the newly-refused case AND the originally-false-red case
still accepted — because a fix that closes the new hole by reopening the old one
is not a fix.

---

## S5-9 — Gate 6 went green then red on an unchanged tree, and the mechanism is NOT the one CLAUDE.md documents

**Found:** MES-51 correction round 2, 2026-08-20. **Status:** recorded; the
mechanism is unfixed and, as stated below, **unfixable by any local or live
check**. Raised for the PO — it is a third gate-6 limitation, and `CLAUDE.md`
lists two.

### The two measurements

Same branch, same tree, same `mix.lock`, no repository change between them:

```
20:49:39Z   tip 2186343 committed
            ...gates run on it, gate 6b -> EXIT 0
            "No retired or security advisory packages found"
21:01:27Z   that green reported (comment 24956)

21:35:19Z   gate 6b re-run, same lock -> EXIT 1
            bandit 1.12.1: EEF-CVE-2026-74836 (HIGH), EEF-CVE-2026-75484 (MEDIUM)
```

All timestamps UTC, container clock, with the offset written out (R2). The Jira
comment carrying the green is stamped `22:01:27+0100`, which is the same instant
— the two clocks in this project are one hour apart and mixing them has already
manufactured a phantom stall once.

### The correction — this is not a stale cache, and saying so would be the error

The obvious reading, and the one first reported on the ticket, is that this is
`CLAUDE.md`'s **Known limitation 2** observed rather than theorised: a
complete-but-old registry passing while an advisory published since the snapshot
goes unreported. **The timestamps rule that out.** Both advisories were published
upstream *after* the green ran:

```
$ curl -s https://api.osv.dev/v1/vulns/EEF-CVE-2026-74836 | python3 -c 'import sys,json;print(json.load(sys.stdin)["published"])'
2026-08-20T21:11:18.999Z
$ curl -s https://api.osv.dev/v1/vulns/EEF-CVE-2026-75484 | python3 -c 'import sys,json;print(json.load(sys.stdin)["published"])'
2026-08-20T21:11:27.523Z
```

The green run is bounded to `(20:49:39Z, 21:01:27Z)` — after the commit it
audited, before the comment reporting it. Publication is at `21:11:18.999Z`.
Even taking the very latest instant the green could have run, it preceded the
first advisory's publication by **591 seconds**, and publication falls strictly
inside the green→red interval.

So the local cache was not carrying old data. **There was no advisory to carry.**
The gate was *correct* at 21:01 and *correct* at 21:35, and the answer changed
because the world did. Reporting it as a staleness instance would be claiming a
mechanism wider than the measurement supports — this sprint's own central finding,
committed by the person who found it.

The one bound worth stating: hex's advisory rows and the OSV record come from the
same EEF CNA feed (the ids are literally `EEF-CVE-*`, sourced from
`cna.erlef.org/osv/`), so OSV's `published` is being used as the upstream
availability time. hex.pm cannot plausibly have carried the row *before* the CNA
published it, which is the only direction that would reopen the staleness reading.

### The mechanism

**Gate 6's verdict is a function of `(lock, wall-clock)`, not of the commit.**
Every other DoD gate is a pure function of the tree: gates 1–5 give the same
answer on the same commit forever. Gate 6 reads a continuously-updated external
feed, so its verdict carries an implicit *as-of* timestamp that nothing in our
process records and nothing in our process re-checks.

The DoD is written as though greenness were a property of the commit — "six gates
green" — and for gate 6 it is a property of a moment that has already passed by
the time anybody reads the sentence.

### Why the existing compensating controls do not cover it

This is the part that matters, and it is the reason this entry is not a
restatement of a known limitation:

| Control | Covers absent/corrupt data | Covers stale data | Covers **this** |
|---|---|---|---|
| Gate 6a baseline-lock sentinel | 5 of 26 packages | no | **no** |
| Gate 6b `mix hex.audit` | no (limitation 1) | no (limitation 2) | **no** |
| MES-19's live whole-tree OSV cross-check | yes | yes | **no** |

The live OSV cross-check is freshness-independent and cannot be stale-green — and
it would still have returned **green at 21:01**, because at 21:01 OSV had no
record either. **A control cannot report a fact that is not yet true.** No amount
of freshness, fail-closed behaviour, or live querying reaches this; the gap is not
in where the data is read from but in *when the reading is taken*.

### The rule

Separate the two failure modes, because they have different fixes and only one of
them has a fix at all:

- **Freshness** — the data existed and I did not have it. Fixed by refetching, or
  by querying live. This is limitations 1 and 2, and MES-19 covers them.
- **Recency** — the data did not exist yet. Not fixable by any check, however
  live, run at the same instant.

For recency the only available control is **re-running the check at the moment of
the decision it gates**, and treating the earlier verdict as expired rather than
banked. Concretely: a green gate 6 at ticket time is not evidence at merge time,
and a green at merge time is not evidence at publish time. `CLAUDE.md` already
says a release must not treat a green `mix hex.audit` as publish-blocking evidence
on its own; **the same reasoning applies one level down, to the per-ticket gate,
and is not currently written anywhere.**

The transferable shape, beyond this gate: **any verdict derived from an external
feed should be recorded with the timestamp it was taken at, and consumed with an
explicit expiry.** A verdict quoted without its as-of time is being read as a
property of the artefact when it is a property of an instant — which is exactly
the provenance failure the rest of this ticket exists to make detectable, arrived
at from the opposite direction.

### What was done about it here

MES-51 bumped `bandit` 1.12.1 → 1.12.5 under A11.1, which clears both ids and
turns 6b green again. That fixes the instance. **It does not touch the mechanism**,
and the next advisory published against a locked package between one seat's gate
run and the next will reproduce it exactly.

`CLAUDE.md`'s gate-6 text is deliberately **not** edited. Whether the DoD should
carry an as-of stamp or an expiry for gate 6 is a procedure change and therefore
the PO's decision, not a correction round's.

---

## S5-10 — A command's exit status read off a pipeline is `tail`'s, so a sweep harness reports green it cannot not report

**Found:** MES-51 correction round 3, 2026-08-20 — **and found before, on MES-19,
in Sprint 4.** **Status:** both instances corrected in place; the *mechanism* is
recorded here because correcting instances has now failed twice.

This entry exists because the finding **recurred**. It was hit, diagnosed and
written down in Sprint 4, in the same document that argues a green is only as
good as the instrument that produced it, and it was then hit again in Sprint 5 by
a different seat on a different ticket. A defect that survives being found once
is no longer an incident; it is a property of how we write these harnesses, and
it needs an entry with an owner rather than a paragraph inside a gate table.
(I14 — a finding with no owner lapses; A8.)

### The mechanism

In POSIX shells, `$?` after a **pipeline** is the exit status of its **last
stage**. Write the idiomatic capture-and-trim —

```bash
out=$(some_command | tail -1); rc=$?
```

— and `rc` is `tail`'s status. `tail` succeeds whenever it can read its input,
which is always. **`rc` is structurally incapable of being non-zero**, whatever
`some_command` did, however loudly it failed, and whether or not it ran at all.

Measured, all three arms in one script:

```text
$ fail() { echo "some output"; return 7; }

  out=$(fail | tail -1); rc=$?      ->  PIPED    rc=0   out=[some output]
  out=$(fail); rc=$?                ->  DIRECT   rc=7   out=[some output]
  set -o pipefail
  out=$(fail | tail -1); rc=$?      ->  PIPEFAIL rc=7   out=[some output]
```

The first line is the defect: **the output is right and the status is wrong**,
which is what makes it survive review. A reader checking the transcript sees the
correct text of a failure sitting next to `rc=0` and reads the pair as consistent,
because the text is the part they actually look at.

### Instance 1 — MES-19, Sprint 4

`docs/sprint_4_issues.md:5616-5623`. The gate-5 seed sweep was first written
`out=$(mix test --seed $s 2>&1 | tail -2 | tr '\n' ' '); rc=$?`, so `$?` was
`tr`'s. Twenty seeds reported `rc=0` and, as that entry states, **every one of
those twenty numbers was meaningless: that harness could not have reported a
failure** — including the loudest failure available, a suite that will not
compile, which is how the instance is remembered. It was caught one round after
the PM had named the trap by hand (MES-19 comment 24577 item 2).

The sharpest detail is not that it happened but that **the correct shape was
already written down in the same file**, `docs/sprint_4_issues.md:5124-5127`:

```text
  out=$(cmd 2>&1); rc=$?      <- rc of cmd            USED
  cmd 2>&1 | tail -1; rc=$?   <- rc of TAIL, always 0  NOT USED
```

Prose stating the right answer, in the same document, a few hundred lines above
the place it was got wrong. **Documenting a remedy is not the same as making it
unavailable to get wrong**, and this is the evidence for that.

### Instance 2 — MES-51, this ticket

Both of this ticket's `mix test` loops — the 20-seed sweep and the order-dependent
positive control — were first written `out=$(mix test --seed $s | tail -2); code=$?`.
Same construct, same inert column.

**It was caught only because the expected answer was known in advance.** The
control probe is two tests deliberately built so that one order fails; the loop
reported it **7 PASS / 0 FAIL**. Re-measured with the status taken off `mix test`
directly, the same probe is **4 FAIL / 3 PASS**. Nothing about the transcript
looked wrong — 7/0 is a perfectly ordinary-looking result — and it was disbelieved
only because the probe had been constructed to fail. **A control whose output
nobody has independently validated is not evidence** (A7c): had this construct
sat under the sweep alone, where 20/20 green is the expected answer, it would have
been believed.

That the seat that hit it had read neither the MES-19 entry nor comment 24577 is
the point, not an excuse. The construct is what a competent person writes when
they want the last two lines of output and the status, and it will be written
again.

### Instance 3 — the same family, already inside a DoD gate

`CLAUDE.md`'s gate 6a carries the note *"Capture output BEFORE matching
(pipefail-safe — no `grep -q` in a pipe)"* (`CLAUDE.md:164`). Same family,
opposite sign, and it is worth measuring rather than asserting because
`set -o pipefail` is the obvious fix and **it introduces its own false verdict**:

```text
$ set -o pipefail
$ if seq 1 200000 | grep -q '^7$'; then echo "matched, rc=$?"; else echo "NOT matched, rc=$?"; fi
NOT matched, rc=141
```

The value **is** present. `grep -q` exits at the first match, the producer is
killed by `SIGPIPE`, and `pipefail` promotes 141 to the pipeline's status — so a
successful match is reported as a failure. `pipefail` converts this class of
false-green into a **false-red**, which is the safer direction but is still a
wrong answer, and under `set -e` it aborts the run.

Three disguises — an inert sweep column, an inert control column, and a gate
match that must not be piped. The project has now paid for one mechanism three
times.

### The remedy, as a property rather than a patch

**Take the status off the command being measured. Never off a pipeline that wraps
it.** Trim, format and match *afterwards*, from a variable or a file:

```bash
out=$(mix test --seed "$s" 2>&1); rc=$?     # status here, from the real process
echo "$out" | tail -2                        # shaping is a separate statement
```

State it as a property because a property is checkable by reading every capture
site, and "we fixed the two loops in this ticket" is not. `pipefail` is a useful
belt but not the fix: it makes the wrong-status case louder, it does not remove
the coupling between "what I measured" and "what I formatted with", and — per
instance 3 — it creates a fresh way to be wrong.

**The general form, of which this is one case:** a status, count or verdict must
be read from the process that produced the thing being judged. Every layer
between the two — a pipe, a wrapper script, a formatter, a `tee`, a subshell — is
a place the value can be replaced by that layer's own, silently and with the
correct-looking text still attached.

### Consequence for this ticket's own evidence — read this before trusting a column

MES-51's gate-5 seed sweep was produced by the broken harness, so **its exit-status
column is withdrawn and is not quoted anywhere in this ticket.** The sweep evidence
of record is the **enumerated per-seed result line** — 20 seeds, 20 reporting
`13 doctests, 626 tests, 0 failures`, 0 not reporting it (A2d) — which is text
ExUnit printed and does not pass through the capture that was broken. Same verdict;
different, and independently produced, evidence for it.

This is said plainly so that a later reader does not re-derive confidence in a
column that was deliberately withdrawn. **A retracted measurement that is merely
"not mentioned again" gets picked back up**, because absence of a caveat reads as
absence of a problem.

---

## S5-11 — Keeping `OptionParser`'s invalid list does not reject unknown switches; only `strict:` does

**Class.** Absence read as satisfaction, third surface. S5-7 was absence in the
*manifest* (an absent JSON key comparing as satisfied). B2 was absence in the
*artefacts* (a missing scenario directory counting as a passing one). This is
absence in **the operator's own input**: a misspelled pin is silently *no* pin,
so the check that was asked for is never run — while the tool returns its only
success signal.

### The defect

`mix conformance.adjudicate` and `mix conformance.run` both parsed argv with
`OptionParser.parse(argv, switches: ...)` and discarded the third element.
Measured against a good manifest whose commit equalled `HEAD`, all of these
exited **0 ACCEPTED**:

```
--bogus                                    rc=0 ACCEPTED
--allow-dirty            (retired a round ago) rc=0 ACCEPTED
--expect-commit          (no value)        rc=0 ACCEPTED
--expect-comit 000…      (misspelled)      rc=0 ACCEPTED
--expect-requirement-md5 bad (misspelled)  rc=0 ACCEPTED
--diagnose=maybe                           rc=0 ACCEPTED
RUN_DIR /another/dir     (extra positional) rc=0 ACCEPTED
```

The sharp one is the misspelling: `--expect-comit 000…` accepts, while the
correctly spelled `--expect-commit 000…` refuses `COMMIT_MISMATCH`. **One
transposed letter turns a refusal into a green**, on the tool MES-56, MES-57 and
MES-58 gate on.

### The trap — the obvious fix catches 2 of the 6

The natural remedy is "stop discarding the invalid list". **It is not
sufficient, and reading the docs will not tell you so.** Under `switches:`, an
*unknown* switch is not reported invalid — it is discarded silently, together
with the value behind it:

```elixir
OptionParser.parse(["/d", "--expect-comit", "0000"], switches: [expect_commit: :string])
#=> {[], ["/d"], []}          # empty invalid list; the misspelling is simply gone

OptionParser.parse(["/d", "--expect-comit", "0000"], strict:   [expect_commit: :string])
#=> {[], ["/d"], [{"--expect-comit", nil}]}
```

Only a **known** switch given a bad or missing value reaches `invalid`. Of the
six invocations above, `switches:` reports **2**; `strict:` reports **6**.
Enumerated, `switches:` catches `--expect-commit` (no value) and
`--diagnose=maybe`, and misses `--bogus`, `--allow-dirty`, `--expect-comit` and
`--expect-requirement-md5`. A fix built on the invalid list alone would have
left the four misspelling-shaped cases — including the one that reaches a
report — exactly as they were, while looking like a fix.

### The remedy, as a property

**No invalid operator input may produce exit 0.** Not "unknown switches are
warned about", not "the invalid list is checked" — the property is about the
*status*, because a consumer reading only the status cannot see anything that
was printed. It needs three mechanisms together, each covering a hole the others
leave:

1. `strict:` — so an unrecognised switch is an error rather than noise;
2. the invalid list — so a known switch with a missing or ill-typed value fails;
3. a bound on positional arguments — so a stray path is not silently ignored.

Stated **once for the whole tool** (`MCP.Conformance.Argv`), not per call site:
three surfaces found by three different means is enough to assume a fourth.

### A retired flag needs its own message

`--allow-dirty` was removed one round earlier *precisely* so it could not yield
exit 0. Passing it still did, by a different route — unrecognised, discarded,
run accepted on its merits. **Removing a flag does not retire it if an unknown
flag is ignored**; an operator on a stale runbook gets exactly the outcome the
removal was meant to prevent, and gets it silently. Retired switches are named
explicitly and say they were removed on purpose.

### The test that passed for the wrong reason

The regression test guarding the removal asserted exit 1 on a **dirty** manifest,
reasoning "OptionParser drops the unknown switch; the run is refused on its
merits". Both halves were true and the conclusion was still wrong: the run was
refused because it was *dirty*, not because the flag was rejected. On a **clean**
manifest — the case it never tried — the same invocation exited 0 ACCEPTED. **A
test whose subject and whose cause of passing differ is a green that means
nothing.** When a test's outcome would be the same with the feature removed,
it is testing something else.

### Choosing the exit status rather than falling into it

A usage error exits **64** (`EX_USAGE`, sysexits.h), not 1 and not 2. Reaching
for `Mix.raise` would have given 1 by accident, and 1 already means *this run is
inadmissible* — a verdict reached by adjudicating the run. A usage error
adjudicates nothing. Sharing the code would make a caller that reports
"provenance refused" misreport a typo as a provenance failure, and the two want
opposite responses: fix the command line, versus re-run the measurement. **The
bound:** a caller testing only `rc != 0` cannot tell the four statuses apart,
and that is intended — the safety property is that a usage error is never
mistaken for success, not that every consumer distinguishes it.

---

## S5-12 — The client leg prints no scenario→artefact map, because it runs in parallel

**Found:** MES-56, 2026-08-21, by a deliberate smoke run rather than by MES-57
hitting it under time pressure. **Status:** the server-leg parser refuses a
client console outright; choosing the client leg's key is MES-57's design call.

`checks.json` carries **no scenario id** — its `id` is the *check's*. So a census
needs some other key from a scenario to the directory holding its results. On the
**server** leg the console provides one, adjacently and unambiguously:

```
=== Running scenario: tools-list ===
Results saved to /tmp/run/server-tools-list-2026-…Z
```

On the **client** leg that key does not exist. Measured at
`@modelcontextprotocol/conformance@0.2.0-alpha.11`, `client --suite sep-835`:

```
Running sep-835 suite (5 scenarios) in parallel...
Starting scenario: auth/scope-from-www-authenticate
Starting scenario: auth/scope-retry-limit
… all five started …
Results saved to /tmp/…/auth/scope-from-scopes-supported-2026-…Z
Results saved to /tmp/…/auth/scope-from-www-authenticate-2026-…Z
… in COMPLETION order …
```

**The mechanism:** the client path is a single `Promise.all` over every scenario
(`dist/index.js`), so all start lines precede all save lines and the saves come
back in completion order. There is no textual adjacency to pair them by. The
`--requirements` invocation takes the same branch, so this is not an artefact of
using `--suite` for the smoke run. Two smaller differences travel with it: the
header is `Starting scenario:`, not `=== Running scenario: … ===`, and the
summary mark grows an optional `, K warnings` suffix.

**Why this is worth an entry rather than a fix.** Pairing them positionally
*looks* correct — every scenario is accounted for and every directory is used —
and would have mis-attributed **four of five** here, silently. That is the worst
available failure: a complete-looking table that is wrong. The client leg needs a
different key entirely (its directories are `<scenario-id>-<timestamp>` under a
real `auth/` directory, which is parseable *because* the expected id list is
known and ambiguity can be made to refuse), and picking one is a design decision,
not an adjustment. So `MCP.Conformance.Console` **refuses** a client console and
says why. An instrument that cannot attribute what it reads should decline, not
guess.

---

## S5-13 — A scenario that throws is summarised, scored, and leaves no artefact

**Found:** MES-56, 2026-08-21, on the null-implementation control run.
**Status:** handled explicitly in the console parser and the census; the entry
exists because the shape generalises.

Running the suite against a server that answers `-32601` to everything made
`tasks-capability-negotiation` **raise** inside the harness. The harness caught
it, and:

* printed `Failed to run scenario <id>: <message>` and a stack trace;
* synthesised a single `FAILURE` check for it and counted it in the SUMMARY
  (`✗ tasks-capability-negotiation: 0 passed, 1 failed`) and in the not-scored
  block;
* wrote **no artefact directory at all** — 49 directories for 50 scenarios.

**The mechanism, and why it is dangerous:** a census built from the artefact tree
alone is short by exactly the scenarios that crashed, and a crashed scenario is
always a *failing* one — so the omission biases in the **flattering** direction,
which is the direction nobody audits. Worse, the natural repair is worse than the
disease: treating "no `checks.json`" as "no checks, therefore nothing failed"
turns every crash into a pass.

This is S5-5's shape a second time — the artefact tree is not a faithful index of
what ran — and it is the reason the console↔disk consistency check exists. That
check **caught this unprompted**, on its first contact with a run nobody had
designed it against, which is the only kind of evidence that a control is not
unfalsifiable.

Handled by distinguishing three endings for an announced scenario, from the
console's own evidence: `Results saved to` (ran, artefacts present),
`Failed to run scenario <same id>` (ran, threw, no artefacts — recorded, with the
message, and **failing** under every reducer), and neither (unattributable —
still a refusal, so accepting the second case did not switch the check off).

---

## S5-14 — The adjudicator cannot accept a run of any tree that predates it

**Found:** MES-56, 2026-08-21, at plan time, trying to satisfy an AC that asked
for an adjudicated comparison against a Sprint 4 figure. **Status:** structural,
correct, and **not to be fixed**; ruled by the PM as the fingerprint route.

`mix conformance.adjudicate` accepts only a run whose worktree was clean at the
measured commit. A tree that predates the adjudicator does not contain it, so:

* transplanting the tooling into that tree makes the worktree dirty →
  `WORKTREE_DIRTY`;
* pointing `--cwd` at an old worktree → `CWD_NOT_PROJECT_ROOT`.

There is no third route, and **that falls straight out of the requirement rather
than being a bug in it.** The consequence is general and every future
re-measurement of a shipped release will hit it: *no historical figure can ever
be retro-adjudicated.*

**What to do instead** — and the reason this is an entry rather than a defect.
Reconstructing "old tree + new tooling" on a throwaway branch would produce an
*accepted* manifest attesting a tree nobody ever shipped: not weak provenance but
**false** provenance, manufactured by the tool built to prevent it. Compare
**fingerprints** instead: quote the historical side explicitly as a claim under
review rather than as an accepted figure, and compare against everything the old
run recorded — every reducer, the null control, the check-level census, the named
failing scenarios, the failure decomposition — not just the headline. Zero delta
then means *the fingerprints match*, and any drift lands on a named scenario and
check id instead of on a total.

---

## S5-15 — A seat can exit mid-ticket still holding the baton, and neither Jira nor the dispatch log detects it alone

**Found:** MES-56, 2026-08-21, by the PM, when this seat's engine died 49 minutes
into execution. **Status:** unmitigated. Recovered by hand; the recovery is
recorded here because the *recovery move is not the obvious one*.

The EMFA overrides already name seat death as a gap in the abstract. This is an
instance, with timestamps, and it sharpens the abstract statement in two places.

**What happened.** All times UTC, from `/tmp/emfa-seat-dispatch.log`; Jira
renders `+0100`, and mixing the two inflates every interval by an hour.

| UTC | event |
|---|---|
| `00:13:58` | `ASSIGNED` + `PICKUP` MES-56 — 6s after the PM's ratification handoff |
| `01:03:15` | `ENGINE_EXIT ticket=MES-56 rc=0` — no close-out posted, assignee unchanged |
| `01:16:23` | PM posts a resume handoff to `CODE_CREATOR`, who is **already** the assignee |
| — | **no dispatch for 8m35s** |
| `01:24:58` | PM unassigns, then hands off — an assignee *change* |
| `01:25:04` | `ASSIGNED` + `PICKUP` — 6s later |

**Mechanism 1 — the exit is invisible from either source on its own, so
detection requires a join.** From Jira the ticket is In Progress and assigned to
a seat: indistinguishable from one still working, and there is no upper bound on
a legitimate turn against which a stall could be timed out. The dispatch log does
record the exit — but it logs `ENGINE_EXIT rc=0` for a *healthy* end-of-turn
too. This very ticket shows both: the planning turn exited `rc=0` at `00:09:25`,
19 seconds after its handoff landed, and that was correct. **`rc=0` is emitted
whether or not the baton was passed**, so the log alone cannot classify an exit
either. The signal is the conjunction — *an `ENGINE_EXIT` whose ticket is still
assigned to the seat that exited* — and nothing computes it.

**Mechanism 2 — the obvious recovery is a silent no-op, and this is the more
useful half.** The harness dispatches on an assignee **change**, not on a new
comment and not on an `updated` timestamp. So re-sending the handoff to a dead
seat — exactly what a PM who has correctly diagnosed the death would do, and
what `jira_handoff` is *for* — sets the assignee to the value it already holds,
changes nothing, and fires nothing. The 8m35s row above is that no-op. A PM can
diagnose the stall correctly, re-hand the baton correctly, and still wait
forever, with every reason to believe the seat is alive. **Recovery requires
manufacturing an assignee change: unassign, then hand off.**

**What bounded the loss**, since the interesting question is why 49 minutes of
work survived. Two things, and only the first is the usual advice:

* Commits were small and frequent — three on the branch — so what was lost was
  not a session but a single untracked directory.
* That directory was `docs/conformance/`, which is a **projection** of saved run
  artefacts plus committed code, not an original. Regenerating it and diffing
  reproduced all three files byte-identically. The generate-don't-transcribe rule
  adopted for the census against MES-24's drift defect turned out to also make
  the artefact *reconstructible after a crash* — a second, unplanned payoff for
  the same discipline.

The general form: **work is recoverable to the extent it is either committed or
derivable.** An untracked file that is neither is the only thing a mid-ticket
death can actually destroy.

---

## S5-16 — A DoD gate the reviewer cannot run: `node` is on two seats' PATH and not on the third's

**Found:** MES-56 round 1, 2026-08-21, by `CODE_REVIEWER`, when it tried to
reproduce a green gate 5 and could not. **Status:** the dependency is now
declared and excluded-with-a-reason (`:requires_live_harness`); the PATH
difference between seats is unfixed and is not this ticket's to fix.

Three conformance tests shell out to `node` to cross-check our parsing of the
harness's frozen requirement set against the harness's own listing of it. They
pass for `PM` and for `CODE_CREATOR`, whose shells have node v24.13.0 via nvm,
and they raise for `CODE_REVIEWER`, whose shell does not. Same clone, same
commit, same `mix test` — a green gate for two seats and `rc 2` for the third.

**The mechanism is not the missing binary.** It is that the seats share a
repository and *not* an environment, while the review model rests on the
reviewer being able to re-derive what the author claims. After the seat-family
change, authorship separation is the independence property we have left; an
environment difference that silently removes the reviewer's ability to re-run a
gate erodes it exactly as effectively as a shared identity would, and it does so
without anyone deciding to.

**The half that was ours, and is worse.** Two of the three tests already guarded
themselves with `if File.exists?(requirements_yaml)`. On a host with the
requirement set installed and no `node`, that guard passes and the body then
explodes — which is how it was found. On a host with neither, the guard fails,
the body never runs, and the test **reports green having checked nothing**. A
conditional skip written inside a test body is indistinguishable from a pass in
every report the suite produces. That is absence read as satisfaction, inside
the test suite, on the ticket about exactly that.

**The remedy is a tag, not a fixture.** The precondition is declared once
(`MCP.Conformance.TestHarness.unavailable_reason/0`) and `test_helper.exs` turns
it into an exclusion that prints the reason and visibly shortens the suite:
`170 tests, 0 failures (3 excluded)` instead of `173 tests, 0 failures`. Both
directions were measured. Recording the harness output as a fixture was
considered and rejected: the value of those tests is that two *independent*
derivations agree, and a snapshot would compare the parser against itself.

**Transferable form:** *a test that decides for itself whether it can run must
report that decision in the suite's own counters.* A skip that is invisible in
the count is a pass. And when a gate's runnability depends on the host,
**a green from one seat is not evidence for another** until the dependency is
declared.

---

## S5-17 — Fixing the instance does not answer the class: four defects of one shape in one sprint

**Found:** MES-56 round 1, 2026-08-21, by the PM, on being handed the fourth.
**Status:** answered for the census by an enumerated precondition register
(`MCP.Conformance.Census.precondition_register/0`), with tests that fail when a
refusal exists without one.

Four separate defects this sprint were the same defect: **a value computed as
though its precondition held, with nothing said when it did not.**

| # | site | what it computed anyway |
|---|---|---|
| S5-7 | a check reading a decoded-JSON operand | passed when the operand was absent |
| MES-51 | the acceptance block | printed a console hash for a file that did not exist |
| S5-16 | a test guarding itself with `File.exists?` | reported green having checked nothing |
| B1 | the null-control join | printed "ours alone" over scenarios the control never ran |

Each was found separately, fixed separately, and none of the fixes protected the
next site. The reason is that they are not related by *code* — different modules,
different authors, different rounds — but by *shape*, and a shape is not
something a diff review can be relied on to see.

**What the register does that a fix cannot.** It lists every site in the module
whose value rests on a precondition, together with what happens when that
precondition fails, and it lists the sites that are **already correct** — because
"correct" and "never examined" are indistinguishable from outside, which is the
whole complaint. Four dispositions are allowed: `:refuses`, `:refused_upstream`
(named the condition that makes the local default unreachable), `:reported`
(stated why no printed figure can depend on it), and `:degrades` — of which
exactly one site is permitted, is named, and is asserted by a test, so a second
cannot join it quietly.

Writing it found a fifth instance the review had not: an unrecognised check
status had no disposition in any reducer, so it was silently non-failing and
counted as a **pass** under all three at once — and the harness cross-check could
not catch it, because the harness keys on `FAILURE` too and calls it non-failing
as well. Now `CHECK_STATUS_UNKNOWN`.

**Transferable form:** when a defect recurs, the deliverable is *the enumeration
of its class*, not the fix. Ask of every value: what must be true for this to
mean anything, and what does this code do when that is false? Write the answer
down for the sites where it is "nothing" as well as the sites where it is
"refuses" — an unenumerated correct site is a site nobody has checked.

---

## S5-18 — A seed sweep that tails its own output cannot name the failure it found

**Found:** MES-56 round 1, 2026-08-21, on the gate-5 sweep for the correction.
**Status:** the sweep harness now writes one full log per seed; the red it found
is recorded here because it could not be identified afterwards.

The first 20-seed sweep of the round came back **19 green, 1 red** (seed
`1000003`). The harness printed `tail -25` of the failing run's output, which on
this suite is Bandit's shutdown logging — the ExUnit failure block had already
scrolled past. Nothing else was kept, so the failing test's *identity was
destroyed by the harness that detected it*.

Everything after that is weaker than it should have been: seed `1000003` was
re-run 22 times and passed every time, a fresh logged 20-seed sweep was 20/20
green, and 20 further logged runs at other seeds were green — **61 runs, one
red, unidentified and unreproduced**. That is enough to say the suite is not
reliably red, and not enough to say what happened once.

**Mechanism, and it is the S5-10 family.** S5-10 is about a status read off a
pipeline being `tail`'s rather than the command's; this is its sibling — the
status was read correctly, and the *evidence* was piped away. A sweep exists to
turn a rare failure into a caught one, and catching it is worth nothing if the
artefact that names it is discarded in the same breath.

**Rule:** a sweep writes each run's complete output to its own file and reports
paths, never excerpts. Cheap — 20 files, a few hundred KB — and it is the whole
difference between "a flake exists somewhere" and a bug report.

**Left open, deliberately:** an unidentified intermittent failure in this
suite. It is not attributed to this round's changes (they add pure, `async`
conformance tests with no ports or timers) and it is not attributed to anything
else either, because attributing it would require the log this file exists to
say we did not keep.

---

## S5-19 — A precondition register is complete only relative to the question used to build it

**Found:** MES-56 round 2, 2026-08-21, by the CODE_REVIEWER, on a register that
S5-17 had just declared the class answer.
**Status:** the register stands and was extended; what changed is that it is no
longer treated as self-certifying. A second, mechanical question is now part of
writing one.

S5-17 answered a recurring defect by enumerating its class into
`MCP.Conformance.Census.precondition_register/0` — fifteen sites, each with what
it does when its precondition fails, including the sites that were already
right. The register was **complete against the question that built it**, which
was an intent question: *what preconditions does this code have?* Every site the
author could think of was in it.

The reviewer found a sixteenth by asking a different question, and a mechanical
one:

> Trace every `Map.new`, every default (`||`, `Map.get/3`, `Enum.find/3`), and
> every list-to-set conversion. At each, ask: **is this value valid only if some
> input is unique, or complete?**

That question does not need the author's model of the code, and it is the reason
it found what the intent walk missed. `Map.new(parsed.marks, &{&1.scenario, &1})`
keys the harness's own per-scenario verdicts by scenario id. Two marks for one
scenario collapse **last-wins**, silently. A one-scenario run whose console
carried both `✗ tools-list: 0 passed, 1 failed` and `✓ tools-list: 1 passed, 0
failed` was ACCEPTED, keeping the ✓ — *the flattering one* — while the
cross-check reported agreement with a harness verdict it had just discarded.
The register said "every scenario has a mark". It did not say "exactly one, and
no conflicting duplicate", because nobody had asked whether it needed to.

**The sub-shape worth carrying: PAIRED CONCEPTS, one half guarded.**
`Console.parse/1` had always faulted a scenario mapped to two artefact
directories (`duplicate_faults/1`). The SUMMARY block — the other half of the
same "one line per scenario" property, in the same file, feeding the same
cross-check — had nothing. The concept existed, was implemented once, and was
never applied to its sibling. That is fix-the-instance-not-the-class in
miniature, occurring *inside* the register written to prevent it. So: **wherever
a guard exists for one member of a pair, go and look at the other member.**

Running the mechanical question over the whole converter found **five more**
accepting cases, each measured on a run the tooling accepted before the guard
and refuses after:

| site | the input it assumed | what it did instead of refusing |
|---|---|---|
| `Console.marks/1` | one SUMMARY mark per scenario | kept the last; the ✗ vanished (B2) |
| `Console.marks/1` | no mark without a scenario | ignored a mark for a scenario that never ran |
| `Console.not_scored/1` | one not-scored line per scenario | kept both; the reason became order-dependent |
| `Console.totals/1` | one `Total:` line, one label each | read the first line, kept the last label |
| `RequirementSet` scored/not-scored lists | each id listed once | `expected_counts.scored = 2` over a one-scenario set, with `absentees.scored = []` |
| `Census` leg → frozen set | the leg is one the set defines | `Map.get(…, leg, [])` gave an empty denominator; 0 of 0 rendered as a complete census |
| `Classification` table | the three sources do not overlap | `Map.merge/2` silently kept the harness entry over ours |

Two are worth naming beyond the table. The `RequirementSet` one is the **AC2
denominator vouching for a total it had inflated itself** — and its own
yaml-versus-listing cross-check could not catch it, because that check compares
`MapSet`s, and a `MapSet` discards multiplicity along with the order it was
written to ignore. The `Classification` one is B2's exact sentence in another
file: a duplicate collapses last-wins, and the winner is the entry that says
failing the scenario "costs nothing against the conformance denominator", so the
owned `:real_gap` is the half that disappears.

**Negatives, enumerated, because a negative is the evidence the pass was made.**
The same trace cleared: `Map.new(@reducers, …)`, `Map.new(@statuses, …)`,
`Map.new(Map.keys(@reducers), …)`, `Map.new(@statuses ++ ["total"], …)` and
`Map.new(Classification.classes(), …)` — every key a literal of this codebase's,
unique by construction and asserted by an existing test; the four sites keying on
scenario id (`by_id` twice, a `Map.keys` difference, one `Enum.find`), which
`duplicate_faults/1` has always refused upstream; `Beacon.read/2`'s
`Enum.uniq`, which collapses multiplicity but keeps the count in a separate
field and feeds an existential test; `counts/1`'s `|| "ABSENT"` and
`Map.merge/3` adder, both closed by `CHECK_STATUS_UNKNOWN`; and
`Manifest.refusal_codes/0`'s `Enum.find_index`, over a literal list.

One site was examined and **deliberately left unguarded**: an *absent* `Total:`
line does not fault. Multiplicity and absence are not the same hazard —
multiplicity means two contradictory values with one chosen silently, absence
means no value, and `%{}` is visibly empty to whoever reads it. Guarding it
would be a bound with nothing behind it.

**Transferable form.** A register is an artefact of the question that produced
it, and its completeness claim is only ever relative to that question. Build one
with at least two questions, and let one of them be mechanical enough that it
does not consult your model of the code: *grep the collapse points, then ask
what each one assumes*. Where the answers differ, the second question is the one
that found something.

---

## S5-20 — A stated property with nothing checking the code against it yields one sibling defect per review round

**Found:** MES-56 round 3, 2026-08-21, by the CODE_REVIEWER; the *class* named by
the PM in the round-4 correction contract.
**Status:** closed by construction — the property is now a table over a set the
code itself defines, and completing that table is the terminating condition.

### The defect

`MCP.Conformance.Console`'s `parse/1` moduledoc has asserted a **universal**
property since it was written:

> A console is well-formed only if every scenario it names appears exactly once
> in each block that names scenarios.

Its bullet list also claimed the membership half for one block ("a SUMMARY mark
for a scenario that never ran"). The code satisfied that claim for **three** of
the four blocks `parse/1` returns, and rounds 2 and 3 each found one more block
it was false of:

| round | block | half that was missing |
|---|---|---|
| 2 (B2) | `marks` | multiplicity, then membership |
| 3 (B3) | `not_scored` | membership |

Neither was a guard someone forgot. Both were **a stated property with nothing
comparing it against the code** — and the thing absent was the doc-to-code
check itself, so its absence read as satisfaction. That is this sprint's
recurring defect one level up (S5-17, S5-19).

### Why patching does not terminate

Round 2 fixed the block the reviewer named and swept for more, using the
reviewer's question. Round 3 asked the *same* question and found the next
sibling. A review round that fixes the named instance and sweeps by the same
question can always yield exactly one more instance, because the sweep's
boundary is the sweeper's model of the code rather than anything the code
declares. Rounds 1, 2 and 3 produced 1, 6 and 1 findings, with no round able to
say it was the last.

### The close, and why it terminates

The enumeration is taken over a set **the code defines rather than the author
chooses**: the four content blocks `parse/1` itself returns
(`mappings`, `marks`, `not_scored`, `totals`). For each, both guarantees are
stated in the moduledoc as a table, and every cell must be one of

* *enforced by* a named function,
* *vacuous* for a stated reason (`mappings` **are** the ground truth membership
  is checked against),
* *bounded* for a stated reason (the client leg has no scenario headers, so
  every mark and every not-scored line is an orphan by construction and
  `parallel_leg_faults/1` refuses that console whole).

A cell that is none of the three is a defect, and the table makes it visible in
the source rather than a review round later. When the table is complete there is
no next sibling for the question to find, because the question's domain is the
return map.

> **Superseded in part, MES-56 round 5 — see S5-21.** This entry originally
> gave `totals` as a second *vacuous* example, on the ground that it keys on
> status labels and never on scenario ids. The premise is true and the
> conclusion was not: a label is still a key, and `total_parts/1` accepted any
> lowercase word. That cell is now *enforced*. More importantly, "the question's
> domain is the return map" fixes the domain and leaves the **arity** free, and
> the register one arity up was not closed at all.

Completing it also opened one guarantee **the table does not itself state**:
`marks` and `not_scored` both carry a ✓/✗ for the *same* scenario, and nothing
compared them, so a console could mark a scenario ✗ in one block and ✓ in the
other while satisfying every cell. That is the duplicate-mark defect spread
across two blocks. Guarded in the same round rather than discovered in the next
one — which is what "closed by construction" is supposed to buy.

### The layering, which is a separate ruling

B3 named two different membership questions and they belong in different
modules:

| question | authority | where |
|---|---|---|
| does this not-scored line name a scenario that **ran**? | intra-console | `Console.orphan_not_scored_faults/3` |
| does the **frozen set** agree this scenario is not scored, and for the same reason? | console vs. requirement set | `Census.corroborate_not_scored/3` (`NOT_SCORED_DISAGREES_WITH_FROZEN_SET`) |

`RequirementSet` is deliberately **not** imported into the parser: a parser that
imports its own referee can no longer be used to check the referee. Both halves
are needed — the intra-console guard catches a not-scored line for a scenario
that never ran, and only the cross-authority one catches a not-scored line for a
scenario that ran and that the frozen set **scores**, which is the flattering
direction (a scenario leaving the scored denominator by an edit to a text file
the census reads and never cross-examines).

### Transferable form

A universal claim in a doc comment is a **specification with no test**. Where
one exists, discharge it as a table over a set the code declares — a return map,
a struct's fields, a behaviour's callbacks — not over a list of places worth
looking at. Then the register is closed by construction, and the convergence
signal is *"the table is complete"* rather than *"this round found nothing"*,
which is a claim no round can make.

---

## S5-21 — A register closed over items is not closed over their joins, and the arity has to be argued rather than climbed one round at a time

**Found:** MES-56 round 4, 2026-08-21, by the CODE_REVIEWER.
**Status:** closed by construction — both registers are now enumerations over
sets the code defines, and the moduledoc states why there is no third.

### The defect

S5-20 closed a universal doc claim by turning it into a table over a **closed**
set: the four blocks `MCP.Conformance.Console.parse/1` returns, two guarantees
each, eight cells, every cell *enforced-by* / *vacuous-because* /
*bounded-because*. The round-4 close-out then claimed closure "in your sense…
the question has no undiscovered instance to find, because its domain is the
return value".

That claim was true of what it enumerated and **false of the register one arity
up**. The eight cells say what is true of each block *on its own*. The blocks
are reducers over one run, so they also constrain *each other*, and a console
can satisfy all eight cells and still be one the harness could not have printed.
Measured: a console whose SUMMARY marks sum to 1 passed / 0 failed while its
`Total:` line states 0 passed / 1 failed satisfies every cell, parses with
`faults: []`, and the census **ACCEPTS** it.

### Why it is the same mechanism as S5-20, one level up

S5-20's lesson was "do not enumerate over a set you chose; enumerate over a set
the code declares". Round 4 did that — and then picked the **arity** by hand.
Unary properties were enumerated exhaustively; binary ones were not enumerated
at all, so the first join anyone looked at was unguarded. Choosing the arity is
choosing the domain again, in the one dimension the closed set does not fix.

Climbing one arity per review round does not terminate either, for exactly the
reason S5-20 gives: each round's boundary is that round's model of the code.

### The close, and why it terminates

Two things, and the second is the one that ends it:

1. **Enumerate the next register too** — four blocks, six unordered pairs, no
   pair omitted, each *guarded-by* or *vacuous-because*. Four of the six were
   already guarded; one (`marks × totals`) was the measured defect above and is
   now `total_sum_faults/3`; two are vacuous for stated reasons.
2. **Argue the arity, in the source.** Take a census of what the blocks carry —
   scenario id, verdict, check counts, an aggregate of those counts, directory,
   reason. A consistency property has content only where a value is derivable
   from more than one block. Membership is always stated against one
   distinguished set, so a three-way membership claim is the conjunction of two
   pairs (transitivity, not a new property); agreement needs two carriers of one
   value and no value has three. A genuine triple needs a **hyperedge** — a
   value derivable jointly from three blocks and from no two of them — and the
   census shows there is none. The same census answers every higher arity,
   because it is an enumeration rather than a search.

The terminating condition is therefore not "round 5 found nothing" but "the
arity argument is stated and its premise is a census over the return map".

### Transferable form

When you discharge a universal claim as a register over a closed set, **state
the register's arity and defend it in the same breath**. A per-item register is
evidence about items; it is silent about joins, and joins are where reducers
over one source disagree. Either show that the n-ary case decomposes into the
(n−1)-ary one — usually by finding the shared value and showing it has at most
two carriers — or enumerate the next register too. A closure claim that does not
name its arity is a closure claim about a domain the reader has to guess.

---

## S5-22 — A hand-built accept-half control can be an artefact the source could never emit, and then it proves less than it appears to

**Found:** MES-56 round 5, 2026-08-21, by the CODE_CREATOR — by the guard added
in the same round refusing the round's own controls.
**Status:** fixed; three probe directories and one test fixture rebuilt, and the
fixture now computes the fields the harness computes.

### The defect

Adding `total_sum_faults/3` (S5-21) immediately refused two things that were
supposed to be **accept halves**:

* `/tmp/mes56r4-ns-clean`, the round-4 accept-half control for the not-scored
  cross-authority guard, and the two refusal probes derived from it. Its
  SUMMARY marks sum to 1 passed / 1 failed; its `Total:` line said
  1 passed / 0 failed. The harness cannot print that — it computes the second by
  summing the first;
* the census test's console fixture, which generated its SUMMARY block from the
  run's scenarios and then stated `Total: 3 passed, 2 failed` as a **constant**.
  Correct for the default run, wrong for every test that passes a subset.

Both were accepted for as long as nothing compared the two blocks. The moment
something did, they were revealed as consoles no run could have produced.

### Why it matters more than a broken fixture

The two derived probes — "the console omits a not-scored scenario that ran" and
"the two authorities give different reasons" — were published in round 4 as
evidence that `NOT_SCORED_DISAGREES_WITH_FROZEN_SET` fires. After the new guard
they refused **earlier**, on the incoherent total, and so no longer reached the
guard they existed to exercise. A refusal control that refuses for the wrong
reason still looks green in a table of refusals.

The same applies in the flattering direction: an **accept**-half control built
by hand is an assertion that the instrument accepts something. If the something
is unreachable from the source, the assertion is about nothing.

### The close

Every fixture field the harness *computes* is now computed in the fixture too —
the `Total:` line from the marks it prints, the opening scenario count from the
scenarios it announces, the not-scored header's failing count from the entries
it lists. A control that spoils one field corrects the fields the harness would
have recomputed, so the forgery is internally coherent and the guard under test
is the one that has to catch it. That is a strictly stronger control: it must
now catch a console nothing else can tell is wrong.

### Transferable form

A control is only as good as the fidelity of the artefact it is built from. For
every field of a synthetic fixture, ask whether the *producer* derives it from
another field; if so, derive it in the fixture too, and have a spoiling probe
correct the derived fields it disturbs. Otherwise the first guard that checks
the derivation will silently re-point your whole control set at itself — and the
table of refusals will not change colour when it does.
