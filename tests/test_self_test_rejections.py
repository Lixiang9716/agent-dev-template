import os
import subprocess
import sys
from pathlib import Path

from gov import self_test as st


def _rejection(root, name, body, executable=True):
    d = root / ".gov" / "rejections"
    d.mkdir(parents=True, exist_ok=True)
    p = d / name
    p.write_text(body)
    if executable:
        p.chmod(0o755)
    return p


def test_project_rejection_failure_names_the_case(tmp_path, monkeypatch, capsys):
    """A local rejection case that cannot prove rejection fails the self-test."""
    monkeypatch.chdir(tmp_path)
    _rejection(tmp_path, "case-broken.sh", "#!/bin/sh\nexit 1\n")
    assert st.main([]) == 1
    out = capsys.readouterr().out
    assert "FAIL .gov/rejections/case-broken.sh" in out
    assert "exit 1" in out


def test_project_rejection_pass_and_scope(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _rejection(tmp_path, "case-good.sh", "#!/bin/sh\nexit 0\n")
    (tmp_path / ".gov" / "rejections" / "README.md").write_text("docs\n")
    assert st.main([]) == 0
    out = capsys.readouterr().out
    assert "PASS .gov/rejections/case-good.sh" in out
    assert "tools 33 + project 1" in out
    # scope filters families
    assert st.main(["--scope", "project"]) == 0
    assert "tools 29" not in capsys.readouterr().out
    assert st.main(["--scope", "tools"]) == 0
    assert "project 1" not in capsys.readouterr().out


def test_non_executable_case_is_named(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _rejection(tmp_path, "case-dead.sh", "#!/bin/sh\nexit 0\n", executable=False)
    assert st.main(["--scope", "project"]) == 1
    assert "not executable" in capsys.readouterr().out


def test_readme_skipped(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _rejection(tmp_path, "README.md", "not a case\n")
    assert st.main(["--scope", "project"]) == 0


def test_parallel_reports_all_failures(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _rejection(tmp_path, "case-a.sh", "#!/bin/sh\nexit 1\n")
    _rejection(tmp_path, "case-b.sh", "#!/bin/sh\nexit 2\n")
    assert st.main(["--scope", "project"]) == 1
    out = capsys.readouterr().out
    assert "case-a.sh" in out and "case-b.sh" in out  # both, not just the first


def test_runaway_case_times_out_fast(tmp_path, monkeypatch, capsys):
    """Wish 5: a sleep-30 case fails as TIMEOUT within the 10s budget."""
    import time
    monkeypatch.chdir(tmp_path)
    _rejection(tmp_path, "case-hang.sh", "#!/bin/sh\nsleep 30\n")
    _rejection(tmp_path, "case-fine.sh", "#!/bin/sh\nexit 0\n")
    t0 = time.monotonic()
    assert st.main(["--scope", "project"]) == 1
    wall = time.monotonic() - t0
    out = capsys.readouterr().out
    assert "FAIL .gov/rejections/case-hang.sh (timed out after 10s)" in out
    assert "PASS .gov/rejections/case-fine.sh" in out  # the run continues
    assert wall < 20, f"a runaway case must not hold the run ({wall:.1f}s)"
