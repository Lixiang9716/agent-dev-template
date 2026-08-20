#!/usr/bin/env bash
# Declare-state vocabulary gate (bash port; pwsh twin: verify-vocabulary.ps1).
#
# Scans the pre-registered document surface (AGENTS.md, AGENTS.zh.md, docs/*.md
# — the `scan` list in scripts/vocabulary.json) for concept-level
# declaration-state words that carry a "certified-as-true" connotation: English
# verified/confirmed/proven/certified/validated/corroborated and any-language
# synonym forms such as 已验证 / 已证实 / 已确认 (Chinese). A translation must
# never bypass the gate. The banned families, meta-annotation whitelist,
# definition markers, and window all live in scripts/vocabulary.json — one home,
# consumed by both ports.
#
# Exemptions are pre-registered and mechanical, checked in order:
#   1. backtick-quoted tokens (code/identifier meta-reference);
#   2. meta-annotation context: the token sits inside a whitelist term that is
#      preceded by a structural delimiter (line start, table pipe, colon,
#      whitespace, quote, backtick, ...). A CJK prefix is not a delimiter, so
#      "该声明处于已确认状态" is a declaration-state usage and is not exempt;
#   3. ban-definition context: a definition marker ends within 6 characters
#      BEFORE the token on the same line (the ban's own definition sentence).
#      A marker AFTER the token does not excuse it.
#
# Fail loud: a malformed vocabulary.json, an unknown shape, or a missing scan
# target aborts naming the offender. Findings are collected and reported all
# at once with file:line positions.

# A UTF-8 locale is load-bearing here, not cosmetic: the en word-boundary
# check classifies the character adjacent to a token via [[:alpha:]], and
# Unicode letters (CJK ideographs) must count as word characters while CJK
# punctuation must not — the exact semantics of \b in the reference
# implementation. The pwsh twin is UTF-16-native and needs no locale pinning.
export LC_ALL=C.UTF-8
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

VOCAB_PATH=$ROOT/scripts/vocabulary.json

VOCAB_VIOLATIONS=()
vocab_violation() { VOCAB_VIOLATIONS+=("$1"); }

# True when $1 is a word character (Unicode letters, digits, underscore) —
# mirrors \b semantics: a CJK ideograph is a word char, CJK punctuation is not.
is_word_char() { # <char>
  [[ $1 == '_' ]] || [[ $1 =~ ^[[:alpha:][:digit:]]$ ]]
}

# Structural delimiter for meta-annotation context (platform delimiter set).
is_delimiter() { # <char>
  case $1 in
    '|'|':'|','|';'|'('|')'|'['|']'|'{'|'}'|'`'|'='|'"'|"'")
      return 0 ;;
    $'\t'|' ') return 0 ;;
  esac
  return 1
}

# Find $2 in $1 from character index $3; sets FOUND_AT, status 1 when absent.
# Case-insensitive when $4 is ci, case-sensitive when cs.
find_token() { # <haystack> <needle> <from> <ci|cs>
  local low needle tail pre
  if [[ ${4:-ci} == ci ]]; then
    low=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    needle=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  else
    low=$1
    needle=$2
  fi
  [[ ${low:$3} == *"$needle"* ]] || return 1
  tail=${low:$3}
  pre=${tail%%"$needle"*}
  FOUND_AT=$(( $3 + ${#pre} ))
}

# True when the en match [start,end) in $1 is word-boundary-delimited.
en_boundary_ok() { # <line> <start> <end>
  local line=$1 s=$2 e=$3
  if (( s > 0 )) && is_word_char "${line:s-1:1}"; then return 1; fi
  if (( e < ${#line} )) && is_word_char "${line:e:1}"; then return 1; fi
  return 0
}

# Backtick spans of $1 as "start:end" pairs into REPLY_SPANS.
backtick_spans() { # <line>
  local line=$1 i ch start=''
  REPLY_SPANS=()
  for (( i = 0; i < ${#line}; i++ )); do
    ch=${line:i:1}
    if [[ $ch == '`' ]]; then
      if [[ -z $start ]]; then
        start=$i
      else
        REPLY_SPANS+=("$start:$i")
        start=''
      fi
    fi
  done
}

# True when both $1 and $2 (match start / match end-1) sit inside one span.
in_backtick_span() { # <start> <end-minus-1>
  local span a b
  for span in "${REPLY_SPANS[@]+"${REPLY_SPANS[@]}"}"; do
    a=${span%%:*}
    b=${span#*:}
    (( $1 >= a && $2 <= b )) && return 0
  done
  return 1
}

# True when the match [start,end) sits inside a whitelist term in meta context
# (the term itself is preceded by a structural delimiter or line start).
meta_excused() { # <line> <start> <end>
  local line=$1 s=$2 e=$3 term tpos prev
  for term in "${META_WHITELIST[@]}"; do
    tpos=0
    while :; do
      find_token "$line" "$term" "$tpos" cs || break
      tpos=$FOUND_AT
      if (( tpos <= s && e <= tpos + ${#term} )); then
        if (( tpos == 0 )); then return 0; fi
        prev=${line:tpos-1:1}
        is_delimiter "$prev" && return 0
      fi
      tpos=$(( tpos + 1 ))
    done
  done
  return 1
}

# True when a definition marker ends within the window BEFORE the token start.
definition_excused() { # <line> <start>
  local line=$1 s=$2 m mpos mend
  for m in "${DEFINITION_MARKERS[@]}"; do
    mpos=0
    while :; do
      find_token "$line" "$m" "$mpos" cs || break
      mpos=$FOUND_AT
      mend=$(( mpos + ${#m} ))
      (( mend <= s && s - mend <= DEFINITION_WINDOW )) && return 0
      mpos=$(( mpos + 1 ))
    done
  done
  return 1
}

# True when the match [start,end) in $1 is covered by a pre-registered exemption.
token_excused() { # <line> <start> <end>
  local line=$1 s=$2 e=$3
  backtick_spans "$line"
  in_backtick_span "$s" "$(( e - 1 ))" && return 0
  meta_excused "$line" "$s" "$e" && return 0
  definition_excused "$line" "$s" && return 0
  return 1
}

# Scan one line of one file for banned tokens; appends violations. All
# candidate matches are collected first, then consumed left to right
# (finditer semantics): the earliest-starting match wins and later candidates
# inside its span are skipped — overlapping tokens such as 已经验证 inside
# 经验证 do not double-report.
scan_line() { # <rel> <lineno> <line>
  local rel=$1 lineno=$2 line=$3 token i start end rest cands=() c cursor ctx
  for token in "${BANNED_EN[@]}"; do
    i=0
    while :; do
      find_token "$line" "$token" "$i" ci || break
      start=$FOUND_AT
      end=$(( start + ${#token} ))
      en_boundary_ok "$line" "$start" "$end" \
        && cands+=("$start"$'\t'"$end"$'\t'"$token")
      i=$end
    done
  done
  for token in "${BANNED_ZH[@]}"; do
    i=0
    while :; do
      find_token "$line" "$token" "$i" ci || break
      start=$FOUND_AT
      end=$(( start + ${#token} ))
      cands+=("$start"$'\t'"$end"$'\t'"$token")
      i=$end
    done
  done
  (( ${#cands[@]} > 0 )) || return 0
  local sorted
  sorted=$(printf '%s\n' "${cands[@]}" | sort -n -k1,1)
  cands=()
  while IFS= read -r c; do cands+=("$c"); done <<< "$sorted"
  cursor=0
  for c in "${cands[@]}"; do
    start=${c%%$'\t'*}
    rest=${c#*$'\t'}
    end=${rest%%$'\t'*}
    token=${rest#*$'\t'}
    (( start < cursor )) && continue
    cursor=$end
    token_excused "$line" "$start" "$end" && continue
    ctx=${line//$'\t'/ }
    ctx=${ctx#"${ctx%%[![:space:]]*}"}
    ctx=${ctx%"${ctx##*[![:space:]]}"}
    vocab_violation "$rel:$lineno: banned declaration-state word \"$token\" — ${ctx:0:160}"
  done
}

# Scan one file: every line, 1-based line numbers.
scan_file() { # <rel> <abs-path>
  local rel=$1 path=$2 lineno=0 line
  while IFS= read -r line || [[ -n $line ]]; do
    (( lineno++ ))
    scan_line "$rel" "$lineno" "$line"
  done < "$path"
}

# Expand the scan list (globs allowed) and scan every match; missing targets
# and empty glob matches fail loud.
scan_surface() {
  local entry f matched
  shopt -s nullglob
  for entry in "${SCAN_LIST[@]}"; do
    if [[ $entry == *'*'* ]]; then
      matched=0
      for f in "$ROOT"/$entry; do
        [[ -f $f ]] || continue
        matched=1
        scan_file "${f#"$ROOT"/}" "$f"
      done
      (( matched )) || vocab_violation "scan pattern \"$entry\" matches no files"
    else
      [[ -f $ROOT/$entry ]] || { vocab_violation "scan target missing: $entry"; continue; }
      scan_file "$entry" "$ROOT/$entry"
    fi
  done
}

# Read $1 as the vocabulary manifest; fills BANNED_EN/BANNED_ZH/META_WHITELIST/
# DEFINITION_MARKERS/DEFINITION_WINDOW/SCAN_LIST. Strict schema: unknown keys
# and an unregistered version abort naming the offender (rule 4 — a mistyped
# whitelist key must never silently disable an exemption).
EXPECTED_VOCAB_VERSION=1
load_vocabulary() { # <path>
  local path=${1:-$VOCAB_PATH} raw i n item key
  VOCAB_VIOLATIONS=()
  BANNED_EN=() BANNED_ZH=() META_WHITELIST=() DEFINITION_MARKERS=() SCAN_LIST=()
  DEFINITION_WINDOW=0
  raw=$(<"$path") || { vocab_violation "$(basename "$path"): unreadable"; return 1; }
  json_parse "$raw" || { vocab_violation "$(basename "$path"): $JSON_ERROR"; return 1; }
  json_type '$' || { vocab_violation "$(basename "$path"): manifest must be a JSON object"; return 1; }
  [[ $REPLY == object ]] || { vocab_violation "$(basename "$path"): manifest must be a JSON object"; return 1; }
  json_keys '$'
  for key in "${REPLY_LIST[@]+"${REPLY_LIST[@]}"}"; do
    case $key in
      version|scan|banned|metaWhitelist|definitionMarkers|definitionWindow) ;;
      *) vocab_violation "$(basename "$path"): unknown key \"$key\" at the manifest top level (allowed: version, scan, banned, metaWhitelist, definitionMarkers, definitionWindow)"; return 1 ;;
    esac
  done
  if json_type '$.banned' && [[ $REPLY == object ]]; then
    json_keys '$.banned'
    for key in "${REPLY_LIST[@]+"${REPLY_LIST[@]}"}"; do
      case $key in
        en|zh) ;;
        *) vocab_violation "$(basename "$path"): unknown key \"$key\" in \"banned\" (allowed: en, zh)"; return 1 ;;
      esac
    done
  fi
  json_type '$.version' || { vocab_violation "$(basename "$path"): version must be a positive integer"; return 1; }
  [[ $REPLY == number ]] || { vocab_violation "$(basename "$path"): version must be a positive integer"; return 1; }
  json_get '$.version'
  [[ $REPLY =~ ^[1-9][0-9]*$ ]] || { vocab_violation "$(basename "$path"): version must be a positive integer"; return 1; }
  [[ $REPLY == "$EXPECTED_VOCAB_VERSION" ]] \
    || { vocab_violation "$(basename "$path"): version $REPLY does not match the registered version $EXPECTED_VOCAB_VERSION — bump EXPECTED_VOCAB_VERSION in both ports when migrating the schema"; return 1; }

  load_str_array() { # <json-path> <array-name>
    local jp=$1 name=$2 j
    json_type "$jp" || { vocab_violation "$(basename "$path"): $jp must be a non-empty array of non-empty strings"; return 1; }
    [[ $REPLY == array ]] || { vocab_violation "$(basename "$path"): $jp must be a non-empty array of non-empty strings"; return 1; }
    json_len "$jp"; n=$REPLY
    (( n > 0 )) || { vocab_violation "$(basename "$path"): $jp must be a non-empty array of non-empty strings"; return 1; }
    for (( j = 0; j < n; j++ )); do
      json_type "$jp[$j]" || { vocab_violation "$(basename "$path"): $jp entries must be non-empty strings"; return 1; }
      [[ $REPLY == string ]] || { vocab_violation "$(basename "$path"): $jp entries must be non-empty strings"; return 1; }
      json_get "$jp[$j]"
      [[ -n $REPLY ]] || { vocab_violation "$(basename "$path"): $jp entries must be non-empty strings"; return 1; }
      eval "${name}+=(\"\$REPLY\")"
    done
  }

  load_str_array '$.scan' SCAN_LIST || return 1
  load_str_array '$.banned.en' BANNED_EN || return 1
  load_str_array '$.banned.zh' BANNED_ZH || return 1
  load_str_array '$.metaWhitelist' META_WHITELIST || return 1
  load_str_array '$.definitionMarkers' DEFINITION_MARKERS || return 1
  json_type '$.definitionWindow' || { vocab_violation "$(basename "$path"): definitionWindow must be a positive integer"; return 1; }
  [[ $REPLY == number ]] || { vocab_violation "$(basename "$path"): definitionWindow must be a positive integer"; return 1; }
  json_get '$.definitionWindow'
  [[ $REPLY =~ ^[1-9][0-9]*$ ]] || { vocab_violation "$(basename "$path"): definitionWindow must be a positive integer"; return 1; }
  DEFINITION_WINDOW=$REPLY
  return 0
}

vocab_main() { # <args...>
  load_vocabulary || {
    printf 'verify-vocabulary: %d violation(s):\n' "${#VOCAB_VIOLATIONS[@]}" >&2
    local v
    for v in "${VOCAB_VIOLATIONS[@]+"${VOCAB_VIOLATIONS[@]}"}"; do printf '  %s\n' "$v" >&2; done
    return 1
  }
  scan_surface
  if (( ${#VOCAB_VIOLATIONS[@]} == 0 )); then
    echo 'verify-vocabulary: the document surface is clean of declaration-state words.'
    return 0
  fi
  printf 'verify-vocabulary: %d violation(s):\n' "${#VOCAB_VIOLATIONS[@]}" >&2
  local v
  for v in "${VOCAB_VIOLATIONS[@]+"${VOCAB_VIOLATIONS[@]}"}"; do
    printf '  %s\n' "$v" >&2
  done
  return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  vocab_main "$@"
fi
