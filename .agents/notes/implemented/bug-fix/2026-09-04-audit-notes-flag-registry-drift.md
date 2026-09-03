# Agent Note: audit-notes flag registry drift — real flags reported as dead commands (issue #101)

Status: implemented

## Problem

An adopter (radiant, gov 0.14.0) ran `gov audit-notes` and got `unknown
flag --adopt on gov init` against a note documenting a *successful*
`gov init --adopt .gov/hooks/pre-push` run — the exact inversion of what
the audit exists to catch, and a standing false signal in every run since
0.13.0 shipped `--adopt`. Root cause: D28's flag registry is a static
table, and the test pin that decision promised ("静态表+用例钉住") was
never written for the flag side — only typo *detection* was pinned, never
registry↔CLI *equality`. The table described 0.12-era init and lagged in
both directions: missing real flags (`init --adopt/--preview/--json`,
`review --grade`, and the `note`/`whatsnew` commands entirely → silent
skip) while keeping a dead one (`run --record`, removed by D29's
default-on recording). govrail's own audit carried three such false
signals (`--adopt`, `--json`, `--grade`). The reporter's guess — that the
lint checks the terse `--help` usage line — was wrong about the mechanism
but right about the symptom's enabler: `gov init --help` printed only the
global one-line summary, hiding the real surface from humans too.

## Decision

The registry is corrected to the full 0.14 surface (init +`--json`
`--adopt` `--preview`, run −`--record` +`--no-record`, review +`--grade`,
trend +`--gate` `--base`, and entries for the previously uncovered
`note`/`whatsnew`/`doctor`/`verify-doc-sync`). D28's "pinned by tests"
promise is now delivered as `tests/test_flag_registry.py`: for every
command, `gov <cmd> --help` must list exactly the registered flags — a
listed-but-unregistered flag means false signals on working commands, an
unregistered-but-listed... the reverse means silent typo misses. Runtime
holds rule 5 too: if the registry and `cli._COMMANDS` disagree,
audit-notes names the mismatch on stderr and exits 2 instead of silently
skipping flag checks. The hand-parsed commands (`init`/`uninstall`/
`verify-notes`, which have no argparse to print options) now declare
their flags as data in `cli.COMMAND_FLAGS`, and `gov init --help` renders
that table — the terse `_COMMANDS` line stays a description, never the
machine-checked surface. A self-test rejection case locks the inversion
fix from both sides: `--adopt`/`--preview` in a note produce no signal,
`--nonexistent` still does. The pin immediately paid for itself: it
caught the dead `--record` entry, and the drifted wish-9–14 note that
cited it was brought current (notes are kept current with shipped facts;
only archived notes are frozen, rule 4).

## Alternatives considered

- Deriving the registry from argparse at run time — rejected (D28
  stands): parsers are built inside `main()`; audit-time introspection is
  the cost D28 already weighed. The pin tests probe the *shipped*
  `--help` surface instead — introspection once, in CI, not per audit.
- Suppressing unknown-flag signals on commands with unlisted flags —
  rejected: that is rule-5's "silently skip" wearing a bandage; it would
  blind the check for every command that ever gains a flag.
- Single-sourcing init's flags by importing `cli.COMMAND_FLAGS` into
  audit_notes — rejected: audit_notes must run by path (self-test executes
  files directly), where the package import may not exist; one literal
  table plus an equality pin keeps both worlds honest and fails loudly
  when they drift.

## Consequences

`gov init --adopt <file>`, `--adopt <file> --preview`, `run --no-record`,
`review --grade`, `note new --class`, `whatsnew --since` in notes and
skills no longer read as dead commands, while `init --nonexistent` still
does. Adding a flag now has a mechanical second step that cannot be
forgotten silently: update the command's help and `audit_notes.FLAGS`, or
`test_flag_registry` (and, for new commands, audit-notes itself, exit 2)
says so by name. `gov init --help` finally answers the question the
issue's reporter asked of it.
