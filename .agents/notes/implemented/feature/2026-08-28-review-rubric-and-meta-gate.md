# Agent Note: the review rubric — judgment gets a structure, and a meta-gate keeps it honest

Status: implemented

## Problem

Rule 1 of `.gov/rules.md` says a convention that cannot be checked belongs
in review. But "review" itself had no structure: the criteria lived in each
reviewer's head, so verdicts drifted across reviewers (and across agent
reviewers even more), authors could not self-check before opening a PR, and
the quality of a review was uninspectable. The judgment half of the plane —
honesty of alternatives, semantic equivalence of translations, sufficiency
of a check set — was the largest surface with no written standard.

## Decision

The judgment criteria are now a published, bilingual rubric:
`docs/review-rubric.md` + `.zh.md` (an external-presentation pair, so the
pairing gate covers it). Eight items, R1–R8, each with four fields —
Checks, Evidence, Anti-pattern, Gate candidate. The rubric states its own
lifecycle: an item is the *review-time* form of a promise; when the promise
becomes mechanically checkable the item graduates into a gate with a
rejection case, and the `Gate candidate` field names which way each item
flows (R4 and R5 already point at their gates). The code-review skill now
grades PRs item by item against the rubric instead of freeform axes.

`gov verify-rubric` is the meta-gate: it never judges judgment — it checks
the rubric file keeps the shape that makes it gradeable (ids contiguous
from R1 and unique, the four fields present and non-empty, a
`Gate candidate: yes` names its destination, and the `.zh.md` side carries
the same id set — ids are the cross-language contract, prose is the
translator's). It ships with a rejection case in self-test and joins this
repository's gates scoped by paths to the two rubric files.

## Alternatives considered

- A prose reviewing guide — rejected: unstructured prose is exactly the
  each-reviewer-their-own-standard failure the rubric exists to end.
- Ship a rubric template with `gov init` — rejected for now: event-driven
  growth; no adopter has asked three times, and rubric content depends on
  each project's rules. The subcommand ships; the content stays ours until
  demand says otherwise.
- Check the translated side's field labels too — rejected: the bilingual
  contract is the id set; forcing English labels on the Chinese side would
  fight the pairing gate's job (content parity at confirmation) and the
  translator's craft.

## Consequences

Reviews gain a fixed, auditable axis set; new criteria must be proposed as
rubric items rather than invented per review. The rubric gate adds two
files' worth of surface to every full run, and the rubric itself is now
governed content — changing it is a non-trivial change with a note.
