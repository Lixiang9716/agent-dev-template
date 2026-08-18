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

t_done
