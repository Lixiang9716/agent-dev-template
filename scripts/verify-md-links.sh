#!/usr/bin/env bash
# Verify that relative Markdown links and reference definitions resolve (bash
# port; pwsh twin: verify-md-links.ps1): the target file must exist, and a
# #fragment on a Markdown target must name a real heading slug (same-file
# #anchors included). Fenced code blocks are not scanned. URL, mailto:, and
# root-absolute targets are excluded; a ?query never affects resolution.
# Archived notes are frozen and excluded — a dead link there is unfixable.
# Explicit <a id> anchors are not recognized; state the heading instead.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
shopt -s nullglob

MDLINKS_VIOLATIONS=()
mdlinks_violation() { MDLINKS_VIOLATIONS+=("$1"); }

# Drop fenced code blocks (the fence lines themselves included).
strip_fences() { # <text>
  awk 'BEGIN { f = 0 } /^```/ { f = !f; next } !f { print }' <<< "$1"
}

# Print every link target in order: `](target)` occurrences plus reference
# definition targets (`[label]: target` lines).
extract_all_targets() { # <text>
  local rest=$1 target line
  local ref_re='^[[:space:]]*\[[^]]+\]:[[:space:]]*([^[:space:]]+)'
  while [[ $rest == *']('* ]]; do
    rest=${rest#*']('}
    [[ $rest == *')'* ]] || break
    target=${rest%%')'*}
    printf '%s\n' "$target"
    rest=${rest#*')'}
  done
  while IFS= read -r line; do
    [[ $line =~ $ref_re ]] \
      && printf '%s\n' "${BASH_REMATCH[1]}"
  done <<< "$1"
}

# GitHub-style heading slug: lowercase, spaces to hyphens, ASCII punctuation
# dropped, non-ASCII (CJK) preserved.
slugify() { # <heading-text>
  local s out='' i c
  s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]*$//')
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    if [[ $c == ' ' ]]; then out+='-'
    elif [[ $c =~ [a-z0-9_-] ]]; then out+=$c
    elif [[ $c == [![:ascii:]] ]]; then out+=$c
    fi
  done
  printf '%s' "$out"
}

# All heading slugs of one text, deduplicated GitHub-style (second -1, third -2).
heading_slugs() { # <text> — sets REPLY_SLUGS
  local line slug orig count i
  local head_re='^#{1,6}[[:space:]]+(.*)$'
  local seen=()
  REPLY_SLUGS=''
  while IFS= read -r line; do
    [[ $line =~ $head_re ]] || continue
    slug=$(slugify "${BASH_REMATCH[1]}")
    [[ -n $slug ]] || continue
    orig=$slug
    count=0
    for (( i = 0; i < ${#seen[@]}; i++ )); do
      [[ ${seen[i]} == "$slug" ]] && (( count++ ))
    done
    if (( count > 0 )); then
      slug="$slug-$count"
    fi
    seen+=("$orig")
    REPLY_SLUGS+="$slug"$'\n'
  done <<< "$1"
}

# Verify every in-scope Markdown file under $1 (default: this repository).
collect_violations() { # <root>
  local root=${1:-$ROOT} f text target path anchor base target_abs rel
  MDLINKS_VIOLATIONS=()
  local files=()
  while IFS= read -r f; do
    [[ -f $f ]] || continue
    [[ $f == "$root"/.agents/notes/archived/* ]] && continue
    files+=("${f#"$root"/}")
  done < <(find "$root" -type f -name '*.md' 2>/dev/null | sort)
  for f in "${files[@]}"; do
    text=$(strip_fences "$(<"$root/$f")")
    while IFS= read -r target; do
      [[ -n $target ]] || continue
      target=${target#'<'}; target=${target%'>'}
      case $target in
        http://*|https://*|mailto:*|tel:*|data:*) continue ;;
      esac
      target=${target%%\?*}
      path=${target%%#*}
      anchor=${target#*#}
      [[ $anchor == "$target" ]] && anchor=''
      if [[ -z $path ]]; then
        # Same-file anchor.
        heading_slugs "$text"
        if [[ -n $anchor ]] && ! grep -Fxq "$anchor" <<< "$REPLY_SLUGS"; then
          mdlinks_violation "$f: same-file anchor '#$anchor' names no heading"
        fi
        continue
      fi
      case $path in
        /*) continue ;; # root-absolute targets are excluded
      esac
      base=$(cd "$root/$(dirname "$f")/$(dirname "$path")" 2>/dev/null && pwd)
      if [[ -z $base ]]; then
        mdlinks_violation "$f: target '$path' does not resolve"
        continue
      fi
      target_abs="$base/$(basename "$path")"
      if [[ ! -e $target_abs ]]; then
        mdlinks_violation "$f: target '$path' does not exist"
        continue
      fi
      if [[ -n $anchor && $target_abs == *.md ]]; then
        heading_slugs "$(strip_fences "$(<"$target_abs")")"
        rel=${target_abs#"$root"/}
        if ! grep -Fxq "$anchor" <<< "$REPLY_SLUGS"; then
          mdlinks_violation "$f: anchor '#$anchor' on '$rel' names no heading"
        fi
      fi
    done < <(extract_all_targets "$text")
  done
}

mdlinks_main() {
  collect_violations "$ROOT"
  if (( ${#MDLINKS_VIOLATIONS[@]} == 0 )); then
    echo 'verify-md-links: every relative link and anchor resolves.'
    return 0
  fi
  printf 'verify-md-links: %d violation(s):\n' "${#MDLINKS_VIOLATIONS[@]}" >&2
  local v
  for v in "${MDLINKS_VIOLATIONS[@]}"; do
    printf '  %s\n' "$v" >&2
  done
  return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  mdlinks_main
fi
