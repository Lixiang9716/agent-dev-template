#!/usr/bin/env python3
"""Verify Agent Note format.

An implemented note must carry the three required sections from D4:
``## Problem``, ``## Decision``, and ``## Alternatives considered``.
``## Consequences`` is allowed but not required. Archived notes are frozen
(D5) and are not re-checked here.
"""
from __future__ import annotations

import sys
from pathlib import Path

NOTES_DIR = Path(".agents/notes")
REQUIRED_SECTIONS = ("## Problem", "## Decision", "## Alternatives considered")


def check_note(path: Path) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or not lines[0].startswith("# "):
        errors.append("missing title heading (first line must start with '# ')")
        return errors
    header = lines[:6]
    if not any(line.startswith("Status:") for line in header):
        errors.append("missing 'Status:' line in the header block")
    for section in REQUIRED_SECTIONS:
        if section not in text:
            errors.append(f"missing required section '{section}'")
    return errors


def main(argv: list[str] | None = None) -> int:
    notes_root = NOTES_DIR / "implemented"
    notes = sorted(notes_root.rglob("*.md")) if notes_root.exists() else []
    errors: list[str] = []
    for note in notes:
        for err in check_note(note):
            errors.append(f"{note}: {err}")
    if errors:
        for err in errors:
            print(err)
        print(f"verify_notes: {len(errors)} violation(s) in {len(notes)} note(s)")
        return 1
    print(f"verify_notes: {len(notes)} note(s) ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
