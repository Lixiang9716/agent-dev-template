#!/usr/bin/env python3
"""Assemble the review dossier for a diff (D28, wish 10).

The code-review skill expects a reviewer to recall first and grade against
the rubric — but assembling the material was four manual commands. This
command produces the dossier in one shot:

1. **Change scope** — surfaces and suggested gates (change-scope's data);
2. **In-scope notes** — notes touched by the diff, and whether the change
   carries one when it should (note-presence's data);
3. **Recall** — memory hits for the change's own keywords (top 5);
4. **Rubric items** — the item list, when the project maintains one
   (three sections, gracefully, when it does not).

Bad refs abort with exit 2 (fail loud). The reviewer — human or agent —
starts from the dossier, not from a cold repository.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:  # package context (`gov ...`)
    from . import change_scope as cs
    from . import recall as rc
    from . import verify_note_presence as vnp
    from . import verify_rubric as vr
except ImportError:  # direct script execution
    import change_scope as cs
    import recall as rc
    import verify_note_presence as vnp
    import verify_rubric as vr

RUBRIC = Path("docs/review-rubric.md")


def _keywords(files: list[str], limit: int = 5) -> list[str]:
    """Distinctive path tokens of the change — recall terms, not stopwords."""
    stop = {"main", "index", "init", "test", "tests", "src", "lib", "docs",
            "config", "setup", "utils", "core", "app"}
    seen: list[str] = []
    for f in files:
        for token in re.split(r"[/_\-\.]+", Path(f).stem) + [Path(f).parent.name]:
            token = token.strip().lower()
            if len(token) < 4 or token in stop or token in seen:
                continue
            seen.append(token)
    return seen[:limit]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gov review",
        description="Assemble the review dossier for a diff (scope, notes, recall, rubric).",
    )
    parser.add_argument("--base", default="HEAD",
                        help="git ref to diff against (default: HEAD — the working tree)")
    parser.add_argument("--hits", type=int, default=5,
                        help="recall hits to include (default: 5)")
    args = parser.parse_args(argv)

    files, err = cs._changed(args.base)
    if err is not None:
        print(f"review: cannot diff against {args.base!r}: {err}", file=sys.stderr)
        return 2
    if not files:
        print(f"review: no changes since {args.base}")
        return 0

    surfaces_cfg = cs._load_surfaces()

    print("## 1. change scope")
    names = sorted({cs._classify(f, surfaces_cfg) for f in files})
    for s in names:
        changed = [f for f in files if cs._classify(f, surfaces_cfg) == s]
        print(f"  {s}: {len(changed)} file(s)")
        for f in changed[:5]:
            print(f"    {f}")
        if len(changed) > 5:
            print(f"    …and {len(changed) - 5} more")
    suggested, from_paths = cs._suggest_gates(files, surfaces_cfg)
    source = "gates.json paths" if from_paths else "surface fallback"
    print(f"  suggested gates ({source}): {', '.join(suggested) or 'code gates'}")

    print("## 2. notes in this change")
    notes = [f for f in files if f.startswith(".agents/notes/")]
    for f in notes:
        print(f"  {f}")
    if not notes:
        non_trivial = [f for f in files if not vnp._is_trivially_scoped(f)]
        if non_trivial:
            shown = ", ".join(non_trivial[:5])
            more = f" …and {len(non_trivial) - 5} more" if len(non_trivial) > 5 else ""
            print(f"  WARNING: {len(non_trivial)} behavior-bearing file(s) ({shown}{more}) "
                  "with no note change (rule 2)")

    print("## 3. recall (change keywords)")
    terms = _keywords(files)
    if not terms:
        print("  (no distinctive keywords in the diff)")
    else:
        print(f"  terms: {', '.join(terms)}")
        entries = rc._entries()
        scored: list[tuple[int, str, str]] = []
        for e in entries:
            best = None
            for t in terms:
                got = rc._score(e, [t])
                if got:
                    rank, where = got
                    if best is None or rank > best[0]:
                        best = (rank, e.source, where)
            if best:
                scored.append((*best, ) if False else (best[0], best[1], best[2]))
        scored.sort(key=lambda h: (-h[0], "/archived/" in h[1], h[1]))
        if not scored:
            print("  (no memory hits — you may be first; plan the note)")
        for rank, source, where in scored[: args.hits]:
            print(f"  {source} — matched in {where}")

    if RUBRIC.is_file():
        print("## 4. rubric")
        text = RUBRIC.read_text(encoding="utf-8")
        for heading in re.findall(r"(?m)^### (R\d+ — .+)$", text):
            print(f"  {heading}")
        print("  grade only the items the diff touches, each with evidence")
    else:
        print("  (no review rubric — reviewing without one)")

    print(f"review: dossier for {len(files)} file(s) vs {args.base}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
