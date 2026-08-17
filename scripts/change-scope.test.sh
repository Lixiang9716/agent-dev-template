#!/usr/bin/env bash
# change-scope contract tests: bash twin of change-scope.test.ps1, run by
# real throwaway git repository: the four path classes partition real states,
# and an unresolvable base fails loud instead of producing an empty record.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh
source scripts/change-scope.sh 2>/dev/null

# Create a git repo with an initial commit on main.
temp_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q --initial-branch=main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  printf 'seed\n' > "$dir/seed.txt"
  git -C "$dir" add .
  git -C "$dir" commit -q -m seed
  REPLY_REPO=$dir
}

# The four path classes partition committed, staged, unstaged, untracked.
temp_repo
repo=$REPLY_REPO
printf 'committed\n' > "$repo/committed.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m committed
printf 'staged\n' > "$repo/staged.txt"
git -C "$repo" add .
# An unstaged change must modify a tracked file; a never-added file is untracked.
printf 'committed, then modified\n' > "$repo/committed.txt"
printf 'untracked\n' > "$repo/untracked.txt"
scope=$(collect_scope "$repo" HEAD~1)
expect_contains 'format version pinned' "$scope" '"formatVersion": 1'
expect_contains 'committed class lists the committed path' "$scope" '"committed": [
    "committed.txt"'
expect_contains 'staged class lists the staged path' "$scope" '"staged": [
    "staged.txt"'
expect_contains 'unstaged class lists the tracked modification' "$scope" '"unstaged": [
    "committed.txt"'
expect_contains 'untracked class lists the never-added path' "$scope" '"untracked.txt"'
rm -rf "$repo"

# A clean tree reports empty path classes and a resolvable merge base.
temp_repo
repo=$REPLY_REPO
scope=$(collect_scope "$repo" HEAD)
expect_contains 'clean tree has empty committed' "$scope" '"committed": []'
expect_contains 'clean tree has empty staged' "$scope" '"staged": []'
expect_contains 'clean tree has empty unstaged' "$scope" '"unstaged": []'
expect_contains 'clean tree has empty untracked' "$scope" '"untracked": []'
head_sha=$(git -C "$repo" rev-parse HEAD)
expect_contains 'merge base equals head on a clean tree' "$scope" "\"mergeBaseSha\": \"$head_sha\""
rm -rf "$repo"

# An unresolvable base fails loud with the git error.
temp_repo
repo=$REPLY_REPO
out=$(collect_scope "$repo" no-such-ref 2>&1)
expect_status 'unresolvable base fails' 1 $?
expect_contains 'unresolvable base names the git command' "$out" 'rev-parse'
rm -rf "$repo"

t_done
