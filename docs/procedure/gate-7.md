# Gate 7 — the official-conformance cross-check (MES-160)

> **Moved verbatim from `CLAUDE.md` by MES-177** (lines 314-501 at e74bf3f; headings promoted
> one level). "The gate-6 pattern" and "for the reason gate 6 gives" are gate 6's
> applicability rule in `CLAUDE.md`, *Definition-of-Done Gates*; gate 5 is in the same list.
> "The applicability diff above" and "the disclosed exception above" are on this page.

**PO ruling, 2026-09-27.** Cases where our tests are green and the official
conformance (OC) check is red are caught **when a test is written**, not by a later
global scan. **The rule: a test may not merge green if it asserts behaviour that a red
OC check contradicts.** Rulings Q1-Q8 on MES-160 (comment `30166`).

**Applicability — the gate-6 pattern.** Gate 7 runs when, and only when, the branch
changes a path under `test/`, `lib/` or `conformance/`:

```bash
git diff --name-only main...{TICKET_KEY} | grep -E '^(test|lib|conformance)/'
```

Three dots, for the reason gate 6 gives. No match ⇒ **skip gate 7 and say so in the
close-out** ("gate 7 not applicable, no test/, lib/ or conformance/ change"). The task
applies the same rule itself and prints `OC-GATE N/A`, so running it on an inapplicable
branch is harmless. `conformance/` is in the trigger (MES-160 N2) because an adapter or
runner edit can move a live check either way.

**The declaration, at writing time.** Every test the branch **adds or changes** in a
`test/**/*_test.exs` file carries, directly above it:

```elixir
@tag oc: "oc:<leg>/<scenario>/<check_id>/<name>[#<discriminator>]"
@tag oc: ["oc:…", "oc:…"]                   # several checks: ALL must be SUCCESS
@tag oc: :none
@tag oc_reason: "<one line: why no OC check corresponds>"
@tag oc: "oc:none/<reason-slug>/<native-id>"   # the existing form; its slug is the reason
```

- **New** = the `{file, describe, name}` identity is absent at the merge-base (a
  rename, or a moved file, is new). A `for`-generated test's identity is its name
  **template**. Everything is read from **git objects**, never the working tree
  (`MCP.Conformance.OcGateDeclarations`), and line/column metadata is stripped first, so
  a reindent is never a change, and neither is a move that crosses no context statement.
  A move that **does** cross one is a change: see `[changed: position]`.
- **Changed** — the output names which of four causes applied (the first that does):
  - `[changed: body]` — the test's context pattern or body differs;
  - `[changed: tags]` — the `@tag`s that attach to the test differ, **including
    `oc:` and `oc_reason:`**, so a re-declared test is re-verified live (MES-160 PJ);
  - `[changed: file]` — **anything in the file outside the test calls and their tags
    differs**: a module attribute, a `defp` helper, `setup`/`setup_all`,
    `describe`-level code, `use` options, a `@moduledoc`, or the head of a `for` that
    generates tests. **Then every test in the file is changed and must carry a
    declaration** (ruled conservative on MES-160 correction round 1). It over-refuses
    by design. It is also what makes a `for`-generated test visible: a new generator
    element, or a new row in the `@attribute` a generator reads, adds a test ExUnit
    will register while the template identity stays the same — the file context is
    what moved. Adding or deleting a test (with its tags) does **not** move the file
    context. **What that costs, in figures** (measured 2026-09-27 at `c8978f4` by the
    gate's own reader — declarations, a `for` template counting once — with ExUnit's
    registered count in brackets): `test/conformance/adjudications_test.exs` **285**
    (298), `crosswalk_test.exs` **135** (135), `match_key_test.exs` **77** (77),
    `manifest_test.exs` **45** (65). So a non-test edit to one of these files — and
    D-work tickets routinely edit the pins in `adjudications_test.exs` — means
    declaring **every** test in it: 285 declarations for that file alone. Tickets that
    touch such a file should plan for that before they start.
  - `[changed: position]` — the test's **slot** moved: the path of blocks enclosing it,
    or the number of context statements (anything but a test call and its tags) before
    it in its own block. A move across a module-attribute redefinition —
    `@x 1; test a; @x 2` to `@x 1; @x 2; test a` — leaves the file context equal but
    changes what the test reads (MES-160 correction round 2, B3; a real shape here:
    `adjudications_test.exs` redefines `@locator` and `@crosswalk`). Only context
    statements count, so adding or deleting a test still moves no **other** test.
- **Refused before any measurement:** `untagged`; `none_without_reason`; `malformed`
  (not a literal, not a token, a `:none` inside a list); `suite_level_tag`
  (`@moduletag`/`@describetag oc:` — the declaration is per test).
- **The discriminator.** Where one check id yields several rows, the token carries
  `#<discriminator>` (`InScope.key_checks/3`'s ratified rule). Today that is
  `HttpServerMetaInvalid400` ×3, told apart only by `details.fieldIssue`
  (`#missing-meta`, `#missing-protocol-version`, `#missing-client-capabilities`). A
  bare token there is refused as `ambiguous`, naming the three.

**The measurement, live on the branch.** For every leg a token names, the task runs the
leg **whole** through the canonical `mix conformance.run` path (`--requirements
2026-07-28`) against the working tree, and the run must pass the census's provenance
judgement pinned to the branch tip **and to the pinned harness build** — `dist/index.js`
sha256 `a10085d0…` (`MCP.Conformance.HarnessHost.pinned_dist_sha256/0`, the one constant
`BucketZero` also cites) — before any figure is read. **The committed census is never
consulted** — it can be stale. A token passes only when it resolves to exactly
one row **and** that row is `SUCCESS`. **`WARNING` and `SKIPPED` are refused like
`FAILURE`** (Q1): a check that cannot be SUCCESS cannot vouch for a test — declare
`oc: :none` with an `oc_reason` citing it. When the branch changes `lib/` or
`conformance/`, every test **already** carrying `@tag oc:` check tokens is re-measured
too (Q5, N2), so a `lib/`- or adapter-only change cannot silently redden an
earlier-tagged test's check.

**Red check ⇒ no merge.** If a named check is red, the branch includes the `lib/` fix
that turns it green, or the test does not merge. There is no known-red path: gate 5
already forbids knowingly red tests.

**The one disclosed exception (PO ruling, MES-161 comment `30342`).** A **pre-existing**
test (not `[new]`) whose **assertions are unchanged** may merge as `oc: :none` while a
red OC check contradicts it, provided that **(a)** any body change is limited to request
construction the branch's own `lib/` fix requires, **(b)** any tag change is limited to
the `oc:`/`oc_reason:` declaration, and **(c)** the `oc_reason` names the red check, the
ticket that owns its fix, and the ruling (`MES-161 30342`). A new test, or one whose
assertions change, still cannot merge. Gate 7 does **not** check this mechanically — a
`:none` declaration measures nothing — so it is the reviewer's, on the checklist item
below.

**Fail-closed.** No `node` on PATH, no harness at `/tmp/conf11`, a harness whose
`dist/index.js` is not the pinned build, a runner that raises, exits or throws, a run the adjudicator
refuses, a scenario that threw or was not run, an unresolvable ref, a HEAD that is not
the branch tip, a dirty tree: each is a **refusal**, never a skip, and each still ends
on the one `OC-GATE` final line. The harness is
required **when a check token needs measuring**; a branch whose declarations are all
`:none` measures nothing and needs no harness — that is not a skip, there is nothing
to run. **The exit status corresponds to the verdict** — 0 for `OC-GATE PASS` and
`OC-GATE N/A`, 1 for `OC-GATE REFUSE (n)` — and the controls hold that; adjudicate on
the final line all the same, because it names what was measured.

**Cost, measured on the CC seat 2026-09-27 (warm build; a cold compile is shared with
gates 2 and 5):** a branch whose tokens name both legs — **10.2-10.3 s** in the task
(client leg 6.0 s, server leg 4.1-4.2 s, each including its provenance judgement), two
runs; one leg **~6 s**; a branch declaring only `:none` **~0.5 s** wall (32
declarations, no leg run). Reading declarations over the whole test tree is ~0.2 s.

**Stated residuals — what gate 7 does not see.**
- **Doctests** (Q3): their content lives in `lib/`; a `test/` diff cannot see it change.
- **`test/support/`** (Q7): a helper change does not make the tests that call it
  "changed".
- **A `@tag` placed before a `for`** is applied by ExUnit to the first generated test
  only; the reader applies it to none (it is file context), so every generated test
  is refused as untagged. The error is in the refusing direction; put the tag inside
  the block.
- **A test file that reads from outside itself.** The file-context rule sees only the
  file's own bytes. A `for` whose enumerable is computed by `lib/`, `test/support/`
  or the filesystem can gain an iteration — a new ExUnit test — with no byte of the
  file moving. Measured on MES-160: of the **8** `for` blocks under `test/` that
  generate tests, **1** is of this kind —
  `test/conformance/adjudications_test.exs` enumerates
  `File.ls!("docs/conformance/adjudications")`, so a new record file adds a test the
  gate cannot see. The other 7 read literals or in-file attributes, and are covered.
- **The live run measures the branch tip, not the squash onto a moved `main`.** It is
  inherent to a per-branch gate; under strict-sequential flow branches are 0 behind.
- **Existing tests are not rescanned** except through Q5: the D records map them, and
  their remediation is ticketed separately.
- **Semantic sameness** is the author's declaration and the reviewer's check. The gate
  proves that the named check is green, not that the test asserts what the check
  measures — that is the MatchKey residual, unchanged.

## Merge-gate checklist item (cite this subsection from the review brief)

> **OC cross-check (gate 7).** Run the applicability diff above and paste it. If it
> applies, check out `{TICKET_KEY}` with a clean tree, run
> `mix conformance.oc_gate {TICKET_KEY}` and paste its output. For each new or changed
> test, check that the declared check (or `oc: :none` reason) is the honest counterpart
> of what the test asserts — the gate cannot. For any `oc: :none` that invokes the
> disclosed exception above, check conditions (a)-(c) against the diff: assertions
> unchanged, body change only request construction, tag change only the declaration,
> and the reason naming the red check, its owning ticket and `MES-161 30342`. If it
> cannot run at your seat (no `node`, no harness), report **that**, and do not record
> the check as done.

## Evidence

`conformance/controls/oc_gate_controls.exs` — each case builds a branch in a throwaway
clone of the repository, plants the thing the gate refuses, drives the real task with
live legs, and requires the named guard to refuse **by its class in the output**, with
the exit status corresponding to the final line: **P1** a SUCCESS check passes (the
positive control); **NA**; **R1** untagged new test; **R2** an existing test's body
changed, untagged; **R3** tagged to a SKIPPED-by-design check; **R3b** tagged to a check
that is FAILURE in the live run (found in that run, not hardcoded); **R4** a
nonexistent check; **R5** `:none` without a reason; **R6a/R6b** harness absent and
`node` absent; **R7** the fieldIssue tie without `#`; **R8a/R8b** HEAD not the tip, and a
dirty tree; **R9** an unresolvable key; **R10** `@moduletag oc:`. Added on correction
round 1: **PA** one row appended to the real `manifest_test.exs` `@pairs`; **PE** a
legacy untagged `for` gaining a generator element; **PB** only a module attribute
changed; **PC** only a same-file `defp` helper changed — all four refused as
`[changed: file]  untagged`; **PJ** a green-tagged test re-tagged onto a SKIPPED check
with no body edit (`[changed: tags]`, `not_success`); **R6c** a harness copy whose dist
has one comment line appended, refused as `run_not_accepted` naming the pinned sha;
**N1** a runner that raises, refused as `run_not_accepted` with the final line intact;
**N3a/N3b** a `lib/`-only branch re-measuring an existing oc-tagged test, green passing
and SKIPPED refused. Added on correction round 2: **PO** a test moved across a
module-attribute redefinition, no statement's bytes changed, refused as
`[changed: position]  untagged`. The `mutation` mode commits one change to the gate's own source per
case, in the clone, and requires the named case to go red (M1-M11; M7 file context
ignored → PA, M8 tags not fingerprinted → PJ, M9 pin not passed → R6c, M10 no
re-measure → N3b, M11 position slot not compared → PO). **Two cases have a second, independent layer, and go red on the
named guard's absent message, not on the verdict:** under **M5** (the HEAD-is-tip check
removed) the run is still refused, by the census's `COMMIT_MISMATCH`; under **M3** (the
harness precondition skipped) the runner completes with no harness and the census
refuses the run as `MANIFEST_INCOMPLETE` (a null `harness.dist_sha256`). Units: `test/conformance/oc_gate_declarations_test.exs`
(including a cross-check of the reader against ExUnit's own runtime tags) and
`test/conformance/oc_gate_test.exs`, both covered by gate 5.
