# Agent Note: init --hooks and --ci — an execution path that ships with the plane

Status: implemented

## Problem

A governance plane's value is automatic execution, but `gov init` provided
none: no pre-push hook, no CI workflow. Every adopter hand-rolled the same
wiring (one reported hand-writing `.gov/hooks/pre-push` plus a symlink), and
each hand-roll was another chance to run the wrong command or lose the
hook on re-clone.

## Decision

`gov init --hooks` writes `.gov/hooks/pre-push` (the auditable copy, version
controlled) and wires an executable copy into `.git/hooks/pre-push`; both
say `exec gov run`, and the hook file carries a `# govrail:` marker.
`gov init --ci` generates `.github/workflows/gov.yml` (checkout, Python,
`pip install govrail`, `gov run`) only when that file does not exist. Both
add-ons pre-flight before init mutates anything: a foreign pre-push or a
missing `.git` aborts with exit 2 and leaves no half-initialized project;
the manifest records the workflow in `created` and the hook in `gitHooks`,
so `uninstall` reverses both exactly. A gov-owned pre-push is replaced
idempotently; a project's own `gov.yml` is never touched.

## Alternatives considered

- Ship hooks/CI by default — rejected: writing into `.git/` and `.github/`
  uninvited violates the non-invasive contract of init; add-ons must be
  opt-in flags.
- Symlink `.git/hooks/pre-push` to `.gov/hooks/pre-push` — rejected:
  symlinks survive poorly across clones, filesystems, and archives; a plain
  executable copy is boring and works everywhere.
- Only generate the files and let the user wire them — rejected: that is the
  hand-rolling the feature exists to remove.

## Consequences

Adopters get push-time enforcement with one flag and can still remove it
with `gov uninstall`. Because the hook runs `gov run` (the defaultMode),
teams control what pre-push enforces entirely from `gates.json` — the hook
file itself never needs editing.
