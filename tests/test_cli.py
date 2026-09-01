import json
from pathlib import Path

from gov import __version__, cli


def test_init_creates_files(tmp_path):
    assert cli.init(tmp_path) == 0
    assert (tmp_path / ".gov" / "rules.md").exists()
    assert (tmp_path / ".gov" / "manifest.json").exists()
    assert (tmp_path / "gates.json").exists()
    assert (tmp_path / ".agents" / "notes" / "README.md").exists()
    assert (tmp_path / "AGENTS.md").exists()


def test_init_template_is_advisory_first(tmp_path):
    """A fresh install must not go red on the first run (P0 defect 3)."""
    assert cli.init(tmp_path) == 0
    cfg = json.loads((tmp_path / "gates.json").read_text())
    assert cfg["defaultMode"] == "all"
    pairing = [g for g in cfg["gates"] if g["id"] == "pairing"][0]
    assert pairing["allowFailure"] is True


def test_init_manifest_records_cli_version(tmp_path):
    assert cli.init(tmp_path) == 0
    manifest = json.loads((tmp_path / ".gov" / "manifest.json").read_text())
    assert manifest["version"] == __version__


def test_init_idempotent(tmp_path):
    assert cli.init(tmp_path) == 0
    before = (tmp_path / "gates.json").read_text()
    assert cli.init(tmp_path) == 0
    assert (tmp_path / "gates.json").read_text() == before


def test_uninstall_reverses(tmp_path):
    cli.init(tmp_path)
    (tmp_path / "keep.txt").write_text("keep")
    assert cli.uninstall(tmp_path) == 0
    assert (tmp_path / "keep.txt").exists()
    assert not (tmp_path / ".gov").exists()
    assert not (tmp_path / "gates.json").exists()


def test_init_help_no_side_effect(tmp_path):
    assert cli.main(["init", "--help"]) == 0
    assert cli.main(["init", "--version"]) == 0


def test_init_unknown_arg_rejected(tmp_path):
    assert cli.main(["init", "--bogus"]) == 2


def _git_repo(tmp_path):
    import subprocess
    for cmd in (
        ["git", "init", "-q", "."],
        ["git", "config", "user.email", "t@t"],
        ["git", "config", "user.name", "t"],
    ):
        subprocess.run(cmd, cwd=tmp_path, check=True)


def test_init_hooks_and_ci_roundtrip(tmp_path):
    _git_repo(tmp_path)
    assert cli.init(tmp_path, hooks=True, ci=True) == 0
    assert (tmp_path / ".gov" / "hooks" / "pre-push").exists()
    git_hook = tmp_path / ".git" / "hooks" / "pre-push"
    assert git_hook.exists() and git_hook.stat().st_mode & 0o111  # executable
    workflow = tmp_path / ".github" / "workflows" / "gov.yml"
    assert workflow.exists()
    assert cli.init(tmp_path, hooks=True, ci=True) == 0  # idempotent re-run
    assert cli.uninstall(tmp_path) == 0
    assert not git_hook.exists()
    assert not workflow.exists()
    assert not (tmp_path / "gates.json").exists()


def test_init_hooks_refuses_foreign_hook(tmp_path):
    _git_repo(tmp_path)
    hooks = tmp_path / ".git" / "hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    (hooks / "pre-push").write_text("#!/bin/sh\nmy own hook\n")
    assert cli.init(tmp_path, hooks=True) == 2
    assert (hooks / "pre-push").read_text().startswith("#!/bin/sh\nmy own")
    assert not (tmp_path / "gates.json").exists()  # no half-initialized state


def test_init_hooks_needs_git(tmp_path):
    assert cli.init(tmp_path, hooks=True) == 2
    assert not (tmp_path / "gates.json").exists()


def test_init_ci_keeps_existing_workflow(tmp_path):
    wf = tmp_path / ".github" / "workflows" / "gov.yml"
    wf.parent.mkdir(parents=True, exist_ok=True)
    wf.write_text("mine: yes\n")
    assert cli.init(tmp_path, ci=True) == 0
    assert wf.read_text() == "mine: yes\n"


def test_init_template_modes_note_presence_and_governance(tmp_path):
    assert cli.init(tmp_path) == 0
    cfg = json.loads((tmp_path / "gates.json").read_text())
    ids = [g["id"] for g in cfg["gates"]]
    assert "note-presence" in ids
    # self-test is the tools' own regression — not a per-project default run
    assert "self-test" not in cfg["modes"]["all"]
    assert cfg["modes"]["governance"] == ["self-test"]


def test_init_injects_skills(tmp_path):
    assert cli.init(tmp_path) == 0
    for name in cli.SKILLS:
        p = tmp_path / ".agents" / "skills" / name / "SKILL.md"
        assert p.exists(), name
    manifest = json.loads((tmp_path / ".gov" / "manifest.json").read_text())
    assert ".agents/skills/recall-first/SKILL.md" in manifest["created"]


def test_init_never_overwrites_own_skill(tmp_path):
    own = tmp_path / ".agents" / "skills" / "code-review" / "SKILL.md"
    own.parent.mkdir(parents=True)
    own.write_text("my own review convention\n")
    assert cli.init(tmp_path) == 0
    assert own.read_text() == "my own review convention\n"
    manifest = json.loads((tmp_path / ".gov" / "manifest.json").read_text())
    assert ".agents/skills/code-review/SKILL.md" not in manifest["created"]


def test_uninstall_removes_injected_skills(tmp_path):
    cli.init(tmp_path)
    assert cli.uninstall(tmp_path) == 0
    assert not (tmp_path / ".agents" / "skills").exists()


def test_templates_match_live_skills():
    """The shipped templates and this repo's live skills are one source."""
    root = Path(__file__).resolve().parent.parent
    for name in cli.SKILLS:
        shipped = root / "gov" / "templates" / "skills" / name / "SKILL.md"
        live = root / ".agents" / "skills" / name / "SKILL.md"
        assert shipped.read_text() == live.read_text(), (
            f"{name}: template and live skill drifted — align them"
        )


def test_init_next_steps_match_reality(tmp_path, capsys):
    """No paired docs → no baseline advice (the old step 2 exit-2'd)."""
    assert cli.init(tmp_path) == 0
    out = capsys.readouterr().out
    assert "no paired docs detected" in out
    assert "verify-pairing --write" not in out


def test_init_next_steps_with_docs(tmp_path, capsys):
    (tmp_path / "README.md").write_text("# x\n")
    assert cli.init(tmp_path) == 0
    out = capsys.readouterr().out
    assert "verify-pairing --write" in out
    assert "no paired docs detected" not in out
