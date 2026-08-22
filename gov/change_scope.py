#!/usr/bin/env python3
"""Report what a change touches, and suggest the smallest gate set.

This is the "check only what changed" hint (rule 9). It does not run gates;
it maps the touched surfaces to the gates that cover them so a developer
picks the smallest sufficient set instead of reflexively running everything.
"""
from __future__ import annotations

import argparse
import subprocess
import sys

SURFACE_GATES = {
    "governance": ["self-test"],
    "notes": ["notes"],
    "docs": ["pairing", "links"],
    "config": ["self-test"],
}


def _classify(path: str) -> str:
    if path.startswith(".agents/notes/"):
        return "notes"
    if path.endswith(".md"):
        return "docs"
    if path in ("gates.json",) or path.startswith(("gates.py", "verify_", "self_test", "gov.py", "change_scope")):
        return "governance"
    return "code"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Report touched surfaces since a base ref.")
    parser.add_argument("--base", default="HEAD~1", help="git ref to diff against")
    args = parser.parse_args(argv)
    try:
        proc = subprocess.run(
            ["git", "diff", "--name-only", args.base],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"change_scope: git diff failed: {e.stderr.strip()}", file=sys.stderr)
        return 2
    files = [f for f in proc.stdout.splitlines() if f]
    if not files:
        print(f"change_scope: no changes since {args.base}")
        return 0

    surfaces = sorted({_classify(f) for f in files})
    gates = sorted({g for s in surfaces for g in SURFACE_GATES.get(s, [])})
    print(f"touched surfaces: {', '.join(surfaces)}")
    for s in surfaces:
        changed = [f for f in files if _classify(f) == s]
        print(f"  {s}: {len(changed)} file(s)")
    print(f"suggested gates: {', '.join(gates) or 'code gates (project toolchain)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
