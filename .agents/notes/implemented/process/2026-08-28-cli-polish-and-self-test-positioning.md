# Agent Note: CLI polish round — usage progs, PyPI links, and where self-test belongs

Status: implemented

## Problem

Three small gaps reported by an adopter: `gov run --help` printed
`usage: gov [-h]` (argparse defaulted prog to the executable, so no
subcommand name appeared — same for verify-pairing and change-scope);
`pip show govrail` listed no homepage or repository, so finding the repo
meant asking a human; and the self-test gate — the govrail tools' own
regression suite — ran identically in every project's every run, costing
seconds to re-prove the tool instead of checking the project.

## Decision

Every argparse parser sets `prog` explicitly (`gov run`,
`gov verify-pairing`, `gov change-scope`, `gov verify-note-presence`), so
usage lines name the subcommand. pyproject gains `[project.urls]` —
Homepage/Repository, Issues, Changelog — pointing at the GitHub repository,
so PyPI metadata answers "where does this live". The injected template moves
self-test out of the default `all` mode into a dedicated `governance` mode:
the tool's regression belongs to the tool's own CI (this repository runs it
on every push), not to every adopter's every run; it stays one `--mode
governance` away for anyone who wants it locally.

## Alternatives considered

- Keep self-test in every default run — rejected: re-proving the shipped
  tool in N projects is duplicated work with no new information; a vacuous
  repetition is the seed of `--no-verify` habits.
- Delete self-test from the template entirely — rejected: rule 6 (verify the
  world) still applies to the governance plane itself, and `governance` mode
  keeps it reachable for contributors to any project.
- A dynamic prog derived from argv — rejected: explicit strings are simpler
  and stable across `gov X` and `python -m gov X` invocations.

## Consequences

User-project default runs get faster and less repetitive; govrail's own
CI keeps running self-test on every push (its `all` mode still lists it).
Anyone forking the tools gets the regression suite via
`gov run --mode governance`.

> Partially superseded by `2026-09-01-gate-reachability.md` (D24): the
> template's `all` mode now includes self-test again — radiant's audit
> showed the governance-only parking left it with no automatic execution
> path. The `governance` mode remains as a self-test-only shortcut.
