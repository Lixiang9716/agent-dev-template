#!/usr/bin/env python3
"""Recall decisions, notes, and postmortems — the read side of memory.

The notes tree is write-disciplined memory (every non-trivial change
carries a note); this command is its read side: deterministic,
structure-aware retrieval over the planes that carry memory —

- ``.agents/notes/`` (implemented and archived Agent Notes),
- ``docs/decisions.md`` (each ``## Dn — title`` section is one entry),
- ``docs/postmortem/`` entries (everything but the README pair).

All query terms must appear, case-insensitively. Where they appear ranks
the hit: title > section heading > body. No index, no semantics, no
dependencies — this memory is small and versioned; grep with structure is
the honest tool (working memory belongs to the session layer, semantic
recall to tooling that may depend on things).

Exit codes: 0 = hits; 1 = no match (fail loud — never reason from an empty
recall); 2 = usage error or no memory sources found (wrong directory?).
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

try:  # package context (`gov ...`)
    from .root import anchor_to_git_root
except ImportError:  # direct script execution (self-test runs files by path)
    from root import anchor_to_git_root

NOTES = Path(".agents/notes")
DECISIONS = Path("docs/decisions.md")
POSTMORTEM = Path("docs/postmortem")
D_SECTION_RX = re.compile(r"(?m)^## (D\d+ — .+)$")


@dataclass
class Entry:
    source: str  # display path (docs/decisions.md#D14 for decision sections)
    title: str
    headings: list[str]
    body: str


def _title_of(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return ""


def _headings_of(text: str) -> list[str]:
    return [line[3:].strip() for line in text.splitlines() if line.startswith("## ")]


def _entries() -> list[Entry]:
    out: list[Entry] = []
    sources = 0
    # Notes are the two lifecycle states (D5) — the same definition
    # verify-notes enforces; anything else under .agents/notes/ is not a
    # note and stays unrecalled.
    for lifecycle in ("implemented", "archived"):
        root = NOTES / lifecycle
        if not root.is_dir():
            continue
        sources += 1
        for p in sorted(root.rglob("*.md")):
            text = p.read_text(encoding="utf-8")
            out.append(Entry(str(p), _title_of(text), _headings_of(text), text))
    if DECISIONS.is_file():
        sources += 1
        text = DECISIONS.read_text(encoding="utf-8")
        parts = D_SECTION_RX.split(text)
        for i in range(1, len(parts) - 1, 2):
            heading = parts[i]
            out.append(
                Entry(
                    source=f"{DECISIONS}#{heading.split(' —')[0]}",
                    title=heading,
                    headings=[],
                    body=parts[i + 1],
                )
            )
    if POSTMORTEM.is_dir():
        sources += 1
        for p in sorted(POSTMORTEM.glob("*.md")):
            if p.name.startswith("README"):
                continue
            text = p.read_text(encoding="utf-8")
            out.append(Entry(str(p), _title_of(text), _headings_of(text), text))
    if sources == 0:
        return []
    return out


def _score(entry: Entry, terms: list[str]) -> tuple[int, str] | None:
    """(rank, where) when every term appears; None when it does not."""
    lowered = [t.lower() for t in terms]
    if all(t in entry.title.lower() for t in lowered):
        return 3, "title"
    for h in entry.headings:
        if all(t in h.lower() for t in lowered):
            return 2, f"section '{h}'"
    if all(t in entry.body.lower() for t in lowered):
        return 1, "body"
    return None


def main(argv: list[str] | None = None) -> int:
    anchor_to_git_root("recall")
    parser = argparse.ArgumentParser(
        prog="gov recall",
        description="Retrieve notes, decisions, and postmortems (all terms, ranked by where they hit).",
    )
    parser.add_argument("query", nargs="+", help="literal terms; all must appear")
    args = parser.parse_args(argv)

    entries = _entries()
    if not entries:
        print(
            "recall: no memory sources found (.agents/notes/, docs/decisions.md, "
            "docs/postmortem/) — is this a project root?",
            file=sys.stderr,
        )
        return 2

    hits: list[tuple[int, str, str]] = []
    for e in entries:
        scored = _score(e, args.query)
        if scored:
            rank, where = scored
            hits.append((rank, e.source, where))
    if not hits:
        print(f"recall: no match for {' '.join(args.query)!r}")
        return 1

    # Equal ranks: current authority (implemented/) outranks frozen
    # evidence (archived/), then path order (F4).
    hits.sort(key=lambda h: (-h[0], "/archived/" in h[1], h[1]))
    for rank, source, where in hits:
        print(f"{source} — matched in {where}")
    print(f"recall: {len(hits)} hit(s) for {' '.join(args.query)!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
