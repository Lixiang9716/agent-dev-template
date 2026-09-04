# Agent Note: the optional pre-commit hook — pairing drift surfaces at commit, not push

Status: implemented

Related: D41, issue #110

## Problem

Radiant hit the same round-trip twice: edit a bilingual pair → commit →
push → the pre-push hook blocks on pairing drift with the inline fix
command → run the scoped `--write` → amend → push again. The check
works, but the feedback arrives one stage later than it could — on a
busy branch this is one blocked push per pair edit. The commit stage
had no cheap, opt-in way to see the same drift the push stage reports.

## Decision

`gov init --hooks --pre-commit` additionally installs an OPTIONAL
pre-commit hook (D39) that runs only the cheap content gates on the
staged files: `gov verify-pairing --staged` — new in this change, it
resolves the git index to the in-scope pairs it touches (staging the
source side, the counterpart side, or the `.i18n.yaml` record all count)
and re-checks only those pairs' sidecar freshness, failing with the
scoped fix command inline — and `verify-conflict-markers --staged`
(shipped in 0.15.0). An index with nothing paired staged is a quiet
pass. The full gate DAG never runs at commit time (rule 1 gives the
push the smallest sufficient set; a commit must stay fast). A lone
`--pre-commit` fails loud — it rides with `--hooks`; a foreign
pre-commit is never overwritten, same as pre-push. Both hooks land in
the manifest's `gitHooks` and `uninstall` reverses them exactly;
`gov doctor` treats the pre-commit hook as opt-in (absent is a choice,
present is checked for executability in both copies). The hook template
scrubs the inherited GIT_* environment (D32's #20 leak) and runs its
two gates without `exec`, so the shell survives for the second call.
Without the flag, repositories see zero change at the commit stage.

## Alternatives considered

- Installing pre-commit by default — rejected: the issue asks for
  opt-in; repos that find commit-stage hooks intrusive stay on the
  pre-push model, and a governance plane that slows every commit
  uninvited spends goodwill it needs elsewhere.
- Running the full gate DAG at commit — rejected: commits must be
  fast; the push/CI own the full matrix (rule 1, D32's rejected
  "hooks run everything" alternative again).
- A new `gov verify-pairing-staged` subcommand — rejected:
  `--staged` matches the conflict-markers gate's existing shape; a
  second CLI spelling for the same narrowing forks the vocabulary.
- Checking freshness by mtime instead of blob hashes — rejected:
  pairing's contract is git blob identity (the sidecar pins blob
  hashes); a second freshness notion would disagree with the push-stage
  verdict the hook is meant to front-run.
