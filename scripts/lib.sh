#!/usr/bin/env bash
# Shared library for the bash governance scripts: a fail-loud minimal JSON
# parser (objects, arrays, strings, integers, floats, booleans, null — the
# superset every manifest here needs), test assertions for scripts/*.test.sh,
# and small helpers. Sourced, never executed: everything here is a definition.
#
# JSON representation: json_parse emits two parallel tables.
#   JSON_NODES:    "<path>\t<type>\t<value>"  — one line per parsed value.
#   JSON_CHILDREN: "<parent-path>\t<key-or-index>" — explicit membership
#                  edges, so object keys may contain dots and slashes without
#                  ambiguity. Query with exact paths built from json_keys.

# Emit one parser node.
_json_emit() { JSON_NODES+=("$1"$'\t'"$2"$'\t'"$3"); }

# Record one parent-child edge.
_json_child() { JSON_CHILDREN+=("$1"$'\t'"$2"); }

# Report a parse failure; the caller propagates the status.
_json_err() { JSON_ERROR="json: $1 at offset $_J_pos"; return 1; }

_json_skip_ws() {
  while (( _J_pos < _J_len )); do
    case ${_J_input:_J_pos:1} in ' '|$'\t'|$'\n'|$'\r') (( _J_pos++ )) ;; *) break ;; esac
  done
}

# Parse a JSON string literal at _J_pos into REPLY; handles all standard
# escapes and \uXXXX (surrogate pairs combined); rejects raw control bytes.
_json_string() {
  local out='' c esc hex code lo hi
  (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} == '"' ]] || { _json_err "expected a string"; return 1; }
  (( _J_pos++ ))
  while :; do
    (( _J_pos < _J_len )) || { _json_err "unterminated string"; return 1; }
    c=${_J_input:_J_pos:1}
    case $c in
      '"') (( _J_pos++ )); REPLY=$out; return 0 ;;
      \\)
        (( _J_pos + 1 < _J_len )) || { _json_err "truncated escape"; return 1; }
        esc=${_J_input:$(( _J_pos + 1 )):1}
        case $esc in
          '"'|'\\'|'/') out+=$esc; (( _J_pos += 2 )) ;;
          'b') out+=$'\b'; (( _J_pos += 2 )) ;;
          'f') out+=$'\f'; (( _J_pos += 2 )) ;;
          'n') out+=$'\n'; (( _J_pos += 2 )) ;;
          'r') out+=$'\r'; (( _J_pos += 2 )) ;;
          't') out+=$'\t'; (( _J_pos += 2 )) ;;
          'u')
            hex=${_J_input:$(( _J_pos + 2 )):4}
            [[ $hex =~ ^[0-9a-fA-F]{4}$ ]] || { _json_err "bad \\u escape"; return 1; }
            code=$(( 16#$hex ))
            if (( code >= 0xD800 && code <= 0xDBFF )); then
              # High surrogate: a low surrogate must follow.
              [[ ${_J_input:$(( _J_pos + 6 )):6} == '\u' ]] || { _json_err "unpaired surrogate"; return 1; }
              lo=${_J_input:$(( _J_pos + 8 )):4}
              [[ $lo =~ ^[0-9a-fA-F]{4}$ ]] || { _json_err "bad \\u escape"; return 1; }
              hi=$(( 16#$lo ))
              (( hi >= 0xDC00 && hi <= 0xDFFF )) || { _json_err "unpaired surrogate"; return 1; }
              code=$(( 0x10000 + ( ( code - 0xD800 ) << 10 ) + hi - 0xDC00 ))
              printf -v esc '\U%08x' "$code"
              out+=$esc; (( _J_pos += 12 ))
            elif (( code >= 0xDC00 && code <= 0xDFFF )); then
              _json_err "unpaired surrogate"; return 1
            else
              printf -v esc '\u%04x' "$code"
              out+=$esc; (( _J_pos += 6 ))
            fi ;;
          *) _json_err "unknown escape \\$esc"; return 1 ;;
        esac ;;
      *)
        # Raw control characters are illegal inside JSON strings.
        [[ $c < ' ' ]] && { _json_err "raw control character in string"; return 1; }
        out+=$c; (( _J_pos++ )) ;;
    esac
  done
}

# True when $1 already has an object child named $2 (duplicate-key guard).
_json_has_child() {
  local edge
  for edge in "${JSON_CHILDREN[@]+"${JSON_CHILDREN[@]}"}"; do
    [[ $edge == "$1"$'\t'"$2" ]] && return 0
  done
  return 1
}

# Parse one value at _J_pos whose node path is $1; recurses into containers.
_json_value() {
  local path=$1 c
  _json_skip_ws
  (( _J_pos < _J_len )) || { _json_err "expected a value"; return 1; }
  c=${_J_input:_J_pos:1}
  case $c in
    '"')
      _json_string || return 1
      _json_emit "$path" string "$REPLY" ;;
    '{')
      (( _J_pos++ )); _json_emit "$path" object ''
      _json_skip_ws
      if (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} == '}' ]]; then (( _J_pos++ )); return 0; fi
      while :; do
        _json_skip_ws
        _json_string || return 1
        local key=$REPLY
        _json_has_child "$path" "$key" && { _json_err "duplicate object key \"$key\""; return 1; }
        _json_skip_ws
        (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} == ':' ]] || { _json_err "expected ':'"; return 1; }
        (( _J_pos++ ))
        _json_child "$path" "$key"
        _json_value "$path.$key" || return 1
        _json_skip_ws
        (( _J_pos < _J_len )) || { _json_err "unterminated object"; return 1; }
        case ${_J_input:_J_pos:1} in
          ',') (( _J_pos++ )) ;;
          '}') (( _J_pos++ )); return 0 ;;
          *) _json_err "expected ',' or '}'"; return 1 ;;
        esac
      done ;;
    '[')
      (( _J_pos++ )); _json_emit "$path" array ''
      _json_skip_ws
      if (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} == ']' ]]; then (( _J_pos++ )); return 0; fi
      local i=0
      while :; do
        _json_child "$path" "$i"
        _json_value "$path[$i]" || return 1
        (( i++ ))
        _json_skip_ws
        (( _J_pos < _J_len )) || { _json_err "unterminated array"; return 1; }
        case ${_J_input:_J_pos:1} in
          ',') (( _J_pos++ )) ;;
          ']') (( _J_pos++ )); return 0 ;;
          *) _json_err "expected ',' or ']'"; return 1 ;;
        esac
      done ;;
    't')
      [[ ${_J_input:_J_pos:4} == 'true' ]] || { _json_err "invalid literal"; return 1; }
      (( _J_pos += 4 )); _json_emit "$path" bool true ;;
    'f')
      [[ ${_J_input:_J_pos:5} == 'false' ]] || { _json_err "invalid literal"; return 1; }
      (( _J_pos += 5 )); _json_emit "$path" bool false ;;
    'n')
      [[ ${_J_input:_J_pos:4} == 'null' ]] || { _json_err "invalid literal"; return 1; }
      (( _J_pos += 4 )); _json_emit "$path" null '' ;;
    '-'|[0-9])
      local start=$_J_pos
      [[ ${_J_input:_J_pos:1} == '-' ]] && (( _J_pos++ ))
      local int_start=$_J_pos
      if [[ ${_J_input:_J_pos:1} == '0' ]]; then
        (( _J_pos++ ))
        [[ ${_J_input:_J_pos:1} =~ [0-9] ]] && { _json_err "invalid number (leading zero)"; return 1; }
      else
        while (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} =~ [0-9] ]]; do (( _J_pos++ )); done
        (( _J_pos > int_start )) || { _json_err "invalid number"; return 1; }
      fi
      if (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} == '.' ]]; then
        (( _J_pos++ ))
        while (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} =~ [0-9] ]]; do (( _J_pos++ )); done
        [[ ${_J_input:$(( _J_pos - 1 )):1} =~ [0-9] ]] || { _json_err "invalid number"; return 1; }
      fi
      if (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} =~ [eE] ]]; then
        (( _J_pos++ ))
        (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} =~ [+-] ]] && (( _J_pos++ ))
        while (( _J_pos < _J_len )) && [[ ${_J_input:_J_pos:1} =~ [0-9] ]]; do (( _J_pos++ )); done
        [[ ${_J_input:$(( _J_pos - 1 )):1} =~ [0-9] ]] || { _json_err "invalid number"; return 1; }
      fi
      _json_emit "$path" number "${_J_input:$start:$(( _J_pos - start ))}" ;;
    *) _json_err "unexpected character '$c'"; return 1 ;;
  esac
}

# Parse $1 as JSON into JSON_NODES/JSON_CHILDREN; JSON_ERROR names the defect.
json_parse() {
  JSON_NODES=() JSON_CHILDREN=() JSON_ERROR=''
  _J_input=$1 _J_len=${#1} _J_pos=0
  _json_value '$' || return 1
  _json_skip_ws
  (( _J_pos == _J_len )) || { _json_err "trailing content after the top-level value"; return 1; }
}

# Node type at an exact path (status 1 when absent).
json_type() {
  local node
  for node in "${JSON_NODES[@]+"${JSON_NODES[@]}"}"; do
    if [[ ${node%%$'\t'*} == "$1" ]]; then
      REPLY=${node#*$'\t'}; REPLY=${REPLY%%$'\t'*}; return 0
    fi
  done
  return 1
}

# Scalar value at an exact path.
json_get() {
  local node
  for node in "${JSON_NODES[@]+"${JSON_NODES[@]}"}"; do
    if [[ ${node%%$'\t'*} == "$1" ]]; then
      REPLY=${node#*$'\t'*$'\t'}; return 0
    fi
  done
  return 1
}

# Object keys of $1 in document order, into REPLY_LIST.
json_keys() {
  local edge prefix=$1$'\t'
  REPLY_LIST=()
  for edge in "${JSON_CHILDREN[@]+"${JSON_CHILDREN[@]}"}"; do
    [[ $edge == "$prefix"* ]] && REPLY_LIST+=("${edge#"$prefix"}")
  done
}

# Element count of an array path.
json_len() {
  local edge prefix=$1$'\t' count=0
  for edge in "${JSON_CHILDREN[@]+"${JSON_CHILDREN[@]}"}"; do
    [[ $edge == "$prefix"[0-9]* ]] && (( count++ ))
  done
  REPLY=$count
}

# The sha256 of one file's bytes, hex, via the first available hasher.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then REPLY=$(sha256sum < "$1"); REPLY=${REPLY%% *}
  elif command -v shasum >/dev/null 2>&1; then REPLY=$(shasum -a 256 < "$1"); REPLY=${REPLY%% *}
  else echo 'lib: no sha256 hasher found (need sha256sum or shasum)' >&2; return 1; fi
}

# Wall-clock milliseconds since the epoch (EPOCHREALTIME on bash >= 5; the
# seconds-resolution fallback keeps macOS's bash 3.2 usable for timing).
now_ms() {
  local us
  if [[ -n ${EPOCHREALTIME:-} ]]; then
    us=${EPOCHREALTIME/./}
    REPLY=$(( us / 1000 ))
  else
    REPLY=$(( $(date +%s) * 1000 ))
  fi
}

# --- test assertions for scripts/*.test.sh -----------------------------------
# A test file sources lib.sh, registers checks, and ends with t_done, which
# exits non-zero when any check failed. Checks print only failures; skips
# print a visible "skipped:" line and never fail the suite.

T_FAILED=0 T_TOTAL=0 T_SKIPPED=0

_fail() { T_FAILED=$(( T_FAILED + 1 )); printf 'FAIL %s\n' "$1" >&2; }

expect_eq() { # <description> <actual> <expected>
  T_TOTAL=$(( T_TOTAL + 1 ))
  [[ $2 == "$3" ]] || _fail "$1: expected [$3], got [$2]"
}

expect_contains() { # <description> <haystack> <needle>
  T_TOTAL=$(( T_TOTAL + 1 ))
  [[ $2 == *"$3"* ]] || _fail "$1: [$2] does not contain [$3]"
}

expect_status() { # <description> <expected-status> <actual-status>
  T_TOTAL=$(( T_TOTAL + 1 ))
  [[ $3 == "$2" ]] || _fail "$1: expected status $2, got $3"
}

# Count one loudly-skipped check — a visible non-check (e.g. a probe test
# whose cross interpreter is absent), never a failure.
expect_skip() { # <description>
  T_TOTAL=$(( T_TOTAL + 1 ))
  T_SKIPPED=$(( T_SKIPPED + 1 ))
  printf 'skipped: %s\n' "$1" >&2
}

t_done() {
  if (( T_SKIPPED > 0 )); then
    printf '%d check(s), %d failed, %d skipped\n' "$T_TOTAL" "$T_FAILED" "$T_SKIPPED" >&2
  else
    printf '%d check(s), %d failed\n' "$T_TOTAL" "$T_FAILED" >&2
  fi
  (( T_FAILED == 0 ))
}
