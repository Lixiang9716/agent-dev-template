#!/usr/bin/env python3
"""Audit implemented notes for mechanical staleness signals.

The note contract says implemented notes are kept current with the shipped
facts; drift is silent. This audit reports mechanical signals only —
references the world no longer satisfies:

- backticked ``gov <subcommand>`` mentions that this CLI does not know;
- ``Dn`` references with no ``## Dn —`` entry in ``docs/decisions.md``
  (checked only when that file exists);
- backticked repo paths (directory separator plus extension, no globs,
  no obvious placeholders) that do not resolve from the project root.

Archived notes are frozen (D5) and exempt by design. Findings are evidence
for the archive-agent-notes skill's judgment, not a verdict: exit 0 with or
without findings, exit 2 only when the tree cannot be read. Package mode
only (`gov audit-notes`) — the command signal needs the CLI's own registry.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

IMPLEMENTED = Path(".agents/notes/implemented")
DECISIONS = Path("docs/decisions.md")
GOV_CMD_RX = re.compile(r"`gov ([a-z][a-z0-9-]*)`")
D_REF_RX = re.compile(r"\bD(\d+)\b")
PATH_RX = re.compile(r"`([A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-/]*\.[A-Za-z0-9]+)`")
PLACEHOLDER_PARTS = {"foo", "bar", "baz", "example", "examples", "xx", "x", "demo", "path"}


def _known_commands() -> set[str] | None:
    try:
        from . import cli
    except ImportError:
        return None
    return set(cli._COMMANDS)


def _known_decisions() -> set[str] | None:
    if not DECISIONS.is_file():
        return None
    text = DECISIONS.read_text(encoding="utf-8")
    return set(re.findall(r"(?m)^## (D\d+) — ", text))


def _flags_note(text: str, commands: set[str] | None,
                decisions: set[str] | None) -> list[str]:
    found: list[str] = []
    if commands is not None:
        for cmd in sorted(set(GOV_CMD_RX.findall(text))):
            if cmd not in commands:
                found.append(f"unknown command `gov {cmd}`")
    if decisions is not None:
        for d in sorted(set(D_REF_RX.findall(text)), key=int):
            if f"D{d}" not in decisions:
                found.append(f"references D{d}, not in {DECISIONS}")
    for raw in sorted(set(PATH_RX.findall(text))):
        if "*" in raw or "{" in raw:
            continue
        parts = Path(raw).parts
        names = set(parts) | {Path(part).stem for part in parts}
        if names & PLACEHOLDER_PARTS:
            continue
        if not Path(raw).exists():
            found.append(f"unresolved path `{raw}` (may be illustrative)")
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gov audit-notes",
        description="Report mechanical staleness signals in implemented notes.",
    )
    parser.parse_args(argv)

    commands = _known_commands()
    if commands is None:
        print("audit_notes: needs package mode — run as `gov audit-notes`", file=sys.stderr)
        return 2
    if not IMPLEMENTED.is_dir():
        print(f"audit_notes: {IMPLEMENTED} not found — is this a project root?", file=sys.stderr)
        return 2
    decisions = _known_decisions()

    findings = 0
    notes = 0
    for p in sorted(IMPLEMENTED.rglob("*.md")):
        notes += 1
        text = p.read_text(encoding="utf-8")
        for flag in _flags_note(text, commands, decisions):
            print(f"{p}: {flag}")
            findings += 1
    state = "clean" if not findings else f"{findings} signal(s)"
    extra = "" if decisions is not None else f" (no {DECISIONS}; D-refs unchecked)"
    print(f"audit_notes: {notes} implemented note(s), {state}{extra}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
