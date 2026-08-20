#!/usr/bin/env pwsh
# Declare-state vocabulary gate (pwsh twin of verify-vocabulary.sh).
#
# Scans the pre-registered document surface (AGENTS.md, AGENTS.zh.md, docs/*.md
# — the `scan` list in scripts/vocabulary.json) for concept-level
# declaration-state words that carry a "certified-as-true" connotation: English
# verified/confirmed/proven/certified/validated/corroborated and any-language
# synonym forms such as 已验证 / 已证实 / 已确认 (Chinese). A translation must
# never bypass the gate. The banned families, meta-annotation whitelist,
# definition markers, and window all live in scripts/vocabulary.json — one home,
# consumed by both ports.
#
# Exemptions are pre-registered and mechanical, checked in order:
#   1. backtick-quoted tokens (code/identifier meta-reference);
#   2. meta-annotation context: the token sits inside a whitelist term that is
#      preceded by a structural delimiter (line start, table pipe, colon,
#      whitespace, quote, backtick, ...). A CJK prefix is not a delimiter, so
#      "该声明处于已确认状态" is a declaration-state usage and is not exempt;
#   3. ban-definition context: a definition marker ends within 6 characters
#      BEFORE the token on the same line (the ban's own definition sentence).
#      A marker AFTER the token does not excuse it.
#
# Fail loud: a malformed vocabulary.json, an unknown shape, or a missing scan
# target aborts naming the offender. Findings are collected and reported all
# at once with file:line positions.

param([switch]$AsLib)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:VocabPath = Join-Path $script:Root 'scripts/vocabulary.json'

$script:VocabViolations = [System.Collections.Generic.List[string]]::new()

function Add-VocabViolation([string]$message) {
  $script:VocabViolations.Add($message)
}

# ASCII word characters for the manual word-boundary check (mirrors \b); CJK
# letters count as word characters too (Unicode \b semantics).
function Test-WordChar([string]$ch) {
  return $ch.Length -eq 1 -and ($ch -cmatch '[A-Za-z0-9_]' -or [char]::IsLetterOrDigit($ch, 0))
}

# Structural delimiter for meta-annotation context (platform delimiter set).
function Test-Delimiter([string]$ch) {
  if ($ch.Length -ne 1) { return $false }
  return ($ch -in @('|', ':', ',', ';', '(', ')', '[', ']', '{', '}', '`', '=', '"', "'", ' ', "`t"))
}

# Index of $needle in $haystack from $from; -1 when absent. Case-insensitive
# when $ci is true, case-sensitive otherwise.
function Find-Token([string]$haystack, [string]$needle, [int]$from, [bool]$ci) {
  $cmp = if ($ci) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  return $haystack.IndexOf($needle, $from, $cmp)
}

# True when the en match [start,end) in $line is word-boundary-delimited.
function Test-EnBoundary([string]$line, [int]$s, [int]$e) {
  if ($s -gt 0 -and (Test-WordChar $line.Substring($s - 1, 1))) { return $false }
  if ($e -lt $line.Length -and (Test-WordChar $line.Substring($e, 1))) { return $false }
  return $true
}

# Backtick spans of $line as [pscustomobject]@{Start;End} pairs.
function Get-BacktickSpans([string]$line) {
  $spans = [System.Collections.Generic.List[object]]::new()
  $start = $null
  for ($i = 0; $i -lt $line.Length; $i++) {
    if ($line[$i] -eq '`') {
      if ($null -eq $start) { $start = $i }
      else { $spans.Add([pscustomobject]@{ Start = $start; End = $i }); $start = $null }
    }
  }
  return ,$spans
}

# True when both $s and $eMinusOne sit inside one backtick span.
function Test-BacktickSpan($spans, [int]$s, [int]$eMinusOne) {
  foreach ($sp in @($spans)) {
    if ($s -ge $sp.Start -and $eMinusOne -le $sp.End) { return $true }
  }
  return $false
}

# True when the match [start,end) sits inside a whitelist term in meta context.
function Test-MetaExcused([string]$line, [int]$s, [int]$e) {
  foreach ($term in $script:MetaWhitelist) {
    $tpos = 0
    while ($tpos -ge 0) {
      $tpos = Find-Token $line $term $tpos $false
      if ($tpos -lt 0) { break }
      if ($tpos -le $s -and $e -le $tpos + $term.Length) {
        if ($tpos -eq 0) { return $true }
        if (Test-Delimiter $line.Substring($tpos - 1, 1)) { return $true }
      }
      $tpos++
    }
  }
  return $false
}

# True when a definition marker ends within the window BEFORE the token start.
function Test-DefinitionExcused([string]$line, [int]$s) {
  foreach ($m in $script:DefinitionMarkers) {
    $mpos = 0
    while ($mpos -ge 0) {
      $mpos = Find-Token $line $m $mpos $false
      if ($mpos -lt 0) { break }
      $mEnd = $mpos + $m.Length
      if ($mEnd -le $s -and ($s - $mEnd) -le $script:DefinitionWindow) { return $true }
      $mpos++
    }
  }
  return $false
}

# True when the match [start,end) in $line is covered by an exemption.
function Test-TokenExcused([string]$line, [int]$s, [int]$e) {
  $spans = Get-BacktickSpans $line
  if (Test-BacktickSpan $spans $s ($e - 1)) { return $true }
  if (Test-MetaExcused $line $s $e) { return $true }
  if (Test-DefinitionExcused $line $s) { return $true }
  return $false
}

# Scan one line of one file for banned tokens; appends violations. All
# candidate matches are collected first, then consumed left to right
# (finditer semantics): the earliest-starting match wins and later candidates
# inside its span are skipped — overlapping tokens such as 已经验证 inside
# 经验证 do not double-report.
function Scan-Line([string]$rel, [int]$lineno, [string]$line) {
  $cands = [System.Collections.Generic.List[string]]::new()
  foreach ($token in $script:BannedEn) {
    $i = 0
    while ($i -ge 0) {
      $i = Find-Token $line $token $i $true
      if ($i -lt 0) { break }
      $end = $i + $token.Length
      if (Test-EnBoundary $line $i $end) { $cands.Add("$i`t$end`t$token") }
      $i = $end
    }
  }
  foreach ($token in $script:BannedZh) {
    $i = 0
    while ($i -ge 0) {
      $i = Find-Token $line $token $i $true
      if ($i -lt 0) { break }
      $end = $i + $token.Length
      $cands.Add("$i`t$end`t$token")
      $i = $end
    }
  }
  if ($cands.Count -eq 0) { return }
  $sorted = @($cands | Sort-Object { [int](($_ -split "`t")[0]) })
  $cursor = 0
  foreach ($c in $sorted) {
    $parts = $c -split "`t"
    $start = [int]$parts[0]
    $end = [int]$parts[1]
    $token = $parts[2]
    if ($start -lt $cursor) { continue }
    $cursor = $end
    if (Test-TokenExcused $line $start $end) { continue }
    $ctx = $line.Trim()
    if ($ctx.Length -gt 160) { $ctx = $ctx.Substring(0, 160) }
    Add-VocabViolation "${rel}:${lineno}: banned declaration-state word `"$token`" — $ctx"
  }
}

# Scan one file: every line, 1-based line numbers.
function Scan-File([string]$rel, [string]$absPath) {
  $lineno = 0
  foreach ($raw in @(Get-Content -LiteralPath $absPath)) {
    $lineno++
    Scan-Line $rel $lineno ($raw -replace "`r$", '')
  }
}

# Expand the scan list (globs allowed) and scan every match; missing targets
# and empty glob matches fail loud.
function Scan-Surface {
  foreach ($entry in $script:ScanList) {
    if ($entry.Contains('*')) {
      $matched = $false
      foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $script:Root (Split-Path $entry)) -File -Filter (Split-Path -Leaf $entry) -ErrorAction SilentlyContinue)) {
        $matched = $true
        Scan-File $f.FullName.Substring($script:Root.Length + 1) $f.FullName
      }
      if (-not $matched) {
        Add-VocabViolation "scan pattern `"$entry`" matches no files"
      }
    } else {
      $abs = Join-Path $script:Root $entry
      if (-not (Test-Path -LiteralPath $abs)) {
        Add-VocabViolation "scan target missing: $entry"
        continue
      }
      Scan-File $entry $abs
    }
  }
}

# True when $v is a positive whole number (JSON integers arrive as [long]).
function Test-WholeNumber($v) {
  return (($v -is [int] -or $v -is [long] -or $v -is [double]) -and $v -gt 0 -and $v -eq [math]::Floor([double]$v))
}

# The registered schema version both ports pin; a manifest claiming any other
# version fails loud (migration = bump this and the bash twin together).
$script:ExpectedVocabVersion = 1

# Read $path as the vocabulary manifest; fills the script-scope arrays.
# Fail loud on any shape defect.
function Import-Vocabulary([string]$path = $script:VocabPath) {
  $script:VocabViolations = [System.Collections.Generic.List[string]]::new()
  $script:ScanList = @()
  $script:BannedEn = @()
  $script:BannedZh = @()
  $script:MetaWhitelist = @()
  $script:DefinitionMarkers = @()
  $script:DefinitionWindow = 0
  if (-not (Test-Path -LiteralPath $path)) {
    Add-VocabViolation "$(Split-Path -Leaf $path): unreadable"
    return $false
  }
  try {
    $m = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
  } catch {
    Add-VocabViolation "$(Split-Path -Leaf $path): $($_.Exception.Message)"
    return $false
  }
  if ($m -isnot [hashtable]) {
    Add-VocabViolation "$(Split-Path -Leaf $path): manifest must be a JSON object"
    return $false
  }
  # Strict schema: unknown keys and an unregistered version abort naming the
  # offender (rule 4 — a mistyped whitelist key must never silently disable an
  # exemption).
  foreach ($key in @($m.Keys)) {
    if ($key -notin @('version', 'scan', 'banned', 'metaWhitelist', 'definitionMarkers', 'definitionWindow')) {
      Add-VocabViolation "$(Split-Path -Leaf $path): unknown key `"$key`" at the manifest top level (allowed: version, scan, banned, metaWhitelist, definitionMarkers, definitionWindow)"
      return $false
    }
  }
  if ($m.ContainsKey('banned') -and $m['banned'] -is [hashtable]) {
    foreach ($key in @($m['banned'].Keys)) {
      if ($key -notin @('en', 'zh')) {
        Add-VocabViolation "$(Split-Path -Leaf $path): unknown key `"$key`" in `"banned`" (allowed: en, zh)"
        return $false
      }
    }
  }
  if (-not ($m.ContainsKey('version') -and (Test-WholeNumber $m['version']))) {
    Add-VocabViolation "$(Split-Path -Leaf $path): version must be a positive integer"
    return $false
  }
  if ([string]$m['version'] -ne "$script:ExpectedVocabVersion") {
    Add-VocabViolation "$(Split-Path -Leaf $path): version $($m['version']) does not match the registered version $script:ExpectedVocabVersion — bump ExpectedVocabVersion in both ports when migrating the schema"
    return $false
  }
  if (-not ($m.ContainsKey('scan') -and $m['scan'] -is [array] -and $m['scan'].Count -gt 0 -and -not ($m['scan'] | Where-Object { $_ -isnot [string] -or [string]::IsNullOrEmpty($_) }))) {
    Add-VocabViolation "$(Split-Path -Leaf $path): scan must be a non-empty array of non-empty strings"
    return $false
  }
  foreach ($key in @('en', 'zh')) {
    if (-not ($m.ContainsKey('banned') -and $m['banned'] -is [hashtable] -and $m['banned'].ContainsKey($key) -and $m['banned'][$key] -is [array] -and $m['banned'][$key].Count -gt 0 -and -not ($m['banned'][$key] | Where-Object { $_ -isnot [string] -or [string]::IsNullOrEmpty($_) }))) {
      Add-VocabViolation "$(Split-Path -Leaf $path): banned.$key must be a non-empty array of non-empty strings"
      return $false
    }
  }
  foreach ($key in @('metaWhitelist', 'definitionMarkers')) {
    if (-not ($m.ContainsKey($key) -and $m[$key] -is [array] -and $m[$key].Count -gt 0 -and -not ($m[$key] | Where-Object { $_ -isnot [string] -or [string]::IsNullOrEmpty($_) }))) {
      Add-VocabViolation "$(Split-Path -Leaf $path): $key must be a non-empty array of non-empty strings"
      return $false
    }
  }
  if (-not ($m.ContainsKey('definitionWindow') -and (Test-WholeNumber $m['definitionWindow']))) {
    Add-VocabViolation "$(Split-Path -Leaf $path): definitionWindow must be a positive integer"
    return $false
  }
  $script:ScanList = @($m['scan'])
  $script:BannedEn = @($m['banned']['en'])
  $script:BannedZh = @($m['banned']['zh'])
  $script:MetaWhitelist = @($m['metaWhitelist'])
  $script:DefinitionMarkers = @($m['definitionMarkers'])
  $script:DefinitionWindow = $m['definitionWindow']
  return $true
}

function Invoke-VocabularyGate {
  if (-not (Import-Vocabulary)) {
    [Console]::Error.WriteLine("verify-vocabulary: $($script:VocabViolations.Count) violation(s):")
    foreach ($v in $script:VocabViolations) { [Console]::Error.WriteLine("  $v") }
    exit 1
  }
  Scan-Surface
  if ($script:VocabViolations.Count -eq 0) {
    Write-Output 'verify-vocabulary: the document surface is clean of declaration-state words.'
    exit 0
  }
  [Console]::Error.WriteLine("verify-vocabulary: $($script:VocabViolations.Count) violation(s):")
  foreach ($v in $script:VocabViolations) { [Console]::Error.WriteLine("  $v") }
  exit 1
}

if (-not $AsLib) { Invoke-VocabularyGate }
