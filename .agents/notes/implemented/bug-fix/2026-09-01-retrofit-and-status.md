# Agent Note: retrofitting add-ons, customized files named before deletion, Status closed

Status: implemented

## Problem

`gov init --hooks` refused to help an already-initialized project ("already
initialized"), so the only way to get the pre-push hook later was
uninstall → init --hooks — and that path silently reset every
customization back to template defaults (a CUSTOM RULE in `.gov/rules.md`,
a CUSTOM LABEL in `gates.json`; notes survived only because init never
created them). Separately, `Status:` had no value domain: `Status: banana`
passed verify-notes while the lifecycle was actually encoded by the
directory, leaving the field decorative.

## Decision

Add-ons are now retrofittable (D22): on an initialized project,
`gov init --hooks`/`--ci` take an incremental path that pre-flights and
installs only the requested add-on and merges it into the manifest —
rules, gates, notes, skills, and the AGENTS.md reference line are never
touched, so retrofitting cannot reset customizations. Re-running is
idempotent; a foreign pre-push still aborts loud. uninstall keeps D10's
exact reversal but names, before deleting, every file that differs by a
single byte from its shipped template (rules.md plus the manifest-created
files that map back to a template). The Status field is closed to exactly
`implemented` — archived notes keep `Status: implemented` plus their
`Archived:` line per the archive procedure, so the directory remains the
only lifecycle fact and the field has no second state to express; both
notes READMEs (live and shipped template) state this.

## Alternatives considered

- Preserve customized files on uninstall — rejected: it would break D10's
  locked exact-reversal contract; warning without preserving keeps the
  contract honest and the loss visible.
- Allow Status ∈ {implemented, archived} — rejected: `archived/` is not
  checked by verify-notes, so a second value would hand the field a duty
  the directory already owns — two sources for one fact.

## Consequences

A project can adopt the runners at any time without re-init, and nobody
loses a customized rules file without reading its name on the way out. A
note drafting with a different Status now fails at the notes gate with the
offending value named, instead of carrying a decorative lie.
