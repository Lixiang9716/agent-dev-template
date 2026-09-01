#!/usr/bin/env python3
"""Verify bilingual pairing (the external-presentation layer).

Every human-facing document is a pair: the source ``foo.md`` plus a
counterpart translation, pinned by a record ``foo.i18n.yaml`` that stores
each side's git blob hash as of the last confirmed-consistent moment::

    pair:
      en: <sha>
      zh: <sha>
    counterpart: foo.zh.md

Editing either side without re-confirming goes red. ``--write <pair>``
re-records both hashes — the explicit "the pair was re-confirmed" act.
``--write en:<path> zh:<path>`` registers a pair whose counterpart does not
follow the naming convention (e.g. ``foo_CN.md``); the record's
``counterpart`` field then pins that name.

Naming conventions are configuration, not code — ``.gov/pairing.json``
(all keys optional)::

    {
      "include": ["docs/**/*.md", "README.md"],
      "counterparts": ["{stem}.zh.md"],
      "exclude": ["docs/decisions.md"]
    }

A ``counterparts`` pattern is ``{stem}`` plus a literal suffix (no ``/``);
a file ending in that suffix is a counterpart side, never a source.
AGENTS.md (agent instructions) and notes under ``.agents/notes/`` are
English-only and out of scope.
"""
from __future__ import annotations

import argparse
import glob as _glob
import json
import subprocess
import sys
from pathlib import Path

try:  # package context (`gov ...`)
    from .root import anchor_to_git_root
except ImportError:  # direct script execution (self-test runs files by path)
    from root import anchor_to_git_root

CONFIG_PATH = Path(".gov/pairing.json")
STEM = "{stem}"
DEFAULT_CONFIG: dict[str, list[str]] = {
    "include": ["docs/**/*.md", "README.md"],
    "counterparts": [f"{STEM}.zh.md"],
    "exclude": [],
}


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
    """Parse ``pair: {en, zh}`` + ``counterpart:`` into a flat dict."""
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line:
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip()
    return result


def _load_config() -> dict[str, list[str]] | None:
    """Load .gov/pairing.json over the defaults; None means fail loud."""
    cfg = {k: list(v) for k, v in DEFAULT_CONFIG.items()}
    if not CONFIG_PATH.exists():
        return cfg
    try:
        raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"verify_translation_pairing: cannot read {CONFIG_PATH}: {e}", file=sys.stderr)
        return None
    if not isinstance(raw, dict):
        print(f"verify_translation_pairing: {CONFIG_PATH} must be an object", file=sys.stderr)
        return None
    for key, value in raw.items():
        if key not in DEFAULT_CONFIG:
            known = ", ".join(sorted(DEFAULT_CONFIG))
            print(
                f"verify_translation_pairing: unknown key '{key}' in {CONFIG_PATH} "
                f"(known: {known})",
                file=sys.stderr,
            )
            return None
        if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
            print(
                f"verify_translation_pairing: '{key}' in {CONFIG_PATH} "
                "must be an array of strings",
                file=sys.stderr,
            )
            return None
        cfg[key] = list(value)
    for key in ("include", "counterparts"):
        if not cfg[key]:
            print(f"verify_translation_pairing: '{key}' in {CONFIG_PATH} must not be empty", file=sys.stderr)
            return None
    for pattern in cfg["counterparts"]:
        literal = pattern[len(STEM):] if pattern.startswith(STEM) else None
        if literal is None or not literal or "/" in literal or "{" in literal or "}" in literal:
            print(
                f"verify_translation_pairing: counterpart pattern '{pattern}' must be "
                f"'{STEM}' followed by a non-empty literal without '/' or braces",
                file=sys.stderr,
            )
            return None
    return cfg


def _literals(cfg: dict[str, list[str]]) -> list[str]:
    return [p[len(STEM):] for p in cfg["counterparts"]]


def _pinned_sides(directory: Path) -> set[str]:
    """Counterpart names pinned by the .i18n.yaml records in one directory."""
    names: set[str] = set()
    if not directory.is_dir():
        return names
    for rec in directory.glob("*.i18n.yaml"):
        name = _parse_record(rec).get("counterpart", "")
        if name and "/" not in name:
            names.add(name)
    return names


def _sources(cfg: dict[str, list[str]]) -> list[Path]:
    """Every in-scope source .md: matched by include, not a side, not excluded."""
    files: dict[Path, None] = {}
    for pattern in cfg["include"]:
        for match in _glob.glob(pattern, recursive=True):
            p = Path(match)
            if p.is_file():
                files[p] = None
    excluded = set(cfg["exclude"])
    literals = _literals(cfg)
    pinned: dict[Path, set[str]] = {}
    out = []
    for f in sorted(files):
        if str(f) in excluded or f.suffix != ".md":
            continue
        if any(f.name.endswith(lit) for lit in literals):
            continue  # a counterpart side by naming convention
        if f.name in pinned.setdefault(f.parent, _pinned_sides(f.parent)):
            continue  # a counterpart side pinned by an explicit registration
        out.append(f)
    return out


def _record_path(src: Path) -> Path:
    return src.with_name(src.stem + ".i18n.yaml")


def _record_files(cfg: dict[str, list[str]]) -> list[Path]:
    """Every .i18n.yaml in the include scope (deduped, sorted)."""
    files: dict[Path, None] = {}
    for pattern in cfg["include"]:
        for match in _glob.glob(pattern.replace(".md", ".i18n.yaml"),
                                recursive=True):
            p = Path(match)
            if p.is_file():
                files[p] = None
    return sorted(files)


def _recorded_counterpart(src: Path) -> Path | None:
    """The counterpart a record explicitly pins, if any (may not exist)."""
    rec = _record_path(src)
    if not rec.exists():
        return None
    name = _parse_record(rec).get("counterpart", "")
    if not name or "/" in name:
        return None
    return src.parent / name


def _pattern_counterpart(src: Path, cfg: dict[str, list[str]]) -> Path | None:
    """The first existing counterpart derived from the naming conventions."""
    for literal in _literals(cfg):
        cand = src.with_name(src.stem + literal)
        if cand.exists():
            return cand
    return None


def _counterpart(src: Path, cfg: dict[str, list[str]]) -> Path | None:
    """Recorded counterpart wins; conventions derive it otherwise."""
    return _recorded_counterpart(src) or _pattern_counterpart(src, cfg)


def _resolve_source(arg: str, cfg: dict[str, list[str]]) -> Path:
    """Resolve a --write argument (bare stem or any side) to the source .md."""
    p = Path(arg)
    name = p.name
    if name.endswith(".i18n.yaml"):
        name = name[: -len(".i18n.yaml")]
    else:
        for lit in sorted(_literals(cfg), key=len, reverse=True):
            if name.endswith(lit):
                name = name[: -len(lit)]
                break
    if not name.endswith(".md"):
        name += ".md"
    p = p.with_name(name)
    if p.exists():
        return p
    alt = Path("docs") / name
    return alt if alt.exists() else p


def _register(src: Path, zh: Path) -> Path:
    """Write the record pinning both hashes and the counterpart's name."""
    record = _record_path(src)
    record.write_text(
        "pair:\n"
        f"  en: {_blob_hash(src)}\n"
        f"  zh: {_blob_hash(zh)}\n"
        f"counterpart: {zh.name}\n",
        encoding="utf-8",
    )
    return record


def _convention_hint(cfg: dict[str, list[str]]) -> str:
    return ", ".join(cfg["counterparts"])


def _write(items: list[str], cfg: dict[str, list[str]]) -> int:
    explicit = [a for a in items if a.startswith(("en:", "zh:"))]
    if explicit:
        if len(explicit) != len(items):
            print(
                "verify_translation_pairing: cannot mix bare pairs with en:/zh: forms",
                file=sys.stderr,
            )
            return 2
        sides: dict[str, Path] = {}
        for a in explicit:
            key, _, path = a.partition(":")
            if key in sides or not path:
                print(f"verify_translation_pairing: duplicated or empty '{key}:' side", file=sys.stderr)
                return 2
            sides[key] = Path(path)
        if set(sides) != {"en", "zh"}:
            print(
                "verify_translation_pairing: explicit registration needs exactly "
                "en:<path> and zh:<path>",
                file=sys.stderr,
            )
            return 2
        en, zh = sides["en"], sides["zh"]
        if not en.exists():
            print(f"verify_translation_pairing: no such source: {en}", file=sys.stderr)
            return 2
        if not zh.exists():
            print(f"verify_translation_pairing: no such counterpart: {zh}", file=sys.stderr)
            return 2
        if en.suffix != ".md":
            print(f"verify_translation_pairing: source must be a .md file: {en}", file=sys.stderr)
            return 2
        if en.parent != zh.parent:
            print("verify_translation_pairing: counterpart must sit next to the source", file=sys.stderr)
            return 2
        print(f"wrote {_register(en, zh)}")
        if str(en) not in {str(p) for p in _sources(cfg)}:
            print(
                f"note: {en} is outside the pairing include scope; the record is "
                "written but verification will not check it",
                file=sys.stderr,
            )
        return 0

    if items:
        sources = sorted({_resolve_source(a, cfg) for a in items})
    else:
        sources = _sources(cfg)
    wrote = 0
    unpairable = 0
    for src in sources:
        if not src.exists():
            print(f"verify_translation_pairing: no such pair source: {src}", file=sys.stderr)
            return 2  # a named path that does not exist is a typo, not a pair state
        zh = _counterpart(src, cfg)
        problem = None
        if zh is None:
            problem = (
                f"no counterpart for {src} (conventions: {_convention_hint(cfg)}) — "
                f"translate it, or register explicitly: --write en:{src} zh:<path>"
            )
        elif not zh.exists():
            problem = (
                f"recorded counterpart '{zh.name}' for {src} is missing — "
                "re-register: --write en:" + str(src) + " zh:<path>"
            )
        if problem is not None:
            # One unpaired file must not block the baseline of the rest
            # (F3): record what can be recorded, report what cannot.
            print(f"verify_translation_pairing: {problem}", file=sys.stderr)
            unpairable += 1
            continue
        print(f"wrote {_register(src, zh)}")
        wrote += 1
    if unpairable:
        print(
            f"verify_translation_pairing: wrote {wrote}, left {unpairable} "
            "unpairable (see above)",
            file=sys.stderr,
        )
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    anchor_to_git_root("verify_translation_pairing")
    parser = argparse.ArgumentParser(
        prog="gov verify-pairing", description="Verify bilingual pairing."
    )
    parser.add_argument("--write", nargs="*", metavar="PAIR",
                        help="re-record pairs (bare stem or any side); or register an "
                             "explicitly named pair with en:<path> zh:<path>")
    args = parser.parse_args(argv)

    cfg = _load_config()
    if cfg is None:
        return 2

    if args.write is not None:
        return _write(args.write, cfg)

    errors: list[str] = []
    pairs = _sources(cfg)
    for src in pairs:
        zh = _counterpart(src, cfg)
        if zh is None:
            errors.append(
                f"{src}: no counterpart found (conventions: {_convention_hint(cfg)}) — "
                f"translate it, or register one: --write en:{src} zh:<path>"
            )
            continue
        if not zh.exists():
            errors.append(
                f"{src}: recorded counterpart '{zh.name}' is missing — "
                "re-register with --write en:" + str(src) + " zh:<path>"
            )
            continue
        rec = _record_path(src)
        if not rec.exists():
            errors.append(f"{src}: missing record {rec.name} — baseline with --write {src}")
            continue
        recorded = _parse_record(rec)
        current = {"en": _blob_hash(src), "zh": _blob_hash(zh)}
        for side, expect in (("en", src), ("zh", zh)):
            if side not in recorded or not recorded[side]:
                errors.append(f"{rec.name}: missing recorded hash for {side}")
            elif recorded[side] != current[side]:
                errors.append(f"{expect}: out of sync — re-confirm with --write")
    # Wish 14/D28: a record whose both sides are gone is garbage that
    # nothing ever reported — count it.
    for rec in sorted(_record_files(cfg)):
        src = rec.with_suffix("").with_suffix(".md")  # foo.i18n.yaml -> foo.md
        pinned = _parse_record(rec).get("counterpart", "")
        counterpart = rec.parent / pinned if pinned else None
        if not src.exists() and (counterpart is None or not counterpart.exists()):
            errors.append(
                f"{rec}: dangling record — both sides are gone; delete it, or "
                "re-create the source and re-register with --write"
            )

    if errors:
        for e in errors:
            print(e)
        print(f"verify_translation_pairing: {len(errors)} violation(s)")
        return 1
    print(f"verify_translation_pairing: {len(pairs)} pair(s) ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
