# Agent Note: language-neutral governance plane

Status: implemented

## Problem

A template that prescribes a programming language excludes every project in another one; yet the governance mechanisms (scheduling, notes, pairing, scope) are inherently language-agnostic.

## Decision

The governance plane ships as zero-dependency Node 20 scripts (node:* builtins only, no package.json, no install step) and never touches product code. The product plane connects exclusively through command slots in `gates.json`. Non-Node hosts run the same gates via a container.

## Alternatives considered

POSIX shell for every script (rejected: the DAG scheduler and hash-based pairing are impractical safely in shell); Python stdlib (viable, rejected only to keep one runtime story; the design keeps the porting surface small); shipping a package.json with dependencies (rejected: it would impose a package manager on adopters and add an install step before first use).

## Consequences

The single requirement is Node 20+ (or any container runtime). Adopters of any language pay nothing beyond that; swapping the script runtime later touches only `scripts/` because no product-plane artifact references script internals.
