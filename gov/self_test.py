#!/usr/bin/env python3
"""Rejection cases for each governance gate (D3).

Every case introduces a deliberate violation, runs the gate, and asserts the
gate FAILS — proving it can reject, not just pass. A green self-test means
each governance gate has demonstrated it catches the violation it claims to.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _run(script: str, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(HERE / script)],
        cwd=cwd,
        capture_output=True,
        text=True,
    )


def _case(script: str, cwd: Path, expect: int, why: str) -> None:
    result = _run(script, cwd)
    assert result.returncode == expect, (
        f"{script} returned {result.returncode}, expected {expect}: {why}\n"
        f"{result.stdout}\n{result.stderr}"
    )


def test_verify_notes_rejects_missing_section() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        notes = root / ".agents" / "notes" / "implemented"
        notes.mkdir(parents=True)
        (notes / "bad.md").write_text(
            "# Agent Note: bad\n\n"
            "Status: implemented\n\n"
            "## Problem\nx\n\n"
            "## Decision\ny\n",
            encoding="utf-8",
        )
        _case("verify_notes.py", root, 1, "a note missing Alternatives must fail")


def test_gates_rejects_duplicate_id() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "a", "command": ["true"]},
                        {"id": "a", "command": ["true"]},
                    ]
                }
            ),
            encoding="utf-8",
        )
        _case("gates.py", root, 2, "duplicate gate ids must fail loud")


def test_gates_rejects_cycle() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "a", "command": ["true"], "needs": ["b"]},
                        {"id": "b", "command": ["true"], "needs": ["a"]},
                    ]
                }
            ),
            encoding="utf-8",
        )
        _case("gates.py", root, 2, "a needs cycle must fail loud")


def test_gates_rejects_unknown_needs() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {"gates": [{"id": "a", "command": ["true"], "needs": ["ghost"]}]}
            ),
            encoding="utf-8",
        )
        _case("gates.py", root, 2, "an unknown needs reference must fail loud")


def test_pairing_rejects_missing_record() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        docs = root / "docs"
        docs.mkdir()
        (docs / "foo.md").write_text("# foo\n", encoding="utf-8")
        (docs / "foo.zh.md").write_text("# foo 中文\n", encoding="utf-8")
        _case(
            "verify_translation_pairing.py",
            root,
            1,
            "a pair with no .i18n.yaml record must fail",
        )


def test_gates_skips_transitively() -> None:
    """A gate whose need was skipped must itself skip, never pass."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "A", "command": ["true"], "needs": ["B"]},
                        {"id": "B", "command": ["true"], "needs": ["C"]},
                        {"id": "C", "command": ["false"]},
                    ]
                }
            ),
            encoding="utf-8",
        )
        result = _run("gates.py", root)
        assert result.returncode == 1, "a blocking failure must exit 1"
        assert "SKIP B" in result.stdout, "B must be skipped when C fails"
        assert "SKIP A" in result.stdout, "A must be skipped when B is skipped"
        assert "PASS A" not in result.stdout, "A must never pass through a skipped need"


def test_gates_rejects_non_object_gate() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(json.dumps({"gates": [None]}), encoding="utf-8")
        _case("gates.py", root, 2, "a null gate must be a config error, not a crash")


def test_cli_init_help_no_side_effect() -> None:
    """`gov init --help` must show help and create nothing, not run init."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        env = dict(os.environ)
        env["PYTHONPATH"] = str(HERE.parent) + os.pathsep + env.get("PYTHONPATH", "")
        result = subprocess.run(
            [sys.executable, "-m", "gov", "init", "--help"],
            cwd=root,
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"init --help must exit 0: {result.stderr}"
        assert not list(root.iterdir()), "init --help must not create any file"


def test_pairing_write_resolves_bare_stem_and_zh_side() -> None:
    """--write must resolve a bare stem and a .zh.md side to the source .md."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        docs = root / "docs"
        docs.mkdir()
        (docs / "foo.md").write_text("# foo\n", encoding="utf-8")
        (docs / "foo.zh.md").write_text("# foo 中文\n", encoding="utf-8")
        for arg in ("foo", "docs/foo.zh.md"):
            result = subprocess.run(
                [sys.executable, str(HERE / "verify_translation_pairing.py"), "--write", arg],
                cwd=root,
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0, f"--write {arg} must exit 0: {result.stderr}"
        assert (docs / "foo.i18n.yaml").exists(), "--write must create the record"


CASES = [
    test_verify_notes_rejects_missing_section,
    test_gates_rejects_duplicate_id,
    test_gates_rejects_cycle,
    test_gates_rejects_unknown_needs,
    test_gates_skips_transitively,
    test_gates_rejects_non_object_gate,
    test_cli_init_help_no_side_effect,
    test_pairing_rejects_missing_record,
    test_pairing_write_resolves_bare_stem_and_zh_side,
]


def main() -> int:
    for case in CASES:
        case()
        print(f"PASS {case.__name__}")
    print(f"self-test: {len(CASES)} rejection case(s) pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
