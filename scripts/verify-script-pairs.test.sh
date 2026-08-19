#!/usr/bin/env bash
# Twin-pair manifest tests (bash twin of verify-script-pairs.test.ps1): a
# confirmed tree passes clean; a one-sided edit fails naming the side; an
# unconfirmed new pair fails; a stale manifest entry fails; --write resolves
# freshness and removes staleness. A gate only guards if the regression
# actually fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh
source scripts/verify-script-pairs.sh 2>/dev/null

# Create a temp repo with one confirmed pair (alpha) in scripts/.
new_tree() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q
  mkdir "$dir/scripts"
  printf '#!/usr/bin/env bash\necho alpha\n' > "$dir/scripts/alpha.sh"
  printf '#!/usr/bin/env pwsh\necho alpha\n' > "$dir/scripts/alpha.ps1"
  REPLY_TREE=$dir
  write_manifest "$dir" >/dev/null 2>&1
}

violations_of() { # <tree>
  PAIRS_VIOLATIONS=()
  collect_state "$1"
  printf '%s\n' "${PAIRS_VIOLATIONS[@]}"
}

new_tree
out=$(violations_of "$REPLY_TREE")
expect_eq 'a confirmed pair passes clean' "$out" ''
tree=$REPLY_TREE

# A one-sided edit fails naming the drifted side.
printf '#!/usr/bin/env pwsh\necho beta\n' > "$tree/scripts/alpha.ps1"
out=$(violations_of "$tree")
expect_contains 'one-sided edit names the pwsh side' "$out" 'alpha: pwsh side edited'
rm -rf "$tree"

# An unconfirmed new pair fails.
new_tree
tree=$REPLY_TREE
printf '#!/usr/bin/env bash\necho b\n' > "$tree/scripts/beta.sh"
printf '#!/usr/bin/env pwsh\necho b\n' > "$tree/scripts/beta.ps1"
out=$(violations_of "$tree")
expect_contains 'unconfirmed pair reported' "$out" 'beta: pair not confirmed yet'
rm -rf "$tree"

# A stale manifest entry fails.
new_tree
tree=$REPLY_TREE
printf '{\n  "alpha": {\n    "sh": "x",\n    "pwsh": "y"\n  },\n  "ghost": {\n    "sh": "x",\n    "pwsh": "y"\n  }\n}\n' > "$tree/scripts/script-pairs.json"
out=$(violations_of "$tree")
expect_contains 'stale entry reported' "$out" 'ghost: manifest entry has no pair on disk'
expect_contains 'wrong hashes reported as drift' "$out" 'alpha: sh pwsh side edited'
rm -rf "$tree"

# --write resolves freshness and removes staleness.
new_tree
tree=$REPLY_TREE
printf '#!/usr/bin/env pwsh\necho gamma\n' > "$tree/scripts/alpha.ps1"
printf '#!/usr/bin/env bash\necho d\n' > "$tree/scripts/delta.sh"
printf '#!/usr/bin/env pwsh\necho d\n' > "$tree/scripts/delta.ps1"
write_manifest "$tree" >/dev/null 2>&1
out=$(violations_of "$tree")
expect_eq 'write resolves every freshness violation' "$out" ''
expect_eq 'manifest carries both pairs' "$(grep -c '": {' "$tree/scripts/script-pairs.json")" 2
rm -rf "$tree"

# --- versioned normalization (M3) ---------------------------------------------

expect_eq 'normalizer registry is pinned' "$NORMALIZER_VERSIONS" 'timestamp:v1 whitespace:v1'

twin_compare 'a b
c' 'a b
c'
expect_status 'identical raw bytes match' 0 $?
expect_eq 'no notice when raw bytes already match' "$PROBE_NOTICE" ''

twin_compare 'a   b
 c' 'a b
c'
expect_status 'whitespace normalization matches' 0 $?
expect_contains 'whitespace-only raw differences raise a blind-spot notice' "$PROBE_NOTICE" 'blind-spot'

twin_compare 'run at 2026-08-19T10:00:00' 'run at 2026-08-19T11:00:00Z'
expect_status 'timestamp normalization matches' 0 $?
expect_contains 'timestamp raw differences raise a blind-spot notice' "$PROBE_NOTICE" 'blind-spot'

twin_compare 'line one' 'line DIFFERENT'
expect_status 'real divergence fails' 1 $?
expect_contains 'divergence names the first differing line' "$COMPARE_FIRST" 'first difference at normalized line 1'

normalize_text 'x' magic >/dev/null 2>&1
expect_status 'unknown normalizer fails loud' 1 $?

# A fixture probe pair: alpha carries the probe; alpha.test is the confirmed
# test-suite pair the probe runs.
fixture_probe_tree() { # <probe-verb> — creates test suites unless told not to
  new_tree
  printf '#!/usr/bin/env bash\nprintf "3 check(s), 0 failed\\n"\n' > "$REPLY_TREE/scripts/alpha.test.sh"
  printf '#!/usr/bin/env pwsh\nWrite-Output "3 check(s), 0 failed"\n' > "$REPLY_TREE/scripts/alpha.test.ps1"
  printf '{\n  "alpha": {\n    "sh": "%s",\n    "pwsh": "%s",\n    "probe": "%s"\n  },\n  "alpha.test": {\n    "sh": "%s",\n    "pwsh": "%s"\n  }\n}\n' \
    "$(git -C "$REPLY_TREE" hash-object "$REPLY_TREE/scripts/alpha.sh")" \
    "$(git -C "$REPLY_TREE" hash-object "$REPLY_TREE/scripts/alpha.ps1")" "$1" \
    "$(git -C "$REPLY_TREE" hash-object "$REPLY_TREE/scripts/alpha.test.sh")" \
    "$(git -C "$REPLY_TREE" hash-object "$REPLY_TREE/scripts/alpha.test.ps1")" > "$REPLY_TREE/scripts/script-pairs.json"
}

# A probe pair whose twin test suites print identical outputs passes.
fixture_probe_tree test
out=$(violations_of "$REPLY_TREE")
expect_eq 'a matching probe passes' "$out" ''
rm -rf "$REPLY_TREE"

# A probe whose twin outputs diverge fails naming the pair.
fixture_probe_tree test
tree=$REPLY_TREE
printf '#!/usr/bin/env pwsh\nWrite-Output "4 check(s), 0 failed"\n' > "$tree/scripts/alpha.test.ps1"
printf '{\n  "alpha": {\n    "sh": "%s",\n    "pwsh": "%s",\n    "probe": "test"\n  },\n  "alpha.test": {\n    "sh": "%s",\n    "pwsh": "%s"\n  }\n}\n' \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.sh")" \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.ps1")" \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.test.sh")" \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.test.ps1")" > "$tree/scripts/script-pairs.json"
out=$(violations_of "$tree")
expect_contains 'a diverging probe fails naming the pair' "$out" 'alpha: twin behaviors diverge after normalization'
expect_contains 'divergence reports the differing line' "$out" 'first difference at normalized line 1'
rm -rf "$tree"

# A probe whose outputs differ only in timestamps passes.
fixture_probe_tree test
tree=$REPLY_TREE
printf '#!/usr/bin/env bash\necho run at 2026-08-19T10:00:00\n' > "$tree/scripts/alpha.test.sh"
printf '#!/usr/bin/env pwsh\nWrite-Output "run at 2026-08-19T11:00:00"\n' > "$tree/scripts/alpha.test.ps1"
printf '{\n  "alpha": {\n    "sh": "%s",\n    "pwsh": "%s",\n    "probe": "test"\n  },\n  "alpha.test": {\n    "sh": "%s",\n    "pwsh": "%s"\n  }\n}\n' \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.sh")" \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.ps1")" \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.test.sh")" \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.test.ps1")" > "$tree/scripts/script-pairs.json"
out=$(violations_of "$tree")
expect_eq 'timestamp-only probe differences normalize away' "$out" ''
rm -rf "$tree"

# A probe without sibling test suites fails loud.
new_tree
tree=$REPLY_TREE
printf '{\n  "alpha": {\n    "sh": "%s",\n    "pwsh": "%s",\n    "probe": "test"\n  }\n}\n' \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.sh")" \
  "$(git -C "$tree" hash-object "$tree/scripts/alpha.ps1")" > "$tree/scripts/script-pairs.json"
out=$(violations_of "$tree")
expect_contains 'probe without test siblings fails loud' "$out" 'probe "test" requires alpha.test.sh and alpha.test.ps1'
rm -rf "$tree"

# An unknown probe verb fails loud.
fixture_probe_tree bogus
out=$(violations_of "$REPLY_TREE")
expect_contains 'unknown probe verb fails loud' "$out" 'unknown probe verb "bogus"; the closed set is test'
rm -rf "$REPLY_TREE"

# --write preserves a surviving pair's probe configuration.
fixture_probe_tree test
tree=$REPLY_TREE
printf '#!/usr/bin/env pwsh\necho gamma\n' > "$tree/scripts/alpha.ps1"
write_manifest "$tree" >/dev/null 2>&1
expect_contains 'write preserves the probe setting' "$(cat "$tree/scripts/script-pairs.json")" '"probe": "test"'
out=$(violations_of "$tree")
expect_eq 'write re-confirms a probed pair cleanly' "$out" ''
rm -rf "$tree"

t_done
