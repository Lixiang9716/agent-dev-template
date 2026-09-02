#!/usr/bin/env python3
"""Verify the decisions table — the governance spine gets a guard (D28).

``docs/decisions.md`` is every adopter's spine (govrail's own D0–D27), yet
it was pure prose: D numbering uniqueness/contiguity, the presence of a
rejected-alternatives section, and orphan decisions were all unchecked.
This gate is the verify-rubric pattern applied to decisions:

- D numbers are unique and contiguous from the table's first entry
  (``D0`` or ``D1`` starts are both legal);
- every D records its options or rejected alternatives (a decision without
  what it beat is the notes rule-3 violation wearing a different hat);
- orphan decisions — defined but never D-referenced by any note — are
  reported as information, not violations (a decision may simply predate
  the notes that would cite it).

Exit codes: 0 = table intact (orphans allowed); 1 = violations; 2 =
unreadable table or bad ``--path``.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import date, datetime
from pathlib import Path

try:  # package context (`gov ...`)
    from .root import anchor_to_git_root
except ImportError:  # direct script execution (self-test runs files by path)
    from root import anchor_to_git_root

DEFAULT_PATH = Path("docs/decisions.md")
NOTES = Path(".agents/notes")
D_SECTION_RX = re.compile(r"(?m)^## (D\d+) — .*$")
# A decision must record what it beat — zh tables say 选项/被否, en tables
# say alternatives.
ALT_RX = re.compile(r"被否|选项|[Aa]lternatives")
D_REF_RX = re.compile(r"\bD(\d+)\b")


def _sections(text: str) -> list[tuple[str, str]]:
    parts = D_SECTION_RX.split(text)
    return [(parts[i], parts[i + 1]) for i in range(1, len(parts) - 1, 2)]


def _note_refs() -> set[str]:
    refs: set[str] = set()
    if not NOTES.is_dir():
        return refs
    for lifecycle in ("implemented", "archived"):
        root = NOTES / lifecycle
        if not root.is_dir():
            continue
        for p in root.rglob("*.md"):
            refs.update(f"D{d}" for d in D_REF_RX.findall(p.read_text(encoding="utf-8")))
    return refs


def main(argv: list[str] | None = None) -> int:
    anchor_to_git_root("verify_decisions")
    parser = argparse.ArgumentParser(
        prog="gov verify-decisions",
        description="Verify the decisions table: numbering, alternatives, orphans.",
    )
    parser.add_argument("--path", default=str(DEFAULT_PATH),
                        help=f"decisions table (default: {DEFAULT_PATH})")
    args = parser.parse_args(argv)

    path = Path(args.path)
    if not path.is_file():
        if args.path == str(DEFAULT_PATH):
            print("verify_decisions: no decisions table — nothing to verify")
            return 0
        print(f"verify_decisions: no such table: {path}", file=sys.stderr)
        return 2
    text = path.read_text(encoding="utf-8")

    sections = _sections(text)
    if not sections:
        if args.path == str(DEFAULT_PATH):
            print("verify_decisions: no decisions table entries — nothing to verify")
            return 0
        print(f"verify_decisions: {path} has no '## Dn — ' sections; check its format",
              file=sys.stderr)
        return 2

    violations: list[str] = []
    ids = [d for d, _ in sections]
    seen: set[str] = set()
    for d in ids:
        if d in seen:
            violations.append(f"{d}: duplicate decision entry")
        seen.add(d)
    numbers = sorted(int(d[1:]) for d in set(ids))
    expected = list(range(numbers[0], numbers[0] + len(numbers)))
    if numbers != expected:
        gaps = [f"D{n}" for n in expected if n not in numbers]
        violations.append(
            f"numbering must be contiguous from D{numbers[0]} (missing: {', '.join(gaps)})"
        )
    for d, body in sections:
        if not ALT_RX.search(body):
            violations.append(
                f"{d}: records no options or rejected alternatives (被否/选项) — "
                "a decision without what it beat invites re-litigation"
            )

    orphans = sorted(set(ids) - _note_refs(), key=lambda d: int(d[1:]))

    # Wish 3/D30: decisions may declare a half-life ("review-by: 2026-09-01")
    # — a passed date is a prompt to re-read, reported like orphans.
    overdue: list[str] = []
    for d, body in sections:
        m = re.search(r"(?m)^-\s*\*\*review-by\*\*:?\s*(\S+)", body)
        if not m:
            continue
        try:
            due = date.fromisoformat(m.group(1))
        except ValueError:
            violations.append(f"{d}: unparseable review-by date {m.group(1)!r}")
            continue
        if due < date.today():
            overdue.append(f"{d} (review-by {m.group(1)})")

    for v in violations:
        print(v)
    if orphans:
        print(f"note: referenced by no note: {', '.join(orphans)} (informational)")
    if overdue:
        print(f"note: review due — context may have drifted: {', '.join(overdue)}")
    if violations:
        print(f"verify_decisions: {len(violations)} violation(s) in {len(sections)} decision(s)")
        return 1
    print(f"verify_decisions: {len(sections)} decision(s) ok"
          + (f", {len(orphans)} orphan(s)" if orphans else "")
          + (f", {len(overdue)} review-due" if overdue else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
