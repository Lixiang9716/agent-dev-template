# Agent Note: Python single-implementation governance plane

Status: implemented

## Problem

The template shipped every governance script twice (bash + PowerShell) and
bundled five-section notes, four lifecycle states, vocabulary and budget gates,
checkpoint discipline, and an adoption ceremony. The result was too heavy to
adopt into an existing project: two runtimes to maintain and too many
mechanisms to calibrate before the first commit.

## Decision

The governance plane is now a Python 3 single implementation, locked in
`docs/decisions.md` (D0–D10):

- **Gates**: a DAG runner (`gov/gates.py`) over `gates.json` — argv commands,
  `needs`, `modes`, `concurrency`, `timeoutMs`, `allowFailure`; five outcomes
  PASS/FAIL/TIMEOUT/MISSING/SKIP; exit 0/1/2; config errors (duplicate ids,
  unknown needs, cycles) fail loud before any child runs.
- **Notes**: three required sections (Problem / Decision / Alternatives),
  Consequences optional; lifecycle reduced to `implemented` + `archived`
  (rejected and proposed removed).
- **Delivery**: `gov init` / `gov uninstall` — injects `.gov/rules.md`, creates
  `gates.json` and the notes README only when missing, appends one reference
  line to AGENTS.md, and reverses exactly via `.gov/manifest.json`. Idempotent
  and non-invasive.
- **Bilingual pairing** stays for the external-presentation docs (README,
  AGENTS, docs), reimplemented as `gov verify-pairing`.
- **Rejection cases**: each governance gate ships one (`gov self-test`), so no
  gate is a vacuous always-passes script.

## Alternatives considered

- **Keep the bash/PowerShell twins** — one logic in two dialects doubles
  maintenance, and the "zero install" claim was half-true anyway (macOS ships
  bash 3.2, Windows ships no bash). Python 3 is one well-understood runtime for
  the developer audience.
- **A read-receipt line to prove the agent read the rules** — checks a process
  side effect, not the outcome, and can be gamed or misfire. The
  failure-message-teaches loop (a failing gate points back at `.gov/rules.md`)
  is more robust: it forces reading by making "not reading" fail, without
  introducing mutable state.
