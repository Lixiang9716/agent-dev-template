#!/usr/bin/env pwsh
# Declarative DAG gate scheduler (pwsh port; the bash twin is gates.sh).
#
# Runs one mode from gates.json: a gate starts once every gate in its `needs`
# has passed, bounded by the concurrency limit; a failed dependency marks its
# dependents skipped with the reason instead of running them. Config problems
# (duplicate ids, unknown needs, dependency cycles, unknown modes) abort
# before any child process starts — a gate list that cannot be executed
# unambiguously is never best-effort run.
#
# Command slots: a plain array runs under both shells; an object declares
# per-shell variants and must name every shell in the closed set (sh, pwsh) —
# a missing variant aborts instead of silently skipping on that platform.
#
# Requires PowerShell 7+ (pwsh). See docs/architecture.md.

param(
  [string]$Mode = 'all',
  [switch]$AsLib
)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ConfigPath = Join-Path $script:Root 'gates.json'

# --- config validation ------------------------------------------------------------

# Throw [Exception] with a plain message; GatesMain prefixes and exits.
function GatesThrow([string]$msg) { throw [Exception]::new($msg) }

# Validate one command slot value: a non-empty string array (shared by both
# shells) or an object with a valid variant for every shell in the closed set.
function Test-CommandSlot([string]$gateId, $command) {
  if ($command -is [System.Array]) {
    $arr = @($command)
    $nonStrings = @($arr | Where-Object { $_ -isnot [string] })
    if ($arr.Count -eq 0 -or $nonStrings.Count -gt 0) {
      GatesThrow "gate `"$gateId`" needs a non-empty command string array"
    }
    return , $arr
  }
  if ($command -isnot [hashtable]) {
    GatesThrow "gate `"$gateId`" needs a non-empty command string array"
  }
  $shells = @($command.Keys)
  foreach ($shell in $shells) {
    if ($shell -ne 'sh' -and $shell -ne 'pwsh') {
      GatesThrow "gate `"$gateId`" command declares unknown shell `"$shell`"; the closed set is sh, pwsh"
    }
  }
  $useVariant = $null
  foreach ($shell in @('sh', 'pwsh')) {
    if ($shells -notcontains $shell) {
      GatesThrow "gate `"$gateId`" command must declare both `"sh`" and `"pwsh`" variants"
    }
    $variant = @($command[$shell])
    $variantNonStrings = @($variant | Where-Object { $_ -isnot [string] })
    if ($variant.Count -eq 0 -or $variantNonStrings.Count -gt 0) {
      GatesThrow "gate `"$gateId`" `"$shell`" command must be a non-empty string array"
    }
    # This port runs the pwsh variant; the sh variant is validated, not run.
    if ($shell -eq 'pwsh') { $useVariant = $variant }
  }
  return , $useVariant
}

# Validate the whole gates.json content string into $script:Gates (ordered
# id list + per-id label/command/needs/allowFailure) and $script:GatesModes.
function Invoke-ValidateConfig([string]$raw) {
  try {
    $config = $raw | ConvertFrom-Json -AsHashtable
  } catch {
    GatesThrow "invalid JSON: $($_.Exception.Message)"
  }
  if ($config -isnot [hashtable]) { GatesThrow 'config must be a JSON object' }
  if (-not $config.ContainsKey('gates') -or @($config['gates']).Count -eq 0) {
    GatesThrow 'gate list is empty — an aggregate with no gates cannot be validated or run'
  }
  if (-not $config.ContainsKey('modes') -or $config['modes'] -isnot [hashtable]) {
    GatesThrow 'modes must be an object mapping mode names to gate id arrays'
  }

  $script:Gates = [ordered]@{}
  foreach ($entry in @($config['gates'])) {
    if ($entry -isnot [hashtable]) { GatesThrow 'each gate must be an object' }
    $id = $entry['id']
    if ($id -isnot [string] -or $id.Length -eq 0) { GatesThrow 'gate id must be a non-empty string' }
    if ($script:Gates.Contains($id)) { GatesThrow "duplicate gate id `"$id`"" }
    $label = $id
    if ($entry.Contains('label') -and $entry['label'] -is [string] -and $entry['label'].Length -gt 0) {
      $label = $entry['label']
    }
    if (-not $entry.Contains('command')) {
      GatesThrow "gate `"$id`" needs a non-empty command string array"
    }
    $argv = Test-CommandSlot $id $entry['command']
    $needs = @()
    if ($entry.Contains('needs') -and $null -ne $entry['needs']) {
      $needsRaw = @($entry['needs'])
      if ($needsRaw | Where-Object { $_ -isnot [string] }) {
        GatesThrow "gate `"$id`" needs must be an array of gate ids"
      }
      $needs = $needsRaw
    }
    $allowFailure = $false
    if ($entry.Contains('allowFailure') -and $null -ne $entry['allowFailure']) {
      if ($entry['allowFailure'] -isnot [bool]) {
        GatesThrow "gate `"$id`" allowFailure must be a boolean"
      }
      $allowFailure = [bool]$entry['allowFailure']
    }
    $script:Gates[$id] = @{
      Label = $label; Argv = $argv; Needs = $needs; AllowFailure = $allowFailure
    }
  }

  foreach ($id in @($script:Gates.Keys)) {
    foreach ($dep in $script:Gates[$id].Needs) {
      if (-not $script:Gates.Contains($dep)) {
        GatesThrow "gate `"$id`" depends on unknown gate `"$dep`""
      }
    }
  }

  $cycle = Find-GatesCycle
  if ($cycle) { GatesThrow "dependency cycle: $($cycle -join ' -> ')" }

  $script:GatesModes = @{}
  foreach ($modeName in @($config['modes'].Keys)) {
    $ids = @($config['modes'][$modeName])
    $badIds = @($ids | Where-Object { $_ -isnot [string] -or -not $script:Gates.Contains($_) })
    if ($ids.Count -eq 0 -or $badIds.Count -gt 0) {
      GatesThrow "mode `"$modeName`" must be a non-empty array of known gate ids"
    }
    $script:GatesModes[$modeName] = $ids
  }
  if (-not $script:GatesModes.ContainsKey('all')) { GatesThrow 'modes must define "all"' }
}

# Return the first dependency cycle as a path of ids, or $null.
function Find-GatesCycle {
  $color = @{}
  foreach ($id in @($script:Gates.Keys)) { $color[$id] = 0 }
  foreach ($start in @($script:Gates.Keys)) {
    if ($color[$start] -ne 0) { continue }
    $result = Visit-GateNode $start $color @()
    if ($result) { return $result }
  }
  return $null
}

function Visit-GateNode([string]$id, $color, [string[]]$path) {
  $color[$id] = 1
  $path = @($path) + $id
  foreach ($dep in $script:Gates[$id].Needs) {
    if ($color[$dep] -eq 0) {
      $result = Visit-GateNode $dep $color $path
      if ($result) { return $result }
    } elseif ($color[$dep] -eq 1) {
      $from = [Array]::IndexOf($path, $dep)
      return @($path[$from..($path.Count - 1)]) + $id
    }
  }
  $color[$id] = 2
  return $null
}

# --- scheduling --------------------------------------------------------------------

# True when every need of $1 has passed (unset needs are not passed).
function Test-GatesReady([string]$id) {
  foreach ($dep in $script:Gates[$id].Needs) {
    if (-not $script:Results.ContainsKey($dep) -or $script:Results[$dep].Status -ne 'passed') {
      return $false
    }
  }
  return $true
}

# A settled outcome blocks the aggregate unless allowFailure covers it.
function Test-ResultBlocking([string]$id) {
  return ($script:Results[$id].Status -ne 'passed') -and (-not $script:Gates[$id].AllowFailure)
}

# Launch one gate as a real child process with exact argv, capturing output.
function Start-GateProcess([string]$id, $running) {
  $gate = $script:Gates[$id]
  Write-Output "gates: start $($gate.Label)"
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $gate.Argv[0]
  foreach ($a in $gate.Argv | Select-Object -Skip 1) { [void]$psi.ArgumentList.Add([string]$a) }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.WorkingDirectory = (Get-Location).Path
  $proc = [System.Diagnostics.Process]::Start($psi)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $running[[int]$proc.Id] = @{
    Id = $id; Proc = $proc; Watch = $sw
    OutTask = $proc.StandardOutput.ReadToEndAsync()
    ErrTask = $proc.StandardError.ReadToEndAsync()
  }
}

# Map an exit code >128 to a signal fact (Unix semantics; Windows cannot
# produce these and never reaches this branch with a signal).
function Get-SignalName([int]$code) {
  $names = @{ 1 = 'SIGHUP'; 2 = 'SIGINT'; 3 = 'SIGQUIT'; 6 = 'SIGABRT'; 9 = 'SIGKILL'; 13 = 'SIGPIPE'; 15 = 'SIGTERM' }
  $n = $code - 128
  if ($names.ContainsKey($n)) { return $names[$n] }
  return "SIG$n"
}

# Print one settled outcome (passes stay silent unless GATE_VERBOSE=1).
function Show-GateResult([string]$id) {
  $gate = $script:Gates[$id]
  $result = $script:Results[$id]
  $secs = [Math]::Round($result.DurationMs / 1000, 2).ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
  if ($result.Status -eq 'passed') {
    if ($env:GATE_VERBOSE -eq '1') { Write-Output "gates: PASS $($gate.Label) (${secs}s)" }
    return
  }
  $upper = $result.Status.ToUpperInvariant()
  $lines = @(
    '',
    "== $upper $($gate.Label) (${secs}s) ==",
    "command: $($gate.Argv -join ' ')",
    "outcome: $($result.Reason)"
  )
  if ($result.Status -eq 'failed') {
    foreach ($line in $lines) { [Console]::Error.WriteLine($line) }
    if ($result.Output.Length -gt 0) { [Console]::Error.Write($result.Output) }
  } else {
    foreach ($line in $lines) { Write-Output $line }
  }
}

# Run the selected gate list: start ready gates up to $MaxActive concurrent
# children, settle them as they finish, and skip pending gates whose
# dependencies did not pass.
function Invoke-RunGates([string[]]$Selected, [int]$MaxActive) {
  $script:Results = @{}
  foreach ($id in $Selected) {
    $script:Results[$id] = @{ Status = 'pending'; Reason = ''; DurationMs = 0; Output = '' }
  }
  $running = [System.Collections.Generic.Dictionary[int, object]]::new()

  while ($true) {
    $runningIds = @($running.Values | ForEach-Object { $_.Id })
    foreach ($id in $Selected) {
      if ($running.Count -ge $MaxActive) { break }
      if ($script:Results[$id].Status -ne 'pending') { continue }
      if ($runningIds -contains $id) { continue }
      if (-not (Test-GatesReady $id)) { continue }
      Start-GateProcess $id $running
    }

    if ($running.Count -eq 0) {
      Complete-SkippedGates $Selected
      break
    }

    Start-Sleep -Milliseconds 50
    foreach ($entry in @($running.GetEnumerator())) {
      $proc = $entry.Value.Proc
      if (-not $proc.HasExited) { continue }
      $proc.WaitForExit()
      $entry.Value.Watch.Stop()
      $id = $entry.Value.Id
      $rc = $proc.ExitCode
      $output = $entry.Value.OutTask.Result + $entry.Value.ErrTask.Result
      [void]$running.Remove($entry.Key)
      if ($rc -eq 0) {
        $script:Results[$id].Status = 'passed'
        $script:Results[$id].Reason = ''
      } elseif ($rc -gt 128) {
        $script:Results[$id].Status = 'failed'
        $script:Results[$id].Reason = "signal $(Get-SignalName $rc)"
      } else {
        $script:Results[$id].Status = 'failed'
        $script:Results[$id].Reason = "exit $rc"
      }
      $script:Results[$id].DurationMs = $entry.Value.Watch.ElapsedMilliseconds
      $script:Results[$id].Output = $output
      Show-GateResult $id
    }
  }
}

# Mark every remaining pending gate skipped, attributing the failed needs.
# Reached only when no gate can start and none is running; a pending gate
# without a failed or skipped dependency is a scheduler defect and dies.
function Complete-SkippedGates([string[]]$Selected) {
  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($id in $Selected) {
      if ($script:Results[$id].Status -ne 'pending') { continue }
      $failedDeps = @($script:Gates[$id].Needs | Where-Object {
        $script:Results.ContainsKey($_) -and ($script:Results[$_].Status -eq 'failed' -or $script:Results[$_].Status -eq 'skipped')
      })
      if ($failedDeps.Count -eq 0) { continue }
      $script:Results[$id].Status = 'skipped'
      $script:Results[$id].Reason = "dependency failed or skipped: $($failedDeps -join ', ')"
      Show-GateResult $id
      $changed = $true
    }
  }
  foreach ($id in $Selected) {
    if ($script:Results[$id].Status -eq 'pending') {
      [Console]::Error.WriteLine('gates: validated graph stalled without a failed dependency')
      exit 1
    }
  }
}

# --- CLI ---------------------------------------------------------------------------

function GatesMain([string]$mode) {
  try {
    $raw = Get-Content -LiteralPath $script:ConfigPath -Raw
    Invoke-ValidateConfig $raw
  } catch {
    [Console]::Error.WriteLine("gates: invalid gates.json: $($_.Exception.Message)")
    exit 1
  }

  if (-not $script:GatesModes.ContainsKey($mode)) {
    $known = (@($script:GatesModes.Keys) | Sort-Object) -join ', '
    [Console]::Error.WriteLine("gates: unknown mode `"$mode`"; known modes: $known")
    exit 1
  }

  $selected = @($script:GatesModes[$mode])

  $cpu = [Environment]::ProcessorCount
  $maxActive = [Math]::Min($cpu, $selected.Count)
  if ($env:GATE_CONCURRENCY) {
    $parsed = 0
    if (-not [int]::TryParse($env:GATE_CONCURRENCY, [ref]$parsed) -or $parsed -lt 1) {
      [Console]::Error.WriteLine("gates: GATE_CONCURRENCY must be a positive integer, got `"$($env:GATE_CONCURRENCY)`"")
      exit 1
    }
    $maxActive = [Math]::Min($parsed, $selected.Count)
  }

  Write-Output "gates: mode `"$mode`" running $($selected.Count) gate(s) with $maxActive worker(s)."
  $sw = [System.Diagnostics.Stopwatch]::StartNew()

  Invoke-RunGates $selected $maxActive

  $sw.Stop()
  $passed = @($selected | Where-Object { $script:Results[$_].Status -eq 'passed' }).Count
  $failed = @($selected | Where-Object { $script:Results[$_].Status -eq 'failed' }).Count
  $skipped = @($selected | Where-Object { $script:Results[$_].Status -eq 'skipped' }).Count
  $secs = [Math]::Round($sw.ElapsedMilliseconds / 1000, 2).ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
  Write-Output ""
  Write-Output "gates: $passed passed, $failed failed, $skipped skipped in ${secs}s."

  $blocking = @($selected | Where-Object { Test-ResultBlocking $_ })
  if ($blocking.Count -gt 0) {
    [Console]::Error.WriteLine('gates: blocking outcomes:')
    foreach ($id in $blocking) {
      $r = $script:Results[$id]
      [Console]::Error.WriteLine("  - $($r.Status.ToUpperInvariant()) $($script:Gates[$id].Label) ($($r.Reason))")
    }
    exit 1
  }
  exit 0
}

if (-not $AsLib) {
  foreach ($arg in $args) {
    [Console]::Error.WriteLine("gates: unknown argument `"$arg`"; only -Mode <name> is supported")
    exit 1
  }
  GatesMain $Mode
}
