# agent-dev-template

English | [中文](README.zh.md)

A language-agnostic template repository for agent-driven development: the governance plane that lets coding agents work fast in parallel while machines, not vigilance, hold the quality line.

The template ships the governance plane only. It never prescribes your programming language, test framework, or package manager — your toolchain plugs in as command slots in `gates.json`. Every script ships as two equivalent ports, bash (`scripts/*.sh`, bash >= 5) and PowerShell (`scripts/*.ps1`, pwsh 7+): run whichever your host already has; no extra runtime, no install step.

## What is inside

- `gates.json` + `scripts/gates.sh` / `scripts/gates.ps1` — a declarative DAG gate scheduler: dependency-ordered parallel execution, failure propagation, and fail-loud validation before any child process starts. A command slot is a plain array (same on both shells) or per-shell variants `{ "sh": [...], "pwsh": [...] }`.
- `.agents/notes/` — the Agent Notes system: five-section decision records with lifecycle (`proposed` / `implemented` / `rejected`) and a sha256-sealed frozen archive. Verified by `scripts/verify-agent-notes.*` and `scripts/archive-agent-notes.*`.
- `scripts/change-scope.*` — a stable JSON report of what a change touches, so agents select the smallest sufficient check set instead of reflexively running everything.
- `scripts/verify-translation-pairing.*` — bilingual documentation pairs (`foo.md` + `foo.zh.md` + `foo.i18n.yaml`) with git-blob-hash consistency; one-sided edits fail the gate.
- `.agents/skills/` — declarative skills (pre-push checks, code review, note archiving) whose descriptions are the trigger conditions.
- `scripts/verify-doc-budgets.*` — word-count ceilings that ratchet down, never up by accident.

## Quickstart

```sh
git clone <this-repo> my-project
cd my-project
rm -rf .git && git init
bash scripts/gates.sh --mode all    # everything green, zero install
sh scripts/install-hooks.sh         # pre-commit, pre-push, merge driver
```

On a PowerShell host the same aggregate runs through the twin:

```sh
pwsh -File scripts/gates.ps1 -Mode all
```

Hosts with neither shell run the same gates through a container:

```sh
docker run --rm -v "$PWD":/w -w /w bash:5 bash scripts/gates.sh --mode all
docker run --rm -v "$PWD":/w -w /w mcr.microsoft.com/powershell pwsh -File scripts/gates.ps1 -Mode all
```

## Adding your toolchain

`gates.json` declares each gate as a command slot. A Go project might add:

```json
{ "id": "test", "command": ["go", "test", "./..."] }
```

Any command that exits non-zero on failure is a gate; a plain array runs on both shells. See [docs/architecture.md](docs/architecture.md).

## Origin

The mechanisms are distilled from the DeepSeek Harness repository, whose governing observation was: agents follow enforced gates far more reliably than prose conventions. See [AGENTS.md](AGENTS.md) for the standing orders.
