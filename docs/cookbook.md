# Cookbook — tasks, commands, what to expect

English | [中文](cookbook.zh.md)

Recipes are task-shaped: a symptom or goal, the command, what good
output looks like. The reference lives in the README; this is the
"what do I do now" layer.

## Install and first day

```sh
gov init --project .            # rules, gates, notes, skills land
gov doctor                      # PATH, python, hooks, gates schema — sound?
gov run                         # pairing runs advisory until baselined
```

A fresh install must not go red. When you have documents to pair:

```sh
gov verify-pairing --write      # baseline every pair (partial: records
                                # what it can, reports the rest)
```

## Pairing went red after an edit

The error carries its own fix — copy it:

```
docs/foo.md: out of sync — re-confirm: gov verify-pairing --write docs/foo
(the en side last moved in a1b2c3d, confirmed 2026-09-01T10:00:00+00:00)
```

`--write <stem>` re-baselines ONLY the named pair. The parenthetical
says which side moved, in which commit, after which confirmation —
check the translation before re-confirming, not after.

## Add a gate, end to end

1. Define it in `gates.json` (unknown keys abort loud — typos cannot
   silently park):

```json
{"id": "source-limits", "command": ["./check_limits.sh"],
 "paths": ["src/**", "eval/**"]}
```

2. Prove it can reject — a rejection case under `.gov/rejections/`,
   shebang on line 1, gate declaration within the first five:

```sh
#!/bin/sh
# gate: source-limits
# introduce an oversized module, assert the gate goes red, restore
...
```

3. Check the ledger: `gov self-test --scope project` ends with
   `source-limits(1)` — not `NONE — rule 6`.

## Experiments are not runtime code

`.gov/surfaces.json`:

```json
{"eval/**": {"surface": "experiments", "gates": ["source-limits"]}}
```

Now `gov change-scope` on an eval-only change suggests exactly
`source-limits` — no product-plane noise.

## Review a PR

```sh
gov review --base origin/main --grade
```

One command: the dossier (scope, notes, recall, rubric), then
interactive grading (`p`/`f`/`s`/`q`; `f` asks for evidence), then the
verdict block — graded lines, blockers, `verdict: approve` or
`request changes`. The human decides; the machine transcribes.

## Write a note

```sh
gov note new --class process --ref D6 "Why we chose x"
gov note check        # format + placement + dangling D-refs, pre-commit-light
```

A wrong class or a dangling D-ref is refused before any prose is
invested. Without a decisions table the D-ref is announced unchecked —
never silently skipped.

## The decisions table

`gov verify-decisions` guards numbering (unique, contiguous),
alternatives (every D records what it beat), and reports orphans
(no note references — informational). A decision with a context that
may expire carries `review-by: 2027-01-01`; past dates print a
review-due note.

## Templates evolved — see, then adopt

```sh
gov init --upgrade            # per-file diffs; never writes
gov init --adopt all          # lands MISSING template files only
gov whatsnew                  # what arrived since your init version
```

Modified files stay yours to merge (the two-step); pure additions land
with one command; `--upgrade --json` lets an agent decide
programmatically.

## Reading a trend mover

Runs record by default (`.gov/history/`, gitignored). `gov trend`
compares window halves per gate; a mover (`×1.8 ↑`) is a question to
investigate, not a verdict:

```sh
gov trend --gate tests --base v1.2.0   # before/after that release
```

## Long session, drowning in untracked-file warnings

```sh
gov verify-note-presence --staged     # index only; silent when clean
```

Lists fold past five (`…and N more`).

## Something feels off in the environment

```sh
gov doctor
```

Names problems rule-5 style: gov unreachable on PATH, hook not
executable, a gate command that does not resolve, schema typos,
decisions that no longer parse.
