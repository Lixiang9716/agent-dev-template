# Agent Note: CHANGELOG ↔ HIGHLIGHTS pairing — version-following made mechanical

Status: implemented

## Problem

Three version-mismatch incidents (0.12.3→0.13.0, 0.12.1 wrong
direction, 0.13.1 wheel-lag) shared one root: HIGHLIGHTS section
headers carried hand-guessed version numbers that release-please then
overturned. The user's insight: the bilingual pairing gate's core
logic — one side updates, the other must follow, a gate enforces —
applies directly. CHANGELOG.md is auto-updated by release-please
(correct by construction); HIGHLIGHTS.md must follow, and its version
numbers should be READ from CHANGELOG, never guessed.

## Decision

A new gate, gov verify-doc-sync (D37): parses CHANGELOG's
`## [X.Y.Z]` section headers and HIGHLIGHTS' `## X.Y.Z` headers;
every released version >= 0.12.0 must have a matching section on both
sides. CHANGELOG gains a version that HIGHLIGHTS lacks → "copy the
version FROM CHANGELOG and add a section"; HIGHLIGHTS has a version
ahead of CHANGELOG → "shipped before its release; fix the header".
The gate joins this repository's config with paths scoped to the two
files. The workflow mirrors bilingual pairing: release-please opens
the release PR (CHANGELOG gains a section), the gate goes red, the
HIGHLIGHTS entry is pushed to the same PR with the version number
copied from CHANGELOG, and the wheel ships with both sides aligned.
The existing tag-coverage test stays as a second line (the gate
catches in the release PR; the test catches on any later push).

## Alternatives considered

- Deleting HIGHLIGHTS and reading CHANGELOG — rejected: changelog
  entries are commit-message one-liners, not usage guidance; the
  cookbook covers usage but is task-organized, not version-organized;
  "what arrived in this release and how to use it" needs per-version
  sections.
- Auto-syncing only the headers — rejected: content still needs a
  human; syncing headers without content is an empty promise.
- The old "guess and hope" workflow — rejected three times by
  production, once per incident.

## Consequences

Version identity is now mechanically enforced across CHANGELOG,
HIGHLIGHTS, and the wheel — the release PR is the enforcement point,
just as the pairing gate makes a PR the enforcement point for
bilingual docs. The remaining human work is writing the usage
content, which is exactly where human judgment belongs.
