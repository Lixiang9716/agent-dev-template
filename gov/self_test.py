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


def test_gates_default_mode_scopes_run() -> None:
    """defaultMode must scope the no-flag run; gates outside it never run."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "modes": {"all": ["a"]},
                    "defaultMode": "all",
                    "gates": [
                        {"id": "a", "command": ["true"]},
                        {"id": "b", "command": ["false"]},
                    ],
                }
            ),
            encoding="utf-8",
        )
        result = _run("gates.py", root)
        assert result.returncode == 0, "a gate outside the default mode must not run"
        assert "PASS a" in result.stdout
        assert "FAIL b" not in result.stdout


def test_gates_rejects_unknown_default_mode() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "modes": {"all": ["a"]},
                    "defaultMode": "ghost",
                    "gates": [{"id": "a", "command": ["true"]}],
                }
            ),
            encoding="utf-8",
        )
        _case("gates.py", root, 2, "a defaultMode naming no known mode must fail loud")


def test_gates_disabled_gate_never_runs() -> None:
    """enabled:false parks a gate visibly outside every run (P0 defect 1)."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "a", "command": ["true"]},
                        {"id": "b", "command": ["false"], "enabled": False},
                    ]
                }
            ),
            encoding="utf-8",
        )
        result = _run("gates.py", root)
        assert result.returncode == 0, "a disabled gate must not affect the run"
        assert "DISABLED b" in result.stdout
        assert "FAIL b" not in result.stdout


def test_gates_advisory_failure_reports_without_blocking() -> None:
    """allowFailure must report the failure output yet keep exit code 0."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "a", "command": ["false"], "allowFailure": True},
                    ]
                }
            ),
            encoding="utf-8",
        )
        result = _run("gates.py", root)
        assert result.returncode == 0, "an advisory gate must never block"
        assert "FAIL a" in result.stdout
        assert "advisory" in result.stdout, "an advisory failure must be visible"


def test_pairing_custom_counterpart_convention() -> None:
    """A .gov/pairing.json convention must be enforced, not ignored."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        gov = root / ".gov"
        gov.mkdir()
        (gov / "pairing.json").write_text(
            json.dumps({"counterparts": ["{stem}_CN.md"]}), encoding="utf-8"
        )
        docs = root / "docs"
        docs.mkdir()
        (docs / "foo.md").write_text("# foo\n", encoding="utf-8")
        (docs / "foo_CN.md").write_text("# foo 中文\n", encoding="utf-8")
        _case(
            "verify_translation_pairing.py",
            root,
            1,
            "a custom-convention pair with no record must fail",
        )


def test_pairing_explicit_registration_sticks() -> None:
    """--write en:.. zh:.. registers any name; verification then pins it."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        docs = root / "docs"
        docs.mkdir()
        (docs / "foo.md").write_text("# foo\n", encoding="utf-8")
        (docs / "foo_CN.md").write_text("# foo 中文\n", encoding="utf-8")
        register = subprocess.run(
            [
                sys.executable,
                str(HERE / "verify_translation_pairing.py"),
                "--write", "en:docs/foo.md", "zh:docs/foo_CN.md",
            ],
            cwd=root,
            capture_output=True,
            text=True,
        )
        assert register.returncode == 0, f"explicit registration must exit 0: {register.stderr}"
        (docs / "foo_CN.md").write_text("# 单边修改\n", encoding="utf-8")
        _case(
            "verify_translation_pairing.py",
            root,
            1,
            "a one-sided edit of a registered pair must fail",
        )


def _git_repo(root: Path) -> None:
    for cmd in (
        ["git", "init", "-q", "."],
        ["git", "config", "user.email", "t@t"],
        ["git", "config", "user.name", "t"],
    ):
        subprocess.run(cmd, cwd=root, check=True)
    (root / "seed.txt").write_text("seed\n", encoding="utf-8")
    subprocess.run(["git", "add", "-A"], cwd=root, check=True)
    subprocess.run(
        ["git", "-c", "commit.gpgsign=false", "commit", "-qm", "init"],
        cwd=root, check=True,
    )


def test_note_presence_warns_then_strict_blocks() -> None:
    """Rule 2's presence half must be checkable: warn by default, block on --strict."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _git_repo(root)
        (root / "app.py").write_text("x = 1\n", encoding="utf-8")
        script = str(HERE / "verify_note_presence.py")
        warn = subprocess.run(
            [sys.executable, script], cwd=root, capture_output=True, text=True
        )
        assert warn.returncode == 0, "advisory mode must not block (D3)"
        assert ".gov/rules.md rule 2" in warn.stdout, "the warning must name its rule"
        strict = subprocess.run(
            [sys.executable, script, "--strict"], cwd=root, capture_output=True, text=True
        )
        assert strict.returncode == 1, "--strict must catch the missing note"


def test_run_base_scopes_gates_by_paths() -> None:
    """--base must select gates by paths; out-of-scope gates never run."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _git_repo(root)
        # docs-gate would PASS, code-gate would FAIL — only the in-scope one runs.
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "docs-gate", "command": ["true"], "paths": ["docs/**"]},
                        {"id": "code-gate", "command": ["false"], "paths": ["src/**"]},
                    ]
                }
            ),
            encoding="utf-8",
        )
        (root / "docs").mkdir()
        (root / "docs" / "a.md").write_text("x\n", encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(HERE / "gates.py"), "--base", "HEAD"],
            cwd=root, capture_output=True, text=True,
        )
        assert result.returncode == 0, (
            "the failing gate is out of scope; the run must be green\n"
            f"{result.stdout}\n{result.stderr}"
        )
        assert "PASS docs-gate" in result.stdout
        assert "out of scope: code-gate" in result.stdout
        assert "FAIL code-gate" not in result.stdout


def test_run_failure_summary_and_gate_flag() -> None:
    """A blocking failure must end with a summary and a single-gate rerun hint."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "boom", "command": ["sh", "-c", "echo boom >&2; exit 3"]},
                        {"id": "ok", "command": ["true"]},
                    ]
                }
            ),
            encoding="utf-8",
        )
        result = _run("gates.py", root)
        assert result.returncode == 1
        assert "--- summary: 1 blocking failure(s) ---" in result.stdout
        assert "boom: boom" in result.stdout
        assert "gov run --gate <id>" in result.stdout
        single = subprocess.run(
            [sys.executable, str(HERE / "gates.py"), "--gate", "ok"],
            cwd=root, capture_output=True, text=True,
        )
        assert single.returncode == 0
        assert "PASS boom" not in single.stdout


def test_change_scope_suggests_from_paths() -> None:
    """change-scope must read gate suggestions from gates.json paths, not prose."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _git_repo(root)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "docs-gate", "command": ["true"], "paths": ["docs/**"]},
                        {"id": "code-gate", "command": ["true"], "paths": ["src/**"]},
                    ]
                }
            ),
            encoding="utf-8",
        )
        (root / "docs").mkdir()
        (root / "docs" / "a.md").write_text("x\n", encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(HERE / "change_scope.py"), "--base", "HEAD"],
            cwd=root, capture_output=True, text=True,
        )
        assert "gates.json paths" in result.stdout, result.stdout + result.stderr
        assert "docs-gate" in result.stdout
        assert "code-gate" not in result.stdout


def test_init_hooks_ci_roundtrip() -> None:
    """init --hooks/--ci must install, and uninstall must reverse exactly."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _git_repo(root)
        env = dict(os.environ)
        env["PYTHONPATH"] = str(HERE.parent) + os.pathsep + env.get("PYTHONPATH", "")
        for args in (
            ["-m", "gov", "init", "--hooks", "--ci"],
            ["-m", "gov", "uninstall"],
        ):
            r = subprocess.run(
                [sys.executable, *args], cwd=root, env=env,
                capture_output=True, text=True,
            )
            assert r.returncode == 0, r.stderr
        assert not (root / ".git" / "hooks" / "pre-push").exists()
        assert not (root / ".github" / "workflows" / "gov.yml").exists()
        assert not (root / "gates.json").exists()


def test_rubric_rejects_broken_structure() -> None:
    """verify-rubric must catch missing fields and bilingual id drift."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        docs = root / "docs"
        docs.mkdir()
        good = (
            "### R1 — a\n\n"
            "- **Checks:** c\n- **Evidence:** e\n"
            "- **Anti-pattern:** a\n- **Gate candidate:** no — judgment\n"
        )
        (docs / "review-rubric.md").write_text(good, encoding="utf-8")
        (docs / "review-rubric.zh.md").write_text(
            good.replace("R1 — a", "R1 — 甲"), encoding="utf-8"
        )
        script = str(HERE / "verify_rubric.py")
        ok = subprocess.run(
            [sys.executable, script], cwd=root, capture_output=True, text=True
        )
        assert ok.returncode == 0, ok.stderr
        (docs / "review-rubric.md").write_text(
            good.replace("- **Evidence:** e\n", ""), encoding="utf-8"
        )
        broken = subprocess.run(
            [sys.executable, script], cwd=root, capture_output=True, text=True
        )
        assert broken.returncode == 1, "a rubric item missing a field must fail"
        assert "Evidence" in broken.stdout
        (docs / "review-rubric.md").write_text(good, encoding="utf-8")
        (docs / "review-rubric.zh.md").write_text(
            "### R2 — 乙\n\n- **查什么：** x\n", encoding="utf-8"
        )
        drift = subprocess.run(
            [sys.executable, script], cwd=root, capture_output=True, text=True
        )
        assert drift.returncode == 1, "bilingual id drift must fail"
        assert "R2" in drift.stdout


def _write_note(root: Path, rel: str, body: str) -> None:
    p = root / ".agents" / "notes" / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body, encoding="utf-8")


_GOOD_NOTE = (
    "# Agent Note: t\n\nStatus: implemented\n\n"
    "## Problem\np\n\n## Decision\nd\n\n## Alternatives considered\na\n"
)


def test_verify_notes_rejects_wrong_section_order() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _write_note(
            root,
            "implemented/architecture/2026-01-01-x.md",
            "# Agent Note: t\n\nStatus: implemented\n\n"
            "## Decision\nd\n\n## Problem\np\n\n## Alternatives considered\na\n",
        )
        _case(
            "verify_notes.py",
            root,
            1,
            "sections out of the promised order must fail (notes README contract)",
        )


def test_verify_notes_rejects_unknown_lifecycle() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _write_note(root, "implemented/architecture/2026-01-01-x.md", _GOOD_NOTE)
        _write_note(root, "drafts/2026-01-01-x.md", _GOOD_NOTE)
        result = _run("verify_notes.py", root)
        assert result.returncode == 1, "an unknown lifecycle dir must fail loud (rule 5)"
        assert "unknown lifecycle 'drafts'" in result.stdout


def test_rubric_rejects_zero_items() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        docs = root / "docs"
        docs.mkdir()
        (docs / "review-rubric.md").write_text(
            "# Review rubric\n\ngarbage content, no items\n", encoding="utf-8"
        )
        _case(
            "verify_rubric.py",
            root,
            1,
            "a rubric with zero items is a vacuous pass (rule 6)",
        )


def test_passing_gate_output_stays_visible() -> None:
    """A pass that printed a warning must not be silenced (P1-2)."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "gates.json").write_text(
            json.dumps(
                {
                    "gates": [
                        {"id": "warny", "command": ["sh", "-c", "echo heads up; exit 0"]},
                    ]
                }
            ),
            encoding="utf-8",
        )
        result = _run("gates.py", root)
        assert result.returncode == 0
        assert "passed with output" in result.stdout
        assert "heads up" in result.stdout


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
    test_gates_default_mode_scopes_run,
    test_gates_rejects_unknown_default_mode,
    test_gates_disabled_gate_never_runs,
    test_gates_advisory_failure_reports_without_blocking,
    test_pairing_custom_counterpart_convention,
    test_pairing_explicit_registration_sticks,
    test_note_presence_warns_then_strict_blocks,
    test_run_base_scopes_gates_by_paths,
    test_run_failure_summary_and_gate_flag,
    test_change_scope_suggests_from_paths,
    test_init_hooks_ci_roundtrip,
    test_rubric_rejects_broken_structure,
    test_verify_notes_rejects_wrong_section_order,
    test_verify_notes_rejects_unknown_lifecycle,
    test_rubric_rejects_zero_items,
    test_passing_gate_output_stays_visible,
]


def main() -> int:
    for case in CASES:
        case()
        print(f"PASS {case.__name__}")
    print(f"self-test: {len(CASES)} rejection case(s) pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
