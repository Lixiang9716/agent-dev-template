# Agent Note: localize defensive-patterns

Status: implemented

## Problem

`docs/defensive-patterns.md` carried two patterns inherited from the upstream distillation whose motivating scars lived upstream, not here: "report orthogonal outcomes" was stated over `timedOut`/`signal`/`exitCode` — this repository ships no timeouts — and "teardown must reach quiescence" spoke of closing listener registries before killing — no shipped mechanism owns listeners. The file violated its own admission rule ("add a pattern only with the failure that motivates it"). Evidence at audit time: added in the seed commit, never modified, zero inbound references; meanwhile two genuinely earned local scars lived only in code comments. A second dead surface: `expect_match` in `scripts/lib.sh` had zero bash consumers while its pwsh twin `Expect-Match` was in use.

## Decision

The pair is rewritten around what this repository ships and how it actually failed: orthogonal outcomes restated on the exit/signal split (status > 128 names a signal; pinned by the kill -9 scheduler tests on both ports); the listener-teardown pattern is dropped; two earned bash patterns are recorded — function-local `declare` vanishing on return (the scheduler's result maps), and a persistent control-character IFS corrupting quoted array expansions (bash 5.1). The dead `expect_match` helper is removed from `lib.sh`; `Expect-Match` stays by usage, resolving the asymmetry by evidence rather than symmetry. The budget ceiling ratchets to the rewritten size.

## Alternatives considered

Deleting the file outright (rejected: the exit/signal pattern ships and is tested, and the two bash scars are the class this tier carries); keeping the inherited patterns as distillation credit (rejected: the file's own header forbids scarless patterns); moving the bash scars into decision notes only (rejected: notes own decisions, the patterns file owns recurring rules of thumb); keeping `expect_match` for twin symmetry (rejected: verifier symmetry is the contract, test-helper symmetry is not).

## Consequences

Every pattern now names a shipped mechanism; provenance of the exit/signal pattern is upstream, pinned locally by tests — the one carried exception. The dropped listener-teardown pattern returns with the first listener-owning mechanism and its first real failure. The first find-simplifications audit concluded with one well-proven proposal rather than a pile of guesses, per its own bar.
