#!/bin/sh
# gate: pairing
# Proves the optional pre-commit hook rejects (#110): with
# `gov init --hooks --pre-commit`, committing one side of a pair without
# re-confirming fails naming the scoped fix command; the fixed pair
# commits. Needs govrail installed (`pip install govrail`) — copy this
# specimen into your project and run `gov self-test --scope project`.
set -u
command -v gov >/dev/null 2>&1 || {
  echo "case-pre-commit-hook: govrail not installed (pip install govrail)" >&2
  exit 1
}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cd "$scratch" || exit 1
git init -q .
git config user.email t@t
git config user.name t
printf 'seed\n' > seed.txt
git add -A
git -c commit.gpgsign=false commit -qm init

gov init --hooks --pre-commit > out.txt 2>&1 || {
  echo "case-pre-commit-hook: init --hooks --pre-commit failed" >&2
  cat out.txt >&2
  exit 1
}
test -x .git/hooks/pre-commit || {
  echo "case-pre-commit-hook: the hook was not wired into .git/hooks" >&2
  exit 1
}

mkdir docs
printf 'hello\n' > docs/a.md
printf 'nihao\n' > docs/a.zh.md
gov verify-pairing --write docs/a.md > out.txt 2>&1 || {
  echo "case-pre-commit-hook: baselining the pair failed" >&2
  cat out.txt >&2
  exit 1
}
git add -A
git -c commit.gpgsign=false commit -qm baseline || {
  echo "case-pre-commit-hook: a confirmed pair failed the hook" >&2
  exit 1
}

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

gov verify-pairing --write docs/a.md > out.txt 2>&1 || {
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
