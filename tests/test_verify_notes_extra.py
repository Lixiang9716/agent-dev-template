from pathlib import Path

from gov import verify_notes as vn


def _note(text):
    return (
        "# Agent Note: t\n\nStatus: implemented\n\n" + text
    )


GOOD = "## Problem\np\n\n## Decision\nd\n\n## Alternatives considered\na\n"


def _put(root, rel, text):
    p = root / ".agents" / "notes" / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    return p


def test_section_order_enforced(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    bad = _note("## Decision\nd\n\n## Problem\np\n\n## Alternatives considered\na\n")
    _put(tmp_path, "implemented/architecture/2026-01-01-x.md", bad)
    assert vn.main([]) == 1
    assert "out of order" in capsys.readouterr().out


def test_unknown_class_rejected(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _put(tmp_path, "implemented/misc/2026-01-01-x.md", _note(GOOD))
    assert vn.main([]) == 1
    assert "unknown class 'misc'" in capsys.readouterr().out


def test_missing_class_dir_rejected(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _put(tmp_path, "implemented/2026-01-01-x.md", _note(GOOD))
    assert vn.main([]) == 1
    assert "implemented/<class>/<file>.md" in capsys.readouterr().out


def test_unknown_lifecycle_fails_loud(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _put(tmp_path, "implemented/architecture/2026-01-01-x.md", _note(GOOD))
    _put(tmp_path, "drafts/2026-01-01-x.md", _note(GOOD))
    assert vn.main([]) == 1
    assert "unknown lifecycle 'drafts'" in capsys.readouterr().out


def test_notes_readme_allowed_at_root(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _put(tmp_path, "implemented/architecture/2026-01-01-x.md", _note(GOOD))
    _put(tmp_path, "README.md", "# Agent Notes\nthe format doc\n")
    assert vn.main([]) == 0
