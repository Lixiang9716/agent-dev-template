# agent-dev-template

English | [中文](README.zh.md)

A language-agnostic template repository for agent-driven development: the governance plane that lets coding agents work fast in parallel while machines, not vigilance, hold the quality line.

The template ships the governance plane only. It never prescribes your programming language, test framework, or package manager — your toolchain plugs in as command slots in `gates.json`. The one runtime requirement is Node.js 20+ for the governance scripts themselves (no npm packages, no install step).

## What is inside

- `gates.json` + `scripts/gates.mjs` — a declarative DAG gate scheduler: dependency-ordered parallel execution, failure propagation, and fail-loud validation before any child process starts.
- `.agents/notes/` — the Agent Notes system: five-section decision records with lifecycle (`proposed` / `implemented` / `rejected`) and a sha256-sealed frozen archive. Verified by `scripts/verify-agent-notes.mjs` and `scripts/archive-agent-notes.mjs`.
- `scripts/change-scope.mjs` — a stable JSON report of what a change touches, so agents select the smallest sufficient check set instead of reflexively running everything.
- `scripts/verify-translation-pairing.mjs` — bilingual documentation pairs (`foo.md` + `foo.zh.md` + `foo.i18n.yaml`) with git-blob-hash consistency; one-sided edits fail the gate.
- `.agents/skills/` — declarative skills (pre-push checks, code review, note archiving) whose descriptions are the trigger conditions.
- `scripts/verify-doc-budgets.mjs` — word-count ceilings that ratchet down, never up by accident.

## Quickstart

```sh
git clone <this-repo> my-project
cd my-project
rm -rf .git && git init
node scripts/gates.mjs --mode all   # everything green, zero install
sh scripts/install-hooks.sh         # pre-commit, pre-push, merge driver
```

Non-Node projects can run the same gates through a container:

```sh
docker run --rm -v "$PWD":/w -w /w node:20 node scripts/gates.mjs --mode all
```

## Adding your toolchain

`gates.json` declares each gate as a command slot. A Go project might add:

```json
{ "id": "test", "command": ["go", "test", "./..."] }
```

Any command that exits non-zero on failure is a gate. See [docs/architecture.md](docs/architecture.md).

## Origin

The mechanisms are distilled from the DeepSeek Harness repository, whose governing observation was: agents follow enforced gates far more reliably than prose conventions. See [AGENTS.md](AGENTS.md) for the standing orders.
