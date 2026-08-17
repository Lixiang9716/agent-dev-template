# Agent Note: standardize a coverage slot

Status: proposed

## Problem

The template documents coverage as a slot adopters may declare, but every adoption invents the naming, the mode wiring, and the failure granularity independently. There is no shared answer to "what does a coverage gate look like here".

## Proposal

Document one conventional slot shape: a `coverage` gate in `gates.json`, run in mode `all`, whose command is the adopting project's own coverage runner configured to fail under its chosen threshold. The template contributes the slot definition and docs, never the runner.

## Alternatives considered

Shipping a bundled coverage tool (rejected: inherently language-specific, breaking the language-neutral plane); leaving it entirely undocumented (rejected: coverage is the most commonly asked-for gate and deserves one documented shape).

## Acceptance criteria

A documentation section shows the slot for two different languages verbatim; the `all` mode in this template's `gates.json` references the slot in a comment-style aside or the docs alone; a reviewer of an adopted project can predict where the coverage gate lives.

## Risks

Adopters may treat the documented shape as a mandate. The docs must state plainly that thresholds, tools, and even the existence of the gate are the adopting project's call.
