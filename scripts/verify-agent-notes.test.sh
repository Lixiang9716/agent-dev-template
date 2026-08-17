#!/usr/bin/env bash
# Negative and positive tests for the notes verifier (bash twin of
# verify-agent-notes.test.ps1): every rejection rule fires on a minimal
# violating tree, and a valid tree passes clean. A gate only guards if the
# regression actually fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh
source scripts/verify-agent-notes.sh 2>/dev/null

VALID_IMPLEMENTED=$(cat <<'NOTE'
# Agent Note: sample decision

Status: implemented

## Problem

A problem statement.

## Decision

The decision.

## Alternatives considered

An alternative and why it lost.

## Consequences

What follows.

NOTE
)

# Create a throwaway notes tree with one note.
notes_tree() { # <lifecycle> <class> <filename> <body>
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/$1/$2"
  printf '%s\n' "$4" > "$dir/$1/$2/$3"
  printf '# Agent Notes\n' > "$dir/README.md"
  REPLY_TREE=$dir
}

violations_of() { # <tree-dir> — prints the violation list
  collect_violations "$1"
  printf '%s\n' "${NOTES_VIOLATIONS[@]}"
}

has_violation() { # <haystack> <fragment>
  expect_contains "$3" "$1" "$2"
}

notes_tree implemented process 2026-01-01-valid-note.md "$VALID_IMPLEMENTED"
tree=$REPLY_TREE
out=$(violations_of "$tree")
expect_eq 'a valid implemented note passes clean' "$out" ''
rm -rf "$tree"

# An unknown lifecycle directory is rejected.
tree=$(mktemp -d)
mkdir -p "$tree/drafts/process"
printf '%s\n' "$VALID_IMPLEMENTED" > "$tree/drafts/process/2026-01-01-x.md"
printf '# Agent Notes\n' > "$tree/README.md"
out=$(violations_of "$tree")
has_violation "$out" 'unknown lifecycle' 'an unknown lifecycle directory is rejected'
rm -rf "$tree"

# An unknown class directory is rejected.
notes_tree implemented misc 2026-01-01-x.md "$VALID_IMPLEMENTED"
out=$(violations_of "$REPLY_TREE")
has_violation "$out" 'unknown class' 'an unknown class directory is rejected'
rm -rf "$REPLY_TREE"

# A malformed filename is rejected.
notes_tree implemented process notes.md "$VALID_IMPLEMENTED"
out=$(violations_of "$REPLY_TREE")
has_violation "$out" 'yyyy-mm-dd-topic.md' 'a malformed filename is rejected'
rm -rf "$REPLY_TREE"

# An implemented note with a Proposal section is rejected.
mutated=$(printf '%s\n' "$VALID_IMPLEMENTED" | sed 's/^## Decision$/## Proposal\n\nOld text.\n\n## Decision/')
notes_tree implemented process 2026-01-01-x.md "$mutated"
out=$(violations_of "$REPLY_TREE")
has_violation "$out" 'proposal-era' 'an implemented note with a Proposal section is rejected'
rm -rf "$REPLY_TREE"

# A rejected note without a reason suffix on Status is rejected.
notes_tree rejected process 2026-01-01-x.md "${VALID_IMPLEMENTED/Status: implemented/Status: rejected}"
out=$(violations_of "$REPLY_TREE")
has_violation "$out" 'Status: rejected —' 'a rejected note without a reason suffix is rejected'
rm -rf "$REPLY_TREE"

# A proposed note missing Acceptance criteria is rejected.
notes_tree proposed process 2026-01-01-x.md "$(cat <<'NOTE'
# Agent Note: sample proposal

Status: proposed

## Problem

P.

## Proposal

Do it.

## Alternatives considered

None.

## Risks

Few.

NOTE
)"
out=$(violations_of "$REPLY_TREE")
has_violation "$out" 'Acceptance criteria' 'a proposed note missing Acceptance criteria is rejected'
rm -rf "$REPLY_TREE"

# INDEX.md is rejected wherever it appears.
notes_tree implemented process 2026-01-01-x.md "$VALID_IMPLEMENTED"
printf '# index\n' > "$REPLY_TREE/implemented/process/INDEX.md"
out=$(violations_of "$REPLY_TREE")
has_violation "$out" 'INDEX.md is forbidden' 'INDEX.md is rejected wherever it appears'
rm -rf "$REPLY_TREE"

# The archived tree is never re-valided here.
notes_tree implemented process 2026-01-01-x.md "$VALID_IMPLEMENTED"
mkdir -p "$REPLY_TREE/archived"
printf 'not a note\n' > "$REPLY_TREE/archived/anything.md"
out=$(violations_of "$REPLY_TREE")
expect_eq 'the archived tree is never re-validated' "$out" ''
rm -rf "$REPLY_TREE"

t_done
