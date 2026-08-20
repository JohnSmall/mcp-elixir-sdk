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

Related in-repo: `docs/adr/0003-2.0.0-conformance-scope.md`.
