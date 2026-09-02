# Agent Note: add request retry with exponential backoff

Status: implemented
Related: D1

## Problem

Transient upstream failures aborted runs; operators retried by hand and
lost the context of what had already succeeded.

## Decision

Outbound calls retry with exponential backoff — 3 attempts, jittered —
before surfacing the failure.

## Alternatives considered

No retry (rejected: the upstream is documented-flaky); a circuit breaker
(rejected: out of proportion for a single dependency).

## Consequences

Runs survive transient blips at the cost of up to ~3x latency on a
hard failure.
