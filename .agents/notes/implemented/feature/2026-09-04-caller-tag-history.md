# Agent Note: caller tagging in .gov/history — multi-agent attribution

Status: implemented

## Problem

Multi-agent repositories (radiant's M2/M3: 6+ distinct subagent sessions
plus a supervisor, all running gates in parallel worktrees) share one
`.gov/history/gates.jsonl`, and every record in it is anonymous. `gov
trend` can answer "did tests get slower?" but not "which caller's runs
keep tripping pairing?" or "do subagent runs have systematically
different durations than the supervisor's?" — the attribution question is
unanswerable from the data the plane already collects (issue #120).

## Decision

Gate runs accept an **optional caller tag**: `gov run --tag <name>`, with
`$GOV_CALLER` as the fallback (the flag wins; whitespace-only counts as
absent). The tag is recorded into gates.jsonl as caller-supplied free
text under a `caller` key — privacy-light by design: no git identity, no
hostname, nothing the caller did not type. Absent tag = no `caller` key:
the record shape, byte for byte, is the pre-#120 anonymous line, so
untagged runs and every existing reader behave exactly as before.
`gov trend --by-tag` groups the window by tag (order of first
appearance; untagged runs group under `(untagged)`) and runs the same
early/late p50 comparison **inside each group** — the halfway split is
per-group, so a tag concentrated in time still compares; `--base` splits
every group at the same commit date. The flag registry
(`gov/audit_notes.py`) moves with both flags, pinned by
tests/test_flag_registry.py (issue #101's lesson).

## Alternatives considered

- Deriving the caller from git config (user.name) — worktrees share one
  identity, so every subagent session would tag identically; useless for
  attribution and silently wrong rather than absent.
- Recording hostname/PID automatically — attribution without consent;
  the issue explicitly asks for privacy-light, caller-supplied text.
- A separate per-caller history file — fragments the append-only ledger
  D28/D29 chose and breaks `--last` windowing across callers.
- Making the tag required — changes today's behavior for every existing
  user; the acceptance criterion is "absent = today".
