# govrail

English | [中文](README.zh.md)

[![CI](https://github.com/Lixiang9716/govrail/actions/workflows/ci.yml/badge.svg)](https://github.com/Lixiang9716/govrail/actions/workflows/ci.yml)
[![PyPI](https://img.shields.io/pypi/v/govrail.svg)](https://pypi.org/project/govrail/)
[![Python](https://img.shields.io/pypi/pyversions/govrail.svg)](https://pypi.org/project/govrail/)
[![GitHub Repo stars](https://img.shields.io/github/stars/Lixiang9716/govrail)](https://github.com/Lixiang9716/govrail/stargazers)

A language-agnostic governance plane for agent-driven development: coding
agents work fast in parallel while machines — not vigilance — hold the quality
line. The only runtime dependency is Python 3.

The plane ships two mechanisms: **gates** (any promise a command can check
becomes a mechanical check) and **notes** (every non-trivial change records the
decision, what it beat, and the consequences). Bilingual pairing keeps the
external-presentation docs in sync.

## What it changes

| Without govrail | With govrail |
|---|---|
| Agents follow rules "on their honor"; nothing is enforced | Every checkable promise is a gate that fails loud |
| "Why did we do this?" is lost or re-litigated | Each decision is a note with the alternatives it beat |
| Adopting tooling means a restructure or a new runtime | One command, zero restructure: `gov init` |

See a governed project in [examples/demo-project](examples/demo-project).

## Install

```sh
pip install govrail        # or: uv tool install govrail / pipx install govrail
```

This puts the `gov` CLI on your PATH (stdlib only — no third-party
dependencies). It has one subcommand per action:

```sh
gov init --project <path>     # inject the plane into an existing project
gov init --project <path> --hooks --ci  # also install a pre-push hook and CI
gov uninstall --project <path>  # reverse it exactly
gov run                        # run the default mode's gate DAG (defaultMode)
gov run --base HEAD~1          # only the gates whose paths match the diff
gov run --gate pairing         # rerun a single gate
gov self-test                  # prove every governance gate can reject
gov verify-pairing --write    # re-confirm a bilingual pair after editing one side
gov verify-pairing --write en:docs/a.md zh:docs/a_CN.md  # register any naming
gov verify-note-presence      # warn when a non-trivial diff carries no Agent Note
gov verify-rubric             # check the review rubric's structure
gov recall <terms>            # retrieve notes, decisions, postmortems
gov audit-notes               # staleness signals in implemented notes
gov change-scope --base <ref> # smallest sufficient check set for a diff
```

`init` is non-invasive and idempotent: it creates `.gov/rules.md`, adds
`gates.json` and the notes README only when missing, appends one reference line
to AGENTS.md, and never overwrites the project's own files. `uninstall` reverses
it exactly — including the hook and workflow `--hooks`/`--ci` added. A fresh
install never goes red on its first run: the pairing gate ships advisory,
`gov verify-pairing --write` baselines the existing pairs, and removing
`allowFailure` turns it enforcing. `enabled: false` parks a gate without
deleting its definition.

## What is inside

- `gov/` — the Python package: `gates` (the DAG runner over `gates.json`),
  `verify_notes` (three required sections), `verify_translation_pairing`
  (git blob hashes), `verify_note_presence`, `verify_rubric`, `recall`
  (memory retrieval), `audit_notes` (staleness signals), `change_scope`,
  `self_test`, `archive_notes`.
- `gov/templates/` — the rules, default `gates.json`, and notes format that
  `gov init` injects into a project.
- `.gov/rules.md` — the single source of truth for the rules.
- `.agents/notes/` — the decision-record format and lifecycle.
- `.agents/skills/` — the triggers that send agents to the tools first:
  `recall-first` (memory before proposals), `pre-push-checks` (smallest
  sufficient set), `code-review` (rubric), `archive-agent-notes`.
- `docs/review-rubric.md` — how PRs are judged: the criteria gates cannot
  check, graded item by item.

## Origin

The mechanisms are distilled from the DeepSeek Harness repository, whose
gates-over-prose axiom shaped this template. Kept: the governance plane. Left to
you: the product plane. The locked design decisions live in
[docs/decisions.md](docs/decisions.md).

## Star History

![Star History](https://raw.githubusercontent.com/Lixiang9716/govrail/stats/stars.svg)
