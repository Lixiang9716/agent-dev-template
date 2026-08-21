#!/usr/bin/env bash
# Declarative DAG gate scheduler (bash port; the pwsh twin is gates.ps1).
#
# Runs one mode from gates.json: a gate starts once every gate in its `needs`
# has passed, bounded by the concurrency limit; a failed dependency marks its
# dependents skipped with the reason instead of running them. Config problems
# (duplicate ids, unknown needs, dependency cycles, unknown modes) abort
# before any child process starts — a gate list that cannot be executed
# unambiguously is never best-effort run.
#
# Command slots: a plain array runs under both shells; an object declares
# per-shell variants and must name every shell in the closed set (sh, pwsh) —
# a missing variant aborts instead of silently skipping on that platform.
#
# bash 3.2 compatibility is load-bearing: the macOS hooks dispatch to the
# system bash (3.2), so no associative arrays, no mapfile, no ${var,,}, and
# every empty-array expansion is guarded. Gate properties live in parallel
# indexed arrays keyed by each gate's position in G_IDS. Zero runtime
# dependencies beyond bash >= 3.2. See docs/architecture.md.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

CONFIG_PATH=$ROOT/gates.json
US=$'\x01' # argv/needs separator; control characters in ids or commands abort validation

# Die with a message on stderr.
gates_die() { printf 'gates: %s\n' "$1" >&2; exit 1; }

# Index of gate $1 in G_IDS; REPLY=index, status 1 when absent.
gates_index() { # <id>
  local id=$1 i
  for (( i = 0; i < ${#G_IDS[@]}; i++ )); do
    [[ ${G_IDS[i]} == "$id" ]] && { REPLY=$i; return 0; }
  done
  return 1
}

gates_has_id() { gates_index "$1" >/dev/null 2>&1; }
gates_label() { gates_index "$1" && printf '%s' "${G_LABELS[$REPLY]}"; }
gates_needs() { gates_index "$1" && printf '%s' "${G_NEEDS[$REPLY]}"; }
gates_cmd() { gates_index "$1" && printf '%s' "${G_CMDS[$REPLY]}"; }
gates_allow() { gates_index "$1" && printf '%s' "${G_ALLOWS[$REPLY]}"; }

gates_mode_exists() { # <mode>
  local mode=$1 i
  for (( i = 0; i < ${#G_MODE_NAMES[@]}; i++ )); do
    [[ ${G_MODE_NAMES[i]} == "$mode" ]] && return 0
  done
  return 1
}

# The US-separated gate id list of mode $1.
gates_mode_ids() { # <mode>
  local mode=$1 i
  for (( i = 0; i < ${#G_MODE_NAMES[@]}; i++ )); do
    if [[ ${G_MODE_NAMES[i]} == "$mode" ]]; then
      printf '%s' "${G_MODE_IDS[i]}"
      return 0
    fi
  done
  return 1
}

# Split $1 on the US separator into SPLIT_PARTS. read -ra with a
# control-character IFS does not split on bash 3.2 (macOS), so the decode is
# done by hand.
us_split() { # <string>
  local rest=$1 part
  SPLIT_PARTS=()
  [[ -n $rest ]] || return 0
  while [[ $rest == *$US* ]]; do
    part=${rest%%$US*}
    SPLIT_PARTS+=("$part")
    rest=${rest#*$US}
  done
  SPLIT_PARTS+=("$rest")
}

# --- runtime state (parallel to G_IDS) -----------------------------------------
r_status() { gates_index "$1" && printf '%s' "${R_STATUS[$REPLY]:-}"; }
r_settled() { gates_index "$1" && [[ -n ${R_STATUS[$REPLY]:-} ]]; }
r_reason() { gates_index "$1" && printf '%s' "${R_REASON[$REPLY]:-}"; }
r_dur() { gates_index "$1" && printf '%s' "${R_DUR[$REPLY]:-}"; }
r_out() { gates_index "$1" && printf '%s' "${R_OUT[$REPLY]:-}"; }
r_set() { # <id> <status> <reason>
  gates_index "$1" || return 1
  R_STATUS[$REPLY]=$2
  R_REASON[$REPLY]=$3
}

# --- config validation --------------------------------------------------------

# Validate one parsed command slot; on success CMD_ARGV holds this shell's
# argv (US-separated). A plain array is shared by both shells; an object must
# carry a valid variant for every shell in the closed set.
gates_validate_command() { # <gate-id> <path> <path-type>
  local gid=$1 cpath=$2 ctype=$3 shell part n have variant
  CMD_ARGV=''
  if [[ $ctype != array && $ctype != object ]]; then
    gates_die "invalid gates.json: gate \"$gid\" needs a non-empty command string array"
  fi
  if [[ $ctype == array ]]; then
    json_len "$cpath"; n=$REPLY
    (( n > 0 )) || gates_die "invalid gates.json: gate \"$gid\" needs a non-empty command string array"
    for (( part = 0; part < n; part++ )); do
      json_type "$cpath[$part]" || gates_die "invalid gates.json: gate \"$gid\" needs a non-empty command string array"
      [[ $REPLY == string ]] || gates_die "invalid gates.json: gate \"$gid\" needs a non-empty command string array"
      json_get "$cpath[$part]"
      [[ $REPLY == *$US* ]] && gates_die "invalid gates.json: gate \"$gid\" command must not contain control characters"
      CMD_ARGV+=${CMD_ARGV:+$US}$REPLY
    done
    return 0
  fi
  json_keys "$cpath"
  for shell in "${REPLY_LIST[@]}"; do
    [[ $shell == sh || $shell == pwsh ]] \
      || gates_die "invalid gates.json: gate \"$gid\" command declares unknown shell \"$shell\"; the closed set is sh, pwsh"
  done
  for shell in sh pwsh; do
    variant=$cpath.$shell
    have=0
    json_type "$variant" && have=1
    (( have )) || gates_die "invalid gates.json: gate \"$gid\" command must declare both \"sh\" and \"pwsh\" variants"
    json_type "$variant"
    [[ $REPLY == array ]] || gates_die "invalid gates.json: gate \"$gid\" \"$shell\" command must be a non-empty string array"
    json_len "$variant"; n=$REPLY
    (( n > 0 )) || gates_die "invalid gates.json: gate \"$gid\" \"$shell\" command must be a non-empty string array"
    for (( part = 0; part < n; part++ )); do
      json_type "$variant[$part]" || gates_die "invalid gates.json: gate \"$gid\" \"$shell\" command must be a non-empty string array"
      [[ $REPLY == string ]] || gates_die "invalid gates.json: gate \"$gid\" \"$shell\" command must be a non-empty string array"
      json_get "$variant[$part]"
      [[ $REPLY == *$US* ]] && gates_die "invalid gates.json: gate \"$gid\" command must not contain control characters"
      [[ $shell == sh ]] && CMD_ARGV+=${CMD_ARGV:+$US}$REPLY
    done
  done
}

# Validate the whole gates.json content string; on success the G_* globals
# hold the normalized model. Dies with the offending name on any defect.
gates_validate() { # <json text>
  local raw=$1 n i gid id_type label needs_str allow dep deps mode m j ids
  json_parse "$raw" || gates_die "invalid gates.json: $JSON_ERROR"
  json_type '$' || gates_die 'invalid gates.json: config must be a JSON object'
  [[ $REPLY == object ]] || gates_die 'invalid gates.json: config must be a JSON object'
  json_type '$.gates' || gates_die 'invalid gates.json: gate list is empty — an aggregate with no gates cannot be validated or run'
  [[ $REPLY == array ]] || gates_die 'invalid gates.json: gate list is empty — an aggregate with no gates cannot be validated or run'
  json_len '$.gates'; n=$REPLY
  (( n > 0 )) || gates_die 'invalid gates.json: gate list is empty — an aggregate with no gates cannot be validated or run'
  json_type '$.modes' || gates_die 'invalid gates.json: modes must be an object mapping mode names to gate id arrays'
  [[ $REPLY == object ]] || gates_die 'invalid gates.json: modes must be an object mapping mode names to gate id arrays'

  G_IDS=() G_LABELS=() G_ALLOWS=() G_NEEDS=() G_CMDS=()
  G_MODE_NAMES=() G_MODE_IDS=()

  for (( i = 0; i < n; i++ )); do
    local gp="$.gates[$i]"
    json_type "$gp" || gates_die 'invalid gates.json: each gate must be an object'
    [[ $REPLY == object ]] || gates_die 'invalid gates.json: each gate must be an object'
    json_type "$gp.id" || gates_die 'invalid gates.json: gate id must be a non-empty string'
    id_type=$REPLY
    [[ $id_type == string ]] || gates_die 'invalid gates.json: gate id must be a non-empty string'
    json_get "$gp.id"; gid=$REPLY
    [[ -n $gid ]] || gates_die 'invalid gates.json: gate id must be a non-empty string'
    [[ $gid == *$US* ]] && gates_die "invalid gates.json: gate id \"$gid\" must not contain control characters"
    gates_has_id "$gid" && gates_die "invalid gates.json: duplicate gate id \"$gid\""

    label=$gid
    if json_type "$gp.label" && [[ $REPLY == string ]]; then
      json_get "$gp.label"
      [[ -n $REPLY ]] && label=$REPLY
    fi

    json_type "$gp.command" || gates_die "invalid gates.json: gate \"$gid\" needs a non-empty command string array"
    gates_validate_command "$gid" "$gp.command" "$REPLY"

    needs_str=''
    if json_type "$gp.needs" && [[ $REPLY != null ]]; then
      [[ $REPLY == array ]] || gates_die "invalid gates.json: gate \"$gid\" needs must be an array of gate ids"
      json_len "$gp.needs"; m=$REPLY
      for (( j = 0; j < m; j++ )); do
        json_type "$gp.needs[$j]" || gates_die "invalid gates.json: gate \"$gid\" needs must be an array of gate ids"
        [[ $REPLY == string ]] || gates_die "invalid gates.json: gate \"$gid\" needs must be an array of gate ids"
        json_get "$gp.needs[$j]"; dep=$REPLY
        [[ $dep == *$US* ]] && gates_die "invalid gates.json: gate \"$gid\" needs must not contain control characters"
        needs_str+=${needs_str:+$US}$dep
      done
    fi

    allow=false
    if json_type "$gp.allowFailure" && [[ $REPLY != null ]]; then
      [[ $REPLY == bool ]] || gates_die "invalid gates.json: gate \"$gid\" allowFailure must be a boolean"
      json_get "$gp.allowFailure"; allow=$REPLY
    fi

    G_IDS+=("$gid")
    G_LABELS+=("$label")
    G_ALLOWS+=("$allow")
    G_NEEDS+=("$needs_str")
    G_CMDS+=("$CMD_ARGV")
  done

  for gid in "${G_IDS[@]}"; do
    us_split "$(gates_needs "$gid")"
    deps=("${SPLIT_PARTS[@]+"${SPLIT_PARTS[@]}"}")
    for dep in "${deps[@]+"${deps[@]}"}"; do
      gates_has_id "$dep" || gates_die "invalid gates.json: gate \"$gid\" depends on unknown gate \"$dep\""
    done
  done

  gates_find_cycle && gates_die "invalid gates.json: dependency cycle: $REPLY"

  json_keys '$.modes'
  for mode in "${REPLY_LIST[@]}"; do
    json_type "\$.modes.$mode"
    [[ $REPLY == array ]] || gates_die "invalid gates.json: mode \"$mode\" must be a non-empty array of known gate ids"
    json_len "\$.modes.$mode"; m=$REPLY
    (( m > 0 )) || gates_die "invalid gates.json: mode \"$mode\" must be a non-empty array of known gate ids"
    ids=''
    for (( j = 0; j < m; j++ )); do
      json_type "\$.modes.$mode[$j]" || gates_die "invalid gates.json: mode \"$mode\" must be a non-empty array of known gate ids"
      [[ $REPLY == string ]] || gates_die "invalid gates.json: mode \"$mode\" must be a non-empty array of known gate ids"
      json_get "\$.modes.$mode[$j]"
      mode_gate=$REPLY
      # gates_has_id clobbers REPLY with the gate's index; capture first.
      gates_has_id "$mode_gate" || gates_die "invalid gates.json: mode \"$mode\" must be a non-empty array of known gate ids"
      ids+=${ids:+$US}$mode_gate
    done
    G_MODE_NAMES+=("$mode")
    G_MODE_IDS+=("$ids")
  done
  gates_mode_exists all || gates_die 'invalid gates.json: modes must define "all"'
}

# Set REPLY to the first dependency cycle as "a -> b -> a", or return 1.
gates_find_cycle() {
  local id
  _COLORS=()
  _PATH=()
  for id in "${G_IDS[@]}"; do
    gates_index "$id" || continue
    [[ ${_COLORS[$REPLY]:-0} -eq 0 ]] || continue
    gates_visit "$id" && return 0
  done
  return 1
}

gates_visit() { # returns 0 when a cycle was found with REPLY set
  local id=$1 dep i deps from out idx
  gates_index "$id" || return 1
  idx=$REPLY
  _COLORS[$idx]=1
  _PATH+=("$id")
  us_split "$(gates_needs "$id")"
  deps=("${SPLIT_PARTS[@]+"${SPLIT_PARTS[@]}"}")
  for dep in "${deps[@]+"${deps[@]}"}"; do
    gates_index "$dep" || continue
    case ${_COLORS[$REPLY]:-0} in
      0)
        gates_visit "$dep" && return 0
        ;;
      1)
        from=-1 out=()
        for i in "${!_PATH[@]}"; do
          [[ ${_PATH[i]} == "$dep" ]] && { from=$i; break; }
        done
        for (( i = from; i < ${#_PATH[@]}; i++ )); do out+=("${_PATH[i]}"); done
        out+=("$id")
        REPLY=${out[0]}
        for (( i = 1; i < ${#out[@]}; i++ )); do REPLY+=" -> ${out[i]}"; done
        return 0
        ;;
    esac
  done
  unset "_PATH[$(( ${#_PATH[@]} - 1 ))]"
  _COLORS[$idx]=2
  return 1
}

# --- scheduling ----------------------------------------------------------------

# Execute one gate as a real child process, capturing combined output.
# Tests may override this to fake outcomes or check scheduling order.
gate_execute() { # <id>
  local id=$1 idx
  gates_index "$id" || return 1
  idx=$REPLY
  us_split "$(gates_cmd "$id")"
  argv=("${SPLIT_PARTS[@]+"${SPLIT_PARTS[@]}"}")
  R_OUT[$idx]=$GATE_TMPDIR/$id.out
  printf 'gates: start %s\n' "$(gates_label "$id")"
  ( "${argv[@]}" >"${R_OUT[$idx]}" 2>&1 ) &
  PIDS+=("$!")
  PID_GATES+=("$idx")
  now_ms
  PID_STARTS+=("$REPLY")
}

# Count the live children in PIDS (cleared entries never shrink the array,
# so ${#PIDS[@]} stays stable and every loop iterates the full range).
live_pids() {
  local n=0 p
  for (( p = 0; p < ${#PIDS[@]}; p++ )); do
    [[ -n ${PIDS[p]:-} ]] && (( n++ ))
  done
  REPLY=$n
}

# True when $1 already has a live child in PIDS — the launch loop must
# never start a second copy of a gate that is still running.
gate_running() { # <id>
  gates_index "$1" || return 1
  local idx=$REPLY p
  for (( p = 0; p < ${#PIDS[@]}; p++ )); do
    [[ -n ${PIDS[p]:-} ]] || continue
    [[ ${PID_GATES[p]:-} == "$idx" ]] && return 0
  done
  return 1
}

# True when every need of $1 has passed (unset needs are not passed).
gates_ready() { # <id>
  local dep deps
  us_split "$(gates_needs "$1")"
  deps=("${SPLIT_PARTS[@]+"${SPLIT_PARTS[@]}"}")
  for dep in "${deps[@]+"${deps[@]}"}"; do
    [[ $(r_status "$dep") == passed ]] || return 1
  done
  return 0
}

# A settled outcome blocks the aggregate unless allowFailure covers it.
result_blocking() { [[ $(r_status "$1") != passed && $(gates_allow "$1") != true ]]; }

# Run the selected gate list (G_SELECTED): start ready gates up to $1
# concurrent children, settle them as they finish, and skip pending gates
# whose dependencies did not pass.
run_gates() { # <max-active>
  local max=$1 id pid rc end sig running_pids reapable p gate_idx start_ms
  PIDS=() PID_GATES=() PID_STARTS=()
  R_STATUS=() R_REASON=() R_DUR=() R_OUT=()
  GATE_TMPDIR=$(mktemp -d)

  while :; do
    # Launch every pending gate whose needs passed, up to the limit.
    live_pids
    local live=$REPLY
    for id in "${G_SELECTED[@]}"; do
      (( live >= max )) && break
      r_settled "$id" && continue
      gate_running "$id" && continue
      gates_ready "$id" || continue
      gate_execute "$id"
      # The cap must track the live count as launches happen: a stale
      # snapshot would start every ready gate in the same round.
      live=$(( live + 1 ))
    done

    live_pids
    if (( $REPLY == 0 )); then
      gates_skip_pending
      break
    fi

    # Poll until at least one child has finished, then reap all finished.
    reapable=0
    while (( ! reapable )); do
      running_pids=$(jobs -pr)
      reapable=1
      for (( p = 0; p < ${#PIDS[@]}; p++ )); do
        [[ -n ${PIDS[p]:-} ]] || continue
        grep -qx "${PIDS[p]}" <<< "$running_pids" && { reapable=0; break; }
      done
      (( reapable )) || sleep 0.05
    done
    for (( p = 0; p < ${#PIDS[@]}; p++ )); do
      pid=${PIDS[p]:-}
      [[ -n $pid ]] || continue
      grep -qx "$pid" <<< "$running_pids" && continue
      gate_idx=${PID_GATES[p]:-}
      [[ -n $gate_idx ]] || continue
      id=${G_IDS[gate_idx]}
      wait "$pid"; rc=$?
      start_ms=${PID_STARTS[p]:-0}
      PIDS[p]='' PID_GATES[p]='' PID_STARTS[p]=''
      now_ms; end=$REPLY
      R_DUR[$gate_idx]=$(( end - start_ms ))
      if (( rc == 0 )); then
        r_set "$id" passed ''
      elif (( rc > 128 )); then
        sig=$(kill -l $(( rc - 128 )) 2>/dev/null || echo "?")
        [[ $sig == SIG* ]] || sig="SIG$sig"
        r_set "$id" failed "signal $sig"
      else
        r_set "$id" failed "exit $rc"
      fi
      gates_report "$id"
    done
  done
}

# Mark every remaining pending gate skipped, attributing the failed needs.
# Reached only when no gate can start and none is running; a pending gate
# without a failed or skipped dependency is a scheduler defect and dies.
gates_skip_pending() {
  local id changed dep deps failed_deps
  changed=1
  while (( changed )); do
    changed=0
    for id in "${G_SELECTED[@]}"; do
      r_settled "$id" && continue
      failed_deps=''
      us_split "$(gates_needs "$id")"
      deps=("${SPLIT_PARTS[@]+"${SPLIT_PARTS[@]}"}")
      for dep in "${deps[@]+"${deps[@]}"}"; do
        [[ $(r_status "$dep") == failed || $(r_status "$dep") == skipped ]] \
          && failed_deps+="${failed_deps:+, }$dep"
      done
      [[ -n $failed_deps ]] || continue
      r_set "$id" skipped "dependency failed or skipped: $failed_deps"
      gates_index "$id" || continue
      R_DUR[$REPLY]=0
      R_OUT[$REPLY]=''
      gates_report "$id"
      changed=1
    done
  done
  for id in "${G_SELECTED[@]}"; do
    r_settled "$id" || gates_die 'validated graph stalled without a failed dependency'
  done
}

# Print one settled outcome (passes stay silent unless GATE_VERBOSE=1; a
# passing gate that emitted loud skip lines surfaces them — a skipped probe
# is degraded verification and must never look like full coverage).
gates_report() { # <id>
  local id=$1 secs argv out
  secs=$(awk -v ms="$(r_dur "$id")" 'BEGIN { printf "%.2f", ms / 1000 }')
  if [[ $(r_status "$id") == passed ]]; then
    [[ ${GATE_VERBOSE:-0} == 1 ]] && printf 'gates: PASS %s (%ss)\n' "$(gates_label "$id")" "$secs"
    out=$(r_out "$id")
    if [[ -s $out ]] && grep -q 'skipped:' "$out"; then
      grep 'skipped:' "$out"
    fi
    return 0
  fi
  us_split "$(gates_cmd "$id")"
  argv=("${SPLIT_PARTS[@]+"${SPLIT_PARTS[@]}"}")
  if [[ $(r_status "$id") == failed ]]; then
    printf '\n== FAILED %s (%ss) ==\n' "$(gates_label "$id")" "$secs" >&2
    printf 'command: %s\n' "${argv[*]}" >&2
    printf 'outcome: %s\n' "$(r_reason "$id")" >&2
    out=$(r_out "$id")
    [[ -s $out ]] && cat "$out" >&2
  else
    printf '\n== SKIPPED %s (%ss) ==\n' "$(gates_label "$id")" "$secs"
    printf 'command: %s\n' "${argv[*]}"
    printf 'outcome: %s\n' "$(r_reason "$id")"
  fi
}

# --- CLI -----------------------------------------------------------------------

gates_main() { # <args...>
  local mode=all arg
  while (( $# )); do
    if [[ $1 == --mode && $# -ge 2 ]]; then
      mode=$2; shift 2
    else
      gates_die "unknown argument \"$1\"; only --mode <name> is supported"
    fi
  done

  local raw
  raw=$(cat "$CONFIG_PATH" 2>/dev/null) || gates_die "cannot read gates.json"
  gates_validate "$raw"

  gates_mode_exists "$mode" || {
    local known='' m
    while IFS= read -r m; do known+=${known:+, }$m; done < <(printf '%s\n' "${G_MODE_NAMES[@]}" | sort)
    gates_die "unknown mode \"$mode\"; known modes: $known"
  }

  G_SELECTED=()
  us_split "$(gates_mode_ids "$mode")"
  G_SELECTED=("${SPLIT_PARTS[@]+"${SPLIT_PARTS[@]}"}")

  local cpu max_active
  cpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || cpu=$(nproc 2>/dev/null) \
    || gates_die 'cannot determine the processor count (need getconf or nproc)'
  [[ $cpu =~ ^[1-9][0-9]*$ ]] || gates_die "cannot determine the processor count (got \"$cpu\")"
  max_active=$(( cpu < ${#G_SELECTED[@]} ? cpu : ${#G_SELECTED[@]} ))

  if [[ -n ${GATE_CONCURRENCY:-} ]]; then
    [[ $GATE_CONCURRENCY =~ ^[1-9][0-9]*$ ]] \
      || gates_die "GATE_CONCURRENCY must be a positive integer, got \"$GATE_CONCURRENCY\""
    max_active=$(( GATE_CONCURRENCY < ${#G_SELECTED[@]} ? GATE_CONCURRENCY : ${#G_SELECTED[@]} ))
  fi

  printf 'gates: mode "%s" running %d gate(s) with %d worker(s).\n' "$mode" "${#G_SELECTED[@]}" "$max_active"
  now_ms
  local started=$REPLY

  trap '[ -n "${GATE_TMPDIR:-}" ] && rm -rf "$GATE_TMPDIR"' EXIT
  run_gates "$max_active"

  now_ms
  local elapsed=$(( REPLY - started ))
  local passed=0 failed=0 skipped=0 id blocking=0
  for id in "${G_SELECTED[@]}"; do
    case $(r_status "$id") in
      passed) (( passed++ )) ;;
      failed) (( failed++ )) ;;
      skipped) (( skipped++ )) ;;
    esac
    result_blocking "$id" && (( blocking++ )) || true
  done
  printf '\ngates: %d passed, %d failed, %d skipped in %ss.\n' "$passed" "$failed" "$skipped" \
    "$(awk -v ms="$elapsed" 'BEGIN { printf "%.2f", ms / 1000 }')"

  if (( blocking > 0 )); then
    printf 'gates: blocking outcomes:\n' >&2
    for id in "${G_SELECTED[@]}"; do
      result_blocking "$id" || continue
      printf '  - %s %s (%s)\n' \
        "$([ "$(r_status "$id")" = failed ] && echo FAILED || echo SKIPPED)" \
        "$(gates_label "$id")" "$(r_reason "$id")" >&2
    done
    exit 1
  fi
  exit 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  gates_main "$@"
fi
