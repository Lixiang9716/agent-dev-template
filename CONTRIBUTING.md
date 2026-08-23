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
gov self-test            # rejection cases: prove every governance gate rejects
gov run --mode all       # the full gate DAG (self-test + notes + pairing)
```

## Making a change

1. Make the change.
2. Run `gov run --mode all` and fix anything red.
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

1. Bump `__version__` in `gov/__init__.py` (single source).
2. `git tag v<version> && git push origin v<version>` — CI publishes to PyPI
   after checking the tag matches the version.
