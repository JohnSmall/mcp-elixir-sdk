# Gate 8 — the ET-CC anchor check (MES-175)

> **Written by MES-175.** The gate's list item and its applicability rule are in
> `CLAUDE.md`, *Definition-of-Done Gates*; "the gate-6 form" is gate 6's applicability rule
> there. Guards 23-27 are `MCP.Conformance.BoundarySweep.check_table!/2`.

**PO ruling, 2026-10-11.** `mix conformance.sweep --verify` is a Definition-of-Done gate
for every ticket whose branch changes `lib/` — a gate, not only a review-checklist item.
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
  byte for byte, in order and in count.

**Applicability — the gate-6 form**, three dots, stated in `CLAUDE.md`:
`git diff --name-only main...{TICKET_KEY} | grep -E '^lib/'`. No match ⇒ skip it and say
so in the close-out ("gate 8 not applicable, no lib/ change").

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

**Verdict forms, and the exit status** (measured 2026-10-11 at `b5b277e`, cases below):

- **Pass** — exit **0**, and the output contains `GUARDS 23-27 — no violation.`
  followed by the five scanned counts (`29 / 19 / 19 / 194 / 194` at `b5b277e`); compile
  output (`Compiling N files`, `Generated …`) may come first. The counts are the positive
  control, and a pass **requires** them: **every count is non-zero**, and
  `guard_26_scanned` = `guard_27_scanned` = the table's `mutation_spec` entry total,
  counted from the committed table with

  ```bash
  python3 -I -c 'import json;d=json.load(open("conformance/data/etcc-boundaries.json"));print(sum(len(b.get("mutation_spec") or []) for b in d["boundaries"]))'
  ```

  (**194** at `b5b277e`). A zero count, or a 26/27 count that differs from that total, is
  a **fail** whatever the exit status: a guard that scanned nothing also reports no
  violation (case RF).
- **Fail** — exit **1**, through an uncaught exception and a stack trace. There is **no
  final verdict line**: the verdict is the first `** (...)` line —
  `** (RuntimeError) GUARD n: …` naming the guard and the entries, or another exception
  (`** (File.Error)` when the table is missing). A `lib/` file that does not compile
  prints its compile-error banner before the `**` line. Any exception is a fail.

Exit 0 occurred if and only if the pass line was printed, in every case run. **Exit 0 does
not exclude a vacuous pass** (RF): adjudicate on the counts as well as the line. In RF the
**zero** rule decides; the total is counted from the same emptied table, so the 26/27
equality holds at 0. A table that is short but not empty passes both rules. Making
`--verify` refuse an empty or short table itself is a code change, in MES-179's scope.

| case | planted, on a throwaway copy | exit | printed |
|---|---|---|---|
| G0 | nothing (3 runs) | 0 | the pass line, `29/19/19/194/194` |
| NA | a comment appended to `lib/mcp/client.ex`, no anchor touched | 0 | the pass line |
| RA | the `MCP.Client` anchor `Jason.decode!(Jason.encode!(struct))` edited away in `lib/mcp/client.ex` | 1 | `GUARD 26: … lib/mcp/client.ex has 0, spec records 1` |
| RB | the same anchor appended a second time, as a comment | 1 | `GUARD 26: … has 2, spec records 1` |
| RC | `" x"` appended to the first `mutation` prose line of the first row with a `mutation_spec` | 1 | `GUARD 27: … do not render back to their committed prose` |
| RD | `l2` removed from the first row with a live count of zero | 1 | `GUARD 23: … no L2 record` |
| RE | the table file moved away | 1 | `** (File.Error) could not read file …` |
| RF | the table's `boundaries` emptied (CR, MES-175 round 1) | 0 | the pass line, counts `0/0/0/0/0` — a **fail** by the count rule |

To re-run a case: copy the worktree, **remove the copy's `.git` link first** (a copied
worktree shares the original's index), plant the change, run the task, then delete the
copy.

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
   repair side the same hole is MES-173: `--emit-spec` re-counts, and turns 26/27 green
   without re-anchoring.
3. **First failure only.** The guards raise in order, 23 to 27, so a second violation
   shows only after the first is fixed. Re-run until green.
4. **Working tree, not git objects.** Guard 26 reads files relative to the cwd. The task
   checks neither that HEAD is the branch tip nor that the tree is clean (gate 7 refuses
   both), so "branch checked out, tree clean" is a rule the person running it keeps.
5. **The trigger is `lib/`, as ruled.** Guards 23, 24, 25 and 27 are functions of the
   table alone; only 26 also reads the tree. A branch that changes only
   `conformance/data/etcc-boundaries.json` or the guard sources skips gate 8. Both measured
   cases are of that shape: **MES-171** re-anchored the table and **MES-174** regenerated
   it, neither touching `lib/`. Widening the trigger was put to the PO on MES-175.

**Repairing a red GUARD 26.** The branch re-anchors the entry to the behaviour its
mutation targets, as MES-171 did, re-establishing the mutation against that behaviour. It
does **not** re-count the entry to match the tree — that is MES-173's hazard, and it turns
the guard green while the verdict it supports has expired.

## Merge-gate checklist item (cite this subsection from the review brief)

> **ET-CC anchor check (gate 8).** Run the applicability diff and paste it. If it
> applies, check out `{TICKET_KEY}` with a clean tree, run `mix conformance.sweep --verify`
> and paste its output, with the `mutation_spec` total counted by the command under
> *Verdict forms*. Adjudicate on what it prints: a pass is `GUARDS 23-27 — no violation.`
> with **every** scanned count non-zero and `guard_26_scanned` = `guard_27_scanned` = that
> total (194 at `b5b277e`); a zero or a mismatch is a fail even at exit 0. A
> `** (RuntimeError) GUARD n:` line, or any other exception, is a fail. For a red GUARD
> 26, check that the branch re-anchors the entry to the behaviour its mutation targets
> (MES-171) and does not merely re-count it (MES-173). If it cannot run at your seat,
> report **that**, and do not record the check as done.

## Evidence

`conformance/controls/etcc_boundary_sweep_controls.exs guards` — each guard broken on a
copy of the table, and the refusal required: **12/12** guard mutations fired, the unmutated
table passes, reach 50 rows; exit 0, 0.82 s at `b5b277e`. It calls `check_table!/1`
directly, not the task, so the task's exit-status correspondence rests on the cases above;
a control for it is a separate backlog ticket.
