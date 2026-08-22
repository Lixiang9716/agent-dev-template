#!/usr/bin/env python3
"""gov — install, uninstall, run, and self-test the governance plane.

Subcommands delegate to the modules in this package; ``init`` injects the
templates shipped as package data, and ``uninstall`` reverses it exactly via
the ``.gov/manifest.json`` it wrote.
"""
from __future__ import annotations

import json
import shutil
import sys
from importlib.resources import files
from pathlib import Path

from . import archive_notes, change_scope, gates, self_test
from . import verify_notes, verify_translation_pairing
from . import __version__

TEMPLATES = files("gov.templates")
REFERENCE_MARKER = "<!-- gov:rules -->"
REFERENCE_LINE = (
    f"{REFERENCE_MARKER} Read .gov/rules.md and follow it before starting work."
)


def _copy(source, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as f:
        dest.write_bytes(f.read())


def _remove_empty_dirs(root: Path) -> None:
    """Remove empty parent dirs, deepest first, stopping at the first non-empty."""
    p = root
    while p != p.parent:
        try:
            p.rmdir()
        except OSError:
            break
        p = p.parent


def init(project: Path) -> int:
    project = project.resolve()
    if not project.is_dir():
        print(f"init: {project} is not a directory", file=sys.stderr)
        return 2
    if (project / ".gov" / "manifest.json").exists():
        print(f"init: {project} is already initialized")
        return 0

    gov_dir = project / ".gov"
    created: list[str] = []

    _copy(TEMPLATES.joinpath("rules.md"), gov_dir / "rules.md")

    if not (project / "gates.json").exists():
        _copy(TEMPLATES.joinpath("gates.json"), project / "gates.json")
        created.append("gates.json")

    notes_readme = project / ".agents" / "notes" / "README.md"
    if not notes_readme.exists():
        _copy(TEMPLATES.joinpath("notes-README.md"), notes_readme)
        created.append(".agents/notes/README.md")

    ag = project / "AGENTS.md"
    if ag.exists():
        text = ag.read_text(encoding="utf-8")
        if REFERENCE_MARKER not in text:
            if text and not text.endswith("\n"):
                text += "\n"
            ag.write_text(text + REFERENCE_LINE + "\n", encoding="utf-8")
    else:
        ag.write_text(REFERENCE_LINE + "\n", encoding="utf-8")

    (gov_dir / "manifest.json").write_text(
        json.dumps({"version": "0.1.0", "created": created}, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"init: initialized {project}")
    print("  .gov/rules.md (rules)")
    if created:
        print("  " + ", ".join(created) + " (created; project had none)")
    print("  AGENTS.md reference line")
    return 0


def uninstall(project: Path) -> int:
    project = project.resolve()
    manifest = project / ".gov" / "manifest.json"
    if not manifest.exists():
        print(f"uninstall: {project} is not initialized", file=sys.stderr)
        return 2
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"uninstall: corrupt manifest {manifest}: {e}", file=sys.stderr)
        return 2

    ag = project / "AGENTS.md"
    if ag.exists():
        kept = [line for line in ag.read_text(encoding="utf-8").splitlines()
                if REFERENCE_MARKER not in line]
        while kept and kept[-1] == "":
            kept.pop()
        if kept:
            ag.write_text("\n".join(kept) + "\n", encoding="utf-8")
        else:
            ag.unlink()

    for rel in data.get("created", []):
        p = project / rel
        if p.exists():
            p.unlink()
            _remove_empty_dirs(p.parent)

    shutil.rmtree(project / ".gov", ignore_errors=True)
    print(f"uninstall: removed governance from {project}")
    return 0


_COMMANDS = {
    "init": "inject the plane into a project",
    "uninstall": "reverse init",
    "run": "run the project's gate DAG (args forwarded to gates.py)",
    "self-test": "run governance rejection cases",
    "verify-notes": "check note format",
    "verify-pairing": "check bilingual pairing (e.g. --write)",
    "change-scope": "report touched surfaces (e.g. --base <ref>)",
    "archive-notes": "seal the archived-notes manifest",
}


def _usage() -> None:
    print("usage: gov <command> [args]", file=sys.stderr)
    print("commands:", file=sys.stderr)
    for name, help_text in _COMMANDS.items():
        print(f"  {name:<16} {help_text}", file=sys.stderr)


_HELP_FLAGS = ("-h", "--help", "help")
_VERSION_FLAGS = ("-v", "--version", "version")
# Commands whose args are NOT forwarded to an argparse parser: they must
# intercept help/version themselves so a trailing flag never runs the action.
_NO_FORWARD = ("init", "uninstall", "self-test", "verify-notes", "archive-notes")


def _init_uninstall_args(args: list[str], what: str) -> Path | None:
    """Parse the only supported flag ``--project <dir>``; reject the rest."""
    project = "."
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--project":
            if i + 1 >= len(args):
                print(f"gov {what}: --project requires a directory", file=sys.stderr)
                return None
            project = args[i + 1]
            i += 2
        else:
            print(f"gov {what}: unexpected argument '{a}'", file=sys.stderr)
            _usage()
            return None
    return Path(project)


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        _usage()
        return 2
    cmd, rest = argv[0], argv[1:]

    if cmd in _HELP_FLAGS:
        _usage()
        return 0
    if cmd in _VERSION_FLAGS:
        print(f"gov {__version__}")
        return 0
    # Subcommand-level help/version: never execute the action as a side effect.
    if cmd in _NO_FORWARD:
        if any(a in _HELP_FLAGS for a in rest):
            _usage()
            return 0
        if any(a in _VERSION_FLAGS for a in rest):
            print(f"gov {__version__}")
            return 0
    if cmd == "init":
        project = _init_uninstall_args(rest, "init")
        return 2 if project is None else init(project)
    if cmd == "uninstall":
        project = _init_uninstall_args(rest, "uninstall")
        return 2 if project is None else uninstall(project)
    if cmd == "run":
        return gates.main(rest)
    if cmd == "self-test":
        return self_test.main()
    if cmd == "verify-notes":
        return verify_notes.main()
    if cmd == "verify-pairing":
        return verify_translation_pairing.main(rest)
    if cmd == "change-scope":
        return change_scope.main(rest)
    if cmd == "archive-notes":
        return archive_notes.main()
    print(f"gov: unknown command '{cmd}'", file=sys.stderr)
    _usage()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
