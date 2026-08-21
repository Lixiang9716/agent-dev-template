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
#
# Every suite execution is guarded by a stage-named timeout (600 s): on
# expiry the process tree is killed and the suite reports FAIL with the
# partial output instead of hanging forever (Windows pipe-handle hang).

param([switch]$AsLib)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib.ps1')
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_OPTIONAL_LOCKS = '0'

# Run $command in $dir with a stage-named timeout; output is redirected to
# files (never pipes — an inherited pipe handle hangs the reader on
# Windows) and on timeout the process tree is killed and TimedOutStage is
# set so the caller reports the FAIL with the captured output.
# Remove the capture files if they exist and only then. A cleanup must
# never crash the gate: paths are validated before removal and every removal
# is swallowed (a cleanup failure is noise, not a verdict — rule 4 fails on
# real failures, not on janitorial errors).
function Remove-CaptureFiles([string[]]$paths) {
  foreach ($p in @($paths)) {
    if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {
      try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop } catch { }
    }
  }
}

function Invoke-InDirTimed([string]$dir, [string]$stage, [int]$timeoutSeconds, [string]$command, [string[]]$arguments) {
  $script:TimedOutStage = $null
  if (-not $IsWindows) {
    # Fast path: direct invocation with pipe capture. The pipe-handle
    # inheritance hang is Windows-specific; the guarded Start-Process path
    # stays on Windows, where the CI hang was observed.
    Push-Location $dir
    try {
      $script:Captured = (@(& $command @arguments 2>&1) -join "`n")
      $script:CapturedRc = $LASTEXITCODE
    } finally {
      Pop-Location
    }
    return
  }
  # The stage names carry ':' (suite:adopt-plane.test), which is invalid in
  # Windows file names — the capture files get a sanitized component.
  $fileStage = $stage.Replace(':', '_').Replace('/', '_').Replace('\\', '_')
  $outFile = Join-Path ([IO.Path]::GetTempPath()) ('st-' + $fileStage + '-' + [Guid]::NewGuid().ToString('N'))
  $errFile = "$outFile.err"
  $proc = Start-Process -FilePath $command -ArgumentList $arguments -WorkingDirectory $dir `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru -NoNewWindow
  $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
  $timedOut = $false
  while (-not $proc.HasExited) {
    if ([DateTime]::UtcNow -gt $deadline) { $timedOut = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if ($timedOut) {
    if ($IsWindows) {
      $null = & taskkill /PID $proc.Id /T /F 2>$null
    } else {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    $proc.WaitForExit()
    $script:Captured = @("TIMEOUT after $timeoutSeconds s",
      (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue),
      (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue))
    $script:CapturedRc = 124
    $script:TimedOutStage = $stage
  } else {
    $script:Captured = @((Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue),
      (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue))
    $script:CapturedRc = $proc.ExitCode
  }
  Remove-CaptureFiles @($outFile, $errFile)
}

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
    Invoke-InDirTimed $script:Root "suite:$name" 3600 'pwsh' @('-NoProfile', '-File', $t.FullName)
    if ($script:TimedOutStage) {
      [Console]::Error.WriteLine("self-test: FAIL $($t.Name) (timeout after 3600s)")
      [Console]::Error.WriteLine(($script:Captured -join "`n"))
      $failed++
      continue
    }
    if ($script:CapturedRc -eq 0) {
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
