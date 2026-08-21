#!/usr/bin/env bash
# Run every scripts/*.test.sh, each in its own bash process, and fail if any
# fails. This is the `self-test` gate's sh-side command; self-test.ps1 runs
# the pwsh twin suite. A gate only guards if the regression actually fails it.
#
# Heavy lane: pairs marked "heavy" in scripts/script-pairs.json (one home,
# consumed by the self-test and pair gates alike) are skipped in light mode
# — GATES_FORCE_HEAVY unset, the default — with a counted, loud skip line;
# GATES_FORCE_HEAVY=1 (closed set {unset, 1}; any other value fails loud
# naming it) runs them. CI owns the heavy lane on a 12-hour schedule and
# forces it on any push or PR whose diff touches the heavy channel itself.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

MANIFEST_REL=scripts/script-pairs.json

# Validate the GATES_FORCE_HEAVY closed set {unset, 1}; fails loud otherwise.
validate_heavy_env() {
  # Is-set semantics: the empty string is a set value, not an unset one, so
  # the closed set is exactly {unset, 1} — anything else, '' included, fails
  # loud naming it.
  if [[ ${GATES_FORCE_HEAVY+x} == x && $GATES_FORCE_HEAVY != 1 ]]; then
    printf 'self-test: GATES_FORCE_HEAVY="%s": unknown value — the closed set is {unset, 1} (unset means light)\n' "$GATES_FORCE_HEAVY" >&2
    return 1
  fi
  return 0
}

# True when the heavy lane is forced.
heavy_lane_enabled() { [[ ${GATES_FORCE_HEAVY:-} == 1 ]]; }

# Load the heavy pair names from the manifest into HEAVY_PAIRS. A missing or
# malformed manifest fails loud — the light/heavy decision must never guess.
load_heavy_pairs() {
  HEAVY_PAIRS=()
  local raw
  raw=$(<"$ROOT/$MANIFEST_REL") || {
    printf 'self-test: %s is missing — the heavy-lane decision cannot be made\n' "$MANIFEST_REL" >&2
    return 1
  }
  json_parse "$raw" || {
    printf 'self-test: %s: %s\n' "$MANIFEST_REL" "$JSON_ERROR" >&2
    return 1
  }
  json_keys '$'
  local key
  for key in "${REPLY_LIST[@]+"${REPLY_LIST[@]}"}"; do
    if json_get "\$.$key.heavy" 2>/dev/null && [[ $REPLY == true ]]; then
      HEAVY_PAIRS+=("$key")
    fi
  done
  return 0
}

# True when $1 is a heavy pair.
is_heavy_pair() { # <pair-name>
  local pair
  for pair in "${HEAVY_PAIRS[@]+"${HEAVY_PAIRS[@]}"}"; do
    [[ $pair == "$1" ]] && return 0
  done
  return 1
}

# True when $1 (a pair name) must be skipped in the current mode: light mode
# skips heavy pairs; the forced heavy lane runs everything.
heavy_pair_skipped() { # <pair-name>
  heavy_lane_enabled && return 1
  is_heavy_pair "$1"
}

self_test_main() {
  validate_heavy_env || return 1
  load_heavy_pairs || return 1
  local total=0 failed=0 skipped=0 t name
  for t in "$ROOT"/scripts/*.test.sh; do
    [[ -f $t ]] || continue
    (( total++ ))
    name=$(basename "$t" .sh)
    if heavy_pair_skipped "$name"; then
      printf 'skipped: heavy suite %s — GATES_FORCE_HEAVY=1 forces it in scheduled CI\n' "$name"
      (( skipped++ )) || true
      continue
    fi
    out=$(bash "$t" 2>&1); rc=$?
    if (( rc == 0 )); then
      echo "self-test: PASS ${t#"$ROOT"/}"
      # Re-surface the suite's loud skip lines — a skipped probe must never
      # look like full coverage (the gate prints 'skipped:' lines from a
      # passing self-test).
      grep 'skipped:' <<< "$out" || true
    else
      # Evidence over pointers: the failure tail names the failing check.
      tail_join "$out" 15
      echo "self-test: FAIL ${t#"$ROOT"/} (tail: $REPLY)" >&2
      (( failed++ )) || true
    fi
  done

  (( total > 0 )) || { echo 'self-test: no test files found under scripts/*.test.sh' >&2; return 1; }
  if (( skipped > 0 )); then
    printf 'self-test: %d suite(s), %d failed, %d skipped\n' "$total" "$failed" "$skipped"
  else
    printf 'self-test: %d suite(s), %d failed\n' "$total" "$failed"
  fi
  (( failed == 0 ))
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  self_test_main "$@"
fi
