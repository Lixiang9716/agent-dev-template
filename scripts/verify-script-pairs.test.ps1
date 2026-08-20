#!/usr/bin/env pwsh
# Twin-pair manifest tests (pwsh twin of verify-script-pairs.test.sh): a
# confirmed tree passes clean; a one-sided edit fails naming the side; an
# unconfirmed new pair fails; a stale manifest entry fails; -Write resolves
# freshness and removes staleness. A gate only guards if the regression
# actually fails it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'verify-script-pairs.ps1') -AsLib:$true

# The suite is hermetic: the availability tests manage GATES_FORCE_PROBE
# explicitly, so an ambient value (CI sets 1) must not leak into the
# manifest tests below.
$env:GATES_FORCE_PROBE = $null

# Create a temp repo with one confirmed pair (alpha) in scripts/.
$script:Tree = $null
function New-PairTree {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("pairs-" + [guid]::NewGuid())
  [IO.Directory]::CreateDirectory("$dir/scripts") | Out-Null
  & git -C $dir init -q
  [IO.File]::WriteAllText("$dir/scripts/alpha.sh", "#!/usr/bin/env bash`necho alpha`n")
  [IO.File]::WriteAllText("$dir/scripts/alpha.ps1", "#!/usr/bin/env pwsh`necho alpha`n")
  [void](Write-ScriptPairManifest $dir)
  $script:Tree = $dir
}

function Get-ViolationsText([string]$tree) {
  $v = Get-ScriptPairViolations $tree
  return (@($v) -join "`n")
}

New-PairTree
$text = Get-ViolationsText $script:Tree
Expect-Eq 'a confirmed pair passes clean' $text ''
$tree = $script:Tree

# A one-sided edit fails naming the drifted side.
[IO.File]::WriteAllText("$tree/scripts/alpha.ps1", "#!/usr/bin/env pwsh`necho beta`n")
$text = Get-ViolationsText $tree
Expect-Contains 'one-sided edit names the pwsh side' $text 'alpha: pwsh side edited'
Remove-Item -Recurse -Force $tree

# An unconfirmed new pair fails.
New-PairTree
$tree = $script:Tree
[IO.File]::WriteAllText("$tree/scripts/beta.sh", "#!/usr/bin/env bash`necho b`n")
[IO.File]::WriteAllText("$tree/scripts/beta.ps1", "#!/usr/bin/env pwsh`necho b`n")
$text = Get-ViolationsText $tree
Expect-Contains 'unconfirmed pair reported' $text 'beta: pair not confirmed yet'
Remove-Item -Recurse -Force $tree

# A stale manifest entry fails.
New-PairTree
$tree = $script:Tree
[IO.File]::WriteAllText("$tree/scripts/script-pairs.json", "{`n  `"alpha`": {`n    `"sh`": `"x`",`n    `"pwsh`": `"y`"`n  },`n  `"ghost`": {`n    `"sh`": `"x`",`n    `"pwsh`": `"y`"`n  }`n}`n")
$text = Get-ViolationsText $tree
Expect-Contains 'stale entry reported' $text 'ghost: manifest entry has no pair on disk'
Expect-Contains 'wrong hashes reported as drift' $text 'alpha: sh pwsh side edited'
Remove-Item -Recurse -Force $tree

# -Write resolves freshness and removes staleness.
New-PairTree
$tree = $script:Tree
[IO.File]::WriteAllText("$tree/scripts/alpha.ps1", "#!/usr/bin/env pwsh`necho gamma`n")
[IO.File]::WriteAllText("$tree/scripts/delta.sh", "#!/usr/bin/env bash`necho d`n")
[IO.File]::WriteAllText("$tree/scripts/delta.ps1", "#!/usr/bin/env pwsh`necho d`n")
[void](Write-ScriptPairManifest $tree)
$text = Get-ViolationsText $tree
Expect-Eq 'write resolves every freshness violation' $text ''
Expect-Eq 'manifest carries both pairs' @(([regex]::Matches((Get-Content -LiteralPath "$tree/scripts/script-pairs.json" -Raw), '": \{'))).Count 2
Remove-Item -Recurse -Force $tree

# --- versioned normalization (M3) ---------------------------------------------

Expect-Eq 'normalizer registry is pinned' $script:NormalizerVersions 'timestamp:v1 whitespace:v1'

$ok = Compare-TwinOutputs "a b`nc" "a b`nc"
Expect-Eq 'identical raw bytes match' $true $ok
Expect-Eq 'no notice when raw bytes already match' $script:ProbeNotice ''

$ok = Compare-TwinOutputs "a   b`n c" "a b`nc"
Expect-Eq 'whitespace normalization matches' $true $ok
Expect-Contains 'whitespace-only raw differences raise a blind-spot notice' $script:ProbeNotice 'blind-spot'

$ok = Compare-TwinOutputs 'run at 2026-08-19T10:00:00' 'run at 2026-08-19T11:00:00Z'
Expect-Eq 'timestamp normalization matches' $true $ok
Expect-Contains 'timestamp raw differences raise a blind-spot notice' $script:ProbeNotice 'blind-spot'

$ok = Compare-TwinOutputs 'line one' 'line DIFFERENT'
Expect-Eq 'real divergence fails' $false $ok
Expect-Contains 'divergence names the first differing line' $script:CompareFirst 'first difference at normalized line 1'

$threw = $false
try { [void](Convert-NormalizedText 'x' 'magic') } catch { $threw = $true }
Expect-Eq 'unknown normalizer fails loud' $true $threw

# A fixture probe pair: alpha carries the probe; alpha.test is the confirmed
# test-suite pair the probe runs.
function New-FixtureProbeTree([string]$probeVerb = 'test') {
  New-PairTree
  [IO.File]::WriteAllText("$script:Tree/scripts/alpha.test.sh", "#!/usr/bin/env bash`nprintf `"3 check(s), 0 failed\\n`"`n")
  [IO.File]::WriteAllText("$script:Tree/scripts/alpha.test.ps1", "#!/usr/bin/env pwsh`nWrite-Output `"3 check(s), 0 failed`"`n")
  [IO.File]::WriteAllText("$script:Tree/scripts/script-pairs.json",
    "{`n  `"alpha`": {`n    `"sh`": `"$(Get-BlobHash "$script:Tree/scripts/alpha.sh")`",`n    `"pwsh`": `"$(Get-BlobHash "$script:Tree/scripts/alpha.ps1")`",`n    `"probe`": `"$probeVerb`"`n  },`n  `"alpha.test`": {`n    `"sh`": `"$(Get-BlobHash "$script:Tree/scripts/alpha.test.sh")`",`n    `"pwsh`": `"$(Get-BlobHash "$script:Tree/scripts/alpha.test.ps1")`"`n  }`n}`n")
}

# The probe executes the cross interpreter (bash), so the probe tests below
# are loudly skipped on a bash-less host — counted, never failed — because
# CI's forced lane (GATES_FORCE_PROBE=1) owns cross-port exhaustiveness.
function Probe-Skip([string]$desc) {
  Expect-Skip "$desc (skipped: bash not on PATH; GATES_FORCE_PROBE=1 forces probes in CI)"
}

if (Test-BashAvailable) {
  # A probe pair whose twin test suites print identical outputs passes.
  New-FixtureProbeTree
  $text = Get-ViolationsText $script:Tree
  Expect-Eq 'a matching probe passes' $text ''
  Remove-Item -Recurse -Force $script:Tree

  # A probe whose twin outputs diverge fails naming the pair.
  New-FixtureProbeTree
  $tree = $script:Tree
  [IO.File]::WriteAllText("$tree/scripts/alpha.test.ps1", "#!/usr/bin/env pwsh`nWrite-Output `"4 check(s), 0 failed`"`n")
  [IO.File]::WriteAllText("$tree/scripts/script-pairs.json",
    "{`n  `"alpha`": {`n    `"sh`": `"$(Get-BlobHash "$tree/scripts/alpha.sh")`",`n    `"pwsh`": `"$(Get-BlobHash "$tree/scripts/alpha.ps1")`",`n    `"probe`": `"test`"`n  },`n  `"alpha.test`": {`n    `"sh`": `"$(Get-BlobHash "$tree/scripts/alpha.test.sh")`",`n    `"pwsh`": `"$(Get-BlobHash "$tree/scripts/alpha.test.ps1")`"`n  }`n}`n")
  $text = Get-ViolationsText $tree
  Expect-Contains 'a diverging probe fails naming the pair' $text 'alpha: twin behaviors diverge after normalization'
  Expect-Contains 'divergence reports the differing line' $text 'first difference at normalized line 1'
  Remove-Item -Recurse -Force $tree

  # A probe whose outputs differ only in timestamps passes.
  New-FixtureProbeTree
  $tree = $script:Tree
  [IO.File]::WriteAllText("$tree/scripts/alpha.test.sh", "#!/usr/bin/env bash`necho run at 2026-08-19T10:00:00`n")
  [IO.File]::WriteAllText("$tree/scripts/alpha.test.ps1", "#!/usr/bin/env pwsh`nWrite-Output `"run at 2026-08-19T11:00:00`"`n")
  [IO.File]::WriteAllText("$tree/scripts/script-pairs.json",
    "{`n  `"alpha`": {`n    `"sh`": `"$(Get-BlobHash "$tree/scripts/alpha.sh")`",`n    `"pwsh`": `"$(Get-BlobHash "$tree/scripts/alpha.ps1")`",`n    `"probe`": `"test`"`n  },`n  `"alpha.test`": {`n    `"sh`": `"$(Get-BlobHash "$tree/scripts/alpha.test.sh")`",`n    `"pwsh`": `"$(Get-BlobHash "$tree/scripts/alpha.test.ps1")`"`n  }`n}`n")
  $text = Get-ViolationsText $tree
  Expect-Eq 'timestamp-only probe differences normalize away' $text ''
  Remove-Item -Recurse -Force $tree
} else {
  Probe-Skip 'a matching probe passes'
  Probe-Skip 'a diverging probe fails naming the pair'
  Probe-Skip 'divergence reports the differing line'
  Probe-Skip 'timestamp-only probe differences normalize away'
}

# A probe without sibling test suites fails loud (no interpreter involved).
New-PairTree
$tree = $script:Tree
[IO.File]::WriteAllText("$tree/scripts/script-pairs.json",
  "{`n  `"alpha`": {`n    `"sh`": `"$(Get-BlobHash "$tree/scripts/alpha.sh")`",`n    `"pwsh`": `"$(Get-BlobHash "$tree/scripts/alpha.ps1")`",`n    `"probe`": `"test`"`n  }`n}`n")
$text = Get-ViolationsText $tree
Expect-Contains 'probe without test siblings fails loud' $text 'probe "test" requires alpha.test.sh and alpha.test.ps1'
Remove-Item -Recurse -Force $tree

# An unknown probe verb fails loud.
New-FixtureProbeTree 'bogus'
$text = Get-ViolationsText $script:Tree
Expect-Contains 'unknown probe verb fails loud' $text 'unknown probe verb "bogus"; the closed set is test'
Remove-Item -Recurse -Force $script:Tree

# Availability semantics: with the cross interpreter absent and no force, a
# probed pair is loudly skipped — one exact line, no violation, exit 0 — and
# stays hash-confirmed.
New-FixtureProbeTree
$tree = $script:Tree
$savedForce = $env:GATES_FORCE_PROBE
$env:GATES_FORCE_PROBE = $null
function Test-BashAvailable { return $false }
$v = Get-ScriptPairViolations $tree
Expect-Eq 'a probed pair stays hash-confirmed when the cross interpreter is missing' (@($v).Count) 0
Expect-Contains 'the skip is loud, names the pair, and points at CI' ($script:ProbeSkips -join "`n") 'probe skipped: alpha — bash not on PATH; cross-port behavioral consistency is verified in CI (GATES_FORCE_PROBE=1)'
Remove-Item -Recurse -Force $tree
function Test-BashAvailable { return $null -ne (Get-Command bash -ErrorAction SilentlyContinue) }
$env:GATES_FORCE_PROBE = $savedForce

# GATES_FORCE_PROBE=1 with the cross interpreter absent fails loud — CI owns
# exhaustiveness (AGENTS.md rule 9).
New-FixtureProbeTree
$tree = $script:Tree
$savedForce = $env:GATES_FORCE_PROBE
function Test-BashAvailable { return $false }
$env:GATES_FORCE_PROBE = '1'
$text = Get-ViolationsText $tree
Expect-Contains 'a forced probe without the cross interpreter fails loud' $text 'alpha: probe "test" cannot run — bash is not on PATH and GATES_FORCE_PROBE=1 forces the probe'
Remove-Item -Recurse -Force $tree
function Test-BashAvailable { return $null -ne (Get-Command bash -ErrorAction SilentlyContinue) }
$env:GATES_FORCE_PROBE = $savedForce

# GATES_FORCE_PROBE has a closed set: {unset, 1}; any other value fails loud
# naming the value (AGENTS.md rule 4).
New-FixtureProbeTree
$tree = $script:Tree
$env:GATES_FORCE_PROBE = 'true'
$text = Get-ViolationsText $tree
Expect-Contains 'an unknown GATES_FORCE_PROBE value fails loud' $text 'GATES_FORCE_PROBE="true": unknown value — the closed set is 1'
Remove-Item -Recurse -Force $tree
$env:GATES_FORCE_PROBE = $savedForce

# -Write preserves a surviving pair's probe configuration.
New-FixtureProbeTree
$tree = $script:Tree
[IO.File]::WriteAllText("$tree/scripts/alpha.ps1", "#!/usr/bin/env pwsh`necho gamma`n")
[void](Write-ScriptPairManifest $tree)
Expect-Contains 'write preserves the probe setting' (Get-Content -LiteralPath "$tree/scripts/script-pairs.json" -Raw) '"probe": "test"'
if (Test-BashAvailable) {
  $text = Get-ViolationsText $tree
  Expect-Eq 'write re-confirms a probed pair cleanly' $text ''
} else {
  Probe-Skip 'write re-confirms a probed pair cleanly'
}
Remove-Item -Recurse -Force $tree

Complete-TestSuite
