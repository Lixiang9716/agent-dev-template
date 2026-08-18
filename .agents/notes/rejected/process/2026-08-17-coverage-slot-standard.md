# Agent Note: standardize a coverage slot

Status: rejected — zero adopters have asked; the uniform slot model already answers it generically, and special-casing one slot opens a taxonomy the model deliberately avoids. Reintroduce when a deriving project actually asks about coverage.

## Problem

The template documents coverage as a slot adopters may declare, but every adoption invents the naming, the mode wiring, and the failure granularity independently. There is no shared answer to "what does a coverage gate look like here".

## Proposal

Document one conventional slot shape: a `coverage` gate in `gates.json`, run in mode `all`, whose command is the adopting project's own coverage runner configured to fail under its chosen threshold. The template contributes the slot definition and docs, never the runner.

## Alternatives considered

The uniform slot model plus the self-use-first positioning (chosen: "any command that exits non-zero on failure is a gate" already covers coverage with nothing template-specific to add — the adopting project's runner, threshold, and mode wiring are exactly the freedoms every other slot enjoys; the positioning note bars landing work for hypothetical users, and no deriving project has asked). Documenting the shape for two languages verbatim (rejected: starts a slot taxonomy — lint, typecheck — that uniformity exists to prevent, and the proposal's own risk section concedes adopters may read documentation as mandate). Shipping a bundled coverage tool (rejected: inherently language-specific, breaking the language-neutral plane).
