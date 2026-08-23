import json
from pathlib import Path

import pytest

from gov import gates


def _write(tmp_path: Path, data) -> Path:
    p = tmp_path / "gates.json"
    p.write_text(json.dumps(data))
    return p


def test_load_config_valid(tmp_path):
    p = _write(tmp_path, {"gates": [{"id": "a", "command": ["true"]}]})
    modes, gs, concurrency = gates.load_config(str(p))
    assert [g.id for g in gs] == ["a"]
    assert gs[0].command == ["true"]
    assert concurrency == 0


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
