import json

import pytest

from gov import cli

from gov import archive_notes as an


def test_seals_nothing_without_crashing(tmp_path, monkeypatch, capsys):
    """A fresh init has no archived/ dir — sealing must not traceback."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".agents" / "notes" / "implemented").mkdir(parents=True)
    assert an.main([]) == 0
    assert "nothing to seal" in capsys.readouterr().out
    assert not (tmp_path / ".agents" / "notes" / "archived" / "manifest.json").exists()


def test_seals_real_notes(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    arch = tmp_path / ".agents" / "notes" / "archived" / "process"
    arch.mkdir(parents=True)
    (arch / "2026-01-01-x.md").write_text("# Agent Note: x\n")
    assert an.main([]) == 0
    manifest = tmp_path / ".agents" / "notes" / "archived" / "manifest.json"
    data = json.loads(manifest.read_text())
    assert "process/2026-01-01-x.md" in data["files"]


def test_rejects_unknown_args(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".agents" / "notes").mkdir(parents=True)
    with pytest.raises(SystemExit) as exc:
        an.main(["--bogus"])
    assert exc.value.code == 2  # argparse: unknown args abort loud


def test_fails_loud_outside_governed_project(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert an.main([]) == 2


def test_cli_dispatch_forwards_args(tmp_path, monkeypatch):
    """`gov archive-notes --bogus` must abort loud, not swallow the flag."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".agents" / "notes").mkdir(parents=True)
    with pytest.raises(SystemExit) as exc:
        cli.main(["archive-notes", "--bogus"])
    assert exc.value.code == 2  # argparse aborts loud (same as verify-pairing)
    assert cli.main(["archive-notes"]) == 0
