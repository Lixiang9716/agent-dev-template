# Agent Note: change-scope minimal check surface

Status: implemented

## Problem

Facing a push, the reflex is to run everything; on a large repository that burns the inner loop and trains people to skip checks entirely.

## Decision

`scripts/change-scope.sh` / `scripts/change-scope.ps1` report the change scope as stable JSON: the verified base, merge base, and four path classes (committed, staged, unstaged, untracked). The pre-push-checks skill maps those paths to the smallest sufficient gate set. The base is an argument, never guessed or fetched — the caller passes a ref it verified.

## Alternatives considered

Always running the full aggregate (rejected: exhaustiveness is CI's job; the local loop must stay fast enough to actually run); auto-inferring the base from branch tracking (rejected: inference can silently pick a stale or wrong base, defeating the point of a trustworthy scope).

## Consequences

Gate selection becomes evidence-based and auditable: the skill's report includes the commands run. Dirty worktree files are surfaced as their own class so they are committed or explicitly excluded, never assumed away.
