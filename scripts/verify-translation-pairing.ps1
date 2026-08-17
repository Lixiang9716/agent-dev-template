#!/usr/bin/env pwsh
# Verify bilingual documentation pairs (pwsh port; bash twin:
# verify-translation-pairing.sh).
#
# A pair is three sibling files: `foo.md` + `foo.zh.md` + `foo.i18n.yaml`.
# The sidecar records the git blob hash of each side at its last
# confirmed-consistent state, so a later edit on either side alone fails here
# until the pair is re-confirmed with -Write in the same change. Structural
# signatures (heading counts, list counts, table rows, link targets,
# byte-identical fenced blocks) must also match. A green gate means the pair
# was confirmed consistent at these exact contents — not that the translation
# is good. Translation quality belongs to review.

param(
  [switch]$Write,
  [string]$Path,
  [switch]$AsLib
)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-BlobHash([string]$root, [string]$relPath) {
  $out = & git -C $root hash-object $relPath 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "verify-translation-pairing: git hash-object failed for ${relPath}: $out"
  }
  return "$out".Trim()
}

# Expand the scope to sorted repo-relative English-side paths.
function Get-PairingScope([string]$root) {
  $paths = [System.Collections.Generic.HashSet[string]]::new()
  $addDir = {
    param([string]$dirRel, [bool]$recursive)
    $dir = if ($dirRel -eq '') { $root } else { Join-Path $root $dirRel }
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($entry in @(Get-ChildItem -LiteralPath $dir -File)) {
      if ($entry.Name -like '*.md' -and $entry.Name -notlike '*.zh.md') {
        $rel = if ($dirRel -eq '') { $entry.Name } else { "$dirRel/$($entry.Name)" }
        [void]$paths.Add($rel)
      }
    }
    if ($recursive) {
      foreach ($entry in @(Get-ChildItem -LiteralPath $dir -Directory)) {
        & $addDir $(if ($dirRel -eq '') { $entry.Name } else { "$dirRel/$($entry.Name)" }) $true
      }
    }
  }
  & $addDir '' $false
  & $addDir 'docs' $true
  return @($paths | Sort-Object)
}

# Read the exact sidecar shape: pair:\n  en: <hash>\n  zh: <hash>\n.
function Read-PairingSidecar([string]$path) {
  $lines = (Get-Content -LiteralPath $path -Raw) -split "`n"
  if ($lines.Count -ne 4 -or $lines[0] -ne 'pair:' -or -not $lines[1].StartsWith('  en: ') -or -not $lines[2].StartsWith('  zh: ') -or $lines[3] -ne '') {
    throw "must contain exactly `"pair:`", `"  en: <hash>`", `"  zh: <hash>`""
  }
  return @{ En = $lines[1].Substring(6).Trim(); Zh = $lines[2].Substring(6).Trim() }
}

# Extract fenced code blocks' exact bytes, joined by newlines.
function Get-Fences([string]$text) {
  (@([regex]::Matches($text, '```[^\n]*\n[\s\S]*?```') | ForEach-Object { $_.Value }) -join "`n")
}

# Canonicalized link targets with the document's own name dropped (a target
# may carry a #anchor after the .zh.md suffix).
function Get-SignatureLinks([string]$text, [string]$ownCanonicalName) {
  @([regex]::Matches($text, '\]\(([^)]+)\)') | ForEach-Object {
    $target = $_.Groups[1].Value -replace '\.zh\.md(#|$)', '.md$1'
    if ($target -ne $ownCanonicalName) { $target }
  })
}

# First differing signature key of the two sides, or $null.
function Get-SignatureDiff([string]$enRel, [string]$en, [string]$zh) {
  $enName = Split-Path -Leaf $enRel
  $enLinks = (Get-SignatureLinks $en $enName) -join "`n"
  $zhLinks = (Get-SignatureLinks $zh $enName) -join "`n"
  $enFences = Get-Fences $en
  $zhFences = Get-Fences $zh
  $sigs = @{
    headings    = @(([regex]::Matches($en, '(?m)^#{1,6} ')).Count, ([regex]::Matches($zh, '(?m)^#{1,6} ')).Count)
    listItems   = @(([regex]::Matches($en, '(?m)^\s*([-*+]|\d+\.)\s+')).Count, ([regex]::Matches($zh, '(?m)^\s*([-*+]|\d+\.)\s+')).Count)
    tableRows   = @(([regex]::Matches($en, '(?m)^\|')).Count, ([regex]::Matches($zh, '(?m)^\|')).Count)
    linkTargets = @($enLinks, $zhLinks)
    fences      = @($enFences, $zhFences)
  }
  foreach ($key in @('headings', 'listItems', 'tableRows', 'linkTargets', 'fences')) {
    if ("$($sigs[$key][0])" -ne "$($sigs[$key][1])") { return $key }
  }
  return $null
}

# True when the first six lines contain a markdown link to $counterpartName.
function Test-LinksCounterpart([string]$text, [string]$counterpartName) {
  $head = (@($text -split "`n")[0..5] -join "`n")
  $pattern = '\]\(' + [regex]::Escape($counterpartName) + '\)'
  return $head -match $pattern
}

# Verify every pair in scope. <root> then English-side paths (all in scope
# when none given); returns the violation list.
function Get-PairingViolations([string]$root, [string[]]$sources = @()) {
  $violations = [System.Collections.Generic.List[string]]::new()
  if ($sources.Count -eq 0) { $sources = Get-PairingScope $root }
  foreach ($rel in $sources) {
    $base = $rel -replace '\.md$', ''
    $enRel = $rel
    $zhRel = "$base.zh.md"
    $sidecarRel = "$base.i18n.yaml"
    $enPath = Join-Path $root $enRel
    $zhPath = Join-Path $root $zhRel
    $sidecarPath = Join-Path $root $sidecarRel
    $missing = @()
    if (-not (Test-Path -LiteralPath $enPath)) { $missing += $enRel }
    if (-not (Test-Path -LiteralPath $zhPath)) { $missing += $zhRel }
    if (-not (Test-Path -LiteralPath $sidecarPath)) { $missing += $sidecarRel }
    if ($missing.Count -gt 0) {
      $violations.Add("${rel}: incomplete pair — missing $($missing -join ', ')")
      continue
    }
    try {
      $recorded = Read-PairingSidecar $sidecarPath
    } catch {
      $violations.Add("verify-translation-pairing: ${sidecarRel}: $($_.Exception.Message)")
      continue
    }
    $enHash = Get-BlobHash $root $enRel
    $zhHash = Get-BlobHash $root $zhRel
    $stale = @()
    if ($recorded.En -ne $enHash) { $stale += 'English' }
    if ($recorded.Zh -ne $zhHash) { $stale += '中文' }
    if ($stale.Count -gt 0) {
      $violations.Add("${rel}: $($stale -join ' and ') side edited since the last confirmed state — re-confirm with -Write in the same change, or revert")
    }
    $enText = Get-Content -LiteralPath $enPath -Raw
    $zhText = Get-Content -LiteralPath $zhPath -Raw
    $diffKey = Get-SignatureDiff $enRel $enText $zhText
    if ($diffKey) {
      $violations.Add("${zhRel}: structural mismatch on $diffKey; both sides must carry the same structure")
    }
    if (-not (Test-LinksCounterpart $zhText (Split-Path -Leaf $enRel))) {
      $violations.Add("${zhRel}: must link the English side in the first lines (language switcher)")
    }
    if (-not (Test-LinksCounterpart $enText (Split-Path -Leaf $zhRel))) {
      $violations.Add("${enRel}: must link the Chinese side in the first lines (language switcher)")
    }
  }
  return $violations
}

# Re-record one pair's hashes after a confirmed-consistent edit.
function Write-PairingSidecar([string]$rel) {
  $base = $rel -replace '\.md$', ''
  $enRel = $rel
  $zhRel = "$base.zh.md"
  $sidecarRel = "$base.i18n.yaml"
  $missing = @()
  if (-not (Test-Path -LiteralPath (Join-Path $script:Root $enRel))) { $missing += $enRel }
  if (-not (Test-Path -LiteralPath (Join-Path $script:Root $zhRel))) { $missing += $zhRel }
  if ($missing.Count -gt 0) {
    [Console]::Error.WriteLine("verify-translation-pairing: cannot write an incomplete pair — missing $($missing -join ', ')")
    return 2
  }
  $enHash = Get-BlobHash $script:Root $enRel
  $zhHash = Get-BlobHash $script:Root $zhRel
  # Byte-identical with the bash port: LF newlines, trailing newline.
  [IO.File]::WriteAllText((Join-Path $script:Root $sidecarRel), "pair:`n  en: $enHash`n  zh: $zhHash`n")
  Write-Output "verify-translation-pairing: recorded $enRel"
  return 0
}

function PairingMain {
  if ($Write) {
    if ([string]::IsNullOrEmpty($Path)) {
      [Console]::Error.WriteLine('verify-translation-pairing: -Write takes exactly one English-side path, e.g. -Write -Path README.md')
      exit 2
    }
    $full = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
    $rel = [IO.Path]::GetRelativePath($script:Root, $full).Replace('\', '/')
    exit (Write-PairingSidecar $rel)
  }
  $violations = Get-PairingViolations $script:Root
  if ($violations.Count -eq 0) {
    Write-Output 'verify-translation-pairing: all pairs confirmed consistent at recorded contents.'
    exit 0
  }
  [Console]::Error.WriteLine("verify-translation-pairing: $($violations.Count) violation(s):")
  foreach ($v in $violations) { [Console]::Error.WriteLine("  $v") }
  exit 1
}

if (-not $AsLib) { PairingMain }
