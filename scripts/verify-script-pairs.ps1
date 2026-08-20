#!/usr/bin/env pwsh
# Confirm twin-script pairs (pwsh twin of verify-script-pairs.sh).
#
# Every scripts/<name>.sh with a sibling <name>.ps1 is a pair. The manifest
# scripts/script-pairs.json pins each side's git blob hash at its last
# confirmed-consistent state: editing one side alone fails the gate until the
# pair is re-confirmed with -Write in the same change — the re-confirm is
# the explicit "the twin was considered" acknowledgment, covering both
# behavior fixes (touch both sides) and shell-specific fixes (touch one,
# re-record).
#
# A pair may also declare a behavioral probe (`"probe": "test"`): the gate
# then runs the pair's sibling test suites on both sides and compares the
# outputs AFTER pre-registered, versioned normalization (timestamp@v1,
# whitespace@v1 — the registry lives identically in both ports; bump the
# version in the same change that changes a normalizer). Still-unequal
# outputs fail loud naming the pair; raw bytes that differ but normalize
# equal are reported as a normalization blind-spot notice. The probe is
# opt-in per pair: pairs without one stay covered by hash freshness and the
# per-port suites.
#
# Fail loud: unconfirmed pairs, stale entries, drifted sides, unknown probe
# verbs, and probe failures abort with the offending name.

param([switch]$Write, [switch]$AsLib)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-BlobHash([string]$absPath) {
  (& git hash-object $absPath).Trim()
}

# --- versioned normalizers ------------------------------------------------------
# Pre-registered, versioned normalization applied to BOTH sides of a probe
# comparison before equality (normalization clause of the verification
# semantics). The registry is pinned identically in both ports; a version
# bump is a deliberate act in the same change that alters a normalizer.

$script:NormalizerVersions = 'timestamp:v1 whitespace:v1'

# Normalize one text with the named normalizer; throws on unknown names.
function Convert-NormalizedText([string]$text, [string]$name) {
  switch ($name) {
    'timestamp' {
      return [regex]::Replace($text, '[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}[T ][0-9]{1,2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?', '<TS>')
    }
    'whitespace' {
      $lines = @()
      foreach ($ln in @($text -split "`n")) {
        $lines += (($ln -replace '[ \t]+', ' ') -replace '^ ', '') -replace ' $', ''
      }
      return ($lines -join "`n")
    }
    default {
      throw "verify-script-pairs: unknown normalizer `"$name`"; registered: timestamp@v1, whitespace@v1"
    }
  }
}

# Apply every registered normalizer in order.
function Convert-NormalizedAll([string]$text) {
  foreach ($name in @('timestamp', 'whitespace')) {
    $text = Convert-NormalizedText $text $name
  }
  return $text
}

# Compare two probe outputs after normalization. Returns $true when
# normalized-equal ($script:ProbeNotice set when raw bytes differ — blind-spot
# candidate); $false with $script:CompareFirst naming the first differing
# normalized line.
function Compare-TwinOutputs([string]$rawA, [string]$rawB) {
  $script:ProbeNotice = ''
  $script:CompareFirst = ''
  $a = Convert-NormalizedAll $rawA
  $b = Convert-NormalizedAll $rawB
  if ($a -ceq $b) {
    if ($rawA -cne $rawB) {
      $script:ProbeNotice = 'raw outputs differ but normalized equal (normalization blind-spot candidate)'
    }
    return $true
  }
  $na = @($a -split "`n")
  $nb = @($b -split "`n")
  $width = [Math]::Max($na.Count, $nb.Count)
  for ($i = 0; $i -lt $width; $i++) {
    $aLine = if ($i -lt $na.Count) { $na[$i] } else { '<missing>' }
    $bLine = if ($i -lt $nb.Count) { $nb[$i] } else { '<missing>' }
    if ($aLine -cne $bLine) {
      $shortA = if ($aLine.Length -gt 100) { $aLine.Substring(0, 100) } else { $aLine }
      $shortB = if ($bLine.Length -gt 100) { $bLine.Substring(0, 100) } else { $bLine }
      $script:CompareFirst = "first difference at normalized line $($i + 1): sh=[$shortA] pwsh=[$shortB]"
      return $false
    }
  }
  return $false
}

# Run one pair's behavioral probe and compare both sides after normalization.
function Invoke-PairProbe([string]$root, [string]$name, $violations) {
  $shTest = Join-Path $root "scripts/$name.test.sh"
  $psTest = Join-Path $root "scripts/$name.test.ps1"
  if (-not (Test-Path -LiteralPath $shTest) -or -not (Test-Path -LiteralPath $psTest)) {
    $violations.Add("${name}: probe `"test`" requires $name.test.sh and $name.test.ps1")
    return
  }
  $outA = & bash $shTest 2>&1
  $rcA = $LASTEXITCODE
  $outB = & pwsh -NoProfile -File $psTest 2>&1
  $rcB = $LASTEXITCODE
  $side = @()
  if ($rcA -ne 0) { $side += 'sh' }
  if ($rcB -ne 0) { $side += 'pwsh' }
  if ($side.Count -gt 0) {
    $violations.Add("${name}: probe `"test`" failed on $($side -join ', ') (run the test suites directly for detail)")
    return
  }
  if (Compare-TwinOutputs ($outA -join "`n") ($outB -join "`n")) {
    if ($script:ProbeNotice) {
      $script:ProbeNotices.Add("${name}: $($script:ProbeNotice)")
    }
    return
  }
  $violations.Add("${name}: twin behaviors diverge after normalization — $($script:CompareFirst)")
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
  $script:ProbeNotices = [System.Collections.Generic.List[string]]::new()
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
    $probe = ''
    if ($entry -is [hashtable] -and $entry.ContainsKey('probe')) { $probe = [string]$entry['probe'] }
    if ($probe -and $probe -ne 'test') {
      $violations.Add("${name}: unknown probe verb `"$probe`"; the closed set is test")
      continue
    }
    $drifted = @()
    if ($entry -isnot [hashtable] -or -not $entry.ContainsKey('sh') -or "$($entry['sh'])" -ne $shHash) { $drifted += 'sh' }
    if ($entry -isnot [hashtable] -or -not $entry.ContainsKey('pwsh') -or "$($entry['pwsh'])" -ne $psHash) { $drifted += 'pwsh' }
    if ($drifted.Count -gt 0) {
      $violations.Add("${name}: $($drifted -join ' ') side edited since the last confirmed state — re-confirm with --write in the same change, or revert")
    }
    if ($probe) { Invoke-PairProbe $root $name $violations }
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
# port: sorted names, 2-space JSON, LF newlines. A surviving pair's probe
# setting is preserved: -Write refreshes hashes, never silently drops
# behavioral configuration.
function Write-ScriptPairManifest([string]$root = $script:Root) {
  $pairs = @(Get-ScriptPairNames $root)
  $old = @{}
  $manifestPath = Join-Path $root 'scripts/script-pairs.json'
  if (Test-Path -LiteralPath $manifestPath) {
    try { $old = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable } catch { $old = @{} }
  }
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("{`n")
  for ($i = 0; $i -lt $pairs.Count; $i++) {
    $sh = Get-BlobHash (Join-Path $root "scripts/$($pairs[$i]).sh")
    $ps = Get-BlobHash (Join-Path $root "scripts/$($pairs[$i]).ps1")
    [void]$sb.Append("  `"$($pairs[$i])`": {`n    `"sh`": `"$sh`",`n    `"pwsh`": `"$ps`"")
    if ($old.ContainsKey($pairs[$i]) -and $old[$pairs[$i]] -is [hashtable] -and $old[$pairs[$i]].ContainsKey('probe')) {
      [void]$sb.Append(",`n    `"probe`": `"$($old[$pairs[$i]]['probe'])`"")
    }
    [void]$sb.Append("`n  }")
    if ($i -lt $pairs.Count - 1) { [void]$sb.Append(',') }
    [void]$sb.Append("`n")
  }
  [void]$sb.Append("}`n")
  [IO.File]::WriteAllText($manifestPath, $sb.ToString())
  return $pairs.Count
}

function PairsMain([bool]$writeMode) {
  if ($writeMode) {
    $count = Write-ScriptPairManifest
    Write-Output "verify-script-pairs: recorded $count pair(s)."
  }
  $script:ProbeNotices = [System.Collections.Generic.List[string]]::new()
  $violations = Get-ScriptPairViolations
  if ($violations.Count -gt 0) {
    [Console]::Error.WriteLine("verify-script-pairs: $($violations.Count) violation(s):")
    foreach ($v in $violations) { [Console]::Error.WriteLine("  $v") }
    exit 1
  }
  foreach ($n in $script:ProbeNotices) {
    Write-Output "verify-script-pairs: notice: $n"
  }
  Write-Output 'verify-script-pairs: every twin pair confirmed at recorded contents.'
  exit 0
}

if (-not $AsLib) { PairsMain ([bool]$Write) }
