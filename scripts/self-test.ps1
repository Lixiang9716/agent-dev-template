#!/usr/bin/env pwsh
# Run every scripts/*.test.ps1, each in its own pwsh process, and fail if any
# fails. This is the `self-test` gate's pwsh-side command; self-test.sh runs
# the bash twin suite. A gate only guards if the regression actually fails it.
#
# Heavy lane: pairs marked "heavy" in scripts/script-pairs.json (one home,
# consumed by the self-test and pair gates alike) are skipped in light mode
# — GATES_FORCE_HEAVY unset, the default — with a counted, loud skip line;
# GATES_FORCE_HEAVY=1 (closed set {unset, 1}; any other value fails loud
# naming it) runs them. CI owns the heavy lane on a 12-hour schedule and
# forces it on any push or PR whose diff touches the heavy channel itself.

param([switch]$AsLib)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib.ps1')

$script:ManifestRel = 'scripts/script-pairs.json'

# Validate the GATES_FORCE_HEAVY closed set {unset, 1}; fails loud otherwise.
function Test-HeavyEnvValid {
  # Is-set semantics: the empty string is a set value, not an unset one, so
  # the closed set is exactly {unset, 1} — anything else, '' included, fails
  # loud naming it.
  if ($null -ne $env:GATES_FORCE_HEAVY -and $env:GATES_FORCE_HEAVY -ne '1') {
    [Console]::Error.WriteLine("self-test: GATES_FORCE_HEAVY=`"$env:GATES_FORCE_HEAVY`": unknown value — the closed set is {unset, 1} (unset means light)")
    return $false
  }
  return $true
}

# True when the heavy lane is forced.
function Test-HeavyLaneEnabled {
  return ($env:GATES_FORCE_HEAVY -eq '1')
}

# Load the heavy pair names from the manifest into $script:HeavyPairs. A
# missing or malformed manifest fails loud — the light/heavy decision must
# never guess.
function Import-HeavyPairs {
  $script:HeavyPairs = @{}
  $path = Join-Path $script:Root $script:ManifestRel
  if (-not (Test-Path -LiteralPath $path)) {
    [Console]::Error.WriteLine("self-test: $script:ManifestRel is missing — the heavy-lane decision cannot be made")
    return $false
  }
  try {
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
  } catch {
    [Console]::Error.WriteLine("self-test: $script:ManifestRel: $($_.Exception.Message)")
    return $false
  }
  foreach ($key in @($manifest.Keys)) {
    $entry = $manifest[$key]
    if ($entry -is [hashtable] -and $entry.ContainsKey('heavy') -and $entry['heavy'] -eq $true) {
      $script:HeavyPairs[$key] = $true
    }
  }
  return $true
}

# True when $1 is a heavy pair.
function Test-HeavyPair([string]$name) {
  return $script:HeavyPairs.ContainsKey($name)
}

# True when $1 (a pair name) must be skipped in the current mode: light mode
# skips heavy pairs; the forced heavy lane runs everything.
function Test-HeavyPairSkipped([string]$name) {
  if (Test-HeavyLaneEnabled) { return $false }
  return Test-HeavyPair $name
}

function Invoke-SelfTest {
  $script:SelfTestRc = 0
  if (-not (Test-HeavyEnvValid)) { $script:SelfTestRc = 1; return }
  if (-not (Import-HeavyPairs)) { $script:SelfTestRc = 1; return }
  $total = 0
  $failed = 0
  $skipped = 0
  foreach ($t in @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'scripts') -Filter '*.test.ps1' | Sort-Object Name)) {
    $total++
    $name = [IO.Path]::GetFileNameWithoutExtension($t.Name)
    if (Test-HeavyPairSkipped $name) {
      Write-Output "skipped: heavy suite $name — GATES_FORCE_HEAVY=1 forces it in scheduled CI"
      $skipped++
      continue
    }
    & pwsh -NoProfile -File $t.FullName
    if ($LASTEXITCODE -eq 0) {
      Write-Output "self-test: PASS $($t.Name)"
    } else {
      [Console]::Error.WriteLine("self-test: FAIL $($t.Name)")
      $failed++
    }
  }

  if ($total -eq 0) {
    [Console]::Error.WriteLine('self-test: no test files found under scripts/*.test.ps1')
    $script:SelfTestRc = 1
    return
  }
  if ($skipped -gt 0) {
    Write-Output "self-test: $total suite(s), $failed failed, $skipped skipped"
  } else {
    Write-Output "self-test: $total suite(s), $failed failed"
  }
  if ($failed -gt 0) { $script:SelfTestRc = 1 }
}

if (-not $AsLib) {
  # The call's output must flow to the pipeline; only the script-level status
  # becomes the process exit code — `return <value>` would both emit the value
  # and `exit (Invoke-SelfTest)` would swallow the output into the argument.
  Invoke-SelfTest
  exit $script:SelfTestRc
}
