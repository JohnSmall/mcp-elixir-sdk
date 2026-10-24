# Gate 8 — the ET-CC anchor check (MES-175)

> **Written by MES-175; trigger widened by MES-180.** The gate's list item is in `CLAUDE.md`,
> *Definition-of-Done Gates*; "the gate-6 form" is gate 6's applicability rule there. The
> trigger command's home is the fenced block under *Applicability* below; `CLAUDE.md` carries
> a byte-identical copy, and `test/conformance/gate_8_trigger_test.exs` holds the two equal.
> Guards 23-27 are `MCP.Conformance.BoundarySweep.check_table!/2`; the population refusal
> and the `ETCC-VERIFY` verdict line are MES-179's.

**PO ruling, 2026-10-11.** `mix conformance.sweep --verify` is a Definition-of-Done gate
for every ticket whose branch changes `lib/` — a gate, not only a review-checklist item.
**Widened 2026-10-12** (PO ruling, MES-96 comment 32057, Q5; MES-180): it also applies when
the branch changes the ET-CC boundary table or a guard source, the files `--verify` reads its
verdict from.
**Why:** GUARD 26 went red on `main` because MES-161 (Meta) and MES-157 (Plug) edited the
`lib/` lines two ET-CC `mutation_spec` entries anchor on, and nothing noticed until the
Sprint 13 end-of-sprint sweep refused to run (MES-171). `--verify` resolves the anchors
against the tree in under a second, so that breakage is caught on the ticket that causes
it.

**What it checks.** The five table guards, in order, against
`conformance/data/etcc-boundaries.json`:

- **23** — every direction with a live count of zero carries an L2 record;
- **24** — every DEAD direction's mutation reddened at least one of its own units;
- **25** — every DEAD direction carries both L2 conjuncts (byte probe and call-site
  enumeration);
- **26** — every `mutation_spec` entry's FROM occurs in its file exactly as many times as
  recorded. **This is the one guard that reads the tree**; at `b5b277e` all 194 entries,
  over 50 directions, name files under `lib/`;
- **27** — every `mutation_spec` entry renders back to its committed `mutation` prose,
  byte for byte, in order and in count; and, since MES-173, records `occurrences` as a
  **positive integer**, whatever the direction's verdict. A zero-site mutation replaces
  nothing, so it reddens nothing and establishes nothing. Guard 24 checks DEAD rows only,
  and guard 26 passes a recorded 0 whose FROM is indeed absent, so before MES-173 a 0 on a
  LIVE row was seen by no guard. The pass line and the five scanned keys are unchanged.

**Applicability — the gate-6 form**, three dots, with this exact command (`CLAUDE.md`
item 8 carries the same bytes):

```bash
git diff --no-renames --name-only main...{TICKET_KEY} | grep -E '^(lib/|conformance/data/etcc-boundaries\.json$|conformance/lib/mcp/conformance/boundary_sweep\.ex$|conformance/lib/mix/tasks/conformance\.sweep\.ex$)'
```

It fires on any path under `lib/` (guard 26 reads it), and on exactly three files:
`conformance/data/etcc-boundaries.json`, the table guards 23-27 judge;
`conformance/lib/mcp/conformance/boundary_sweep.ex`, the guards; and
`conformance/lib/mix/tasks/conformance.sweep.ex`, the task that runs them. The caret makes
every alternative match from the start of the path (`x/lib/a.ex` does not fire); the `$`
makes each file an exact path (`etcc-boundaries.json.bak` does not fire); the dots are
escaped. **`--no-renames`** departs from the gate-6 form on purpose: with git's default
rename detection, a branch that only renames the table lists the new path alone, so the
trigger stays silent while `--verify` refuses with `File.Error` (case RE); with it, the old
path is listed too (MES-180 Q1). No match ⇒ skip it and say so in the close-out ("gate 8 not
applicable, no lib/, table or guard change").

**Why a documented diff and not an `N/A` in the task** (MES-175 AC4, PM-ratified). The
task runs in about 0.6 s and is harmless on any tree: on an inapplicable branch it is
simply green, so a self-applied `N/A` would protect nothing. `oc_gate` applies its own
rule because an inapplicable run there would cost leg runs and a harness, and it refuses
on HEAD and tree state. A ticket argument would also be a `conformance/lib/` change
needing its own controls.

**Run it** from the ticket's worktree, with `{TICKET_KEY}` checked out and the tree clean:

```bash
mix conformance.sweep --verify
```

**Verdict forms, and the exit status** (MES-179; re-measured 2026-10-22 at `d9aaff1`, and
held by the `verify` control below). **The verdict is the last non-blank line.**

- **Pass** — exit **0**, and the last line is

  ```
  ETCC-VERIFY PASS (scanned 23:29 24:19 25:19 26:194 27:194; mutation_spec total 194)
  ```

  (the counts as at `d9aaff1`). Above it, unchanged: `GUARDS 23-27 — no violation.`, the
  five scanned counts and a note; compile output (`Compiling N files`, `Generated …`) may
  come first. The counts are the positive control, and **the task refuses them itself**
  (`MCP.Conformance.BoundarySweep.check_population!/2`): any scanned count of **zero**, or
  a `guard_26_scanned` / `guard_27_scanned` other than the table's `mutation_spec` entry
  total, counted by the task from the decoded table outside the guards, is a
  `POPULATION` refusal. An optional cross-check of that total, independent of the
  instrument:

  ```bash
  python3 -I -c 'import json;d=json.load(open("conformance/data/etcc-boundaries.json"));print(sum(len(b.get("mutation_spec") or []) for b in d["boundaries"]))'
  ```

  (**194** at `d9aaff1`).
- **Fail** — exit **1**. The original exception, throw or exit is printed in full, stack
  trace included, and the last line names the kind:
  - `** (Mix) ETCC-VERIFY REFUSE: GUARD n`, **n = 23-27 only**, after
    `** (RuntimeError) GUARD n: …` naming the guard and the entries;
  - `** (Mix) ETCC-VERIFY REFUSE: POPULATION`, after `** (RuntimeError) POPULATION: …`
    naming the limb and the keys;
  - `** (Mix) ETCC-VERIFY REFUSE: ERROR <exception>`, for any other exception — `ERROR
    File.Error` when the table is missing, and `ERROR RuntimeError` for a RuntimeError
    that is not one of the five guards' (`GUARD 999: …`, case G999);
  - `** (Mix) ETCC-VERIFY REFUSE: THROW`, after `** (throw) …`, and
    `** (Mix) ETCC-VERIFY REFUSE: EXIT`, after `** (exit) …`. `exit(:normal)` is caught
    too: uncaught, it ends mix at status 0 with no verdict line (MES-179 round 1, F1).

  A `lib/` or `conformance/lib/` file that does not compile stops mix before the task
  runs: exit 1, a `** (CompileError)` line and **no** `ETCC-VERIFY` line. That is a fail.

  **The boundary of the last-line promise.** Two things are outside it. `System.halt/1`
  ends the VM where no `try` can see it, so it prints no verdict and its status is
  whatever it was given. And output that an `at_exit` callback writes after the verdict
  becomes the last line; a reader judging on the last line already rejects it, because
  that line is not `ETCC-VERIFY PASS`.

**The three population limbs, and what they do not see** (PM rulings, MES-179 comments
34240 and 34253). They run in this order, each with its own message:

- **Shape.** Each of `guard_23_scanned` … `guard_27_scanned` must be present and a
  non-negative integer. A missing key, a negative value, a non-integer or `:skipped`
  refuses as `POPULATION: --verify refuses a malformed scan: <key> <value>`, the value
  `absent` for a missing key. With the zero limb, every count must be a positive integer
  (round 1, F3). No table can produce a malformed scan today, so its controls plant the
  scan's return (S1 `-1`, S2 an absent key, S3 `:skipped`) or the call (EQ1,
  `check_tree: false`, which makes guard 26 `:skipped`).

- **Zero.** Any of the five counts at 0 refuses. It closes the vacuous pass CR found on
  MES-175 (case RF: `boundaries` emptied, counts `0/0/0/0/0`, exit 0) and two partial ones
  measured on MES-179: every DEAD row deleted (`10/0/0/76/76`) and every `mutation_spec`
  removed with its prose (`29/19/19/0/0`). **Residual:** a future table that legitimately
  has no DEAD direction refuses gate 8 until the code changes. Fail-closed by ruling (Q2).
- **Equality.** `guard_26_scanned` and `guard_27_scanned` must each equal the total; the
  two halves are checked, and controlled, separately. **This limb is entailed by today's
  scan**: guards 26 and 27 `flat_map` over every entry, so no table can fire it. It is a
  tripwire against a future scan that skips or short-counts, and its controls plant the
  instrument, not the table (EQ2 for 26, EQ3 for 27; Q3).
- **Residual: a table short by whole rows.** Deleting a row that leaves no count at zero
  passes all three limbs (case RS1: `29/19/19/193/193`, total 193, exit 0). Only a floor from
  outside the table would see it, and nothing compares the table with its committed
  history (Q1). The `verify` control pins RS1 as passing, so a change is seen.

| case | planted, on a throwaway copy | exit | last line |
|---|---|---|---|
| G0 | nothing | 0 | `ETCC-VERIFY PASS (scanned 23:29 24:19 25:19 26:194 27:194; mutation_spec total 194)` |
| NA | a comment appended to `lib/mcp/client.ex`, no anchor touched | 0 | the same |
| RA | the `MCP.Client` anchor `Jason.decode!(Jason.encode!(struct))` edited to `Jason.decode!( Jason.encode!(struct))` | 1 | `… REFUSE: GUARD 26` (`has 0, spec records 1`) |
| RA′ | the same anchor edited so the file does not compile | 1 | `** (CompileError) …` — no `ETCC-VERIFY` line |
| RB | the same anchor appended a second time, as a comment | 1 | `… REFUSE: GUARD 26` (`has 2, spec records 1`) |
| RC | `" x"` appended to the first `mutation` prose line of the first row with a `mutation_spec` | 1 | `… REFUSE: GUARD 27` (`do not render back`) |
| RZ2 | a LIVE row's first entry made zero-site, its prose rendered to match | 1 | `… REFUSE: GUARD 27` (`positive integer occurrences`) |
| RD | `l2` removed from the first LIVE row with a live count of zero | 1 | `… REFUSE: GUARD 23` |
| R24 | the first DEAD row made impotent | 1 | `… REFUSE: GUARD 24` |
| R25 | the first DEAD row's `byte_probe` removed | 1 | `… REFUSE: GUARD 25` |
| RE | the table file moved away | 1 | `… REFUSE: ERROR File.Error` |
| RF | the table's `boundaries` emptied (CR, MES-175 round 1) | 1 | `… REFUSE: POPULATION` (zero) |
| RS2 | every DEAD row deleted | 1 | `… REFUSE: POPULATION` (zero) |
| RS4 | every `mutation_spec` and its `mutation` prose removed | 1 | `… REFUSE: POPULATION` (zero) |
| EQ1 | instrument plant: the task calls `check_table!` with `check_tree: false` | 1 | `… REFUSE: POPULATION` (shape: `guard_26_scanned :skipped`) |
| EQ2 | instrument plant: guard 26's scan counts one short | 1 | `… REFUSE: POPULATION` (`guard_26_scanned 193`) |
| EQ3 | instrument plant: guard 27's scan counts one short | 1 | `… REFUSE: POPULATION` (`guard_27_scanned 193`) |
| S1 | instrument plant: the scan returns `guard_23_scanned` -1 | 1 | `… REFUSE: POPULATION` (shape: `guard_23_scanned -1`) |
| S2 | instrument plant: the scan returns no `guard_24_scanned` | 1 | `… REFUSE: POPULATION` (shape: `guard_24_scanned absent`) |
| S3 | instrument plant: the scan returns `guard_25_scanned` `:skipped` | 1 | `… REFUSE: POPULATION` (shape: `guard_25_scanned :skipped`) |
| THROW | instrument plant: `verify/0` throws | 1 | `… REFUSE: THROW` |
| EXIT | instrument plant: `verify/0` calls `exit(:normal)` | 1 | `… REFUSE: EXIT` (exit 0 before round 1) |
| G999 | instrument plant: `verify/0` raises `"GUARD 999: …"` | 1 | `… REFUSE: ERROR RuntimeError` |
| RS1 | the first row deleted — **the residual** | 0 | `ETCC-VERIFY PASS (… 26:193 27:193; mutation_spec total 193)` |

Exit 0 occurred if and only if `GUARDS 23-27 — no violation.` and the `ETCC-VERIFY PASS`
line were printed, in every case. Before MES-179 RF, RS2 and RS4 exited 0. To re-run a
case by hand: copy the worktree, **remove the copy's `.git` link first** (a copied worktree
shares the original's index), plant the change, run the task, then delete the copy. The
`verify` control does exactly that.

**Cost, measured on the CC seat 2026-10-11** (Elixir 1.19.5 / OTP 28): warm
**569 / 601 / 570 ms** (three runs); **793-830 ms** after a one-file `lib/` edit, recompile
included; **29.5 s** cold (no `_build`) — the project compile gates 2 and 5 already pay.

**Stated residuals — what gate 8 does not see.**
1. **Anchors, not liveness.** A `lib/` change that leaves every anchor in place but
   changes whether a unit can see the mutation is invisible here. Liveness stays with the
   end-of-sprint sweep (`docs/procedure/end-of-sprint.md`, step 4), whose L2 half MES-174
   repaired.
2. **Count, not meaning.** Guard 26 compares occurrence counts. An edit that keeps FROM's
   count but changes what it means, or moves it into a different function, passes. On the
   repair side, MES-173 closed the tool path: `--emit-spec` used to re-count every entry,
   turning 26/27 green without re-anchoring, and now keeps an existing entry as recorded
   and refuses (`GUARD 26: --emit-spec refuses to re-count`) when the tree no longer
   matches it. **Residual:** "existing" means present in the table as read. Deleting a
   row's `mutation_spec`, or hand-editing a recorded count, then emitting still derives
   afresh (PM ruling, MES-173 comment 34227, Q2); the review is what sees that.
3. **First failure only.** The guards raise in order, 23 to 27, so a second violation
   shows only after the first is fixed. Re-run until green.
4. **Working tree, not git objects.** Guard 26 reads files relative to the cwd. The task
   checks neither that HEAD is the branch tip nor that the tree is clean (gate 7 refuses
   both), so "branch checked out, tree clean" is a rule the person running it keeps.
5. **Resolved by MES-180: the trigger was `lib/` alone.** Guards 23, 24, 25 and 27 are
   functions of the table alone; only 26 also reads the tree, so a branch that changed only
   `conformance/data/etcc-boundaries.json` or the guard sources skipped gate 8. Both
   measured cases were of that shape: **MES-171** re-anchored the table and **MES-174**
   regenerated it, neither touching `lib/`. The PO widened the trigger on 2026-10-12
   (MES-96 comment 32057, Q5); the command under *Applicability* covers both.
6. **An unresolvable ref reads as "not applicable".** A mistyped key, a deleted branch or
   the wrong directory makes `git diff` print `fatal:` to stderr and list nothing; `grep`
   exits 1 with empty output — the same as a branch that touches none of the paths. The
   gate-6 and gate-7 forms share this (S9-23 is the D7 guard's case of it), and so does
   their rename blind spot that `--no-renames` closes here; the cross-gate remedy is a
   PM-raised backlog ticket. `gate_8_trigger_test.exs` pins the behaviour as observed
   (case E1), so a change to it is seen. Check the diff's stderr before reading an empty
   result as a skip.
7. **The guard sources are three files, as measured at `98c2519`.** `--verify` reaches
   only the task's `verify/0` and `boundaries/0` and `BoundarySweep`'s `paths/0`,
   `check_table!/2` and its five `check_*` functions, which call no other project module.
   Two things outside the trigger can still break it: guard code moved into a **new**
   module, which the trigger would not see until the list is widened; and `mix.exs`
   `elixirc_paths`, which decides whether `conformance/lib` compiles at all (gate 6's
   trigger, not gate 8's). Neither is checked mechanically.

**Repairing a red GUARD 26.** The branch re-anchors the entry to the behaviour its
mutation targets, as MES-171 did, re-establishing the mutation against that behaviour. It
does **not** re-count the entry to match the tree — that is MES-173's hazard, and it turns
the guard green while the verdict it supports has expired. `--emit-spec` refuses to
re-count since MES-173, so a re-count now has to be made by hand: edit the prose and its
`mutation_spec` entry together, then measure with `mix conformance.sweep --check --only ID`.

## Merge-gate checklist item (cite this subsection from the review brief)

> **ET-CC anchor check (gate 8).** Run the applicability diff and paste it. If it
> applies, check out `{TICKET_KEY}` with a clean tree, run `mix conformance.sweep --verify`
> and paste its output. Adjudicate on the **last line**: a pass is exit 0 with a last line
> beginning `ETCC-VERIFY PASS` (`ETCC-VERIFY PASS (scanned 23:29 24:19 25:19 26:194 27:194;
> mutation_spec total 194)` at `d9aaff1`). Since MES-179 the task itself refuses a scanned count
> that is missing or not a positive integer, and a guard 26/27 count that differs from the
> table's `mutation_spec` total. Any other last line is a fail:
> `** (Mix) ETCC-VERIFY REFUSE: GUARD n`, `… REFUSE: POPULATION`,
> `… REFUSE: ERROR <exception>`, `… REFUSE: THROW`, `… REFUSE: EXIT`, or no `ETCC-VERIFY`
> line at all (a compile error). For a red GUARD 26, check that the branch re-anchors the entry to the
> behaviour its mutation targets (MES-171) and does not merely re-count it (MES-173). If
> it cannot run at your seat, report **that**, and do not record the check as done.

## Evidence

`conformance/controls/etcc_boundary_sweep_controls.exs emit` (MES-173) — `--emit-spec`
never re-counts, and guard 27's positivity refuses through every caller: `check_table!/2`
with the tree check on and off, `emit_spec/1`, `apply!/1`, and the task driven in process
(W2 plants a duplicate anchor in `lib/mcp/protocol/meta.ex`, refuses to start unless
`lib/` is clean, and halts non-zero if the restore does not compare equal).
`... emit-mutation` undoes each new refusal in memory, requires the limbs holding it to go
red, then requires them green on the restored source.

`conformance/controls/etcc_boundary_sweep_controls.exs guards` — each guard broken on a
copy of the table, and the refusal required: **12/12** guard mutations fired, the unmutated
table passes, reach 50 rows; exit 0, 0.82 s at `b5b277e`. MES-173 adds two guard-27 cases
(a recorded 0 on a LIVE row and on a DEAD row), so the mode reports **14/14**. It calls `check_table!/1`
directly, not the task; the task is `verify`'s.

`conformance/controls/etcc_boundary_sweep_controls.exs verify` (MES-179) drives the
**task** in its own OS process (`System.cmd("env", ["-i", …, "mix", "conformance.sweep",
"--verify"])`, so the status is mix's own, with no pipeline) against a throwaway copy of
the worktree with its `.git` link removed: the 23 cases in the table above (RA′ aside),
every plant restored byte-exactly in the copy. It refuses to start unless `git status
--porcelain` is empty, and halts 1 if the real table's sha256 or the porcelain output
moved. Each case is held on exit 0 ⇔ the pass line, exit 0 ⇔ a last line of
`ETCC-VERIFY PASS`, and its own verdict: a pass's exact line, with the counts counted by
the control from the planted table; a refusal's original message, a stack trace, and the
`ETCC-VERIFY REFUSE` line for its own guard.
`... verify-mutation` plants 19 mutants (V0, V23-V26, V27r, V27p, VZ, VE26, VE27, VS, VP,
VX, VL, VN, VR, VF, VCT, VCE) into the copy's instrument, each anchor required at exactly
one occurrence. It requires every control a mutant names to go red, the controls it names
as unaffected to stay green (VE26 keeps EQ3, VE27 keeps EQ2), and then all of them
green on the restored bytes.

`test/conformance/gate_8_trigger_test.exs` (MES-180, under gate 5) — the trigger command,
extracted from this page and required byte-identical in `CLAUDE.md`, run against a throwaway
git repository: it fires on a `lib/` change (F1), on each of the three files separately
(F2a-F2c) and on a rename of the table (F3); it stays silent on unrelated `conformance/`
paths (U1), on near-miss paths (N1-N5) and on a `lib/` change that only `main` made (B1).
Each case is shown able to fail by a named in-memory mutation of the extracted command
(M1-M8), and the retired `lib/`-only grep is required absent from every tracked file except
the sprint registers (`docs/sprint_*_issues.md`, historical records).
