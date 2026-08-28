# Agent Note: pairing conventions move from code to .gov/pairing.json; --write can register

Status: implemented

## Problem

The pairing gate hardcoded the `.zh.md` counterpart suffix, the scan scope
(`docs/` + `README.md`), and even this repository's private exclusion of
`docs/decisions.md`. An existing project naming translations `foo_CN.md`
could not adopt the gate at all. Worse, `--write` could only re-record
already-paired files: running it to "register" a pair printed
`missing counterpart` and did nothing, which reads as a crash rather than a
rule.

## Decision

Conventions are configuration in `.gov/pairing.json` (all keys optional, bad
config exits 2): `include` (globs, default `docs/**/*.md` + `README.md`),
`counterparts` (`{stem}` + literal-suffix patterns, default `{stem}.zh.md`),
`exclude` (paths). This repository's exclusion of `decisions.md` moved from
the tool into this repository's own config. The record gains a
`counterpart: <name>` field that pins the translation side's name;
verification prefers the pinned name and falls back to convention derivation,
so old records keep working. `--write en:<path> zh:<path>` registers a pair
that follows no convention (both sides must exist, same directory); a pinned
name is never mistaken for a source document. Errors now state the
conventions tried and how to register explicitly.

## Alternatives considered

- Putting pairing settings inside `gates.json` — rejected: D1 locks that
  schema to the runner; tool-private config would pollute it.
- Explicit registration without config — rejected: registration must keep
  working on later runs, and the scanner cannot rediscover a convention-less
  counterpart without either a config or a record-pinned name; we needed both.
- Counterparts in other directories — rejected: the record pins a basename
  next to the source; relative paths would complicate the record format for
  no adopter need yet.

## Consequences

One-off oddities need one explicit registration each; projects with a uniform
non-default convention set one config key. The record format grew a field, so
tooling that parses records should ignore unknown keys (the shipped parser
already does).
