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

Each gate resolves to one of five outcomes — `PASS`, `FAIL`, `TIMEOUT`,
`MISSING` (executable absent), `SKIP` — and `allowFailure: true` keeps a gate's
failure observational. Exit code 0 = all green, 1 = a blocking failure.

## Knowledge planes

- **Agent Notes** carry decisions (`implemented/` then a frozen `archived/`).
  `gov verify-notes` enforces the three required sections: `## Problem`,
  `## Decision`, `## Alternatives considered` (`## Consequences` optional).
- **Bilingual pairs** carry the external-presentation docs: `foo.md` +
  `foo.zh.md` + `foo.i18n.yaml` pinned by git blob hashes.
  `gov verify-pairing` fails a one-sided edit.
- **`gov self-test`** runs a rejection case per governance gate — proving each
  gate rejects the violation it claims to catch, so no gate is a vacuous script.

## Adoption: gov init / uninstall

`gov init` injects the plane into a project: it copies `.gov/rules.md` (the
single source of truth for the rules), creates `gates.json` and the notes README
only when they are missing, appends one reference line to AGENTS.md, and records
what it created in `.gov/manifest.json`. `gov uninstall` reads that manifest and
reverses init exactly — removing only what init created, never the project's own
files. Both are idempotent.

## Growing the plane

The governance plane is a floor, not a ceiling. Growth is event-driven, never
inspiration-driven:

| Trigger | Landing |
|---|---|
| A defect class ships and is expensive to rediscover | `docs/postmortem/` entry; its guardrail distills into a gate |
| A convention is enforced by hand a third time | a skill whose description is the trigger |
| A prose promise becomes mechanically checkable | a new gate in `gates.json` with a rejection test |
| A non-trivial decision is made | an Agent Note in the same change |
