#!/usr/bin/env python3
"""Seal the archived-notes manifest: recompute sha256 for every archived note.

Archived notes are frozen (D5); the manifest pins each file's content hash so
any later edit is detectable. Run this after moving a note into ``archived/``.
Sealing nothing is reported, never written — an empty manifest is a vacuous
seal. Unknown arguments abort (rule 5: fail loud, never silently accept).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

try:  # package context (`gov ...`)
    from .root import anchor_to_git_root
except ImportError:  # direct script execution (self-test runs files by path)
    from root import anchor_to_git_root

NOTES_ROOT = Path(".agents/notes")
ARCHIVED = NOTES_ROOT / "archived"


def main(argv: list[str] | None = None) -> int:
    anchor_to_git_root("archive_notes")
    parser = argparse.ArgumentParser(
        prog="gov archive-notes",
        description="Seal the archived-notes manifest (recompute every sha256).",
    )
    parser.parse_args(argv)  # unknown args abort with exit 2

    if not NOTES_ROOT.is_dir():
        print(
            f"archive_notes: {NOTES_ROOT} not found — run in a governed project root",
            file=sys.stderr,
        )
        return 2

    files: dict[str, dict[str, str]] = {}
    for p in sorted(ARCHIVED.rglob("*.md")):
        rel = str(p.relative_to(ARCHIVED))
        files[rel] = {"sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
    if not files:
        print("archive_notes: nothing to seal (no notes under archived/)")
        return 0

    ARCHIVED.mkdir(parents=True, exist_ok=True)
    (ARCHIVED / "manifest.json").write_text(
        json.dumps({"files": files}, indent=2) + "\n", encoding="utf-8"
    )
    print(f"archive_notes: sealed {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
