#!/usr/bin/env python3
"""Verify that a non-trivial change carries an Agent Note (D3, rule 2).

Rule 2 of ``.gov/rules.md``: every non-trivial change adds or updates at
least one note. This gate checks the observable half of that promise —
whether a diff that touches behavior-bearing surfaces (code, contracts,
tooling, config) also touches ``.agents/notes/implemented/``. Whether a
specific change is *trivial* stays a human judgment; this gate only warns,
naming the rule, so the warning is a prompt rather than a verdict.

By default a violation is a warning (exit 0, D3: warn, never block);
``--strict`` turns it into a blocking failure (exit 1) for teams that have
earned it. The default base is ``HEAD`` — the working tree and index, the
natural unit of a local pre-push check, and a ref that exists from a
repository's first commit (CI passes an explicit ``--base origin/main`` or
similar). Unrunnable prerequisites (git failure, bad ref) exit 2 — fail
loud, never silently pass.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

NOTES_DIR = ".agents/notes/implemented"
RULE = ".gov/rules.md rule 2 (every non-trivial change carries an Agent Note)"

# Surfaces whose change is presumptively non-trivial. Documentation and the
# notes themselves are excluded: docs answer to the pairing gate, and a
# notes-only diff is the note. Root-level presentation files (README,
# CHANGELOG) are trivial; other root .md files (DESIGN.md, ARCHITECTURE.md)
# are treated as behavior-bearing — in doc-driven repositories they are the
# contract (D20).
TRIVIAL_PREFIXES = (".agents/notes/", "docs/")
TRIVIAL_ROOT_STEMS = ("README", "CHANGELOG", "CHANGES", "CONTRIBUTING")
TRIVIAL_SUFFIXES = (".i18n.yaml",)


def _is_trivially_scoped(path: str) -> bool:
    if path.startswith(TRIVIAL_PREFIXES):
        return True
    if "/" in path:
        return path.endswith(TRIVIAL_SUFFIXES)
    stem = path[: -len(".md")] if path.endswith(".md") else path
    return stem.startswith(TRIVIAL_ROOT_STEMS)


def _changed_files(base: str) -> tuple[list[str], str | None]:
    """Tracked diff plus untracked files against ``base``; error message."""
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gov verify-note-presence",
        description="Warn when a non-trivial diff carries no Agent Note.",
    )
    parser.add_argument("--base", default="HEAD",
                        help="git ref to diff against (default: HEAD — the "
                             "working tree; CI passes an explicit ref)")
    parser.add_argument("--strict", action="store_true",
                        help="a violation blocks (exit 1) instead of warning")
    args = parser.parse_args(argv)

    files, err = _changed_files(args.base)
    if err is not None:
        print(f"verify_note_presence: cannot diff against {args.base!r}: {err}",
              file=sys.stderr)
        return 2

    non_trivial = [f for f in files if not _is_trivially_scoped(f)]
    notes = [f for f in files if f.startswith(NOTES_DIR)]

    if not non_trivial or notes:
        # Nothing behavior-bearing, or the change carries its note.
        print(f"verify_note_presence: {len(non_trivial)} non-trivial file(s), "
              f"{len(notes)} note file(s) — ok")
        return 0

    listing = ", ".join(non_trivial[:5]) + ("…" if len(non_trivial) > 5 else "")
    print(f"verify_note_presence: {len(non_trivial)} non-trivial file(s) "
          f"({listing}) changed with no note under {NOTES_DIR}/")
    print(f"  if the change is non-trivial, add or update a note (see {RULE})")
    print("  if it is truly trivial (typo, format, local rename), ignore this warning")
    if args.strict:
        print("verify_note_presence: violation (--strict)")
        return 1
    print("verify_note_presence: warning (advisory; --strict to enforce)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
