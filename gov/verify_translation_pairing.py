#!/usr/bin/env python3
"""Verify bilingual pairing (the external-presentation layer).

Every human-facing document is a three-file pair: ``foo.md`` + ``foo.zh.md``
+ ``foo.i18n.yaml``. The yaml records each side's git blob hash as of the last
confirmed-consistent moment, in the form::

    pair:
      en: <sha>
      zh: <sha>

Editing either side without re-confirming goes red. ``--write <pair>``
re-records both hashes — the explicit "the pair was re-confirmed" act.
AGENTS.md (agent instructions) and notes under ``.agents/notes/`` are
English-only and out of scope; only the external-presentation docs pair.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCOPE_DIRS = [Path("docs")]
SCOPE_FILES = [Path("README.md")]
# Working design log, not external presentation: English-only like the notes.
SKIP = {Path("docs/decisions.md")}


def _blob_hash(path: Path) -> str:
    """Return the git blob SHA for a file (works on the working tree)."""
    proc = subprocess.run(
        ["git", "hash-object", str(path)],
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.strip()


def _parse_record(path: Path) -> dict[str, str]:
    """Parse ``pair: {en, zh}`` into a flat dict."""
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line:
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip()
    return result


def _pairs() -> list[Path]:
    pairs: list[Path] = []
    for f in SCOPE_FILES:
        if f.exists():
            pairs.append(f)
    for d in SCOPE_DIRS:
        if d.exists():
            pairs.extend(sorted(d.rglob("*.md")))
    return [p for p in pairs if not p.name.endswith(".zh.md") and p not in SKIP]


def _record_path(src: Path) -> Path:
    return src.with_name(src.stem + ".i18n.yaml")


def _write_record(src: Path) -> None:
    zh = src.with_name(src.stem + ".zh.md")
    record = _record_path(src)
    record.write_text(
        "pair:\n"
        f"  en: {_blob_hash(src)}\n"
        f"  zh: {_blob_hash(zh)}\n",
        encoding="utf-8",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify bilingual pairing.")
    parser.add_argument("--write", nargs="*", metavar="PAIR",
                        help="re-record one or more pairs (bare stem or any side)")
    args = parser.parse_args(argv)

    if args.write is not None:
        targets = {Path(p) for p in args.write} if args.write else {p for p in _pairs()}
        # Resolve each target to a source-side .md path.
        for t in sorted(targets):
            t = t if t.suffix == ".md" else t
            if t.name.endswith(".zh.md"):
                t = t.with_name(t.name[:-7] + ".md")
            _write_record(t)
            print(f"wrote {_record_path(t)}")
        return 0

    errors: list[str] = []
    pairs = _pairs()
    for src in pairs:
        zh = src.with_name(src.stem + ".zh.md")
        rec = _record_path(src)
        if not zh.exists():
            errors.append(f"{src}: missing counterpart {zh.name}")
            continue
        if not rec.exists():
            errors.append(f"{src}: missing record {rec.name}")
            continue
        recorded = _parse_record(rec)
        current = {"en": _blob_hash(src), "zh": _blob_hash(zh)}
        for side, expect in (("en", src), ("zh", zh)):
            if side not in recorded or not recorded[side]:
                errors.append(f"{rec.name}: missing recorded hash for {side}")
            elif recorded[side] != current[side]:
                errors.append(f"{expect}: out of sync — re-confirm with --write")
    if errors:
        for e in errors:
            print(e)
        print(f"verify_translation_pairing: {len(errors)} violation(s)")
        return 1
    print(f"verify_translation_pairing: {len(pairs)} pair(s) ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
