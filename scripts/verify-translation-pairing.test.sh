#!/usr/bin/env bash
# Pairing verifier tests: bash twin of verify-translation-pairing.test.ps1
# against real throwaway git repositories: a fresh recorded pair passes, a
# one-sided edit fails with the side named, a structural divergence fails
# with the signature key, and an incomplete pair is reported, not crashed on.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh
source scripts/verify-translation-pairing.sh 2>/dev/null

# Write a consistent English/Chinese pair body with the switcher links.
pair_body() { # <en|zh>
  if [[ $1 == en ]]; then
    printf '# Title en\n\n[中文](README.zh.md)\n\n## Section\n\nSome words.\n\n```sh\nmake check\n```\n'
  else
    printf '# Title zh\n\n[English](README.md)\n\n## Section\n\n一些文字。\n\n```sh\nmake check\n```\n'
  fi
}

# Create a temp git repo containing one valid recorded pair.
temp_repo_with_pair() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q
  pair_body en > "$dir/README.md"
  pair_body zh > "$dir/README.zh.md"
  printf 'pair:\n  en: %s\n  zh: %s\n' \
    "$(git -C "$dir" hash-object "$dir/README.md")" \
    "$(git -C "$dir" hash-object "$dir/README.zh.md")" > "$dir/README.i18n.yaml"
  REPLY_REPO=$dir
}

pairing_violations_of() { # <repo-dir> — prints violation list
  collect_violations "$1" README.md
  printf '%s\n' "${PAIRING_VIOLATIONS[@]}"
}

temp_repo_with_pair
out=$(pairing_violations_of "$REPLY_REPO")
expect_eq 'a recorded consistent pair passes clean' "$out" ''
rm -rf "$REPLY_REPO"

# A one-sided edit fails and names the edited side.
temp_repo_with_pair
pair_body zh | sed 's/一些文字。/更多文字。/' > "$REPLY_REPO/README.zh.md"
out=$(pairing_violations_of "$REPLY_REPO")
expect_eq 'a one-sided edit reports exactly one violation' "$(printf '%s\n' "$out" | grep -c .)" 1
expect_contains 'a one-sided edit names the Chinese side' "$out" '中文 side edited'
rm -rf "$REPLY_REPO"

# A structural divergence fails with the signature key and the stale hash.
temp_repo_with_pair
pair_body zh | sed 's/一些文字。/一些文字。\n\n- 列表项/' > "$REPLY_REPO/README.zh.md"
printf 'pair:\n  en: x\n  zh: y\n' > "$REPLY_REPO/README.i18n.yaml"
out=$(pairing_violations_of "$REPLY_REPO")
expect_contains 'a structural divergence names listItems' "$out" 'structural mismatch on listItems'
expect_contains 'the stale side is also named' "$out" 'edited since'
rm -rf "$REPLY_REPO"

# An incomplete pair is reported instead of crashing.
temp_repo_with_pair
rm "$REPLY_REPO/README.i18n.yaml"
out=$(pairing_violations_of "$REPLY_REPO")
expect_contains 'an incomplete pair is reported' "$out" 'incomplete pair'
rm -rf "$REPLY_REPO"

# A fence divergence fails on the fences signature.
temp_repo_with_pair
pair_body en > "$REPLY_REPO/README.md"
pair_body zh | sed 's/make check/make build/' > "$REPLY_REPO/README.zh.md"
printf 'pair:\n  en: %s\n  zh: %s\n' \
  "$(git -C "$REPLY_REPO" hash-object "$REPLY_REPO/README.md")" \
  "$(git -C "$REPLY_REPO" hash-object "$REPLY_REPO/README.zh.md")" > "$REPLY_REPO/README.i18n.yaml"
out=$(pairing_violations_of "$REPLY_REPO")
expect_contains 'a fence divergence names fences' "$out" 'structural mismatch on fences'
rm -rf "$REPLY_REPO"
# Anchored counterpart links canonicalize across languages; a differing
# anchor fails on linkTargets.
temp_repo_with_pair
pair_body en > "$REPLY_REPO/README.md"
printf '\n[deep](README.zh.md#section)\n' >> "$REPLY_REPO/README.md"
pair_body zh > "$REPLY_REPO/README.zh.md"
printf '\n[深链](README.md#section)\n' >> "$REPLY_REPO/README.zh.md"
printf 'pair:\n  en: %s\n  zh: %s\n' \
  "$(git -C "$REPLY_REPO" hash-object "$REPLY_REPO/README.md")" \
  "$(git -C "$REPLY_REPO" hash-object "$REPLY_REPO/README.zh.md")" > "$REPLY_REPO/README.i18n.yaml"
out=$(pairing_violations_of "$REPLY_REPO")
expect_eq 'anchored counterpart links pass clean' "$out" ''
sed -i 's|#section|#other|' "$REPLY_REPO/README.zh.md"
printf 'pair:\n  en: %s\n  zh: %s\n' \
  "$(git -C "$REPLY_REPO" hash-object "$REPLY_REPO/README.md")" \
  "$(git -C "$REPLY_REPO" hash-object "$REPLY_REPO/README.zh.md")" > "$REPLY_REPO/README.i18n.yaml"
out=$(pairing_violations_of "$REPLY_REPO")
expect_contains 'a differing anchor fails on linkTargets' "$out" 'structural mismatch on linkTargets'
rm -rf "$REPLY_REPO"

t_done
