---
name: find-simplifications
description: Use to find non-obvious simplification candidates and turn them into evidence-backed Agent Notes — dead, duplicated, speculative, over-built, added-then-removed, or hand-rolled-where-a-standard-exists surfaces; also to audit or coalesce superseded Agent Notes. The pruning balance to the grow-the-plane rule.
---

# Finding simplifications

Standing order 11 grows the governance plane; this skill prunes it. A plane that only grows inflates. Prefer a few well-proven candidates over a pile of thin guesses — judgment stays active, this is guidance not a checklist.

## Where simplifications hide

- **Dead**: shipped surface with no caller, reader, or gate exercising it.
- **Duplicated**: two mechanisms carrying one fact; one home per fact (AGENTS.md rule 5) says one of them is wrong.
- **Speculative**: flexibility built for a future that arrived differently or never.
- **Over-built**: a verifier or doc solving a problem the repository does not have.
- **Hand-rolled**: a bespoke routine where a standard tool the repo already depends on does the job.

## Procedure

1. Gather evidence per candidate: when it was added (the owning note), what it costs now, what consumes it today.
2. Write a proposed note per candidate with the evidence and the removal consequence — never remove in the same change as proposing.
3. For superseded notes, coalesce per the notes README: the successor absorbs the unique rationale and links back.
4. Never judge by size or age alone; the archive skill owns those criteria.
