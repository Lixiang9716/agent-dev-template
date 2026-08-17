# Agent Note: language-neutral governance plane

Status: implemented

## Problem

A template that prescribes a programming language excludes every project in another one; yet the governance mechanisms (scheduling, notes, pairing, scope) are inherently language-agnostic.

## Decision

The governance plane ships as twin bash and pwsh ports (bash >= 5 / pwsh 7+, zero install; see the dual bash and pwsh governance runners note) and never touches product code. The product plane connects exclusively through command slots in `gates.json`. Hosts with neither shell run the same gates via a container.

## Alternatives considered

Shell scripts for every port (initially rejected as impractical to write safely, later reversed by the dual-shell runners note once per-port rejection tests pinned identical behavior); Python stdlib (viable, rejected to keep the runtime story to shells every host already has); shipping a package.json with dependencies (rejected: it would impose a package manager on adopters and add an install step before first use).

## Consequences

The runtime requirement is bash 5+ or pwsh 7+ (or any container runtime). Adopters of any language pay nothing beyond a shell their host already carries; swapping the script runtime later touches only `scripts/` because no product-plane artifact references script internals.
