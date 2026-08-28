# Agent Note: verify-note-presence — the checkable half of rule 2

Status: implemented

## Problem

Rules say every non-trivial change carries an Agent Note (rule 2), and that
any checkable promise must be a gate (rule 1) — yet the notes gate only
validated the format of notes that already existed. Whether a change carries
a note at all was pure honor system, and D3's locked extension (a
note-presence soft gate) had never been implemented. Adopters noticed: the
strongest rule in the plane had no enforcement path at all.

## Decision

`gov verify-note-presence` checks the observable half: when the diff against
a base (tracked diff plus untracked files) touches behavior-bearing surfaces
— anything not under `.agents/notes/`, not under `docs/`, and not a
root-level `.md` — and nothing under `.agents/notes/implemented/` changed,
it warns, naming `.gov/rules.md` rule 2 and offering the trivial-change
exit. The default is advisory (exit 0, per D3); `--strict` blocks (exit 1)
for teams that choose it. The default base is `HEAD` — the working tree —
because a base of `HEAD~1` does not exist in a one-commit repository, which
is exactly the state of a project in its first week. Git failures exit 2.
The gate ships in the injected default mode; change-scope prints the same
reminder.

## Alternatives considered

- Hard-fail from day one — rejected: "is this change trivial?" is ultimately
  a human judgment; a mechanical block would false-positive typoes into
  failures and teach people to bypass the gate.
- Commit-message `note:` trailers — rejected: commit messages live on a
  different plane and get rewritten by squash/rebase; the diff-versus-notes
  file surface is stable evidence.
- Checking note *quality* — rejected: format is already `verify-notes`;
  presence is the only part a command can honestly observe.

## Consequences

A docs-only or notes-only diff never warns; a big refactor without a note
always does. Teams that want enforcement flip `--strict` in their
`gates.json` command; the shipped template keeps it advisory so a fresh
install's first run stays green.
