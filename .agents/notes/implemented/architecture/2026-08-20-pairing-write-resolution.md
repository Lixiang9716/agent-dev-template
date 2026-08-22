# Agent Note: --write argument resolution

Status: implemented

## Problem

`gov verify-pairing --write` accepted a bare stem or a `.zh.md`/`.i18n.yaml`
side, but its resolver was broken: a bare stem was used as a cwd-relative path
and never searched under `docs/`, and the `.zh.md` suffix was stripped with an
off-by-one (`[:-7]` instead of `[:-6]`), producing `fo.md` from `foo.zh.md`.
Both crashed with an uncaught `CalledProcessError` traceback (exit 1).

## Decision

Add `_resolve_source(arg)` that maps a bare stem, `.md`, `.zh.md`, or
`.i18n.yaml` argument to the source `.md` path, falling back to `docs/<name>`.
The `--write` branch resolves every argument through it, verifies the source
and its `.zh.md` counterpart exist, and reports a clean exit-2 error otherwise.
A regression case covers bare-stem and `.zh.md` resolution.

## Alternatives considered

- **Require full `docs/foo.md` paths only** — rejected: the help text already
  promises "bare stem or any side", so the resolver must honor it rather than
  narrow the interface.
