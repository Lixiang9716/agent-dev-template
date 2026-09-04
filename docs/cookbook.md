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

## Catch the drift at commit, not at push

The pre-push block works, but on a busy branch every pair edit costs a
blocked push first (issue #110's evidence). Install the optional
pre-commit hook — cheap content gates on the staged files only:

```sh
gov init --hooks --pre-commit   # add-on; --hooks alone stays push-stage
```

Now the same edit fails one stage earlier, at `git commit`, with the
same scoped fix inline — run it, re-stage, and the commit lands without
the push round-trip:

```
docs/foo.md: out of sync — re-confirm: gov verify-pairing --write docs/foo
verify_translation_pairing: 1 violation(s) in 1 staged pair(s)
```

Nothing paired staged? The hook is quiet. Repos that find commit hooks
intrusive simply do not pass `--pre-commit` — zero change at the commit
stage, the pre-push model untouched.

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

## A rebase left conflict markers in the diff

Symptom: `git add` during a rebase stages a file that still carries
`<<<<<<<` / `=======` / `>>>>>>>` blocks, and `git rebase --continue`
commits it without a word — git cannot tell a real marker from a
quoted one, so it stays silent. The conflict-markers gate ships in the
template's `all` mode and reads the changed files' content:

```sh
gov verify-conflict-markers            # changed files vs the auto base
gov verify-conflict-markers --staged   # only the index — pre-commit-light
```

Expected output when a marked file is in the diff (exit 1):

```
doc.md:3: conflict marker '<<<<<<<' — resolve the merge, or append 'gov:ignore-marker' to exempt a deliberate literal
doc.md:5: conflict marker '======='
doc.md:7: conflict marker '>>>>>>>'
verify_conflict_markers: 3 marker(s) in 1 file(s) — git will not police its own conflict text; the gate does (D38)
```

Escape hatch: a deliberate literal (a test fixture quoting markers, a
doc about merging) appends the token `gov:ignore-marker` to that line
and passes. A bare `=======` alone — a Markdown H1 setext underline —
is not a marker; it counts only beside a sibling marker in the same
file (D38).

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

## Parallel branches both want the next D-number

```sh
gov decision next --base origin/master   # the number merged history will show
gov decision add --from draft.md          # atomic append, validated before writing
gov verify-decisions --base origin/master
```

Two worktrees computing "next free" from the same base both get D39;
`--base` unions what already landed on the base branch, and the gate run
names the collision (`D39: number collision … renumber via gov decision
next --base`) instead of letting a duplicate row merge. Appending in the
single-file formats is atomic (temp file + replace) but still a textual
merge conflict across worktrees — configure
`.gov/decisions.json` `{"path": ".gov/decisions", "format": "dir"}`
(one file per decision) and appends become new files: parallel branches
merge with no conflict at all.

## Templates evolved — see, then adopt

```sh
gov init --upgrade            # per-file diffs; never writes
gov init --adopt all          # lands MISSING template files only
gov init --adopt-new gates.json  # merges NEW shipped gates into a
                                 # customized gates.json (by gate id)
gov whatsnew                  # what arrived since your init version
```

Modified files stay yours to merge (the two-step); pure additions land
with one command; a customized gates.json can absorb newly shipped gates
additively — local gates untouched, conflicting ids refused loudly
(D39); `--upgrade --json` lets an agent decide programmatically.

## Orchestrating several worktrees without cd

```sh
gov -C ../wt-x run --base master   # gates the wt-x tree, not this one
gov -C ../wt-x doctor
```

`-C <path>` (or `--path`, before the command; chainable like git's)
chdirs by value before dispatch, and the output header names the
resolved work-tree root — a wrong-tree invocation is visible, not just
valid. A nonexistent path fails loud (#121). Subcommands with their own
`--path` (verify-decisions, verify-rubric) keep it: theirs names a
file and comes after the command.

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
