from gov import recall


def _memory(root):
    notes = root / ".agents" / "notes" / "implemented" / "architecture"
    notes.mkdir(parents=True)
    (notes / "2026-01-01-gate-runner.md").write_text(
        "# Agent Note: the gate runner DAG\n\nStatus: implemented\n\n"
        "## Problem\nconcurrency was unbounded.\n\n"
        "## Decision\nthe runner respects the needs DAG.\n\n"
        "## Alternatives considered\na plain loop.\n"
    )
    (notes / "2026-01-02-pairing.md").write_text(
        "# Agent Note: pairing by blob hash\n\nStatus: implemented\n\n"
        "## Problem\ndrift between languages.\n\n"
        "## Decision\nhashes pin the pair.\n\n"
        "## Alternatives considered\nmanual review.\n"
    )
    docs = root / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text(
        "# log\n\n## D1 — 默认运行集\n\n- **状态**：已决\n- **决定**：defaultMode 声明默认集。\n\n"
        "## D2 — pairing 约定\n\n- **状态**：已决\n"
    )
    pm = docs / "postmortem"
    pm.mkdir()
    (pm / "2026-01-03-outage.md").write_text("# Postmortem: the outage\n\n## Root cause\ndrift.\n")
    (pm / "README.md").write_text("# Postmortems\ncontract only\n")


def test_recall_ranks_title_above_body(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _memory(tmp_path)
    assert recall.main(["pairing"]) == 0
    out = capsys.readouterr().out
    note_line = [l for l in out.splitlines() if "2026-01-02-pairing.md" in l][0]
    d_line = [l for l in out.splitlines() if "decisions.md#D2" in l][0]
    assert "matched in title" in note_line
    assert "matched in title" in d_line  # the D-heading is the entry's title
    # 'defaultMode' appears only inside D1's body → body match
    assert recall.main(["defaultMode"]) == 0
    body_out = capsys.readouterr().out
    body_line = [l for l in body_out.splitlines() if "decisions.md#D1" in l][0]
    assert "matched in body" in body_line
    assert "README" not in out  # the postmortem contract is not an entry


def test_recall_requires_all_terms(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _memory(tmp_path)
    assert recall.main(["pairing", "quantum-nonsense"]) == 1
    assert "no match" in capsys.readouterr().out


def test_recall_decisions_sections_are_entries(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _memory(tmp_path)
    assert recall.main(["默认运行集"]) == 0
    out = capsys.readouterr().out
    assert "decisions.md#D1" in out and "matched in title" in out


def test_recall_no_sources_fails_loud(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert recall.main(["anything"]) == 2


def test_recall_archived_notes_searchable(tmp_path, monkeypatch, capsys):
    arch = tmp_path / ".agents" / "notes" / "archived" / "process"
    arch.mkdir(parents=True)
    (arch / "2026-01-01-old.md").write_text("# Agent Note: the old way\n\n## Problem\nhistory.\n")
    monkeypatch.chdir(tmp_path)
    assert recall.main(["old way"]) == 0
    assert "archived/process/2026-01-01-old.md" in capsys.readouterr().out
