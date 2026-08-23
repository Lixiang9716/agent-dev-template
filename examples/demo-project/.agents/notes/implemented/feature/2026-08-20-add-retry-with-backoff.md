# Agent Note: add request retry with exponential backoff

Status: implemented

## Problem

Upstream API calls failed transiently under load, and every caller had to hand
roll its own retry, duplicating backoff and jitter logic across the codebase.

## Decision

Add one shared `retry()` helper with exponential backoff and full jitter.
Callers opt in with a single decorator, and the helper owns the delay and the
max-attempts policy.

## Alternatives considered

- **Fixed-delay retry** — simpler, but causes a thundering herd on recovery,
  so it was rejected.
- **Retry inside each caller** — no shared contract, so backoff drifted across
  call sites; rejected.
