# Governance architecture

English | [中文](architecture.zh.md)

The template separates two planes. The governance plane — gates, notes, pairing, scope — is language-agnostic machinery that operates on git, Markdown, and JSON. The product plane is your code in any language; it connects only through command slots in `gates.json`.

Every governance script ships as two equivalent ports: a bash twin (`scripts/*.sh`, bash >= 5) and a PowerShell twin (`scripts/*.ps1`, pwsh 7+). Both read the same `gates.json` and produce the same vocabulary; CI runs both. Twin pairs confirm together: `scripts/script-pairs.json` pins each side's blob hash, and a drifted pair fails the gate until a fresh `--write` re-confirms both sides in the same change — the re-confirm is the explicit "the twin was considered" acknowledgment. A pair may declare a behavioral probe that runs both sides' sibling test suites and compares normalized output; the probe is availability-aware — it runs when the cross interpreter is on PATH and is loudly skipped when it is not, so a bash-only or pwsh-only host passes every local gate, while CI forces the probe on every matrix leg (`GATES_FORCE_PROBE=1`; its closed set is {unset, 1} — other values fail loud). A gate slot is either a plain command array (identical on both shells) or per-shell variants, and a variant object must name every shell in the closed set — a missing variant aborts rather than silently skipping on that platform.

## The gate scheduler

`scripts/gates.sh --mode <name>` (pwsh: `scripts/gates.ps1 -Mode <name>`) reads `gates.json` and runs one mode (`all|quick|docs`). Gates form a DAG through `needs`: a gate starts once every dependency passed; a failed dependency marks dependents skipped with the cause instead of running them. The whole config is checked before any child process starts — duplicate ids, unknown needs, and cycles abort with the offending names. `allowFailure: true` keeps a gate's failure out of the blocking set for observational lanes.

Concurrency defaults to the CPU count and can be capped with `GATE_CONCURRENCY`. Output is captured per gate: passing gates stay silent (set `GATE_VERBOSE=1` to see them) except loud skip lines, which surface even on a passing gate — a skipped probe never looks like full coverage; failing gates print command, outcome, and output.

## Slots, not frameworks

A gate is any command array that exits non-zero on failure. Language-specific work — tests, coverage, typecheck, lint — enters as slots you declare once and CI runs forever. The governance scripts self-host this pattern: their own test suites (`scripts/self-test.sh`, `scripts/self-test.ps1`) are the `self-test` gate, one suite per port.

## Knowledge planes

Agent Notes carry decisions (`proposed` / `implemented` / `rejected`, then a sealed `archived/`); the verifier enforces the five-section format and the archive seals content with sha256. Bilingual pairs carry user-facing documentation; the pairing verifier pins both sides with git blob hashes. Postmortems carry failures; their guardrails become gates. [docs/tiers.md](tiers.md) maps each fact to its one home.

## Growing the plane

The governance plane is a floor, not a ceiling: derived projects extend it with their own history, and growth is event-driven, never inspiration-driven.

| Trigger | Landing |
|---|---|
| A defect class ships and is expensive to rediscover | `docs/postmortem/` entry; its guardrail distills into a gate |
| A convention is enforced by hand a third time | `.agents/skills/` entry whose description is the trigger |
| A prose promise becomes mechanically checkable | new gate in `gates.json` with a rejection test (rule 3) |
| A non-trivial decision is made | Agent Note in the same PR (rule 2) |
| A new fact needs a home | pick its tier first ([tiers.md](tiers.md)), land it once |

Closed sets (note classes, lifecycles) grow by deliberate acts that update the verifier and the notes README together. Word budgets bound the growth: adding a home means feeding it a ceiling.

## Checkpoint discipline

Long-running work keeps a numbered, append-only checkpoint record. Every checkpoint entry carries a verifier (who checked it), a coverage scope (what it covers), and a goal-link (which Goal or Core it serves). Numbering is sequential 1..N and never edited or renumbered; recovery resumes from the highest-numbered entry with an intact chain, and an entry whose chain is broken is not a restore point.
