#!/usr/bin/env bash
# Confirm twin-script pairs (bash port; pwsh twin: verify-script-pairs.ps1).
#
# Every scripts/<name>.sh with a sibling <name>.ps1 is a pair. The manifest
# scripts/script-pairs.json pins each side's git blob hash at its last
# confirmed-consistent state: editing one side alone fails the gate until the
# pair is re-confirmed with --write in the same change — the re-confirm is
# the explicit "the twin was considered" acknowledgment, covering both
# behavior fixes (touch both sides) and shell-specific fixes (touch one,
# re-record). The manifest covers only hash freshness; behavioral
# equivalence stays with the per-port test suites and the CI matrix.
# Fail loud: unconfirmed pairs, stale entries, and drifted sides abort with
# the offending name.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

MANIFEST_REL=scripts/script-pairs.json

PAIRS_VIOLATIONS=()
pairs_violation() { PAIRS_VIOLATIONS+=("$1"); }

# Discover pair names: every scripts/<name>.sh with a sibling <name>.ps1.
discover_pairs() { # <root>
  local root=$1 f base
  PAIR_NAMES=()
  for f in "$root"/scripts/*.sh; do
    [[ -f $f ]] || continue
    base=$(basename "$f" .sh)
    [[ -f "$root/scripts/$base.ps1" ]] && PAIR_NAMES+=("$base")
  done
}

# Blob hash of one file (absolute path).
blob_hash() { # <abs-path>
  git hash-object "$1" 2>/dev/null
}

# Write the manifest from current reality (sorted pairs, current hashes).
write_manifest() { # <root>
  local root=$1 name i=0
  discover_pairs "$root"
  {
    printf '{\n'
    for name in "${PAIR_NAMES[@]}"; do
      printf '  "%s": {\n    "sh": "%s",\n    "pwsh": "%s"\n  }' \
        "$name" "$(blob_hash "$root/scripts/$name.sh")" "$(blob_hash "$root/scripts/$name.ps1")"
      (( ++i < ${#PAIR_NAMES[@]} )) && printf ',' || true
      printf '\n'
    done
    printf '}\n'
  } > "$root/$MANIFEST_REL"
}

# Verify the manifest under $1 against current reality.
collect_state() { # <root>
  local root=$1 name rec_sh rec_ps have drifted key
  discover_pairs "$root"

  local manifest="$root/$MANIFEST_REL"
  [[ -f $manifest ]] || { pairs_violation "$MANIFEST_REL: manifest missing — run --write and commit it"; return 0; }
  json_parse "$(<"$manifest")" || { pairs_violation "$MANIFEST_REL: $JSON_ERROR"; return 0; }

  for name in "${PAIR_NAMES[@]}"; do
    rec_sh='' rec_ps='' have=0
    if json_get "\$.$name.sh" 2>/dev/null; then rec_sh=$REPLY; have=1; fi
    json_get "\$.$name.pwsh" 2>/dev/null && rec_ps=$REPLY
    if (( ! have )); then
      pairs_violation "$name: pair not confirmed yet — run --write and commit the manifest"
      continue
    fi
    drifted=()
    [[ $rec_sh == "$(blob_hash "$root/scripts/$name.sh")" ]] || drifted+=(sh)
    [[ $rec_ps == "$(blob_hash "$root/scripts/$name.ps1")" ]] || drifted+=(pwsh)
    if (( ${#drifted[@]} > 0 )); then
      pairs_violation "$name: ${drifted[*]} side edited since the last confirmed state — re-confirm with --write in the same change, or revert"
    fi
  done

  # Stale entries: manifest names with no pair on disk.
  json_keys '$'
  for key in "${REPLY_LIST[@]}"; do
    local found=0
    for name in "${PAIR_NAMES[@]}"; do
      [[ $key == "$name" ]] && { found=1; break; }
    done
    (( found )) || pairs_violation "$key: manifest entry has no pair on disk — refresh with --write"
  done
}

pairs_main() { # <args...>
  if [[ ${1:-} == --write ]]; then
    write_manifest "$ROOT"
    echo "verify-script-pairs: recorded ${#PAIR_NAMES[@]} pair(s)."
  fi
  PAIRS_VIOLATIONS=()
  collect_state "$ROOT"
  if (( ${#PAIRS_VIOLATIONS[@]} > 0 )); then
    printf 'verify-script-pairs: %d violation(s):\n' "${#PAIRS_VIOLATIONS[@]}" >&2
    local v
    for v in "${PAIRS_VIOLATIONS[@]}"; do
      printf '  %s\n' "$v" >&2
    done
    return 1
  fi
  echo 'verify-script-pairs: every twin pair confirmed at recorded contents.'
  return 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  pairs_main "$@"
fi
