# Contributing

govrail is a governance plane for agent-driven development, and it governs its
own development — so contributing means following the same rules it injects
into other projects.

## Setup

```sh
git clone https://github.com/Lixiang9716/govrail.git
cd govrail
pip install -e .        # installs the gov CLI in editable mode
```

## Run the gates

```sh
pytest -q                 # unit tests
gov self-test             # rejection cases: prove every governance gate rejects
gov run                   # the full gate DAG (notes + pairing + note-presence + self-test)
```

## Making a change

1. Make the change.
2. Run `gov run` and fix anything red (`gov run --base <ref>` for the
   smallest sufficient set).
3. If the change is non-trivial, add or update an Agent Note in the same PR
   (`.agents/notes/implemented/<class>/<date>-<topic>.md`). The note needs
   `## Problem`, `## Decision`, and `## Alternatives considered` — see
   `.gov/rules.md` rule 2 and 3 for the exact test.
4. Open a PR. CI runs the gates.

## Notes and rules

- Standing orders: [.gov/rules.md](.gov/rules.md) (read before starting).
- Locked design decisions: [docs/decisions.md](docs/decisions.md).
- Bilingual docs pair whole: [docs/i18n/README.md](docs/i18n/README.md).
- Select the smallest sufficient check set:
  `gov change-scope --base <verified-ref>`.

## Releasing

1. Releases are cut by release-please from conventional commits; the version
   lives in `gov/version.py` (single source).
2. Publishing to PyPI is automated on the release tag — the workflow checks
   the tag matches the package version. The PyPI index can lag the publish
   by ~a minute; a first `pip install -U` right after may miss the fresh
   wheel — retry before suspecting the release.

### The release PR may need one click

The `chore(master): release x.y.z` PR is authored by the release-please bot.
GitHub holds its CI run in "action_required" (workflow runs from bot PRs
need a maintainer's approval; that setting exists only in the repository UI).
When it happens, either:

- open the PR's checks and click **Approve and run** — CI runs, the `gates`
  check reports, and the PR merges normally; or
- merge with the owner bypass (`gh pr merge <n> --squash --admin`) — admins
  are not subject to the required checks on this repository, which is scoped
  deliberately: every non-admin PR (human or agent) still requires `gates`.

Prefer the first: it keeps the release PR's CI evidence real.
