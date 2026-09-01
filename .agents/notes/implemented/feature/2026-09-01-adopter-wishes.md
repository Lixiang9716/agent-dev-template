# Agent Note: the adopter wishes — local rejection cases, --json, parallel self-test, surface mapping

Status: implemented

## Problem

Four wishes from the first adopter (radiant), ranked by value. The
strongest: rule 6 demands every governance gate ship a rejection case, but
`gov self-test` ran only govrail's own — an adopter writing a custom gate
(source-limits) had nowhere to wire its rejection proof except pytest:
another runtime, another report. The plane's own axiom — a promise without
an execution path does not exist — applied to itself. Then: gate results
were human-line text only, so machines (trend charts, duration
regressions, report aggregation) had to parse stdout; self-test in the
default mode (D24) made its serial case startup a linear CI tax that
would tempt adopters to park it again; and change-scope's surface
classification was hardcoded, filing an `eval/` experiment rig under
"code" and suggesting the full set.

## Decision

All four shipped (D25). `.gov/rejections/` is rule 6's last mile: every
executable file there runs as part of `gov self-test` with the repository
root as cwd — exit 0 means the rejection proof holds, non-zero fails the
self-test naming the file and its first output line; README* files are
skipped; non-executables are named; `gov init` injects the convention's
README, and the report counts `tools` and `project` separately with
`--scope tools|project` to run one family. `gov run --json` puts exactly
one JSON array on stdout — `{gate, outcome, blocking, duration_ms,
detail}` per gate in config order, DISABLED included — while the human
report moves to stderr; exit codes and every selector stay orthogonal.
self-test runs its cases on a 4-worker pool (report order stays
deterministic: CASES order then sorted paths; all failures are reported,
not just the first). `.gov/surfaces.json` maps path globs to a surface
name and the gates that cover them; a matched file reports that surface
and its gates replace the fallback suggestion (all-matched means exactly
the configured gates); malformed config exits 2; absent config keeps the
built-in classification.

## Alternatives considered

- Rejection cases in pytest — rejected: another runtime and report; the
  proof of a gate belongs with the gate runner.
- A summary object inside --json — rejected: the array is the record;
  aggregation is the consumer's one line of jq.
- Scoping instead of parallelism — rejected: scope answers "which",
  concurrency answers "how long"; the full-matrix tax was the complaint.
- Fully configurable surfaces — rejected: the no-config default is the
  newcomer's first impression; hardcoded defaults with optional override
  is how adoption stays progressive.

## Consequences

A project's custom gates can now carry mechanically-wired rejection
proofs from day one, counted next to the tools' own. The meta-case for
this feature taught a lesson recorded in its code: a self-test case that
spawns the self-test must scope itself to `--scope project` or it
recurses — the case comments why. --json makes gate health a time series
(radiant's rig is the first consumer), and surfaces.json lets an eval/
directory stop masquerading as runtime code.
