#!/usr/bin/env bash
# Validate the Agent Notes tree (bash port; pwsh twin: verify-agent-notes.ps1):
# closed lifecycle and class sets, dated filenames, the three-line header, the
# required sections per lifecycle, and the entry discipline — Claim entries
# carry verifier/coverage/goal-link sub-bullets, Open entries carry settled-by,
# and "not-refuted" statements carry rate/schedule/reviewer sampling in their
# paragraph. `archived/` is frozen and owned by archive-agent-notes.sh; this
# verifier never re-validates sealed content. Failures are collected and
# reported all at once with file-relative paths.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NOTES_DIR=$ROOT/.agents/notes

LIFECYCLES=(proposed implemented rejected)                       # closed set; archived/ is a sibling frozen tree
CLASSES=(feature bug-fix simplification architecture process testing) # closed set

# Required sections per lifecycle, newline-separated. A function (not an
# associative array) keeps the script runnable on bash 3.2 (macOS).
required_sections() { # <lifecycle>
  case "$1" in
    proposed)    printf 'Proposal\nAlternatives considered\nAcceptance criteria\nRisks\n';;
    implemented) printf 'Decision\nAlternatives considered\nConsequences\n';;
    rejected)    printf 'Proposal\nAlternatives considered\n';;
  esac
}

FORBIDDEN_IN_IMPLEMENTED=('Proposal' 'Plan' 'Migration plan' 'Acceptance criteria')

NOTES_VIOLATIONS=()
note_violation() { NOTES_VIOLATIONS+=("$1"); }

# True when the string list in $2 (newline-separated) contains $1.
list_has() { # <needle> <newline-separated list>
  local item
  while IFS= read -r item; do
    [[ $item == "$1" ]] && return 0
  done <<< "$2"
  return 1
}

# Validate one note file's header, filename, and sections.
check_note() { # <rel-path> <abs-path>
  local rel=$1 path=$2 lifecycle name lines line3 text sections
  local name_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*[.]md$'
  lifecycle=${rel%%/*}
  name=${rel##*/}
  if ! [[ $name =~ $name_re ]]; then
    note_violation "$rel: filename must be yyyy-mm-dd-topic.md (kebab-case topic, dated at first proposal)"
    return 0
  fi
  lines=()
  while IFS= read -r line || [[ -n $line ]]; do lines+=("$line"); done < "$path"
  text=$(<"$path")
  [[ ${lines[0]-} == '# Agent Note: '* ]] || { note_violation "$rel: line 1 must be \"# Agent Note: <title>\""; return 0; }
  [[ ${lines[1]-} == '' ]] || note_violation "$rel: line 2 must be empty"
  line3=${lines[2]-}
  if [[ $lifecycle == rejected ]]; then
    [[ $line3 == 'Status: rejected — '* && ${#line3} -gt 19 ]] \
      || note_violation "$rel: line 3 for a rejected note must be \"Status: rejected — <why>\""
  else
    [[ $line3 == "Status: $lifecycle" ]] || note_violation "$rel: line 3 must be exactly \"Status: $lifecycle\""
  fi
  local status_count
  status_count=$(grep -c '^Status: ' <<< "$text" || true)
  [[ $status_count == 1 ]] || note_violation "$rel: exactly one \"Status:\" line is allowed"
  [[ ${lines[3]-} == '' ]] || note_violation "$rel: line 4 must be empty"

  sections=$(sed -n 's/^## \(.*\)$/\1/p' <<< "$text")
  [[ $(head -n 1 <<< "$sections") == 'Problem' ]] || note_violation "$rel: the first section must be \"## Problem\""
  local want has_ok
  while IFS= read -r want; do
    [[ -n $want ]] || continue
    has_ok=0
    while IFS= read -r item; do
      [[ $item == "$want" ]] && { has_ok=1; break; }
    done <<< "$sections"
    (( has_ok )) || note_violation "$rel: lifecycle \"$lifecycle\" requires a \"## $want\" section"
  done < <(required_sections "$lifecycle")

  if [[ $lifecycle == implemented ]]; then
    for want in "${FORBIDDEN_IN_IMPLEMENTED[@]}"; do
      list_has "$want" "$sections" \
        && note_violation "$rel: \"## $want\" is proposal-era; an implemented note states what is"
    done
  fi

  check_discipline "$rel" "$text"
}

# --- entry discipline ---------------------------------------------------------
#
# Optional structured entries (any lifecycle; historical notes without them are
# untouched — the rules bind only the entries that are present):
#   - Claim: <text>      requires sub-bullets verifier / coverage / goal-link
#   - Open: <text>       requires a sub-bullet settled-by
#   a statement containing "not-refuted" requires rate / schedule / reviewer in
#   the same paragraph (blank-line or heading delimited), inline or as
#   sub-bullets.
# A claim/open entry is its bullet plus the consecutive "  - " sub-bullets
# that follow it; the entry text itself must be non-empty.

# True when $1 is a two-space sub-bullet line.
is_sub_bullet() { [[ $1 == '  - '* ]]; }

# Value after "  - <field>: " in $1, or status 1 when absent or empty.
sub_bullet_value() { # <line> <field>
  [[ $1 == "  - $2: "* ]] || return 1
  REPLY=${1#"  - $2: "}
  [[ -n $REPLY ]] || return 1
}

# A paragraph is consecutive non-blank lines between blank lines or headings.
is_paragraph_break() { [[ -z $1 || $1 == '## '* ]]; }

# Check one claim/open entry: its sub-bullet block must carry every required
# field with a non-empty value. NLINES holds the note's lines; $3 is the
# entry's index.
check_entry_block() { # <rel> <entry-line> <index>
  local rel=$1 entry=$2 idx=$3 want missing='' line j fields=() kind
  if [[ $entry == '- Claim: '* ]]; then
    kind=Claim fields=(verifier coverage goal-link)
  else
    kind=Open fields=(settled-by)
  fi
  for want in "${fields[@]+"${fields[@]}"}"; do missing+="$want "; done
  j=$(( idx + 1 ))
  while (( j < ${#NLINES[@]} )) && is_sub_bullet "${NLINES[j]}"; do
    line=${NLINES[j]}
    for want in "${fields[@]+"${fields[@]}"}"; do
      sub_bullet_value "$line" "$want" && missing=${missing//"$want "/}
    done
    (( j++ ))
  done
  [[ -z $missing ]] \
    || note_violation "$rel: $kind entry \"${entry#- }\" missing sub-bullet(s): ${missing% }"
}

# Require rate/schedule/reviewer in the paragraph that carries "not-refuted".
require_sampling() { # <rel> <paragraph>
  local rel=$1 para=$2 missing='rate schedule reviewer ' line f re
  while IFS= read -r line; do
    for f in rate schedule reviewer; do
      re="(^|[^A-Za-z])${f}:[[:space:]]*[^[:space:]]"
      [[ $line =~ $re ]] \
        && missing=${missing//"$f "/}
    done
  done <<< "$para"
  [[ -z $missing ]] \
    || note_violation "$rel: statement containing \"not-refuted\" missing sampling field(s) in its paragraph: ${missing% }"
}

# Check a whole note body for the discipline rules; NLINES holds its lines.
check_discipline() { # <rel> <text>
  local rel=$1 text=$2 line i=0 para=''
  NLINES=()
  while IFS= read -r line || [[ -n $line ]]; do NLINES+=("$line"); done <<< "$text"
  while (( i < ${#NLINES[@]} )); do
    line=${NLINES[i]}
    if [[ $line == '- Claim: '* || $line == '- Open: '* ]]; then
      check_entry_block "$rel" "$line" "$i"
      (( i++ ))
      while (( i < ${#NLINES[@]} )) && is_sub_bullet "${NLINES[i]}"; do (( i++ )); done
      continue
    fi
    (( i++ ))
  done
  while IFS= read -r line; do
    if is_paragraph_break "$line"; then
      [[ $para == *'not-refuted'* ]] && require_sampling "$rel" "$para"
      para=''
    else
      para+=$'\n'"$line"
    fi
  done <<< "$text"
  [[ $para == *'not-refuted'* ]] && require_sampling "$rel" "$para"
}

# Validate the whole notes tree under $1 (default: this repository's tree).
collect_violations() { # <notes-dir>
  local dir=${1:-$NOTES_DIR} entry lifecycle class file rel is_lifecycle is_class
  NOTES_VIOLATIONS=()
  for entry in $(cd "$dir" && ls -A); do
    case $entry in
      README.md|archived) continue ;;
      INDEX.md)
        note_violation 'INDEX.md is forbidden: the tree layout is the index'
        continue ;;
    esac
    is_lifecycle=0
    for lifecycle in "${LIFECYCLES[@]}"; do
      [[ $entry == "$lifecycle" ]] && { is_lifecycle=1; break; }
    done
    if (( ! is_lifecycle )); then
      note_violation "$entry/: unknown lifecycle directory; closed set is ${LIFECYCLES[*]// /, }"
      continue
    fi
    for class in $(cd "$dir/$entry" && ls -A); do
      rel=$entry/$class
      if [[ ! -d "$dir/$rel" ]]; then
        note_violation "$rel: unexpected file directly under a lifecycle directory"
        continue
      fi
      is_class=0
      for c in "${CLASSES[@]}"; do
        [[ $class == "$c" ]] && { is_class=1; break; }
      done
      if (( ! is_class )); then
        note_violation "$rel/: unknown class; closed set is ${CLASSES[*]// /, }"
        continue
      fi
      for file in $(cd "$dir/$rel" && ls -A); do
        rel=$entry/$class/$file
        if [[ $file == INDEX.md ]]; then
          note_violation "$rel: INDEX.md is forbidden"
        elif [[ $file == *.md ]]; then
          check_note "$rel" "$dir/$rel"
        else
          note_violation "$rel: notes are English-only Markdown; unexpected file type"
        fi
      done
    done
  done
}

notes_main() {
  collect_violations "$NOTES_DIR"
  if (( ${#NOTES_VIOLATIONS[@]} == 0 )); then
    echo 'verify-agent-notes: the notes tree is valid.'
    return 0
  fi
  printf 'verify-agent-notes: %d violation(s):\n' "${#NOTES_VIOLATIONS[@]}" >&2
  local v
  for v in "${NOTES_VIOLATIONS[@]+"${NOTES_VIOLATIONS[@]}"}"; do
    printf '  %s\n' "$v" >&2
  done
  return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  notes_main
fi
