# Work-item lanes (D7)

> **Moved verbatim from `CLAUDE.md` by MES-177** (lines 25-81 at e74bf3f); the core keeps
> a summary and a pointer here. **Since MES-177 the gate text this boundary protects lives in
> `docs/procedure/`, so "`CLAUDE.md`" in the boundary below reads as "`CLAUDE.md` or
> `docs/procedure/`", pending D7's amendment on 250052681.** "This file" below is this page:
> `conformance/controls/pm_alone_lane_guard_controls.exs` extracts the guard block from here.
> "D8(b)" is run point (b) in `docs/procedure/publication.md`; the DoD gates are in `CLAUDE.md`.

**Work-item lanes (D7).** The lane is the **Jira issue type**, and the default is safe. A
**PM Task** (issue type id `10484`, hierarchy level 0) is worked **PM-alone**: the PM plans,
executes, runs the applicable gates, authors the merge as `Project-Manager` (**D6**),
transitions (**D5**) and unassigns — **no handoff to CC or CR**. **Every other level-0 type —
Story, Task, Bug, Feature — keeps the full `PM→CC→PM→CR→PM` cycle.** The PM-alone lane is
reached only by deliberately choosing the type, so a mis-file defaults to the *reviewed* lane,
never away from it. **Epics are unaffected** — this governs level-0 work items only.

**The boundary — what a PM Task may NOT touch.** Its branch must change **no reviewable
path** — `lib/`, `test/`, `conformance/lib/`, `conformance/controls/`, `docs/conformance/*`
(the change-controlled criterion/register) — **or** a `CLAUDE.md` change that alters a **DoD
gate** or ships an **instrument**. It may touch repo docs/config with no correctness surface:
a sprint findings register, a README tidy, an editorial `CLAUDE.md` edit. **When in doubt, it
is a Task, not a PM Task.** Everything else binds unchanged — D5's baton and channel model,
D6's commit identity and merge authorship, gates 1–5 (they simply have little to bite on for a
docs-only change), gate 6 by the three-dot rule, and D8's push of `main` and the tag.

**Guarded fail-closed at the merge.** The PM-alone merge asserts the branch touched no
reviewable path, and refuses otherwise:

```bash
git diff --name-only main...{TICKET_KEY} \
  | grep -Eq '^(lib/|test/|conformance/lib/|conformance/controls/|docs/conformance/)' \
  && { echo "REFUSE PM-alone: branch touched a reviewable path — re-type to Task, route to CR"; exit 1; }
```

The type is a declaration of intent; the guard verifies the intent against the diff — belt
(safe default) and braces (the check). **Canonical statement: D7 on 250052681.** Evidence:
`conformance/controls/pm_alone_lane_guard_controls.exs` (see below).

**Merge-gate checklist item (cite this paragraph from the review brief).**

> **Lane check (D7).** State the ticket's issue type. A **PM Task** that reached CR at all
> is a mis-route — a finding against the routing, not against the branch. Then run the D7
> guard above with this ticket's key and paste its output. On a Task either verdict is
> admissible; what you attest is that the instrument **runs at this seat** and that its
> verdict is consistent with the type. **Adjudicate on the REFUSE message, not on the exit
> status** — the two are not in correspondence (see the evidence note below). If it cannot
> run at your seat, report **that**, and do not record the check as done.

**What this item does not attest.** Not a *past* PM-alone merge. The canonical form needs
the branch, and branches are bare `{TICKET_KEY}` and local-only (**D6**), deleted at merge —
so there is no D8(b)-shaped previous-merge limb available without inventing a second command
shape, which is the drift this ticket exists to prevent. Stated as a residual, not papered over.

**Evidence, and two measured properties of the guard you must not be surprised by.**
`conformance/controls/pm_alone_lane_guard_controls.exs` **extracts the fenced block above out
of this file** and runs it against throwaway git fixtures, so a drift between this copy and
the control is impossible by construction; `mix run … mutation` mutates the extracted snippet
in memory and requires the named cases to go red. Two behaviours are controlled **as
observed**, not fixed here — the string above is D7's and is shipped verbatim:
**(1)** the guard's **exit status does not correspond to its verdict** — as the last command
of a script it exits `1` on a clean docs-only branch, the same status as the refusal
(**S9-22**); **(2)** on an **unresolvable ref** — a mistyped key, an absent branch, the wrong
directory — it prints git's `fatal:` to stderr, matches nothing and falls through **green**
(**S9-23**). Both measurements are in `docs/sprint_9_issues.md`; the remedy is an amendment to
D7 on 250052681 and is owned by **MES-106**, not by this file.
