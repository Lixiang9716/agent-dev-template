#!/usr/bin/env pwsh
# Run every scripts/*.test.ps1, each in its own pwsh process, and fail if any
# fails. This is the `self-test` gate's pwsh-side command; self-test.sh runs
# the bash twin suite. A gate only guards if the regression actually fails it.

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$total = 0
$failed = 0
foreach ($t in @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.test.ps1' | Sort-Object Name)) {
  $total++
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
  exit 1
}
Write-Output "self-test: $total suite(s), $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
