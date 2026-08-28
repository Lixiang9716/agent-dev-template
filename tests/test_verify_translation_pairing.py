import json

from gov import verify_translation_pairing as vtp


def _pair(root, zh_name="foo.zh.md"):
    docs = root / "docs"
    docs.mkdir(exist_ok=True)
    (docs / "foo.md").write_text("# foo\n")
    (docs / zh_name).write_text("# foo 中文\n")
    return docs


def test_resolve_source_bare_stem(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _pair(tmp_path)
    assert vtp._resolve_source("foo", vtp.DEFAULT_CONFIG).resolve() == (tmp_path / "docs" / "foo.md").resolve()


def test_resolve_source_zh_side(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _pair(tmp_path)
    assert vtp._resolve_source("docs/foo.zh.md", vtp.DEFAULT_CONFIG).resolve() == (tmp_path / "docs" / "foo.md").resolve()


def test_resolve_source_i18n_side(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _pair(tmp_path)
    assert vtp._resolve_source("docs/foo.i18n.yaml", vtp.DEFAULT_CONFIG).resolve() == (tmp_path / "docs" / "foo.md").resolve()


def test_verify_rejects_missing_record(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _pair(tmp_path)
    assert vtp.main([]) == 1


def test_custom_counterpart_convention(tmp_path, monkeypatch):
    """A project using _CN.md pairs via .gov/pairing.json."""
    monkeypatch.chdir(tmp_path)
    gov = tmp_path / ".gov"
    gov.mkdir()
    (gov / "pairing.json").write_text(json.dumps({"counterparts": ["{stem}_CN.md"]}))
    docs = _pair(tmp_path, "foo_CN.md")
    assert vtp.main([]) == 1  # no record yet — the gate rejects
    assert vtp.main(["--write", "foo"]) == 0
    rec = docs / "foo.i18n.yaml"
    assert rec.exists()
    assert "counterpart: foo_CN.md" in rec.read_text()
    assert vtp.main([]) == 0
    (docs / "foo_CN.md").write_text("# 改了\n")
    assert vtp.main([]) == 1  # a one-sided edit still goes red


def test_explicit_registration_pins_any_name(tmp_path, monkeypatch):
    """--write en:.. zh:.. registers a pair that follows no convention."""
    monkeypatch.chdir(tmp_path)
    docs = _pair(tmp_path, "foo_CN.md")
    rc = vtp.main(["--write", "en:docs/foo.md", "zh:docs/foo_CN.md"])
    assert rc == 0
    rec = (docs / "foo.i18n.yaml").read_text()
    assert "counterpart: foo_CN.md" in rec
    assert vtp.main([]) == 0  # verification honors the pinned name
    (docs / "foo_CN.md").write_text("# 改了\n")
    assert vtp.main([]) == 1  # a one-sided edit still goes red


def test_write_hint_names_the_conventions(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "foo.md").write_text("# foo\n")
    result = vtp.main(["--write", "foo"])
    assert result == 2
    err = capsys.readouterr().err
    assert "{stem}.zh.md" in err  # what was tried
    assert "en:docs/foo.md" in err  # how to register explicitly


def test_config_fail_loud(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    gov = tmp_path / ".gov"
    gov.mkdir()
    for bad in (
        {"unknown-key": []},
        {"counterparts": ["bad-pattern.md"]},
        {"counterparts": ["{stem}/x.md"]},
        {"counterparts": []},
        {"include": "docs"},
    ):
        (gov / "pairing.json").write_text(json.dumps(bad))
        assert vtp.main([]) == 2, bad
    (gov / "pairing.json").write_text("{not json")
    assert vtp.main([]) == 2


def test_exclude_removes_a_doc_from_scope(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    gov = tmp_path / ".gov"
    gov.mkdir()
    (gov / "pairing.json").write_text(json.dumps({"exclude": ["docs/foo.md"]}))
    _pair(tmp_path)
    assert vtp.main([]) == 0  # excluded source without counterpart is fine
