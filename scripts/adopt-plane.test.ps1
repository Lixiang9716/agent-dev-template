#!/usr/bin/env pwsh
# Rejection tests for the adoption proof (pwsh twin of adopt-plane.test.sh):
# the full run passes end to end with deterministic output, each injected
# mutation fails the verify run naming its stage, -Clean is instance-scoped
# and never touches a foreign root, and every temporary directory is cleaned
# up (hermetic contract). A gate only guards if the regression actually
# fails it.

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib.ps1')
$script:AdoptPlane = Join-Path $PSScriptRoot 'adopt-plane.ps1'

# The suite owns a private temp root: every child instance scopes its
# transient files under it, so concurrent suites (the self-test and probe
# lanes run adopt-plane suites in parallel) cannot interfere with each other.
$script:SuiteTmp = Join-Path ([IO.Path]::GetTempPath()) ('adopt-plane.suite.' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:SuiteTmp -Force)
$env:TMPDIR = $script:SuiteTmp

# Number of entries in the suite's own temp root: child instances must leave
# it exactly as the suite arranges it. The pwsh runtime's own IPC artifacts
# (named pipes and diagnostic sockets) land in TMPDIR on Linux and linger
# after every child pwsh exits; they are .NET's, not ours, and are excluded
# from the count.
function Get-SuiteEntries {
  return @(Get-ChildItem -LiteralPath $script:SuiteTmp -Force -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -notlike 'CoreFxPipe_*' -and
      $_.Name -notlike 'clr-debug-pipe-*' -and
      $_.Name -notlike 'dotnet-diagnostic-*'
    }).Count
}

# The mutations the verify battery must detect (same shapes the battery
# itself injects: the proof must reject a mutation injected from outside).
function Invoke-InjectPairing([string]$dir) {
  [IO.File]::AppendAllText((Join-Path $dir 'README.zh.md'), "`nadopt-plane: pairing mutation`n")
}
function Invoke-InjectVocabulary([string]$dir) {
  [IO.File]::AppendAllText((Join-Path $dir 'docs/adoption.md'), "`nThis statement is verified by nothing.`n")
}
function Invoke-InjectNotes([string]$dir) {
  [IO.File]::WriteAllText((Join-Path $dir '.agents/notes/implemented/architecture/2026-08-19-mutation-note.md'), "garbage`n", (New-Object System.Text.UTF8Encoding($false)))
}
function Invoke-InjectScriptPairs([string]$dir) {
  [IO.File]::AppendAllText((Join-Path $dir 'scripts/adopt-plane.sh'), "`n# adopt-plane: drift mutation`n")
}
function Invoke-InjectPlaneFile([string]$dir) {
  Remove-Item -LiteralPath (Join-Path $dir '.gitattributes') -Force
}

try {
  Expect-Eq 'the suite temp root starts empty' (Get-SuiteEntries) 0

  # -Clean is instance-scoped: it must never touch a foreign root, and its
  # own transient root is gone afterwards.
  $foreign = Join-Path $script:SuiteTmp ('adopt-plane.foreign.' + [Guid]::NewGuid().ToString('N'))
  [void](New-Item -ItemType Directory -Path $foreign -Force)
  & pwsh -NoProfile -File $script:AdoptPlane -Clean | Out-Null
  $kept = if (Test-Path -LiteralPath $foreign) { 'kept' } else { 'removed' }
  Expect-Eq '--clean never touches a foreign root' $kept 'kept'
  Expect-Eq '--clean leaves no residue of its own' (Get-SuiteEntries) 1

  # (a) The full run passes end to end with deterministic output.
  $out = & pwsh -NoProfile -File $script:AdoptPlane 2>&1
  $rc = $LASTEXITCODE
  $outText = $out -join "`n"
  $lineCount = @(($outText -split "`n") | Where-Object { $_ -ne '' }).Count
  Expect-Status 'full run exits 0' 0 $rc
  Expect-Eq 'full run output is line-deterministic' $lineCount 12
  Expect-Contains 'full run reports the PASS summary' $outText 'adopt-plane: PASS'
  Expect-Contains 'full run proves gates all green' $outText 'adopt-plane: gate all PASS'
  Expect-Contains 'full run proves the hook install' $outText 'adopt-plane: install-hooks PASS'
  Expect-Contains 'full run proves the pre-commit commit' $outText 'adopt-plane: pre-commit PASS'
  Expect-Contains 'full run rejects the pairing mutation' $outText 'adopt-plane: FAIL stage=pairing'
  Expect-Contains 'full run rejects the vocabulary mutation' $outText 'adopt-plane: FAIL stage=vocabulary'
  Expect-Contains 'full run rejects the notes mutation' $outText 'adopt-plane: FAIL stage=notes'
  Expect-Contains 'full run rejects the script-pairs mutation' $outText 'adopt-plane: FAIL stage=script-pairs'
  Expect-Contains 'full run proves pre-commit rejection' $outText 'adopt-plane: pre-commit REJECT'
  Expect-Eq 'full run leaves no residue in the suite root' (Get-SuiteEntries) 1

  # (b) Each mutation, injected into a fresh scaffold, fails the verify run
  # naming its stage; the verified dir is removed.
  function Invoke-MutationCase([string]$stage, [string]$injectFn, [int]$commitProof, [string]$expected) {
    $dir = Join-Path $script:SuiteTmp ('case.' + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $dir -Force)
    & pwsh -NoProfile -File $script:AdoptPlane -Scaffold $dir | Out-Null
    Expect-Status "scaffold for stage=$stage exits 0" 0 $LASTEXITCODE
    & $injectFn $dir
    $vout = & pwsh -NoProfile -File $script:AdoptPlane -Verify $dir 2>&1
    $voutText = $vout -join "`n"
    Expect-Status "verify for stage=$stage exits non-zero" 1 $LASTEXITCODE
    Expect-Contains "verify names stage=$stage" $voutText $expected
    if ($commitProof -eq 1) {
      Expect-Contains "verify proves pre-commit rejection for stage=$stage" $voutText 'adopt-plane: pre-commit REJECT'
    }
    $kept = if (Test-Path -LiteralPath $dir) { 'kept' } else { 'removed' }
    Expect-Eq "verify removes the scaffold dir for stage=$stage" $kept 'removed'
  }

  Invoke-MutationCase 'pairing' 'Invoke-InjectPairing' 1 'adopt-plane: FAIL stage=pairing'
  Invoke-MutationCase 'vocabulary' 'Invoke-InjectVocabulary' 1 'adopt-plane: FAIL stage=vocabulary'
  Invoke-MutationCase 'notes' 'Invoke-InjectNotes' 0 'adopt-plane: FAIL stage=notes'
  Invoke-MutationCase 'script-pairs' 'Invoke-InjectScriptPairs' 0 'adopt-plane: FAIL stage=script-pairs'
  Invoke-MutationCase 'plane-file' 'Invoke-InjectPlaneFile' 0 'adopt-plane: FAIL plane-file .gitattributes'

  # (c) The suite leaves no residue and cleans its own fixture.
  Expect-Eq 'no residue at the end of the suite' (Get-SuiteEntries) 1
  Remove-Item -LiteralPath $foreign -Recurse -Force
  Expect-Eq 'the suite cleans its own fixture' (Get-SuiteEntries) 0

  Complete-TestSuite
} finally {
  Remove-Item -LiteralPath $script:SuiteTmp -Recurse -Force -ErrorAction SilentlyContinue
}
