# Agent Notes

One kind of design doc lives here. An **Agent Note** records a decision or proposal that affects this repository — the *why* and *what we gave up*, the parts code and docs cannot carry. Agents and humans write them; `verify-agent-notes.mjs` enforces the format mechanically.

## Layout

A note's path encodes both of its axes: `{lifecycle}/{class}/yyyy-mm-dd-topic-title.md`.

- **Lifecycle**: `proposed/` (review before implementation), `implemented/` (the decision that shipped; kept current with the shipped facts — update paths, names, and defaults in the same change that alters them, but never rewrite the decision itself), `rejected/` (kept only when the reasoning still blocks a tempting mistake), and `archived/` (frozen, sha256-sealed, owned by `archive-agent-notes.mjs`).
- **Class** (closed set): `feature`, `bug-fix`, `simplification`, `architecture`, `process`, `testing`.
- The filename date is when the topic was **first proposed**. Notes are English-only in this template.

## Format

The header is exactly three content lines:

```
# Agent Note: <title>

Status: proposed|implemented|rejected
```

A rejected note adds the reason on the Status line: `Status: rejected — <why>`. The body starts with `## Problem`, then per lifecycle:

- **proposed**: `## Proposal` (future tense allowed), `## Alternatives considered`, `## Acceptance criteria`, `## Risks`.
- **implemented**: `## Decision` (present tense, matching what shipped), `## Alternatives considered`, `## Consequences`. Proposal-era headings (`## Proposal`, `## Plan`, `## Migration plan`, `## Acceptance criteria`) are rejected — an implemented note states what is.
- **rejected**: `## Proposal`, `## Alternatives considered`.

`## Alternatives considered` is mandatory in every lifecycle: a decision recorded without what it beat invites re-litigation — the exact failure Agent Notes exist to prevent.

## When to write one

Every non-trivial change adds or updates at least one note in the same PR. When a note is fully superseded, the successor absorbs its unique rationale and links back, then the old note archives. There is no `INDEX.md`; the tree layout is the index.
