# Changelog

All notable changes to govrail are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-08-23

First release, renamed from `agent-dev-template`.

### Added

- `gov` CLI with eight subcommands: `init`, `uninstall`, `run`, `self-test`,
  `verify-notes`, `verify-pairing`, `change-scope`, `archive-notes`.
- Gates: a DAG runner over `gates.json` with `needs`/`modes`/`concurrency`/
  `timeoutMs`/`allowFailure`, and five outcomes (PASS/FAIL/TIMEOUT/MISSING/SKIP).
- Notes: three required sections (Problem/Decision/Alternatives) and an
  implemented/archived lifecycle.
- Bilingual pairing pinned by git blob hashes.
- Rejection cases (`self-test`) proving each governance gate rejects.
- `gov init`/`uninstall`: non-invasive, idempotent, manifest-reversible.
- Packaging installable via pip/uv/pipx and published to PyPI.
- CI: gates on every push/PR; version-tagged publish to PyPI with a tag/version
  consistency check.

### Removed

- The bash/PowerShell twin implementation, replaced by a Python single
  implementation.
