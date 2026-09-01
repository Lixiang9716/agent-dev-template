# Agent Note: the executor honesty round — auto base, root anchoring, partial baselines

Status: implemented

## Problem

Four findings from another adversarial pass, the first structural:
note-presence was correct as a tool and inert where it actually ran. Both
shipped runners see a clean tree — the pre-push hook fires after commits,
CI checks out a clean checkout — and its default base (`HEAD`, the working
tree) therefore diffed nothing: a committed behavior change without a note
pushed straight past a green gate. Second, calling verify-notes or
verify-pairing from a subdirectory reported "0 notes ok / 0 pairs ok" and
passed, while the other root-relative tools failed loud — five commands,
two standards for "am I at the governed root". Third, a bare
`--write` refused to baseline anything as soon as one unrelated file had
no counterpart. Fourth, recall's alphabetical tie-break listed archived
notes ahead of implemented ones at equal rank.

## Decision

note-presence's default base is now an auto cascade (D21): a dirty
worktree reviews the working tree; a clean one reviews the commits ahead
of upstream, else the last commit, else everything (single-commit
repository) — with the chosen base and reason printed first. The CI
workflow templates (and this repository's CI) fetch full history so the
cascade never falls through to "everything" on a shallow clone; the
pre-push hook stays a plain `exec gov run`, now correct by construction. A
new shared `gov/root.py` anchors the five notes/pairing tools to the git
work-tree root — announced on stderr, never silent — so subdirectory
calls see the real tree instead of a vacuous zero. Bare `--write` records
what it can and reports what it cannot (`wrote N, left M unpairable`,
exit 1; a named nonexistent path stays exit 2 — a typo, not a pair
state). Recall's sort puts implemented/ before archived/ at equal rank:
current authority outranks frozen evidence.

## Alternatives considered

- Parsing the pre-push stdin ref range in the hook — rejected: every
  executor computing its own base is how the drift happened; one cascade
  in the tool keeps the hook logic-free.
- Per-tool root validation — rejected: five implementations of one
  judgment is exactly the inconsistency that produced the silent zero.
- Keeping all-or-nothing `--write` — rejected: one unpaired file holding
  every good baseline hostage is the failure mode being reported.

## Consequences

`gov run` on a clean tree now reviews unpushed commits — local runs after
committing get the same honesty the hook needs, at the cost of a warning
for committed-but-unnoted work that previously slipped through silently.
Auto base prints its choice, so a surprising range is visible immediately.
