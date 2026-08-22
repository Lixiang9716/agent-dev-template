#!/usr/bin/env python3
"""Rejection cases for each governance gate (D3).

Every case introduces a deliberate violation, runs the gate, and asserts the
gate FAILS — proving it can reject, not just pass. A green self-test means
each governance gate has demonstrated it catches the violation it claims to.
"""
from __future__ import annotations

import json
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


CASES = [
    test_verify_notes_rejects_missing_section,
    test_gates_rejects_duplicate_id,
    test_gates_rejects_cycle,
    test_gates_rejects_unknown_needs,
    test_pairing_rejects_missing_record,
]


def main() -> int:
    for case in CASES:
        case()
        print(f"PASS {case.__name__}")
    print(f"self-test: {len(CASES)} rejection case(s) pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
