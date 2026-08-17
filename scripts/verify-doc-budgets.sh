#!/usr/bin/env bash
# Enforce word-count ceilings from scripts/doc-budgets.json on the English
# side of every in-scope document (bash port; pwsh twin: verify-doc-budgets.ps1).
# Ceilings ratchet down; raising one is a deliberate change to this manifest,
# made in the same PR that needs the words. The Chinese side is not counted;
# the English side is the canonical count for a pair.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

MANIFEST_PATH=$ROOT/scripts/doc-budgets.json

# Count words wc-style: whitespace-separated tokens.
word_count() { # <path>
  wc -w < "$1"
}

# Validate every budget entry.
collect_violations() {
  local raw
  BUDGET_VIOLATIONS=()
  raw=$(<"$MANIFEST_PATH")
  json_parse "$raw" || { BUDGET_VIOLATIONS+=("scripts/doc-budgets.json: $JSON_ERROR"); return 0; }
  json_type '$' || { BUDGET_VIOLATIONS+=('scripts/doc-budgets.json: manifest must be a JSON object'); return 0; }
  [[ $REPLY == object ]] || { BUDGET_VIOLATIONS+=('scripts/doc-budgets.json: manifest must be a JSON object'); return 0; }
  json_keys '$'
  local rel ceiling words
  for rel in "${REPLY_LIST[@]}"; do
    json_type "\$.$rel" || { BUDGET_VIOLATIONS+=("$rel: ceiling must be a positive integer"); continue; }
    [[ $REPLY == number ]] || { BUDGET_VIOLATIONS+=("$rel: ceiling must be a positive integer"); continue; }
    json_get "\$.$rel"; ceiling=$REPLY
    [[ $ceiling =~ ^[1-9][0-9]*$ ]] && (( ceiling <= 9007199254740991 )) \
      || { BUDGET_VIOLATIONS+=("$rel: ceiling must be a positive integer"); continue; }
    if [[ ! -f $ROOT/$rel ]]; then
      BUDGET_VIOLATIONS+=("$rel: budgeted document is missing — renamed or deleted? update scripts/doc-budgets.json in the same change")
      continue
    fi
    words=$(word_count "$ROOT/$rel")
    (( words > ceiling )) && BUDGET_VIOLATIONS+=("$rel: $words words exceed the $ceiling-word ceiling — relocate or condense, or raise the ceiling here with justification")
  done
}

budgets_main() {
  collect_violations
  if (( ${#BUDGET_VIOLATIONS[@]} == 0 )); then
    echo 'verify-doc-budgets: every budgeted document fits its ceiling.'
    return 0
  fi
  printf 'verify-doc-budgets: %d violation(s):\n' "${#BUDGET_VIOLATIONS[@]}" >&2
  local v
  for v in "${BUDGET_VIOLATIONS[@]}"; do
    printf '  %s\n' "$v" >&2
  done
  return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  budgets_main
fi
