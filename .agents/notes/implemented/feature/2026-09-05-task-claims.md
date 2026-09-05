# Agent Note: task claims — lease semantics for parallel workers, and lock-root visibility

Status: implemented

Related: D52 (the lease machinery this applies — no new decision row), D43
(task cards are a rules pin + receipt; why the claim never lives there),
D2 (exit vocabulary; 3 stays the busy code), D42 (the `$GOV_CALLER`
holder vocabulary), D19 (the parallel-workers skill's byte-identical
template copy)

## Problem

The concurrency drills (5/10/15-way) left three findings, all pointing at
the same gap.

First: two parallel workers could both take the same task card and both
do the work — nothing mechanical stopped it. The card is a file; both
workers read "open" and started. The governance review had already drawn
the boundary for any fix: the claim state must NOT be written into the
card JSON (the card is a D43 receipt — a rules@hash pin plus a green-run
record; mutating it per-claim would break receipt integrity), so the
claim has to live in the runtime domain, like the locks do.

Second: `gov acquire` resolved the lock root from cwd and said nothing
about where the lease actually landed. A drill agent with the wrong cwd
locked a REAL repository by mistake and could not tell — the success
line looked exactly like every other success.

Third: the drills measured the starvation shape D52's "no fairness
guarantee" implies — a loser with `--wait 120s` against a winner holding
`--ttl 300s` waited out its whole wait and still exited 3 at the
deadline; the resource stayed blocked until the winner's full TTL ran
out. Nothing in the parallel-workers skill warned against sizing
`--wait` below the holder's remaining TTL.

## Decision

`gov task claim <task-id> --agent <id> [--ttl DUR] [--wait DUR]` and
`gov task release <task-id> --agent <id>` put the D52 lease machinery
around a card, unchanged: the resource name is `task/<id>` in the common
dir's gov-locks, so O_EXCL creation, lazy takeover of an expired lease,
the guard-flocked critical section, and holder-verified release are all
the locks layer's own code — none of it is rewritten. Claim refuses
anything but an open card (missing or closed → exit 2, named — a usage
error, not a busy: waiting cannot reopen a closed card); a live lease
held by someone else is exit 3 naming holder and expiry. Success
announces holder and expiry instant on stderr. The card JSON is never
touched by a claim — the lease file is the only claim state, and
`gov task list --json` reads it to report a `claim` field
(`{claimed_by, expires_at}` or null; expired reads as null, same
freshness classification the lease layer uses), while the text listing
appends a `[claimed by … until …]` column to otherwise unchanged lines.
`gov task close` clears the card's own lease unconditionally — a
successful close means the work is finished, so any claim lease naming
any holder is moot; holder-verified cleanup (matching the closer's
$GOV_CALLER/OS user against the claimer's --agent) was tried first and
starved the next claimer for the winner's full TTL in the claim-race
drill — the closer's identity never matched the claimer's --agent.
`gov acquire` and `gov release` now announce the resolved lock
root (`acquire: lock root <abs path>`) on stderr, on success and busy
alike — the misdomain acquire is visible at the moment it happens. The
parallel-workers skill (both the live file and its byte-identical
template copy, D19) gains a "size the TTL, then size --wait to match"
section carrying the drill numbers: TTL ≈ 2-3x the critical section,
`--wait` ≥ the holder's remaining TTL + margin, or fail fast.

## Alternatives considered

Claim state written into the card JSON — rejected on D43's boundary:
the card is a verifiable receipt (rules pin + green-run record), and a
claim stamp would mutate it mid-flight and break receipt re-verification;
the runtime/common-dir domain is where cross-process, cross-worktree
state already lives (D52, D32#9). GitHub assignee as the claim truth —
rejected: it presumes the card is an issue and needs cross-machine
semantics the plane deliberately defers (v1 is one clone's worktrees);
the lease already spans every worktree of the clone. A bare lock without
TTL for cards — rejected for the same reason D52 rejected it for
resources: a crashed holder would block the card forever; the lease's
lazy takeover is the recovery path. Announcing the lock root only on
error — rejected: the drill's failure WAS a success line (a lease taken,
in the wrong repo); the announcement must ride the success path to be
worth anything.
