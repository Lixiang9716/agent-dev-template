# Agent Note: lease locks — acquire/release/locks for oblivious parallel agents

Status: implemented

Related: D52 (this decision), D51 (the deferral criterion this PR redeems —
"≥2 real parallel workers coordinating a shared resource" has fired), D2
(exit-code vocabulary, additively extended with 3), D42 (the GOV_CALLER
caller vocabulary, reused for holder identity), D32#9 (git common dir as
the cross-worktree shared domain) and D32#6/D33 (hostile GIT_* environment
refused, never silently re-domained), D40 (whose rejected alternative
"file locks cannot lock independent checkouts" remains true — see the
supersede boundary)

## Problem

Users really do run multiple agents that are oblivious to each other and
coordinate shared-resource writes (say, several workers appending to one
report) by "the tool blocks or continues". D51 deferred the lock/lease
layer behind exactly this criterion; it has now fired. Four independent
reviews of the lock layer converged on corrections that any implementation
must absorb: flock(2) belongs to its holding process, so `gov acquire` —
a separate, short-lived process — cannot hold a lock across durations with
flock; mixing flock with TTL/reaper was rejected (a reaper cannot release
another process's flock, and unlink-then-recreate mints double holders).
What is needed is the LEASE class: cross-process, cross-duration,
declarative — and correct even when the lock itself fails (fail-open).

## Decision

`gov acquire <resource> [--agent ID] [--ttl S] [--wait S]`,
`gov release <resource> --agent ID`, and `gov locks` ship in
`gov/locks.py`:

- **Storage** — the lease lives at `<git-common-dir>/gov-locks/<resource>.json`
  (`/` in a resource name becomes `__`; the directory is created on
  demand). The git common dir is shared by every worktree of one clone,
  so leases span worktrees. Entry refuses a hostile GIT_* environment and
  any common-dir resolution failure with exit 2, named — never a cwd-level
  silent fallback.
- **acquire is an atomic create** (O_CREAT|O_EXCL) of
  `{"resource", "holder", "acquired_at", "expires_at"}`. A fresh lease in
  the way is **busy**: exit 3 naming the holder and expiry, or `--wait S`
  polls at 1s until the deadline (timeout: exit 3). An EXPIRED lease may
  be taken over lazily — the takeover's unlink→recreate critical section
  is flock-guarded on a `.guard` sibling (flock's lawful single-command
  duration: two takers-over serialize and re-check expiry inside the
  guard); the fresh-create path never needs the guard and never unlinks a
  fresh lock. The lock is not reentrant: even the holder's own repeat
  acquire is exit 3.
- **release is holder-verified**: a mismatching `--agent` is refused
  (exit 2) with the real holder named; a lease is never released on
  another holder's behalf. The check+unlink runs under the same guard so
  a stale-check release cannot unlink a lease a concurrent takeover just
  re-issued. `gov locks` is a read-only listing (with an expired flag;
  empty listing when no locks) — pure diagnostics that never feed an
  admission decision.
- **Exit 3 joins the D2 vocabulary additively**: busy/wait-timeout must be
  branchable by a caller and is neither a gate failure (1) nor a
  configuration error (2); 0/1/2 semantics are unchanged. Holder identity
  defaults to `--agent`, then `$GOV_CALLER` (D42), then the OS user.
  The flag registry moved with the flags (tests/test_flag_registry.py's
  pin). Acceptance is subprocess-based in tests/test_locks.py, including
  the two-process race: started simultaneously on the same expired lease
  via a go-file barrier, exactly one wins through the guarded takeover and
  the loser exits 3 — and a comment in the tests says plainly what locks
  cannot do: a holder that stalls past its TTL shares the resource with a
  taker-over, and upper-layer validation (push CAS, delivery rebase)
  carries correctness. The lock is the liveness layer.

## Alternatives considered

- **Long-held flock** — rejected on review P0: an flock belongs to its
  holding process, so a separate acquire process cannot hold it across
  durations; the lock would silently vanish when the process exits.
- **A semaphore-style `gov acquire slot`** (concurrency caps) — deferred:
  a concurrency limit belongs to the scheduling layer (D51's last staged
  criterion), not to a lease primitive; shipping it now would invent
  policy with no worker contention to tune against.
- **Sleep-poll with all waiters thundering on expiry** — the guard flock
  absorbs it today at this scale (two to a handful of workers; the loser
  re-checks inside the guard and exits 3 immediately). A queue would be
  scheduling-layer machinery without the event that justifies it.
- **Locks under `.gov/`** — rejected: `gov uninstall` deletes `.gov/`
  wholesale (D10's exact-reversal contract), so uninstalling the plane
  would silently release every live lease; the `.git` shared domain
  (D32#9's precedent) has no such reversing step and is shared by
  worktrees for free.
