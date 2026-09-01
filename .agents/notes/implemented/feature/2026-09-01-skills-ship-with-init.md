# Agent Note: the agent skills ship with the plane

Status: implemented

## Problem

The skills made agents reach for the tools first (recall before
proposals, smallest gate set before runs, rubric before review), but they
lived only in this repository: `gov init` injected rules, gates, and the
notes format — not the habits that route an agent session to them. An
adopter's agents got the tools without the triggers, which is the
half-installed state the earlier "repo-local, not template" stance
(D17/D18 line) was eventually going to hit. The maintainer called it:
ship them.

## Decision

`gov init` now injects the four skills — recall-first, pre-push-checks,
code-review, archive-agent-notes — as create-if-missing template copies
under `.agents/skills/<name>/SKILL.md`, recorded in the manifest and
removed by `gov uninstall`; a project's own skill with the same name is
never overwritten. The rubric-dependent parts of code-review and
pre-push-checks were rewritten conditionally (grade against
`docs/review-rubric.md` when the project maintains one; otherwise fall
back to the reviewer-only axes), so the shipped templates and this
repository's live skills are byte-identical — one source of truth, locked
by a pytest drift assertion that fails the build when they diverge.
Packaging uses a `skills/*/SKILL.md` package-data glob, verified by
building the wheel and listing its contents. The rubric itself still does
not ship (D17 stands: its items are half repo-specific); the conditional
skill wording absorbs that dependency.

## Alternatives considered

- Keep skills repo-local — superseded: the triggering event arrived
  (maintainer request); tools without triggers is guns without sights.
- Ship repo-specific skills verbatim — rejected: they reference
  `docs/review-rubric.md`, which adopters do not have; the injected
  dangling references would be flagged by our own `gov audit-notes`.
- Ship the rubric as a template too — rejected for now: half its items
  cite this repository's artifacts (tests, tiers.md, decisions.md); a
  generic rubric is a rewrite, not a copy, and nothing has asked for it.
- Maintain separate template and live variants — rejected: two sources
  of the same fact must drift; conditionals plus a drift test keep one.

## Consequences

Every `gov init`-ed project's agents now see the same four triggers. Skill
changes in this repository must keep the template copies identical (the
drift test enforces it), and the shipped skill text must stay
project-agnostic — repo-specific guidance belongs in the live copy only
at the cost of breaking the drift test, so in practice it belongs
elsewhere (rules, rubric, notes).
