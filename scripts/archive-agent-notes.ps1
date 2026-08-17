#!/usr/bin/env pwsh
# Seal and verify the archived Agent Notes tree (pwsh port; bash twin:
# archive-agent-notes.sh).
#
# Every archived note is content-addressed by sha256 in manifest.json. Check
# mode fails on: a sealed note whose content changed, a manifest entry with
# no file, or a new unsealed note (run -Write to seal). -Write only appends
# new hashes; it never rewrites or removes existing seals. After a triplet is
# sealed, never edit, move, or delete it.

param(
  [switch]$Write,
  [switch]$AsLib
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ArchiveDir = Join-Path $script:Root '.agents/notes/archived'
$script:ManifestPath = Join-Path $script:ArchiveDir 'manifest.json'

function Get-ArchivedFiles([string]$archiveDir) {
  @(Get-ChildItem -LiteralPath $archiveDir -Recurse -File -Filter '*.md' |
    Sort-Object FullName | ForEach-Object {
      [IO.Path]::GetRelativePath($archiveDir, $_.FullName).Replace('\', '/')
    })
}

# Read manifest.json as an ordered list of @{Path; Sha256}; a missing or
# unparseable manifest reads as empty — -Write then seals everything.
function Read-ArchiveManifest {
  $entries = [System.Collections.Generic.List[object]]::new()
  if (-not (Test-Path -LiteralPath $script:ManifestPath)) { return $entries }
  try {
    $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json -AsHashtable
  } catch {
    return $entries
  }
  if (-not $manifest.ContainsKey('files') -or $manifest['files'] -isnot [hashtable]) { return $entries }
  foreach ($key in @($manifest['files'].Keys)) {
    $sha = $null
    if ($manifest['files'][$key] -is [hashtable] -and $manifest['files'][$key].ContainsKey('sha256')) {
      $sha = [string]$manifest['files'][$key]['sha256']
    }
    $entries.Add([pscustomobject]@{ Path = $key; Sha256 = $sha })
  }
  return $entries
}

# Validate header shape: line 1 title, line 3 implemented status, line 4 the
# archive date, which must not predate the filename date.
function Test-ArchiveHeader([string]$relPath, [string]$absPath, $violations) {
  $lines = (Get-Content -LiteralPath $absPath -Raw) -split "`n"
  if (-not $lines[0].StartsWith('# Agent Note: ')) {
    $violations.Add("${relPath}: line 1 must be `"# Agent Note: <title>`"")
  }
  if ($lines[2] -ne 'Status: implemented') {
    $violations.Add("${relPath}: line 3 must be `"Status: implemented`" (archived notes were decisions that shipped)")
  }
  $name = Split-Path -Leaf $relPath
  $filenameDate = $name.Substring(0, 10)
  if ($lines[3] -notmatch '^Archived: \d{4}-\d{2}-\d{2}$') {
    $violations.Add("${relPath}: line 4 must be `"Archived: <date>`"")
    return
  }
  $archivedDate = $lines[3].Substring('Archived: '.Length)
  if ([string]::CompareOrdinal($archivedDate, $filenameDate) -lt 0) {
    $violations.Add("${relPath}: archived date $archivedDate predates the filename date $filenameDate")
  }
}

function ArchiveMain([bool]$writeMode) {
  $files = Get-ArchivedFiles $script:ArchiveDir
  $manifest = Read-ArchiveManifest
  $violations = [System.Collections.Generic.List[string]]::new()

  foreach ($rel in $files) {
    Test-ArchiveHeader $rel (Join-Path $script:ArchiveDir $rel) $violations
  }

  $sealed = @{}
  foreach ($entry in $manifest) { $sealed[$entry.Path] = $entry.Sha256 }
  $sealedNew = $false
  foreach ($rel in $files) {
    $digest = Get-FileSha256 (Join-Path $script:ArchiveDir $rel)
    if (-not $sealed.ContainsKey($rel)) {
      if ($writeMode) {
        $sealed[$rel] = $digest
        $manifest.Add([pscustomobject]@{ Path = $rel; Sha256 = $digest })
        $sealedNew = $true
        Write-Output "archive-agent-notes: sealed $rel"
      } else {
        $violations.Add("${rel}: not sealed; run `"pwsh scripts/archive-agent-notes.ps1 -Write`" and commit the manifest")
      }
    } elseif ($sealed[$rel] -ne $digest) {
      $violations.Add("${rel}: content changed after sealing; a sealed note is never edited — restore it or supersede it with a new note")
    }
  }

  foreach ($entry in $manifest) {
    if ($files -notcontains $entry.Path) {
      $violations.Add("$($entry.Path): manifest entry has no file; seals are never removed")
    }
  }

  if ($violations.Count -gt 0) {
    [Console]::Error.WriteLine("archive-agent-notes: $($violations.Count) violation(s):")
    foreach ($v in $violations) { [Console]::Error.WriteLine("  $v") }
    exit 1
  }

  if ($writeMode -and $sealedNew) {
    # Byte-identical format with the bash port: 2-space JSON, LF newlines.
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("{`n  `"files`": {`n")
    for ($i = 0; $i -lt $manifest.Count; $i++) {
      [void]$sb.Append("    `"$($manifest[$i].Path)`": {`n      `"sha256`": `"$($manifest[$i].Sha256)`"`n    }")
      if ($i -lt $manifest.Count - 1) { [void]$sb.Append(',') }
      [void]$sb.Append("`n")
    }
    [void]$sb.Append("  }`n}`n")
    [IO.File]::WriteAllText($script:ManifestPath, $sb.ToString())
  }
  Write-Output 'archive-agent-notes: the archive is sealed and consistent.'
  exit 0
}

if (-not $AsLib) { ArchiveMain ([bool]$Write) }
