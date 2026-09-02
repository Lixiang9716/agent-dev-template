# Agent Note: wishes round IV — grade mode, pairing round-trip, decision half-life, coverage ledger, dry checks, per-gate trends

Status: implemented

## Problem

The review dossier had solved evidence-hunting but verdicts still had to
be hand-transcribed into the skill's format. A pairing failure cost
three steps and a full re-baseline, with no way to see which side moved
first. Decisions had no half-life — a D whose context quietly expired
stayed "current" forever. Rule 6's coverage was unledgered: whether
thirteen gates all had rejection cases was pure discipline (an adopter's
evalkit-tests nearly slipped through). A typo'd gate command waited for
the next ordinary change to explode as MISSING. And trend lacked a
single-gate view, a ref-anchored split, and a machine-readable upgrade
report.

## Decision

`gov review --grade` (D30): after the dossier, an interactive per-item
loop (p/f/s/q, fail prompts for evidence) that emits the code-review
skill's exact output contract — one line per graded item, the blocker
list, an explicit verdict; humans decide, the machine transcribes.
Pairing failures now carry the inline fix command for the named pair
only, and sidecars record last_confirmed plus each side's last-touch
commit, so drift reports say which side moved in which commit after
which confirmation. Decisions gain an optional review-by date: passed
dates print a review-due note (informational, like orphans); unparseable
values are violations. self-test ends with a coverage ledger: project
cases declare their gate with a `# gate: <id>` comment (shebang stays on
line one — a shebang-less case is named, no longer crashes the runner),
the report shows gate(n) with NONE — rule 6 for uncovered gates and
names stray gate ids. doctor resolves every gate command and reports
missing executables before a run ever reports MISSING. trend filters by
--gate and can split its early/late windows at a git ref's commit date;
`gov init --upgrade --json` emits exactly one JSON value for
programmatic adoption.

## Alternatives considered

- Auto-grading from the dossier — rejected: the grader must be the
  human or reviewing agent; the machine owns transcription, not verdicts.
- Overdue review-by as a violation — rejected: expiry means re-read,
  not wrong; informational strength matches orphans.
- Coverage gaps as failures — rejected: during ramp-up that pressure
  deletes gates instead of adding cases.

## Consequences

A review is now: run one command, read one dossier, answer p/f per
item — the transcription and formatting are gone. Pairing drift reads
like a sentence ("the zh side last moved in abc1234, confirmed
2026-09-01T..."), rule 6 has a ledger instead of faith, and a broken
gate command surfaces in doctor before it surfaces in a run.
