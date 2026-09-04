# Agent Note: note-presence exemptions — routine bookkeeping stops crying wolf

Status: implemented

## Problem

Two recurring false positives in an adopter repo (radiant, #149): closing a
task card wrote `.gov/tasks/T-0001-*.json` — a machine-written,
rules-hash-pinned receipt (D43) — and the note-presence advisory flagged it
("non-trivial file(s) changed with no note"); every docs-sync PR (decision
table rows plus a README pair restamp, no code) drew the same warning,
although the notes existed in the feature PRs and the sync PR merely landed
their payloads. Advisory-only severity is right (D14), but when the two most
routine agent workflows always warn, agents learn the warning is noise and
stop reading it — including when it points at a real omission.

## Decision

`gov verify-note-presence` treats `.gov/tasks/**` as trivially scoped by
default: task receipts are the task system's own tamper-evident output,
bookkeeping rather than decisions. A repo can exempt further surfaces by
declaring `"note_presence_exempt": [glob, ...]` in `.gov/manifest.json`
(D49) — gate-paths glob semantics (D15: `**` spans directories, `*` does
not), matched against repo-relative paths; the advisory then fires only
outside the declared scopes. An absent manifest or key means built-in
defaults only (the manifest stays optional, and its unknown keys remain
none of this gate's business, like every other manifest reader); a manifest
that exists but cannot be parsed, or an ill-shaped key, exits 2 naming the
file and key (rule 5), and the active exemptions are printed when the gate
runs. The warning now says which absence it found — "no note file appears
anywhere in this diff", explicitly not "none for these specific paths",
since any note file in the diff passes the gate. `gov change-scope`'s
reminder and `gov review`'s dossier use the same shared predicate, so the
surfaces cannot disagree (change-scope's root-.md handling thereby aligns
with D20). The advisory semantics are unchanged: this is noise reduction,
not a stricter check.

## Alternatives considered

- Per-path note attribution in the warning — rejected: there is no
  mechanical mapping from notes to paths; checking it for real would warn
  on diffs that do carry a note (stricter, the opposite of this round's
  goal), and pretending to check would be dishonest output.
- Only exempting `.gov/tasks/**` — rejected: the docs-sync class of false
  positives survives, and every repo's bookkeeping surface differs; without
  a declaration surface each new routine workflow means another tool change.
- Housing the exemption list in a per-gate config (`.gov/note-presence.json`
  or inside `.gov/pairing.json`) — rejected: one private config file per
  gate fragments the configuration plane; the manifest is already where a
  repo declares its relationship to the plane (D10/D34 vocabulary).
