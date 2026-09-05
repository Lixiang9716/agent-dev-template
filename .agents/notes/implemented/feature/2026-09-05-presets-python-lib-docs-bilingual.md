# Agent Note: presets — python-lib and docs-bilingual bundles

Status: implemented

Date: 2026-09-05
Related: D53, D28, D37, D39

## Problem

D53 shipped the preset machine and the first bundle (`agent-heavy`) with
a staged promise: python-lib and docs-bilingual would follow on the same
matrix. Until they did, adopters of those two project types still
hand-wrote their gates — a Python package repo typed out pytest and
build invocations in `gates.json` by hand, and a bilingual docs repo
wired the CHANGELOG/HIGHLIGHTS sync guard (D37's `verify-doc-sync`)
itself, copy-pasting paths and mode membership and hoping the wiring
matched the plane's conventions.

## Decision

The two content presets ship, D53's staged second stage — pure data on
the existing machine, no new decision row and no new merge semantics.
`gov/templates/presets/python-lib/` lands the `pytest`
(`python -m pytest -q`) and `build` (`python -m build`) gates scoped to
`**/*.py` + `pyproject.toml`, with `pytest` joining `quick` and both
joining `all`; `gov/templates/presets/docs-bilingual/` lands the
`doc-sync` gate (`gov verify-doc-sync`, paths `CHANGELOG.md` +
`HIGHLIGHTS.md`) in `all`. Both are deliberately lean — no skills, no
hints — and each carries a README stating who it is for, what lands,
and the premise (python-lib: the environment needs `pytest` and
`build`; docs-bilingual: the repository really carries the two files,
and `verify-doc-sync` reads the HIGHLIGHTS file at `gov/HIGHLIGHTS.md`,
this plane's own layout — a red gate from a missing file is correct
fail-loud, rule 5). Declaring `all`/`quick` exercised the D39
append-into-existing-mode path for the first time from a preset; the
machine already implemented it (agent-heavy appended into the
template's `governance` mode), and tests now pin it both ways —
template membership preserved verbatim, only newly adopted ids
appended, never duplicated. Tests: schema walks for both bundles,
list/show surfaces, package-data reachability for skill-less preset
dirs, the mode-append pins, and two scratch acceptances (python-lib:
plain init → apply → `gov run --every-gate` green with pytest and
`python -m build` actually executing, skipped loudly where the `build`
package is absent — now in the `dev` extra so CI runs it; docs-bilingual:
paired green, then an unpaired CHANGELOG version proven red).

## Alternatives considered

Putting the typed gates into the default init template — violates D28
and the reason presets exist: the generic floor keeps every project
from paying for gates it will not use. A pip plugin / downloadable
preset feed — violates the zero-dependency stance, and presets land
gate `command` argvs, so a remote source is an arbitrary-command
surface; bundled data travels with code review. Widening
`verify-doc-sync` to search for the HIGHLIGHTS file so the preset could
claim any layout — a silent second contract for a shipped gate; the
preset documents the real path instead, and a mis-laid file fails loud.
