# Agent Note: CLI help/version must be side-effect free

Status: implemented

## Problem

`gov <cmd> --help` / `--version` on the non-forwarding commands (init,
uninstall, self-test, verify-notes, archive-notes) were silently ignored and
executed the command anyway: `gov init --help` initialized the current
directory (writing `.gov/`, `gates.json`, `AGENTS.md`), and
`gov archive-notes --help` rewrote the archive manifest. `--help`/`--version`
are meta commands and must never have a side effect; silently dropping an
unknown flag also violates fail-loud.

## Decision

`cli.main` intercepts `-h/--help/help` and `-v/--version/version` both at the
top level and inside each non-forwarding subcommand's args, returning before
any action runs. `init`/`uninstall` now parse only `--project <dir>` and reject
any other argument with exit 2 instead of silently ignoring it. A regression
case (`test_cli_init_help_no_side_effect`) proves `gov init --help` creates
nothing.

## Alternatives considered

- **Forward every subcommand through argparse** — heavier than warranted for
  eight small subcommands; the manual dispatch plus explicit help/version
  interception stays simpler.
