# Agent Note: defaultMode and enabled:false — a default run set and parking without deletion

Status: implemented

## Problem

`gov run` without `--mode` ran every gate; `modes.all` was only an explicitly
selectable name, not a default set. An adopter who removed `pairing` from
`modes.all` saw it run anyway (3 gates: 1 fail). The only way to turn a gate
off was to delete its definition — losing the configuration history and the
intent to re-enable it later. Disabling a gate and reverting a mode were the
same destructive edit.

## Decision

`gates.json` gains a top-level `defaultMode` (must name a known mode, else
exit 2) and gates gain `enabled` (bool, default true). Without `--mode`, the
default mode runs when configured (the injected template ships
`"defaultMode": "all"`); with neither, every enabled gate runs — the
historical behavior. `enabled: false` excludes a gate from every selection and
prints a `DISABLED <id>` line, so off is visible, never silent. A mode may
still list a disabled gate (filtered); listing an unknown gate remains a
config error.

## Alternatives considered

- Special-case a mode named `all` as the default — rejected: an implicit magic
  name contradicts fail-loud; users would discover it only by surprise.
- `enabled: false` alone — rejected: it cannot make a mode set the default
  run, so editing `modes.all` would still not change `gov run`.
- Erroring when a mode references a disabled gate — rejected: disabling would
  then require edits in every mode listing, recreating the delete-the-definition
  pressure this change exists to remove.

## Consequences

Turning a gate off is one edit and one `DISABLED` line of noise per run;
re-enabling is one edit back. Configs without `defaultMode` behave exactly as
before, so the schema addition is backward compatible.
