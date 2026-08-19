#!/usr/bin/env pwsh
# Validate the Agent Notes tree (pwsh twin of verify-agent-notes.sh):
# closed lifecycle and class sets, dated filenames, the three-line header, the
# required sections per lifecycle, and the entry discipline — Claim entries
# carry verifier/coverage/goal-link sub-bullets, Open entries carry settled-by,
# and "not-refuted" statements carry rate/schedule/reviewer sampling in their
# paragraph. `archived/` is frozen and owned by archive-agent-notes.ps1; this
# verifier never re-validates sealed content. Failures are collected and
# reported all at once with file-relative paths.

param([switch]$AsLib)

$ErrorActionPreference = 'Stop'
$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:NotesDir = Join-Path $script:Root '.agents/notes'

$script:Lifecycles = @('proposed', 'implemented', 'rejected')
$script:Classes = @('feature', 'bug-fix', 'simplification', 'architecture', 'process', 'testing')
$script:RequiredSections = @{
  proposed    = @('Proposal', 'Alternatives considered', 'Acceptance criteria', 'Risks')
  implemented = @('Decision', 'Alternatives considered', 'Consequences')
  rejected    = @('Proposal', 'Alternatives considered')
}
$script:ForbiddenInImplemented = @('Proposal', 'Plan', 'Migration plan', 'Acceptance criteria')

function Add-NoteViolation([System.Collections.Generic.List[string]]$violations, [string]$message) {
  $violations.Add($message)
}

# Validate one note file's header, filename, and sections.
function Test-AgentNote([string]$relPath, [string]$absPath, $violations) {
  $lifecycle = ($relPath -split '/')[0]
  $name = Split-Path -Leaf $relPath
  if ($name -notmatch '^\d{4}-\d{2}-\d{2}-[a-z0-9]+(-[a-z0-9]+)*\.md$') {
    Add-NoteViolation $violations "$relPath`: filename must be yyyy-mm-dd-topic.md (kebab-case topic, dated at first proposal)"
    return
  }
  $lines = (Get-Content -LiteralPath $absPath -Raw) -split "`n"
  $text = Get-Content -LiteralPath $absPath -Raw
  if (-not $lines[0].StartsWith('# Agent Note: ')) {
    Add-NoteViolation $violations "$relPath`: line 1 must be `"# Agent Note: <title>`""
    return
  }
  if ($lines[1] -ne '') { Add-NoteViolation $violations "$relPath`: line 2 must be empty" }
  $line3 = $lines[2]
  if ($lifecycle -eq 'rejected') {
    if ($line3 -notmatch '^Status: rejected — .+$') {
      Add-NoteViolation $violations "$relPath`: line 3 for a rejected note must be `"Status: rejected — <why>`""
    }
  } elseif ($line3 -ne "Status: $lifecycle") {
    Add-NoteViolation $violations "$relPath`: line 3 must be exactly `"Status: $lifecycle`""
  }
  $statusCount = ([regex]::Matches($text, '(?m)^Status: ')).Count
  if ($statusCount -ne 1) { Add-NoteViolation $violations "$relPath`: exactly one `"Status:`" line is allowed" }
  if ($lines[3] -ne '') { Add-NoteViolation $violations "$relPath`: line 4 must be empty" }

  $sections = @([regex]::Matches($text, '(?m)^## (.+)$') | ForEach-Object { $_.Groups[1].Value })
  if ($sections.Count -eq 0 -or $sections[0] -ne 'Problem') {
    Add-NoteViolation $violations "$relPath`: the first section must be `"## Problem`""
  }
  foreach ($want in $script:RequiredSections[$lifecycle]) {
    if ($sections -notcontains $want) {
      Add-NoteViolation $violations "$relPath`: lifecycle `"$lifecycle`" requires a `"## $want`" section"
    }
  }
  if ($lifecycle -eq 'implemented') {
    foreach ($heading in $script:ForbiddenInImplemented) {
      if ($sections -contains $heading) {
        Add-NoteViolation $violations "$relPath`: `"## $heading`" is proposal-era; an implemented note states what is"
      }
    }
  }

  Test-NoteDiscipline $relPath $text $violations
}

# --- entry discipline ---------------------------------------------------------
#
# Optional structured entries (any lifecycle; historical notes without them are
# untouched — the rules bind only the entries that are present):
#   - Claim: <text>      requires sub-bullets verifier / coverage / goal-link
#   - Open: <text>       requires a sub-bullet settled-by
#   a statement containing "not-refuted" requires rate / schedule / reviewer in
#   the same paragraph (blank-line or heading delimited), inline or as
#   sub-bullets.
# A claim/open entry is its bullet plus the consecutive "  - " sub-bullets
# that follow it; the entry text itself must be non-empty.

function Test-SubBullet([string]$line) {
  return $line.StartsWith('  - ')
}

function Get-SubBulletValue([string]$line, [string]$field) {
  $prefix = "  - $field`: "
  if (-not $line.StartsWith($prefix)) { return $null }
  $value = $line.Substring($prefix.Length)
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  return $value
}

function Test-ParagraphBreak([string]$line) {
  return [string]::IsNullOrEmpty($line) -or $line.StartsWith('## ')
}

# Check one claim/open entry: its sub-bullet block must carry every required
# field with a non-empty value. $noteLines holds the note's lines; $idx is the
# entry's index.
function Test-EntryBlock([string]$relPath, [string]$entry, [int]$idx, [string[]]$noteLines, $violations) {
  $kind = 'Open'
  $fields = @('settled-by')
  if ($entry.StartsWith('- Claim: ')) {
    $kind = 'Claim'
    $fields = @('verifier', 'coverage', 'goal-link')
  }
  $missing = @($fields)
  for ($j = $idx + 1; $j -lt $noteLines.Count; $j++) {
    $line = $noteLines[$j]
    if (-not (Test-SubBullet $line)) { break }
    foreach ($f in $fields) {
      if ($null -ne (Get-SubBulletValue $line $f)) {
        $missing = @($missing | Where-Object { $_ -ne $f })
      }
    }
  }
  if ($missing.Count -gt 0) {
    Add-NoteViolation $violations "$relPath`: $kind entry `"$($entry.Substring(2))`" missing sub-bullet(s): $($missing -join ' ')"
  }
}

# Require rate/schedule/reviewer in the paragraph that carries "not-refuted".
function Test-SamplingFields([string]$relPath, [string]$paragraph, $violations) {
  $missing = @('rate', 'schedule', 'reviewer')
  foreach ($line in @($paragraph -split "`n")) {
    foreach ($f in @('rate', 'schedule', 'reviewer')) {
      if ($line -match "(^|[^A-Za-z])$f`:\s*\S") {
        $missing = @($missing | Where-Object { $_ -ne $f })
      }
    }
  }
  if ($missing.Count -gt 0) {
    Add-NoteViolation $violations "$relPath`: statement containing `"not-refuted`" missing sampling field(s) in its paragraph: $($missing -join ' ')"
  }
}

# Check a whole note body for the discipline rules.
function Test-NoteDiscipline([string]$relPath, [string]$text, $violations) {
  $noteLines = @($text -split "`n")
  for ($i = 0; $i -lt $noteLines.Count; $i++) {
    $line = $noteLines[$i]
    if ($line.StartsWith('- Claim: ') -or $line.StartsWith('- Open: ')) {
      Test-EntryBlock $relPath $line $i $noteLines $violations
      $i++
      while ($i -lt $noteLines.Count -and (Test-SubBullet $noteLines[$i])) { $i++ }
      $i--
    }
  }
  $para = ''
  foreach ($line in @($text -split "`n")) {
    if (Test-ParagraphBreak $line) {
      if ($para.Contains('not-refuted')) { Test-SamplingFields $relPath $para $violations }
      $para = ''
    } else {
      $para += "`n$line"
    }
  }
  if ($para.Contains('not-refuted')) { Test-SamplingFields $relPath $para $violations }
}

# Validate the whole notes tree under $notesDir (default: this repository's).
function Get-AgentNotesViolations([string]$notesDir = $script:NotesDir) {
  $violations = [System.Collections.Generic.List[string]]::new()
  foreach ($entry in @(Get-ChildItem -LiteralPath $notesDir -Force | Sort-Object Name)) {
    if ($entry.Name -eq 'README.md' -or $entry.Name -eq 'archived') { continue }
    if ($entry.Name -eq 'INDEX.md') {
      Add-NoteViolation $violations 'INDEX.md is forbidden: the tree layout is the index'
      continue
    }
    if ($script:Lifecycles -notcontains $entry.Name) {
      Add-NoteViolation $violations "$($entry.Name)/: unknown lifecycle directory; closed set is $($script:Lifecycles -join ', ')"
      continue
    }
    foreach ($class in @(Get-ChildItem -LiteralPath $entry.FullName -Force | Sort-Object Name)) {
      $rel = "$($entry.Name)/$($class.Name)"
      if (-not $class.PSIsContainer) {
        Add-NoteViolation $violations "${rel}: unexpected file directly under a lifecycle directory"
        continue
      }
      if ($script:Classes -notcontains $class.Name) {
        Add-NoteViolation $violations "${rel}/: unknown class; closed set is $($script:Classes -join ', ')"
        continue
      }
      foreach ($file in @(Get-ChildItem -LiteralPath $class.FullName -Force | Sort-Object Name)) {
        $rel = "$($entry.Name)/$($class.Name)/$($file.Name)"
        if ($file.Name -eq 'INDEX.md') {
          Add-NoteViolation $violations "${rel}: INDEX.md is forbidden"
        } elseif ($file.Name -like '*.md') {
          Test-AgentNote $rel $file.FullName $violations
        } else {
          Add-NoteViolation $violations "${rel}: notes are English-only Markdown; unexpected file type"
        }
      }
    }
  }
  return $violations
}

function NotesMain {
  $violations = Get-AgentNotesViolations
  if ($violations.Count -eq 0) {
    Write-Output 'verify-agent-notes: the notes tree is valid.'
    exit 0
  }
  [Console]::Error.WriteLine("verify-agent-notes: $($violations.Count) violation(s):")
  foreach ($v in $violations) { [Console]::Error.WriteLine("  $v") }
  exit 1
}

if (-not $AsLib) { NotesMain }
