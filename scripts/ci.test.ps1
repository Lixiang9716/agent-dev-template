#!/usr/bin/env pwsh
# CI workflow shape tests (pwsh twin of ci.test.sh): the gate matrix must
# carry all four OS/shell legs and the summary job must always run — a
# skipped required check counts as passing on GitHub, so its guard is
# load-bearing. A guard only guards if the regression actually fails it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$ci = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../.github/workflows/ci.yml') -Raw

Expect-Eq 'four matrix legs total' @(([regex]::Matches($ci, '(?m)^\s+- os: '))).Count 4
Expect-Eq 'one sh leg in the matrix' @(([regex]::Matches($ci, '(?m)shell: sh$'))).Count 1
# The matrix indents shell keys deeper (12 spaces) than the step-level
# `shell: pwsh` directive (8 spaces); the depth split keeps the counts honest.
Expect-Eq 'three pwsh legs in the matrix' @(([regex]::Matches($ci, '(?m)^ {10,}shell: pwsh$'))).Count 3
Expect-Contains 'ubuntu leg present' $ci 'os: ubuntu-latest'
Expect-Contains 'macos leg present' $ci 'os: macos-latest'
Expect-Contains 'windows leg present' $ci 'os: windows-latest'
Expect-Contains 'gates job runs the bash twin' $ci 'bash scripts/gates.sh --mode all'
Expect-Contains 'gates job runs the pwsh twin' $ci 'pwsh -File scripts/gates.ps1 -Mode all'
Expect-Contains 'summary depends on gates' $ci 'needs: [gates]'
Expect-Contains 'summary always runs' $ci 'if: always()'
Expect-Contains 'heartbeat schedule present' $ci "cron: '17 2 * * 0'"

Complete-TestSuite
