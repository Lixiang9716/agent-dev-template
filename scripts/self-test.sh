#!/usr/bin/env bash
# Run every scripts/*.test.sh, each in its own bash process, and fail if any
# fails. This is the `self-test` gate's sh-side command; self-test.ps1 runs
# the pwsh twin suite. A gate only guards if the regression actually fails it.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

total=0 failed=0
for t in "$ROOT"/scripts/*.test.sh; do
  [[ -f $t ]] || continue
  (( total++ ))
  if bash "$t"; then
    echo "self-test: PASS ${t#"$ROOT"/}"
  else
    echo "self-test: FAIL ${t#"$ROOT"/}" >&2
    (( failed++ )) || true
  fi
done

(( total > 0 )) || { echo 'self-test: no test files found under scripts/*.test.sh' >&2; exit 1; }
printf 'self-test: %d suite(s), %d failed\n' "$total" "$failed"
(( failed == 0 ))
