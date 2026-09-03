import json
import os
import subprocess

from gov import doctor


def _git_repo(root):
    for cmd in (["git", "init", "-q", "."],
                ["git", "config", "user.email", "t@t"],
                ["git", "config", "user.name", "t"]):
        subprocess.run(cmd, cwd=root, check=True)


def test_healthy_environment(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "gates.json").write_text(json.dumps(
        {"modes": {"all": ["a"]}, "gates": [{"id": "a", "command": ["true"]}]}))
    hooks = tmp_path / ".git" / "hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    (hooks / "pre-push").write_text("#!/bin/sh\n")
    (hooks / "pre-push").chmod(0o755)
    assert doctor.main([]) in (0, 1)  # gov-on-PATH depends on the host
    out = capsys.readouterr().out
    assert "ok: gates.json passes the strict schema" in out
    import re
    assert re.search(r"ok: .*(/|\\)hooks(/|\\)pre-push is executable", out)
    assert "ok: python" in out


def test_bad_gates_schema_is_a_problem(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "gates.json").write_text(json.dumps(
        {"gates": [{"id": "a", "command": ["true"], "enable": False}]}))
    assert doctor.main([]) == 1
    out = capsys.readouterr().out
    assert "problem: gates.json:" in out
    assert "unknown key(s): enable" in out


def test_non_executable_hook_is_a_problem(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    hooks = tmp_path / ".git" / "hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    (hooks / "pre-push").write_text("#!/bin/sh\n")  # no +x
    assert doctor.main([]) == 1
    assert "not executable" in capsys.readouterr().out


def test_missing_gate_command_is_a_problem(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "gates.json").write_text(json.dumps(
        {"modes": {"all": ["x", "y"]},
         "gates": [{"id": "x", "command": ["no-such-bin-xyz"]},
                   {"id": "y", "command": ["true"]}]}))
    assert doctor.main([]) == 1
    out = capsys.readouterr().out
    assert "gate 'x': command 'no-such-bin-xyz' not found on PATH" in out
    assert "ok: gate 'y' command resolves" in out
