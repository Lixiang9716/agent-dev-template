# Agent Note: the conflict-marker gate — git's blind spot becomes a content gate

Status: implemented

Related: D38, issue #104

## Problem

A rebase of two parallel feature branches staged a file that still
carried three `<<<<<<< HEAD / ======= / >>>>>>>` blocks; `git add`
accepted it, `git rebase --continue` committed it, and two intermediate
commits shipped the markers. Nothing in the standard gate set
(notes, pairing, tests, source-limits) inspects file content, and git
itself refuses to police its own conflict text — it cannot tell a real
marker from a quoted one. A docs-only diff would have sailed to main;
the near-miss was caught only because the operator happened to look.

## Decision

`gov verify-conflict-markers` (D38) scans the working-tree content of
every changed file (auto base cascade identical to note-presence) and
fails exit 1 naming `file:line` for each marker: a line-initial
`<<<<<<<`, `>>>>>>>`, or diff3 `|||||||` is primary evidence; a bare
`=======` counts only beside a sibling primary marker, so Markdown
setext underlines stay legal. Exactly seven marker characters count —
`<<<<<<<<` (eight) does not. A line carrying the token
`gov:ignore-marker` is exempt: the documented escape hatch for string
literals and docs that quote markers. Binary files (NUL byte) and
deleted paths are skipped; git failures exit 2. The gate ships in the
template's `all` mode with no `paths` — markers can land in any file
type — plus a tools-family rejection case, a project case under
`.gov/rejections/` (coverage ledger shows `conflict-markers(1)`), and a
real, non-stub case in the demo specimen.

## Alternatives considered

- Scanning only diff-added lines — rejected: content-level scanning of
  touched files is strictly stronger (markers committed earlier in the
  range are still in the file's current content) and cheaper to
  implement.
- Tolerating string literals via per-language parsing — rejected: the
  promise is grep-level; a parser per language forks the gate's
  semantics. One ignore token per line covers the legitimate cases.
- Leaving it to linters (flake8 W605-style checks, etc.) — rejected:
  language-bound; the governance plane is language-agnostic, and a
  docs-only diff — the exact case from the issue — has no linter to
  run.
- Flagging a bare `=======` without a sibling — rejected: a Markdown
  H1 underline would false-positive on the first day, and a gate's
  first false positive spends its credibility.
