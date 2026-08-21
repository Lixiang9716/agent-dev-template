# agent-dev-template

English | [中文](README.zh.md)

A language-agnostic template repository for agent-driven development: the governance plane that lets coding agents work fast in parallel while machines, not vigilance, hold the quality line.

The template ships the governance plane only. It never prescribes your programming language, test framework, or package manager — your toolchain plugs in as command slots in `gates.json`. Every script ships as two equivalent ports, bash (`scripts/*.sh`, compatible with macOS's bash 3.2) and PowerShell (`scripts/*.ps1`, pwsh 7+): run whichever your host already has; no extra runtime, no install step. Pair probes run when the twin interpreter exists, skip loudly otherwise; CI forces them.

## The agent development mode

Agents follow enforced gates far more reliably than prose conventions — the observation this template is built on. The mode is a loop:

1. **Work freely, verify mechanically.** Every promise that a command can check is a gate in `gates.json`; nothing waits on human vigilance.
2. **Record the why.** Every non-trivial change carries an Agent Note in the same PR: the decision, what it beat, the consequences — shared memory that keeps settled decisions settled.
3. **Check only what changed.** `change-scope` reports the touched surface; the smallest sufficient gate set follows from it. CI owns exhaustiveness.
4. **Docs pair or fail.** Bilingual pairs are pinned by git blob hashes; one-sided edits cannot hide.

Standing orders live in [AGENTS.md](AGENTS.md); the machinery in [docs/architecture.md](docs/architecture.md).

## Installation

Derive a fresh repository from the GitHub template — one command, clean history:

```sh
gh repo create my-app --template Lixiang9716/agent-dev-template
```

Or the explicit clone:

```sh
git clone https://github.com/Lixiang9716/agent-dev-template my-project
cd my-project
rm -rf .git && git init
bash scripts/gates.sh --mode all    # everything green, zero install
sh scripts/install-hooks.sh         # pre-commit, pre-push, merge driver
```

PowerShell hosts run the twin:

```sh
pwsh -File scripts/gates.ps1 -Mode all
```

A host with neither shell installs pwsh 7 — one package, no container:

```sh
winget install --id Microsoft.PowerShell   # Windows
brew install powershell                    # macOS
```

## First day

The day-one route: [docs/adoption.md](docs/adoption.md) — what the plane gives you, what to calibrate, and the steps to your first pull request.

## Adding your toolchain

`gates.json` declares each gate as a command slot. A Go project might add:

```json
{ "id": "test", "command": ["go", "test", "./..."] }
```

Any command that exits non-zero on failure is a gate; a plain array runs on both shells. See [docs/architecture.md](docs/architecture.md).

## What is inside

- `gates.json` + `scripts/gates.*` — the declarative DAG gate scheduler: dependency-ordered parallel execution, failure propagation, fail-loud validation before any child starts.
- `.agents/notes/` — Agent Notes: five-section decision records with lifecycle and a sha256-sealed frozen archive.
- `scripts/change-scope.*` — a stable JSON report of what a change touches.
- `scripts/verify-translation-pairing.*` — bilingual pairs pinned by git blob hashes.
- `.agents/skills/` — declarative skills (pre-push checks, code review, note archiving).
- `scripts/verify-doc-budgets.*` — word-count ceilings that ratchet down.

## Origin

The mechanisms are distilled from the DeepSeek Harness repository, whose plugin-everything architecture and gates-over-prose axiom shaped this template. Kept: the governance plane. Left to you: the product plane.
