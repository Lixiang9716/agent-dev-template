# Agent Note: dual bash and pwsh governance runners

Status: implemented

## Problem

A Node-only governance plane imposes a runtime the adopting project never chose: hosts without Node 20 need a container before the first gate can run, and Windows-first teams live in PowerShell, not bash.

## Decision

Every governance script ships as two equivalent ports: a bash twin (`scripts/*.sh`, bash >= 5, zero dependencies beyond a POSIX toolchain) and a PowerShell twin (`scripts/*.ps1`, pwsh 7+). Both read the same `gates.json`, emit the same output vocabulary, and carry their own rejection-test suites (`scripts/self-test.sh`, `scripts/self-test.ps1`); CI runs both. Command slots are a plain array (identical on both shells) or per-shell variants that must name every shell in the closed set (`sh`, `pwsh`) — a missing variant aborts instead of silently skipping on that platform. This supersedes the runtime story of the language-neutral governance plane note (whose language-agnostic principle stands unchanged) and reverses its old "shell is impractical" objection: the DAG scheduler, hash-based pairing, and a fail-loud minimal JSON reader proved portable once each port carried rejection tests pinning identical behavior.

## Alternatives considered

Keeping the Node scripts (rejected: governance should ride the shells developer boxes already have — bash and pwsh ship with Linux, macOS, and Windows; Node does not); POSIX sh alone (rejected: no first-class Windows story, and bash 5 features carry the scheduler); per-product-language runner clones (rejected by the per-language gate runners note — those clone per product language; this is two platform twins of one declarative contract, taken with that note's replication cost explicitly accepted).

## Consequences

Every scheduler or verifier fix lands twice with parallel tests — the exact replication cost the rejected clone note warned about, accepted for the zero-runtime goal and bounded by the single `gates.json` contract and identical output vocabulary. The bash port requires bash >= 5 (associative arrays, EPOCHREALTIME, `wait`-style reaping) and embeds a minimal fail-loud JSON reader rather than depending on `jq`. A gate command that cannot start surfaces as `exit 127` with the shell's captured error, not a distinct spawn-error class.
