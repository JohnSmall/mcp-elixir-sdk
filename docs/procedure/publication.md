# Publication — push `main` and the merge's tag, every merge (D8)

> **Moved verbatim from `CLAUDE.md` by MES-177** (lines 503-609 at e74bf3f; headings promoted
> one level). "The DoD gates" and "the gate table" are in `CLAUDE.md`,
> *Definition-of-Done Gates*; run point (c), "the end-of-sprint sweep", is step 5 of
> `docs/procedure/end-of-sprint.md`.

**PO-ratified 2026-09-10; codified as overrides-page entry D8 by MES-95.** This
is a *public* Hex package with a *public* GitHub repo
(`github.com/JohnSmall/mcp-elixir-sdk`), so **source visibility is decoupled from
release**: `main` on GitHub is the product surface people read, clone and file
issues against, and it must not lag. Public status changes *when source is
visible*, not *when a release is cut*.

1. **`git push origin main` is the final step of the PM merge gate**, after the
   squash-merge and its tag. Safe to run continuously because every merge is
   DoD-green — there is no unstable intermediate state to hide.
2. **Push the merge's tag too.** Origin mirrors `main` *including* the
   `2.0.0-dev.N` tags (PO-directed, "including the tags").
3. **Releases are unchanged.** The release tag (`v2.0.0`, suffix dropped) and the
   Hex publish still happen only at the PO-scheduled release ticket. The
   `2.0.0-dev.N` counter continues between releases.
4. **D6's branch rule is unchanged.** Ticket branches stay bare `{TICKET_KEY}`
   and local-only. This section is about `main`, not about branches.

## The instrument — `mix origin.sync`

A convention with no instrument lapses silently, and this one already did:
`origin/main` sat at the Sprint 5 close for **30 commits / 2.5 sprints**, and was
then rationalised as intentional in several PM reports rather than flagged
(S7-47). So the rule is instrumented, not merely written. The blunt test — *if
every trace of this rule were removed, what goes red?* — is answered by:

```bash
mix origin.sync        # exit 0 in sync, 1 otherwise. Seconds. Read-only.
```

Five conjuncts, each naming its own failure: **C1** origin is reachable and
readable; **C2** the *live* `refs/heads/main` equals local `main`; **C3** the tag
named by `mix.exs`'s version exists locally and is annotated; **C4** that tag is
on origin *as the same object*; **C5** the tag peels to an ancestor-or-equal of
local `main`.

**It is live, and it decides on shas — never on exit codes, never on a tracking
ref.** Both halves of the obvious check were measured exiting green over a
divergent origin: `origin/main` is `refs/remotes/origin/main`, a local file that
changes only on fetch or push; and `git ls-remote origin refs/tags/<absent>`
exits **0** with empty output, so "the tag resolves on origin" cannot be
established by a status at all. **It is fail-closed**: a conjunct it cannot
determine is a failure, so a seat that cannot reach origin fails honestly rather
than green.

**Why C5 is ancestor-or-equal and not "on the tip":** measured 2026-09-20,
`2.0.0-dev.33` peels to `main~1` on a correct repository, because the PM's
post-merge sweep record is committed after the tagged merge. A tip check would be
red on a healthy tree.

## Run points — three, and none of them is a DoD gate

The DoD gates are per-ticket and run by CODE_CREATOR on a branch, **before the merge
exists**. A sync check there would be red by construction on every ticket, which
would make the gate table permanently false rather than informative. So:

| # | Who | When | What it attests |
|---|-----|------|-----------------|
| (a) | PM | immediately after `git push origin main` and the tag push | this merge |
| (b) | CODE_REVIEWER | on the merge-gate checklist, in every review | the **previous** merge |
| (c) | PM | the end-of-sprint sweep | the sprint's final tip |

**(b) is the self-enforcing limb.** It is the D1a shape — verification of a
commit no reviewer has seen — and it is what makes a missed push go red at the
*very next merge gate* rather than never. Without it the rule is again a
convention the PM checks on the PM's own honour, which is the arrangement that
failed.

## Merge-gate checklist item (cite this subsection from the review brief)

> **Publication check.** Run `mix origin.sync` and paste its output. It attests
> the **previous** merge, not the branch under review, so it is expected green
> before this ticket merges. If it is red, say so in the review: a red here means
> a merge that is already on `main` was never published, and that is a finding
> against the merge gate, not against this ticket. If it cannot run at your seat,
> report **that**, and do not record the check as done — an unrun check and a
> null result are the same artefact.

## What it does not cover

It checks the **current** version's tag only. That *every* `dev.N` in `mix.exs`
history has a tag on the right commit is **MES-90**'s, and is not built here.
(MES-90's body still carries a "do not push tags" line written before the PO
ruled for a full mirror; that line needs superseding when MES-90 is scheduled.)

## Evidence

`conformance/controls/origin_sync_controls.exs` — eleven controls on throwaway git
fixtures under a per-run generated root, driving the real task: **P1** in sync (the
positive control, without which a check that is red on everything would "pass"
every red case vacuously); **R1** main not pushed; **R2** main pushed and the tag
not — the S7-47 lapse; **R3** one tag name, two objects; **R4** origin
unreachable, red and not green; **R5/R5a** a stale `refs/remotes/origin/main`
shown **green under the `rev-parse` form and red under `mix origin.sync`, on the
same fixture**; and **G0-G3**, which hold the controls' own fixture-containment
guard to the property written over it — the in-root fixture accepted, and a
same-tmp sibling, a path-prefix escape and an out-of-root work tree each refused.

Plus two mutation modes, because a case that always passes is not evidence:
`... origin_sync_controls.exs mutation` shows the controls' **adjudicator**
refusing an expectation the run does not support, and `... guard-mutation` puts
the **superseded containment predicate** back in charge and requires all three
escapes to be admitted — so G0-G3 are shown able to fail, and it is the fix that
makes them pass. Decision-logic units are in
`test/conformance/origin_sync_test.exs` and so are covered by gate 5.
