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


def _history_tagged(root, runs):
    h = root / ".gov" / "history"
    h.mkdir(parents=True)
    with (h / "gates.jsonl").open("w") as f:
        for caller, gates in runs:
            rec = {"ts": "2026-09-01T00:00:00+00:00", "gates": gates}
            if caller:
                rec["caller"] = caller
            f.write(json.dumps(rec) + "\n")


def test_trend_by_tag_splits_callers(tmp_path, monkeypatch, capsys):
    """#120/D42: two tagged callers report separately; untagged runs group
    under (untagged); plain `gov trend` is unchanged by tags."""
    monkeypatch.chdir(tmp_path)
    g = lambda ms: [{"gate": "tests", "outcome": "PASS",
                     "duration_ms": ms, "blocking": False, "detail": ""}]
    _history_tagged(tmp_path, [
        ("alpha", g(1000)), ("alpha", g(1000)), ("alpha", g(4000)),
        ("beta", g(100)), ("beta", g(100)), ("beta", g(100)),
        (None, g(500)), (None, g(500)),
    ])
    assert trend.main(["--by-tag"]) == 0
    out = capsys.readouterr().out
    assert "caller alpha: 3 run(s)" in out
    assert "caller beta: 3 run(s)" in out
    assert "caller (untagged): 2 run(s)" in out
    assert "×2.5 ↑" in out          # alpha's mover computed within its runs
    assert "stable" in out          # beta stable
    # untagged output stays identical in shape: tags never leak into it
    assert trend.main([]) == 0
    out = capsys.readouterr().out
    assert "caller" not in out and "×2.5" not in out


def test_trend_by_tag_without_any_tag(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _history_tagged(tmp_path, [(None, [{"gate": "a", "outcome": "PASS",
                                        "duration_ms": 1, "blocking": False,
                                        "detail": ""}])] * 2)
    assert trend.main(["--by-tag"]) == 0
    out = capsys.readouterr().out
    assert "no run carries a caller tag" in out
    assert "--tag" in out
