import json
import re
from pathlib import Path

import gov.whatsnew as wn


def test_whatsnew_since_manifest(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".gov").mkdir()
    (tmp_path / ".gov" / "manifest.json").write_text(
        json.dumps({"version": "0.10.0"}))
    assert wn.main([]) == 0
    out = capsys.readouterr().out
    assert "since 0.10.0" in out
    assert "0.12.1" in out and "0.11.0" in out
    assert "0.9.0" not in out  # not newer than 0.10.0


def test_whatsnew_no_project_prints_newest(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    assert wn.main([]) == 0
    out = capsys.readouterr().out
    assert "newest section" in out
    assert "0.12.1" in out


def test_whatsnew_explicit_since(capsys):
    assert wn.main(["--since", "0.11.0"]) == 0
    out = capsys.readouterr().out
    assert "0.12.1" in out and "## 0.11.0" not in out
