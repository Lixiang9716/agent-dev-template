import io
import subprocess
import sys
from pathlib import Path

from gov import decision, verify_decisions as vd

SECTIONS_TABLE = "# 决策\n\n## D1 — one\n\n- **选项**: a\n- **被否**: b\n"


def _git_repo(root):
    for cmd in (["git", "init", "-q", "."],
                ["git", "config", "user.email", "t@t"],
                ["git", "config", "user.name", "t"]):
        subprocess.run(cmd, cwd=root, check=True,
                       env={k: v for k, v in subprocess.os.environ.items()
                            if not k.startswith("GIT_")})


def _commit(root, msg="c"):
    env = {k: v for k, v in subprocess.os.environ.items()
           if not k.startswith("GIT_")}
    subprocess.run(["git", "add", "-A"], cwd=root, check=True, env=env)
    subprocess.run(["git", "-c", "commit.gpgsign=false", "commit", "-qm", msg],
                   cwd=root, check=True, env=env)


def _draft(tmp_path, title, body):
    p = tmp_path / "draft.md"
    p.write_text(f"{title}\n{body}\n", encoding="utf-8")
    return str(p)


# --- next -------------------------------------------------------------------

def test_next_empty_table_starts_at_d0(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text("# 决策\n")
    assert decision.main(["next"]) == 0
    assert capsys.readouterr().out.strip() == "D0"


def test_next_returns_max_plus_one_and_counts(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(
        "# 决策\n\n## D0 — a\n\n- **选项**: x\n\n## D1 — b\n\n- **选项**: x\n")
    assert decision.main(["next"]) == 0
    assert capsys.readouterr().out.strip() == "D2"
    assert decision.main(["next", "--count", "3"]) == 0
    assert capsys.readouterr().out.split() == ["D2", "D3", "D4"]


def test_next_base_unions_landed_numbers(tmp_path, monkeypatch, capsys):
    """A branch cut before a sibling landed must not re-allocate (accept #2)."""
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(SECTIONS_TABLE)
    _commit(tmp_path, "base")
    # the "sibling" branch lands D2 on master while we sit on the fork
    (docs / "decisions.md").write_text(
        SECTIONS_TABLE + "\n## D2 — two\n\n- **选项**: a\n- **被否**: b\n")
    _commit(tmp_path, "sibling lands D2")
    # our branch resets to the fork point: locally D2 is free, on master it
    # is not — --base must say D3, plain next would say D2
    subprocess.run(["git", "checkout", "-q", "HEAD~1", "--", "docs"],
                   cwd=tmp_path, check=True)
    assert decision.main(["next", "--base", "master"]) == 0
    assert capsys.readouterr().out.strip() == "D3"


def test_next_bad_base_fails_loud(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(SECTIONS_TABLE)
    try:
        decision.main(["next", "--base", "no-such-ref"])
        raise AssertionError("unknown --base must exit 2")
    except SystemExit as e:
        assert e.code == 2


# --- add --------------------------------------------------------------------

def test_add_sections_appends_validated_row(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(SECTIONS_TABLE)
    draft = _draft(tmp_path, "two", "- **选项**: a\n- **被否**: b")
    assert decision.main(["add", "--from", draft]) == 0
    text = (docs / "decisions.md").read_text(encoding="utf-8")
    assert "## D2 — two" in text
    assert text.rstrip("\n").endswith("- **被否**: b")
    # the appended table still satisfies the gate
    assert vd.main([]) == 0


def test_add_refuses_duplicate_and_gap_and_altless(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(SECTIONS_TABLE)
    dup = _draft(tmp_path, "x", "- **选项**: a\n- **被否**: b")
    try:
        decision.main(["add", "--from", dup, "--id", "D1"])
        raise AssertionError("duplicate --id must exit 1")
    except SystemExit as e:
        assert e.code == 1
    assert "D1 already exists" in capsys.readouterr().err
    gap = _draft(tmp_path, "x", "- **选项**: a\n- **被否**: b")
    try:
        decision.main(["add", "--from", gap, "--id", "D5"])
        raise AssertionError("a gap-opening --id must exit 1")
    except SystemExit as e:
        assert e.code == 1
    assert "skips" in capsys.readouterr().err
    altless = _draft(tmp_path, "x", "- **状态**: 已决")
    try:
        decision.main(["add", "--from", altless])
        raise AssertionError("an alternative-less draft must exit 1")
    except SystemExit as e:
        assert e.code == 1
    assert "alternatives" in capsys.readouterr().err
    # nothing was written by any refusal
    assert "## D2" not in (docs / "decisions.md").read_text(encoding="utf-8")


def test_add_dry_run_writes_nothing(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(SECTIONS_TABLE)
    before = (docs / "decisions.md").read_text(encoding="utf-8")
    draft = _draft(tmp_path, "two", "- **选项**: a\n- **被否**: b")
    assert decision.main(["add", "--from", draft, "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert "## D2 — two" in out
    assert (docs / "decisions.md").read_text(encoding="utf-8") == before


def test_add_table_format_allocates_first_cell(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    gov = tmp_path / ".gov"
    gov.mkdir()
    (gov / "decisions.json").write_text(
        '{"path": "TABLE.md", "format": "table"}', encoding="utf-8")
    (tmp_path / "TABLE.md").write_text(
        "| id | title | alternatives |\n|---|---|---|\n"
        "| D1 | one | a vs b |\n", encoding="utf-8")
    draft = tmp_path / "draft.md"
    draft.write_text("| ? | two | c vs d |\n", encoding="utf-8")
    assert decision.main(["add", "--from", str(draft)]) == 0
    text = (tmp_path / "TABLE.md").read_text(encoding="utf-8")
    assert "| D2 | two | c vs d |" in text
    # header alternatives column covers the row — no alt refusal
    assert vd.main([]) == 0


def test_add_dir_format_creates_file_and_gate_passes(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    gov = tmp_path / ".gov"
    (gov / "decisions").mkdir(parents=True)
    (gov / "decisions.json").write_text(
        '{"path": ".gov/decisions", "format": "dir"}', encoding="utf-8")
    (gov / "decisions" / "D1-one.md").write_text(
        "## D1 — one\n\n- **选项**: a\n- **被否**: b\n", encoding="utf-8")
    draft = _draft(tmp_path, "two", "- **选项**: a\n- **被否**: b")
    assert decision.main(["add", "--from", draft]) == 0
    new = gov / "decisions" / "D2-two.md"
    assert new.is_file()
    assert new.read_text(encoding="utf-8").startswith("## D2 — two")
    assert vd.main([]) == 0


# --- accept criteria: two worktrees from the same base -----------------------

def _dir_repo(root):
    """A committed dir-format repo ready to fan out into worktrees."""
    _git_repo(root)
    (root / ".gov" / "decisions").mkdir(parents=True)
    (root / ".gov" / "decisions.json").write_text(
        '{"path": ".gov/decisions", "format": "dir"}', encoding="utf-8")
    (root / ".gov" / "decisions" / "D1-one.md").write_text(
        "## D1 — one\n\n- **选项**: a\n- **被否**: b\n", encoding="utf-8")
    _commit(root, "base")


def test_two_worktrees_dir_format_merge_clean_or_named_collision(tmp_path,
                                                                 monkeypatch):
    """Accept #107: same-base appends merge without textual conflicts;
    a shared number becomes a loud, named gate failure — never silence."""
    env = {k: v for k, v in subprocess.os.environ.items()
           if not k.startswith("GIT_")}
    base = tmp_path / "base"
    base.mkdir()
    _dir_repo(base)
    for name in ("wt-a", "wt-b"):
        subprocess.run(["git", "worktree", "add", "-q", "-b", name,
                        str(tmp_path / name)], cwd=base, check=True, env=env)

    def add_in(wt, title):
        # run THIS checkout's gov, not any installed wheel
        repo_root = str(Path(__file__).resolve().parents[1])
        subprocess.run(
            [sys.executable, "-m", "gov", "decision", "add", "--from",
             _draft(tmp_path, title, "- **选项**: a\n- **被否**: b")],
            cwd=wt, check=True, capture_output=True, text=True,
            env=dict(env, PYTHONPATH=repo_root),
        )

    add_in(tmp_path / "wt-a", "from a")
    add_in(tmp_path / "wt-b", "from b")  # same base → same number D2
    for name in ("wt-a", "wt-b"):
        subprocess.run(["git", "add", "-A"], cwd=tmp_path / name,
                       check=True, env=env)
        subprocess.run(["git", "-c", "commit.gpgsign=false", "commit",
                        "-qm", name], cwd=tmp_path / name, check=True,
                       env=env)
    # merge B into A: dir format → no textual conflict (different files)
    merge = subprocess.run(["git", "merge", "-q", "--no-edit", "wt-b"],
                           cwd=tmp_path / "wt-a", capture_output=True,
                           text=True, env=env)
    assert merge.returncode == 0, (merge.stdout, merge.stderr)
    # but the duplicate number is a loud, named gate failure
    monkeypatch.chdir(tmp_path / "wt-a")
    import io
    import contextlib
    err = io.StringIO()
    with contextlib.redirect_stdout(err):
        code = vd.main([])
    assert code == 1
    assert "D2: duplicate decision entry" in err.getvalue()


def test_verify_decisions_base_names_collision(tmp_path, monkeypatch,
                                               capsys):
    """--base: a number added on both sides since the fork is refused,
    by name, with the fix in the message."""
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    subprocess.run(["git", "branch", "-q", "-m", "main"], cwd=tmp_path,
                   check=True)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(SECTIONS_TABLE)
    _commit(tmp_path, "fork point")
    subprocess.run(["git", "checkout", "-q", "-b", "topic"], cwd=tmp_path,
                   check=True)
    (docs / "decisions.md").write_text(
        SECTIONS_TABLE + "\n## D2 — mine\n\n- **选项**: a\n- **被否**: b\n")
    _commit(tmp_path, "branch adds D2")
    subprocess.run(["git", "checkout", "-q", "main"], cwd=tmp_path,
                   check=True)
    (docs / "decisions.md").write_text(
        SECTIONS_TABLE + "\n## D2 — theirs\n\n- **选项**: a\n- **被否**: b\n"
        "\n## D3 — fill\n\n- **选项**: a\n- **被否**: b\n")
    _commit(tmp_path, "sibling adds D2+D3")
    subprocess.run(["git", "checkout", "-q", "topic"], cwd=tmp_path,
                   check=True)
    assert vd.main(["--base", "main"]) == 1
    out = capsys.readouterr().out
    assert "D2: number collision" in out
    assert "gov decision next --base main" in out
    # bad ref: exit 2, named
    assert vd.main(["--base", "nope"]) == 2


def test_verify_decisions_base_gap_is_informational(tmp_path, monkeypatch,
                                                    capsys):
    monkeypatch.chdir(tmp_path)
    _git_repo(tmp_path)
    subprocess.run(["git", "branch", "-q", "-m", "main"], cwd=tmp_path,
                   check=True)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(SECTIONS_TABLE)
    _commit(tmp_path, "fork")
    subprocess.run(["git", "checkout", "-q", "-b", "topic"], cwd=tmp_path,
                   check=True)
    # branch pre-partitions: takes D3 (D2 lands on a sibling)
    (docs / "decisions.md").write_text(
        "# 决策\n\n## D1 — one\n\n- **选项**: a\n- **被否**: b\n"
        "\n## D3 — mine\n\n- **选项**: a\n- **被否**: b\n")
    _commit(tmp_path, "branch takes D3")
    # contiguity alone still flags the gap (merged history must be whole)
    assert vd.main([]) == 1
    assert "missing: D2" in capsys.readouterr().out
    # the sibling lands D2 on main meanwhile
    subprocess.run(["git", "checkout", "-q", "main"], cwd=tmp_path,
                   check=True)
    (docs / "decisions.md").write_text(
        "# 决策\n\n## D1 — one\n\n- **选项**: a\n- **被否**: b\n"
        "\n## D2 — theirs\n\n- **选项**: a\n- **被否**: b\n")
    _commit(tmp_path, "sibling lands D2")
    subprocess.run(["git", "checkout", "-q", "topic"], cwd=tmp_path,
                   check=True)
    # --base must NOT call D3 a collision: it is a pre-partitioned gap
    # whose filler (D2) exists on main — informational territory
    import contextlib
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        assert vd.main(["--base", "main"]) == 1  # local gap still a violation
    assert "number collision" not in out.getvalue()
