#!/usr/bin/env python3
"""gov doctor — environment self-check (D29, wish: no silent environment).

The plane's runners assume an environment; when the assumption breaks
(gov on an un-PATH'd ~/.local/bin, a hook that cannot exec, a gates.json
typo) the failure mode has been silence or a confusing crash. Doctor
names the problems, one per line, rule-5 style; exit 1 when any check
fails, 0 when the environment is sound.

Checks: CLI reachability from PATH (the hook's fast path), the Python
interpreter against the package requirement, pre-push hook presence and
executability (both copies), gates.json schema (strict keys), and — when
a decisions table exists — that it parses.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys

from . import __version__

MIN_PYTHON = (3, 9)


def _check_gov_on_path(problems: list[str]) -> None:
    if shutil.which("gov"):
        print("ok: gov resolves on PATH (hooks' fast path works)")
    else:
        problems.append(
            "gov is not on PATH — hooks and rejection cases calling `gov` "
            "will fail; export GOV_BIN, or ensure the install bin dir "
            "(e.g. ~/.local/bin) is on PATH"
        )


def _check_python(problems: list[str]) -> None:
    v = sys.version_info
    if v[:2] >= MIN_PYTHON:
        print(f"ok: python {v.major}.{v.minor} meets the required >="
              f" {MIN_PYTHON[0]}.{MIN_PYTHON[1]}")
    else:
        problems.append(
            f"python {v.major}.{v.minor} is below the required "
            f"{MIN_PYTHON[0]}.{MIN_PYTHON[1]}"
        )


def _git_dir() -> str | None:
    """The git dir, worktree-aware (#15/D32): a linked worktree's .git is a
    FILE; git rev-parse --git-common-dir resolves the shared dir (hooks
    live there even from a linked worktree)."""
    proc = subprocess.run(["git", "rev-parse", "--git-common-dir"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    import os
    return os.path.abspath(proc.stdout.strip()) or None


def _check_hook(problems: list[str]) -> None:
    import os
    git_dir = _git_dir()
    if git_dir is None:
        print("note: not a git repository — hook checks skipped")
        return
    hook = os.path.join(git_dir, "hooks", "pre-push")
    for rel, what in ((hook, "the wired git hook"),
                      (".gov/hooks/pre-push", "the auditable copy")):
        if not os.path.exists(rel):
            print(f"note: {rel} absent ({what}) — gov init --hooks installs it")
            continue
        if os.access(rel, os.X_OK):
            print(f"ok: {rel} is executable")
        else:
            problems.append(f"{rel} is not executable — chmod +x it")


def _check_version_drift(problems: list[str]) -> None:
    """#19/D32: the environment self-check must see manifest drift."""
    import json
    import os
    manifest = ".gov/manifest.json"
    if not os.path.exists(manifest):
        return
    try:
        init_version = json.loads(
            open(manifest, encoding="utf-8").read()).get("version")
    except (OSError, ValueError):
        return
    if init_version and init_version != __version__:
        print(f"note: manifest initialized with govrail {init_version}, "
              f"this package is {__version__} — gov init --upgrade shows "
              "template drift; gov whatsnew --since "
              f"{init_version} shows what arrived")


def _check_gates(problems: list[str]) -> None:
    import os
    if not os.path.exists("gates.json"):
        print("note: no gates.json — gov init creates one when missing")
        return
    from . import gates as gates_mod
    try:
        _, gs, _, _ = gates_mod.load_config("gates.json")
        print("ok: gates.json passes the strict schema")
        for g in gs:
            if g.command and not shutil.which(g.command[0]):
                problems.append(
                    f"gate '{g.id}': command '{g.command[0]}' not found on "
                    "PATH — the run would report MISSING"
                )
            elif g.command:
                print(f"ok: gate '{g.id}' command resolves ({g.command[0]})")
    except gates_mod.ConfigError as e:
        problems.append(f"gates.json: {e}")


def _check_decisions(problems: list[str]) -> None:
    import os
    if not os.path.exists("docs/decisions.md"):
        return  # no table, nothing to check — not an environment problem
    from . import verify_decisions as vd
    rc = vd.main([])
    if rc == 0:
        print("ok: decisions table parses")
    else:
        problems.append("decisions table has violations — gov verify-decisions")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gov doctor",
        description="Environment self-check: PATH, Python, hooks, gates schema.",
    )
    parser.parse_args(argv)

    problems: list[str] = []
    print(f"gov doctor — govrail {__version__}")
    _check_gov_on_path(problems)
    _check_python(problems)
    _check_version_drift(problems)
    _check_hook(problems)
    _check_gates(problems)
    _check_decisions(problems)

    if problems:
        print()
        for p in problems:
            print(f"problem: {p}")
        print(f"gov doctor: {len(problems)} problem(s)")
        return 1
    print("gov doctor: environment sound")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
