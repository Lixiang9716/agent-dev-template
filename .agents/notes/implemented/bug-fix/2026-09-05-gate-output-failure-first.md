# Agent Note: failure-first gate output — failed evidence is never clipped (issue #109)

Status: implemented

## Problem

`gov run` truncated a FAILing gate's output at capture time: `_run_one`
kept only the last 2000 characters (`_tail`), so by the time the report
was rendered the failing gate's evidence — the "why" — was already gone.
The reporter debugged pre-push failures where the failure line named the
check (`self-test: rts_without_blocking`) but its output lived in the
truncated region, forcing re-runs with different tails or single-gate
reruns just to see the reason. Passing gates already had a display-side
budget (tail-3, D20); the defect was applying a capture-side budget to
the one block whose completeness the user depends on. Additionally, the
rerun hint existed only as a generic trailer line (`rerun a single gate:
gov run --gate <id>`), not in the per-gate failure line where the eye
lands.

## Decision

- `_run_one` returns the FAILing gate's **full** stdout+stderr; the
  `_tail` helper is deleted. Full evidence flows to the human report
  and to the JSON run record (D25) alike.
- The summary failure line itself carries the per-gate rerun command:
  `boom: boom (rerun: gov run --gate boom)`. The generic trailer line
  is removed — the per-gate form names the exact gate.
- Passing gates are unchanged: tail-3 with an omission note (D20).
  Advisory allowFailure failures follow the same full-output path as
  blocking ones.

## Alternatives considered

- **Raise the tail limit (e.g. 10k chars)** — rejected: any budget
  re-creates the bug for gates with longer evidence; the truncation
  point is a guess about what matters, and the reporter's case proves
  the guess fails.
- **Render-time de-truncation (keep clipped detail, re-capture on
  failure)** — rejected: requires re-running the gate, which is
  non-deterministic and slower precisely when the user needs speed.
- **Keep the generic trailer alongside per-gate hints** — rejected as
  redundancy; the per-gate line is strictly more specific.

## Consequences

- Run records (`--record` / JSON mode) grow for failing gates — the
  history file is local/gitignored and per-run, so growth is bounded by
  failure frequency, and full evidence in records is a feature for
  postmortems, not a cost.
- A pathological gate emitting megabytes on failure will flood the
  terminal; that is accepted (issue #109 explicitly prefers full over
  truncated) and the gate's own output hygiene is that gate's problem.
