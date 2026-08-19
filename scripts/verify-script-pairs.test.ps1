#!/usr/bin/env pwsh
# Twin-pair manifest tests (pwsh twin of verify-script-pairs.test.sh): a
# confirmed tree passes clean; a one-sided edit fails naming the side; an
# unconfirmed new pair fails; a stale manifest entry fails; -Write resolves
# freshness and removes staleness. A gate only guards if the regression
# actually fails it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'verify-script-pairs.ps1') -AsLib:$true

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

# A probe without sibling test suites fails loud.
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

# -Write preserves a surviving pair's probe configuration.
New-FixtureProbeTree
$tree = $script:Tree
[IO.File]::WriteAllText("$tree/scripts/alpha.ps1", "#!/usr/bin/env pwsh`necho gamma`n")
[void](Write-ScriptPairManifest $tree)
Expect-Contains 'write preserves the probe setting' (Get-Content -LiteralPath "$tree/scripts/script-pairs.json" -Raw) '"probe": "test"'
$text = Get-ViolationsText $tree
Expect-Eq 'write re-confirms a probed pair cleanly' $text ''
Remove-Item -Recurse -Force $tree

Complete-TestSuite
