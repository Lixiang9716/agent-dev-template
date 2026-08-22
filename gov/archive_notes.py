#!/usr/bin/env python3
"""Seal the archived-notes manifest: recompute sha256 for every archived note.

Archived notes are frozen (D5); the manifest pins each file's content hash so
any later edit is detectable. Run this after moving a note into ``archived/``.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ARCHIVED = Path(".agents/notes/archived")


def main() -> int:
    files: dict[str, dict[str, str]] = {}
    for p in sorted(ARCHIVED.rglob("*.md")):
        rel = str(p.relative_to(ARCHIVED))
        files[rel] = {"sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
    (ARCHIVED / "manifest.json").write_text(
        json.dumps({"files": files}, indent=2) + "\n", encoding="utf-8"
    )
    print(f"archive_notes: sealed {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
