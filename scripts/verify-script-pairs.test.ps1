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

Complete-TestSuite
