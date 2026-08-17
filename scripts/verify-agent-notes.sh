#!/usr/bin/env bash
# Validate the Agent Notes tree (bash port; pwsh twin: verify-agent-notes.ps1):
# closed lifecycle and class sets, dated filenames, the three-line header, and
# the required sections per lifecycle. `archived/` is frozen and owned by
# archive-agent-notes.sh; this verifier never re-validates sealed content.
# Failures are collected and reported all at once with file-relative paths.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NOTES_DIR=$ROOT/.agents/notes

LIFECYCLES=(proposed implemented rejected)                       # closed set; archived/ is a sibling frozen tree
CLASSES=(feature bug-fix simplification architecture process testing) # closed set
declare -A REQUIRED_SECTIONS=(
  ['proposed']=$'Proposal\nAlternatives considered\nAcceptance criteria\nRisks'
  ['implemented']=$'Decision\nAlternatives considered\nConsequences'
  ['rejected']=$'Proposal\nAlternatives considered'
)
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
  lifecycle=${rel%%/*}
  name=${rel##*/}
  if ! [[ $name =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*[.]md$ ]]; then
    note_violation "$rel: filename must be yyyy-mm-dd-topic.md (kebab-case topic, dated at first proposal)"
    return 0
  fi
  mapfile -t lines < "$path"
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
  done <<< "${REQUIRED_SECTIONS[$lifecycle]}"

  if [[ $lifecycle == implemented ]]; then
    for want in "${FORBIDDEN_IN_IMPLEMENTED[@]}"; do
      list_has "$want" "$sections" \
        && note_violation "$rel: \"## $want\" is proposal-era; an implemented note states what is"
    done
  fi
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
  for v in "${NOTES_VIOLATIONS[@]}"; do
    printf '  %s\n' "$v" >&2
  done
  return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  notes_main
fi
