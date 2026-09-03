"""CHANGELOG ↔ HIGHLIGHTS pairing (D37)."""
import subprocess
import sys
from pathlib import Path

from gov import verify_doc_sync as vds


def test_paired_versions_pass():
    assert vds.main([]) == 0


def test_changelog_gains_version_highlights_missing(tmp_path, monkeypatch, capsys):
    """The release-please flow: CHANGELOG gains a section, HIGHLIGHTS
    hasn't followed yet — the gate goes red, naming the version to copy."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / "CHANGELOG.md").write_text(
        "# Changelog\n\n## [0.14.0] (2026-09-04)\n\n### Features\n\n* new thing\n")
    gov = tmp_path / "gov"
    gov.mkdir()
    (gov / "HIGHLIGHTS.md").write_text(
        "## 0.13.2 — old\n\n- something\n")
    assert vds.main([]) == 1
    out = capsys.readouterr().out
    assert "CHANGELOG has [0.14.0] but HIGHLIGHTS has no section" in out
    assert "copy the version FROM CHANGELOG" in out


def test_highlights_ahead_of_changelog(tmp_path, monkeypatch, capsys):
    """A section written for a version that hasn't released yet — the gate
    catches the direction too (section shipped before its release)."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / "CHANGELOG.md").write_text(
        "# Changelog\n\n## [0.13.0] (2026-09-03)\n\n### Features\n\n* something\n")
    gov = tmp_path / "gov"
    gov.mkdir()
    (gov / "HIGHLIGHTS.md").write_text(
        "## 0.14.0 — guessed\n\n- not released yet\n\n## 0.13.0 — real\n\n- something\n")
    assert vds.main([]) == 1
    assert "HIGHLIGHTS has 0.14.0 but CHANGELOG does not" in capsys.readouterr().out


def test_floor_excludes_pre_012_versions(tmp_path, monkeypatch):
    """Versions before 0.12.0 (HIGHLIGHTS' birth) are exempt."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / "CHANGELOG.md").write_text(
        "# Changelog\n\n## [0.11.0] (2026-09-01)\n\n### Features\n\n* old\n"
        "\n## [0.12.0] (2026-09-02)\n\n### Features\n\n* new\n")
    gov = tmp_path / "gov"
    gov.mkdir()
    (gov / "HIGHLIGHTS.md").write_text("## 0.12.0 — birth\n\n- here\n")
    assert vds.main([]) == 0  # 0.11.0 exempt; 0.12.0 paired
