# Client-leg run fixture — `@modelcontextprotocol/conformance@0.2.0-alpha.11`

Captured from a **real** client-leg run at `--requirements 2026-07-28`, driven by
`conformance/client_adapter.exs`. Not hand-authored, and that is the point
(S5-22): MES-56's round-5 guard caught two round-4 controls that were artefacts
the harness could not have produced, and a hand-built fixture is exactly that
failure with the evidence removed.

| file | what it is |
| --- | --- |
| `console.txt` | the run's console verbatim. Client-shaped: every `Starting scenario:` precedes every `Results saved to`, and the saves are in **completion** order |
| `expected.txt` | `conformance list --requirements 2026-07-28`, the scored/not-scored denominator |
| `requirements.yaml` | a byte copy of the frozen set the run was scored against |
| `scenario-dirs.txt` | every directory the run produced, relative and **sorted** |

## Why `scenario-dirs.txt` is sorted, and why it is a separate file

The directory names are also recoverable from `console.txt`'s
`Results saved to` lines — **in completion order**. Reading them from there
would make the fixture carry the very ordering the tests exist to prove is not
consulted, and a test that reconstructs its input from the thing under test
proves nothing. So the names are stored once, sorted, and the tests permute them
deliberately.

`auth` appears in the list with no timestamp suffix. It is not a scenario: it is
the container `path.join` creates because client scenario ids contain slashes.
`MCP.Conformance.RunIndex` admits it as an ancestor of candidates and refuses any
other unstamped directory.

## What is NOT here

The 39 `checks.json` files, and the `stdout.txt`/`stderr.txt` beside each. They
are ~600 KB and nothing in `RunIndexTest` reads them: the scenario key is
derived from directory names and the frozen set, so what a check sheet *says* is
irrelevant to whether it is attributed to the right scenario. The tests
synthesise empty sheets, and one deliberately omits a sheet to exercise
`ARTEFACT_CHECKS_ABSENT`.

The run's own figures live in `docs/conformance/client-2026-07-28.json`, which
is rendered from the census rather than copied.
