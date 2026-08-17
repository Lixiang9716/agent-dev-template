#!/usr/bin/env bash
# Report the explicit scope of a repository change as stable JSON (bash port;
# pwsh twin: change-scope.ps1).
#
# Consumers (the pre-push-checks and code-review skills) use this output to
# select the smallest sufficient check set for the outgoing diff instead of
# reflexively running every gate. The base is never guessed and never
# fetched: the caller passes a ref it has already verified.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

FORMAT_VERSION=1 # bumped whenever the output shape changes; consumers pin what they read

# Run one git command in $1, failing loud on any git error.
git_out() { # <repo-dir> <args...>
  local repo=$1; shift
  local out rc err_file err
  err_file=$(mktemp)
  out=$(git -C "$repo" "$@" 2>"$err_file")
  rc=$?
  if (( rc != 0 )); then
    err=$(<"$err_file")
    rm -f "$err_file"
    err="${err#"${err%%[![:space:]]*}"}" # leading
    err="${err%"${err##*[![:space:]]}"}" # trailing
    printf 'change-scope: git %s failed: %s\n' "$*" "$err" >&2
    return 1
  fi
  rm -f "$err_file"
  printf '%s' "${out%$'\n'}"
}

# JSON-escape one string value.
json_escape() { # <string>
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# Print a JSON array of paths, one element per line, 2-space indented at $1.
emit_path_array() { # <indent> <newline-separated paths>
  local indent=$1 paths=$2 p first=1
  if [[ -z $paths ]]; then
    printf '[]'
    return 0
  fi
  printf '[\n'
  while IFS= read -r p; do
    [[ -n $p ]] || continue
    (( first )) || printf ',\n'
    first=0
    printf '%s  "%s"' "$indent" "$(json_escape "$p")"
  done <<< "$paths"
  printf '\n%s]' "$indent"
}

# Collect the change scope of base..head plus the working tree; prints JSON.
collect_scope() { # <repo-dir> <base> [head]
  local repo=$1 base=$2 head=${3:-HEAD} base_sha head_sha merge_base out
  base_sha=$(git_out "$repo" rev-parse --verify "$base^{commit}") || return 1
  head_sha=$(git_out "$repo" rev-parse --verify "$head^{commit}") || return 1
  merge_base=$(git_out "$repo" merge-base "$base_sha" "$head_sha") || return 1

  local listed
  listed() { # <args...>
    local out
    out=$(git_out "$repo" "$@") || return 1
    if [[ -z $out ]]; then
      REPLY_LIST=''
    else
      REPLY_LIST=$(sort <<< "$out")
    fi
  }

  local committed staged unstaged untracked
  listed diff --name-only "$merge_base" "$head_sha" && committed=$REPLY_LIST || return 1
  listed diff --name-only --cached && staged=$REPLY_LIST || return 1
  listed diff --name-only && unstaged=$REPLY_LIST || return 1
  listed ls-files --others --exclude-standard && untracked=$REPLY_LIST || return 1

  printf '{\n'
  printf '  "formatVersion": %s,\n' "$FORMAT_VERSION"
  printf '  "base": "%s",\n' "$(json_escape "$base")"
  printf '  "baseSha": "%s",\n' "$base_sha"
  printf '  "head": "%s",\n' "$(json_escape "$head")"
  printf '  "headSha": "%s",\n' "$head_sha"
  printf '  "mergeBaseSha": "%s",\n' "$merge_base"
  printf '  "committed": %s,\n' "$(emit_path_array '  ' "$committed")"
  printf '  "staged": %s,\n' "$(emit_path_array '  ' "$staged")"
  printf '  "unstaged": %s,\n' "$(emit_path_array '  ' "$unstaged")"
  printf '  "untracked": %s\n' "$(emit_path_array '  ' "$untracked")"
  printf '}\n'
}

scope_main() { # <args...>
  local base head=HEAD
  while (( $# )); do
    if [[ $1 == --base && $# -ge 2 ]]; then
      base=$2; shift 2
    elif [[ $1 == --head && $# -ge 2 ]]; then
      head=$2; shift 2
    else
      printf 'change-scope: unknown argument "%s"; only --base <ref> [--head <ref>] is supported\n' "$1" >&2
      return 2
    fi
  done
  if [[ -z ${base:-} ]]; then
    echo 'change-scope: --base <ref> is required; pass a ref you have already verified — it is never guessed or fetched' >&2
    return 2
  fi
  collect_scope "$ROOT" "$base" "$head" || return 1
  return 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  scope_main "$@"
fi
