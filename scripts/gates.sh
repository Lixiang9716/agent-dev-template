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
# Zero runtime dependencies beyond bash >= 5. See docs/architecture.md.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

CONFIG_PATH=$ROOT/gates.json
US=$'\x01' # argv/needs separator; control characters in ids or commands abort validation

# Die with a message on stderr.
gates_die() { printf 'gates: %s\n' "$1" >&2; exit 1; }

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

  G_IDS=()
  declare -gA G_MODES=() G_LABEL=() G_ALLOW=() G_NEEDS=() G_CMD=()

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
    [[ -z ${G_LABEL[$gid]+x} ]] || gates_die "invalid gates.json: duplicate gate id \"$gid\""

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

    G_LABEL[$gid]=$label G_ALLOW[$gid]=$allow G_NEEDS[$gid]=$needs_str G_CMD[$gid]=$CMD_ARGV
    G_IDS+=("$gid")
  done

  for gid in "${G_IDS[@]}"; do
    IFS=$US read -ra deps <<< "${G_NEEDS[$gid]}"
    for dep in "${deps[@]}"; do
      [[ -n ${G_LABEL[$dep]+x} ]] || gates_die "invalid gates.json: gate \"$gid\" depends on unknown gate \"$dep\""
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
      [[ -n ${G_LABEL[$REPLY]+x} ]] || gates_die "invalid gates.json: mode \"$mode\" must be a non-empty array of known gate ids"
      ids+=${ids:+$US}$REPLY
    done
    G_MODES[$mode]=$ids
  done
  [[ -n ${G_MODES[all]+x} ]] || gates_die 'invalid gates.json: modes must define "all"'
}

# Set REPLY to the first dependency cycle as "a -> b -> a", or return 1.
gates_find_cycle() {
  local id
  declare -A _COLOR=()
  _PATH=()
  for id in "${G_IDS[@]}"; do
    [[ ${_COLOR[$id]:-0} -eq 0 ]] || continue
    gates_visit "$id" && return 0
  done
  return 1
}

gates_visit() { # returns 0 when a cycle was found with REPLY set
  local id=$1 dep i deps from out
  _COLOR[$id]=1
  _PATH+=("$id")
  IFS=$US read -ra deps <<< "${G_NEEDS[$id]}"
  for dep in "${deps[@]}"; do
    case ${_COLOR[$dep]:-0} in
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
  _COLOR[$id]=2
  return 1
}

# --- scheduling ----------------------------------------------------------------

# Execute one gate as a real child process, capturing combined output.
# Tests may override this to fake outcomes or check scheduling order.
gate_execute() { # <id>
  local id=$1 argv
  IFS=$US read -ra argv <<< "${G_CMD[$id]}"
  R_OUT[$id]=$GATE_TMPDIR/$id.out
  printf 'gates: start %s\n' "${G_LABEL[$id]}"
  ( "${argv[@]}" >"${R_OUT[$id]}" 2>&1 ) &
  R_PID[$!]=$id
  now_ms
  A_START[$!]=$REPLY
}

# True when every need of $1 has passed (unset needs are not passed).
gates_ready() { # <id>
  local dep deps
  IFS=$US read -ra deps <<< "${G_NEEDS[$1]}"
  for dep in "${deps[@]}"; do
    [[ ${R_STATUS[$dep]:-} == passed ]] || return 1
  done
  return 0
}

# A settled outcome blocks the aggregate unless allowFailure covers it.
result_blocking() { [[ ${R_STATUS[$1]:-} != passed && ${G_ALLOW[$1]} != true ]]; }

# Run the selected gate list (G_SELECTED): start ready gates up to $1
# concurrent children, settle them as they finish, and skip pending gates
# whose dependencies did not pass.
run_gates() { # <max-active>
  local max=$1 id pid rc end sig running_pids reapable
  declare -gA R_PID=() A_START=()
  declare -gA R_STATUS=() R_REASON=() R_DUR=() R_OUT=()
  GATE_TMPDIR=$(mktemp -d)

  while :; do
    # Launch every pending gate whose needs passed, up to the limit.
    for id in "${G_SELECTED[@]}"; do
      (( ${#R_PID[@]} >= max )) && break
      [[ ${R_STATUS[$id]+x} ]] && continue
      gates_ready "$id" || continue
      gate_execute "$id"
    done

    if (( ${#R_PID[@]} == 0 )); then
      gates_skip_pending
      break
    fi

    # Poll until at least one child has finished, then reap all finished.
    reapable=0
    while (( ! reapable )); do
      running_pids=$(jobs -pr)
      reapable=1
      for pid in "${!R_PID[@]}"; do
        grep -qx "$pid" <<< "$running_pids" && { reapable=0; break; }
      done
      (( reapable )) || sleep 0.05
    done
    for pid in "${!R_PID[@]}"; do
      grep -qx "$pid" <<< "$running_pids" && continue
      id=${R_PID[$pid]}
      wait "$pid"; rc=$?
      unset "R_PID[$pid]"
      now_ms; end=$REPLY
      R_DUR[$id]=$(( end - A_START[$pid] ))
      if (( rc == 0 )); then
        R_STATUS[$id]=passed R_REASON[$id]=''
      elif (( rc > 128 )); then
        sig=$(kill -l $(( rc - 128 )) 2>/dev/null || echo "?")
        [[ $sig == SIG* ]] || sig="SIG$sig"
        R_STATUS[$id]=failed R_REASON[$id]="signal $sig"
      else
        R_STATUS[$id]=failed R_REASON[$id]="exit $rc"
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
      [[ ${R_STATUS[$id]+x} ]] && continue
      failed_deps=''
      IFS=$US read -ra deps <<< "${G_NEEDS[$id]}"
      for dep in "${deps[@]}"; do
        [[ ${R_STATUS[$dep]:-pending} == failed || ${R_STATUS[$dep]:-pending} == skipped ]] \
          && failed_deps+="${failed_deps:+, }$dep"
      done
      [[ -n $failed_deps ]] || continue
      R_STATUS[$id]=skipped
      R_REASON[$id]="dependency failed or skipped: $failed_deps"
      R_DUR[$id]=0 R_OUT[$id]=''
      gates_report "$id"
      changed=1
    done
  done
  for id in "${G_SELECTED[@]}"; do
    [[ ${R_STATUS[$id]+x} ]] || gates_die 'validated graph stalled without a failed dependency'
  done
}

# Print one settled outcome (passes stay silent unless GATE_VERBOSE=1).
gates_report() { # <id>
  local id=$1 secs argv
  secs=$(awk -v ms="${R_DUR[$id]}" 'BEGIN { printf "%.2f", ms / 1000 }')
  if [[ ${R_STATUS[$id]} == passed ]]; then
    [[ ${GATE_VERBOSE:-0} == 1 ]] && printf 'gates: PASS %s (%ss)\n' "${G_LABEL[$id]}" "$secs"
    return 0
  fi
  IFS=$US read -ra argv <<< "${G_CMD[$id]}"
  if [[ ${R_STATUS[$id]} == failed ]]; then
    printf '\n== FAILED %s (%ss) ==\n' "${G_LABEL[$id]}" "$secs" >&2
    printf 'command: %s\n' "${argv[*]}" >&2
    printf 'outcome: %s\n' "${R_REASON[$id]:-unknown}" >&2
    [[ -s ${R_OUT[$id]:-} ]] && cat "${R_OUT[$id]}" >&2
  else
    printf '\n== SKIPPED %s (%ss) ==\n' "${G_LABEL[$id]}" "$secs"
    printf 'command: %s\n' "${argv[*]}"
    printf 'outcome: %s\n' "${R_REASON[$id]:-unknown}"
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

  [[ -n ${G_MODES[$mode]+x} ]] || {
    local known='' m
    while IFS= read -r m; do known+=${known:+, }$m; done < <(printf '%s\n' "${!G_MODES[@]}" | sort)
    gates_die "unknown mode \"$mode\"; known modes: $known"
  }

  G_SELECTED=()
  # Inline IFS: a persistent IFS with a control character breaks quoted
  # array expansions on bash 5.1, so it must never outlive this read.
  IFS=$US read -ra G_SELECTED <<< "${G_MODES[$mode]}"

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
    case ${R_STATUS[$id]} in
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
        "$([ "${R_STATUS[$id]}" = failed ] && echo FAILED || echo SKIPPED)" \
        "${G_LABEL[$id]}" "${R_REASON[$id]:-unknown}" >&2
    done
    exit 1
  fi
  exit 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  gates_main "$@"
fi
