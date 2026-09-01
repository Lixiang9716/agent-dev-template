# Agent Note: the honesty round — enforce what was already promised

Status: implemented

## Problem

An adversarial pass found ten places where the documentation promised a
semantic and the tool did not enforce it: `gov archive-notes` crashed with
a bare traceback on any fresh project (it wrote `archived/manifest.json`
without creating `archived/`, and sealed an empty manifest when there was
nothing to seal); the runner discarded the output of exit-0 gates, so an
advisory warning printed inside a passing gate evaporated — the user saw
only a green light; a rubric with zero items passed vacuously against the
gate's own rule 6; the notes README's "in this order" and D5's closed
class/lifecycle sets were unenforced (`implemented/misc/` passed, a
`drafts/` directory was silently ignored by verify-notes yet retrieved by
recall — two tools, two definitions of a note); archive-notes accepted any
argument silently; init's next-steps advice exit-2'd on projects with
nothing to pair; audit-notes false-flagged every D-ref when decisions.md
used a different heading format; and root-level `.md` files were all
presumed trivial, letting a doc-driven repository's DESIGN.md — its
contract — escape the note-presence check.

## Decision

Each gap was closed by enforcing the existing promise, not by adding
mechanisms (D20): archive-notes mkdirs, reports "nothing to seal", parses
arguments, and fails loud outside a governed tree; the runner keeps PASS
and exit codes but shows the last lines of a passing gate's output in a
`(passed with output)` block — D2's "passes are silent" is amended to
"passes with no output are silent"; verify-rubric rejects zero-item
rubrics; verify-notes enforces section order, the
`implemented/<class>/<file>.md` placement, and fails loud on unknown
lifecycle directories; recall now searches exactly `implemented/` and
`archived/`, making the definition of a note identical across tools;
note-presence treats only presentation roots (README, CHANGELOG,
CONTRIBUTING) as trivial, so DESIGN.md is behavior-bearing while `docs/`
stays the pairing gate's territory; init's next-steps does a read-only
existence probe to pick advice (not D13's rejected auto-baselining —
nothing is judged or written); audit-notes warns on a decisions file that
parses to zero sections and leaves D-refs unchecked instead of
false-flagging all of them.

## Alternatives considered

- A sixth WARN outcome for pass-with-output — rejected: it would amend
  D2's locked five-outcome contract where showing the output tail already
  achieves the goal.
- Treating all root `.md` as non-trivial — rejected: README and CHANGELOG
  edits are presentation churn; flooding an advisory with warnings trains
  people to ignore it.
- Configurable lifecycle directories — rejected: D5 locked the minimal
  two-state set; no event has asked for more.

## Consequences

Every `gov run` is noisier by design: passing gates that speak are heard,
capped at three lines. Stricter placement means a misplaced note now fails
the notes gate instead of lingering unfound, and the round's own diff was
reminded by note-presence to carry this note before it was written.
