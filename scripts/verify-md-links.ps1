#!/usr/bin/env pwsh
# Verify that relative Markdown links and reference definitions resolve (pwsh
# twin of verify-md-links.sh): the target file must exist, and a #fragment on
# a Markdown target must name a real heading slug (same-file #anchors
# included). Fenced code blocks are not scanned. URL, mailto:, and
# root-absolute targets are excluded; a ?query never affects resolution.
# Archived notes are frozen and excluded — a dead link there is unfixable.
# Explicit <a id> anchors are not recognized; state the heading instead.

param([switch]$AsLib)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Remove-MdFences([string]$text) {
  $kept = @()
  $inFence = $false
  foreach ($line in @($text -split "`n")) {
    if ($line -match '^```') { $inFence = -not $inFence; continue }
    if (-not $inFence) { $kept += $line }
  }
  return ($kept -join "`n")
}

function Get-AllLinkTargets([string]$text) {
  $targets = [System.Collections.Generic.List[string]]::new()
  foreach ($m in [regex]::Matches($text, '\]\(([^)]+)\)')) {
    $targets.Add($m.Groups[1].Value)
  }
  foreach ($line in @($text -split "`n")) {
    if ($line -match '^\s*\[[^\]]+\]:\s*(\S+)') {
      $targets.Add($Matches[1])
    }
  }
  return $targets
}

# GitHub-style heading slug: lowercase, spaces to hyphens, punctuation
# dropped; IsLetterOrDigit keeps CJK characters.
function ConvertTo-HeadingSlug([string]$text) {
  $sb = [System.Text.StringBuilder]::new()
  foreach ($ch in $text.Trim().ToLowerInvariant().ToCharArray()) {
    if ($ch -eq ' ') { [void]$sb.Append('-') }
    elseif ([char]::IsLetterOrDigit($ch) -or $ch -eq '-' -or $ch -eq '_') { [void]$sb.Append($ch) }
  }
  return $sb.ToString()
}

# All heading slugs of one text, deduplicated GitHub-style (second -1, third -2).
function Get-HeadingSlugs([string]$text) {
  $slugs = [System.Collections.Generic.List[string]]::new()
  $seen = @{}
  foreach ($line in @($text -split "`n")) {
    if ($line -notmatch '^#{1,6}\s+(.+)$') { continue }
    $slug = ConvertTo-HeadingSlug $Matches[1]
    if ($slug -eq '') { continue }
    if ($seen.ContainsKey($slug)) {
      $seen[$slug]++
      $slug = "$slug-$($seen[$slug])"
    } else {
      $seen[$slug] = 0
    }
    $slugs.Add($slug)
  }
  return $slugs
}

# Verify every in-scope Markdown file under $root (default: this repository).
function Get-MdLinkViolations([string]$root = $script:Root) {
  $violations = [System.Collections.Generic.List[string]]::new()
  $files = @(Get-ChildItem -LiteralPath $root -File -Filter '*.md')
  foreach ($sub in @('docs', '.agents')) {
    $subPath = Join-Path $root $sub
    if (Test-Path -LiteralPath $subPath) {
      $files += @(Get-ChildItem -LiteralPath $subPath -Recurse -File -Filter '*.md')
    }
  }
  foreach ($f in $files) {
    if ($f.FullName -like "*$([IO.Path]::DirectorySeparatorChar).agents$([IO.Path]::DirectorySeparatorChar)notes$([IO.Path]::DirectorySeparatorChar)archived$([IO.Path]::DirectorySeparatorChar)*") { continue }
    $text = Remove-MdFences (Get-Content -LiteralPath $f.FullName -Raw)
    $ownSlugs = $null
    foreach ($target in @(Get-AllLinkTargets $text)) {
      if ($target -eq '') { continue }
      $target = $target.Trim('<', '>')
      if ($target -match '^(https?://|mailto:|tel:|data:)') { continue }
      $target = ($target -split '\?', 2)[0]
      $path, $anchor = $target -split '#', 2
      if ($path -eq '') {
        if ($null -eq $ownSlugs) { $ownSlugs = Get-HeadingSlugs $text }
        if ($anchor -and ($ownSlugs -notcontains $anchor)) {
          $violations.Add("$($f.Name): same-file anchor '#$anchor' names no heading")
        }
        continue
      }
      if ($path.StartsWith('/') -or $path -match '^[A-Za-z]:') { continue }
      $dir = Split-Path -Parent $f.FullName
      $targetPath = [IO.Path]::GetFullPath((Join-Path $dir $path))
      $parentDir = Split-Path -Parent $targetPath
      if (-not (Test-Path -LiteralPath $parentDir)) {
        $violations.Add("$($f.Name): target '$path' does not resolve")
        continue
      }
      if (-not (Test-Path -LiteralPath $targetPath)) {
        $violations.Add("$($f.Name): target '$path' does not exist")
        continue
      }
      if ($anchor -and $targetPath.EndsWith('.md')) {
        $targetSlugs = Get-HeadingSlugs (Remove-MdFences (Get-Content -LiteralPath $targetPath -Raw))
        if ($targetSlugs -notcontains $anchor) {
          $rel = [IO.Path]::GetRelativePath($root, $targetPath).Replace('\', '/')
          $violations.Add("$($f.Name): anchor '#$anchor' on '$rel' names no heading")
        }
      }
    }
  }
  return $violations
}

function MdLinksMain {
  $violations = Get-MdLinkViolations
  if ($violations.Count -eq 0) {
    Write-Output 'verify-md-links: every relative link and anchor resolves.'
    exit 0
  }
  [Console]::Error.WriteLine("verify-md-links: $($violations.Count) violation(s):")
  foreach ($v in $violations) { [Console]::Error.WriteLine("  $v") }
  exit 1
}

if (-not $AsLib) { MdLinksMain }
