# Governance architecture

English | [中文](architecture.zh.md)

The template separates two planes. The **governance plane** — gates, notes,
pairing, scope — is language-agnostic machinery in Python 3 that operates on
git, Markdown, and JSON. The **product plane** is your code in any language; it
connects only through command slots in `gates.json`.

## The gate DAG

`gov run --mode <name>` reads `gates.json` and runs one mode. A gate is any
command array that exits non-zero on failure; `needs` forms a DAG (a gate runs
after every dependency passed, and is `SKIP`ped when one failed blocking), and
`concurrency` caps parallel runs. The whole config is validated before any
child starts: duplicate ids, unknown needs, and cycles abort with the offending
names (exit code 2).

Without `--mode`, the top-level `defaultMode` runs when configured (the
injected template ships `"defaultMode": "all"`) — editing a mode is editing
the default run. `enabled: false` parks a gate outside every run, reported as
a `DISABLED` line, so "off" stays written down instead of deleting the
definition.

Gates declare what they cover with `paths` globs (`**` spans directories):
`gov run --base <ref>` selects the gates whose paths match the diff (unpathed
gates always run) and reports what was left out as out of scope — the
smallest sufficient set from one source of truth, the same `paths`
`gov change-scope` reads for its suggestions. `gov run --gate <id>` reruns a
single gate.

Each gate resolves to one of five outcomes — `PASS`, `FAIL`, `TIMEOUT`,
`MISSING` (executable absent), `SKIP` — and `allowFailure: true` keeps a
gate's failure advisory: the outcome line and its output are reported tagged
`advisory`, but the exit code stays 0. Exit code 0 = all green,
1 = a blocking failure, which ends with a summary block naming each failed
gate, its first output line, and how to rerun it alone.

## Knowledge planes

- **Agent Notes** carry decisions (`implemented/` then a frozen `archived/`).
  `gov verify-notes` enforces the three required sections: `## Problem`,
  `## Decision`, `## Alternatives considered` (`## Consequences` optional).
  `gov verify-note-presence` checks the observable half of rule 2 — a diff
  that touches behavior-bearing surfaces with no note change warns (naming
  the rule); `--strict` makes it block. The read side of this memory:
  `gov recall <terms>` retrieves across notes, decisions, and postmortems
  (ranked by where the terms hit), and `gov audit-notes` reports mechanical
  staleness signals — references the world no longer satisfies — as
  evidence for the archive skill's judgment.
- **Bilingual pairs** carry the external-presentation docs: a source `foo.md`,
  a counterpart translation, and a `foo.i18n.yaml` record pinning both sides
  by git blob hashes (plus the counterpart's name). Naming conventions are
  configuration in `.gov/pairing.json` (`include`, `counterparts`, `exclude`);
  a pair that follows no convention is registered explicitly with
  `gov verify-pairing --write en:<path> zh:<path>`. A one-sided edit fails.
- **`gov self-test`** runs a rejection case per governance gate — proving each
  gate rejects the violation it claims to catch, so no gate is a vacuous
  script. It is the tools' own regression: it ships in the template's
  `governance` mode, not in every project's default run.
- **The review rubric** carries the judgment criteria gates cannot check:
  [review-rubric.md](review-rubric.md) grades PRs item by item with
  evidence; each item's `Gate candidate` field says whether it graduates
  into a gate when its promise becomes mechanically checkable.
  `gov verify-rubric` checks the rubric's own structure — never the
  judgment itself.

## Adoption: gov init / uninstall

`gov init` injects the plane into a project: it copies `.gov/rules.md` (the
single source of truth for the rules), creates `gates.json` and the notes README
only when they are missing, appends one reference line to AGENTS.md, and records
what it created in `.gov/manifest.json`. `gov uninstall` reads that manifest and
reverses init exactly — removing only what init created, never the project's own
files. Both are idempotent.

Execution is opt-in: `gov init --hooks` installs a `pre-push` hook that runs
the gate DAG (a foreign pre-push is never overwritten — the add-on fails loud
before anything is mutated), and `gov init --ci` generates a
`.github/workflows/gov.yml` that runs `gov run`, only when that file does not
exist. Both are recorded in the manifest and reversed by `uninstall`.

A fresh install never goes red on its first run: the pairing gate ships
advisory (`allowFailure: true`), reporting what needs baselining; after
`gov verify-pairing --write` records the existing pairs, removing
`allowFailure` turns the gate enforcing. `init` prints these next steps.

## Growing the plane

The governance plane is a floor, not a ceiling. Growth is event-driven, never
inspiration-driven:

| Trigger | Landing |
|---|---|
| A defect class ships and is expensive to rediscover | `docs/postmortem/` entry; its guardrail distills into a gate |
| A convention is enforced by hand a third time | a skill whose description is the trigger |
| A prose promise becomes mechanically checkable | a new gate in `gates.json` with a rejection test |
| A non-trivial decision is made | an Agent Note in the same change |
