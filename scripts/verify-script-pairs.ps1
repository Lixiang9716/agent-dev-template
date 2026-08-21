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
# The probe is availability-aware: it runs only when the cross interpreter
# (bash) is on PATH. When it is missing, the probe is loudly skipped — one
# visible line per probed pair, exit code 0 — and the pair degrades to
# hash/record confirmation, so a pwsh-only host passes every local gate.
# GATES_FORCE_PROBE=1 (set by CI, which owns exhaustiveness per rule 9)
# forces the probe and fails loud naming the pair when the cross
# interpreter is missing.
#
# Fail loud: unconfirmed pairs, stale entries, drifted sides, unknown probe
# verbs, and probe failures abort with the offending name.

param([switch]$Write, [switch]$AsLib)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-BlobHash([string]$absPath) {
  Invoke-InDirTimed ([IO.Path]::GetDirectoryName($absPath)) 'hash' 120 'git' @('hash-object', [IO.Path]::GetFileName($absPath))
  if ($script:TimedOutStage) {
    throw "verify-script-pairs: blob hash of $absPath timed out after 120 s"
  }
  return ($script:Captured -split "`n")[0]
}

# True when the cross interpreter (bash) is on PATH; the behavioral probe
# needs both interpreters.
function Test-BashAvailable {
  return $null -ne (Get-Command bash -ErrorAction SilentlyContinue)
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
# normalized-equal ($script:ProbeNotice set when the trimmed raw bytes differ
# — blind-spot candidate); $false with $script:CompareFirst naming the first
# differing normalized line. Trailing blank lines are stripped from both
# sides first (the Windows guarded capture preserves a trailing newline the
# direct capture strips — symmetric tolerance, never a verdict).
function Convert-TrimTrailingBlanks([string]$text) {
  return $text.TrimEnd("`n")
}

function Compare-TwinOutputs([string]$rawA, [string]$rawB) {
  $script:ProbeNotice = ''
  $script:CompareFirst = ''
  $trimA = Convert-TrimTrailingBlanks $rawA
  $trimB = Convert-TrimTrailingBlanks $rawB
  $a = Convert-NormalizedAll $trimA
  $b = Convert-NormalizedAll $trimB
  if ($a -ceq $b) {
    if ($trimA -cne $trimB) {
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
# Loudly-skipped probes (cross interpreter absent, no force) are recorded in
# $script:ProbeSkips — one line per probed pair, never a violation; a forced
# probe (GATES_FORCE_PROBE=1) on such a host fails loud naming the pair.
# Light mode skips a heavy pair's probe loudly — the heavy lane is owned by
# the 12-hour scheduled CI job, and pushes touching the heavy channel force
# it on that leg.
function Invoke-PairProbe([string]$root, [string]$name, [string]$heavy, $violations) {
  $shTest = Join-Path $root "scripts/$name.test.sh"
  $psTest = Join-Path $root "scripts/$name.test.ps1"
  if ($heavy -eq 'true' -and -not $env:GATES_FORCE_HEAVY) {
    $script:ProbeSkips.Add("probe skipped: ${name} — heavy pair; GATES_FORCE_HEAVY=1 forces it in scheduled CI")
    return
  }
  if (-not (Test-Path -LiteralPath $shTest) -or -not (Test-Path -LiteralPath $psTest)) {
    $violations.Add("${name}: probe `"test`" requires $name.test.sh and $name.test.ps1")
    return
  }
  if (-not (Test-BashAvailable)) {
    if ($env:GATES_FORCE_PROBE -eq '1') {
      $violations.Add("${name}: probe `"test`" cannot run — bash is not on PATH and GATES_FORCE_PROBE=1 forces the probe (CI owns exhaustiveness)")
    } else {
      $script:ProbeSkips.Add("probe skipped: ${name} — bash not on PATH; cross-port behavioral consistency is verified in CI (GATES_FORCE_PROBE=1)")
    }
    return
  }
  Invoke-InDirTimed $root "probe:$name" 10800 'bash' @($shTest)
  if ($script:TimedOutStage) {
    $violations.Add("${name}: probe `"test`" timed out after 10800 s on the sh side")
    $violations.Add(($script:Captured -join "`n"))
    return
  }
  $outA = $script:Captured
  $rcA = $script:CapturedRc
  Invoke-InDirTimed $root "probe:$name" 10800 'pwsh' @('-NoProfile', '-File', $psTest)
  if ($script:TimedOutStage) {
    $violations.Add("${name}: probe `"test`" timed out after 10800 s on the pwsh side")
    $violations.Add(($script:Captured -join "`n"))
    return
  }
  $outB = $script:Captured
  $rcB = $script:CapturedRc
  $side = @()
  if ($rcA -ne 0) { $side += 'sh' }
  if ($rcB -ne 0) { $side += 'pwsh' }
  if ($side.Count -gt 0) {
    # Evidence over pointers: the failure tail (last 15 lines, |-joined) is
    # appended so the CI log names the failing check without a replay. The
    # bash twin strips exactly one trailing separator; mirror it exactly.
    $tailText = ''
    if ($rcA -ne 0) {
      $tailText = (@($outA -split "`n") | Select-Object -Last 15) -join '|'
    } else {
      $tailText = (@($outB -split "`n") | Select-Object -Last 15) -join '|'
    }
    if ($tailText.EndsWith('|')) { $tailText = $tailText.Substring(0, $tailText.Length - 1) }
    $violations.Add("${name}: probe `"test`" failed on $($side -join ', ') (tail: $tailText)")
    return
  }
  if (Compare-TwinOutputs $outA $outB) {
    if ($script:ProbeNotice) {
      $script:ProbeNotices.Add("${name}: $($script:ProbeNotice)")
    }
    return
  }
  $violations.Add("${name}: twin behaviors diverge after normalization — $($script:CompareFirst)")
}

# Discover pair names: every scripts/<name>.sh with a sibling <name>.ps1.
# Run $command with $arguments and cwd $dir, capturing combined output into
# $script:Captured and its status into $script:CapturedRc. Output is
# redirected to files (a descendant holding a pipe handle would hang the
# reader on Windows); on timeout the process tree is killed and
# $script:TimedOutStage is set so the caller can fail loud naming the pair.
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
  # The stage names carry ':' (probe:adopt-plane), which is invalid in
  # Windows file names — the capture files get a sanitized component.
  $fileStage = $stage.Replace(':', '_').Replace('/', '_').Replace('\\', '_')
  $outFile = Join-Path ([IO.Path]::GetTempPath()) ('vsp-' + $fileStage + '-' + [Guid]::NewGuid().ToString('N'))
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

# git must never sit waiting on a credential prompt or an index lock.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_OPTIONAL_LOCKS = '0'

function Get-ScriptPairNames([string]$root = $script:Root) {
  @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Filter '*.sh' | Sort-Object Name | ForEach-Object {
    $ps1 = Join-Path $_.DirectoryName ($_.BaseName + '.ps1')
    if (Test-Path -LiteralPath $ps1) { $_.BaseName }
  })
}

function Get-ScriptPairViolations([string]$root = $script:Root) {
  $violations = [System.Collections.Generic.List[string]]::new()
  $script:ProbeNotices = [System.Collections.Generic.List[string]]::new()
  $script:ProbeSkips = [System.Collections.Generic.List[string]]::new()

  # The env knobs' closed sets are {unset, 1}: any other value is a
  # misconfiguration and fails loud naming it (AGENTS.md rule 4).
  if ($env:GATES_FORCE_PROBE -and $env:GATES_FORCE_PROBE -ne '1') {
    $violations.Add("GATES_FORCE_PROBE=`"$($env:GATES_FORCE_PROBE)`": unknown value — the closed set is 1 (unset means no force)")
  }
  if ($null -ne $env:GATES_FORCE_HEAVY -and $env:GATES_FORCE_HEAVY -ne '1') {
    $violations.Add("GATES_FORCE_HEAVY=`"$($env:GATES_FORCE_HEAVY)`": unknown value — the closed set is {unset, 1} (unset means light)")
  }
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
    $heavy = ''
    if ($entry -is [hashtable] -and $entry.ContainsKey('heavy')) {
      if ($entry['heavy'] -isnot [bool]) {
        $violations.Add("${name}: `"heavy`" must be a boolean")
        continue
      }
      if ($entry['heavy']) { $heavy = 'true' }
    }
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
    if ($probe) { Invoke-PairProbe $root $name $heavy $violations }
  }

  # Stale entries: manifest names with no pair on disk.
  foreach ($key in @($manifest.Keys)) {
    if ($pairs -notcontains $key) {
      $violations.Add("${key}: manifest entry has no pair on disk — refresh with --write")
    }
    # A heavy mark is load-bearing in every mode: its twin files must exist,
    # so a deleted heavy suite is a named failure, never a silent skip.
    $entry = $manifest[$key]
    if ($entry -is [hashtable] -and $entry.ContainsKey('heavy') -and $entry['heavy'] -eq $true) {
      if (-not (Test-Path -LiteralPath (Join-Path $root "scripts/$key.sh"))) {
        $violations.Add("${key}: heavy pair's bash twin is missing — the heavy lane cannot run it")
      }
      if (-not (Test-Path -LiteralPath (Join-Path $root "scripts/$key.ps1"))) {
        $violations.Add("${key}: heavy pair's pwsh twin is missing — the heavy lane cannot run it")
      }
    }
  }

  return ,$violations
}

# Write the manifest from current reality — byte-identical with the bash
# port: sorted names, 2-space JSON, LF newlines. A surviving pair's probe
# and heavy settings are preserved: -Write refreshes hashes, never silently
# drops behavioral configuration.
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
    if ($old.ContainsKey($pairs[$i]) -and $old[$pairs[$i]] -is [hashtable] -and $old[$pairs[$i]].ContainsKey('heavy')) {
      if ($old[$pairs[$i]]['heavy']) { [void]$sb.Append(",`n    `"heavy`": true") } else { [void]$sb.Append(",`n    `"heavy`": false") }
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
  $script:ProbeSkips = [System.Collections.Generic.List[string]]::new()
  $violations = Get-ScriptPairViolations
  if ($violations.Count -gt 0) {
    [Console]::Error.WriteLine("verify-script-pairs: $($violations.Count) violation(s):")
    foreach ($v in $violations) { [Console]::Error.WriteLine("  $v") }
    exit 1
  }
  foreach ($n in $script:ProbeNotices) {
    Write-Output "verify-script-pairs: notice: $n"
  }
  foreach ($s in $script:ProbeSkips) {
    Write-Output $s
  }
  Write-Output 'verify-script-pairs: every twin pair confirmed at recorded contents.'
  exit 0
}

if (-not $AsLib) { PairsMain ([bool]$Write) }
