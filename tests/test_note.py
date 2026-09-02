from gov import note as nt


def test_new_scaffold_and_bad_ref(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text("## D6 — x\n\n- **选项**：y\n")
    assert nt.main(["new", "--class", "misc", "--ref", "D6", "T"]) == 2  # closed set
    assert nt.main(["new", "--class", "process", "--ref", "D99", "T"]) == 2  # bad ref
    assert nt.main(["new", "--class", "process", "--ref", "D6", "Adopt Flow"]) == 0
    out = capsys.readouterr().out
    p = tmp_path / ".agents" / "notes" / "implemented" / "process"
    created = list(p.glob("*-adopt-flow.md"))
    assert created and "Related: D6" in created[0].read_text()
    for sec in ("## Problem", "## Decision", "## Alternatives considered"):
        assert sec in created[0].read_text()


def test_check_catches_dangling_ref(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    d = tmp_path / ".agents" / "notes" / "implemented" / "process"
    d.mkdir(parents=True)
    (d / "2026-01-01-x.md").write_text(
        "# Agent Note: x\n\nStatus: implemented\n\n## Problem\np\n\n"
        "## Decision\nd\n\n## Alternatives considered\na\n\nLocked by D42.\n")
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "decisions.md").write_text("## D6 — x\n\n- **选项**：y\n")
    assert nt.main(["check"]) == 1
    assert "D42" in capsys.readouterr().out
