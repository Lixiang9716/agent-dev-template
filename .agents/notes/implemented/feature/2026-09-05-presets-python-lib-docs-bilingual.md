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
`verify-doc-sync` reads the HIGHLIGHTS file at `gov/HIGHLIGHTS.md`,
this plane's own layout, and HIGHLIGHTS headings must read
`## <version> <description>` — a bare `## 1.0.0` is not a section to
D37's parser; a red gate from a missing file is correct fail-loud,
rule 5). A preset's mode declaration is a membership patch on the same
shared merge: `gates.merge_gates_by_id` grew an explicit
`mode_membership` ruling — `--adopt-new` keeps D39's added-only
behavior unchanged; presets converge, i.e. an existing local mode
gains every declared id that resolves in the project's gates, whether
adopted this round or already local, with local membership and its
order untouched, and an id no gate carries is skipped and named. The
verification drill found why convergence is not a nicety: a project
whose gates were already adopted (hand-wired) but whose mode
membership never landed got a silent "already adopted" and stayed
D24-unreachable (the next `gov run` died on a config error) — apply
now lands the membership even when no gate is added in the round, and
a fully converged re-apply writes nothing. Tests pin all of it:
schema walks for both bundles, list/show surfaces, package-data
reachability for skill-less preset dirs, the membership-convergence
pins (drill repro included, plus the ghost-id skip), and two scratch
acceptances (python-lib: plain init → apply → `gov run --every-gate`
green with pytest and `python -m build` actually executing, skipped
loudly where the `build` package is absent — now in the `dev` extra
so CI runs it; docs-bilingual: paired green, then an unpaired
CHANGELOG version proven red).

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
