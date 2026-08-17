# Agent Note: per-language gate runner clones

Status: rejected — each clone re-implements scheduling and validation, and every fix must be replicated N times; the declarative scheduler with command slots delivers the same fit with one auditable implementation.

## Problem

Projects in different languages might prefer gate tooling written in their own language for contributor familiarity.

## Proposal

Ship runner templates (a Makefile flavor, a Python flavor, a Node flavor) that adopters pick at clone time.

## Alternatives considered

One declarative scheduler with language-neutral command slots (chosen: single implementation, single test suite, single place to fix scheduling defects — see the declarative gates.json note).

## Consequences

Familiarity is traded for uniformity: every adopter reads the same `gates.json` and the same failure vocabulary. A project that truly needs native tooling can still wrap it as command slots.
