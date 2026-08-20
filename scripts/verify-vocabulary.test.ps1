#!/usr/bin/env pwsh
# Negative and positive tests for the vocabulary gate (pwsh twin of
# verify-vocabulary.test.sh): every banned form is rejected in both
# languages, every pre-registered exemption is honored, malformed manifests
# and missing scan targets fail loud, and the repository's own document
# surface passes the gate. A gate only guards if the regression actually
# fails it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'verify-vocabulary.ps1') -AsLib:$true

if (-not (Import-Vocabulary)) { throw 'test setup: repo vocabulary.json must load' }

# Scan one fixture line; leaves $script:VocabViolations filled.
function Invoke-Violations([string]$line) {
  $script:VocabViolations = [System.Collections.Generic.List[string]]::new()
  Scan-Line 'x.md' 1 $line
}

function Get-ViolationCount {
  return $script:VocabViolations.Count
}

Invoke-Violations '文档干净,无违规。'
Expect-Eq 'a clean line passes' (Get-ViolationCount) 0

Invoke-Violations '该结果已由 oracle verified。'
Expect-Eq 'en verified rejected' (Get-ViolationCount) 1
Expect-Contains 'en verified names the token' (@($script:VocabViolations) -join ' ') 'banned declaration-state word "verified"'
Invoke-Violations 'Result: Verified.'
Expect-Eq 'en verified is case-insensitive' (Get-ViolationCount) 1
Invoke-Violations 'The claim is confirmed.'
Expect-Eq 'en confirmed rejected' (Get-ViolationCount) 1
Invoke-Violations '结论:该声明已验证。'
Expect-Eq 'zh 已验证 rejected' (Get-ViolationCount) 1
Expect-Contains 'zh 已验证 names the token' (@($script:VocabViolations) -join ' ') '"已验证"'
Invoke-Violations '该机制已证实。'
Expect-Eq 'zh 已证实 rejected' (Get-ViolationCount) 1
Invoke-Violations '该声明已确认。'
Expect-Eq 'zh 已确认 rejected' (Get-ViolationCount) 1

# The concept-level en synonym family (pre-registered list).
foreach ($s in @('The claim is proven.', 'The result is certified.', 'The claim is validated.', 'The finding is corroborated.', 'This is proven correct.')) {
  Invoke-Violations $s
  Expect-Eq "en synonym rejected: $s" (Get-ViolationCount) 1
}

# The concept-level zh synonym family (pre-registered list).
foreach ($s in @('该结论被证实。', '该结果已经验证。', '该机制经过验证。', '该声明确认无误。', '该功能验证通过。', '该机制确证有效。', '该定理已证明。', '该结论经证实。', '该方案经验证。', '该事项核查通过。', '该设备已核验。', '该方案证实有效。', '该方案确认有效。')) {
  Invoke-Violations $s
  Expect-Eq "zh synonym rejected: $s" (Get-ViolationCount) 1
}

# A definition marker far away does not excuse.
Invoke-Violations '词汇门禁是平台治理机制。该结果 verified。'
Expect-Eq 'marker beyond the window does not excuse' (Get-ViolationCount) 1

# A definition marker AFTER the token does not excuse.
Invoke-Violations '该结果已 verified。严禁外传。'
Expect-Eq 'marker after the token does not excuse' (Get-ViolationCount) 1

# Meta-annotation whitelist: column names and table cells are allowed.
Invoke-Violations '列名:已验证状态'
Expect-Eq 'meta whitelist column allowed' (Get-ViolationCount) 0
Invoke-Violations '| 已验证状态 | 通过 |'
Expect-Eq 'meta whitelist table cell allowed' (Get-ViolationCount) 0

# A CJK prefix is not a delimiter: "处于X状态" is a declaration-state usage.
Invoke-Violations '该声明处于已确认状态。'
Expect-Eq 'zh state prose rejected (已确认)' (Get-ViolationCount) 1
Invoke-Violations '该声明处于已验证状态。'
Expect-Eq 'zh state prose rejected (已验证)' (Get-ViolationCount) 1

# Bare "verified status" in prose is a declaration state; backtick-quoted is a
# meta reference.
Invoke-Violations 'The result is in verified status.'
Expect-Eq 'en verified status prose rejected' (Get-ViolationCount) 1
Invoke-Violations 'column: `verified status`'
Expect-Eq 'en verified status backticked allowed' (Get-ViolationCount) 0

# Backtick-quoted tokens are meta references.
Invoke-Violations '禁止词表含 `verified` 字样。'
Expect-Eq 'backtick-quoted token allowed' (Get-ViolationCount) 0

# Definition sentences: a ban marker immediately before the token excuses it.
Invoke-Violations '本门禁禁用 verified 等声明状态词。'
Expect-Eq 'en definition sentence allowed' (Get-ViolationCount) 0
Invoke-Violations '门禁禁止 已验证 作为状态。'
Expect-Eq 'zh definition sentence allowed' (Get-ViolationCount) 0

# Word boundaries: "unverified" is not "verified".
Invoke-Violations 'The claim is unverified.'
Expect-Eq 'en word boundary respected' (Get-ViolationCount) 0
Invoke-Violations '状态verified'
Expect-Eq 'en boundary after CJK respected' (Get-ViolationCount) 0

# A malformed manifest fails loud naming the defect.
$bad = Join-Path ([IO.Path]::GetTempPath()) ("vocab-" + [guid]::NewGuid() + '.json')
[IO.File]::WriteAllText($bad, '{"version": 1, "banned": {}}')
$ok = Import-Vocabulary $bad
Expect-Eq 'malformed manifest rejected' $false $ok
Expect-Contains 'malformed manifest names the defect' (@($script:VocabViolations) -join ' ') 'scan must be a non-empty array of non-empty strings'
Remove-Item -Force $bad

$bad = Join-Path ([IO.Path]::GetTempPath()) ("vocab-" + [guid]::NewGuid() + '.json')
[IO.File]::WriteAllText($bad, '{not json')
$ok = Import-Vocabulary $bad
Expect-Eq 'unparseable manifest rejected' $false $ok
Expect-Contains 'unparseable manifest names the defect' (@($script:VocabViolations) -join ' ') 'json'
Remove-Item -Force $bad

# An unknown top-level key is rejected naming the offender (strict schema).
$bad = Join-Path ([IO.Path]::GetTempPath()) ("vocab-" + [guid]::NewGuid() + '.json')
[IO.File]::WriteAllText($bad, '{"version": 1, "extra": 1}')
$ok = Import-Vocabulary $bad
Expect-Eq 'unknown top-level key rejected' $false $ok
Expect-Contains 'unknown top-level key names the offender' (@($script:VocabViolations) -join ' ') 'unknown key "extra" at the manifest top level'
Remove-Item -Force $bad

# An unknown key inside "banned" is rejected naming the offender.
$bad = Join-Path ([IO.Path]::GetTempPath()) ("vocab-" + [guid]::NewGuid() + '.json')
[IO.File]::WriteAllText($bad, '{"version": 1, "banned": {"en": ["verified"], "zh": ["已验证"], "fr": ["verifie"]}}')
$ok = Import-Vocabulary $bad
Expect-Eq 'unknown banned key rejected' $false $ok
Expect-Contains 'unknown banned key names the offender' (@($script:VocabViolations) -join ' ') 'unknown key "fr" in "banned"'
Remove-Item -Force $bad

# A version that does not match the registered pin is rejected.
$bad = Join-Path ([IO.Path]::GetTempPath()) ("vocab-" + [guid]::NewGuid() + '.json')
[IO.File]::WriteAllText($bad, '{"version": 99, "scan": ["AGENTS.md"], "banned": {"en": ["verified"], "zh": ["已验证"]}, "metaWhitelist": ["验证状态"], "definitionMarkers": ["禁用"], "definitionWindow": 6}')
$ok = Import-Vocabulary $bad
Expect-Eq 'unregistered version rejected' $false $ok
Expect-Contains 'unregistered version names the pin' (@($script:VocabViolations) -join ' ') 'version 99 does not match the registered version 1'
Remove-Item -Force $bad

# A missing scan target fails loud; an empty glob match fails loud.
$script:ScanList = @('no-such-target.md')
$script:VocabViolations = [System.Collections.Generic.List[string]]::new()
Scan-Surface
Expect-Contains 'missing scan target fails loud' (@($script:VocabViolations) -join ' ') 'scan target missing: no-such-target.md'
$script:ScanList = @('docs/*.nomatch')
$script:VocabViolations = [System.Collections.Generic.List[string]]::new()
Scan-Surface
Expect-Contains 'empty glob match fails loud' (@($script:VocabViolations) -join ' ') 'matches no files'

# The gate passes its own document surface (AGENTS.md, AGENTS.zh.md, docs/*.md).
if (-not (Import-Vocabulary)) { throw 'repo vocabulary.json must load' }
$script:VocabViolations = [System.Collections.Generic.List[string]]::new()
Scan-Surface
Expect-Eq 'the repository document surface is clean' $script:VocabViolations.Count 0

Complete-TestSuite
