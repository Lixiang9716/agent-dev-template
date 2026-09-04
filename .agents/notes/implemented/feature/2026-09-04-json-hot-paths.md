# Agent Note: JSON output on the hot paths — run/audit-notes/verify-decisions/doctor (issue #119)

Status: implemented

## Problem

The delivery loop is operated by agents, and their single largest
recurring cost was parsing human-formatted output: every verification
chain was text-scraping — `gov run … | tail -1`, grep for counts,
pattern-matching truncated streams. `init --upgrade --json` (D26) and
`gov run --json` (D25) proved the pattern, but the other hot paths had
no machine mode, and `run --json` itself could not answer "which gates
were selected and why" — a path-scoped-out gate was simply absent from
the record, so an agent could not distinguish "scoped out" from
"deleted" from "never existed".

## Decision

- `gov run --json` records gain two fields (#119): `selected_by` (the
  mechanism that picked the set: `gate`, `mode:<name>`, `base:<ref>`,
  `every-gate`, `default-mode:<name>`, `all-enabled`) and `scoped_out`
  (bool). Every enabled gate now appears exactly once per run: gates
  the mechanism did not pick carry outcome `NOT_SELECTED`, gates
  excluded by `--base` path scoping carry `SCOPED_OUT` with
  `scoped_out: true`, and gates cancelled by `--fail-fast` carry
  `NOT_RUN`. Failure evidence stays full (D25/#109) in `detail`.
- `gov doctor --json` emits `{version, status, checks, problems}` with
  per-check `{name, state: ok|note|problem, detail}`; the checks were
  refactored from free-form prints into structured entries, and the
  embedded verify-decisions sub-run is stdout-captured so doctor's
  stdout carries exactly one JSON value (D26). The human format and
  its exact strings are unchanged and remain the default.
- `gov verify-decisions --json` emits `{source, decisions, violations,
  orphans, overdue, status}`; `gov audit-notes --json` emits `{notes,
  skills, decisions_source, findings: [{file, signal}], state}`.
  In both, the human report (findings included) moves to stderr.
- `gov trend` now skips non-run outcomes (`SCOPED_OUT`,
  `NOT_SELECTED`, `NOT_RUN`, `DISABLED`) — a gate the diff did not
  touch must not drag a 0ms p50 down.
- The flag registry (D28) pins the three new `--json` flags; the
  registry test and the flag-help surfaces agree.

## Alternatives considered

- **A single `gov --json` global mode** — rejected: the hot paths are
  invoked individually by scripts; a global flag changes every
  subcommand's contract at once and invites half-migrated outputs.
  Per-command `--json` keeps each surface independently pinnable.
- **Machine mode as the default** — rejected (#119 explicitly): the
  human format is the primary UX; JSON is opt-in and stdout-pure so
  both can coexist (JSON on stdout, human report on stderr, D26).
- **Leaving scoped-out gates absent, documented as "absence means out
  of scope"** — rejected: absence is ambiguous against NOT_SELECTED and
  misconfigured modes; an explicit `SCOPED_OUT` row is one honest line
  per gate.
- **Separate `--json` output schemas per command family** — rejected:
  all four follow one convention (exactly one JSON value on stdout,
  human report on stderr), so an agent learns it once.

## Consequences

- History records (`.gov/history/gates.jsonl`) now include one row per
  enabled gate per run; growth is linear in gate count, and trend's
  non-run skip keeps statistics unaffected.
- Consumers that asserted the exact four-key record schema must add the
  two new keys (the repo's own tests were updated in the same change).
