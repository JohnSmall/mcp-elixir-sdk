---
date: 2026-08-08 22:53:04 EDT
repo: git@github.com:jmagar/mcp-elixir-sdk.git
branch: codex/mcp-routing-headers
head: 332235c28423246299b8f837330e35247b43b5d1
working directory: /home/jmagar/workspace/mcp-elixir-sdk
worktree: /home/jmagar/workspace/mcp-elixir-sdk
---

# MCP Elixir SDK 2.0 routing and subscriptions

## User Request

Review the existing Elixir MCP SDK, fork it, establish substantive 2.0 specifications and contracts, implement the work in test-first slices, publish the repository, and continue through adversarial review.

## Session Overview

The session forked and published the SDK, implemented the 2026-07-28 standard and custom routing-header slice, added the substantive 2.0 documentation package and three durable ADRs, and built the first three subscription sub-slices: codecs, client ownership/queueing, and server publication/queueing. A Lavra review then identified ten concrete correctness and resilience issues that remain to be fixed after this checkpoint.

## Sequence of Events

1. Reviewed the upstream SDK and confirmed that it already uses OTP but lacks the intended 2.0 stateless-core work.
2. Forked the SDK into `/home/jmagar/workspace/mcp-elixir-sdk`, created `codex/mcp-routing-headers`, and established a test-first slice plan.
3. Implemented routing headers, schema-driven `Mcp-Param-*` handling, bounded schema descriptors, identity-aware server validation, and one-shot refresh behavior.
4. Added normative specifications, contracts, types, runtime models, the meta-plan, and ADRs for immutable handler configuration, consumer-owned subscription supervision, and no result cache.
5. Implemented subscription codecs and supervised client/server workers with bounded queues and publication filtering.
6. Ran an eight-role Lavra review. Ten unique findings survived deduplication; remediation follows this checkpoint.

## Key Findings

- The baseline is `2b34b32`; routing/docs were committed as `332235c` and pushed to `origin/codex/mcp-routing-headers`.
- The current S2a-S2c work is locally green at 266 tests with strict Credo, Dialyzer, formatting, and diff checks previously clean.
- Review reproduced subscription event loss after a timed-out `next/2` in both worker implementations.
- Review found remotely triggerable crashes from malformed nested routing arguments and malformed `tools/list` entries.
- Review found incomplete HTTP mismatch propagation, cache self-healing, sentinel decoding, registry validation, and request-ID validation.

## Technical Decisions

- The 2.0 target is the stateless MCP `2026-07-28` core, with per-request metadata and no initialization session.
- Handler launch configuration is immutable; mutable consumer state belongs in explicit OTP owners.
- Subscription supervision and server publication registries are consumer-owned, with no SDK-global singleton.
- Subscription queues are bounded at 256 by default and overflow terminates only the affected subscription.
- The SDK preserves cache hints but does not cache MCP results in 2.0.

## Files Changed

| Status | Path | Previous path | Purpose | Evidence |
| --- | --- | --- | --- | --- |
| modified | `README.md` | — | Mark the 2.0 migration and link normative docs | `git diff 2b34b32` |
| modified | `conformance/client_adapter.exs` | — | Add routing-header scenario coverage | `332235c` |
| created | `docs/adr/0004-immutable-handler-launch-configuration.md` | — | Preserve handler configuration decision | `332235c` |
| created | `docs/adr/0005-consumer-owned-subscription-supervision.md` | — | Preserve subscription ownership decision | `332235c` |
| created | `docs/adr/0006-no-client-result-cache-in-2.0.md` | — | Preserve client cache decision | `332235c` |
| modified | `docs/adr/README.md` | — | Register ADRs 004-006 | `332235c` |
| created | `docs/sdk-2.0/contracts.md` | — | Define boundary and failure contracts | `332235c` |
| created | `docs/sdk-2.0/meta-plan.md` | — | Track slices, evidence, risks, and progress | current worktree |
| created | `docs/sdk-2.0/runtime-models.md` | — | Define OTP ownership and lifecycle models | `332235c` |
| created | `docs/sdk-2.0/specifications.md` | — | Define normative 2.0 behavior | `332235c` |
| created | `docs/sdk-2.0/types.md` | — | Define wire and public types | `332235c` |
| created | `docs/sessions/2026-08-08-mcp-elixir-sdk-2.0-routing-subscriptions.md` | — | Preserve this session checkpoint | current worktree |
| modified | `lib/mcp/client.ex` | — | Add routing schema index and refresh behavior | `332235c` |
| created | `lib/mcp/client/subscription_handle.ex` | — | Add opaque subscription consumer handle | current worktree |
| created | `lib/mcp/client/subscription_worker.ex` | — | Add bounded supervised client queue | current worktree |
| modified | `lib/mcp/protocol/methods.ex` | — | Add subscription method constants | current worktree |
| created | `lib/mcp/protocol/messages/subscriptions/acknowledged_params.ex` | — | Add acknowledgment codec | current worktree |
| created | `lib/mcp/protocol/messages/subscriptions/listen_params.ex` | — | Add listen request codec | current worktree |
| created | `lib/mcp/protocol/messages/subscriptions/listen_result.ex` | — | Add graceful result codec | current worktree |
| created | `lib/mcp/protocol/tool_routing.ex` | — | Validate annotations and routing arguments | `332235c` |
| created | `lib/mcp/protocol/types/subscription_filter.ex` | — | Add strict subscription filter type | current worktree |
| modified | `lib/mcp/protocol/types/tool.ex` | — | Enforce object-root tool input schemas | `332235c` |
| created | `lib/mcp/server/subscription_publisher.ex` | — | Filter and dispatch subscription notifications | current worktree |
| created | `lib/mcp/server/subscription_registry.ex` | — | Resolve publication registry references | current worktree |
| created | `lib/mcp/server/subscription_worker.ex` | — | Add bounded server subscription worker | current worktree |
| modified | `lib/mcp/transport.ex` | — | Add optional transport send options | `332235c` |
| modified | `lib/mcp/transport/streamable_http/client.ex` | — | Emit standard and custom routing headers | `332235c` |
| modified | `lib/mcp/transport/streamable_http/plug.ex` | — | Enforce routing headers and identity-aware schemas | `332235c` |
| modified | `mix.exs` | — | Update fork metadata and HexDocs extras | `332235c` |
| modified | `test/mcp/client_test.exs` | — | Cover schema index and refresh behavior | `332235c` |
| created | `test/mcp/client/subscription_worker_test.exs` | — | Cover client worker lifecycle and queues | current worktree |
| modified | `test/mcp/protocol/methods_test.exs` | — | Cover subscription method constants | current worktree |
| created | `test/mcp/protocol/messages/subscriptions_test.exs` | — | Cover subscription message codecs | current worktree |
| created | `test/mcp/protocol/types/subscription_filter_test.exs` | — | Cover strict filter codec | current worktree |
| modified | `test/mcp/protocol/types/tool_test.exs` | — | Cover input schema object roots | `332235c` |
| created | `test/mcp/server/subscription_worker_test.exs` | — | Cover publication, filtering, overflow, and cleanup | current worktree |
| modified | `test/mcp/transport/streamable_http_ac_test.exs` | — | Align HTTP acceptance tests | `332235c` |
| created | `test/mcp/transport/streamable_http_client_test.exs` | — | Cover client routing headers | `332235c` |
| modified | `test/mcp/transport/streamable_http_stateless_test.exs` | — | Cover server routing enforcement | `332235c` |
| modified | `test/support/mock_transport.ex` | — | Capture transport options | `332235c` |
| created | `test/support/request_capture_plug.ex` | — | Capture outbound HTTP requests | `332235c` |

## Beads Activity

No bead activity was observed. `bd where` reports that this repository has no active Beads workspace; initialization was not inferred.

## Repository Maintenance

- Plans: no `docs/plans` files exist, so nothing was moved.
- Beads: unavailable because no Beads database exists; no tracker state was changed.
- Worktrees and branches: the repository has one worktree. `main` is protected from cleanup and the active feature branch is unmerged, so no branch or worktree was removed.
- Stale docs: the 2.0 documentation package and meta-plan were updated during the session; the README's full 2.0 cutover remains explicitly assigned to S6.
- Changelog: it has no commit-summary table anchor, so quick-push left it unchanged rather than guessing a new format.

## Tools and Skills Used

- Shell and Git: repository inspection, diffs, branch creation, commits, pushes, and verification.
- Elixir tooling: `mix test`, focused ExUnit runs, formatter, Credo, and Dialyzer through pinned mise runtimes.
- GitHub CLI: fork/remote and hosted repository inspection.
- Elixir skill: OTP, GenServer, supervision, and ExUnit guidance.
- Lavra Review: eight review roles distributed across three subagents; findings were reconciled and reproduced locally.
- Quick Push and Save to Markdown: checkpoint documentation and publication workflow.

## Commands Executed

| Command | Result |
| --- | --- |
| `mise x erlang@27.2.3 elixir@1.18.4-otp-27 -- mix test --seed 0` | 266 tests, 0 failures |
| `mise x erlang@27.2.3 elixir@1.18.4-otp-27 -- mix credo --strict` | No issues |
| `mise x erlang@27.2.3 elixir@1.18.4-otp-27 -- mix dialyzer` | 0 errors |
| `mix format --check-formatted` | Passed under pinned runtime |
| `git diff --check` | Passed |
| `gh pr list --head codex/mcp-routing-headers` | No PR exists |

## Errors Encountered

- The host default Elixir toolchain was unsuitable for this branch; pinned Erlang 27.2.3 and Elixir 1.18.4 were used through mise.
- The project emits broad pre-existing incremental Jason protocol redefinition warnings during compilation; tests still pass.
- Beads commands fail because this checkout has no Beads database.

## Behavior Changes (Before/After)

| Area | Before | After |
| --- | --- | --- |
| HTTP routing | Optional/incomplete routing-header checks | Required standard headers plus schema-driven custom headers |
| Handler identity | Per-request seam without selected-schema validation | Identity-aware schema resolution before dispatch |
| Documentation | Scattered historical planning | Normative specifications, contracts, types, models, ADRs, and evidence ledger |
| Subscriptions | No 2026 unified subscription primitives | Codecs and separately supervised client/server queue workers |

## Verification Evidence

| Command | Expected | Actual | Status |
| --- | --- | --- | --- |
| Full ExUnit suite | All tests pass | 266 tests, 0 failures | Pass |
| Strict Credo | No findings | No issues | Pass |
| Dialyzer | No errors | 0 errors | Pass |
| Formatter | No changes required | Passed | Pass |
| Diff check | No whitespace errors | Passed | Pass |

## Risks and Rollback

The branch remains development-only and is not merged into `main`. Rollback is non-destructive: revert the feature commits or continue from baseline tag `2.0.0-dev.1` (`2b34b32`). The known Lavra findings must be resolved before merge or release.

## Decisions Not Taken

- No SDK-global subscription supervisor was added because ownership belongs to consumers.
- No MCP result cache was added because a correct identity-partitioned policy is outside the 2.0 migration.
- No Beads database was initialized because repository tracker adoption was not requested.
- No version bump was made by quick-push because its supported primary manifest set is absent.

## References

- MCP `2026-07-28` schema pinned at commit `5f5440bb26a62e2cf3440b92da5a667efa03b267`.
- `docs/sdk-2.0/meta-plan.md` for current slice evidence and remaining gates.
- `docs/adr/0004-immutable-handler-launch-configuration.md` through `0006-no-client-result-cache-in-2.0.md`.

## Open Questions

- Whether this fork should adopt Beads before future Lavra review waves.
- Whether the current feature branch should become a pull request after review closure.

## Next Steps

1. Push this S2a-S2c checkpoint.
2. Add failing tests for all ten findings from the completed Lavra review and implement every fix.
3. Re-run full tests, formatter, Credo, and Dialyzer.
4. Run a fresh Lavra closure review and address any additional findings.
5. Commit and push the remediation, then continue S2 transport wiring.
