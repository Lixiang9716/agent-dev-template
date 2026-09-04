# Agent Note: pairing sidecar is self-describing — template comments, --write field echo, --explain

Status: implemented

Related: D30 (sidecar confirmation metadata: last_confirmed, en_commit/zh_commit), D12 (pairing conventions are configuration), D50 (this decision), issue #150

## Problem

An orchestrating agent edited both sides of a README pair, then re-stamped
the sidecar by hand with `en_commit`/`zh_commit = <current HEAD>` — the
natural reading of "record the commits". The gate then rewrote them with
the last commits that actually touched each file (much older hashes), the
mismatch cost one amended commit plus a force-push, and the whole episode
was only diagnosable because someone had read a related issue's resolution:
the sidecar's field semantics — blob hashes not sha256, last-touched-commit
not HEAD, `datetime.isoformat()` timestamps — existed only in this module's
code. The gate's error message pointing at `--write` worked exactly as
designed; what was missing was any readable statement of what the fields
mean and what `--write` would produce.

## Decision

The record now explains itself, in three places (#150):

- **Template comments** — `_register` writes comment lines into every
  generated `.i18n.yaml` stating the semantics: `pair.en`/`pair.zh` are git
  blob hashes (`git hash-object`), not file sha256; `en_commit`/`zh_commit`
  are the last commits that touched each side at confirmation time (not
  HEAD, not the confirmation commit, informational — the gate compares only
  the en/zh hashes); `last_confirmed` is the UTC ISO-8601 instant
  (`datetime.isoformat()`, `+00:00`). Comments are legal YAML and the
  line-wise `_parse_record` already skipped them; records live only in the
  sidecar, so they cannot perturb the side hashes the record pins.
- **`--write` announces its fields** — every write (explicit `en:/zh:`
  registration, named pair, or the bare out-of-sync sweep) prints the
  record path, the en/zh hashes ("git blob hashes, not file sha256"), the
  en_commit/zh_commit values ("last commit that touched each side — not
  HEAD"; `untracked` when a side has no commit), and `last_confirmed` —
  the same values the record now carries, so a restamp by `--write` and a
  sanity glance at the output can never disagree.
- **`--explain`** — prints the expected schema, this project's configured
  conventions (include globs, counterpart patterns read from
  `.gov/pairing.json`), the current in-scope pair count, the field
  semantics, and the command surface. Strictly read-only: it loads config
  (a bad config still exits 2, consistent with every other entry point)
  and judges nothing — an unrecorded pair stays unrecorded.

The flag is registered in audit-notes' FLAGS table (the
test_flag_registry pin forces the argparse help and the table to move
together, per #101). README and cookbook (both languages, pairs
re-confirmed) document the semantics and the new flag.

## Alternatives considered

- Editing the existing sidecars in place to add comments — pointless
  churn: records regenerate on the next legitimate re-confirmation, and
  the gate never reads the comments. Green pairs keep the confirmation
  they earned (D32).
- A `--dry-run` for `--write` — the issue's titular suggestion, but
  `--write` is idempotent and self-announcing now; a dry-run would add a
  second mode to reason about for a need the field echo already answers.
  If a real want arrives (previewing a bulk baseline), it should be
  designed against that want, not against the documentation gap.
- Replacing the line-wise parser with a YAML library — the zero-
  dependency stance (D18/D25) holds, and a real parser would reject or
  rewrite comments the line-wise reader correctly ignores.
- Teaching the drift error message the full semantics — it already names
  the mover and the confirmation time (D30); the gap was discoverability
  before the failure and trust in what `--write` writes, not the failure
  text itself.
