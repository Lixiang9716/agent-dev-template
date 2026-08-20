# First day in a derived project

English | [中文](adoption.zh.md)

The plane your project inherited is already working: gates, hooks, and pairing all run on the first commit. This guide is the day-one route: what the plane gives you, what to calibrate, and the ordered steps from derivation to your first pull request. Standing orders live in [AGENTS.md](../AGENTS.md); the machinery is explained in [architecture.md](architecture.md).

## What the plane gives you

- `gates.json` + `scripts/gates.*` — a declarative scheduler: every promise a command can check is a gate; `bash scripts/gates.sh --mode all` runs them dependency-ordered (pwsh: `pwsh -File scripts/gates.ps1 -Mode all`).
- `scripts/install-hooks.sh` — one command installs pre-commit, pre-push, and the pairing merge driver; hooks stay fast and CI owns the exhaustive matrix.
- `.agents/notes/` — Agent Notes: decision records with a lifecycle and a frozen archive.
- Bilingual pairs — every user-facing document is three sibling files pinned by git blob hashes; a one-sided edit fails the pairing gate until `--write` re-records.
- `.agents/skills/` — repeated agent workflows distilled into executable guidance.

## What to calibrate

The template's defaults are seed values, not verdicts. Before the first PR, set each of the four manifests to your project's truth:

1. `scripts/vocabulary.json` — the banned declaration-state words and the exemptions your docs need. Editing it changes a gate: re-run the vocabulary gate and its tests.
2. `scripts/doc-budgets.json` — word ceilings per document. They ratchet down; raising one is a deliberate act argued in the PR.
3. `scripts/script-pairs.json` — twin-script hashes. Edit a twin and re-confirm with `bash scripts/verify-script-pairs.sh --write` in the same change.
4. `AGENTS.md` — the standing orders your agents inherit. Keep the gates-over-prose spine; rewrite what your project needs.

A change to any manifest above is a change to the plane: update the owning Agent Note and re-run the affected gate in the same PR.

## The notes tree is inherited seed memory

`.agents/notes/` travels with the template: each note records a decision, what it beat, and the consequences. Read the existing notes before writing your own — the layout is the index. Your first note is one file:

```text
.agents/notes/implemented/process/2026-01-01-first-decision.md
```

The header is exactly three content lines, the body opens with `## Problem`, and an implemented note carries `## Decision`, `## Alternatives considered`, and `## Consequences`. A `- Claim:` entry must name its verifier, coverage, and goal-link. `scripts/verify-agent-notes.sh` enforces the shape; write your first note, run the gate, and commit it in the same PR as the change it records.

## First-day checklist

```sh
gh repo create my-app --template <owner>/agent-dev-template   # or clone and re-init
cd my-app
bash scripts/gates.sh --mode all          # everything green, zero install
sh scripts/install-hooks.sh               # pre-commit, pre-push, merge driver
# calibrate the four manifests above, then:
bash scripts/change-scope.sh --base main  # the smallest sufficient check set
# make your first real change, record it as an Agent Note, and:
bash scripts/verify-translation-pairing.sh --write README.md   # after any doc edit
git add -A && git commit                  # pre-commit runs the local gates
GATES_FORCE_HEAVY=1 bash scripts/gates.sh --mode all   # the full adoption proof (CI runs it every 12h)
```

Then open the first PR. Pre-push runs the quick mode; CI runs the light lane on every push and the heavy lane every 12 hours on a schedule. `scripts/adopt-plane.sh` re-runs this whole route on a copy of your repository — keep it green and the day-one story stays true. Local hooks stay light; only a manual heavy run takes long enough that an SSH push may need `GIT_SSH_COMMAND='ssh -o ServerAliveInterval=60'`.
