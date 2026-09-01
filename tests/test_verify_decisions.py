import subprocess

from gov import verify_decisions as vd


def _table(*sections):
    return "# 决策\n\n" + "\n".join(sections)


def _d(n, body="- **选项**：x\n- **被否**：y\n"):
    return f"## D{n} — t{n}\n\n{body}\n"


def _git_repo(root):
    for cmd in (["git", "init", "-q", "."],
                ["git", "config", "user.email", "t@t"],
                ["git", "config", "user.name", "t"]):
        subprocess.run(cmd, cwd=root, check=True)


def test_clean_table_passes_d0_or_d1_start(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(_table(_d(1), _d(2), _d(3)))
    assert vd.main([]) == 0
    assert "3 decision(s) ok" in capsys.readouterr().out


def test_duplicate_and_gap_named(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    # D1, D1 (duplicate), then D3 with D2 missing
    (docs / "decisions.md").write_text(_table(_d(1), _d(1), _d(3)))
    assert vd.main([]) == 1
    out = capsys.readouterr().out
    assert "D1: duplicate decision entry" in out
    assert "missing: D2" in out


def test_missing_alternatives_named(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(_table(
        _d(1), _d(2, body="- **状态**：已决\n- **决定**：就这么办。\n")))
    assert vd.main([]) == 1
    out = capsys.readouterr().out
    assert "D2: records no options or rejected alternatives" in out


def test_orphans_informational_not_blocking(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(_table(_d(1), _d(2)))
    notes = tmp_path / ".agents" / "notes" / "implemented" / "architecture"
    notes.mkdir(parents=True)
    (notes / "x.md").write_text("locked by D1\n")
    assert vd.main([]) == 0  # D2 orphaned but that is information
    out = capsys.readouterr().out
    assert "referenced by no note: D2 (informational)" in out
    assert "2 decision(s) ok, 1 orphan(s)" in out


def test_no_table_is_not_an_error(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert vd.main([]) == 0
