#!/usr/bin/env python3
"""The decisions source: one loader, three consumers (#17/D32).

The decisions plane hardcoded ``docs/decisions.md`` — a project keeping
its table inside DESIGN.md got a vacuous green ("no decisions table")
while its notes referenced D1–D26. One loader now serves
verify-decisions, audit-notes, and recall:

- default source: ``docs/decisions.md`` (``sections`` format —
  ``## Dn — title`` headings, as govrail itself uses);
- configurable: ``.gov/decisions.json`` ``{"path": "DESIGN.md",
  "format": "table"}`` — ``table`` parses markdown-table rows whose
  first cell is ``Dn``; an alternatives column in the header satisfies
  the alternatives check for every row;
- no source at all: the loader says so, and the consumers refuse the
  vacuous pass when notes reference D-refs into nothing.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

CONFIG = Path(".gov/decisions.json")
DEFAULT_PATH = Path("docs/decisions.md")
SECTION_RX = re.compile(r"(?m)^## (D\d+) — .*$")
ROW_RX = re.compile(r"(?m)^\|\s*(D\d+)\s*\|.*$")  # whole row line
ALT_RX = re.compile(r"被否|选项|否决|[Aa]lternatives")


@dataclass
class Source:
    path: Path
    fmt: str  # sections | table
    text: str

    def entries(self) -> list[tuple[str, str, str]]:
        """(D-number, title, body) in file order.

        sections: title is the full ``## Dn — title`` line, body the rest.
        table: title and body are both the row (a row is one line).
        """
        if self.fmt == "table":
            out = []
            for m in ROW_RX.finditer(self.text):
                row = m.group(0).strip()
                first_cell = row.strip("|").split("|")[0].strip()
                out.append((m.group(1), f"{m.group(1)} — {first_cell}", row))
            return out
        parts = SECTION_RX.split(self.text)
        # split yields [pre, id1, body1, id2, body2, ...] — the heading
        # text is the first line of the ORIGINAL section; recover it by
        # re-matching headings in order.
        headings = [m.group(0).lstrip("# ").strip() for m in
                    re.finditer(r"(?m)^## (D\d+) — .*$", self.text)]
        triples = []
        for i, idx in enumerate(range(1, len(parts) - 1, 2)):
            title = headings[i] if i < len(headings) else parts[idx]
            triples.append((parts[idx], title, parts[idx + 1]))
        return triples

    def header_has_alternatives(self) -> bool:
        return bool(ALT_RX.search(self.text))


def load() -> Source | None:
    """The configured or default source; None when nothing exists."""
    path, fmt = DEFAULT_PATH, "sections"
    if CONFIG.is_file():
        try:
            cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            cfg = {}
        p = cfg.get("path")
        if isinstance(p, str) and p:
            path = Path(p)
        f = cfg.get("format")
        if f in ("sections", "table"):
            fmt = f
    if not path.is_file():
        return None
    return Source(path=path, fmt=fmt, text=path.read_text(encoding="utf-8"))
