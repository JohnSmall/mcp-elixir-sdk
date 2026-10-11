# Gate 6 — `mix hex.audit`: cost, limitations and the two-step procedure

> **Moved verbatim from `CLAUDE.md` by MES-177** (lines 184-312 at e74bf3f). The gate list
> and gate 6's applicability rule stay in `CLAUDE.md`, *Definition-of-Done Gates*. "The
> end-of-sprint sweep below" is step 2 of `docs/procedure/end-of-sprint.md`; "the 6a snippet
> below" and "the offline finding above" (limitation 1) are on this page.

**Why, and what it costs.** Gate 6 is a *dependency-advisory* gate. A ticket that
changes no dependency cannot fail it for anything that ticket caused, so running it
yields no information about the work under review. It is also the most expensive gate
and the only side-effecting one: 6a materialises a separate tree at `d697093`, runs
`mix deps.get` inside it, and audits 22 advisory ids. **Measured on MES-57:** the
cleanup form in the 6a snippet below was *rejected by CODE_REVIEWER's command guard*
and ran clean twice under CODE_CREATOR's — so the behaviour is **per-seat, not
universal**, and a run that could not have found anything relevant also left a temp
directory behind on the seat that refused it. The distinction decides the remedy: if
the guards merely differ, rewriting the snippet fixes the wrong thing. Recorded as
S5-27; not acted on here.

**What this rule gives up, and where it is picked up.** Gate 6's verdict is a function
of *(lock, wall-clock)* — every other gate's is a function of the tree alone. A
universal gate 6 would therefore catch advisories published *since the last run*,
against dependencies no ticket touched. **Per-ticket, this rule gives that up**: a run
of ticket-shaped work that never touches `mix.lock` never re-audits. That coverage is
not abandoned — it moves to a cadence where it can actually be acted on, the
**end-of-sprint sweep** below (PO-ratified 2026-08-21, settling the cadence half of
PA-9). Per-ticket is the wrong cadence for it in any case: an advisory found mid-sprint
against an untouched dependency is not the reviewing seat's to fix, and blocking a
merge on it would be the one thing nobody wants.

**Gate 6 (`mix hex.audit`) — reproducibility and behaviour.**

- **Toolchain minimum (not a pin).** The hex archive is a Mix archive, not an
  asdf/mise tool, so no `.tool-versions`/declarative mechanism binds its version.
  The documented **minimum is hex ≥ 2.5.1** (the version whose advisory results and
  branch-(b) ignore mechanism are verified). Install an exact version with
  `mix local.hex 2.5.1 --force` (`mix local.hex [version]` is documented). The DoD
  check is `mix hex --version` meeting the minimum. This guarantees nobody runs the
  gate *below* the floor without noticing; it does **not** prevent drift *above* it,
  and a future hex could change the gate's behaviour.
- **Known limitation 1 — false-green on ABSENT/CORRUPT advisory data.** `mix hex.audit`
  reads advisory & retirement data from the **local registry cache**
  (`Registry.open`/`Registry.prefetch`). Confirmed from hex 2.5.1 source: the advisory
  lookup returns `nil` for a missing key (no error, no refetch), and offline `prefetch`
  checks only package **presence**, not advisory-data **completeness** — and it is
  **per-package**, so one package's advisory rows can be absent while another's are
  intact. So an incomplete/corrupt snapshot makes `mix hex.audit` **exit 0 while
  advisories are outstanding**, with no warning; it **runs offline** (`HEX_OFFLINE=1`
  exits 0) and **no native flag forces a refresh** (`HEX_NO_CACHE=1` does not — verified).
  A bare `mix hex.audit` green is not trustworthy by itself. The baseline-lock
  sentinel (6a) **narrows** this limitation to the five advisory-bearing packages —
  it does **not** compensate for it; **21 of 26 packages remain unvalidated** (see
  the residual under 6a). The freshness-independent compensating control is the live
  whole-tree OSV cross-check, owned by MES-19.

- **Known limitation 2 — the gate detects ABSENCE/CORRUPTION, NOT STALENESS, and no
  local mechanism can fix that.** A **complete-but-old** registry that still contains the
  sentinel data passes 6a and 6b while missing every advisory published since the
  snapshot — and staleness is likelier than absence. hex offers no freshness/refresh
  guarantee, so **do not add one here** (claiming a bound that does not hold would be
  worse). **This obligation is discharged elsewhere:** a release must not treat a green
  `mix hex.audit` as publish-blocking evidence on its own — it runs the
  **freshness-independent** whole-tree OSV cross-check with a positive control (this
  ticket's AC4), which queries an external feed live and cannot be stale-green. Owned by
  **MES-19** (release conformance/gating).

- **Compensating control (6a) — a baseline-lock sentinel INSIDE the gate.** Run gate 6
  as two steps; it passes only if 6a passes **and** 6b exits 0 (A7c applied to the gate).
  6a audits the **pre-remediation baseline lock at `d697093`** (sourced from git) and
  requires **all 22 known advisory ids** to be reported — validating advisory rows for
  **every package that has ever carried an advisory in this tree** (`bandit`, `plug`,
  `req`, `mint`, `hpax`), not a single-package sentinel. It asserts a **superset** ("all
  22 present"), never "exactly 22", so a *new* advisory against a baseline version does
  not false-red the gate.

  **What 6a does NOT cover — the residual, stated by enumeration (A2d).** 6a
  validates advisory rows only for the **five** packages that carry the 22 baseline
  ids (`bandit`, `hpax`, `mint`, `plug`, `req`). For every **other** package in the
  tree, limitation 1 is untouched: if that package acquires an advisory and its local
  cache rows are absent, 6a passes and 6b exits 0 over an outstanding advisory
  (demonstrated on `thousand_island` 1.5.0). The residual is therefore **21 of the 26
  locked packages**, not three: `bunt`, `credo`, `dialyxir`, `earmark_parser`,
  `elixir_uuid`, `erlex`, `ex_doc`, `file_system`, **`finch`**, `jason`, `makeup`,
  `makeup_elixir`, `makeup_erlang`, `mime`, `nimble_options`, `nimble_parsec`,
  `nimble_pool`, `plug_crypto`, `telemetry`, **`thousand_island`**, `websock`.
  **`finch` and `thousand_island` are runtime deps on the transport path this SDK
  uses** — the residual is not confined to dev/build tooling.

  This is **irreducible for the sentinel**: a package that has never carried an
  advisory has nothing whose absence is detectable, so no sentinel can validate it
  (attempting to would be the AC7 error — claiming a bound that does not hold). The
  compensating control that *does* cover the remainder is the **live whole-tree OSV
  cross-check** (this ticket's AC4), which queries an external feed and so is not
  limited to what the local cache happens to hold. It is **owned by MES-19** for
  release. **PA-9, restated 2026-08-21 — what remains open is narrower than it was.**
  The question used to be whether the OSV check should join the *per-ticket* gate 6,
  and the standing objection was that this would make a per-ticket gate
  network-dependent, against the offline finding above. The end-of-sprint sweep
  changes that: **at a sprint boundary, network dependence costs nothing** — no work
  is in flight, no merge is blocked, and the run is PM-owned rather than on a seat's
  critical path. So the live question is now whether the OSV cross-check should also
  run at the sprint boundary, giving two independent checks per sprint instead of
  one at release. **Still the PO's, still not decided here** — but decide it against
  the boundary, not against the gate.

  ```bash
  # Gate 6a — baseline-lock sentinel: require ALL 22 known advisory ids (superset).
  # Capture output BEFORE matching (pipefail-safe — no `grep -q` in a pipe); `|| true`
  # because the baseline audit exits 1 by design (it HAS advisories) and that expected
  # nonzero must not abort a `set -e` run. Verified positive+negative under normal AND
  # `set -euo pipefail`.
  KNOWN_IDS="EEF-CVE-2026-8468 EEF-CVE-2026-39803 EEF-CVE-2026-39804 EEF-CVE-2026-39805 EEF-CVE-2026-39806 EEF-CVE-2026-39807 EEF-CVE-2026-42786 EEF-CVE-2026-42788 EEF-CVE-2026-48861 EEF-CVE-2026-48862 EEF-CVE-2026-49753 EEF-CVE-2026-49754 EEF-CVE-2026-49755 EEF-CVE-2026-49756 EEF-CVE-2026-54892 EEF-CVE-2026-56810 EEF-CVE-2026-56813 EEF-CVE-2026-56814 EEF-CVE-2026-58226 EEF-CVE-2026-58229 EEF-CVE-2026-59246 EEF-CVE-2026-59249"
  pc=$(mktemp -d)
  git show d697093:mix.exs  > "$pc/mix.exs"
  git show d697093:mix.lock > "$pc/mix.lock"
  audit_out=$( cd "$pc" && { mix deps.get >/dev/null 2>&1 || true; mix hex.audit 2>&1 || true; } )
  rm -rf "$pc"
  missing=""
  for id in $KNOWN_IDS; do case "$audit_out" in *"$id"*) : ;; *) missing="$missing $id" ;; esac; done
  if [ -n "$missing" ]; then
    echo "GATE 6 FAILS: baseline sentinel missing $(echo $missing | wc -w) of 22 known advisory ids:$missing"
    echo "  Verify each missing id at https://osv.dev BEFORE assuming local cache corruption:"
    echo "   many/all missing together => local advisory data broken/absent (run 'mix deps.get' or rebuild ~/.hex)"
    echo "   exactly one missing alone  => advisory likely withdrawn/renumbered upstream (update KNOWN_IDS, not the cache)"
    exit 1
  fi

  # Gate 6b — the real audit on THIS project. Must exit 0.
  mix hex.audit
  ```

  Verified 2026-08-12: 6a PASSes on the current registry and FAILs (naming the missing
  ids) when a package's advisory rows are stripped from a synthesised cache — shown for
  `bandit` (7 missing) and `plug` (4 missing) — under both ordinary and
  `set -euo pipefail` shells. If a future hex adds a fail-closed freshness mode, gate 6
  can simplify toward a bare invocation.
