# Agent Note: `gov -C <path>` — target another worktree without cd

Status: implemented

## Problem

A supervisor agent orchestrating N worktrees had to cd into each subject
tree before every finish-chain step (probe status → verify → push), and
one path typo ran the gates against the WRONG tree with no warning —
the invocation looked perfectly valid (#121). The tools resolve the
repository by cwd (D21's design), so cwd bookkeeping was the only way
to steer them, and nothing in the output named which tree a run had
actually gated.

## Decision

`cli.main` consumes leading `-C <path>` / `--path <path>` flags before
subcommand dispatch: each path resolves against the previous one (git
`-C` semantics, chainable), a nonexistent directory fails loud with
exit 2, and after the chdir the resolved git work-tree root (exactly
what cd + root anchoring resolves to; plain cwd outside a work tree) is
announced on stderr as `gov: targeting <root> (via -C …)` — so every
command run this way carries the wrong-tree-visible header the issue
asked for, not just doctor. Because it is a chdir in front of the
existing dispatch, it applies uniformly to run/verify-*/doctor/decision
and everything else, without touching any tool module; D21's cwd-based
resolution is preserved, only the cwd is now set by value. Subcommands
with their own `--path` (verify-decisions, verify-rubric — a file
argument) are unaffected: the global flag must precede the command.

## Alternatives considered

- A `--project`-style flag per subcommand: init/uninstall already have
  one, but the root-relative tools have no such parameter, and adding
  it to ~15 argparse parsers multiplies surface for one concern.
- Resolving the root inside the flag handler and passing it down:
  rejected — it would fork every tool's path resolution away from
  D21's anchor_to_git_root and its announced-never-silent rule.
- Making doctor alone print the root: rejected — the issue's failure
  mode is a valid-looking invocation gating the wrong tree in ANY
  command; the header belongs where the targeting decision is made.

## Consequences

`--path` now means two things depending on position (global directory
before the command; file argument after verify-decisions/verify-rubric)
— documented in the cookbook entry and usage text. Documented in
docs/cookbook.md + .zh.md (pairing re-confirmed).
