---
name: code-review
description: Use when reviewing a pull request in this repository; orients the reviewer to what code alone cannot show — decisions, guardrail proof, and pairing honesty.
---

# Code review

A short review with one substantiated blocker beats a list of nits. Machines already checked format, structure, and freshness; review what they cannot.

## Before reading the diff

1. Run `bash scripts/change-scope.sh --base <verified-ref> --head <pr-head>` (pwsh twin: `pwsh -File scripts/change-scope.ps1 -Base <verified-ref> -Head <pr-head>`) and read the scope first; a dirty worktree in the output means the PR author must either commit or exclude those files.
2. Find the PR's Agent Note. A non-trivial change without a note in the same PR is a blocker by AGENTS.md rule 2. The note must carry `Alternatives considered` — a decision without what it beat invites re-litigation.

## What only a reviewer can check

- **Guardrail proof**: for every new gate or assertion, is there a test proving it rejects an invalid case? A guard that has never failed is decoration.
- **Docs standing at HEAD**: no change narration, no citations of drafts or sessions, no reviewer-addressed justification in prose.
- **Pairing honesty**: if a `.zh.md` changed, its sidecar must be re-recorded in the same PR; "I will translate later" fails the pair gate and the PR.
- **Vocabulary**: changes touching the scanned docs surface (AGENTS.md, AGENTS.zh.md, docs/*.md) must clear the declaration-state vocabulary gate; a new claim word there is a blocker, and the pre-registered exemption ladder (meta-annotation, ban-definition sentence, backtick reference) is the only way in — a doc that defines the ban may say the word, a doc that asserts may not.
- **Silent skips**: any new code path that ignores an unknown value instead of failing loud is a blocker regardless of convenience.
- **Budgets**: a ceiling raised in `scripts/doc-budgets.json` needs an argued reason in the PR description, not just a number bump.

## Output

State blockers with file and line, each with the observed evidence. End with the explicit verdict: approve, or the blocking list.
