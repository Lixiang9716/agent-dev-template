from gov import audit_notes


def _note(root, name, body):
    d = root / ".agents" / "notes" / "implemented" / "architecture"
    d.mkdir(parents=True, exist_ok=True)
    (d / name).write_text(body)


def test_clean_note_passes_silently(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _note(tmp_path, "2026-01-01-clean.md",
          "# Agent Note: clean\n\nStatus: implemented\n\n"
          "## Decision\nUses `gov run` and `gov recall`; see D-ref none.\n")
    assert audit_notes.main([]) == 0
    out = capsys.readouterr().out
    assert "clean" in out and "signal" not in out


def test_unknown_command_flagged(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _note(tmp_path, "2026-01-01-stale.md",
          "# Agent Note: stale\n\nStatus: implemented\n\n"
          "## Decision\nGuarded by `gov verify-links`.\n")
    assert audit_notes.main([]) == 0  # advisory: report, not block
    out = capsys.readouterr().out
    assert "`gov verify-links`" in out


def test_d_reference_without_entry_flagged(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _note(tmp_path, "2026-01-01-dref.md",
          "# Agent Note: dref\n\nStatus: implemented\n\n"
          "## Decision\nLocked by D99.\n")
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text("## D1 — real\n\n- **状态**：已决\n")
    assert audit_notes.main([]) == 0
    out = capsys.readouterr().out
    assert "D99" in out


def test_unresolved_path_flagged_placeholders_ignored(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _note(tmp_path, "2026-01-01-paths.md",
          "# Agent Note: paths\n\nStatus: implemented\n\n"
          "## Decision\nSee docs/real.md via `docs/real.md` and example `docs/foo.md`.\n")
    (tmp_path / "docs").mkdir(exist_ok=True)
    (tmp_path / "docs" / "real.md").write_text("x\n")
    assert audit_notes.main([]) == 0
    out = capsys.readouterr().out
    assert "`docs/missing" not in out  # sanity
    assert "unresolved path `docs/real.md`" not in out
    assert "foo" not in out  # placeholder paths are not flagged


def test_unresolved_real_path_flagged(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _note(tmp_path, "2026-01-01-gone.md",
          "# Agent Note: gone\n\nStatus: implemented\n\n"
          "## Decision\nLives in `gov/legacy_runner.py`.\n")
    assert audit_notes.main([]) == 0
    out = capsys.readouterr().out
    assert "unresolved path `gov/legacy_runner.py`" in out


def test_archived_exempt(tmp_path, monkeypatch, capsys):
    arch = tmp_path / ".agents" / "notes" / "archived" / "process"
    arch.mkdir(parents=True)
    (arch / "2026-01-01-frozen.md").write_text(
        "# Agent Note: frozen\n\n`gov verify-ancient` and `gone/old.py`.\n")
    monkeypatch.chdir(tmp_path)
    # implemented/ missing entirely → exit 2, so add one clean implemented note
    _note(tmp_path, "2026-01-01-clean.md",
          "# Agent Note: clean\n\nStatus: implemented\n\n## Decision\nfine.\n")
    assert audit_notes.main([]) == 0
    out = capsys.readouterr().out
    assert "frozen" not in out and "1 implemented note(s), clean" in out


def test_no_tree_fails_loud(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert audit_notes.main([]) == 2
