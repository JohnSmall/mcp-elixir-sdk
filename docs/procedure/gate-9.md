# Gate 9 — the ET-CC register drift check (MES-241)

> **Written by MES-241.** The gate's list item is in `CLAUDE.md`, *Definition-of-Done Gates*;
> "the gate-8 form" is gate 8's applicability rule there (three dots, `--no-renames`). The
> trigger command's home is the fenced block under *Applicability* below; `CLAUDE.md` carries
> a byte-identical copy, and `test/conformance/gate_9_trigger_test.exs` holds the two equal
> and runs the command against a git fixture. The instrument is `mix conformance.register_drift`
> (`MCP.Conformance.RegisterDrift`); its controls are
> `conformance/controls/register_drift_controls.exs`.

**PO ruling, 2026-11-17** (MES-241 comment 35681). The register check is a
Definition-of-Done gate, gate 9, not only a review-checklist item (Q1, Option A), and its
trigger is the full register-input regex below, not `^test/mcp/` alone (Q3).
**Why:** since MES-229 the generator reproduces `docs/conformance/etcc-register.json` byte
for byte, and nothing on a ticket checked that it still would after the ticket. Measured on
the MES-241 plan (comment 35676, at `beca615`): the `keysets` control was green on every
planted change, because it reads only the committed rows file; `reproduce` missed a test
appended at the end of a file and a new doctest example in `lib/`, because neither moves an
existing row; and gate 5 missed a rename and the end-append. Each of those changes the
register once the suite is re-captured.

## What it checks

`mix conformance.register_drift` captures the suite at HEAD (`mix test --seed 0` into a
private temporary directory, the MES-240 capture), refuses a capture that fails any of the
rows-drift guards RD1-RD9, and then runs three steps:

- **reproduce** — build the register from the committed inputs and compare its bytes with
  the committed register (the `reproduce` control, through the writer's own encoder).
- **keysets** — the three key-set equalities of the `keysets` control. A diagnostic: when
  `reproduce` is green it cannot be red, because the build refuses a key-set or partition
  failure.
- **fresh** — build the register from the FRESH capture, with the same decisions, boundaries
  and sources, and compare its rows with the committed register's rows, key by key and field
  by field. This is the step that sees an added, renamed or deleted unit, and a new doctest:
  the build refuses a unit with no decision, and a decision with no unit.

A build refusal in either build is drift, and the refusal's message is printed. `out_of_scope`,
the totals and the provenance are not compared (see *Stated residuals*).

## Applicability — the gate-8 form

Three dots and `--no-renames`, with this exact command (`CLAUDE.md` item 9 carries the same
bytes):

```bash
git diff --no-renames --name-only main...{TICKET_KEY} | grep -E '^(mix\.exs$|config/|lib/|test/mcp/|test/support/|test/test_helper\.exs$|docs/conformance/etcc-(register|exunit-rows)\.json$|conformance/data/etcc-(decisions|boundaries)\.json$|conformance/lib/mcp/conformance/(etcc_register|unit_locator|exunit_rows|boundary_sweep|rows_drift|register_drift)\.ex$|conformance/lib/mix/tasks/conformance\.register_drift\.ex$)'
```

Each alternation is there because a change to that path can move the register or the check:

- `mix.exs` (root) — `test_paths`, `test_pattern`, `test_load_filters`, `test_ignore_filters`
  and `elixirc_paths` decide which files the suite loads. Measured by CODE_REVIEWER on
  MES-241 (comment 35688): a `test_load_filters` that drops `header_mirror_test.exs` left this
  trigger silent while the forced gate went red ("38 decision(s) name a key that is not an
  in-scope unit"). Added in correction round 1 (PM 35691), applying the Q3 ruling.
- `config/` — Mix loads `config/config.exs` when it exists, and ExUnit reads its application
  environment, so `config :ex_unit, exclude: [:etcc]` selects the population. Measured on
  MES-241 at `beca615`, in a scratch clone: `mix test test/mcp/protocol/header_mirror_test.exs`
  ran 34 tests with no `config/`, and 18 with 20 excluded with that one-line `config/config.exs`.
  There is no `config/` at `beca615`.
- `test/support/` — compiled into the test environment (`elixirc_paths(:test)`), so a macro
  there can declare or name tests. At `beca615` it holds no `defmacro` and no `test "`, so
  this alternation is precautionary; 3 of the last 20 tickets touched it, and each of those
  also matched `test/mcp/`.
- `lib/` — doctest units are keyed `(N)` by the `iex>` examples of a module a `test/mcp/`
  file doctests, so a new example is a new unit (MES-241 plant P7). All of `lib/`, not a
  list of doctested modules: such a list would have to follow the `doctest` directives, and
  a stale list fails silent. This alternation assumes that every module doctested from
  `test/mcp/` is defined under `lib/`. On each gate-9 run, refusal guard RT5 checks the
  doctested modules' names and their suite-end compile sources against `lib/`; it does not
  establish the assumption in full (see *Running it* and residual 8).
- `test/mcp/` — the register's population (`ETCCRegister`'s in-scope prefix). Names, lines,
  additions and deletions all reach it.
- `test/test_helper.exs` — it attaches the rows formatter and owns the exclusions, so it
  decides which units a capture records.
- `docs/conformance/etcc-register.json`, `docs/conformance/etcc-exunit-rows.json` — the
  register itself, and the committed rows file it is built from.
- `conformance/data/etcc-decisions.json`, `conformance/data/etcc-boundaries.json` — the
  authored decisions, and the boundaries table the build checks every decision against.
- `conformance/lib/mcp/conformance/` `etcc_register.ex` (the generator), `unit_locator.ex`
  (it locates every test row's line), `exunit_rows.ex` (the capture formatter),
  `boundary_sweep.ex` (`check_table!`, which the build runs), `rows_drift.ex` (the capture
  and the RD guards this gate uses) and `register_drift.ex` (this gate).
- `conformance/lib/mix/tasks/conformance.register_drift.ex` — this gate's task.

Swept and left out, each with its reason (MES-241 correction round 1):

- `test/conformance/` — its own tests are keyed only into `out_of_scope`, which this gate does
  not compare; test code there can still change in-scope doctest units without firing the
  trigger (residual 8, MES-248).
- `mix.lock` — no dependency declares or names a test here: ExUnit ships with Elixir, and no
  test uses a test-declaring macro from a dependency (no `property` or `check all` under
  `test/`). Gates 6 and 7 own a lock change.
- `.formatter.exs`, `.credo.exs` — formatting and lint only; neither is read by `mix test`.
- `test/fixtures/` — data that tests read; it cannot declare a test.
- `conformance/request_state.ex` — loaded by `test/mcp/conformance_request_state_test.exs`
  with `Code.require_file`, but it declares no tests and has no `iex>` examples, and no
  `test/mcp/` file doctests it. A `test/mcp/` change that adds such a doctest fires gate 9,
  and RT5 refuses a doctested module whose suite-end compile source is outside `lib/` (below).
- The Elixir and OTP versions and the environment (`MIX_ENV`, environment variables) — not
  paths, so no trigger can name them (residual 7).

**The merge's version bump is not on the branch.** The PM's squash-merge writes the new
`@version` into `mix.exs` on `main`; the branch never carries it, so the three-dot diff does
not list `mix.exs` for it. Over the 20 merged tickets MES-215 to MES-240, one changed `mix.exs`
on the branch beyond `@version` (MES-227, the dependency bump: two lines).
**When a new register input or generator file appears, this regex is extended in the same
ticket**, here and in `CLAUDE.md` together (the trigger test fails if they differ), with a
firing case and a mutation for it in `gate_9_trigger_test.exs`.

No match ⇒ skip it and say so in the close-out ("gate 9 not applicable, no register input
change"). Measured over the 20 merged tickets MES-215 to MES-240, with the merge's version
bump left out: 15 match this regex (14 before `mix.exs`, `config/` and `test/support/` were
added; MES-227 is the fifteenth), and 7 match `^(lib/|test/mcp/)` alone.

## Running it

With the branch checked out and the tree **clean** (a dirty tree is refused RD6), and with
`node` on `PATH` (a host that excludes the live-harness tests is refused RD5):

```
mix conformance.register_drift
```

`--keep FILE` writes the adjudicated capture, `run.suite_rc` included, to FILE (keep it outside
the tree); `--fresh FILE` adjudicates an existing capture instead of capturing; `--json OUT`
writes the `etcc-register-drift/1` report.

**A capture is judged only at its own commit** (correction round 1, CR findings R1 and R2).
Before anything is compared, the capture must pass every rows-drift guard (RD1-RD9) and three
of this gate's own: **RT1**, its `run.tip` is the current `HEAD`; **RT2**, the tree being
judged is clean now (`git status --porcelain` empty), whatever the capture recorded; **RT3**,
it carries an integer `run.suite_rc`, which RD7 reads. So a `--fresh` replay of a capture from
another commit, over a dirty tree, or with the suite's exit status lost, is refused. Neither output may name
the committed rows file or the register by any route (literally, through a symlinked parent,
or a hard link): that exits 64 before anything runs, and the check is made again at the
write itself.

**Verdict forms.** The last line is the verdict:

- `register-drift: CLEAN - reproduce ok, keysets ok, fresh ok`, exit **0**: the gate passes.
- `register-drift: DRIFT - …`, exit **1**: each red step is listed above it, with the build's
  refusal or the differing keys and fields.
- `register-drift: REFUSED - RDn (a refusal is not a clean result)`, exit **2**: the capture
  failed its guard, and nothing was compared. A red suite is RD7: fix gate 5 first. RT1-RT3
  are the same form for a capture of another commit, a dirty tree, or no `suite_rc`. RT5 is
  the same form for a failed doctest check (below).
- `register-drift: REFUSED - RT4 (…)`, exit **2**: the instrument failed. An exception in a
  build that is neither one of the generator's `REFUSING to write` refusals nor a `File.Error`
  with reason `:enoent` on an in-scope test source (under `test/mcp/`) that the committed
  register or the rows that build read name (a test file that moved or went) is printed with
  its type and is no verdict on the register. So `:eacces`, `:emfile`, or `:enoent` on any
  other path, including one only an `out_of_scope` row names, is RT4, not drift (CR finding R4,
  narrowed in correction rounds 2 and 3).
- exit **64**: a usage error or a protected output path. Nothing was run.

**RT5, the doctest check, read from the capture** (correction round 3, PM ruling on CR finding
R5, after two rounds of source scanners each missed legal forms: a qualified
`ExUnit.DocTest.doctest/1`, an attribute reassigned inside `if`, `require ..., as:`). Every
in-scope row of the capture whose `test_type` is `doctest` must name, in its test name
(`doctest Mod.fun/arity (n)` or `doctest module Mod (n)`) and in ExUnit's own `doctest` tag
where present, a module that a `defmodule` under `lib/` defines (read from `lib/**/*.ex` by
AST). **And the doctested module, as loaded at suite end, must have been compiled from `lib/`**
(correction round 4, PM ruling on CR's shadow case, a byte-copy of `HeaderMirror` compiled from
`conformance/` and loaded by a `test_helper.exs` hook, which a name check accepts). The capture
records, read inside the test VM when the suite finishes, each doctested module's
`module_info(:compile)[:source]` in the run-level field `run.doctest_sources`; its real path
must be a regular file under this repository's `lib/`.
That field cannot move the register: the build reads only the rows and `run.rows_md5`, which
hashes the rows alone, and neither the committed rows file nor the register changes
(`reproduce` stays identical). An unparseable name, a name and tag that disagree, a name no
`lib/` defmodule defines, no recorded source, or a source elsewhere is refused with the module
named. A test build compiled at another path (copied `_build`) is refused too, fail-closed:
recompile in the tree being judged. **What RT5 establishes, exactly:** the compile source of
each doctested module as loaded at suite end, read in the test VM. It does NOT establish which
definition DocTest expanded its units from: test code that loads an outside definition, lets
DocTest expand from it, and reloads the `lib/` module before the suite ends is not detected
(CR 35837; residual 8, hardening ticketed as MES-248). **What that leaves:** when gate 9 runs,
an outside suite-end source is refused by RT5. A definition swapped mid-run is not seen by
RT5, and such a swap needs test code. A hook in `test/mcp/`, `test/support/` or
`test/test_helper.exs` fires gate 9; a hook elsewhere, for example in `test/conformance/`
(CR 35914, a live fixture), does not. Either way it is a reviewable change under D7, but gate 9
itself does not guarantee to see it.

**Cost:** one capture, 122-140 s over nine captures on the MES-241 plan, plus about 1 s for
the steps. It falls twice per applicable ticket: CODE_CREATOR at the close-out and
CODE_REVIEWER at review.

## When it is red

- **A move only** (lines shifted, nothing added, renamed or removed): rebuild the register,
  `mix run conformance/build_etcc_register.exs`, and commit it. This is mechanical. Measured
  on the plan: a three-line insertion changed 12 register lines; after the rebuild
  `reproduce` was identical and the fresh step had no changed row. Then run G33 with
  `--repin` if gate 5 asks for it.
- **A unit added, renamed or deleted, or a doctest example added:** re-capture the rows file
  (`mix conformance.rows_drift --keep FILE`, which keeps the formatter's own bytes, then copy
  FILE over `docs/conformance/etcc-exunit-rows.json` by hand; gate 9's `--keep` adds
  `suite_rc`, which a committed rows file does not carry), author, re-key or remove its decision
  in `conformance/data/etcc-decisions.json`, and rebuild the register. **This is not
  mechanical.** A new unit needs a membership judgement under
  `docs/conformance/etcc-membership.md`, and a new ET-CC member brings the MES-231 cascade
  with it (the attribution file, crosswalk G24, the D2a-ii and D3+D6 records, G33). A rename
  is close to mechanical: re-key the decision and anything that cites the old key.
- **The re-capture caveat (MES-247).** Until MES-247 lands, `main`'s committed rows file is
  behind the suite under `test/conformance/` (31 added, 294 relined, 6 refielded at `dec37c2`).
  A re-capture on any branch brings that drift in with it, and the register's
  `out_of_scope` grows to match on the rebuild. Gate 9 itself is green at `main` regardless,
  because that drift reaches only `out_of_scope`. MES-247 does not block this gate.

## Stated residuals — what gate 9 does not see

1. **`out_of_scope`.** It holds only `test/conformance/` keys and is not compared, so a change
   to `test/conformance/`'s own tests is invisible here (plant P1 stays green). The
   end-of-sprint rows-drift sweep owns it (`docs/procedure/end-of-sprint.md`, step 6). Test code
   there can still change in-scope doctest units without firing the trigger (residual 8,
   MES-248).
2. **A body-only change.** Rows carry no body hash, so a test whose name, file and line are
   unchanged reads as no change. Gate 7 sees body changes.
3. **A red or partial suite.** The capture is refused (RD7, RD3), so a tree that fails gate 5
   cannot be checked until gate 5 is green.
4. **A host without `node`.** Refused RD5, visibly; the gate could not run there.
5. **Totals and provenance.** Not compared in the fresh step: the in-scope totals are a
   function of the rows, and the provenance carries the capture's own md5. `reproduce`
   compares both, byte for byte, for the committed inputs.
6. **A path outside the trigger.** A change that moves the register through a path the regex
   does not name is not checked on its ticket. The regex is to be extended when such a path
   is found (see *Applicability*).
7. **The environment.** The Elixir or OTP version, `MIX_ENV` and environment variables can
   change what ExUnit runs, and no path names them. The capture records `elixir` and `otp`;
   an exclusion shows as RD5.
8. **A definition swapped during the run** (CR 35837, MES-248). RT5 reads each doctested
   module's compile source at suite end. Test code that loads an outside definition, lets
   DocTest expand from it and then reloads the `lib/` module passes RT5. A hook in
   `test/mcp/`, `test/support/` or `test/test_helper.exs` fires gate 9; a hook elsewhere, for
   example in `test/conformance/` (CR 35914), does not fire it at all. Either way the hook is a
   reviewable change under D7; gate 9 does not guarantee to see it. MES-248's hardening must
   also cover hooks outside the trigger paths.

## Controls

- `mix run conformance/controls/register_drift_controls.exs all` — six modes, each in its
  own VM, in a clone of the committed HEAD. **plants** (P0-P11, each step adjudicated on its
  reason class: the four ticket cases, the end-append, a doctest example, the doctest
  directive moved, a `test/conformance/`-only change that must stay 0, register hand-edits,
  and a renamed test file whose register was rebuilt without the rows file); **guards**
  (RD1-RD9, RT1-RT3, RT5 (including a stripped `doctest_sources` and a `lib/` name compiled
  outside `lib/`) and the false-green route FG through the real task; RT4 by injected
  exceptions: an ArgumentError, a non-REFUSING RuntimeError, and File.Error `:eacces`,
  `:emfile`, an uncited `:enoent`, an `:enoent` on a `test/conformance/` file and one on a path
  a planted `out_of_scope` row names; and advertised-equals-exercised);
  **neverwrite** (both protected files, every route, and the at-write re-check);
  **mutation** (M1, M2, M4, M6a, M6b, M7, MP, MT1-MT3, MK, MR4, MR4f, MR4s, MT5, MT5n (the
  name-only fallback) and MR4n killed; M3 and M5 stated
  equivalent, M3's equivalence measured on every case); **live** (two real captures: one at
  HEAD, exit 0, replayed clean at HEAD and refused RT1 after a commit and RT2 over a dirty
  tree; one of a suite that exits 7 with every row green, refused RD7 live and on replay, and
  RT3 with `suite_rc` stripped); **livedoc** (one real capture of a `test/mcp/` file that
  doctests three modules outside `lib/` by a qualified call, a reassigned attribute and an
  attribute, and a `lib/` module through `require ..., as:`: refused RT5 naming the three, not
  the `lib/` one; and a second capture of CR's shadow, refused RT5 alone with the recorded source
  `conformance/cr_header_mirror.ex`). `all` takes about twelve minutes; a seat whose foreground calls stop at 600 s
  runs the modes one by one, which is what `all` does in separate VMs.
- `mix test test/conformance/gate_9_trigger_test.exs` (in gate 5) — the trigger command,
  extracted from this page, against a git fixture: every alternation fires, near-misses and
  non-inputs stay silent, a rename counts, a `main`-only change does not, and a mutation of
  the command flips each case.

## Merge-gate checklist item (cite this subsection from the review brief)

> **ET-CC register drift check (gate 9).** Run the applicability diff and paste it. If it
> applies, check out `{TICKET_KEY}` with a clean tree and `node` on `PATH`, run
> `mix conformance.register_drift` (a live capture, not a `--fresh` replay of someone else's
> file) and paste its output. Adjudicate on the **last line** and
> the exit status: a pass is exit 0 with a last line beginning `register-drift: CLEAN`. A last
> line beginning `register-drift: DRIFT` or `register-drift: REFUSED`, any other exit, or no
> `register-drift:` line at all is a fail. For a DRIFT, check that the branch's remedy matches
> *When it is red*: a rebuild for a move; a re-capture, a decision and a rebuild for a new,
> renamed or deleted unit. If it cannot run at your seat, report **that**, and do not record
> the check as done.

## Evidence

The close-out quotes the applicability diff and its output, then the command, its full
output and its exit status. A skipped gate is stated as "gate 9 not applicable, no register
input change", with the diff that shows it.
