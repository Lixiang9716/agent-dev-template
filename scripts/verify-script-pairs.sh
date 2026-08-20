#!/usr/bin/env bash
# Confirm twin-script pairs (bash port; pwsh twin: verify-script-pairs.ps1).
#
# Every scripts/<name>.sh with a sibling <name>.ps1 is a pair. The manifest
# scripts/script-pairs.json pins each side's git blob hash at its last
# confirmed-consistent state: editing one side alone fails the gate until the
# pair is re-confirmed with --write in the same change — the re-confirm is
# the explicit "the twin was considered" acknowledgment, covering both
# behavior fixes (touch both sides) and shell-specific fixes (touch one,
# re-record).
#
# A pair may also declare a behavioral probe (`"probe": "test"`): the gate
# then runs the pair's sibling test suites on both sides and compares the
# outputs AFTER pre-registered, versioned normalization (timestamp@v1,
# whitespace@v1 — the registry lives identically in both ports; bump the
# version in the same change that changes a normalizer). Still-unequal
# outputs fail loud naming the pair; raw bytes that differ but normalize
# equal are reported as a normalization blind-spot notice. The probe is
# opt-in per pair: pairs without one stay covered by hash freshness and the
# per-port suites.
#
# The probe is availability-aware: it runs only when the cross interpreter
# (pwsh) is on PATH. When it is missing, the probe is loudly skipped — one
# visible line per probed pair, exit code 0 — and the pair degrades to
# hash/record confirmation, so a bash-only host passes every local gate.
# GATES_FORCE_PROBE=1 (set by CI, which owns exhaustiveness per rule 9)
# forces the probe and fails loud naming the pair when the cross
# interpreter is missing.
#
# Fail loud: unconfirmed pairs, stale entries, drifted sides, unknown probe
# verbs, and probe failures abort with the offending name.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

MANIFEST_REL=scripts/script-pairs.json

PAIRS_VIOLATIONS=()
pairs_violation() { PAIRS_VIOLATIONS+=("$1"); }

# True when the cross interpreter (pwsh) is on PATH; the behavioral probe
# needs both interpreters.
pwsh_available() { command -v pwsh >/dev/null 2>&1; }

# --- versioned normalizers ------------------------------------------------------
# Pre-registered, versioned normalization applied to BOTH sides of a probe
# comparison before equality (normalization clause of the verification
# semantics). The registry is pinned identically in both ports; a version
# bump is a deliberate act in the same change that alters a normalizer.

NORMALIZER_VERSIONS='timestamp:v1 whitespace:v1'

# Normalize one text with the named normalizer; status 1 on unknown names.
normalize_text() { # <text> <normalizer-name>
  local text=$1 name=$2
  case $name in
    timestamp)
      printf '%s' "$text" | sed -E 's/[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}[T ][0-9]{1,2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?/<TS>/g' ;;
    whitespace)
      printf '%s' "$text" | sed -E 's/[ \t]+/ /g; s/^ //; s/ $//' ;;
    *)
      echo "verify-script-pairs: unknown normalizer \"$name\"; registered: timestamp@v1, whitespace@v1" >&2
      return 1 ;;
  esac
}

# Apply every registered normalizer in order.
normalize_all() { # <text>
  local text=$1 name out
  for name in timestamp whitespace; do
    out=$(normalize_text "$text" "$name") || return 1
    text=$out
  done
  printf '%s' "$text"
}

# Compare two probe outputs after normalization. Status 0 when normalized
# equal (PROBE_NOTICE set when raw bytes differ — blind-spot candidate);
# status 1 with COMPARE_FIRST naming the first differing normalized line.
twin_compare() { # <raw-a> <raw-b>
  local a b na nb a_line b_line i width
  a=$(normalize_all "$1") || return 2
  b=$(normalize_all "$2") || return 2
  PROBE_NOTICE='' COMPARE_FIRST=''
  if [[ $a == "$b" ]]; then
    [[ $1 != "$2" ]] && PROBE_NOTICE='raw outputs differ but normalized equal (normalization blind-spot candidate)'
    return 0
  fi
  na=(); while IFS= read -r l || [[ -n $l ]]; do na+=("$l"); done <<< "$a"
  nb=(); while IFS= read -r l || [[ -n $l ]]; do nb+=("$l"); done <<< "$b"
  width=$(( ${#na[@]} > ${#nb[@]} ? ${#na[@]} : ${#nb[@]} ))
  for (( i = 0; i < width; i++ )); do
    a_line=${na[i]-'<missing>'}
    b_line=${nb[i]-'<missing>'}
    if [[ $a_line != "$b_line" ]]; then
      COMPARE_FIRST="first difference at normalized line $(( i + 1 )): sh=[${a_line:0:100}] pwsh=[${b_line:0:100}]"
      return 1
    fi
  done
  return 1
}

# Run one pair's behavioral probe and compare both sides after normalization.
run_probe() { # <root> <name> <heavy>
  local root=$1 name=$2 heavy=$3 sh_test ps_test out_a out_b rc_a rc_b side=''
  sh_test="$root/scripts/$name.test.sh"
  ps_test="$root/scripts/$name.test.ps1"
  # Light mode skips a heavy pair's probe loudly — the heavy lane is owned by
  # the 12-hour scheduled CI job, and pushes touching the heavy channel force
  # it on that leg.
  if [[ $heavy == true && -z ${GATES_FORCE_HEAVY:-} ]]; then
    echo "probe skipped: $name — heavy pair; GATES_FORCE_HEAVY=1 forces it in scheduled CI"
    return 0
  fi
  if [[ ! -f $sh_test || ! -f $ps_test ]]; then
    pairs_violation "$name: probe \"test\" requires $name.test.sh and $name.test.ps1"
    return 0
  fi
  if ! pwsh_available; then
    if [[ ${GATES_FORCE_PROBE:-} == 1 ]]; then
      pairs_violation "$name: probe \"test\" cannot run — pwsh is not on PATH and GATES_FORCE_PROBE=1 forces the probe (CI owns exhaustiveness)"
    else
      # Loud skip: one visible line per probed pair, exit code 0 — the pair
      # stays hash/record-confirmed.
      echo "probe skipped: $name — pwsh not on PATH; cross-port behavioral consistency is verified in CI (GATES_FORCE_PROBE=1)"
    fi
    return 0
  fi
  out_a=$(bash "$sh_test" 2>&1); rc_a=$?
  out_b=$(pwsh -NoProfile -File "$ps_test" 2>&1); rc_b=$?
  (( rc_a != 0 )) && side+='sh'
  (( rc_b != 0 )) && side+="${side:+, }pwsh"
  if [[ -n $side ]]; then
    pairs_violation "$name: probe \"test\" failed on $side (run the test suites directly for detail)"
    return 0
  fi
  if twin_compare "$out_a" "$out_b"; then
    [[ -n $PROBE_NOTICE ]] && PROBE_NOTICES+=("$name: $PROBE_NOTICE")
    return 0
  fi
  pairs_violation "$name: twin behaviors diverge after normalization — $COMPARE_FIRST"
}

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
# A surviving pair's probe and heavy settings are preserved: --write
# refreshes hashes, never silently drops behavioral configuration.
write_manifest() { # <root>
  local root=$1 name i=0
  discover_pairs "$root"
  if [[ -f $root/$MANIFEST_REL ]] && json_parse "$(<"$root/$MANIFEST_REL")"; then
    : # previous manifest parsed; probe lookups below consult it
  fi
  {
    printf '{\n'
    for name in "${PAIR_NAMES[@]}"; do
      printf '  "%s": {\n    "sh": "%s",\n    "pwsh": "%s"' \
        "$name" "$(blob_hash "$root/scripts/$name.sh")" "$(blob_hash "$root/scripts/$name.ps1")"
      if json_get "\$.$name.probe" 2>/dev/null; then
        printf ',\n    "probe": "%s"' "$REPLY"
      fi
      if json_get "\$.$name.heavy" 2>/dev/null; then
        printf ',\n    "heavy": %s' "$REPLY"
      fi
      printf '\n  }'
      (( ++i < ${#PAIR_NAMES[@]} )) && printf ',' || true
      printf '\n'
    done
    printf '}\n'
  } > "$root/$MANIFEST_REL"
}

# Verify the manifest under $1 against current reality.
collect_state() { # <root>
  local root=$1 name rec_sh rec_ps have drifted key probe heavy
  discover_pairs "$root"

  # The env knobs' closed sets are {unset, 1}: any other value is a
  # misconfiguration and fails loud naming it (AGENTS.md rule 4).
  if [[ -n ${GATES_FORCE_PROBE:-} && $GATES_FORCE_PROBE != 1 ]]; then
    pairs_violation "GATES_FORCE_PROBE=\"$GATES_FORCE_PROBE\": unknown value — the closed set is 1 (unset means no force)"
  fi
  if [[ ${GATES_FORCE_HEAVY+x} == x && $GATES_FORCE_HEAVY != 1 ]]; then
    pairs_violation "GATES_FORCE_HEAVY=\"$GATES_FORCE_HEAVY\": unknown value — the closed set is {unset, 1} (unset means light)"
  fi

  local manifest="$root/$MANIFEST_REL"
  [[ -f $manifest ]] || { pairs_violation "$MANIFEST_REL: manifest missing — run --write and commit it"; return 0; }
  json_parse "$(<"$manifest")" || { pairs_violation "$MANIFEST_REL: $JSON_ERROR"; return 0; }

  for name in "${PAIR_NAMES[@]}"; do
    rec_sh='' rec_ps='' probe='' heavy='' have=0
    if json_get "\$.$name.sh" 2>/dev/null; then rec_sh=$REPLY; have=1; fi
    json_get "\$.$name.pwsh" 2>/dev/null && rec_ps=$REPLY
    json_get "\$.$name.probe" 2>/dev/null && probe=$REPLY
    if json_type "\$.$name.heavy" 2>/dev/null; then
      [[ $REPLY == bool ]] || { pairs_violation "$name: \"heavy\" must be a boolean"; continue; }
      json_get "\$.$name.heavy"; heavy=$REPLY
    fi
    if [[ -n $probe && $probe != test ]]; then
      pairs_violation "$name: unknown probe verb \"$probe\"; the closed set is test"
      continue
    fi
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
    [[ -n $probe ]] && run_probe "$root" "$name" "$heavy"
  done

  # Stale entries: manifest names with no pair on disk.
  json_keys '$'
  for key in "${REPLY_LIST[@]}"; do
    local found=0
    for name in "${PAIR_NAMES[@]}"; do
      [[ $key == "$name" ]] && { found=1; break; }
    done
    (( found )) || pairs_violation "$key: manifest entry has no pair on disk — refresh with --write"
    # A heavy mark is load-bearing in every mode: its twin files must exist,
    # so a deleted heavy suite is a named failure, never a silent skip.
    if json_get "\$.$key.heavy" 2>/dev/null && [[ $REPLY == true ]]; then
      [[ -f $root/scripts/$key.sh ]] || pairs_violation "$key: heavy pair's bash twin is missing — the heavy lane cannot run it"
      [[ -f $root/scripts/$key.ps1 ]] || pairs_violation "$key: heavy pair's pwsh twin is missing — the heavy lane cannot run it"
    fi
  done
}

pairs_main() { # <args...>
  if [[ ${1:-} == --write ]]; then
    write_manifest "$ROOT"
    echo "verify-script-pairs: recorded ${#PAIR_NAMES[@]} pair(s)."
  fi
  PAIRS_VIOLATIONS=()
  PROBE_NOTICES=()
  collect_state "$ROOT"
  if (( ${#PAIRS_VIOLATIONS[@]} > 0 )); then
    printf 'verify-script-pairs: %d violation(s):\n' "${#PAIRS_VIOLATIONS[@]}" >&2
    local v
    for v in "${PAIRS_VIOLATIONS[@]}"; do
      printf '  %s\n' "$v" >&2
    done
    return 1
  fi
  local n
  for n in ${PROBE_NOTICES[@]+"${PROBE_NOTICES[@]}"}; do
    printf 'verify-script-pairs: notice: %s\n' "$n"
  done
  echo 'verify-script-pairs: every twin pair confirmed at recorded contents.'
  return 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  pairs_main "$@"
fi
