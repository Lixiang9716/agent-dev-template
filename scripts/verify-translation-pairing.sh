#!/usr/bin/env bash
# Verify bilingual documentation pairs (bash port; pwsh twin:
# verify-translation-pairing.ps1).
#
# A pair is three sibling files: `foo.md` + `foo.zh.md` + `foo.i18n.yaml`.
# The sidecar records the git blob hash of each side at its last
# confirmed-consistent state, so a later edit on either side alone fails here
# until the pair is re-confirmed with --write in the same change. Structural
# signatures (heading counts, list counts, table rows, link targets,
# byte-identical fenced blocks) must also match. A green gate means the pair
# was confirmed consistent at these exact contents — not that the translation
# is good. Translation quality belongs to review.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
shopt -s globstar nullglob

PAIRING_VIOLATIONS=()
pairing_violation() { PAIRING_VIOLATIONS+=("$1"); }

# Compute the git blob hash of one file. Works on working-tree content.
blob_hash() { # <root> <path>
  local out
  out=$(git -C "$1" hash-object "$2" 2>&1)
  local rc=$?
  if (( rc != 0 )); then
    printf 'verify-translation-pairing: git hash-object failed for %s: %s\n' "$2" "$out" >&2
    return 1
  fi
  printf '%s' "$out"
}

# Expand the scope to sorted repo-relative English-side paths.
expand_scope() { # <root>
  local root=$1 f
  {
    for f in "$root"/*.md; do
      [[ -f $f ]] || continue
      [[ $f == *.zh.md ]] && continue
      printf '%s\n' "${f#"$root"/}"
    done
    for f in "$root"/docs/**/*.md; do
      [[ -f $f ]] || continue
      [[ $f == *.zh.md ]] && continue
      printf '%s\n' "${f#"$root"/}"
    done
  } | sort
}

# Read the exact sidecar shape: pair:\n  en: <hash>\n  zh: <hash>\n.
parse_sidecar() { # <path> — sets SIDECAR_EN / SIDECAR_ZH, or returns 1 with message in REPLY
  local lines
  mapfile -t lines < "$1"
  if (( ${#lines[@]} != 3 )) \
    || [[ ${lines[0]} != 'pair:' ]] \
    || [[ ${lines[1]} != '  en: '* ]] \
    || [[ ${lines[2]} != '  zh: '* ]]; then
    REPLY='must contain exactly "pair:", "  en: <hash>", "  zh: <hash>" (with a trailing newline)'
    return 1
  fi
  SIDECAR_EN=${lines[1]#  en: }
  SIDECAR_ZH=${lines[2]#  zh: }
}

# Count lines matching an extended regex.
count_matching() { # <text> <ere>
  grep -cE "$2" <<< "$1" || true
}

# Extract markdown link targets in order: every `](target)` occurrence, the
# target running to the first `)`. Mirrors the regex /\]\(([^)]+)\)/g.
extract_link_targets() { # <text> — prints one target per line
  local rest=$1 target
  while [[ $rest == *']('* ]]; do
    rest=${rest#*']('}
    [[ $rest == *')'* ]] || break
    target=${rest%%')'*}
    printf '%s\n' "$target"
    rest=${rest#*')'}
  done
}

# Extract fenced code blocks' exact bytes, joined by newlines; an unterminated
# fence is not a block. Mirrors /```[^\n]*\n[\s\S]*?```/g.
extract_fences() { # <text>
  awk '
    /^```/ {
      if (infence) { buf = buf $0 "\n"; blocks = blocks buf "\n"; buf = ""; infence = 0 }
      else { infence = 1; buf = $0 "\n" }
      next
    }
    infence { buf = buf $0 "\n" }
    END { printf "%s", blocks }
  ' <<< "$1"
}

# Canonicalized link targets with the document's own name dropped (each side
# legitimately links its own language; a target may carry a #anchor).
signature_links() { # <text> <own-canonical-name>
  local target anchor
  while IFS= read -r target; do
    if [[ $target == *".zh.md#"* ]]; then
      anchor=${target#*".zh.md#"}
      target="${target%%.zh.md#*}.md#$anchor"
    elif [[ $target == *.zh.md ]]; then
      target="${target%.zh.md}.md"
    fi
    [[ $target == "$2" ]] || printf '%s\n' "$target"
  done < <(extract_link_targets "$1")
}

# First differing signature key of the two sides, or empty when equal.
signature_diff() { # <en-path-rel> <zh-path-rel> <en-text> <zh-text>
  local en_rel=$1 zh_rel=$2 en=$3 zh=$4
  local en_name=${en_rel##*/} zh_name=${zh_rel##*/}
  local keys=(headings listItems tableRows linkTargets fences) key
  for key in "${keys[@]}"; do
    local a b
    case $key in
      headings)  a=$(count_matching "$en" '^#{1,6} '); b=$(count_matching "$zh" '^#{1,6} ') ;;
      listItems) a=$(count_matching "$en" '^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+'); b=$(count_matching "$zh" '^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+') ;;
      tableRows) a=$(count_matching "$en" '^\|'); b=$(count_matching "$zh" '^\|') ;;
      linkTargets) a=$(signature_links "$en" "$en_name"); b=$(signature_links "$zh" "$en_name") ;;
      fences)    a=$(extract_fences "$en"); b=$(extract_fences "$zh") ;;
    esac
    [[ $a == "$b" ]] || { printf '%s' "$key"; return 0; }
  done
  printf ''
}

# True when the first six lines contain a markdown link to $2.
links_counterpart() { # <text> <counterpart-name>
  local head target
  head=$(head -n 6 <<< "$1")
  while IFS= read -r target; do
    [[ $target == "$2" ]] && return 0
  done < <(extract_link_targets "$head")
  return 1
}

# Verify every pair in scope. <root> <english-side-path...>
collect_violations() {
  local root=$1; shift
  local sources=("$@")
  PAIRING_VIOLATIONS=()
  if (( ${#sources[@]} == 0 )); then
    mapfile -t sources < <(expand_scope "$root")
  fi
  local rel base en_rel zh_rel sidecar_rel en_path zh_path sidecar_path missing=()
  for rel in "${sources[@]}"; do
    base=${rel%.md}
    en_rel=$rel
    zh_rel=$base.zh.md
    sidecar_rel=$base.i18n.yaml
    en_path=$root/$en_rel
    zh_path=$root/$zh_rel
    sidecar_path=$root/$sidecar_rel
    missing=()
    [[ -f $en_path ]] || missing+=("$en_rel")
    [[ -f $zh_path ]] || missing+=("$zh_rel")
    [[ -f $sidecar_path ]] || missing+=("$sidecar_rel")
    if (( ${#missing[@]} > 0 )); then
      pairing_violation "$rel: incomplete pair — missing ${missing[*]}"
      continue
    fi
    if ! parse_sidecar "$sidecar_path"; then
      pairing_violation "verify-translation-pairing: $sidecar_rel $REPLY"
      continue
    fi
    local en_hash zh_hash stale=()
    en_hash=$(blob_hash "$root" "$en_rel") || return 1
    zh_hash=$(blob_hash "$root" "$zh_rel") || return 1
    [[ $SIDECAR_EN == "$en_hash" ]] || stale+=('English')
    [[ $SIDECAR_ZH == "$zh_hash" ]] || stale+=('中文')
    if (( ${#stale[@]} > 0 )); then
      local joined=${stale[0]} i
      for (( i = 1; i < ${#stale[@]}; i++ )); do joined+=" and ${stale[$i]}"; done
      pairing_violation "$rel: $joined side edited since the last confirmed state — re-confirm with --write in the same change, or revert"
    fi
    local en_text zh_text diff_key
    en_text=$(<"$en_path")
    zh_text=$(<"$zh_path")
    diff_key=$(signature_diff "$en_rel" "$zh_rel" "$en_text" "$zh_text")
    [[ -z $diff_key ]] || pairing_violation "$zh_rel: structural mismatch on $diff_key; both sides must carry the same structure"
    links_counterpart "$zh_text" "${en_rel##*/}" \
      || pairing_violation "$zh_rel: must link the English side in the first lines (language switcher)"
    links_counterpart "$en_text" "${zh_rel##*/}" \
      || pairing_violation "$en_rel: must link the Chinese side in the first lines (language switcher)"
  done
}

# Re-record one pair's hashes after a confirmed-consistent edit.
write_pair() { # <rel>
  local rel=$1 base en_rel zh_rel sidecar_rel
  base=${rel%.md}
  en_rel=$rel
  zh_rel=$base.zh.md
  sidecar_rel=$base.i18n.yaml
  local missing=()
  [[ -f $ROOT/$en_rel ]] || missing+=("$en_rel")
  [[ -f $ROOT/$zh_rel ]] || missing+=("$zh_rel")
  if (( ${#missing[@]} > 0 )); then
    printf 'verify-translation-pairing: cannot write an incomplete pair — missing %s\n' "${missing[*]}" >&2
    return 2
  fi
  local en_hash zh_hash
  en_hash=$(blob_hash "$ROOT" "$en_rel") || return 1
  zh_hash=$(blob_hash "$ROOT" "$zh_rel") || return 1
  printf 'pair:\n  en: %s\n  zh: %s\n' "$en_hash" "$zh_hash" > "$ROOT/$sidecar_rel"
  echo "verify-translation-pairing: recorded $en_rel"
  return 0
}

# Normalize a user path to a repo-relative path.
rel_from_root() { # <path>
  local p=$1 abs dir
  p=${p#./}
  if [[ $p == /* ]]; then
    abs=$p
  else
    dir=$(cd "$ROOT/$(dirname "$p")" 2>/dev/null && pwd) || return 1
    abs=$dir/$(basename "$p")
  fi
  printf '%s' "${abs#"$ROOT"/}"
}

pairing_main() { # <args...>
  if [[ ${1:-} == --write ]]; then
    if (( $# != 2 )); then
      echo 'verify-translation-pairing: --write takes exactly one English-side path, e.g. --write README.md' >&2
      return 2
    fi
    local rel
    rel=$(rel_from_root "$2") || { echo "verify-translation-pairing: no such path: $2" >&2; return 2; }
    write_pair "$rel"
    return $?
  fi
  if (( $# > 0 )); then
    echo 'verify-translation-pairing: unknown arguments; only --write <path> is supported' >&2
    return 2
  fi
  collect_violations "$ROOT"
  if (( ${#PAIRING_VIOLATIONS[@]} == 0 )); then
    echo 'verify-translation-pairing: all pairs confirmed consistent at recorded contents.'
    return 0
  fi
  printf 'verify-translation-pairing: %d violation(s):\n' "${#PAIRING_VIOLATIONS[@]}" >&2
  local v
  for v in "${PAIRING_VIOLATIONS[@]}"; do
    printf '  %s\n' "$v" >&2
  done
  return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  pairing_main "$@"
fi
