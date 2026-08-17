# Governance architecture

English | [中文](architecture.zh.md)

The template separates two planes. The governance plane — gates, notes, pairing, scope — is language-agnostic machinery that operates on git, Markdown, and JSON. The product plane is your code in any language; it connects only through command slots in `gates.json`.

Every governance script ships as two equivalent ports: a bash twin (`scripts/*.sh`, bash >= 5) and a PowerShell twin (`scripts/*.ps1`, pwsh 7+). Both read the same `gates.json` and produce the same vocabulary; CI runs both. A gate slot is either a plain command array (identical on both shells) or per-shell variants, and a variant object must name every shell in the closed set — a missing variant aborts rather than silently skipping on that platform.

## The gate scheduler

`scripts/gates.sh --mode <name>` (pwsh: `scripts/gates.ps1 -Mode <name>`) reads `gates.json` and runs one mode (`all|quick|docs`). Gates form a DAG through `needs`: a gate starts once every dependency passed; a failed dependency marks dependents skipped with the cause instead of running them. The whole config is validated before any child process starts — duplicate ids, unknown needs, and cycles abort with the offending names. `allowFailure: true` keeps a gate's failure out of the blocking set for observational lanes.

Concurrency defaults to the CPU count and can be capped with `GATE_CONCURRENCY`. Output is captured per gate: passing gates stay silent (set `GATE_VERBOSE=1` to see them), failing gates print command, outcome, and output.

## Slots, not frameworks

A gate is any command array that exits non-zero on failure. Language-specific work — tests, coverage, typecheck, lint — enters as slots you declare once and CI runs forever. The governance scripts self-host this pattern: their own test suites (`scripts/self-test.sh`, `scripts/self-test.ps1`) are the `self-test` gate, one suite per port.

## Knowledge planes

Agent Notes carry decisions (`proposed` / `implemented` / `rejected`, then a sealed `archived/`); the verifier enforces the five-section format and the archive seals content with sha256. Bilingual pairs carry user-facing documentation; the pairing verifier pins both sides with git blob hashes. Postmortems carry failures; their guardrails become gates. [docs/tiers.md](tiers.md) maps each fact to its one home.
