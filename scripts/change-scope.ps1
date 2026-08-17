#!/usr/bin/env pwsh
# Report the explicit scope of a repository change as stable JSON (pwsh port;
# bash twin: change-scope.sh).
#
# Consumers (the pre-push-checks and code-review skills) use this output to
# select the smallest sufficient check set for the outgoing diff instead of
# reflexively running every gate. The base is never guessed and never
# fetched: the caller passes a ref it has already verified.

param(
  [string]$Base,
  [string]$Head = 'HEAD',
  [switch]$AsLib
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$script:FormatVersion = 1 # bumped whenever the output shape changes

# Run one git command in $repoDir, failing loud on any git error.
function Invoke-ScopeGit([string]$repoDir, [string[]]$Arguments) {
  return Invoke-Git $repoDir $Arguments
}

# Run a path-listing git command and return its sorted paths as an array
# (empty when the listing is empty).
function Get-ListedPaths([string]$repoDir, [string[]]$gitArgs) {
  $out = Invoke-ScopeGit $repoDir $gitArgs
  if ([string]::IsNullOrEmpty($out)) { return , @() }
  return , @($out -split "`n" | Sort-Object)
}

# Collect the change scope of base..head plus the working tree as JSON text.
function Get-ChangeScope([string]$repoDir, [string]$base, [string]$head = 'HEAD') {
  $baseSha = Invoke-ScopeGit $repoDir @('rev-parse', '--verify', "$base^{commit}")
  $headSha = Invoke-ScopeGit $repoDir @('rev-parse', '--verify', "$head^{commit}")
  $mergeBase = Invoke-ScopeGit $repoDir @('merge-base', $baseSha, $headSha)
  $scope = [ordered]@{
    formatVersion = $script:FormatVersion
    base          = $base
    baseSha       = $baseSha
    head          = $head
    headSha       = $headSha
    mergeBaseSha  = $mergeBase
    committed     = Get-ListedPaths $repoDir @('diff', '--name-only', $mergeBase, $headSha)
    staged        = Get-ListedPaths $repoDir @('diff', '--name-only', '--cached')
    unstaged      = Get-ListedPaths $repoDir @('diff', '--name-only')
    untracked     = Get-ListedPaths $repoDir @('ls-files', '--others', '--exclude-standard')
  }
  return ($scope | ConvertTo-Json -Depth 4)
}

function ScopeMain {
  foreach ($arg in $args) {
    [Console]::Error.WriteLine("change-scope: unknown argument `"$arg`"; only -Base <ref> [-Head <ref>] is supported")
    exit 2
  }
  if ([string]::IsNullOrEmpty($Base)) {
    [Console]::Error.WriteLine('change-scope: -Base <ref> is required; pass a ref you have already verified — it is never guessed or fetched')
    exit 2
  }
  try {
    Get-ChangeScope $script:Root $Base $Head
  } catch {
    [Console]::Error.WriteLine("$($_.Exception.Message)")
    exit 1
  }
  exit 0
}

if (-not $AsLib) { ScopeMain }
