# Conformance Testing — pointer

**Read this only when you need it** (e.g. sprint planning that measures us against the
official MCP conformance suite, or a ticket to run/align conformance). It is a stub on
purpose: the full report lives on Confluence so ordinary sessions don't spend tokens on it.

## Where the report is

**Specs — MCP 2026-07-28 Official Conformance Testing** (Confluence, MES space `ElixirMCPS`):
https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/272367618

Fetch it with `getConfluencePage` (cloudId `2d3e57bc-fd18-403e-9c7e-0c43a6058185`,
pageId `272367618`) when the task actually needs it.

## What it covers (so you can decide whether to open it)

- How to run the **official** suite (`@modelcontextprotocol/conformance`) against this SDK at
  protocol revision **2026-07-28** — server mode and client mode, exact commands.
- The one trap: pin the **`0.2.0-alpha`** line (`latest` = `0.1.16` has **no** 2026-07-28
  scenarios); the frozen scored manifest is `requirements/2026-07-28.yaml`.
- How scoring really works (`server:`/`client:`/`not_scored:`, `reason:` codes, silent-`exit 0`
  skips) — i.e. how to read where we measure up.
- **Workstream A** (wire up & run official conformance) and **Workstream B** (align our ExUnit
  tests to the scenarios), each as pickable ticket items with acceptance-criteria seeds.
- Source links back to the conformance repo, README, manifest, npm, and the spec schema.

## Running a measurement in this repo (MES-51 + MES-56)

Three Mix tasks, in this order. Each is a gate on the next, by exit status:

```bash
mix conformance.run --leg server -o RUN_DIR              # measure; writes manifest.json
mix conformance.run --leg server --adapter null -o CTL   # the do-nothing control
mix conformance.adjudicate RUN_DIR --expect-commit <FULL SHA>   # 0 = quotable
mix conformance.census RUN_DIR --control CTL \
    -o docs/conformance/server-2026-07-28.json \
    --markdown docs/conformance/server-2026-07-28.md
```

**No figure may be quoted from a run the adjudicator has not accepted**, and that
is enforced rather than asked for: `conformance.census` calls the same `judge/3`
and exits 1 on any refusal. `--expect-commit` compares literally, so pass the
**full** sha or omit it (it defaults to HEAD).

`census.json` is the documented intermediate representation — raw check counts
over all five statuses plus **named reducers**, never a stored verdict, because
the harness applies three different rules and they disagree. The Markdown table
is rendered *from* that JSON and never written by hand. Schema and reducer
definitions: `MCP.Conformance.Census`.

**Server leg only, today.** The client leg runs its scenarios in parallel and
prints no scenario→artefact map; the parser refuses a client console rather than
mis-attributing it. See `docs/sprint_5_issues.md` S5-12, and MES-57.

Related in-repo: `docs/adr/0003-2.0.0-conformance-scope.md`,
`docs/sprint_5_issues.md` (S5-5, S5-6, S5-12, S5-13, S5-14),
`docs/conformance/` (the committed census and table).
