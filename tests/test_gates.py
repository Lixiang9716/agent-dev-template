import json
import subprocess
from pathlib import Path

import pytest

from gov import gates


def _write(tmp_path: Path, data) -> Path:
    p = tmp_path / "gates.json"
    p.write_text(json.dumps(data))
    return p


def _git_repo(tmp_path: Path) -> None:
    for cmd in (
        ["git", "init", "-q", "."],
        ["git", "config", "user.email", "t@t"],
        ["git", "config", "user.name", "t"],
    ):
        subprocess.run(cmd, cwd=tmp_path, check=True)
    (tmp_path / "seed.txt").write_text("seed\n")
    subprocess.run(["git", "add", "-A"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-c", "commit.gpgsign=false", "commit", "-qm", "init"],
                   cwd=tmp_path, check=True)


def test_load_config_valid(tmp_path):
    p = _write(tmp_path, {"gates": [{"id": "a", "command": ["true"]}]})
    modes, gs, concurrency, default_mode = gates.load_config(str(p))
    assert [g.id for g in gs] == ["a"]
    assert gs[0].command == ["true"]
    assert concurrency == 0
    assert default_mode is None
    assert gs[0].enabled is True


def test_load_config_parses_default_mode_and_enabled(tmp_path):
    p = _write(
        tmp_path,
        {
            "modes": {"all": ["a"]},
            "defaultMode": "all",
            "gates": [
                {"id": "a", "command": ["true"]},
                {"id": "b", "command": ["true"], "enabled": False},
            ],
        },
    )
    modes, gs, concurrency, default_mode = gates.load_config(str(p))
    assert default_mode == "all"
    assert [g.enabled for g in gs] == [True, False]


@pytest.mark.parametrize(
    "data",
    [
        {"modes": {"all": ["a"]}, "defaultMode": "ghost",
         "gates": [{"id": "a", "command": ["true"]}]},
        {"modes": {"all": ["a"]}, "defaultMode": 3,
         "gates": [{"id": "a", "command": ["true"]}]},
        {"modes": {"all": ["a"]}, "defaultMode": "",
         "gates": [{"id": "a", "command": ["true"]}]},
        {"gates": [{"id": "a", "command": ["true"], "enabled": "false"}]},
    ],
)
def test_load_config_rejects_bad_default_mode_or_enabled(tmp_path, data):
    p = _write(tmp_path, data)
    with pytest.raises(gates.ConfigError):
        gates.load_config(str(p))


@pytest.mark.parametrize(
    "data",
    [
        {"gates": [{"id": "a", "command": ["true"]}, {"id": "a", "command": ["true"]}]},
        {"gates": [{"id": "a", "command": ["true"], "needs": ["ghost"]}]},
        {
            "gates": [
                {"id": "a", "command": ["true"], "needs": ["b"]},
                {"id": "b", "command": ["true"], "needs": ["a"]},
            ]
        },
        {"gates": [None]},
        {"gates": "nope"},
        {"concurrency": -1, "gates": [{"id": "a", "command": ["true"]}]},
        {"gates": [{"id": "a", "command": ["true"], "timeoutMs": "x"}]},
        [],
    ],
)
def test_load_config_rejects(tmp_path, data):
    p = _write(tmp_path, data)
    with pytest.raises(gates.ConfigError):
        gates.load_config(str(p))


def test_run_gates_passes():
    gs = [gates.Gate(id="a", command=["true"]), gates.Gate(id="b", command=["true"])]
    assert gates.run_gates(gs, None, 1, False) == 0


def test_run_gates_skips_transitively(capsys):
    gs = [
        gates.Gate(id="A", command=["true"], needs=["B"]),
        gates.Gate(id="B", command=["true"], needs=["C"]),
        gates.Gate(id="C", command=["false"]),
    ]
    assert gates.run_gates(gs, None, 1, False) == 1
    out = capsys.readouterr().out
    assert "SKIP A" in out
    assert "SKIP B" in out
    assert "PASS A" not in out


def test_run_gates_missing_command():
    gs = [gates.Gate(id="a", command=["no-such-cmd-xyz"])]
    assert gates.run_gates(gs, None, 1, False) == 1


def test_run_gates_reports_disabled_and_never_runs_them(capsys):
    gs = [
        gates.Gate(id="a", command=["true"]),
        gates.Gate(id="b", command=["false"], enabled=False),
    ]
    assert gates.run_gates(gs, None, 1, False) == 0
    out = capsys.readouterr().out
    assert "DISABLED b" in out
    assert "FAIL b" not in out


def test_run_gates_selection_skips_disabled(capsys):
    gs = [
        gates.Gate(id="a", command=["true"]),
        gates.Gate(id="b", command=["false"], enabled=False),
    ]
    assert gates.run_gates(gs, ["a", "b"], 1, False) == 0
    out = capsys.readouterr().out
    assert "DISABLED b" in out
    assert "FAIL b" not in out


def test_run_gates_advisory_failure_reports_but_does_not_block(capsys):
    gs = [gates.Gate(id="a", command=["false"], allow_failure=True)]
    assert gates.run_gates(gs, None, 1, False) == 0
    out = capsys.readouterr().out
    assert "FAIL a" in out
    assert "advisory" in out


def test_main_default_mode_scopes_run(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(
        tmp_path,
        {
            "modes": {"all": ["a"], "also": ["b"]},
            "defaultMode": "all",
            "gates": [
                {"id": "a", "command": ["true"]},
                {"id": "b", "command": ["false"]},
            ],
        },
    )
    assert gates.main([]) == 0
    out = capsys.readouterr().out
    assert "PASS a" in out
    assert "FAIL b" not in out  # b is outside the default mode; it must not run


def test_main_mode_overrides_default_mode(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(
        tmp_path,
        {
            "modes": {"all": ["a"], "just-b": ["b"]},
            "defaultMode": "all",
            "gates": [
                {"id": "a", "command": ["true"]},
                {"id": "b", "command": ["true"]},
            ],
        },
    )
    assert gates.main(["--mode", "just-b"]) == 0
    out = capsys.readouterr().out
    assert "PASS b" in out
    assert "PASS a" not in out


def test_load_config_parses_paths(tmp_path):
    p = _write(tmp_path, {"gates": [{"id": "a", "command": ["true"],
                                     "paths": ["gov/**", "gates.json"]}]})
    modes, gs, concurrency, default_mode = gates.load_config(str(p))
    assert gs[0].paths == ["gov/**", "gates.json"]


@pytest.mark.parametrize("paths", ["gov/", [""], [1]])
def test_load_config_rejects_bad_paths(tmp_path, paths):
    p = _write(tmp_path, {"gates": [{"id": "a", "command": ["true"], "paths": paths}]})
    with pytest.raises(gates.ConfigError):
        gates.load_config(str(p))


def test_glob_regex_span_and_depth():
    assert gates._glob_regex("gov/**").match("gov/cli.py")
    assert gates._glob_regex("gov/**").match("gov/templates/gates.json")
    assert not gates._glob_regex("gov/*").match("gov/templates/gates.json")
    assert gates._glob_regex("*.i18n.yaml").match("README.i18n.yaml")
    assert not gates._glob_regex("*.i18n.yaml").match("docs/x.i18n.yaml")


def test_select_by_paths():
    gs = [
        gates.Gate(id="unpathed", command=["true"]),
        gates.Gate(id="docs-gate", command=["true"], paths=["docs/**"]),
        gates.Gate(id="off", command=["true"], enabled=False, paths=["docs/**"]),
    ]
    selected, out = gates._select_by_paths(gs, ["docs/a.md", "README.md"])
    assert selected == ["unpathed", "docs-gate"]
    assert out == []


def test_main_base_scopes_run(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    _write(
        tmp_path,
        {
            "gates": [
                {"id": "docs-gate", "command": ["true"], "paths": ["docs/**"]},
                {"id": "code-gate", "command": ["true"], "paths": ["src/**"]},
                {"id": "unpathed", "command": ["true"]},
            ]
        },
    )
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "a.md").write_text("x\n")
    assert gates.main(["--base", "HEAD"]) == 0
    out = capsys.readouterr().out
    assert "out of scope: code-gate" in out
    assert "PASS docs-gate" in out
    assert "PASS code-gate" not in out
    assert "PASS unpathed" in out  # unpathed gates always run


def test_main_gate_flag_runs_one(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(
        tmp_path,
        {"gates": [{"id": "a", "command": ["true"]},
                   {"id": "b", "command": ["true"]}]},
    )
    assert gates.main(["--gate", "b"]) == 0
    out = capsys.readouterr().out
    assert "PASS b" in out
    assert "PASS a" not in out


def test_main_rejects_gate_and_mode_combo(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(tmp_path, {"modes": {"all": ["a"]},
                      "gates": [{"id": "a", "command": ["true"]}]})
    assert gates.main(["--gate", "a", "--mode", "all"]) == 2


def test_main_rejects_unknown_gate(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(tmp_path, {"gates": [{"id": "a", "command": ["true"]}]})
    assert gates.main(["--gate", "ghost"]) == 2


def test_failure_summary_names_gate_and_rerun(capsys):
    gs = [
        gates.Gate(id="boom", command=["sh", "-c", "echo boom >&2; exit 3"]),
        gates.Gate(id="ok", command=["true"]),
    ]
    assert gates.run_gates(gs, None, 1, False) == 1
    out = capsys.readouterr().out
    assert "--- summary: 1 blocking failure(s) ---" in out
    assert "boom: boom" in out
    assert "rerun a single gate: gov run --gate <id>" in out


def test_usage_prog_names_the_subcommand(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(tmp_path, {"gates": []})
    with pytest.raises(SystemExit) as exc:
        gates.main(["--help"])
    assert exc.value.code == 0
    assert "usage: gov run" in capsys.readouterr().out


def test_pass_with_output_stays_visible(capsys):
    """A passing gate that printed a warning must not be silenced (P1-2)."""
    gs = [gates.Gate(id="warny", command=["sh", "-c", "echo line1; echo line2; echo line3; echo heads up; echo last warning; exit 0"])]
    assert gates.run_gates(gs, None, 1, False) == 0
    out = capsys.readouterr().out
    assert "PASS warny" in out
    assert "passed with output" in out
    assert "last warning" in out
    assert "earlier line(s) not shown" in out  # the cap dropped earlier lines
    assert "line1" not in out
    # the omission note reads after the shown content, not before it
    assert out.index("last warning") < out.index("earlier line(s) not shown")


def test_load_config_rejects_gate_in_no_mode(tmp_path):
    """D24: mode omission is not a parking mechanism — it silently never runs."""
    p = _write(tmp_path, {
        "modes": {"all": ["a"]},
        "gates": [{"id": "a", "command": ["true"]},
                  {"id": "ghost-gate", "command": ["true"]}],
    })
    with pytest.raises(gates.ConfigError) as e:
        gates.load_config(str(p))
    assert "ghost-gate" in str(e.value)
    assert "enabled\": false" in str(e.value)


def test_disabled_gate_may_omit_modes(tmp_path):
    p = _write(tmp_path, {
        "modes": {"all": ["a"]},
        "gates": [{"id": "a", "command": ["true"]},
                  {"id": "parked", "command": ["true"], "enabled": False}],
    })
    modes, gs, concurrency, default_mode = gates.load_config(str(p))
    assert [g.id for g in gs] == ["a", "parked"]


def test_gate_on_disabled_gate_fails_loud(tmp_path, capsys, monkeypatch):
    """N4: naming a parked gate is operator error, not a silent green."""
    monkeypatch.chdir(tmp_path)
    _write(tmp_path, {"gates": [{"id": "a", "command": ["true"], "enabled": False}]})
    assert gates.main(["--gate", "a"]) == 2
    assert "disabled" in capsys.readouterr().err


def test_every_gate_ignores_default_mode(tmp_path, capsys, monkeypatch):
    """D24: the explicit full matrix for CI."""
    monkeypatch.chdir(tmp_path)
    _write(tmp_path, {
        "modes": {"all": ["a"], "also": ["b"]},
        "defaultMode": "all",
        "gates": [{"id": "a", "command": ["true"]},
                  {"id": "b", "command": ["true"]}],
    })
    assert gates.main(["--every-gate"]) == 0
    out = capsys.readouterr().out
    assert "PASS a" in out and "PASS b" in out
    # and the default run still scopes to `all`
    assert gates.main([]) == 0
    out = capsys.readouterr().out
    assert "PASS b" not in out
