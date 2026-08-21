#!/usr/bin/env pwsh
# Scheduler self-tests (pwsh twin of gates.test.sh). These
# pin the contract the gates aggregate relies on: invalid graphs are rejected
# before any child starts, failures propagate as skips with the cause,
# allowFailure stays non-blocking, and per-shell command slots must name every
# shell. A gate only guards if the regression actually fails it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'gates.ps1') -AsLib:$true

function Expect-Reject([string]$desc, [string]$json, [string]$fragment) {
  $out = ''
  $code = & {
    try {
      Invoke-ValidateConfig $json | Out-Null
      return 0
    } catch {
      return "gates: invalid gates.json: $($_.Exception.Message)"
    }
  }
  # $code is 0 on accept, or the message on reject.
  if ($code -eq 0) {
    $script:T_Total++
    Fail "${desc}: accepted an invalid config"
  } else {
    Expect-Contains $desc "$code" $fragment
  }
}

function Expect-Accept([string]$desc, [string]$json) {
  $msg = & {
    try {
      Invoke-ValidateConfig $json | Out-Null
      return ''
    } catch {
      return $_.Exception.Message
    }
  }
  Expect-Eq $desc "$msg" ''
}

function New-Cfg([string[]]$ids, [string]$gatesJson) {
  '{"modes":{"all":[' + ($ids -join ',') + ']},"gates":[' + $gatesJson + ']}'
}

Expect-Reject 'empty gate list rejected' '{"modes":{"all":[]},"gates":[]}' 'gate list is empty'
Expect-Reject 'duplicate gate ids rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":["true"]},{"id":"a","command":["true"]}') `
  'duplicate gate id "a"'
Expect-Reject 'unknown dependency rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":["true"],"needs":["ghost"]}') `
  'gate "a" depends on unknown gate "ghost"'
Expect-Reject 'two-gate cycle rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":["true"],"needs":["b"]},{"id":"b","command":["true"],"needs":["a"]}') `
  'dependency cycle'
Expect-Reject 'self-cycle rejected' `
  (New-Cfg @('"a"') '{"id":"self","command":["true"],"needs":["self"]}') `
  'dependency cycle'
Expect-Reject 'three-gate cycle rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":["true"],"needs":["b"]},{"id":"b","command":["true"],"needs":["c"]},{"id":"c","command":["true"],"needs":["a"]}') `
  'dependency cycle'
Expect-Reject 'empty command array rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":[]}') `
  'gate "a" needs a non-empty command string array'
Expect-Reject 'non-array command rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":"true"}') `
  'gate "a" needs a non-empty command string array'
Expect-Reject 'mode with unknown gate rejected' `
  '{"modes":{"all":["a"],"extra":["ghost"]},"gates":[{"id":"a","command":["true"]}]}' `
  'mode "extra" must be a non-empty array of known gate ids'
Expect-Reject 'missing modes.all rejected' `
  '{"modes":{"quick":["a"]},"gates":[{"id":"a","command":["true"]}]}' `
  'modes must define "all"'
Expect-Reject 'missing pwsh variant rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":{"sh":["true"]}}') `
  'must declare both "sh" and "pwsh" variants'
Expect-Reject 'unknown shell variant rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":{"sh":["true"],"pwsh":["true"],"node":["true"]}}') `
  'unknown shell "node"; the closed set is sh, pwsh'
Expect-Reject 'empty variant array rejected' `
  (New-Cfg @('"a"') '{"id":"a","command":{"sh":["true"],"pwsh":[]}}') `
  '"pwsh" command must be a non-empty string array'
Expect-Accept 'complete per-shell variants accepted' `
  (New-Cfg @('"a"') '{"id":"a","command":{"sh":["true"],"pwsh":["pwsh","-Version","1"]}}')

# The pwsh port runs the pwsh variant; the sh variant is validated, not run.
Invoke-ValidateConfig (New-Cfg @('"a"') '{"id":"a","command":{"sh":["echo","sh-ran"],"pwsh":["echo","pwsh-ran"]}}') | Out-Null
Expect-Eq 'pwsh port selects the pwsh variant' ($script:Gates['a'].Argv -join ' ') 'echo pwsh-ran'

# --- scheduling (real child processes) ------------------------------------------

function Invoke-Configured([string]$gatesJson, [string[]]$selected, [int]$max) {
  Invoke-ValidateConfig $gatesJson | Out-Null
  $out = Invoke-RunGates $selected $max 6>&1 2>&1
  return $out
}

# A failing dependency skips its dependents with the cause.
Invoke-Configured (New-Cfg @('"root"', '"child"', '"grandchild"') `
  '{"id":"root","command":["pwsh","-NoProfile","-Command","exit 3"]},{"id":"child","command":["true"],"needs":["root"]},{"id":"grandchild","command":["true"],"needs":["child"]}') `
  @('root', 'child', 'grandchild') 2 | Out-Null
Expect-Eq 'failing root is failed' $script:Results['root'].Status 'failed'
Expect-Eq 'dependent is skipped' $script:Results['child'].Status 'skipped'
Expect-Eq 'skip reason names the dependency' $script:Results['child'].Reason 'dependency failed or skipped: root'
Expect-Eq 'transitive dependent is skipped' $script:Results['grandchild'].Status 'skipped'

# A dependent gate runs only after its dependency passes (absolute marker).
$dir = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ("gates-order-" + [guid]::NewGuid()))
$dirPath = $dir.FullName.Replace('\', '/')
Invoke-Configured (New-Cfg @('"produce"', '"consume"') `
  ('{"id":"produce","command":["pwsh","-NoProfile","-Command","New-Item -ItemType File -Path ''' + $dirPath + '/marker''"]},' +
   '{"id":"consume","command":["pwsh","-NoProfile","-Command","if (-not (Test-Path ''' + $dirPath + '/marker'')) { exit 1 }"],"needs":["produce"]}')) `
  @('produce', 'consume') 4 | Out-Null
Expect-Eq 'producer passed' $script:Results['produce'].Status 'passed'
Expect-Eq 'consumer passed after producer' $script:Results['consume'].Status 'passed'
Remove-Item -Recurse -Force $dir.FullName

# allowFailure keeps a failed gate out of the blocking set.
Invoke-Configured (New-Cfg @('"observational"') '{"id":"observational","command":["pwsh","-NoProfile","-Command","exit 1"],"allowFailure":true}') `
  @('observational') 1 | Out-Null
Expect-Eq 'observational gate still fails' $script:Results['observational'].Status 'failed'
Expect-Eq 'allowFailure not blocking' ([bool](Test-ResultBlocking 'observational')) $false

# A signal kill is reported with the signal fact (Unix only; Windows has no
# signals, so the check is skipped there rather than lied about).
if ($IsLinux -or $IsMacOS) {
  Invoke-Configured (New-Cfg @('"self-kill"') '{"id":"self-kill","command":["pwsh","-NoProfile","-Command","Stop-Process -Id $PID -Force"]}') `
    @('self-kill') 1 | Out-Null
  Expect-Eq 'signal kill is failed' $script:Results['self-kill'].Status 'failed'
  Expect-Match 'signal reason names the signal' $script:Results['self-kill'].Reason '^signal SIG(KILL|TERM)'
  Expect-Eq 'signal kill blocking' ([bool](Test-ResultBlocking 'self-kill')) $true
}

# A mode selecting a gate whose needs are unselected fails loud, not
# silently. Complete-SkippedGates exits the process, so run it in a child.
$stallScript = '. "{0}" -AsLib:$true; ' -f (Join-Path $PSScriptRoot 'gates.ps1') +
  'Invoke-ValidateConfig ''{"modes":{"all":["a","b"],"lonely":["b"]},"gates":[{"id":"a","command":["true"]},{"id":"b","command":["true"],"needs":["a"]}]}'' | Out-Null; ' +
  '$script:Results = @{}; foreach ($id in @(''b'')) { $script:Results[$id] = @{ Status = ''pending''; Reason = ''''; DurationMs = 0; Output = '''' } }; ' +
  'Complete-SkippedGates @(''b'')'
$stallOut = & pwsh -NoProfile -Command $stallScript 2>&1
Expect-Status 'unselected dependency stalls loud' 1 $LASTEXITCODE
Expect-Contains 'stall message names the defect' "$stallOut" 'validated graph stalled without a failed dependency'

# A passing gate that emitted a loud skip surfaces the skip line — a skipped
# probe is degraded verification and must never look like full coverage
# (AGENTS.md rule 4).
$savedVerbose = $env:GATE_VERBOSE
$env:GATE_VERBOSE = $null
$skipOut = Invoke-Configured (New-Cfg @('"skippy"') '{"id":"skippy","command":["pwsh","-NoProfile","-Command","Write-Output ''probe skipped: alpha — pwsh not on PATH; cross-port behavioral consistency is verified in CI (GATES_FORCE_PROBE=1)''"]}') @('skippy') 1
Expect-Contains 'a passing gate surfaces its probe skip line' "$skipOut" 'probe skipped: alpha — pwsh not on PATH'

# A passing gate without skip lines stays silent apart from its start line.
$quietOut = Invoke-Configured (New-Cfg @('"quiet"') '{"id":"quiet","command":["pwsh","-NoProfile","-Command","Write-Output ''plain output''"]}') @('quiet') 1
Expect-Eq 'a passing gate without skips stays silent' "$quietOut" 'gates: start quiet'
$env:GATE_VERBOSE = $savedVerbose

# The concurrency cap is honored per launch: with one worker, three ready
# gates run sequentially — a stale live-count snapshot would start them all
# in the same round and finish in one sleep period.
$serialOut = Invoke-Configured (New-Cfg @('"s1"', '"s2"', '"s3"') '{"id":"s1","command":["bash","-c","sleep 1.0"]},
   {"id":"s2","command":["bash","-c","sleep 1.0"]},
   {"id":"s3","command":["bash","-c","sleep 1.0"]}') @('s1', 's2', 's3') 1
$t0 = Get-Date
[void](Invoke-Configured (New-Cfg @('"s1"', '"s2"', '"s3"') '{"id":"s1","command":["bash","-c","sleep 1.0"]},
   {"id":"s2","command":["bash","-c","sleep 1.0"]},
   {"id":"s3","command":["bash","-c","sleep 1.0"]}') @('s1', 's2', 's3') 1)
$elapsed = ((Get-Date) - $t0).TotalSeconds
Expect-Eq 'the cap starts all three gates' @(([regex]::Matches(($serialOut -join "`n"), 'gates: start'))).Count 3
Expect-Eq 'the cap serializes them (total at least two sleep periods)' $(if ($elapsed -ge 2) { 1 } else { 0 }) 1

Complete-TestSuite
