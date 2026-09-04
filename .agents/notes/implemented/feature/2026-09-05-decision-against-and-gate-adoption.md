# Agent Note: `decision --against` stale-base warning and doctor's unadopted-gate naming

Status: implemented

Related: D48 (issue #147), builds on D40 (#107)

## Problem

A radiant batch ran 7 parallel agent branches cut from `main@6df5211`
while a second session landed D39–D42 on origin/main. The branches
numbered from their local tables; the result was 3 PRs closed as
superseded, 4 mid-flight renumberings, and 2 force-push rebase rounds.
Two existing mechanisms should have caught it and neither did:

1. `decision next/add --base` (D40) unions a ref's numbers — but the
   union is silent about the thing that matters: the local table is
   missing rows the ref has, i.e. the base is stale and the table being
   numbered from is blind. And without the flag, only the local
   worktree is ever read.
2. `verify-decisions --base` names parallel-branch collisions — but the
   gate was not in the project's gates.json at all. It predates the
   gate's release, nothing ever prompted its adoption, and a gate
   absent from gates.json is invisible to every run. The one check
   that would have named the collision never ran.

## Decision

Three moves, all soft or naming — none changes an exit code:

- `gov decision next|add --against <ref>`: an alias of `--base`
  (same dest; the issue's requested surface and the shipped vocabulary
  are one semantic). When a ref is given, `ref − local` non-empty
  prints `your base is N rows behind '<ref>' (missing …) — rebase
  before numbering` to stderr; `next`'s stdout stays exactly the
  number list.
- `decision add` carries the same soft warning: the union-allocated
  row is still written, exit 0 — awareness, not a block.
- `gov doctor` gains a `gate-adoption` check (a note, never a
  problem): it inventories the gates this govrail version ships — the
  template gates (adoption path `gov init --adopt-new gates.json`,
  D39) plus the hand tools whose paths are project-specific
  (`verify-decisions`, `verify-rubric`, `verify-doc-sync`) — and names
  any absent from the project's gates.json, by gate id or command
  token. A gate parked via `enabled: false` counts as adopted: parking
  is the loud, deliberate mechanism (D24). The flag registry
  (audit-notes) gains `--against`.

## Alternatives considered

- Auto-detecting a ref (upstream / origin HEAD) when no flag is passed
  — rejected: guessing intent is the recurring rejected stance (D11),
  and the silent fallback branches (no upstream, offline, ref without
  a decisions source) would be harder to explain than an explicit
  flag's absence. Union and warning both hang off the explicit ref.
- Making `--against` a second flag with its own semantics — rejected:
  two declarations of one meaning is the vocabulary fork D41/D44
  rejected; an alias keeps one semantic with near-zero cost.
- Making unadopted gates a doctor *problem* (exit 1) — rejected:
  adoption is deliberate (D17/D28 — the plane is a floor, growth is
  event-driven); absence is a state to see, not a malfunction, and a
  defined-but-unmoded gate is already refused loudly by D24's
  reachability check.
- Putting `verify-decisions` into the injection template so template
  delta covers it — rejected: D28 adjudicated it out (its paths are
  project-specific); doctor naming it with the command to wire is the
  discovery layer that respects that ruling.
