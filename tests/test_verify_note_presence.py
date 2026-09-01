import subprocess

from gov import verify_note_presence as vnp


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


def _note(root, name="2026-08-28-x"):
    d = root / ".agents" / "notes" / "implemented" / "feature"
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{name}.md").write_text(
        "# Agent Note: x\n\nStatus: implemented\n\n"
        "## Problem\np\n\n## Decision\nd\n\n## Alternatives considered\na\n"
    )


def test_warns_on_code_change_without_note(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "app.py").write_text("print('v2')\n")
    assert vnp.main([]) == 0  # warn, never block (D3)
    out = capsys.readouterr().out
    assert "app.py" in out
    assert ".gov/rules.md rule 2" in out  # rule provenance, per D3


def test_strict_blocks(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "app.py").write_text("print('v2')\n")
    assert vnp.main(["--strict"]) == 1


def test_untracked_note_satisfies(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "app.py").write_text("print('v2')\n")
    _note(tmp_path)
    assert vnp.main(["--strict"]) == 0
    assert "no note" not in capsys.readouterr().out


def test_docs_only_change_needs_no_note(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "guide.md").write_text("# d\n")
    assert vnp.main(["--strict"]) == 0
    assert "non-trivial file(s) changed" not in capsys.readouterr().out


def test_root_design_doc_is_behavior_bearing(tmp_path, monkeypatch):
    """In doc-driven repos the root DESIGN.md is the contract (P3-10)."""
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "DESIGN.md").write_text("# the contract\n")
    assert vnp.main(["--strict"]) == 1


def test_root_readme_stays_trivial(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "README.md").write_text("# presentation\n")
    assert vnp.main(["--strict"]) == 0


def test_bad_ref_fails_loud(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    assert vnp.main(["--base", "no-such-ref"]) == 2


def test_single_commit_repo_works_by_default(tmp_path, monkeypatch):
    """The default base must exist from a repository's first commit."""
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)  # exactly one commit
    (tmp_path / "app.py").write_text("print('v2')\n")
    assert vnp.main([]) == 0  # runs (and warns), never dies on HEAD~1


def _commit_all(root, msg="wip"):
    subprocess.run(["git", "add", "-A"], cwd=root, check=True)
    subprocess.run(
        ["git", "-c", "commit.gpgsign=false", "commit", "-qm", msg],
        cwd=root, check=True,
    )


def test_auto_base_reviews_committed_clean_work(tmp_path, monkeypatch, capsys):
    """F1: clean tree + committed no-note work must not pass silently."""
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "app.py").write_text("v1\n")
    _commit_all(tmp_path, "first")
    (tmp_path / "app.py").write_text("v2\n")
    _commit_all(tmp_path, "second")  # clean now; no upstream configured
    assert vnp.main(["--strict"]) == 1
    out = capsys.readouterr().out
    assert "base=HEAD~1" in out
    assert "app.py" in out


def test_auto_base_prefers_upstream_range(tmp_path, monkeypatch, capsys):
    """F1: with an upstream, the clean tree reviews commits ahead of it."""
    import subprocess as sp
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    remote = tmp_path / "remote.git"
    sp.run(["git", "init", "-q", "--bare", str(remote)], check=True)
    sp.run(["git", "remote", "add", "origin", str(remote)], cwd=tmp_path, check=True)
    (tmp_path / "app.py").write_text("v1\n")
    _commit_all(tmp_path, "first")
    sp.run(["git", "push", "-q", "-u", "origin", "HEAD"], cwd=tmp_path, check=True)
    (tmp_path / "app.py").write_text("v2\n")
    _commit_all(tmp_path, "second-no-note")  # ahead of upstream, clean tree
    assert vnp.main(["--strict"]) == 1
    out = capsys.readouterr().out
    assert "upstream" in out
    assert "app.py" in out


def test_auto_base_dirty_tree_uses_head(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "app.py").write_text("uncommitted\n")  # dirty
    assert vnp.main([]) == 0
    assert "base=HEAD" in capsys.readouterr().out


def test_zero_commit_repo_first_run_stays_green(tmp_path, monkeypatch, capsys):
    """D13: a fresh install with zero commits must not go red (no HEAD)."""
    import subprocess
    monkeypatch.chdir(tmp_path)
    subprocess.run(["git", "init", "-q", "."], cwd=tmp_path, check=True)
    (tmp_path / "app.py").write_text("x = 1\n")  # untracked, no commits yet
    assert vnp.main([]) == 0
    assert "app.py" in capsys.readouterr().out


def test_staged_silent_on_clean_index(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    (tmp_path / "app.py").write_text("uncommitted\n")  # dirty worktree only
    assert vnp.main(["--staged"]) == 0
    assert capsys.readouterr().out == ""  # silent: the index is clean


def test_long_lists_collapse(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    for i in range(8):
        (tmp_path / f"file{i}.py").write_text("x\n")
    assert vnp.main([]) == 0
    out = capsys.readouterr().out
    assert "…and 3 more" in out
