import json
import os
import subprocess
import sys
from pathlib import Path

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


def test_json_mode_pure_stdout(tmp_path, monkeypatch, capsys):
    """#119: doctor --json — stdout is exactly one JSON object; the human
    report moves to stderr."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / "gates.json").write_text(json.dumps(
        {"modes": {"all": ["x", "y"]},
         "gates": [{"id": "x", "command": ["no-such-bin-xyz"]},
                   {"id": "y", "command": ["true"]}]}))
    import json as _json
    assert doctor.main(["--json"]) == 1
    captured = capsys.readouterr()
    payload = _json.loads(captured.out)  # exactly one JSON value
    assert payload["status"] == "problems"
    assert any(c["name"] == "gate:x" and c["state"] == "problem"
               for c in payload["checks"])
    assert "gate:x" in payload["problems"]
    assert all(c["state"] in ("ok", "note", "problem") for c in payload["checks"])
    assert "gov doctor" in captured.err  # the human report moved to stderr
    assert payload["problems"][0] == "gate:x"


_SHADOW_ARGPARSE = (
    "#138: a faithful-enough stand-in for the py2-era backport (PyPI\n"
    "# argparse 1.4.0): real stdlib argparse with pre-3.7 add_subparsers\n"
    "# restored — `required` is refused.\n"
    "import importlib.util, os, sysconfig\n"
    "_dir = os.path.dirname(os.path.abspath(__file__))\n"
    "_p = os.path.join(sysconfig.get_paths()['stdlib'], 'argparse.py')\n"
    "_s = importlib.util.spec_from_file_location('_stdlib_argparse', _p)\n"
    "_m = importlib.util.module_from_spec(_s)\n"
    "_s.loader.exec_module(_m)\n"
    "globals().update(vars(_m))\n"
    "__file__ = os.path.join(_dir, 'argparse.py')\n"
    "__name__ = 'argparse'\n"
    "_real = _m.ArgumentParser.add_subparsers\n"
    "def _old(self, **kw):\n"
    "    if 'required' in kw:\n"
    "        raise TypeError(\"_SubParsersAction.__init__() got an \"\n"
    "                        \"unexpected keyword argument 'required'\")\n"
    "    return _real(self, **kw)\n"
    "ArgumentParser.add_subparsers = _old\n")


def test_argparse_backport_shadow_is_named(tmp_path):
    """#138: an argparse backport beside an installed gov shadows the
    stdlib when PYTHONPATH promotes that dir — doctor must name it as a
    problem with the fix spelled out, and still run (it never needed the
    modern argparse surface itself). The clean run reports ok."""
    repo = Path(__file__).resolve().parent.parent
    clean = subprocess.run(
        [sys.executable, "-m", "gov", "doctor"], cwd=tmp_path,
        capture_output=True, text=True,
        env={**os.environ, "PYTHONPATH": str(repo)})
    assert "argparse resolves to the stdlib" in clean.stdout

    shadow = tmp_path / "shadow"
    shadow.mkdir()
    (shadow / "argparse.py").write_text(_SHADOW_ARGPARSE, encoding="utf-8")
    env = {**os.environ,
           "PYTHONPATH": os.pathsep.join([str(shadow), str(repo)])}
    r = subprocess.run(
        [sys.executable, "-m", "gov", "doctor"], cwd=tmp_path,
        capture_output=True, text=True, env=env)
    assert r.returncode == 1, r.stdout
    assert "argparse resolves to" in r.stdout
    assert "pip uninstall argparse" in r.stdout
