# Defensive patterns

English | [中文](defensive-patterns.zh.md)

Rules for classes of defects that actually shipped somewhere and were expensive to rediscover. Each entry states the rule and the bug class it prevents. Add a pattern only with the failure that motivates it — a pattern without a scar is speculation.

## Report exit and signal as independent facts

A child can die from a signal that never produces a normal exit code. Both scheduler ports derive two facts from the raw wait status — `exit N`, or `signal SIGKILL` when the status exceeds 128, named through `kill -l` — and report whichever occurred on its own. Never fold one fact into another's branch, or a killed gate reads as a clean success. The split is pinned by the scheduler's kill -9 tests on both ports.

## Bash declarations inside a function are local

`declare` (and `declare -A`) inside a function creates a local that vanishes on return. The scheduler's result maps vanished exactly this way: `run_gates` populated them, the caller read unbound variables and crashed. Cross-function state needs `declare -gA`.

## A persistent control-character IFS corrupts quoted array expansions

On bash 5.1, leaving IFS set to a control character makes every quoted `"${arr[@]}"` expansion explode into single characters — the scheduler launched gates with empty ids and died on array subscripts. Scope a special IFS to the one command that needs it (`IFS=$US read -ra ...`); it must never outlive that line.
