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
    assert "tools 34 + project 1" in out
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


def test_coverage_ledger_and_bad_shebang(tmp_path, monkeypatch, capsys):
    """Wish 4: gate x case matrix; a shebang-less case is named, not fatal."""
    import json as _json
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".gov").mkdir()
    (tmp_path / "gates.json").write_text(_json.dumps(
        {"modes": {"all": ["alpha", "beta"]},
         "gates": [{"id": "alpha", "command": ["true"]},
                   {"id": "beta", "command": ["true"]}]}))
    rej = tmp_path / ".gov" / "rejections"
    rej.mkdir()
    good = rej / "case-alpha.sh"
    good.write_text("#!/bin/sh\n# gate: alpha\nexit 0\n")
    good.chmod(0o755)
    bad = rej / "case-noshebang.sh"
    bad.write_text("# gate: ghost\nexit 0\n")  # no shebang, unknown gate
    bad.chmod(0o755)
    assert st.main(["--scope", "project"]) == 1  # the bad case fails, named
    out = capsys.readouterr().out
    assert "missing shebang" in out
    assert "alpha(1)" in out and "beta(NONE — rule 6)" in out
    assert "case names unknown gate(s): ghost" in out


def test_coverage_pointer_when_uncovered(tmp_path, monkeypatch, capsys):
    import json as _json
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".gov").mkdir()
    (tmp_path / "gates.json").write_text(_json.dumps(
        {"modes": {"all": ["x"]}, "gates": [{"id": "x", "command": ["true"]}]}))
    assert st.main(["--scope", "project"]) == 0  # no cases at all
    out = capsys.readouterr().out
    assert "x(NONE — rule 6)" in out
    assert "write one: .gov/rejections/case-<gate-id>.sh" in out
