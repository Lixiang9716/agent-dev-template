# Governance architecture

English | [中文](architecture.zh.md)

The template separates two planes. The governance plane — gates, notes, pairing, scope — is language-agnostic machinery that operates on git, Markdown, and JSON. The product plane is your code in any language; it connects only through command slots in `gates.json`.

## The gate scheduler

`scripts/gates.mjs` reads `gates.json` and runs one mode (`--mode all|quick|docs`). Gates form a DAG through `needs`: a gate starts once every dependency passed; a failed dependency marks dependents skipped with the cause instead of running them. The whole config is validated before any child process starts — duplicate ids, unknown needs, and cycles abort with the offending names. `allowFailure: true` keeps a gate's failure out of the blocking set for observational lanes.

Concurrency defaults to the CPU count and can be capped with `GATE_CONCURRENCY`. Output is captured per gate: passing gates stay silent (set `GATE_VERBOSE=1` to see them), failing gates print command, outcome, and output.

## Slots, not frameworks

A gate is any command array that exits non-zero on failure. Language-specific work — tests, coverage, typecheck, lint — enters as slots you declare once and CI runs forever. The governance scripts self-host this pattern: their own tests (`node --test scripts/`) are the `self-test` gate.

## Knowledge planes

Agent Notes carry decisions (`proposed` / `implemented` / `rejected`, then a sealed `archived/`); the verifier enforces the five-section format and the archive seals content with sha256. Bilingual pairs carry user-facing documentation; the pairing verifier pins both sides with git blob hashes. Postmortems carry failures; their guardrails become gates. [docs/tiers.md](tiers.md) maps each fact to its one home.
