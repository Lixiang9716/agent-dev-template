#!/usr/bin/env pwsh
# Enforce word-count ceilings from scripts/doc-budgets.json on the English
# side of every in-scope document (pwsh port; bash twin: verify-doc-budgets.sh).
# Ceilings ratchet down; raising one is a deliberate change to this manifest,
# made in the same PR that needs the words. The Chinese side is not counted;
# the English side is the canonical count for a pair.

param([switch]$AsLib)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ManifestPath = Join-Path $script:Root 'scripts/doc-budgets.json'

# Count words wc-style: whitespace-separated tokens.
function Get-WordCount([string]$path) {
  ([regex]::Matches((Get-Content -LiteralPath $path -Raw).Trim(), '\S+')).Count
}

# Validate every budget entry.
function Get-BudgetViolations {
  $violations = [System.Collections.Generic.List[string]]::new()
  $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json -AsHashtable
  foreach ($rel in @($manifest.Keys)) {
    $raw = $manifest[$rel]
    $ceiling = 0
    if ($raw -isnot [long] -or $raw -lt 1 -or $raw -gt 9007199254740991) {
      $violations.Add("${rel}: ceiling must be a positive integer")
      continue
    }
    $ceiling = [int]$raw
    if (-not (Test-Path -LiteralPath (Join-Path $script:Root $rel))) {
      $violations.Add("${rel}: budgeted document is missing — renamed or deleted? update scripts/doc-budgets.json in the same change")
      continue
    }
    $words = Get-WordCount (Join-Path $script:Root $rel)
    if ($words -gt $ceiling) {
      $violations.Add("${rel}: $words words exceed the $ceiling-word ceiling — relocate or condense, or raise the ceiling here with justification")
    }
  }
  return $violations
}

function BudgetsMain {
  $violations = Get-BudgetViolations
  if ($violations.Count -eq 0) {
    Write-Output 'verify-doc-budgets: every budgeted document fits its ceiling.'
    exit 0
  }
  [Console]::Error.WriteLine("verify-doc-budgets: $($violations.Count) violation(s):")
  foreach ($v in $violations) { [Console]::Error.WriteLine("  $v") }
  exit 1
}

if (-not $AsLib) { BudgetsMain }
