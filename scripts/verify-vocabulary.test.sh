#!/usr/bin/env bash
# Negative and positive tests for the vocabulary gate (bash twin of
# verify-vocabulary.test.ps1): every banned form is rejected in both
# languages, every pre-registered exemption is honored, malformed manifests
# and missing scan targets fail loud, and the repository's own document
# surface passes the gate. A gate only guards if the regression actually
# fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh
source scripts/verify-vocabulary.sh 2>/dev/null

load_vocabulary >/dev/null 2>&1 || { echo 'test setup: repo vocabulary.json must load' >&2; exit 1; }

# Scan one fixture line; leaves VOCAB_VIOLATIONS filled.
violations_of() { # <line>
  VOCAB_VIOLATIONS=()
  scan_line x.md 1 "$1"
}

violations_of '文档干净,无违规。'
expect_eq 'a clean line passes' "${#VOCAB_VIOLATIONS[@]}" 0

violations_of '该结果已由 oracle verified。'
expect_eq 'en verified rejected' "${#VOCAB_VIOLATIONS[@]}" 1
expect_contains 'en verified names the token' "${VOCAB_VIOLATIONS[*]}" 'banned declaration-state word "verified"'
violations_of 'Result: Verified.'
expect_eq 'en verified is case-insensitive' "${#VOCAB_VIOLATIONS[@]}" 1
violations_of 'The claim is confirmed.'
expect_eq 'en confirmed rejected' "${#VOCAB_VIOLATIONS[@]}" 1
violations_of '结论:该声明已验证。'
expect_eq 'zh 已验证 rejected' "${#VOCAB_VIOLATIONS[@]}" 1
expect_contains 'zh 已验证 names the token' "${VOCAB_VIOLATIONS[*]}" '"已验证"'
violations_of '该机制已证实。'
expect_eq 'zh 已证实 rejected' "${#VOCAB_VIOLATIONS[@]}" 1
violations_of '该声明已确认。'
expect_eq 'zh 已确认 rejected' "${#VOCAB_VIOLATIONS[@]}" 1

# The concept-level en synonym family (pre-registered list).
for s in 'The claim is proven.' 'The result is certified.' 'The claim is validated.' 'The finding is corroborated.' 'This is proven correct.'; do
  violations_of "$s"
  expect_eq "en synonym rejected: $s" "${#VOCAB_VIOLATIONS[@]}" 1
done

# The concept-level zh synonym family (pre-registered list).
for s in '该结论被证实。' '该结果已经验证。' '该机制经过验证。' '该声明确认无误。' '该功能验证通过。' '该机制确证有效。' '该定理已证明。' '该结论经证实。' '该方案经验证。' '该事项核查通过。' '该设备已核验。' '该方案证实有效。' '该方案确认有效。'; do
  violations_of "$s"
  expect_eq "zh synonym rejected: $s" "${#VOCAB_VIOLATIONS[@]}" 1
done

# A definition marker far away does not excuse.
violations_of '词汇门禁是平台治理机制。该结果 verified。'
expect_eq 'marker beyond the window does not excuse' "${#VOCAB_VIOLATIONS[@]}" 1

# A definition marker AFTER the token does not excuse.
violations_of '该结果已 verified。严禁外传。'
expect_eq 'marker after the token does not excuse' "${#VOCAB_VIOLATIONS[@]}" 1

# Meta-annotation whitelist: column names and table cells are allowed.
violations_of '列名:已验证状态'
expect_eq 'meta whitelist column allowed' "${#VOCAB_VIOLATIONS[@]}" 0
violations_of '| 已验证状态 | 通过 |'
expect_eq 'meta whitelist table cell allowed' "${#VOCAB_VIOLATIONS[@]}" 0

# A CJK prefix is not a delimiter: "处于X状态" is a declaration-state usage.
violations_of '该声明处于已确认状态。'
expect_eq 'zh state prose rejected (已确认)' "${#VOCAB_VIOLATIONS[@]}" 1
violations_of '该声明处于已验证状态。'
expect_eq 'zh state prose rejected (已验证)' "${#VOCAB_VIOLATIONS[@]}" 1

# Bare "verified status" in prose is a declaration state; backtick-quoted is a
# meta reference.
violations_of 'The result is in verified status.'
expect_eq 'en verified status prose rejected' "${#VOCAB_VIOLATIONS[@]}" 1
violations_of 'column: `verified status`'
expect_eq 'en verified status backticked allowed' "${#VOCAB_VIOLATIONS[@]}" 0

# Backtick-quoted tokens are meta references.
violations_of '禁止词表含 `verified` 字样。'
expect_eq 'backtick-quoted token allowed' "${#VOCAB_VIOLATIONS[@]}" 0

# Definition sentences: a ban marker immediately before the token excuses it.
violations_of '本门禁禁用 verified 等声明状态词。'
expect_eq 'en definition sentence allowed' "${#VOCAB_VIOLATIONS[@]}" 0
violations_of '门禁禁止 已验证 作为状态。'
expect_eq 'zh definition sentence allowed' "${#VOCAB_VIOLATIONS[@]}" 0

# Word boundaries: "unverified" is not "verified".
violations_of 'The claim is unverified.'
expect_eq 'en word boundary respected' "${#VOCAB_VIOLATIONS[@]}" 0
violations_of '状态verified'
expect_eq 'en boundary after CJK respected' "${#VOCAB_VIOLATIONS[@]}" 0

# A malformed manifest fails loud naming the defect.
bad=$(mktemp)
printf '%s\n' '{"version": 1, "banned": {}}' > "$bad"
load_vocabulary "$bad" >/dev/null 2>&1
expect_status 'malformed manifest rejected' 1 $?
expect_contains 'malformed manifest names the defect' "${VOCAB_VIOLATIONS[*]}" 'scan must be a non-empty array of non-empty strings'
rm -f "$bad"

bad=$(mktemp)
printf '%s\n' '{not json' > "$bad"
load_vocabulary "$bad" >/dev/null 2>&1
expect_status 'unparseable manifest rejected' 1 $?
expect_contains 'unparseable manifest names the defect' "${VOCAB_VIOLATIONS[*]}" 'json:'
rm -f "$bad"

# An unknown top-level key is rejected naming the offender (strict schema).
bad=$(mktemp)
printf '%s\n' '{"version": 1, "extra": 1}' > "$bad"
load_vocabulary "$bad" >/dev/null 2>&1
expect_status 'unknown top-level key rejected' 1 $?
expect_contains 'unknown top-level key names the offender' "${VOCAB_VIOLATIONS[*]}" 'unknown key "extra" at the manifest top level'
rm -f "$bad"

# An unknown key inside "banned" is rejected naming the offender.
bad=$(mktemp)
printf '%s\n' '{"version": 1, "banned": {"en": ["verified"], "zh": ["已验证"], "fr": ["verifie"]}}' > "$bad"
load_vocabulary "$bad" >/dev/null 2>&1
expect_status 'unknown banned key rejected' 1 $?
expect_contains 'unknown banned key names the offender' "${VOCAB_VIOLATIONS[*]}" 'unknown key "fr" in "banned"'
rm -f "$bad"

# A version that does not match the registered pin is rejected.
bad=$(mktemp)
printf '%s\n' '{"version": 99, "scan": ["AGENTS.md"], "banned": {"en": ["verified"], "zh": ["已验证"]}, "metaWhitelist": ["验证状态"], "definitionMarkers": ["禁用"], "definitionWindow": 6}' > "$bad"
load_vocabulary "$bad" >/dev/null 2>&1
expect_status 'unregistered version rejected' 1 $?
expect_contains 'unregistered version names the pin' "${VOCAB_VIOLATIONS[*]}" 'version 99 does not match the registered version 1'
rm -f "$bad"

# A missing scan target fails loud; an empty glob match fails loud.
SCAN_LIST=('no-such-target.md')
VOCAB_VIOLATIONS=()
scan_surface
expect_contains 'missing scan target fails loud' "${VOCAB_VIOLATIONS[*]}" 'scan target missing: no-such-target.md'
SCAN_LIST=('docs/*.nomatch')
VOCAB_VIOLATIONS=()
scan_surface
expect_contains 'empty glob match fails loud' "${VOCAB_VIOLATIONS[*]}" 'matches no files'

# The gate passes its own document surface (AGENTS.md, AGENTS.zh.md, docs/*.md).
load_vocabulary >/dev/null 2>&1 || exit 1
VOCAB_VIOLATIONS=()
scan_surface
expect_eq 'the repository document surface is clean' "${#VOCAB_VIOLATIONS[@]}" 0

t_done
