import subprocess

from gov import review


def _git_repo(root, files):
    for cmd in (["git", "init", "-q", "."],
                ["git", "config", "user.email", "t@t"],
                ["git", "config", "user.name", "t"]):
        subprocess.run(cmd, cwd=root, check=True)
    for name, text in files.items():
        p = root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    subprocess.run(["git", "add", "-A"], cwd=root, check=True)
    subprocess.run(["git", "-c", "commit.gpgsign=false", "commit", "-qm", "base"],
                   cwd=root, check=True)


def test_dossier_four_sections_with_rubric(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path, {"src/app.py": "x=1\n"})
    (tmp_path / "src" / "app.py").write_text("x=2\n")
    rub = tmp_path / "docs"
    rub.mkdir()
    (rub / "review-rubric.md").write_text(
        "### R1 — a\n\n- **Checks:** c\n- **Evidence:** e\n"
        "- **Anti-pattern:** a\n- **Gate candidate:** no\n")
    assert review.main(["--base", "HEAD"]) == 0
    out = capsys.readouterr().out
    for section in ("## 1. change scope", "## 2. notes in this change",
                    "## 3. recall", "## 4. rubric"):
        assert section in out
    assert "R1 — a" in out
    assert "WARNING" in out  # behavior-bearing change, no note


def test_dossier_three_sections_without_rubric(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path, {"README.md": "# x\n"})
    (tmp_path / "README.md").write_text("# y\n")
    assert review.main(["--base", "HEAD"]) == 0
    out = capsys.readouterr().out
    assert "## 3. recall" in out
    assert "## 4. rubric" not in out
    assert "reviewing without one" in out


def test_bad_ref_fails_loud(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path, {"a.txt": "x\n"})
    assert review.main(["--base", "no-such-ref"]) == 2
