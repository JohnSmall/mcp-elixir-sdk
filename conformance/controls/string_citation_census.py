#!/usr/bin/env python3
"""String-form `file:N` citation census over the conformance artefacts (MES-167).

EVIDENCE, NOT A GATE. This file is wired into no mix task, no DoD gate and no
test, and nothing runs it automatically. It is the instrument MES-167 used to
measure and re-resolve the `file:N` / `file:N-M` citations written as prose
inside conformance/data and docs/conformance. It is kept so a reviewer can
re-run the measurement instead of trusting a figure. It is SUPERSEDED by the
string-citation guard of MES-192 (MES-167 split (d)) once that lands.

    python3 -I conformance/controls/string_citation_census.py <repo> <rev> [-o OUT.json]

<repo> is a checkout and <rev> the commit to measure, e.g. `. c15ddf4`. Every
byte is read from git objects at <rev> (never the working tree), so a dirty
tree cannot move the figures. Read-only: it writes OUT.json and nothing else.

## What it counts

Every tracked file under conformance/data and docs/conformance at <rev>. In
each, every token of the form `path/or/basename.ex[s]:N` or `…:N-M` (range
separator `-`, an en dash, or its JSON escape). A token resolves to a tracked
.ex/.exs file by exact path, path suffix or basename. Both forms are counted:
the basename-only form missed the path form (MES-161 30355). A token that
resolves to no tracked file is reported as `external`.

## How a citation is judged: by intent, not by the nearest token

The bytes a citation meant are the cited window AT THE COMMIT THAT FIRST
INTRODUCED THAT STRING into that artefact (`git log --reverse -S`). Blame is
a second anchor. Blame alone is wrong here: a line rewritten by a later
commit (MES-84's re-addressing, MES-161's) keeps cites it never re-resolved.

  intact               window at the tip == window at introduction
  intact:trivial_line  ... but the window is blank / `end` (wrong since authored)
  stale:moved          the introduced window occurs exactly once elsewhere at the tip
  stale:moved_ambiguous  it occurs more than once
  stale:changed        it occurs nowhere at the tip
  stale:out_of_range   the address is past the end of the file

`anchor_conflict` marks a row whose blame commit holds different bytes at the
address than the introduction commit. `token_in_window` is false when the
`name/arity` written just before the cite is not in the tip window. A row
with either flag needs a reading, not a rewrite.

## What this census cannot see (residuals)

  * The authoring tree is not the squash-merge tree. A record written on a
    branch whose base trailed `main` was authored against other bytes than the
    merge commit holds, so the introduction anchor can misjudge it. Such rows
    were settled in MES-167 by owner test, quoted code and prose, not by the
    census.
  * Intent beyond bytes: a cite whose bytes are unchanged but whose sentence
    no longer describes the code (a request MES-161 re-shaped) reads `intact`.
  * Bare continuations (`:713` after `plug.ex:687, `) and other forms ("lines
    X-Y of f") are not tokens here.
  * Declared classes (sweep measurements, dated publications, D-record
    citations anchored with `at` under MES-161 30337 Q9, gate-5-checked D1
    readings) are counted like any other row. Partitioning them is the
    reader's job, and MES-167's close-out lists that partition.
"""
import json
import re
import subprocess
import sys

ROOTS = ("conformance/data/", "docs/conformance/")
CITE = re.compile(
    r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.exs?):(\d+)(?:(?:-|–|\\u2013)(\d+))?(?![\d])"
)
TOKEN = re.compile(r"`(?:[A-Z][\w.]*\.)?([a-z_][\w?!]*)/\d")
TRIVIAL = ("", "end", "end)", "}", "]", ")")


def main(argv):
    repo, rev = argv[0], argv[1]
    out = argv[argv.index("-o") + 1] if "-o" in argv else "string_citation_census.json"

    def git(*args):
        return subprocess.run(
            ["git", "-C", repo, *args], capture_output=True, text=True, errors="replace"
        ).stdout

    cache = {}

    def show(at, path):
        if (at, path) not in cache:
            r = subprocess.run(
                ["git", "-C", repo, "show", f"{at}:{path}"],
                capture_output=True, text=True, errors="replace",
            )
            cache[(at, path)] = r.stdout.split("\n") if r.returncode == 0 else None
        return cache[(at, path)]

    def window(lines, a, b):
        if lines is None or a < 1 or b > len(lines):
            return None
        return [l.strip() for l in lines[a - 1:b]]

    def blame(path):
        rows, lines, i = {}, git("blame", "--porcelain", rev, "--", path).split("\n"), 0
        while i < len(lines):
            h = lines[i].split(" ")
            if len(h) >= 3 and re.fullmatch(r"[0-9a-f]{40}", h[0]):
                sha, final = h[0], int(h[2])
                i += 1
                while i < len(lines) and not lines[i].startswith("\t"):
                    i += 1
                rows[final] = sha
            i += 1
        return rows

    tracked = git("ls-tree", "-r", "--name-only", rev).splitlines()
    sources = [p for p in tracked if re.search(r"\.exs?$", p)]
    by_base = {}
    for p in sources:
        by_base.setdefault(p.rsplit("/", 1)[-1], []).append(p)
    artefacts = [p for p in tracked if p.startswith(ROOTS)]

    rows, intro = [], {}
    for art in artefacts:
        text = show(rev, art)
        if text is None:
            continue
        blamed = None
        for n, line in enumerate(text, 1):
            for m in CITE.finditer(line):
                tok, a = m.group(1), int(m.group(2))
                b = int(m.group(3)) if m.group(3) else a
                hits = (
                    [p for p in sources if p == tok or p.endswith("/" + tok)]
                    if "/" in tok
                    else by_base.get(tok, [])
                )
                r = dict(art=art, line=n, cite=m.group(0), a=a, b=b,
                         form="path" if "/" in tok else "basename")
                if not hits:
                    r.update(cls="external", target=tok)
                    rows.append(r)
                    continue
                if blamed is None:
                    blamed = blame(art)
                cb = blamed.get(n)
                key = (art, m.group(0))
                if key not in intro:
                    found = git("log", "--format=%H", "--reverse", "-S" + m.group(0), rev, "--", art).split()
                    intro[key] = found[0] if found else cb
                ci = intro[key] or cb
                cands = [(t, window(show(rev, t), a, b), window(show(ci, t), a, b)) for t in hits]
                target, head, then = ([c for c in cands if c[2] is not None] or cands)[0]
                r.update(target=target, introduced=ci[:7], blamed=cb[:7], ambiguous_target=len(hits) > 1)
                if head is None:
                    r["cls"] = "stale:out_of_range"
                elif then is None:
                    r["cls"] = "unverifiable:target_absent_at_introduction"
                elif head == then:
                    r["cls"] = "intact:trivial_line" if all(x in TRIVIAL for x in head) else "intact"
                else:
                    tip = [l.strip() for l in show(rev, target)]
                    k = len(then)
                    at = [i + 1 for i in range(len(tip) - k + 1) if tip[i:i + k] == then]
                    r["cls"] = ("stale:moved" if len(at) == 1
                                else "stale:moved_ambiguous" if at else "stale:changed")
                    if len(at) == 1:
                        r["to"] = at[0]
                if cb != ci:
                    r["anchor_conflict"] = window(show(cb, target), a, b) != then
                names = TOKEN.findall(line[max(0, m.start() - 160):m.start()])
                if names and head is not None:
                    r["token"] = names[-1]
                    r["token_in_window"] = any(names[-1] in x for x in head)
                rows.append(r)

    with open(out, "w") as f:
        json.dump(rows, f, indent=1)
    counts = {}
    for r in rows:
        counts[r["cls"]] = counts.get(r["cls"], 0) + 1
    print(f"{len(rows)} citation(s) in {len(artefacts)} artefact(s) at {rev}: "
          + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))


if __name__ == "__main__":
    main(sys.argv[1:])
