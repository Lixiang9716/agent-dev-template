# Agent Note: decision-row tooling for parallel branches (gov decision next/add)

Status: implemented
Related: D40, D32, D28

## Problem

Issue #107 reported, with evidence from a nine-row batch (D30–D38 across
eight PRs developed in parallel worktrees), that decision-row maintenance
had no tooling for the workflow that actually produces them:

- **number allocation was manual and racy** — two branches each compute
  "next free D-number" from their own base and collide silently; the only
  defense was hand pre-partitioning ("you take D31/D32, you take D33");
- **appending a row was a textual merge-conflict factory** — the decision
  table is one markdown file, so parallel appends conflict on every
  rebase, and restoring numeric order afterwards is manual.

Nothing answered "what is the next number from *this* branch's point of
view" or "will this number survive the merge".

## Decision

Three pieces shipped, all built on the shared decisions loader (D32):

- `gov decision next [--count N] [--base REF]` — next free D-number from
  the configured source; `--base` unions numbers already landed on REF so
  a branch cut before a sibling landed does not re-allocate (the number
  it prints is the one the eventual merged history shows);
- `gov decision add --from FILE [--id Dn] [--base REF] [--dry-run]` —
  atomic append (temp file + os.replace, flock for same-checkout
  concurrency) validated *before* writing: duplicate numbers, gap-opening
  numbers, and drafts without an options/rejected-alternatives section
  are refused by name;
- a `dir` source format (`.gov/decisions.json` `{"format": "dir"}`,
  one file per decision under e.g. `.gov/decisions/D39-title.md`) — an
  append is a new file, so two worktrees appending from the same base
  merge with no textual conflict at all; `verify-decisions`, `recall`,
  and `audit-notes` consume it through the same loader.

The gate-time signal is `gov verify-decisions --base REF`: numbers added
on both sides since the merge-base are a named collision (a duplicate in
the merged history) refused with the `decision next --base` fix in the
message; a gap that merely pre-partitions numbers still landing on
sibling branches stays informational, like orphans. A tools-family
self-test case proves the collision refusal, and an acceptance test
reproduces the issue's scenario end-to-end: two real git worktrees from
one base each run `decision add`; the dir format merges clean and a
shared number becomes "D2: duplicate decision entry" — loud and named,
never silent.

## Alternatives considered

- **A cross-worktree lock** — rejected: parallel worktrees are separate
  checkouts; a lockfile cannot see them. Allocation across branches is
  `--base`'s job (information), the gate's job (detection).
- **Auto-renumbering on collision** — rejected: silently changing a
  number rewrites every D-reference in notes; a loud, named collision
  with the fix command in the message is the honest contract.
- **Migrating govrail's own table to dir format** — rejected for now:
  single-file sections stay this repo's source of truth; dir format is
  an adopter option, exercised by tests and the demo path.
- **Gap-opening numbers as hard refusal everywhere** — kept as refusal in
  `add` (local contiguity is the gate's own rule) but informational in
  `verify-decisions --base`: pre-partitioning across branches is exactly
  the legal workflow the issue described, once the sibling numbers land.

## Consequences

`gov decision next` prints one number per line (script-friendly);
`next --base` requires a fetch first (`--base origin/master` sees only
what you have fetched). The repo's own gates.json now scopes the
decisions gate to `.gov/decisions.json` and `.gov/decisions/**` too, so
dir-format adopters get the gate on source changes.
