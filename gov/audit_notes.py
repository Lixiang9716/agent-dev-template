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

try:  # package context (`gov ...`)
    from .root import anchor_to_git_root
except ImportError:  # direct script execution (self-test runs files by path)
    from root import anchor_to_git_root

IMPLEMENTED = Path(".agents/notes/implemented")
DECISIONS = Path("docs/decisions.md")
GOV_CMD_RX = re.compile(r"`gov ([a-z][a-z0-9-]*)((?: [^`]*?)?)`")  # cmd + args
D_REF_RX = re.compile(r"\bD(\d+)\b")
PATH_RX = re.compile(r"`([A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-/]*\.[A-Za-z0-9]+)`")
PLACEHOLDER_PARTS = {"foo", "bar", "baz", "example", "examples", "xx", "x", "demo", "path"}
SKILLS_DIR = Path(".agents/skills")
# Universal flags every command answers (cli handles them uniformly).
UNIVERSAL_FLAGS = {"-h", "--help", "-v", "--version"}

# Flag registry for the skills-drift check (wish 11/D28). The command set
# is cli._COMMANDS (single source); flags are declared here because the
# argparse parsers are built inside main() at run time. When a flag moves,
# move it here — the self-test case pins the round trip.
FLAGS: dict[str, set[str]] = {
    "run": {"--config", "--mode", "--base", "--gate", "--every-gate",
            "--record", "--json", "--fail-fast", "--verbose"},
    "self-test": {"--scope"},
    "verify-pairing": {"--write"},
    "verify-note-presence": {"--base", "--strict", "--staged"},
    "verify-rubric": {"--path"},
    "verify-decisions": {"--path"},
    "verify-archive": set(),
    "verify-notes": set(),
    "recall": set(),
    "audit-notes": set(),
    "change-scope": {"--base"},
    "review": {"--base", "--hits"},
    "trend": {"--last"},
    "archive-notes": {"--rebaseline"},
    "init": {"--project", "--hooks", "--ci", "--upgrade"},
    "uninstall": {"--project", "--force"},
}


def _known_commands() -> set[str] | None:
    try:
        from . import cli
    except ImportError:
        return None
    return set(cli._COMMANDS)


def _known_decisions() -> set[str] | None:
    """D-numbers in decisions.md.

    None = no decisions file; an EMPTY set = the file exists but parses to
    zero sections (format mismatch) — two states the summary must not
    confuse. Callers treat an empty set as "unchecked", same as None.
    """
    if not DECISIONS.is_file():
        return None
    text = DECISIONS.read_text(encoding="utf-8")
    found = set(re.findall(r"(?m)^## (D\d+) — ", text))
    if not found:
        # A decisions file that parses to zero entries means a format
        # mismatch — treating it as "no decisions" would flag every D-ref
        # as missing. Say so and leave D-refs unchecked instead.
        print(
            f"audit_notes: {DECISIONS} has no '## Dn — ' sections; "
            "check its format (D-refs left unchecked)",
            file=sys.stderr,
        )
        return set()
    return found


def _drift(text: str, commands: set[str]) -> list[str]:
    """Unknown `gov <cmd>` mentions and unknown flags, per mention."""
    found: list[str] = []
    for cmd, rest in sorted(set(GOV_CMD_RX.findall(text))):
        if cmd not in commands:
            found.append(f"unknown command `gov {cmd}`")
            continue
        known_flags = FLAGS.get(cmd)
        if known_flags is None:
            continue  # no flag registry for this command — command check only
        for flag in sorted(set(re.findall(r"(?<!\w)(?:--[a-z][a-z0-9-]*|-h|-v)", rest))):
            if flag in UNIVERSAL_FLAGS:
                continue  # every command answers these (cli handles them)
            if flag not in known_flags:
                found.append(f"unknown flag `{flag}` on `gov {cmd}`")
    return found


def _flags_note(text: str, commands: set[str] | None,
                decisions: set[str] | None) -> list[str]:
    found: list[str] = []
    if commands is not None:
        found.extend(_drift(text, commands))
    if decisions:  # non-empty: the set to check against
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
    anchor_to_git_root("audit_notes")
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

    # Wish 11/D28: skills are the manual agents read most literally —
    # a renamed command or flag silently expires them.
    skills = 0
    if SKILLS_DIR.is_dir():
        for p in sorted(SKILLS_DIR.rglob("*.md")):
            skills += 1
            for flag in _drift(p.read_text(encoding="utf-8"), commands):
                print(f"{p}: {flag}")
                findings += 1
    state = "clean" if not findings else f"{findings} signal(s)"
    if decisions is None:
        extra = f" (no {DECISIONS}; D-refs unchecked)"
    elif not decisions:
        extra = f" ({DECISIONS} has no '## Dn — ' sections; D-refs unchecked)"
    else:
        extra = ""
    print(f"audit_notes: {notes} implemented note(s), {skills} skill file(s), {state}{extra}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
