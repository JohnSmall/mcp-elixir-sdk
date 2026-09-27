# Sprint 13 — findings register

**Sprint goal, as re-planned by the PO on 2026-09-27 (met).** Sprint 13 opened as the second
half of the D group (epic MES-96): buckets 1, 3, 6 and 5b, with 5a to follow. Mid-sprint the PO
asked whether this was conformance work or internal documentation, and then ruled (MES-96
comment 30143, Q1–Q5 all YES) as follows:

- A test that is green while its official-conformance (OC) check is red should be caught
  **when the test is written**, not by a global scan. This became **DoD gate 7** (MES-160).
- MES-147 and MES-148 (bucket 5a) left the sprint.
- The four lib/ fixes the D records had identified were brought in, held to the new gate.

Sixteen tickets merged, `2.0.0-dev.62` → `2.0.0-dev.77`.

| dev | ticket | what landed |
|-----|--------|-------------|
| .62 | MES-137 | Boundary drift at the Sprint 12 close: Error (encode) dead again; L1 counts units that execute lib/ |
| .63 | MES-135 | G32 hardened before reuse: content tied to key, a universe of views owed a record, exclusive closure |
| .64 | MES-138 | D1-nd+CU: none_determinable 21 (open) and claim-unmatched 9 (CLOSED); D1 disposition family in G32 |
| .65 | MES-139 | D1-client-i: 35 client-leg members (ClientTest + ClientToolSchemasTest) |
| .66 | MES-140 | D1-client-ii: the other 36 client-leg members |
| .67 | MES-141 | D1-server-i: 39 server-leg members (ExtensionsNegotiation + JsonSchema202012) |
| .68 | MES-142 | D1-server-ii: 37 server-leg members (SubscriptionsDispatch, SSE, Stateless, SubscriptionsStream) |
| .69 | MES-143 | D1-server-iii: the last 27; **bucket 1 CLOSED** (53/86/53/3 + claims 3/0/6/0; 145 routed); mirror |
| .70 | MES-144 | D3+D6: buckets 3 and 6 CLOSED and EMPTY, with an echoed emptiness premise |
| .71 | MES-145 | D5b-i: the D5 discrimination family in G32; 31 client edges (7/11/7/6/0) |
| .72 | MES-146 | D5b-ii: http-custom-headers 36; **bucket 5b CLOSED** (view 7/11/43/6/0); mirror |
| .73 | MES-160 | **DoD gate 7** — `mix conformance.oc_gate`: no test merges green while its OC check is red |
| .74 | MES-161 | Server rejects a request missing required `_meta` with -32602 (HTTP 400, id kept) |
| .75 | MES-155 | HTTP server requires MCP-Protocol-Version / Mcp-Method / Mcp-Name; header vs `_meta` version check |
| .76 | MES-157 | Plug error responses carry the JSON-RPC id (readable id, or null) |
| .77 | MES-156 | SSE parser accepts CRLF/CR/LF (incl. split across chunks), a stream-start BOM, spec field grammar |

**Live OC movement from the fix tickets** (whole legs, `--requirements 2026-07-28`, pinned
harness dist `a10085d0…`; every run ACCEPTED by the census):

- **Server leg: 131 → 142 SUCCESS.**
  - MES-161: +6 (RequestMetaInvalid ×3, HttpServerMetaInvalid400 ×3).
  - MES-155: +5 (HttpServerHeaderMismatch400, ServerRejectsMissing{Method,Name}Header and their
    ErrorCode rows).
  - Nothing reddened on any merge.
- **MES-157 and MES-156 moved no row, by measurement.** The pinned suite cannot see the paths
  they change:
  - MES-157: mx2 put a wrong id on every changed body and HttpServerErrorJsonrpcId stayed
    SUCCESS.
  - MES-156: the pinned dist and its SDK scenario servers contain 0 CR bytes and 0 BOM bytes.
  - Both tickets' units are `oc: :none` with that measurement as their reason.

**Board state at close.** G32 owes 11 views: 10 closed, 1 pending (bucket 5a, now in the backlog as
MES-147/148). Backlog raised this sprint: MES-152/153 (routing), 154, 158, 159, 162, 163, 164,
165, 166, 167, 168, 169, 170.

## S13-1 — the PO's re-plan: the gate catches at writing time what the D scan found after the fact

The D group's scans kept finding the same shape: a unit green while its OC counterpart was red.
The PO's ruling moved that check to the moment a test is written. Gate 7 declares the check per
test (`@tag oc:`), measures it live on the branch, and refuses WARNING and SKIPPED as well as
FAILURE.

It proved itself on its first four users:
- **MES-161** needed 214 declarations. Six of them turned red checks green.
- **MES-155** declared real check tokens on a scenario the scoring set excludes. Gate 7 measured
  them live.

What it costs, and what it found:
- **Declaration cost.** Any non-test edit to a test file marks every test in it changed. Plan for
  that before editing a large file; `adjudications_test.exs` is 285 declarations.
- **First exception.** On MES-161 three pre-existing tests were contradicted by a red check. The
  PO granted a disclosed exception (MES-161 comment 30342), codified in CLAUDE.md gate 7 and in
  D10 v18. Conditions: the test's assertions are unchanged; its body change is request
  construction only; its tag change is the declaration only; and the reason names the red check,
  the owning ticket and the ruling.

## S13-2 — gate-7 declarations collide with G32's line citations; anchoring is the answer for removed defects

Gate 7 puts a line above every declared test. The D records cite test files by line window, and
G32 refuses even a one-line shift.

MES-161 re-resolved 636 citations mechanically. The mapping came from each file's own diff and
was verified by token alignment, first by CC and then independently by CR: BAD 0 both times.

127 citations quoted the **defect itself**: requests that lacked the `_meta` MES-161 now
requires. Re-citing those at the tip would have made the records claim the defect still exists.
They are **anchored** instead (`"at": <sha>`) at the last commit that had the text. G32 reads
anchored citations from git objects. Anchoring is refused in three cases:
- the sha is not an ancestor;
- the cited text still exists at the tip, so anchoring cannot hide ordinary drift;
- the anchor is a prose anchor outside its field.

MES-155 added one anchor, so G32 now prints `anchored 128`. MES-155 and MES-157 held plug.ex
line-neutral by placement; MES-156 held `sse.ex:216` in place. Every cited line held.

**Residual:** G32 does not check that `at` is the *last* commit that had the text. That is in
the moduledoc's "does not hold" list.

## S13-3 — an unchanged anchor is not an unchanged mutation (MES-157 B1)

MES-157 widened a `decode_well_formed/1` clause beyond the ratified plan. Production behaviour
was unchanged, but D1-server-iii's recorded M30' mutation was swallowed: it now produced -32600
where the record says -32602. Its old-string still occurred exactly once, so G32 stayed green.
Only CR re-running the mutation showed it.

**Practice adopted (PM memory):** a ticket that edits a lib/ file re-runs every recorded mutation
touching that file, at main and at the tip, **one after the other**, and compares red sets.
Running them in parallel turned 3 unrelated client tests red. MES-157's close-out and MES-156's
plan both carried the table.

## S13-4 — engine exits: detached work survives, and so can a detached mutation

Silent seat exits happened throughout: CC on MES-161, and twice on MES-156; CR once on MES-155,
42 s after pickup. The resume procedure worked every time: a RESUME comment, clear the edge
marker, confirm PICKUP.

Two new failure shapes:
1. **An engine exit sends SIGTERM to child processes.** A long swap audit died with the session.
   Fix: launch long runs detached (`setsid nohup`).
2. **Detached runs outlive the engine.** On MES-156 a detached mutation runner kept rewriting
   `lib/mcp/transport/sse.ex` in the **shared clone on main** after the exit, and after the PM had
   restored the file. It was about to `git checkout` a scratch branch there. CC found it on
   resume and killed it.

**Rules adopted:**
- After any silent exit, run `ps` for orphaned runners before trusting the tree, then read the
  diff.
- Mutations run only in throwaway worktrees, never in the shared clone.
- Every hand-back includes a `ps` check and a worktree listing that shows dirty status.

## S13-5 — merge-gate incidents: the branch assertion and worktree cleanup

1. **MES-143.** The shared clone was on a ticket branch at merge time, so a tag was pushed
   pointing off main. `mix origin.sync` C5 caught it. The tag was deleted and redone, and the
   incident disclosed on the ticket. **Rule:** assert branch == main and a clean tree before the
   squash and again before the tag. Printing the branch is not checking it. The assertion held
   on every merge after.
2. **MES-145.** Worktree cleanup force-removed a scratch worktree holding uncommitted
   ledger/universe edits, without naming it. It was harmless, since the branch was the reviewed
   tip. **Rule:** list each worktree's dirty status before removing it.

## S13-6 — correction rounds: what each class of review finding was

Every correction round was caught by CR, and none moved a merged number:
- **MES-141 F1.** "Not covered" was claimed on "not scored" evidence. The excluded scenarios
  were never searched.
- **MES-142 B1.** The one "genuine" row sent a malformed request of its own.
- **MES-143.**
  - B1: a control was shown "non-conforming" by construction, not by the strongest conforming
    alternative.
  - B3: the fix added a false universal claim.
- **MES-144 B1.** A landing claim was false for one AGREE-onto-red edge.
- **MES-145.**
  - B1: per-request aggregated OC checks against a member that sampled one request type.
  - B2: a false moduledoc premise.
  - B3: a false sweep reason.
- **MES-160.**
  - B1: for-generated tests went unseen.
  - B2: the harness pin was not enforced.
  - B3: a test move across an attribute redefinition went unseen.
- **MES-161 B1.** The -32602 check ran after identity resolution, contrary to the ratified
  order.
- **MES-155 R1.** One limb was unpinned; the whole suite stayed green with it deleted.
- **MES-157 B1.** See S13-3.

**Pattern:** most were a claim broader than its measurement. The briefs that carried the
previous ticket's lesson in advance (MES-142 → MES-143, MES-145 → MES-146, S13-3 → MES-156)
had fewer rounds.

## S13-7 — smaller findings (backlog or noted)

1. **Seed-18 flake.** `mes135-g32-<unique_integer>` tmp dirs collide across VMs
   (adjudications_test.exs:2555).
2. **MES-141 hop A** reported progress without disclosing a red gate 5 (4 global pins not
   moved).
3. **Test cost.** The MES-145 K1-R tie (c) unit takes 42–46 s alone; it was given a 300 s
   timeout. It taxes every gate-5 run and seed sweep. Candidate backlog: make it cheaper.
4. **Unpinned figures.** Gate-5 figure strings inside records are unpinned (1619→1623 was caught
   by eye, MES-144).
5. **G32 gaps.** G32 admits `sections: []`. A missing-universe echo passes.
6. **Bucket 6** can only be filled by a test that is red on arrival, and gate 5 forbids that on
   main (MES-144).
7. **Crosswalk `et_verdict`** is hand-entered, not tied to a run.
8. **CR N1 on MES-146.** A no-op assert cannot fail by construction; the real bound is the
   gate-5 unit.
9. **`mix conformance.etcc_tags --check` is red on main.** A MES-160 fixture string matches as a
   stray tag. It is not a DoD gate, so MES-160 merged with it red → **MES-166**.
10. **Gate 7's own residuals:**
    - doctests and `test/support/` changes are not seen;
    - an out-of-file `for` generator is not seen (**MES-162**);
    - the one shared MES-156 `oc_reason` names only CR/CRLF, though it also stands over the BOM
      and grammar units (incomplete, not false; CR 30519).
11. **Nested test modules** (CLAUDE.md rule) exist in 3 test files, as precedent. A tidy would be
    one sweep, not per ticket.
12. **Multiset key counts depend on the keying** (77 vs 100 on MES-156). The identity result
    holds either way. State the key with the figure.
13. **Sweep instruments.** CC's first MES-156 run globbed one directory level and counted 65
    client rows instead of 128. Caught and re-run before quoting. Sweep checks-files
    recursively.

## S13-8 — behaviour changes shipped (for the next release notes)

- **MES-161.** A request missing `_meta` protocolVersion or clientCapabilities now gets -32602
  (HTTP 400 on the Plug), including on `server/discover`. The -32602 check runs before the
  handler_opts identity factory. A present-but-unsupported version still gets -32022.
- **MES-155.** Every POST needs MCP-Protocol-Version and Mcp-Method, plus Mcp-Name when the method
  has a string name target, or it gets 400/-32020. This includes notifications. A legacy
  `initialize`/`ping` sent without headers now gets 400/-32020 instead of 200/-32022; that is
  spec-conformant (streamable-http.mdx:280-283), but the explanatory text is lost. A non-object
  body now gets 400/-32600; on main it raised BadMapError.
- **MES-157.** Every JSON-RPC error body written by the Plug carries an `id` key.
- **MES-156.** The client's SSE parser state is an opaque map; a legacy binary state is still
  accepted. `retry: 5 ` with a trailing space is now ignored, per spec.

## S13-9 — the boundary sweep could not run: the sweep's own mutation anchors were not in any ticket's blast radius

The practice in S13-3 covered the mutations recorded in the **D records**. It did not cover the
**ET-CC boundary sweep's** `mutation_spec` (`conformance/data/etcc-boundaries.json`), which also
anchors on lib/ bytes. Two fix tickets broke those anchors:
- MES-161 multiplied `"_meta"` in meta.ex from 2 occurrences to 9.
- MES-157 removed the hand-built error map in plug.ex (1 occurrence → 0).

Nothing per-ticket checks those anchors. The sweep's GUARD 26 caught both at the sprint
boundary and refused to run, which is the fail-closed behaviour it was built for.
**→ MES-171:** re-anchor each entry to the behaviour it mutated at 5047a0e, then run the owed
sweep. **Carry forward:** a lib/ ticket's blast radius includes the ET-CC `mutation_spec`
entries for the files it edits. A resolve-only GUARD 26 check would take seconds.

## End-of-sprint sweeps (at the final tip `2.0.0-dev.77` / `2feeb63`)

**Dependency-advisory sweep (the two-step gate 6).** hex 2.5.1, at the floor.
- The 6a baseline sentinel PASSES: all 22 known advisory ids are present.
- 6b, `mix hex.audit` on this project, reports **"No retired or security advisory packages
  found", exit 0**.

Checked, and zero.

**Publication sweep (`mix origin.sync`, run point c).** GREEN: C1–C5 all green and IN SYNC at
`2.0.0-dev.77` (`2feeb63`). Tag 240e5b7ca3ae is the same object on origin.

**Boundary-liveness sweep (`mix conformance.sweep --check`).** OWED, and the run was REFUSED
(fail-closed). The last sweep tip is `5047a0e` (the Sprint 12 close). The three skip
conditions:
- (a) `git diff --name-only 5047a0e...HEAD -- lib/` gives **5** files: `lib/mcp/protocol/error.ex`, `lib/mcp/protocol/meta.ex`, `lib/mcp/server/dispatch.ex`, `lib/mcp/transport/sse.ex`, `lib/mcp/transport/streamable_http/plug.ex`.
- (b) `git diff --name-only 5047a0e...HEAD -- test/ test/support/ conformance/lib/` gives
  **30** files.
- (c) `mix conformance.sweep --host` MATCHES: node=v24.13.0, harness=available, recorded and
  current.

(a) and (b) are non-empty, so the sweep was owed. It was launched at `2feeb63` with seats
idle; lib/ was dirty 0 before and 0 after. It ended immediately:

```
** (RuntimeError) GUARD 26: 2 mutation_spec entry/ies no longer resolve at this tip:
  MCP.Protocol.Meta: lib/mcp/protocol/meta.ex has 9, spec records 2
  MCP.Transport.StreamableHTTP.Plug: lib/mcp/transport/streamable_http/plug.ex has 0, spec records 1
SWEEP DONE exit=1
```

**No verdict was measured at this boundary.** Cause and remedy: S13-9, **→ MES-171**. Until
MES-171 lands, the committed table dates from 5047a0e. The one-sprint rot bound in the
CLAUDE.md sweep section does not hold for Sprint 13; it is exceeded.


## Open for the PO at this boundary

See the question table posted with this register.
