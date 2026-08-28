#!/usr/bin/env python3
"""gov — install, uninstall, run, and self-test the governance plane.

Subcommands delegate to the modules in this package; ``init`` injects the
templates shipped as package data, and ``uninstall`` reverses it exactly via
the ``.gov/manifest.json`` it wrote. ``init --hooks`` additionally installs a
``pre-push`` hook that runs the gate DAG, and ``init --ci`` generates a
GitHub Actions workflow — both recorded in the manifest and reversed by
``uninstall``.
"""
from __future__ import annotations

import json
import shutil
import sys
from importlib.resources import files
from pathlib import Path

from . import archive_notes, change_scope, gates, self_test
from . import verify_note_presence, verify_notes, verify_translation_pairing
from . import __version__

TEMPLATES = files("gov.templates")
REFERENCE_MARKER = "<!-- gov:rules -->"
REFERENCE_LINE = (
    f"{REFERENCE_MARKER} Read .gov/rules.md and follow it before starting work."
)
HOOK_MARKER = "# govrail:"


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


def _hook_conflict(project: Path) -> bool:
    """True when .git/hooks/pre-push exists and is not a gov hook."""
    git_hook = project / ".git" / "hooks" / "pre-push"
    if not git_hook.exists():
        return False
    try:
        existing = git_hook.read_text(encoding="utf-8")
    except OSError:
        return True
    return HOOK_MARKER not in existing


def _install_hook(project: Path) -> None:
    """Write .gov/hooks/pre-push and wire it into .git/hooks (both executable)."""
    data = TEMPLATES.joinpath("pre-push").read_bytes()
    hook_dir = project / ".gov" / "hooks"
    hook_dir.mkdir(parents=True, exist_ok=True)
    for dest in (hook_dir / "pre-push", project / ".git" / "hooks" / "pre-push"):
        dest.write_bytes(data)
        dest.chmod(0o755)


def _install_ci(project: Path, created: list[str]) -> None:
    """Generate .github/workflows/gov.yml only when it does not exist."""
    workflow = project / ".github" / "workflows" / "gov.yml"
    if workflow.exists():
        print("init: .github/workflows/gov.yml already exists; leaving it untouched")
        return
    workflow.parent.mkdir(parents=True, exist_ok=True)
    workflow.write_bytes(TEMPLATES.joinpath("gov.yml").read_bytes())
    created.append(".github/workflows/gov.yml")


def init(project: Path, hooks: bool = False, ci: bool = False) -> int:
    project = project.resolve()
    if not project.is_dir():
        print(f"init: {project} is not a directory", file=sys.stderr)
        return 2
    if (project / ".gov" / "manifest.json").exists():
        print(f"init: {project} is already initialized")
        return 0

    # Pre-flight the add-ons: fail loud before mutating anything, so a
    # conflict never leaves a half-initialized project with no manifest.
    if hooks and not (project / ".git").is_dir():
        print("init: --hooks needs a git repository (no .git found)", file=sys.stderr)
        return 2
    if hooks and _hook_conflict(project):
        print(
            f"init: refusing to overwrite {project / '.git' / 'hooks' / 'pre-push'} — "
            "it is not a gov hook; merge the two by hand",
            file=sys.stderr,
        )
        return 2

    gov_dir = project / ".gov"
    created: list[str] = []
    git_hooks: list[str] = []

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

    if hooks:
        _install_hook(project)
        git_hooks.append("pre-push")
    if ci:
        _install_ci(project, created)

    (gov_dir / "manifest.json").write_text(
        json.dumps(
            {"version": __version__, "created": created, "gitHooks": git_hooks},
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"init: initialized {project}")
    print("  .gov/rules.md (rules)")
    if created:
        print("  " + ", ".join(created) + " (created; project had none)")
    print("  AGENTS.md reference line")
    if hooks:
        print("  .gov/hooks/pre-push + .git/hooks/pre-push (runs gov run before push)")
    if ci and ".github/workflows/gov.yml" in created:
        print("  .github/workflows/gov.yml (CI runs gov run)")

    if "gates.json" in created:
        print("next steps:")
        print("  1. gov run                        # pairing runs advisory until baselined")
        print("  2. gov verify-pairing --write     # baseline doc pairs (writes .i18n.yaml records)")
        print("  3. remove \"allowFailure\" from the pairing gate in gates.json to enforce")
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

    for name in data.get("gitHooks", []):
        p = project / ".git" / "hooks" / name
        if p.exists():
            p.unlink()

    shutil.rmtree(project / ".gov", ignore_errors=True)
    print(f"uninstall: removed governance from {project}")
    return 0


_COMMANDS = {
    "init": "inject the plane into a project (--hooks, --ci add the runners)",
    "uninstall": "reverse init",
    "run": "run the project's gate DAG (args forwarded to gates.py)",
    "self-test": "run governance rejection cases",
    "verify-notes": "check note format",
    "verify-pairing": "check bilingual pairing (e.g. --write)",
    "verify-note-presence": "warn when a non-trivial diff carries no note (e.g. --base <ref>, --strict)",
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


def _init_uninstall_args(args: list[str], what: str) -> tuple[Path, bool, bool] | None:
    """Parse ``--project <dir>`` (plus init's ``--hooks``/``--ci``); reject the rest."""
    project = "."
    hooks = ci = False
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--project":
            if i + 1 >= len(args):
                print(f"gov {what}: --project requires a directory", file=sys.stderr)
                return None
            project = args[i + 1]
            i += 2
        elif what == "init" and a == "--hooks":
            hooks = True
            i += 1
        elif what == "init" and a == "--ci":
            ci = True
            i += 1
        else:
            print(f"gov {what}: unexpected argument '{a}'", file=sys.stderr)
            _usage()
            return None
    return Path(project), hooks, ci


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
        parsed = _init_uninstall_args(rest, "init")
        return 2 if parsed is None else init(parsed[0], hooks=parsed[1], ci=parsed[2])
    if cmd == "uninstall":
        parsed = _init_uninstall_args(rest, "uninstall")
        return 2 if parsed is None else uninstall(parsed[0])
    if cmd == "run":
        return gates.main(rest)
    if cmd == "self-test":
        return self_test.main()
    if cmd == "verify-notes":
        return verify_notes.main()
    if cmd == "verify-pairing":
        return verify_translation_pairing.main(rest)
    if cmd == "verify-note-presence":
        return verify_note_presence.main(rest)
    if cmd == "change-scope":
        return change_scope.main(rest)
    if cmd == "archive-notes":
        return archive_notes.main()
    print(f"gov: unknown command '{cmd}'", file=sys.stderr)
    _usage()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
