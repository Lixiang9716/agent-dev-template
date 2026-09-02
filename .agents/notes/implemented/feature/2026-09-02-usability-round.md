# Agent Note: the usability round — a living specimen, a cookbook, whatsnew, and reports that point ahead

Status: implemented

## Problem

Three shipped features came back as new wishes — duration_ms in --json,
--write for a named pair, note new's no-table notice. That is the
clearest possible evidence that discoverability, not capability, was
the bottleneck: an adopter's information about an update was one
changelog line and one README line. The demo project exercised a third
of the plane, no task-oriented documentation existed, and some reports
answered without pointing to the next step.

## Decision

Four things (D31). examples/demo-project became a living specimen:
bilingual rubric, a decisions table with review-by, a rejection case
declaring its gate, surfaces.json, a note carrying a D-reference, and
gates for rubric/decisions/source-limits — an adopter can diff their
setup against it. docs/cookbook.md (a bilingual pair) is the
task-oriented layer: symptom, command, expected output — built from
this session's real collision scenarios. gov whatsnew prints
gov/HIGHLIGHTS.md, a curated usage-oriented per-release summary shipped
as package data, defaulting to everything newer than the manifest's
init version; gov init --upgrade points at it when the package is
newer. And reports point ahead: the coverage ledger's NONE line
explains the case-file format, trend movers explain what a mover means.

## Alternatives considered

- whatsnew reading the raw CHANGELOG — rejected: commit logs narrate
  commits, not usage; the curated file costs maintenance but every line
  answers "how do I use this".
- Shipping the cookbook inside the package — rejected: repository docs
  suffice; the package stays light.
- Running the specimen's gates green in our CI — rejected: it lives
  inside this repository, so root-anchoring resolves to the parent;
  its independent verification happens in an adopter's copy.

## Consequences

An adopter upgrading now has three paths to "what changed and how do I
use it" (whatsnew, cookbook, specimen) that require no repository
archaeology — and the next already-shipped-feature-wish becomes the
metric of failure for this round.
