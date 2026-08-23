# The ET row key, and the ExUnit row artefact

**Defined on MES-83 (B3), Sprint 7, 2026-08-23.** This file is the **single
home** for the row key. B2a (`MES-81`) and B4 (`MES-84`) adopt it verbatim; C1
joins on it.

**Repo is source of truth; there is no Confluence mirror of this file at the
time of writing.**

---

## §0 The authority this key answers to — CITED, not restated

The unit of ET-CC membership, and the constraint the key must satisfy, are fixed
by **[`etcc-membership.md`](etcc-membership.md) §0** (ratified MES-67, landed on
`main` at `ffc1a2f`).

**Read that section there.** It is not reproduced here, and that is deliberate:
a definition living in two places diverges, which is S7-6 and S6-5 before it.
MES-80 exists because of exactly that, and a second copy made one hop
downstream of the ticket that fixed it would be the same defect again.

What this file adds is the **concrete form** — the rendering, the JSON schema,
and the join rules — which §0 fixes the shape of but not the spelling.

---

## §1 The key

    key = inspect(module) <> "/" <> name

Both halves come off the `%ExUnit.Test{}` struct the event manager broadcasts at
runtime.

| part | source | rendering |
| --- | --- | --- |
| `module` | `test.module` | `inspect/1` — e.g. `MCP.Protocol.ErrorTest` |
| `name` | `test.name` | the atom as a string, **verbatim** |

**`name` is verbatim, and nothing is stripped.** It carries the `test `/
`doctest ` type prefix and the describe prefix that **ExUnit itself** builds at
`case.ex:701` and `case.ex:705`
(`"#{test_type} #{describe} #{name}"`, Elixir 1.19.5). Two examples from the
committed artefact:

    MCP.ClientConformanceTest/test CG2 / T-CG2 — extensions negotiation, both directions an unknown extension is not logged as a fault
    MCP.Protocol.ExtensionsTest/doctest MCP.Protocol.Extensions.normalise/2 (5)

Not normalising is what lets B2a reconstruct a key from source by applying the
same ExUnit rule, rather than by guessing at a normalisation.

### §1.1 Splitting a key

Split on the **first** `/`. A module name cannot contain `/`, so this is
lossless even though a test name routinely does — the doctest example above has
two. `MCP.Conformance.ExUnitRows.split_key/1` is the implementation.

### §1.2 Uniqueness

Uniqueness within a module is **ExUnit's, by construction**: it raises
`"..." is already defined in <mod>` at `case.ex:710`. So a collision in the
artefact can only come from the *rendering* being lossy, never from two tests
genuinely sharing a key. That is why every artefact carries a computed
`run.key_collisions` and a test asserts it is empty: the check is on the
instrument, not on ExUnit.

`file:line` is recorded as two fields and is **never** the key.

---

## §2 The artefact

`docs/conformance/etcc-exunit-rows.json`, written by
`MCP.Conformance.ExUnitRows` (`conformance/lib/mcp/conformance/exunit_rows.ex`).

    {
      "schema": "etcc-exunit-rows/1",
      "run":    { ... provenance, see §5 ... },
      "totals": { ... DERIVED from rows, see §3 ... },
      "rows":   [ ... one per runtime test ... ]
    }

### Row fields

| field | meaning |
| --- | --- |
| `key` | §1. Derived: `module <> "/" <> name`. |
| `module` | `inspect(test.module)`. |
| `name` | the test's name, verbatim. |
| `test_type` | `"test"`, `"doctest"`, … — the `:test_type` tag. |
| `file` | path **relative to the checkout**, so a worktree and a clone agree. |
| `line` | the line of the `test`/`doctest` **declaration** — *not* the line of a preceding `@tag`. |
| `describe` | the enclosing `describe` string, or `null`. |
| `tags` | the whole tag map minus the deny-list below. |
| `status` | one of the five in §4. |
| `reason` | ExUnit's own reason for `excluded`, `skipped` and `invalid`; `null` otherwise. |
| `failure` | for `failed` and `invalid`: `kind`, `exception`, `message`, `at`. `null` otherwise. |

### The tag deny-list, and why it is a deny-list

Recorded tags are the whole map minus
`:async :describe :describe_line :file :line :module :registered :test
:test_group :test_type`.

A **deny-list with a stated reason** is the S6-11-safe form of a projection: an
allow-list would drop tags nobody thought of, invisibly. Each key is denied for
one of two reasons:

* **promoted to its own row field** — `:file`, `:line`, `:describe`,
  `:test_type` (and `:describe_line`, `:registered`, `:test` and `:module`,
  which are ExUnit bookkeeping the row already carries).
* **present only for tests that RAN** — `:async` and `:test_group`.
  `prepare_tests/4` (`runner.ex:255-303`) merges `:test`, `:module`, `:async`
  and `:test_group` into the tags while evaluating the filter and stores the
  merged map **only on the to-run branch**, so an excluded or skipped test keeps
  its original tags. Denying those four is what makes the recorded tag map
  **identical between run states**, and so independent of the host.

Non-JSON tag values are rendered with `inspect/1` rather than dropped.

`time` is deliberately **not** a field: it would make every run differ and
destroy the diff.

---

## §3 Totals are DERIVED

`totals` is produced by `derive_totals/1` from `rows` and by nothing else, and
two tests assert it — one over synthetic rows, one re-deriving the committed
artefact's totals from the committed artefact's own rows. A hand-edited total is
a red.

`by_status` **always carries all five keys**, including zeros, for the same
reason an excluded test gets a row: a consumer must never have to tell "zero"
from "absent".

`by_test_type_not_excluded` is the shape ExUnit's **own headline** counts in —
`update_test_counter/2` (`cli_formatter.ex:263-265`) returns the counter
unchanged for `{:excluded, _reason}`, so the headline omits excluded tests and
includes skipped and invalid ones. That is the term the reconciliation compares
against, and it is why the naive `rows == total` identity would be wrong.

---

## §4 The five statuses, and the sixth thing

| status | ExUnit state | meaning |
| --- | --- | --- |
| `passed` | `nil` | ran, no failure |
| `failed` | `{:failed, _}` | ran, failed |
| `excluded` | `{:excluded, reason}` | a **filter** decided it would not run |
| `skipped` | `{:skipped, reason}` | `@tag :skip` |
| `invalid` | `{:invalid, module}` | the module's `setup_all` failed, so it never ran — neither a pass nor a failure |

Vocabulary read off `t:ExUnit.state/0` (`ex_unit.ex:76-81`).

### §4.1 The join rule — absence is the sixth thing, and it is the consumer's

**An excluded test HAS a row.** So for anyone joining against this artefact:

* key present, `status: "excluded"` → **the test exists and this run did not
  drive it**, and `reason` says which filter.
* key **absent from `rows`** → **the test does not exist at this tip.**

Those are different facts and the artefact keeps them different. An artefact
that simply omitted an excluded test would collapse them, which is S6-9 one
layer down: *a captured denominator records what WAS measured, so an absence in
it conflates "the instrument cannot score this" with "this run did not drive
it".*

---

## §5 Provenance, and which fields may legitimately differ

`run` is the provenance block. **It is not claimed stable, and `rows` is.**

### What IS claimed

`rows` is **byte-identical across seeds** — demonstrated over a seed sweep by
`conformance/controls/exunit_rows_controls.exs sweep`, which prints every md5
rather than asserting agreement. Row *order* is canonical (sorted by
`{module, name}` on write), so a diff is meaningful.

### What is NOT claimed

* **The `run` block.** Across a seed sweep it differs in `seed` and `argv`.
* **Failure-detail text.** It can embed runtime values. A green suite has no
  failure rows, so a sweep never exercises the field, and claiming a bound the
  sweep cannot test would be worse than saying so.

### §5.1 The committed copy is HOST-DEPENDENT. Read a diff against this list.

**The committed artefact was generated on the host that has `node` and the
pinned conformance harness present** — the state `test/test_helper.exs` requires
for a complete gate 5. Specifically: `node v24.13.0` on `PATH`, harness at
`/tmp/conf11/node_modules/@modelcontextprotocol/conformance`, Elixir 1.19.5 /
OTP 28.

On a host **without** `node`, `test_helper.exs` excludes
`:requires_live_harness` and regeneration is **not** byte-identical. Measured
2026-08-23 at `45ef504` by running both ways on this machine and diffing — not
predicted:

| what moves | how |
| --- | --- |
| **3 rows**, and only these three | `status` `passed` → `excluded`, `reason` → `"due to requires_live_harness filter"`. `classification_test.exs:48`, `classification_test.exs:137`, `requirement_set_test.exs:358` |
| `run.exclude` | `[]` → `[":requires_live_harness"]` |
| `run.rows_md5`, `run.module_cross_check.compared`, `totals` | all **derived** from the above; they move because the rows did |
| `run.tip`, `run.argv`, `run.seed` | provenance of the regenerating run, not host variation — see below |

**Nothing else.** All 992 keys are present in both, and no row appears or
disappears — which is §4.1 working: the artefact says *"could not run here"*,
never *absent*.

**So: a diff confined to those fields is expected host variation. A diff outside
them is a finding.**

### §5.2 `run.tip` names a commit the squash-merge makes UNREACHABLE. Verify against `rows_md5`.

The artefact is generated on the branch, so `run.tip` names the branch commit
whose tree the rows were measured at — and the PM's squash-merge collapses that
branch into a single commit on `main` and deletes it. **`git show` on the
recorded `run.tip` will therefore fail for any copy generated before a merge**,
including this one, whose `run.tip` was `8a305d3` on branch `MES-83`.

This is not drift and it does not weaken the artefact. The measurement happened;
what is gone is the *address*, not the bytes. **`run.rows_md5` is the field to
verify against** — it is a function of the rows alone, it survives the merge
unchanged, and comparing it is what §5 already tells a reader to do. `run.tip`
remains useful on an unmerged branch and as a record that a specific tree was
measured; it is not a handle you can resolve after the fact.

Recorded by the PM at MES-83's merge gate, because the merge is what creates the
condition — B3 could not have avoided it without regenerating after every commit,
which moves the tip again. There is no fixed point here, only a field to trust. In particular a diff in `key`, `module`, `name`,
`test_type`, `file`, `line`, `describe` or `tags` is a finding regardless of
host.

`run.tree_dirty` is the porcelain list of paths that were not clean when the
rows were captured, with the artefact's own path excluded — it is the file being
written. It is a **list** rather than a boolean because "clean, and here is the
empty list" and "clean, take my word for it" otherwise print the same.

`run.tip` and `run.tree_clean` name the tree the rows were **measured** at. The
artefact's own commit is that tip's child, so regenerating after it has landed
advances `tip` by design — compare `rows_md5`, not `tip`, when asking whether
the content moved. **Detecting drift between the artefact and the suite is
MES-84's**, not this file's.

---

## §6 Regenerating it

    MCP_ETCC_ROWS=docs/conformance/etcc-exunit-rows.json mix test --seed 0

Capture is **off** unless `MCP_ETCC_ROWS` names a path: a plain `mix test` does
not attach the formatter at all, so gate 5 — which runs on every ticket at three
seats — cannot be broken by this instrument.

The controls, which are what make a green here mean anything:

    mix run conformance/controls/exunit_rows_controls.exs states     # all five statuses, from a real run
    mix run conformance/controls/exunit_rows_controls.exs flip       # one test, two runs, two statuses
    mix run conformance/controls/exunit_rows_controls.exs reconcile  # rows vs ExUnit's own summary
    mix run conformance/controls/exunit_rows_controls.exs sweep      # row content across 20 seeds
