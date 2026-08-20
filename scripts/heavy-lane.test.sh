#!/usr/bin/env bash
# Heavy/light lane separation tests (bash twin of heavy-lane.test.ps1): the
# self-test gate skips heavy-marked suites in light mode (GATES_FORCE_HEAVY
# unset) with a counted skip line, the decision logic flips to "run" under
# GATES_FORCE_HEAVY=1, an unknown value fails loud naming it, and the pair
# gate rejects a heavy-marked entry whose twin files are missing. The suite
# itself is light: it never executes a heavy suite. A gate only guards if
# the regression actually fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh

# Recursion guard: this suite invokes self-test.sh once (section a), and
# self-test runs every *.test.sh — including this file. The inner instance
# closes immediately instead of re-triggering the whole suite.
if [[ ${HEAVY_LANE_GUARD:-0} == 1 ]]; then
  t_done
  exit $?
fi
export HEAVY_LANE_GUARD=1
unset GATES_FORCE_HEAVY

# Both scripts re-source lib.sh, which resets the check counters — they must
# be loaded before any check registers.
source scripts/self-test.sh 2>/dev/null
source scripts/verify-script-pairs.sh 2>/dev/null

# (a) Light mode: the real self-test gate skips heavy-marked suites with a
# counted, loud line and passes — the inner invocation is pinned to light so
# the assertion never depends on the ambient mode. On foreign soil (a
# scaffold) the manifest carries no heavy marks, and the same machinery must
# run every suite: the assertions follow the local manifest.
load_heavy_pairs
unset GATES_FORCE_HEAVY
out=$(bash scripts/self-test.sh 2>&1); rc=$?
expect_status 'light self-test exits 0' 0 $rc
if is_heavy_pair adopt-plane.test; then
  expect_contains 'light self-test skips the heavy suite loudly' "$out" 'skipped: heavy suite adopt-plane.test — GATES_FORCE_HEAVY=1 forces it in scheduled CI'
  expect_contains 'light self-test counts the skip' "$out" ', 1 skipped'
else
  expect_eq 'light self-test runs every suite when nothing is heavy' "$(printf '%s\n' "$out" | grep -c 'skipped: heavy suite')" 0
fi

# (b) The decision logic: heavy mode runs the heavy pair, light mode skips
# it, and a light pair is never skipped.
GATES_FORCE_HEAVY=1
heavy_lane_enabled
expect_status 'heavy_lane_enabled is true under =1' 0 $?
heavy_pair_skipped adopt-plane.test
expect_status 'heavy pair is not skipped under =1' 1 $?
unset GATES_FORCE_HEAVY
heavy_lane_enabled
expect_status 'heavy_lane_enabled is false when unset' 1 $?
heavy_pair_skipped adopt-plane.test
skip_rc=$?
if is_heavy_pair adopt-plane.test; then
  expect_status 'heavy pair is skipped in light mode' 0 $skip_rc
else
  expect_status 'an unmarked pair is never skipped in light mode' 1 $skip_rc
fi
heavy_pair_skipped verify-vocabulary.test
expect_status 'a light pair is never skipped' 1 $?
is_heavy_pair adopt-plane.test
heavy_rc=$?
if (( heavy_rc == 0 )); then
  expect_status 'the manifest marks adopt-plane.test heavy' 0 $heavy_rc
else
  expect_status 'the local manifest carries no heavy marks' 1 $heavy_rc
fi

# (c) The closed set is {unset, 1} with is-set semantics: an unknown value
# and the empty string both fail loud, naming the offending value.
out=$(GATES_FORCE_HEAVY=banana bash scripts/self-test.sh 2>&1); rc=$?
expect_status 'an unknown GATES_FORCE_HEAVY fails loud' 1 $rc
expect_contains 'the failure names the offending value' "$out" 'GATES_FORCE_HEAVY="banana": unknown value — the closed set is {unset, 1} (unset means light)'
unset GATES_FORCE_HEAVY
out=$(GATES_FORCE_HEAVY='' bash scripts/self-test.sh 2>&1); rc=$?
expect_status 'an empty GATES_FORCE_HEAVY fails loud' 1 $rc
expect_contains 'the empty-string failure names the value' "$out" 'GATES_FORCE_HEAVY="": unknown value — the closed set is {unset, 1}'
unset GATES_FORCE_HEAVY

# (d) The pair gate validates heavy marks in every mode: an entry whose twin
# files are missing, and a non-boolean heavy field, both fail loud.
tree=$(mktemp -d)
mkdir -p "$tree/scripts"
printf '#!/usr/bin/env bash\necho alpha\n' > "$tree/scripts/alpha.sh"
printf '#!/usr/bin/env pwsh\necho alpha\n' > "$tree/scripts/alpha.ps1"
printf '{\n  "alpha": {\n    "sh": "%s",\n    "pwsh": "%s",\n    "heavy": true\n  },\n  "ghost": {\n    "sh": "x",\n    "pwsh": "y",\n    "heavy": true\n  }\n}\n' \
  "$(git hash-object "$tree/scripts/alpha.sh")" \
  "$(git hash-object "$tree/scripts/alpha.ps1")" > "$tree/scripts/script-pairs.json"
PAIRS_VIOLATIONS=()
collect_state "$tree"
out=$(printf '%s\n' "${PAIRS_VIOLATIONS[@]}")
expect_contains 'a heavy entry with missing twins fails loud' "$out" 'ghost: heavy pair'
expect_contains 'the missing pair is also reported stale' "$out" 'manifest entry has no pair on disk'
rm -rf "$tree"

tree=$(mktemp -d)
mkdir -p "$tree/scripts"
printf '#!/usr/bin/env bash\necho alpha\n' > "$tree/scripts/alpha.sh"
printf '#!/usr/bin/env pwsh\necho alpha\n' > "$tree/scripts/alpha.ps1"
printf '{\n  "alpha": {\n    "sh": "%s",\n    "pwsh": "%s",\n    "heavy": "yes"\n  }\n}\n' \
  "$(git hash-object "$tree/scripts/alpha.sh")" \
  "$(git hash-object "$tree/scripts/alpha.ps1")" > "$tree/scripts/script-pairs.json"
PAIRS_VIOLATIONS=()
collect_state "$tree"
out=$(printf '%s\n' "${PAIRS_VIOLATIONS[@]}")
expect_contains 'a non-boolean heavy field fails loud' "$out" '"heavy" must be a boolean'
rm -rf "$tree"

t_done
