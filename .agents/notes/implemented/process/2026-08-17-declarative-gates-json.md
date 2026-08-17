# Agent Note: declarative gates.json with command slots

Status: implemented

## Problem

Gate orchestration hard-coded per repository locks adopters into one toolchain and makes the scheduler itself unauditable configuration.

## Decision

Gates are data: `gates.json` declares each gate as `{id, command, needs?, allowFailure?}` plus named modes; a command is a shell-shared array or per-shell variants (see the dual bash and pwsh governance runners note). The scheduler validates the graph before running and treats any non-zero exit as failure. Product-plane work enters as command slots the adopting project declares once.

## Alternatives considered

A Makefile (rejected: DAG semantics exist but failure propagation, skip attribution, and output capture per gate are unnatural); per-language runner scripts (rejected by the companion note on the language-neutral governance plane).

## Consequences

Any failing command is a gate, in any language. The scheduler's own behavior is pinned by `scripts/gates.test.sh` and `scripts/gates.test.ps1`, including rejection of cyclic and malformed graphs before any child starts.
