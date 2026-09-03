#!/usr/bin/env python3
"""CHANGELOG ↔ HIGHLIGHTS pairing (D37): one updates, the other follows.

The bilingual pairing gate enforces ``foo.md`` ↔ ``foo.zh.md``; this gate
applies the same axiom to the version-facing docs — release-please
updates CHANGELOG.md automatically from commit messages, and the
usage-oriented HIGHLIGHTS.md must carry a section for every released
version, with the version number read FROM CHANGELOG (never guessed).

The gate that catches a missing section is the release workflow itself:
release-please opens the release PR (CHANGELOG gains a section), this
gate goes red, and the fix is pushing the HIGHLIGHTS entry — version
number copied from CHANGELOG — to the same PR.

Exit codes: 0 = paired; 1 = violations; 2 = unreadable source.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:  # package context (`gov ...`)
    from .root import anchor_to_git_root
except ImportError:  # direct script execution
    from root import anchor_to_git_root

CHANGELOG = Path("CHANGELOG.md")
HIGHLIGHTS = Path("gov/HIGHLIGHTS.md")
# Coverage begins where HIGHLIGHTS was born (0.12.0).
FLOOR = (0, 12, 0)


def _versions_from_changelog(text: str) -> list[tuple]:
    return sorted(
        tuple(int(x) for x in v.split("."))
        for v in re.findall(r"(?m)^## \[(\d+\.\d+\.\d+)\]", text)
    )


def _versions_from_highlights(text: str) -> set[tuple]:
    return {
        tuple(int(x) for x in v.split("."))
        for v in re.findall(r"(?m)^## (\d+\.\d+\.\d+) ", text)
    }


def main(argv: list[str] | None = None) -> int:
    anchor_to_git_root("verify_doc_sync")
    parser = argparse.ArgumentParser(
        prog="gov verify-doc-sync",
        description="CHANGELOG ↔ HIGHLIGHTS pairing: every released version "
                    "has a usage-oriented section.",
    )
    parser.parse_args(argv)

    if not CHANGELOG.is_file():
        print("verify_doc_sync: no CHANGELOG.md — nothing to pair")
        return 0
    changelog_text = CHANGELOG.read_text(encoding="utf-8")

    try:
        highlights_text = HIGHLIGHTS.read_text(encoding="utf-8")
    except OSError:
        print(f"verify_doc_sync: cannot read {HIGHLIGHTS}", file=sys.stderr)
        return 2

    released = [v for v in _versions_from_changelog(changelog_text) if v >= FLOOR]
    covered = _versions_from_highlights(highlights_text)

    missing = [v for v in released if v not in covered]
    ahead = [v for v in covered if v not in released and v > (max(released) if released else (0, 0, 0))]

    for v in missing:
        print(f"verify_doc_sync: CHANGELOG has [{_fmt(v)}] but HIGHLIGHTS has "
              f"no section for it — copy the version FROM CHANGELOG and add "
              f"a '## {_fmt(v)}' section")
    for v in ahead:
        print(f"verify_doc_sync: HIGHLIGHTS has {_fmt(v)} but CHANGELOG does "
              f"not — the section shipped before its release; fix the header "
              f"to the released version")

    if missing or ahead:
        print(f"verify_doc_sync: {len(missing)} missing, {len(ahead)} ahead")
        return 1
    print(f"verify_doc_sync: {len(released)} version(s) paired (CHANGELOG ↔ HIGHLIGHTS)")
    return 0


def _fmt(v: tuple) -> str:
    return ".".join(str(x) for x in v)


if __name__ == "__main__":
    raise SystemExit(main())
