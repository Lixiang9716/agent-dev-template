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

One shipped gate inspects content rather than exit codes:
`gov verify-conflict-markers` (issue #104/D38) reads the changed files'
working-tree content and fails naming `file:line` when a line-initial
git conflict marker survives — the rebase failure mode git itself
refuses to police. Deliberate literals append the token
`gov:ignore-marker` to the line; a bare `=======` alone (a Markdown
setext underline) is not a marker.

Each gate resolves to one of five outcomes — `PASS`, `FAIL`, `TIMEOUT`,
`MISSING` (executable absent), `SKIP` — and `allowFailure: true` keeps a
gate's failure advisory: the outcome line and its output are reported tagged
`advisory`, but the exit code stays 0. A gate that passes with output keeps
its last lines visible in a `(passed with output)` block — passing with
something to say is never silenced (D20). Exit code 0 = all green,
1 = a blocking failure, which ends with a summary block naming each failed
gate, its first output line, and how to rerun it alone.

A run can leave verifiable evidence, not just a ledger line:
`gov run --receipt` appends a hash-chained receipt of the run —
per-gate outcomes bound to the tree's commit **and** tree sha, tagged
with the run's caller (`--tag`/`$GOV_CALLER`, D42), chained to the
previous receipt — to `.gov/history/receipts.jsonl` (issue #124/D44).
Editing, deleting, or reordering history breaks every later link:
`gov receipt verify <commit>` re-walks the chain and answers, with exit
0 or a named failure, whether a **full** (every enabled gate), **clean**
(no tracked file differed from the commit), **green** (every gate PASS)
run was recorded against exactly that tree — including across a squash
merge, which moves the commit sha but not the tree. A single receipt
cited in a PR body self-verifies via `gov receipt verify <commit>
--record '<json>'`, so prose like "reviewer re-ran the gates" can be
replaced by an id a machine can check. The chain is deliberately
keyless — it proves consistency and binding, not authorship; real
signatures are future work.

## Knowledge planes

- **Agent Notes** carry decisions (`implemented/` then a frozen `archived/`).
  `gov verify-notes` enforces the three required sections: `## Problem`,
  `## Decision`, `## Alternatives considered` (`## Consequences` optional).
  `gov verify-note-presence` checks the observable half of rule 2 — a diff
  that touches behavior-bearing surfaces with no note change warns (naming
  the rule); `--strict` makes it block. Its base is auto: a dirty worktree
  reviews the working tree, a clean one reviews the commits ahead of
  upstream (else the last commit) — so the pre-push hook and CI, which
  always see clean trees, review the pushed work instead of an empty diff.
  The read side of this memory:
  `gov recall <terms>` retrieves across notes, decisions, and postmortems
  (ranked by where the terms hit). Every run states the corpus it searched
  on stderr (per-class counts), a miss prints per-term hit counts so "one
  term failed the AND" is distinguishable from "the corpus lacks it"
  (#148), and `--any` ranks partial matches instead of refusing — the
  strict AND stays the default. `gov audit-notes` reports mechanical
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
  script. It is the tools' own regression and ships in the template's
  default run (`governance` mode stays as a self-test-only shortcut):
  the template CI installs an unpinned govrail, so the smoke test of the
  tool itself runs on the adopter's side. Every enabled gate must belong
  to a mode — parking is `"enabled": false`, the one loud mechanism
  (a `DISABLED` line); `gov run --every-gate` is the explicit full
  matrix. Every FAIL is classified (#139/D47): the case is replayed in
  a minimal clean environment (a temp copy of the stdlib-only package,
  no host `PYTHON*`), and the FAIL line is labeled `environment-suspect`
  (replay passes) or `tool-defect` (replay fails too) — a diagnosis,
  never a pass; `--case NAME` reruns a single case by name.
- **Task cards** carry the subagent hand-off (`gov task`, #125/D43):
  `gov task new "Title" --check "criterion"` writes `.gov/tasks/T-0001-*.json`
  pinning the current rule set (`.gov/rules.md` + `gates.json`) by content
  hash, so a brief carries the one-line pin `obey rules@<hash>` instead of
  restated discipline. `gov task check` — a gate scoped to `.gov/tasks/**` —
  names the stale cards after a governance adoption and re-verifies done
  cards' receipts; `gov task close T-0001` runs the gate DAG and records an
  all-green run as the card's completion receipt.
- **The review rubric** carries the judgment criteria gates cannot check:
  [review-rubric.md](review-rubric.md) grades PRs item by item with
  evidence; each item's `Gate candidate` field says whether it graduates
  into a gate when its promise becomes mechanically checkable.
  `gov verify-rubric` checks the rubric's own structure — never the
  judgment itself.

## Adoption: gov init / uninstall

`gov init` injects the plane into a project: it copies `.gov/rules.md` (the
single source of truth for the rules), creates `gates.json`, the notes
README, and the agent skills (recall-first, pre-push-checks, code-review,
archive-agent-notes) only when they are missing — a project's own skill is
never overwritten — appends one reference line to AGENTS.md, and records
what it created in `.gov/manifest.json`. `gov uninstall` reads that manifest and
reverses init exactly — removing only what init created, never the project's own
files. Both are idempotent.

Execution is opt-in: `gov init --hooks` installs a `pre-push` hook that runs
the gate DAG (a foreign pre-push is never overwritten — the add-on fails loud
before anything is mutated), and `gov init --ci` generates a
`.github/workflows/gov.yml` that runs `gov run`, only when that file does not
exist. Both are recorded in the manifest and reversed by `uninstall`.

The optional pre-commit hook (`gov init --hooks --pre-commit`, #110) runs
only the cheap content gates on the staged files — `verify-pairing --staged`
(sidecar freshness for the staged `.md`/`.zh.md` pairs; staging the source,
the counterpart, or the record counts as touching the pair) and
`verify-conflict-markers --staged` — so pairing drift surfaces at
`git commit` with the scoped fix command inline, one stage earlier than the
pre-push block. Repos that find commit hooks intrusive stay on the pre-push
model (no flag, zero change at the commit stage); the full gate DAG never
runs at commit time — a commit must stay fast, and rule 1 gives the push
the smallest sufficient set. A lone `--pre-commit` fails loud (it rides
with `--hooks`); a foreign pre-commit is never overwritten.

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
