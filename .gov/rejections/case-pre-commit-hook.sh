#!/bin/sh
# gate: pairing
# Proves the optional pre-commit hook rejects (#110): with
# `gov init --hooks --pre-commit` installed, `git commit` of a pair whose
# sidecar is stale fails naming the scoped fix command, and the fixed
# pair commits. Repos without the flag keep the pre-push model — that
# half is pinned in tests/test_pre_commit_hook.py.
set -u
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# Resolve the govrail package from this repository (self-test runs us
# with the repository root as cwd; `gov` may not be on PATH here).
repo_root=$(pwd)

cd "$scratch" || exit 1
git init -q .
git config user.email t@t
git config user.name t
printf 'seed\n' > seed.txt
git add -A
git -c commit.gpgsign=false commit -qm init

# Deterministic hook resolution: GOV_BIN wins over PATH/module fallback.
export GOV_BIN="python3 -m gov"
export PYTHONPATH="$repo_root"

if python3 -m gov init --hooks --pre-commit > out.txt 2>&1; then
  :
else
  echo "case-pre-commit-hook: init --hooks --pre-commit failed" >&2
  cat out.txt >&2
  exit 1
fi
test -x .git/hooks/pre-commit || {
  echo "case-pre-commit-hook: the hook was not wired into .git/hooks" >&2
  exit 1
}

# A confirmed pair, committed through the hook (must pass).
mkdir docs
printf 'hello\n' > docs/a.md
printf 'nihao\n' > docs/a.zh.md
python3 -m gov verify-pairing --write docs/a.md > out.txt 2>&1 || {
  echo "case-pre-commit-hook: baselining the pair failed" >&2
  cat out.txt >&2
  exit 1
}
git add -A
git -c commit.gpgsign=false commit -qm baseline || {
  echo "case-pre-commit-hook: a confirmed pair failed the hook" >&2
  exit 1
}

# The issue's evidence: edit one side, stage it, commit — one stage
# earlier than push, with the scoped fix command inline.
printf 'hello v2\n' > docs/a.md
git add docs/a.md
if git -c commit.gpgsign=false commit -qm drift > out.txt 2>&1; then
  echo "case-pre-commit-hook: a stale sidecar committed without complaint" >&2
  exit 1
fi
grep -q 'gov verify-pairing --write docs/a.md' out.txt || {
  echo "case-pre-commit-hook: the block does not name the scoped fix command" >&2
  cat out.txt >&2
  exit 1
}

# The scoped fix closes the loop: re-stage, commit lands.
python3 -m gov verify-pairing --write docs/a.md > out.txt 2>&1 || {
  echo "case-pre-commit-hook: the scoped fix failed" >&2
  cat out.txt >&2
  exit 1
}
git add -A
if git -c commit.gpgsign=false commit -qm drift > out.txt 2>&1; then
  echo "case-pre-commit-hook: rejection proof holds"
  exit 0
fi
echo "case-pre-commit-hook: the fixed pair still could not commit" >&2
cat out.txt >&2
exit 1
