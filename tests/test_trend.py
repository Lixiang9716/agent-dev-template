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


def test_trend_gate_filter_and_base_split(tmp_path, monkeypatch, capsys):
    import subprocess
    monkeypatch.chdir(tmp_path)
    for cmd in (["git", "init", "-q", "."],
                ["git", "config", "user.email", "t@t"],
                ["git", "config", "user.name", "t"]):
        subprocess.run(cmd, cwd=tmp_path, check=True)
    (tmp_path / "seed.txt").write_text("x\n")
    subprocess.run(["git", "add", "-A"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-c", "commit.gpgsign=false", "commit", "-qm", "base"],
                   cwd=tmp_path, check=True)
    _history(tmp_path, [
        [{"gate": "a", "outcome": "PASS", "duration_ms": 100, "blocking": False, "detail": ""}],
        [{"gate": "b", "outcome": "PASS", "duration_ms": 500, "blocking": False, "detail": ""}],
        [{"gate": "a", "outcome": "PASS", "duration_ms": 900, "blocking": False, "detail": ""}],
    ])
    assert trend.main(["--gate", "a"]) == 0
    out = capsys.readouterr().out
    assert "a" in out and " b" not in out.replace("gate", " ")
    # split at the first commit (before all runs) -> everything is "late"
    assert trend.main(["--gate", "a", "--base", "HEAD"]) == 0
    assert "split at HEAD" in capsys.readouterr().out
