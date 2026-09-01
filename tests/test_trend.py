import json

from gov import trend


def _history(root, runs):
    h = root / ".gov" / "history"
    h.mkdir(parents=True)
    with (h / "gates.jsonl").open("w") as f:
        for gates in runs:
            f.write(json.dumps({"ts": "2026-09-01T00:00:00+00:00", "gates": gates}) + "\n")


def test_trend_names_duration_movers(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _history(tmp_path, [
        [{"gate": "tests", "outcome": "PASS", "duration_ms": 1000, "blocking": False, "detail": ""}],
        [{"gate": "tests", "outcome": "PASS", "duration_ms": 1000, "blocking": False, "detail": ""}],
        [{"gate": "tests", "outcome": "PASS", "duration_ms": 4000, "blocking": False, "detail": ""}],
    ])
    assert trend.main([]) == 0
    out = capsys.readouterr().out
    assert "tests" in out and "↑" in out
    assert "×2.5" in out  # p50 1.0s → 2.5s


def test_trend_stable_and_empty(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    assert trend.main([]) == 0
    assert "no history" in capsys.readouterr().out
    _history(tmp_path, [
        [{"gate": "a", "outcome": "PASS", "duration_ms": 100, "blocking": False, "detail": ""}],
        [{"gate": "a", "outcome": "PASS", "duration_ms": 110, "blocking": False, "detail": ""}],
    ])
    assert trend.main([]) == 0
    assert "stable" in capsys.readouterr().out
