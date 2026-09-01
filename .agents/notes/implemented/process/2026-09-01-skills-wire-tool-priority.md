# Agent Note: skills wire agents to the tools first

Status: implemented

## Problem

The plane's tools had reached the point where an agent's correct first
move was usually one of them — recall before proposing, audit before
curation, `--base` selection before gate runs, the rubric before review —
but nothing told a fresh agent session that. Skills are the repo's
established trigger mechanism (a convention enforced by hand a third time
becomes a skill whose description is the trigger), yet only three existed,
two of which predated the memory read side and path-scoped selection. Left
as-is, agents keep hand-grepping and re-arguing exactly the way this
session did before `gov recall` existed.

## Decision

A new `recall-first` skill: use before designing, re-opening a settled
question, or grepping for why something exists — query `gov recall`,
read the hits' rejected alternatives, link or supersede, and treat a
no-match as making the change non-trivial (plan the note now).
`archive-agent-notes` gained step 0: run `gov audit-notes` for mechanical
evidence, with an explicit Never — archiving on a mechanical signal alone.
`pre-push-checks` now prefers the mechanical selector
(`gov run --base <verified-ref>`, per D15) over its hand-maintained
surface map (kept as fallback, corrected to the current tree), and adds a
rubric self-grade step for the judgment items (R1/R3/R6/R7; R4/R5 are
gate-covered). README's "What is inside" now lists the skills directory.

## Alternatives considered

- A new rule in `.gov/rules.md` ("consult memory before rework") —
  rejected: recall is unprovable from a diff, and rule 1 sends
  uncheckable conventions to review/skills, not to rule text.
- Shipping skill templates with `gov init` — rejected for now, same line
  as D17/D18: skills encode this repository's conventions; adopters'
  triggers depend on their rules. Event-driven, revisit on third ask.
- More new skills (a separate audit skill, a self-check skill) — rejected:
  extend before proliferate; the existing skills are the natural homes.

## Consequences

A fresh agent session in this repo now sees recall-first, pre-push-checks,
code-review, and archive-agent-notes as first-class triggers, each routing
to the tool instead of manual work. The pre-push skill's surface fallback
will drift again if gates change — it now defers to `paths` first, so the
drift surface is smaller but not zero.
