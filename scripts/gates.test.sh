#!/usr/bin/env bash
# Scheduler self-tests (bash twin of gates.test.ps1). These pin the contract
# the gates aggregate relies on: invalid graphs are rejected before any child
# starts, failures propagate as skips with the cause, allowFailure stays
# non-blocking, and per-shell command slots must name every shell. A gate only
# guards if the regression actually fails it — every rejection rule here has
# a check that proves it fires.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/gates.sh 2>/dev/null

# Validate a config in a subshell; dies print `gates: invalid gates.json: ...`.
expect_reject() { # <description> <json> <expected-fragment>
  local out rc
  out=$(bash -c 'source scripts/gates.sh 2>/dev/null; gates_validate "$1"' _ "$2" 2>&1)
  rc=$?
  expect_status "$1" 1 "$rc"
  expect_contains "$1 message" "$out" "gates: invalid gates.json: $3"
}

expect_accept() { # <description> <json>
  local out rc
  out=$(bash -c 'source scripts/gates.sh 2>/dev/null; gates_validate "$1"' _ "$2" 2>&1)
  rc=$?
  expect_status "$1" 0 "$rc"
}

cfg() { printf '{"modes":{"all":[%s]},"gates":[%s]}' "$1" "$2"; }

expect_reject 'empty gate list rejected' \
  '{"modes":{"all":[]},"gates":[]}' \
  'gate list is empty'
expect_reject 'duplicate gate ids rejected' \
  "$(cfg '' '{"id":"a","command":["true"]},{"id":"a","command":["true"]}')" \
  'duplicate gate id "a"'
expect_reject 'unknown dependency rejected' \
  "$(cfg '"a"' '{"id":"a","command":["true"],"needs":["ghost"]}')" \
  'gate "a" depends on unknown gate "ghost"'
expect_reject 'two-gate cycle rejected' \
  "$(cfg '"a"' '{"id":"a","command":["true"],"needs":["b"]},{"id":"b","command":["true"],"needs":["a"]}')" \
  'dependency cycle'
expect_reject 'self-cycle rejected' \
  "$(cfg '"self"' '{"id":"self","command":["true"],"needs":["self"]}')" \
  'dependency cycle'
expect_reject 'three-gate cycle rejected' \
  "$(cfg '"a"' '{"id":"a","command":["true"],"needs":["b"]},{"id":"b","command":["true"],"needs":["c"]},{"id":"c","command":["true"],"needs":["a"]}')" \
  'dependency cycle'
expect_reject 'empty command array rejected' \
  "$(cfg '"a"' '{"id":"a","command":[]}')" \
  'gate "a" needs a non-empty command string array'
expect_reject 'non-array command rejected' \
  "$(cfg '"a"' '{"id":"a","command":"true"}')" \
  'gate "a" needs a non-empty command string array'
expect_reject 'mode with unknown gate rejected' \
  '{"modes":{"all":["a"],"extra":["ghost"]},"gates":[{"id":"a","command":["true"]}]}' \
  'mode "extra" must be a non-empty array of known gate ids'
expect_reject 'missing modes.all rejected' \
  '{"modes":{"quick":["a"]},"gates":[{"id":"a","command":["true"]}]}' \
  'modes must define "all"'
expect_reject 'missing pwsh variant rejected' \
  "$(cfg '"a"' '{"id":"a","command":{"sh":["true"]}}')" \
  'gate "a" command must declare both "sh" and "pwsh" variants'
expect_reject 'unknown shell variant rejected' \
  "$(cfg '"a"' '{"id":"a","command":{"sh":["true"],"pwsh":["true"],"node":["true"]}}')" \
  'gate "a" command declares unknown shell "node"; the closed set is sh, pwsh'
expect_reject 'empty variant array rejected' \
  "$(cfg '"a"' '{"id":"a","command":{"sh":["true"],"pwsh":[]}}')" \
  'gate "a" "pwsh" command must be a non-empty string array'
expect_accept 'complete per-shell variants accepted' \
  "$(cfg '"a"' '{"id":"a","command":{"sh":["true"],"pwsh":["pwsh","-Version","1"]}}')"

# The bash port runs the sh variant; the pwsh variant is validated, not run.
out=$(bash -c 'source scripts/gates.sh 2>/dev/null; gates_validate "$1" && printf "%s" "${G_CMD[a]}"' _ \
  "$(cfg '"a"' '{"id":"a","command":{"sh":["echo","sh-ran"],"pwsh":["echo","pwsh-ran"]}}')")
expect_eq 'bash port selects the sh variant' "$out" $'echo\x01sh-ran'

# --- scheduling ----------------------------------------------------------------

# A failing dependency skips its dependents with the cause.
gates_validate "$(cfg '"root","child","grandchild"' \
  '{"id":"root","command":["bash","-c","exit 3"]},
   {"id":"child","command":["true"],"needs":["root"]},
   {"id":"grandchild","command":["true"],"needs":["child"]}')" || exit 1
G_SELECTED=(root child grandchild)
run_gates 2 >/dev/null 2>&1
rm -rf "$GATE_TMPDIR"
expect_eq 'failing root is failed' "${R_STATUS[root]}" failed
expect_eq 'dependent is skipped' "${R_STATUS[child]}" skipped
expect_eq 'skip reason names the dependency' "${R_REASON[child]}" 'dependency failed or skipped: root'
expect_eq 'transitive dependent is skipped' "${R_STATUS[grandchild]}" skipped

# A dependent gate runs only after its dependency passes (absolute marker).
dir=$(mktemp -d)
gates_validate "$(cfg '"produce","consume"' \
  "{\"id\":\"produce\",\"command\":[\"bash\",\"-c\",\"touch $dir/marker\"]},
   {\"id\":\"consume\",\"command\":[\"bash\",\"-c\",\"test -f $dir/marker\"],\"needs\":[\"produce\"]}")" || exit 1
G_SELECTED=(produce consume)
run_gates 4 >/dev/null 2>&1
rm -rf "$GATE_TMPDIR"
expect_eq 'producer passed' "${R_STATUS[produce]}" passed
expect_eq 'consumer passed after producer' "${R_STATUS[consume]}" passed
rm -rf "$dir"

# allowFailure keeps a failed gate out of the blocking set.
gates_validate "$(cfg '"observational"' \
  '{"id":"observational","command":["bash","-c","exit 1"],"allowFailure":true}')" || exit 1
G_SELECTED=(observational)
run_gates 1 >/dev/null 2>&1
rm -rf "$GATE_TMPDIR"
expect_eq 'observational gate still fails' "${R_STATUS[observational]}" failed
if result_blocking observational; then expect_eq 'allowFailure not blocking' 'blocking' 'not blocking'; else expect_eq 'allowFailure not blocking' ok ok; fi

# A signal kill is reported with the signal fact.
gates_validate "$(cfg '"self-kill"' \
  '{"id":"self-kill","command":["bash","-c","kill -9 $$"]}')" || exit 1
G_SELECTED=(self-kill)
run_gates 1 >/dev/null 2>&1
rm -rf "$GATE_TMPDIR"
expect_eq 'signal kill is failed' "${R_STATUS[self-kill]}" failed
expect_eq 'signal reason names SIGKILL' "${R_REASON[self-kill]}" 'signal SIGKILL'
if result_blocking self-kill; then expect_eq 'signal kill blocking' blocking blocking; else expect_eq 'signal kill blocking' not-blocking blocking; fi

# A mode selecting a gate whose needs are unselected fails loud, not silently.
gates_validate '{"modes":{"all":["a","b"],"lonely":["b"]},"gates":[{"id":"a","command":["true"]},{"id":"b","command":["true"],"needs":["a"]}]}' || exit 1
G_SELECTED=(b)
out=$(trap 'rm -rf "$GATE_TMPDIR"' EXIT; run_gates 1 2>&1)
expect_contains 'unselected dependency stalls loud' "$out" 'validated graph stalled without a failed dependency'

# A passing gate that emitted a loud skip surfaces the skip line — a skipped
# probe is degraded verification and must never look like full coverage
# (AGENTS.md rule 4).
gates_validate "$(cfg '"skippy"' '{"id":"skippy","command":["bash","-c","echo \"probe skipped: alpha — pwsh not on PATH; cross-port behavioral consistency is verified in CI (GATES_FORCE_PROBE=1)\""]}')" || exit 1
G_SELECTED=(skippy)
GATE_VERBOSE=0 out=$(trap 'rm -rf "$GATE_TMPDIR"' EXIT; run_gates 1 2>&1)
expect_contains 'a passing gate surfaces its probe skip line' "$out" 'probe skipped: alpha — pwsh not on PATH'

# A passing gate without skip lines stays silent apart from its start line.
gates_validate "$(cfg '"quiet"' '{"id":"quiet","command":["echo","plain output"]}')" || exit 1
G_SELECTED=(quiet)
GATE_VERBOSE=0 out=$(trap 'rm -rf "$GATE_TMPDIR"' EXIT; run_gates 1 2>&1)
expect_eq 'a passing gate without skips stays silent' "$out" 'gates: start quiet'

t_done
