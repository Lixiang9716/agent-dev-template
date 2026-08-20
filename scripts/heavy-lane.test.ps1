#!/usr/bin/env pwsh
# Heavy/light lane separation tests (pwsh twin of heavy-lane.test.sh): the
# self-test gate skips heavy-marked suites in light mode (GATES_FORCE_HEAVY
# unset) with a counted skip line, the decision logic flips to "run" under
# GATES_FORCE_HEAVY=1, an unknown value fails loud naming it, and the pair
# gate rejects a heavy-marked entry whose twin files are missing. The suite
# itself is light: it never executes a heavy suite. A gate only guards if
# the regression actually fails it.

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib.ps1')

# Recursion guard: this suite invokes self-test.ps1 once (section a), and
# self-test runs every *.test.ps1 — including this file. The inner instance
# closes immediately instead of re-triggering the whole suite.
if ($env:HEAVY_LANE_GUARD -eq '1') {
  Complete-TestSuite
}
$env:HEAVY_LANE_GUARD = '1'
$env:GATES_FORCE_HEAVY = $null

. (Join-Path $PSScriptRoot 'self-test.ps1') -AsLib
. (Join-Path $PSScriptRoot 'verify-script-pairs.ps1') -AsLib

# (a) Light mode: the real self-test gate skips heavy-marked suites with a
# counted, loud line and passes — the inner invocation is pinned to light so
# the assertion never depends on the ambient mode. On foreign soil (a
# scaffold) the manifest carries no heavy marks, and the same machinery must
# run every suite: the assertions follow the local manifest.
[void](Import-HeavyPairs)
$env:GATES_FORCE_HEAVY = $null
$out = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'self-test.ps1') 2>&1
$outText = $out -join "`n"
Expect-Status 'light self-test exits 0' 0 $LASTEXITCODE
if (Test-HeavyPair 'adopt-plane.test') {
  Expect-Contains 'light self-test skips the heavy suite loudly' $outText 'skipped: heavy suite adopt-plane.test — GATES_FORCE_HEAVY=1 forces it in scheduled CI'
  Expect-Contains 'light self-test counts the skip' $outText ', 1 skipped'
} else {
  $skipCount = @(($outText -split "`n") | Where-Object { $_ -like 'skipped: heavy suite*' }).Count
  Expect-Eq 'light self-test runs every suite when nothing is heavy' $skipCount 0
}

# (b) The decision logic: heavy mode runs the heavy pair, light mode skips
# it, and a light pair is never skipped.
$env:GATES_FORCE_HEAVY = '1'
Expect-Eq 'heavy_lane_enabled is true under =1' "$(Test-HeavyLaneEnabled)" 'True'
Expect-Eq 'heavy pair is not skipped under =1' "$(Test-HeavyPairSkipped 'adopt-plane.test')" 'False'
$env:GATES_FORCE_HEAVY = $null
Expect-Eq 'heavy_lane_enabled is false when unset' "$(Test-HeavyLaneEnabled)" 'False'
$skipped = Test-HeavyPairSkipped 'adopt-plane.test'
if (Test-HeavyPair 'adopt-plane.test') {
  Expect-Eq 'heavy pair is skipped in light mode' "$skipped" 'True'
} else {
  Expect-Eq 'an unmarked pair is never skipped in light mode' "$skipped" 'False'
}
Expect-Eq 'a light pair is never skipped' "$(Test-HeavyPairSkipped 'verify-vocabulary.test')" 'False'
if (Test-HeavyPair 'adopt-plane.test') {
  Expect-Eq 'the manifest marks adopt-plane.test heavy' "$(Test-HeavyPair 'adopt-plane.test')" 'True'
} else {
  Expect-Eq 'the local manifest carries no heavy marks' "$(Test-HeavyPair 'adopt-plane.test')" 'False'
}

# (c) The closed set is {unset, 1} with is-set semantics: an unknown value
# and the empty string both fail loud, naming the offending value.
$env:GATES_FORCE_HEAVY = 'banana'
$out = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'self-test.ps1') 2>&1
$outText = $out -join "`n"
Expect-Status 'an unknown GATES_FORCE_HEAVY fails loud' 1 $LASTEXITCODE
Expect-Contains 'the failure names the offending value' $outText 'GATES_FORCE_HEAVY="banana": unknown value — the closed set is {unset, 1} (unset means light)'
$env:GATES_FORCE_HEAVY = $null
$env:GATES_FORCE_HEAVY = ''
$out = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'self-test.ps1') 2>&1
$outText = $out -join "`n"
Expect-Status 'an empty GATES_FORCE_HEAVY fails loud' 1 $LASTEXITCODE
Expect-Contains 'the empty-string failure names the value' $outText 'GATES_FORCE_HEAVY="": unknown value — the closed set is {unset, 1}'
$env:GATES_FORCE_HEAVY = $null

# (d) The pair gate validates heavy marks in every mode: an entry whose twin
# files are missing, and a non-boolean heavy field, both fail loud.
function Get-TreePairViolations([string]$tree) {
  return ((Get-ScriptPairViolations $tree) -join "`n")
}

$tree = Join-Path ([IO.Path]::GetTempPath()) ('heavy-lane.' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path (Join-Path $tree 'scripts') -Force)
[IO.File]::WriteAllText((Join-Path $tree 'scripts/alpha.sh'), "#!/usr/bin/env bash`necho alpha`n")
[IO.File]::WriteAllText((Join-Path $tree 'scripts/alpha.ps1'), "#!/usr/bin/env pwsh`necho alpha`n")
$shHash = (& git hash-object (Join-Path $tree 'scripts/alpha.sh')).Trim()
$psHash = (& git hash-object (Join-Path $tree 'scripts/alpha.ps1')).Trim()
[IO.File]::WriteAllText((Join-Path $tree 'scripts/script-pairs.json'),
  "{`n  `"alpha`": {`n    `"sh`": `"$shHash`",`n    `"pwsh`": `"$psHash`",`n    `"heavy`": true`n  },`n  `"ghost`": {`n    `"sh`": `"x`",`n    `"pwsh`": `"y`",`n    `"heavy`": true`n  }`n}`n")
$out = Get-TreePairViolations $tree
Expect-Contains 'a heavy entry with missing twins fails loud' $out 'ghost: heavy pair'
Expect-Contains 'the missing pair is also reported stale' $out 'manifest entry has no pair on disk'
Remove-Item -LiteralPath $tree -Recurse -Force

$tree = Join-Path ([IO.Path]::GetTempPath()) ('heavy-lane.' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path (Join-Path $tree 'scripts') -Force)
[IO.File]::WriteAllText((Join-Path $tree 'scripts/alpha.sh'), "#!/usr/bin/env bash`necho alpha`n")
[IO.File]::WriteAllText((Join-Path $tree 'scripts/alpha.ps1'), "#!/usr/bin/env pwsh`necho alpha`n")
$shHash = (& git hash-object (Join-Path $tree 'scripts/alpha.sh')).Trim()
$psHash = (& git hash-object (Join-Path $tree 'scripts/alpha.ps1')).Trim()
[IO.File]::WriteAllText((Join-Path $tree 'scripts/script-pairs.json'),
  "{`n  `"alpha`": {`n    `"sh`": `"$shHash`",`n    `"pwsh`": `"$psHash`",`n    `"heavy`": `"yes`"`n  }`n}`n")
$out = Get-TreePairViolations $tree
Expect-Contains 'a non-boolean heavy field fails loud' $out '"heavy" must be a boolean'
Remove-Item -LiteralPath $tree -Recurse -Force

Complete-TestSuite
