from gov import cli


def test_init_creates_files(tmp_path):
    assert cli.init(tmp_path) == 0
    assert (tmp_path / ".gov" / "rules.md").exists()
    assert (tmp_path / ".gov" / "manifest.json").exists()
    assert (tmp_path / "gates.json").exists()
    assert (tmp_path / ".agents" / "notes" / "README.md").exists()
    assert (tmp_path / "AGENTS.md").exists()


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
