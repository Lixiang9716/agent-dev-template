#!/usr/bin/env pwsh
# Confirm twin-script pairs (pwsh twin of verify-script-pairs.sh).
#
# Every scripts/<name>.sh with a sibling <name>.ps1 is a pair. The manifest
# scripts/script-pairs.json pins each side's git blob hash at its last
# confirmed-consistent state: editing one side alone fails the gate until the
# pair is re-confirmed with -Write in the same change — the re-confirm is
# the explicit "the twin was considered" acknowledgment, covering both
# behavior fixes (touch both sides) and shell-specific fixes (touch one,
# re-record). The manifest covers only hash freshness; behavioral
# equivalence stays with the per-port test suites and the CI matrix.
# Fail loud: unconfirmed pairs, stale entries, and drifted sides abort with
# the offending name.

param([switch]$Write, [switch]$AsLib)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-BlobHash([string]$absPath) {
  (& git hash-object $absPath).Trim()
}

# Discover pair names: every scripts/<name>.sh with a sibling <name>.ps1.
function Get-ScriptPairNames([string]$root = $script:Root) {
  @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Filter '*.sh' | Sort-Object Name | ForEach-Object {
    $ps1 = Join-Path $_.DirectoryName ($_.BaseName + '.ps1')
    if (Test-Path -LiteralPath $ps1) { $_.BaseName }
  })
}

function Get-ScriptPairViolations([string]$root = $script:Root) {
  $violations = [System.Collections.Generic.List[string]]::new()
  $pairs = @(Get-ScriptPairNames $root)
  $manifestPath = Join-Path $root 'scripts/script-pairs.json'
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    $violations.Add('scripts/script-pairs.json: manifest missing — run --write and commit it')
    return ,$violations
  }
  try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
  } catch {
    $violations.Add("scripts/script-pairs.json: $($_.Exception.Message)")
    return ,$violations
  }

  foreach ($name in $pairs) {
    $shHash = Get-BlobHash (Join-Path $root "scripts/$name.sh")
    $psHash = Get-BlobHash (Join-Path $root "scripts/$name.ps1")
    if (-not $manifest.ContainsKey($name)) {
      $violations.Add("${name}: pair not confirmed yet — run --write and commit the manifest")
      continue
    }
    $entry = $manifest[$name]
    $drifted = @()
    if ($entry -isnot [hashtable] -or -not $entry.ContainsKey('sh') -or "$($entry['sh'])" -ne $shHash) { $drifted += 'sh' }
    if ($entry -isnot [hashtable] -or -not $entry.ContainsKey('pwsh') -or "$($entry['pwsh'])" -ne $psHash) { $drifted += 'pwsh' }
    if ($drifted.Count -gt 0) {
      $violations.Add("${name}: $($drifted -join ' ') side edited since the last confirmed state — re-confirm with --write in the same change, or revert")
    }
  }

  # Stale entries: manifest names with no pair on disk.
  foreach ($key in @($manifest.Keys)) {
    if ($pairs -notcontains $key) {
      $violations.Add("${key}: manifest entry has no pair on disk — refresh with --write")
    }
  }

  return ,$violations
}

# Write the manifest from current reality — byte-identical with the bash
# port: sorted names, 2-space JSON, LF newlines.
function Write-ScriptPairManifest([string]$root = $script:Root) {
  $pairs = @(Get-ScriptPairNames $root)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("{`n")
  for ($i = 0; $i -lt $pairs.Count; $i++) {
    $sh = Get-BlobHash (Join-Path $root "scripts/$($pairs[$i]).sh")
    $ps = Get-BlobHash (Join-Path $root "scripts/$($pairs[$i]).ps1")
    [void]$sb.Append("  `"$($pairs[$i])`": {`n    `"sh`": `"$sh`",`n    `"pwsh`": `"$ps`"`n  }")
    if ($i -lt $pairs.Count - 1) { [void]$sb.Append(',') }
    [void]$sb.Append("`n")
  }
  [void]$sb.Append("}`n")
  [IO.File]::WriteAllText((Join-Path $root 'scripts/script-pairs.json'), $sb.ToString())
  return $pairs.Count
}

function PairsMain([bool]$writeMode) {
  if ($writeMode) {
    $count = Write-ScriptPairManifest
    Write-Output "verify-script-pairs: recorded $count pair(s)."
  }
  $violations = Get-ScriptPairViolations
  if ($violations.Count -gt 0) {
    [Console]::Error.WriteLine("verify-script-pairs: $($violations.Count) violation(s):")
    foreach ($v in $violations) { [Console]::Error.WriteLine("  $v") }
    exit 1
  }
  Write-Output 'verify-script-pairs: every twin pair confirmed at recorded contents.'
  exit 0
}

if (-not $AsLib) { PairsMain ([bool]$Write) }
