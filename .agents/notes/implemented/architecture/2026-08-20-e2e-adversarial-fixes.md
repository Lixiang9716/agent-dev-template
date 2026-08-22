# Agent Note: E2E adversarial test fixes

Status: implemented

## Problem

Two independent end-to-end subagents ran the full install-to-governance flow
and adversarial edge cases. They found six real defects in the Python
governance plane:

1. Transitive SKIP propagation was broken: a gate whose dependency was skipped
   still ran and reported PASS — a false green that violated "fail loud, never
   silently skip".
2. Illegal config values (negative or non-numeric concurrency, a null gate, a
   non-list gates field, a string timeoutMs, a top-level array) crashed with a
   bare traceback and exit 1, not the documented exit 2.
3. A fresh `gov init` could never go green: `verify-pairing` included AGENTS.md
   in scope, but init only appends a reference line and creates no bilingual
   pair, so `run --mode all` always failed pairing.
4. `uninstall` left residue: an empty AGENTS.md (when init had created it) and
   empty `.agents/` directories.
5. `uninstall` crashed on a corrupt `.gov/manifest.json`.
6. `gov --help` / `gov --version` were treated as unknown commands.

## Decision

- Rework `run_gates` to propagate SKIP transitively through the needs DAG: a
  gate is skipped when any need is blocking-failed **or** skipped.
- Validate every config field's type and range in `load_config`, failing with
  `ConfigError` (exit 2) instead of an uncaught exception.
- Remove AGENTS.md from the bilingual pairing scope: agent instructions are
  English-only (matching the notes); only README and `docs/` pair.
- `uninstall` deletes AGENTS.md when it becomes empty after stripping the
  reference line, removes empty parent directories, and reports a clean error
  on a corrupt manifest instead of crashing.
- Accept `-h/--help/help` and `-v/--version/version`.

## Alternatives considered

- **Make `gov init` create a bilingual AGENTS.md pair** — rejected: agent
  instructions are not external presentation, and init should not fabricate a
  Chinese counterpart for a project that may not be bilingual.
- **Keep SKIP propagation but special-case allow-failure dependents** —
  rejected: allowFailure already means "observational, non-blocking"; a skipped
  gate never ran, so its dependents must not silently run either.
