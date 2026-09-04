import json
import subprocess
import sys
from pathlib import Path

import pytest

from gov import task


def _project(tmp_path: Path) -> Path:
    (tmp_path / ".gov" / "tasks").mkdir(parents=True, exist_ok=True)
    (tmp_path / ".gov" / "rules.md").write_text("# Rules\n", encoding="utf-8")
    (tmp_path / "gates.json").write_text(json.dumps({"gates": []}),
                                         encoding="utf-8")
    return tmp_path


def _run(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "gov", "task", *args],
        cwd=cwd, capture_output=True, text=True,
        env={"PYTHONPATH": str(Path(__file__).resolve().parent.parent),
             "PATH": "/usr/bin:/bin", "HOME": str(cwd)},
    )


def test_new_writes_card_with_pin_and_checklist(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(_project(tmp_path))
    rc = task.main(["new", "Fix the flaky gate", "--check", "tests green",
                    "--check", "note written"])
    assert rc == 0
    card = json.loads(
        next((tmp_path / ".gov/tasks").glob("T-0001-*.json"))
        .read_text(encoding="utf-8"))
    assert card["id"] == "T-0001"
    assert card["status"] == "open"
    assert card["checklist"] == ["tests green", "note written"]
    combined, files = task.rules_hash(tmp_path)
    assert card["rules"]["hash"] == combined
    assert set(card["rules"]["files"]) == set(task.RULE_FILES)
    assert f"obey rules@{combined[:12]}" in capsys.readouterr().out


def test_check_flags_stale_pin_after_adoption(tmp_path, monkeypatch):
    proj = _project(tmp_path)
    monkeypatch.chdir(proj)
    assert task.main(["new", "Brief me"]) == 0
    # governance adoption: the rule set moves
    (proj / ".gov/rules.md").write_text("# Rules\n\nNew rule.\n", encoding="utf-8")
    assert task.main(["check"]) == 1


def test_new_rejects_mismatched_rules_pin(tmp_path, monkeypatch):
    monkeypatch.chdir(_project(tmp_path))
    rc = task.main(["new", "Pinned", "--rules", "deadbeef"])
    assert rc == 2


def test_rules_hash_fails_loud_without_rule_set(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    try:
        task.rules_hash()
    except SystemExit as e:
        assert e.code == 2
    else:
        raise AssertionError("missing .gov/rules.md must abort loud")


def test_check_rejects_done_card_without_green_receipt(tmp_path, monkeypatch):
    proj = _project(tmp_path)
    monkeypatch.chdir(proj)
    combined, _ = task.rules_hash(proj)
    (proj / ".gov/tasks/T-0001-x.json").write_text(json.dumps({
        "id": "T-0001", "title": "x",
        "rules": {"hash": combined}, "checklist": [],
        "status": "done", "receipt": None,
    }), encoding="utf-8")
    assert task.main(["check"]) == 1


def test_malformed_card_fails_loud(tmp_path, monkeypatch):
    proj = _project(tmp_path)
    monkeypatch.chdir(proj)
    (proj / ".gov/tasks/badname.json").write_text("{}", encoding="utf-8")
    try:
        task.main(["check"])
    except SystemExit as e:
        assert e.code == 2
    else:
        raise AssertionError("a badly named card must abort loud")


def test_close_runs_gates_and_records_receipt(tmp_path, monkeypatch):
    proj = _project(tmp_path)
    (proj / "gates.json").write_text(json.dumps({
        "modes": {"all": ["noop"]},
        "gates": [{"id": "noop", "command": ["true"]}],
    }), encoding="utf-8")
    monkeypatch.chdir(proj)
    assert task.main(["new", "Close me"]) == 0
    # close shells out to `python -m gov run`; keep it in-process-cheap
    rc = task.main(["close", "T-0001", "--mode", "all", "--timeout", "60"])
    assert rc == 0
    card = json.loads(
        next((proj / ".gov/tasks").glob("T-0001-*.json")).read_text("utf-8"))
    assert card["status"] == "done"
    assert card["receipt"]["green"] is True
    assert all(g["outcome"] == "PASS" for g in card["receipt"]["gates"])
    assert card["receipt"]["rules"] == card["rules"]["hash"]
    assert task.main(["check"]) == 0


def test_close_refuses_stale_card(tmp_path, monkeypatch):
    proj = _project(tmp_path)
    monkeypatch.chdir(proj)
    assert task.main(["new", "Old pin"]) == 0
    (proj / ".gov/rules.md").write_text("# Rules v2\n", encoding="utf-8")
    assert task.main(["close", "T-0001"]) == 1


def test_close_ambiguous_prefix_fails_loud(tmp_path, monkeypatch):
    proj = _project(tmp_path)
    monkeypatch.chdir(proj)
    assert task.main(["new", "One"]) == 0
    assert task.main(["new", "Two"]) == 0
    assert task.main(["new", "Three"]) == 0
    try:
        task.main(["close", "T-0"])
    except SystemExit as e:
        assert e.code == 2
    else:
        raise AssertionError("an ambiguous prefix must abort loud")


def test_bare_task_fails_loud_naming_choices(tmp_path, monkeypatch, capsys):
    """#138: `required=True` on add_subparsers died under a shadowed
    pre-3.7 argparse backport, so the missing-subcommand rule is enforced
    by hand — it must still exit 2 with the choices named."""
    monkeypatch.chdir(_project(tmp_path))
    with pytest.raises(SystemExit) as exc:
        task.main([])
    assert exc.value.code == 2
    err = capsys.readouterr().err
    assert "a subcommand is required (new|check|close|list)" in err
