---
name: code-review
description: Use when reviewing a pull request in this repository; orients the reviewer to what code alone cannot show — decisions, guardrail proof, and pairing honesty — graded item by item against docs/review-rubric.md.
---

# Code review

A short review with one substantiated blocker beats a list of nits. Machines already checked format, structure, and freshness; review what they cannot — with the rubric as the anchor, not impressions.

## Before reading the diff

1. Run `gov change-scope --base <verified-ref>` and read the scope first; a dirty worktree means the PR author must either commit or exclude those files.
2. Find the PR's Agent Note. A non-trivial change without a note in the same PR is a blocker by rule 2 — and `verify-note-presence` will have said so.

## Grade against the rubric

Read [docs/review-rubric.md](../../docs/review-rubric.md) and grade **only the items the diff touches**, each with observed evidence (file and line). The rubric is the closed set of judgment axes; anything outside it is either a nit (group at the end, non-blocking) or a new criterion being invented — if you reach for a new criterion a third time, propose it as a new rubric item instead of repeating it ad hoc.

Machines already cover the mechanical half of several items (pairing hashes, note presence, rubric structure); your job is the half they cannot do — honesty of alternatives, semantic equivalence, sufficiency of the check set, silent skips, whether a new gate proved it can reject.

## Output

One line per graded rubric item: `Rn — verdict — evidence`. Then blockers with file and line (each with the observed evidence and the rubric item it violates). End with the explicit verdict: approve, or the blocking list.
