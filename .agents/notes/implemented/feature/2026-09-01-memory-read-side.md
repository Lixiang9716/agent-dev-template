# Agent Note: the memory read side — gov recall and gov audit-notes

Status: implemented

## Problem

The write side of memory was closed (every non-trivial change carries a
note; format and presence are gated), but the read side was raw grep.
Finding the decision behind a behavior meant hunting through three or four
directories and reading whole files to judge relevance — during this
session's own work that hunt happened repeatedly. Worse, the note contract
promises implemented notes stay "current with the shipped facts", yet
nothing reported drift: a note can reference a command, a decision entry,
or a file the repository no longer has, silently, forever.

## Decision

`gov recall <terms>` is deterministic, structure-aware retrieval over the
memory planes: Agent Notes (implemented and archived), each `## Dn`
section of `docs/decisions.md`, and postmortem entries (contract README
excluded). All terms must appear; hits rank by where (title > section
heading > body); no match exits 1 — an agent must never reason from an
empty recall. `gov audit-notes` reports mechanical staleness signals only:
backticked `gov <subcommand>` mentions the CLI no longer knows, `Dn`
references without a matching decisions entry, and backticked repo paths
(separator + extension, placeholders and globs exempt) that do not resolve.
Archived notes are frozen and exempt. Findings exit 0: they are evidence
for the archive-agent-notes skill's judgment, not a verdict. Both are
tools, not gates — they join no mode in `gates.json`.

## Alternatives considered

- Embeddings / semantic retrieval — rejected: zero dependencies is a
  locked promise, semantic recall is unauditable, and at this scale (tens
  of notes) deterministic ranking is not the bottleneck.
- Session-level working memory — rejected: that belongs to the
  harness/session layer; the governance plane owns versioned repository
  memory only (separation of planes).
- Making audit-notes a blocking gate — rejected: staleness signals include
  legitimately illustrative paths; blocking on them would train people to
  stop writing concrete references. Report, then let the skill judge.

## Consequences

Recall makes the existing memory actually reachable at the moment a
question reopens (its whole purpose per "notes are the agent memory"); the
audit gives the archive skill mechanical evidence it previously lacked. On
this repository the first audit run flagged three notes whose referenced
artifacts (`.gov/manifest.json`, `.github/workflows/gov.yml`) exist only in
`gov init`-ed projects — correct signals, correctly soft.
