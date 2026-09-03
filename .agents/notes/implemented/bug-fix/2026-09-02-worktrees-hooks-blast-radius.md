# Agent Note: worktrees, hook context, blast radius, and the vacuous-green family

Status: implemented

## Problem

Nine findings from the third adversarial audit. doctor mistook every
linked worktree for "not a git repository" (.git is a file there) and
still said "environment sound" with its hook checks silently lost. A
bare verify-pairing --write rewrote every sidecar, granting green pairs
a confirmation nobody made (timestamps and commit fields they never
earned). The decisions plane hard-coded docs/decisions.md: a project
with its table in DESIGN.md got a vacuous green while its notes
referenced D1–D26. The coverage ledger nagged "write one" for a case
that had just run and passed. doctor ignored a manifest reading 0.6.5
against a 0.12.0 package. The pre-push hook deterministically failed
self-test while manual runs passed — reproduced locally: leaked
GIT_DIR/GIT_WORK_TREE made root anchoring resolve scratch repositories
to the host repo. A scoped-out gate's zero-file output was
typographically identical to a real scan. The hook always ran the full
default mode (docs-only pushes reran the whole suite; concurrent pushes
crushed each other). And .gov/history fragmented per worktree.

## Decision

All nine (D32). doctor resolves hooks via git rev-parse
--git-common-dir (worktree-aware) and reports manifest/package version
drift with the upgrade and whatsnew commands. Bare --write baselines
only currently-stale pairs and declares a no-op when everything is
green. A shared decisions loader (gov/decisions.py) serves
verify-decisions, audit-notes, and recall from docs/decisions.md or a
configured .gov/decisions.json (sections or markdown-table format; a
header alternatives column covers every row); with no source and
D-referencing notes it answers REFUSED, exit 1 — a vacuous green is a
rule-6 violation wearing a pass. The coverage ledger separates
never-executed gates (write-one nag) from executed-but-undeclared cases
(named with their missing '# gate:' line). self-test scrubs GIT_* at
process entry — the tools resolve repositories by cwd (D21), inherited
repo-resolving variables only ever mislead — announcing what it
scrubbed; the hook template unsets them too and selects its gate set
from the push range on stdin (--base remote-sha; new branch → full).
Path-scoped gates carry "n in change scope" on their outcome line,
with zero visibly distinct from a scan. Run history records into the
git common dir's parent — the main checkout's ledger, not the
worktree's.

## Alternatives considered

- Per-subprocess env scrubbing — rejected: one scrub at the process
  boundary covers in-process cases and every child they spawn.
- Full-mode hook with caching — rejected: rule 1 gives CI the full
  matrix; the hook owns the smallest sufficient set for the push.
- Refusing on any missing decisions source — rejected: it would break
  first-run-green (D13); D-references into nothing are the dangerous
  signal, and only those refuse.

## Consequences

Pushes from worktrees run the right gates under a clean environment;
green pairs keep the confirmations they earned; decisions live wherever
the project keeps them or the gate says REFUSED; zero-file scopes are
visibly zero; and one ledger accumulates per repository. The hook
template changed — existing installs update via the two-step (edit
.gov/hooks/pre-push or gov init --adopt after removing it), which the
whatsnew entry for 0.13.0 says out loud.
