#!/usr/bin/env python3
"""Report what a change touches, and suggest the smallest gate set.

This is the "check only what changed" hint (rule 1). It does not run gates;
it maps the touched files to the gates that cover them so a developer picks
the smallest sufficient set instead of reflexively running everything.

Suggestions come from the single source of truth: each gate's ``paths``
globs in ``gates.json`` (gates without ``paths`` are always relevant and
always suggested). When the config has no ``paths`` at all, a surface-based
fallback applies. It also reminds whether the diff carries an Agent Note
(rule 2) — the same check ``gov verify-note-presence`` gates.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

try:  # package context (`gov change-scope`)
    from .gates import _glob_regex
except ImportError:  # direct script execution (self-test runs files by path)
    from gates import _glob_regex

# Fallback when gates.json declares no per-gate paths (legacy configs).
SURFACE_GATES = {
    "governance": ["self-test"],
    "notes": ["notes"],
    "docs": ["pairing"],
    "config": ["self-test"],
}
NOTES_DIR = ".agents/notes/implemented"


def _classify(path: str) -> str:
    if path.startswith(".agents/notes/"):
        return "notes"
    if path.endswith(".md"):
        return "docs"
    if path in ("gates.json",) or path.startswith(("gov/", "tests/")):
        return "governance"
    return "code"


def _changed(base: str) -> tuple[list[str], str | None]:
    files: set[str] = set()
    for cmd in (
        ["git", "diff", "--name-only", base],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            return [], proc.stderr.strip()
        files.update(f for f in proc.stdout.splitlines() if f)
    return sorted(files), None


def _suggest_gates(files: list[str]) -> tuple[list[str], bool]:
    """Gate ids covering the change; True when sourced from gates.json paths."""
    try:
        with open("gates.json", encoding="utf-8") as f:
            cfg = json.load(f)
        gates = cfg.get("gates", [])
    except (OSError, json.JSONDecodeError):
        gates = []
    if any(g.get("paths") for g in gates if isinstance(g, dict)):
        suggested = [
            g["id"]
            for g in gates
            if isinstance(g, dict) and "id" in g
            and (not g.get("paths")
                 or any(_glob_regex(p).match(f) for p in g["paths"] for f in files))
        ]
        return sorted(suggested), True
    surfaces = {_classify(f) for f in files}
    return sorted({g for s in surfaces for g in SURFACE_GATES.get(s, [])}), False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gov change-scope",
        description="Report touched surfaces since a base ref.",
    )
    parser.add_argument("--base", default="HEAD~1", help="git ref to diff against")
    args = parser.parse_args(argv)

    files, err = _changed(args.base)
    if err is not None:
        print(f"change_scope: git diff failed: {err}", file=sys.stderr)
        return 2
    if not files:
        print(f"change_scope: no changes since {args.base}")
        return 0

    surfaces = sorted({_classify(f) for f in files})
    print(f"touched surfaces: {', '.join(surfaces)}")
    for s in surfaces:
        changed = [f for f in files if _classify(f) == s]
        print(f"  {s}: {len(changed)} file(s)")

    suggested, from_paths = _suggest_gates(files)
    source = "gates.json paths" if from_paths else "surface fallback"
    print(f"suggested gates ({source}): {', '.join(suggested) or 'code gates (project toolchain)'}")
    print("run them: gov run --base " + args.base + "  (or: gov run --gate <id>)")

    non_trivial = [f for f in files if not f.startswith(".agents/notes/")
                   and not (f.endswith((".md", ".i18n.yaml")) and "/" not in f)
                   and not f.startswith("docs/")]
    has_note = any(f.startswith(NOTES_DIR) for f in files)
    if non_trivial and not has_note:
        print("note: no Agent Note in this change — if it is non-trivial, add one "
              "(.gov/rules.md rule 2; gov verify-note-presence checks it)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
