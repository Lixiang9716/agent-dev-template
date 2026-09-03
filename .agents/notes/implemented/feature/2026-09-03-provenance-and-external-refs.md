# Agent Note: adoption provenance, adopt preview and disclosure, external D-references

Status: implemented

## Problem

The drift report answered every difference with one ambiguous phrase —
"customized locally and/or template evolved" — leaving the adopter's
actual question ("did upstream move? should I re-adopt?") answerable
only by hand-diffing shipped templates against origin/main. --adopt
could not preview a single file, and it edited the manifest silently.
And referencing govrail's own decisions from an adopter's notes
(radiant citing govrail:D24) read as a dangling local reference — there
was no legal cross-project reference syntax.

## Decision

Provenance hashes (D34): init and adopt record the sha256 of every
template file actually landed (manifest "templates"; files the project
already owned are not recorded — nothing was adopted). --upgrade now
performs a three-way call per differing file — UPSTREAM MOVED (your
copy is byte-identical to what was adopted; --adopt takes the new
template safely), BOTH MOVED (your customization and the upstream
template evolved; merge by hand), or, for legacy manifests without
hashes, the old wording with "no adoption hash recorded" stated. --json
gains era and adoptable fields. --adopt will replace an existing file
only when it is byte-identical to its recorded adoption hash — that is
the old template's residue, not the project's content — and never a
customized one. --adopt --preview shows what would land (content for a
missing file, a replacement diff for an existing one) and writes
nothing; every manifest change by adopt is disclosed on stdout. The one
sanctioned cross-project reference is govrail:D<n>: audit-notes,
verify-decisions' orphan math, and note check all strip such references
before extracting local D-numbers (external refs neither dangle locally
nor mask local orphans), and note new --ref accepts them as external —
recorded, not locally validated, and said so.

## Alternatives considered

- Arbitrary namespaced references (foo:D1) — rejected: a silent
  escape hatch for typos; govrail: is the only external table we know.
- Auto re-adopting every UPSTREAM MOVED file during upgrade — rejected:
  batch replacement across files deserves a human look at the preview.
- Recording more than byte hashes in the manifest — rejected: identity
  is all the call needs.

## Consequences

The upgrade report finally answers its central question mechanically:
UPSTREAM MOVED means re-adopt with one command, BOTH MOVED means a
merge, and legacy ambiguity is labeled as what it is. Adopters can cite
the tool's decisions without lying to their own gates, and an adopter's
manifest is now a ledger of exactly what was taken from upstream.
