#!/usr/bin/env pwsh
# Negative and positive tests for the notes verifier (pwsh twin of
# verify-agent-notes.test.sh): every rejection rule fires on a minimal
# violating tree, and a valid tree passes clean. A gate only guards if the
# regression actually fails it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'verify-agent-notes.ps1') -AsLib:$true

$validImplemented = @'
# Agent Note: sample decision

Status: implemented

## Problem

A problem statement.

## Decision

The decision.

## Alternatives considered

An alternative and why it lost.

## Consequences

What follows.
'@

# Create a throwaway notes tree with one note; sets $script:Tree.
function New-NotesTree([string]$lifecycle, [string]$class, [string]$filename, [string]$body) {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("notes-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path (Join-Path $dir "$lifecycle/$class") -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $dir "$lifecycle/$class/$filename"), $body + "`n")
  [IO.File]::WriteAllText((Join-Path $dir 'README.md'), "# Agent Notes`n")
  $script:Tree = $dir
}

function Get-ViolationsText {
  param([string]$tree)
  $v = Get-AgentNotesViolations $tree
  return (@($v) -join "`n")
}

New-NotesTree 'implemented' 'process' '2026-01-01-valid-note.md' $validImplemented
Expect-Eq 'a valid implemented note passes clean' (Get-ViolationsText $script:Tree) ''
Remove-Item -Recurse -Force $script:Tree

# An unknown lifecycle directory is rejected.
$tree = Join-Path ([IO.Path]::GetTempPath()) ("notes-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $tree 'drafts/process') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $tree 'drafts/process/2026-01-01-x.md'), $validImplemented + "`n")
[IO.File]::WriteAllText((Join-Path $tree 'README.md'), "# Agent Notes`n")
Expect-Contains 'an unknown lifecycle directory is rejected' (Get-ViolationsText $tree) 'unknown lifecycle'
Remove-Item -Recurse -Force $tree

# An unknown class directory is rejected.
New-NotesTree 'implemented' 'misc' '2026-01-01-x.md' $validImplemented
Expect-Contains 'an unknown class directory is rejected' (Get-ViolationsText $script:Tree) 'unknown class'
Remove-Item -Recurse -Force $script:Tree

# A malformed filename is rejected.
New-NotesTree 'implemented' 'process' 'notes.md' $validImplemented
Expect-Contains 'a malformed filename is rejected' (Get-ViolationsText $script:Tree) 'yyyy-mm-dd-topic.md'
Remove-Item -Recurse -Force $script:Tree

# An implemented note with a Proposal section is rejected.
$mutated = $validImplemented -replace '(?m)^## Decision$', "## Proposal`n`nOld text.`n`n## Decision"
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $mutated
Expect-Contains 'an implemented note with a Proposal section is rejected' (Get-ViolationsText $script:Tree) 'proposal-era'
Remove-Item -Recurse -Force $script:Tree

# A rejected note without a reason suffix on Status is rejected.
New-NotesTree 'rejected' 'process' '2026-01-01-x.md' ($validImplemented -replace 'Status: implemented', 'Status: rejected')
Expect-Contains 'a rejected note without a reason suffix is rejected' (Get-ViolationsText $script:Tree) 'Status: rejected —'
Remove-Item -Recurse -Force $script:Tree

# A proposed note missing Acceptance criteria is rejected.
$proposedBody = @'
# Agent Note: sample proposal

Status: proposed

## Problem

P.

## Proposal

Do it.

## Alternatives considered

None.

## Risks

Few.
'@
New-NotesTree 'proposed' 'process' '2026-01-01-x.md' $proposedBody
Expect-Contains 'a proposed note missing Acceptance criteria is rejected' (Get-ViolationsText $script:Tree) 'Acceptance criteria'
Remove-Item -Recurse -Force $script:Tree

# INDEX.md is rejected wherever it appears.
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $validImplemented
[IO.File]::WriteAllText((Join-Path $script:Tree 'implemented/process/INDEX.md'), "# index`n")
Expect-Contains 'INDEX.md is rejected wherever it appears' (Get-ViolationsText $script:Tree) 'INDEX.md is forbidden'
Remove-Item -Recurse -Force $script:Tree

# The archived tree is never re-validated here.
New-NotesTree 'implemented' 'process' '2026-01-01-valid-note.md' $validImplemented
New-Item -ItemType Directory -Path (Join-Path $script:Tree 'archived') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $script:Tree 'archived/anything.md'), "not a note`n")
Expect-Eq 'the archived tree is never re-validated' (Get-ViolationsText $script:Tree) ''
Remove-Item -Recurse -Force $script:Tree

# --- entry discipline ---------------------------------------------------------

# An implemented note with a trailing extra section (claims/open/sampling).
function New-NoteWith([string]$extra) {
  return "$validImplemented`n$extra"
}

# A well-formed Claim entry passes.
$body = New-NoteWith @'
## Claims

- Claim: the gate rejects every banned form.
  - verifier: scripts/verify-vocabulary.test.sh
  - coverage: en and zh families, all exemptions
  - goal-link: invariant-3 (declaration-state vocabulary)
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Eq 'a well-formed Claim entry passes' (Get-ViolationsText $script:Tree) ''
Remove-Item -Recurse -Force $script:Tree

# A Claim entry missing verifier is rejected naming the field.
$body = New-NoteWith @'
## Claims

- Claim: the gate rejects every banned form.
  - coverage: en and zh families
  - goal-link: invariant-3
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Contains 'Claim missing verifier is rejected' (Get-ViolationsText $script:Tree) 'Claim entry "Claim: the gate rejects every banned form." missing sub-bullet(s): verifier'
Remove-Item -Recurse -Force $script:Tree

# A Claim entry missing coverage and goal-link is rejected naming both.
$body = New-NoteWith @'
## Claims

- Claim: the gate rejects every banned form.
  - verifier: scripts/verify-vocabulary.test.sh
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Contains 'Claim missing coverage and goal-link is rejected' (Get-ViolationsText $script:Tree) 'missing sub-bullet(s): coverage goal-link'
Remove-Item -Recurse -Force $script:Tree

# An Open entry without settled-by is rejected.
$body = New-NoteWith @'
## Open

- Open: why is the window six characters?
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Contains 'Open entry without settled-by is rejected' (Get-ViolationsText $script:Tree) 'Open entry "Open: why is the window six characters?" missing sub-bullet(s): settled-by'
Remove-Item -Recurse -Force $script:Tree

# An Open entry with settled-by passes.
$body = New-NoteWith @'
## Open

- Open: why is the window six characters?
  - settled-by: the next revision cycle
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Eq 'an Open entry with settled-by passes' (Get-ViolationsText $script:Tree) ''
Remove-Item -Recurse -Force $script:Tree

# A not-refuted statement without sampling fields is rejected naming all three.
$body = New-NoteWith @'
## Verification

- Status: not-refuted for now.
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Contains 'not-refuted without sampling is rejected' (Get-ViolationsText $script:Tree) 'statement containing "not-refuted" missing sampling field(s) in its paragraph: rate schedule reviewer'
Remove-Item -Recurse -Force $script:Tree

# A not-refuted statement with inline sampling passes.
$body = New-NoteWith @'
## Verification

- Status: not-refuted (rate: weekly, schedule: fridays, reviewer: oracle-a).
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Eq 'not-refuted with inline sampling passes' (Get-ViolationsText $script:Tree) ''
Remove-Item -Recurse -Force $script:Tree

# A not-refuted statement with sampling sub-bullets passes.
$body = New-NoteWith @'
## Verification

- Status: not-refuted.
  - rate: 0.2
  - schedule: weekly
  - reviewer: oracle-a
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Eq 'not-refuted with sampling sub-bullets passes' (Get-ViolationsText $script:Tree) ''
Remove-Item -Recurse -Force $script:Tree

# An empty sub-bullet value does not satisfy the requirement.
$body = New-NoteWith @'
## Claims

- Claim: the gate rejects every banned form.
  - verifier:
  - coverage: en and zh families
  - goal-link: invariant-3
'@
New-NotesTree 'implemented' 'process' '2026-01-01-x.md' $body
Expect-Contains 'an empty sub-bullet value is still missing' (Get-ViolationsText $script:Tree) 'missing sub-bullet(s): verifier'
Remove-Item -Recurse -Force $script:Tree

Complete-TestSuite
