from gov import verify_translation_pairing as vtp


def test_resolve_source_bare_stem(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "foo.md").write_text("# foo\n")
    assert vtp._resolve_source("foo").resolve() == (docs / "foo.md").resolve()


def test_resolve_source_zh_side(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "foo.md").write_text("# foo\n")
    assert vtp._resolve_source("docs/foo.zh.md").resolve() == (docs / "foo.md").resolve()


def test_resolve_source_i18n_side(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "foo.md").write_text("# foo\n")
    assert vtp._resolve_source("docs/foo.i18n.yaml").resolve() == (docs / "foo.md").resolve()
