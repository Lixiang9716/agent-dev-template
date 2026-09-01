# Agent Note: gate reachability — one parking mechanism, and it is loud

Status: implemented

## Problem

The first real adopter audit (radiant, public, #5) found that its
governance self-test — 26 rejection cases — had never executed on any
automatic path: the template parked self-test in a `governance` mode that
nothing ran, while the injected CI and the pre-push hook both execute a
bare `gov run` (= defaultMode = all). Rule 1 says CI owns the full
matrix; the shipped config contradicted it. The structural root: gates.json
had grown two parking mechanisms — `"enabled": false` (loud: a DISABLED
line) and mode omission (silent: never runs, never reports, invisible).
The silent one was never documented as parking, yet the template itself
used it — the mirror image of a vacuous pass: a gate that never runs
never even qualifies to fail. Related (N4): `gov run --gate <parked>`
exited 0, green over an impossible request.

## Decision

Parking is now one mechanism and it is loud (D24). load_config rejects
any enabled gate that belongs to no mode (when modes are defined), naming
the gate and the one sanctioned parking mechanism; gates in non-default
modes remain legal (the governance shortcut survives). The template's
`all` mode includes self-test again — partially superseding the 0.3.0
positioning, with evidence: the template CI installs an unpinned govrail,
so self-test is the adopter-side smoke test of the tool itself; radiant
paid 10s → 17s of CI, which is what a full matrix costs.
`gov run --every-gate` gives the full matrix an explicit landing
(ignores modes and defaultMode, runs every enabled gate), and
`--gate <disabled>` now exits 2 — explicitly naming a parked gate is
operator error, not a silent green. Acceptance testing also surfaced a
neighbor defect: note-presence exited 2 on a zero-commit repository
(no HEAD to diff); it now treats the untracked listing as the whole
change there, keeping D13's first-run-green promise.

## Alternatives considered

- Fix only the template — rejected: the silent parking mechanism would
  keep growing never-runs gates in adopter configs.
- Reachability = membership in defaultMode — rejected: it would outlaw
  the governance shortcut; reachability means "belongs to some mode".
- CI runs two commands (`gov run && gov run --mode governance`) —
  rejected: a one-line template change is static, simpler, and
  self-describing.

## Consequences

Every enabled gate is now guaranteed an execution path someone chose;
parking is visible by construction, and a parked gate answers back when
named. Fresh installs run the tools' own regression suite from their
first CI push — adopters watching an unpinned dependency get a loud,
local diagnosis of a tool regression instead of a confusing gate failure.
