#!/usr/bin/env bash
# Link verifier tests (bash twin of verify-md-links.test.ps1): a valid tree
# passes clean; a missing file, a missing anchor on another file, a bad
# same-file anchor, and a dead reference definition each fail with the
# offending link named. Fenced links and URL targets are never flagged.
# A gate only guards if the regression actually fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh
source scripts/verify-md-links.sh 2>/dev/null

violations_of() { # <root-dir>
  collect_violations "$1"
  printf '%s\n' "${MDLINKS_VIOLATIONS[@]}"
}

# A valid tree: file link, cross-file anchor, same-file anchor, URL, fenced link.
tree=$(mktemp -d)
cat > "$tree/README.md" <<'EOF'
# Title

[中文](README.zh.md#section-one) and [docs](docs/guide.md) and [web](https://example.com/x).

```sh
[fenced](missing-inside-fence.md)
```

[anchor](#title)
EOF
cat > "$tree/README.zh.md" <<'EOF'
# 标题

[English](README.md#title)

## 第一节
EOF
sed 's/# 标题/# 标题/' "$tree/README.zh.md" > "$tree/README.zh.md.tmp" && mv "$tree/README.zh.md.tmp" "$tree/README.zh.md"
mkdir -p "$tree/docs"
printf '# Guide\n\n## Overview\n' > "$tree/docs/guide.md"
# The zh side anchors #section-one; give the en file that slug via its heading.
sed '1s/# Title/# Title/' "$tree/README.md" > "$tree/README.md.tmp" && mv "$tree/README.md.tmp" "$tree/README.md"
# README.md heading "# Title" has slug title; README.zh.md needs a heading
# whose slug is section-one for the cross-file anchor in README.md.
printf '\n## Section one\n' >> "$tree/README.zh.md"
out=$(violations_of "$tree")
expect_eq 'a valid tree passes clean' "$out" ''
rm -rf "$tree"

# A missing file fails with the link named.
tree=$(mktemp -d)
printf '# T\n\n[x](gone.md)\n' > "$tree/README.md"
out=$(violations_of "$tree")
expect_contains 'missing file reported' "$out" "target 'gone.md' does not exist"
rm -rf "$tree"

# A missing anchor on another file fails with both names.
tree=$(mktemp -d)
printf '# T\n\n[x](README.zh.md#nope)\n' > "$tree/README.md"
printf '# Z\n' > "$tree/README.zh.md"
out=$(violations_of "$tree")
expect_contains 'missing cross-file anchor reported' "$out" "anchor '#nope' on 'README.zh.md' names no heading"
rm -rf "$tree"

# A bad same-file anchor fails.
tree=$(mktemp -d)
printf '# T\n\n[x](#ghost)\n' > "$tree/README.md"
out=$(violations_of "$tree")
expect_contains 'bad same-file anchor reported' "$out" "same-file anchor '#ghost' names no heading"
rm -rf "$tree"

# A dead reference definition fails; archived notes are skipped.
tree=$(mktemp -d)
printf '# T\n\n[ref]\n\n[ref]: gone-again.md\n' > "$tree/README.md"
mkdir -p "$tree/.agents/notes/archived"
printf '# Frozen\n\n[dead](broken.md)\n' > "$tree/.agents/notes/archived/2026-01-01-frozen.md"
out=$(violations_of "$tree")
expect_contains 'dead reference definition reported' "$out" "target 'gone-again.md' does not exist"
expect_eq 'archived notes are not link-checked' "$(grep -c 'broken.md' <<< "$out" || true)" 0
rm -rf "$tree"

t_done
