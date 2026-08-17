# Agent Note: gates over prose

Status: implemented

## Problem

Agents and humans drift from prose conventions at different rates, and convention violations are discovered late or never. A rule that cannot be executed is a wish.

## Decision

Every mechanically checkable promise becomes a gate declared in `gates.json` and run by `scripts/gates.mjs`. AGENTS.md links to gates instead of restating them; uncheckable guidance belongs to review skills, stated as guidance.

## Alternatives considered

Prose-only conventions (rejected: no enforcement, decays silently); per-language lint configurations as the sole mechanism (rejected: lint checks syntax and style, not process facts like note format or pairing freshness).

## Consequences

Adding a rule means writing or extending a verifier plus a rejection test. Rules are fewer but enforced; AGENTS.md stays short and every claim in it is executable or explicitly judgment-based.
