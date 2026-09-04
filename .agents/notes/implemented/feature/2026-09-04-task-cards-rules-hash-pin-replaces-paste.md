# Agent Note: Task cards: rules@hash pin replaces pasted governance prose

Status: implemented

Related: D42, issue #125

## Problem

Orchestrators hand subagents task briefs that re-embed the repo's governance
rules by hand — explicit-path staging, never `git add -A`, the gate list,
decision-row format, bilingual-pair rule — about fifteen lines of identical
boilerplate per brief. The prose drifts (one governance adoption — a new gate,
new decision tooling — silently outdates every template still being pasted;
issue #125 reports briefs diverging within one session) and nothing verifies
that the asserted discipline was ever applied: the orchestrator vouches in
prose, the plane has no artifact to check.

## Decision

`gov task` ships a task-card artifact (`gov/task.py`, subcommands
`new/check/close/list`). `gov task new "Title" --check "criterion"` writes
`.gov/tasks/T-0001-<slug>.json` pinning the CURRENT rule set by content hash —
`.gov/rules.md` plus `gates.json`, the note conventions included (they live
inside rules.md, so there is exactly one source to hash). The hash is sha256
over the sorted `path:sha256` lines, displayed as a 12-char prefix; a brief
carries the one line `obey rules@<hash>` instead of the boilerplate, and
`--rules <prefix>` makes the orchestrator fail loud if the rules moved since
its pin was taken.

`gov task check` recomputes the hash: an open card pinning a pre-adoption
hash is named STALE and fails the command. It is a gate in `gates.json` with
`paths: [".gov/tasks/**"]` — rule 1's smallest sufficient set: projects with
no cards never run it, and a PR touching cards proves its own freshness.
Done cards are re-verified: the receipt must be an all-PASS run against the
same hash the card pins.

`gov task close T-0001` runs the gate DAG now (`gov run --json`), and only an
all-green run writes the receipt (`ts`, `mode`, rules hash, per-gate outcomes)
and marks the card done — the completion receipt links the subagent's green
run to the card. A red run changes nothing on the card (the run itself lands
in `.gov/history/gates.jsonl`); closing against a stale pin is refused — the
card must be re-briefed against the adopted rules first. Rejection proofs:
two tools-family self-test cases (stale pin goes red; non-green receipt goes
red).

## Alternatives considered

**Hash the note conventions from a separate file.** This repo's note
conventions live inside `.gov/rules.md` (rules 2–4); a second file would be a
second source of truth that drifts from the one rules.md already carries.

**Put `gov task check` in the default mode without paths.** Projects with no
cards would run a guaranteed-vacuous check on every push — against rule 1's
smallest sufficient set. Scoping it to `.gov/tasks/**` keeps the promise
mechanical where it exists and absent where it does not.

**Mark the card done with a red receipt.** "Done yet red" is a lie in the
status field; the card closes only on green, and red-run evidence already
lives in the gate history.

**Store a link to a history line instead of the outcomes.** History is local
and prunable; a receipt must carry its own re-verifiable evidence — check
re-validates the outcomes themselves rather than trusting a pointer.
