#!/usr/bin/env bash
# Rejection tests for the adoption proof (bash twin of adopt-plane.test.ps1):
# the full run passes end to end with deterministic output, each injected
# mutation fails the verify run naming its stage, --clean is instance-scoped
# and never touches a foreign root, and every temporary directory is cleaned
# up (hermetic contract). A gate only guards if the regression actually
# fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh

# The suite owns a private temp root: every child instance scopes its
# transient files under it, so concurrent suites (the self-test and probe
# lanes run adopt-plane suites in parallel) cannot interfere with each other.
SUITE_TMP=$(mktemp -d) || exit 1
export TMPDIR=$SUITE_TMP
trap 'rm -rf "$SUITE_TMP"' EXIT

# Number of entries in the suite's own temp root: child instances must leave
# it exactly as the suite arranges it.
suite_entries() {
  ls -A "$SUITE_TMP" | grep -c .
}

# The mutations the verify battery must detect (same shapes the battery
# itself injects: the proof must reject a mutation injected from outside).
inject_pairing() { printf '\nadopt-plane: pairing mutation\n' >> "$1/README.zh.md"; }
inject_vocabulary() { printf '\nThis statement is verified by nothing.\n' >> "$1/docs/adoption.md"; }
inject_notes() { printf 'garbage\n' > "$1/.agents/notes/implemented/architecture/2026-08-19-mutation-note.md"; }
inject_script_pairs() { printf '\n# adopt-plane: drift mutation\n' >> "$1/scripts/adopt-plane.sh"; }
inject_plane_file() { rm -f "$1/.gitattributes"; }

expect_eq 'the suite temp root starts empty' "$(suite_entries)" 0

# --clean is instance-scoped: it must never touch a foreign root, and its own
# transient root is gone afterwards.
foreign=$(mktemp -d "$SUITE_TMP/adopt-plane.foreign.XXXXXX")
bash scripts/adopt-plane.sh --clean >/dev/null 2>&1
expect_eq '--clean never touches a foreign root' "$(test -d "$foreign" && echo kept || echo removed)" kept
expect_eq '--clean leaves no residue of its own' "$(suite_entries)" 1

# (a) The full run passes end to end with deterministic output.
out=$(bash scripts/adopt-plane.sh 2>&1); rc=$?
expect_status 'full run exits 0' 0 $rc
expect_eq 'full run output is line-deterministic' "$(printf '%s\n' "$out" | grep -c .)" 12
expect_contains 'full run reports the PASS summary' "$out" 'adopt-plane: PASS'
expect_contains 'full run proves gates all green' "$out" 'adopt-plane: gate all PASS'
expect_contains 'full run proves the hook install' "$out" 'adopt-plane: install-hooks PASS'
expect_contains 'full run proves the pre-commit commit' "$out" 'adopt-plane: pre-commit PASS'
expect_contains 'full run rejects the pairing mutation' "$out" 'adopt-plane: FAIL stage=pairing'
expect_contains 'full run rejects the vocabulary mutation' "$out" 'adopt-plane: FAIL stage=vocabulary'
expect_contains 'full run rejects the notes mutation' "$out" 'adopt-plane: FAIL stage=notes'
expect_contains 'full run rejects the script-pairs mutation' "$out" 'adopt-plane: FAIL stage=script-pairs'
expect_contains 'full run proves pre-commit rejection' "$out" 'adopt-plane: pre-commit REJECT'
expect_eq 'full run leaves no residue in the suite root' "$(suite_entries)" 1

# (b) Each mutation, injected into a fresh scaffold, fails the verify run
# naming its stage; the verified dir is removed.
mutation_case() { # <stage> <inject-fn> <commit-proof 0|1> <expected-line>
  local stage=$1 inject=$2 commit_proof=$3 expected=$4 dir out rc
  dir=$(mktemp -d)
  bash scripts/adopt-plane.sh --scaffold "$dir" >/dev/null 2>&1
  expect_status "scaffold for stage=$stage exits 0" 0 $?
  "$inject" "$dir"
  out=$(bash scripts/adopt-plane.sh --verify "$dir" 2>&1); rc=$?
  expect_status "verify for stage=$stage exits non-zero" 1 $rc
  expect_contains "verify names stage=$stage" "$out" "$expected"
  if (( commit_proof )); then
    expect_contains "verify proves pre-commit rejection for stage=$stage" "$out" 'adopt-plane: pre-commit REJECT'
  fi
  expect_eq "verify removes the scaffold dir for stage=$stage" "$(test -d "$dir" && echo kept || echo removed)" removed
}

mutation_case pairing inject_pairing 1 'adopt-plane: FAIL stage=pairing'
mutation_case vocabulary inject_vocabulary 1 'adopt-plane: FAIL stage=vocabulary'
mutation_case notes inject_notes 0 'adopt-plane: FAIL stage=notes'
mutation_case script-pairs inject_script_pairs 0 'adopt-plane: FAIL stage=script-pairs'
mutation_case plane-file inject_plane_file 0 'adopt-plane: FAIL plane-file .gitattributes'

# (c) The suite leaves no residue and cleans its own fixture.
expect_eq 'no residue at the end of the suite' "$(suite_entries)" 1
rm -rf "$foreign"
expect_eq 'the suite cleans its own fixture' "$(suite_entries)" 0

t_done
