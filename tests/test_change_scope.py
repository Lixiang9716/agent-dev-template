import json
import subprocess

from gov import change_scope


def _git_repo(root):
    for cmd in (
        ["git", "init", "-q", "."],
        ["git", "config", "user.email", "t@t"],
        ["git", "config", "user.name", "t"],
    ):
        subprocess.run(cmd, cwd=root, check=True)
    (root / "seed.txt").write_text("seed\n")
    subprocess.run(["git", "add", "-A"], cwd=root, check=True)
    subprocess.run(
        ["git", "-c", "commit.gpgsign=false", "commit", "-qm", "init"],
        cwd=root, check=True,
    )


def test_suggests_from_gates_paths(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "gates.json").write_text(json.dumps({
        "gates": [
            {"id": "docs-gate", "command": ["true"], "paths": ["docs/**"]},
            {"id": "code-gate", "command": ["true"], "paths": ["src/**"]},
        ]
    }))
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "a.md").write_text("x\n")
    assert change_scope.main(["--base", "HEAD"]) == 0
    out = capsys.readouterr().out
    assert "gates.json paths" in out
    assert "docs-gate" in out
    assert "code-gate" not in out
    assert "gov run --base HEAD" in out


def test_note_hint_when_code_changed_without_note(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "gates.json").write_text(json.dumps({"gates": []}))
    (tmp_path / "app.py").write_text("x = 1\n")
    assert change_scope.main(["--base", "HEAD"]) == 0
    assert "no Agent Note in this change" in capsys.readouterr().out


def test_no_ghost_gate_in_fallback(tmp_path, monkeypatch, capsys):
    """The fallback suggestion list must not name gates that do not exist."""
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "app.py").write_text("x = 1\n")  # no gates.json at all
    assert change_scope.main(["--base", "HEAD"]) == 0
    out = capsys.readouterr().out
    assert "links" not in out
