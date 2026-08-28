# Agent Note: per-gate paths, --base selection, --gate rerun, and a failure summary

Status: implemented

## Problem

Rule 1 tells developers to run the smallest sufficient gate set, but the
runner had no idea which gates related to a change: `gov run` was all or a
manually chosen mode, so a docs edit ran the unit-test gate and a code edit
ran pairing. The predictable end state is `--mode quick` muscle memory or
`--no-verify` — the gates get bypassed precisely because they were never
scoped. Meanwhile change-scope suggested gates from a hardcoded
surface→gate map that had already drifted (it recommended a `links` gate
that does not exist). And when several gates failed, output listed PASS/FAIL
lines plus scattered blocks with no aggregate "what broke, rerun what".

## Decision

Gates declare coverage where they live: an optional `paths` array of globs
(`**` spans directories, `*` does not; matched against the full repo-relative
path; validated as a non-empty string array). `gov run --base <ref>` diffs
that ref (tracked diff plus untracked files) and selects the gates whose
paths match, plus every unpathed gate (always relevant), printing what was
left out as out of scope. `--mode`, `--base`, and `--gate` (single-gate
rerun) are mutually exclusive explicit selections that beat `defaultMode`.
change-scope now derives suggestions from the same `paths` in gates.json —
one source of truth — with the surface map kept only as a fallback for
configs without paths, minus the ghost gate. Blocking failures end with a
summary block: each failed gate, the first line of its output, and
`gov run --gate <id>` as the rerun recipe.

## Alternatives considered

- Keep modes as the only scoping mechanism — rejected: modes are named
  presets for humans; a diff is what actually defines "what changed".
- A separate change-scope→gate mapping file — rejected: two sources of the
  same fact must drift; the `links` ghost gate was that drift, caught in the
  wild.
- Intersecting `--base` with `--mode` — rejected: composition would make the
  semantics hard to predict from the command line; one explicit selection
  per invocation is easier to reason about and to script.

## Consequences

A gate without `paths` runs under every `--base` selection, so
always-relevant gates (like note-presence) stay cheap to keep unpathed.
Scoping only applies when `--base` is passed — a plain `gov run` still means
the whole default mode, and CI keeps owning the full matrix.
