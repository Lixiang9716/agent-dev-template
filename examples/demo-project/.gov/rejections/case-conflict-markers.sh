#!/bin/sh
# gate: conflict-markers
# Proves the conflict-markers gate rejects (a real one, not a stub): a
# conflicted file must go red naming file:line; the ignore token must
# exempt a deliberate literal. Needs govrail installed (`pip install
# govrail`) — copy this specimen into your project and run
# `gov self-test --scope project`.
set -u
command -v gov >/dev/null 2>&1 || {
  echo "case-conflict-markers: govrail not installed (pip install govrail)" >&2
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

printf 'intro\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> side\n' > doc.md
if gov verify-conflict-markers > out.txt 2>&1; then
  echo "case-conflict-markers: a marked file passed the gate" >&2
  exit 1
fi
grep -q 'doc.md:2' out.txt || {
  echo "case-conflict-markers: finding does not name file:line" >&2
  cat out.txt >&2
  exit 1
}

printf 'resolved by hand\n' > doc.md
printf '<<<<<<< HEAD gov:ignore-marker\n' > lit.md
if gov verify-conflict-markers > out.txt 2>&1; then
  echo "case-conflict-markers: rejection proof holds"
  exit 0
fi
echo "case-conflict-markers: the ignore token was not tolerated" >&2
cat out.txt >&2
exit 1
