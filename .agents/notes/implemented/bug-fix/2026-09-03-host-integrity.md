# Agent Note: host integrity — three walls around the self-test's scratch fixtures

Status: implemented

## Problem

Two production incidents of the same signature: the self-test's
scratch fixture (`git init` + `git config user.email t@t` + commit
"init", author t<t@t>) mutated the HOST repository. On 0.12.0,
concurrent hook-context runs left an orphan "init" commit on three
linked-worktree branches — leaked GIT_DIR/GIT_INDEX_FILE made scratch
git commands resolve the host repo, and the pushes shipped the poisoned
tips. On 0.12.1, with the environment scrub active, the main
checkout's .git/config was rewritten (core.bare=true, user t/t) during
a worktree self-test window; the exact path stayed unpinned — which is
precisely why a single-point fix cannot be trusted.

## Decision

Three independent walls (D33), any one of which is sufficient on its
own. The fixture runs every git command with GIT_* scrubbed and
GIT_CEILING_DIRECTORIES pinned to the scratch parent (wall one). After
init and before any config/add/commit, a toplevel guard asserts that
`git rev-parse --show-toplevel` resolves to the scratch itself — any
mismatch aborts loud, refusing to touch the repository it found (wall
two). And the self-test entry, having scrubbed the environment, sets a
global GIT_CEILING_DIRECTORIES over the temp area so that even case
bodies calling git directly with the process environment cannot walk
up out of it (wall three). The acceptance is regression-locked from
both directions: running the full self-test inside a linked worktree —
including a variant with hostile GIT_DIR/GIT_INDEX_FILE leaked, the
incident-(a) shape — leaves the host byte-identical (config hash,
refs, status, HEAD), and a negative test pins that a simulated escape
aborts with the guard's message.

## Alternatives considered

- Trusting the entry scrub alone — rejected: incident (b) happened
  with it active; an unpinned mechanism means no single wall suffices.
- Rewriting the fixture on libgit2 or pure-Python git — rejected: a
  new dependency and a rewrite of thirty-three cases to buy what three
  environment walls already guarantee.
- Refusing to run in worktrees — rejected: adopters' real environments
  are worktrees; the tool must hold there, not hide from them.

## Consequences

A scratch fixture can no longer configure, stage, or commit into any
repository but its own — even under a hostile environment or an
unpinned regression, the failure mode becomes a loud abort, not a
mutated host. The guard makes escape attempts visible in test output
by name.
