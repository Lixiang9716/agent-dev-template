#!/usr/bin/env pwsh
# Link verifier tests (pwsh twin of verify-md-links.test.sh): a valid tree
# passes clean; a missing file, a missing anchor on another file, a bad
# same-file anchor, and a dead reference definition each fail with the
# offending link named. Fenced links and URL targets are never flagged.
# A gate only guards if the regression actually fails it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'verify-md-links.ps1') -AsLib:$true

function Get-ViolationsText([string]$tree) {
  $v = Get-MdLinkViolations $tree
  return (@($v) -join "`n")
}

# A valid tree: file link, cross-file anchor, same-file anchor, URL, fenced link.
$tree = Join-Path ([IO.Path]::GetTempPath()) ("mdlinks-" + [guid]::NewGuid())
[IO.Directory]::CreateDirectory("$tree/docs") | Out-Null
[IO.File]::WriteAllText("$tree/README.md", "# Title`n`n[zh](README.zh.md#section-one) and [docs](docs/guide.md) and [web](https://example.com/x).`n`n``````sh`n[fenced](missing-inside-fence.md)`n```````n`n[anchor](#title)`n")
[IO.File]::WriteAllText("$tree/README.zh.md", "# 标题`n`n[English](README.md#title)`n`n## Section one`n")
[IO.File]::WriteAllText("$tree/docs/guide.md", "# Guide`n`n## Overview`n")
$text = Get-ViolationsText $tree
Expect-Eq 'a valid tree passes clean' $text ''
Remove-Item -Recurse -Force $tree

# A missing file fails with the link named.
$tree = Join-Path ([IO.Path]::GetTempPath()) ("mdlinks-" + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($tree) | Out-Null
[IO.File]::WriteAllText("$tree/README.md", "# T`n`n[x](gone.md)`n")
$text = Get-ViolationsText $tree
Expect-Contains 'missing file reported' $text "target 'gone.md' does not exist"
Remove-Item -Recurse -Force $tree

# A missing anchor on another file fails with both names.
$tree = Join-Path ([IO.Path]::GetTempPath()) ("mdlinks-" + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($tree) | Out-Null
[IO.File]::WriteAllText("$tree/README.md", "# T`n`n[x](README.zh.md#nope)`n")
[IO.File]::WriteAllText("$tree/README.zh.md", "# Z`n")
$text = Get-ViolationsText $tree
Expect-Contains 'missing cross-file anchor reported' $text "anchor '#nope' on 'README.zh.md' names no heading"
Remove-Item -Recurse -Force $tree

# A bad same-file anchor fails.
$tree = Join-Path ([IO.Path]::GetTempPath()) ("mdlinks-" + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($tree) | Out-Null
[IO.File]::WriteAllText("$tree/README.md", "# T`n`n[x](#ghost)`n")
$text = Get-ViolationsText $tree
Expect-Contains 'bad same-file anchor reported' $text "same-file anchor '#ghost' names no heading"
Remove-Item -Recurse -Force $tree

# A dead reference definition fails; archived notes are skipped.
$tree = Join-Path ([IO.Path]::GetTempPath()) ("mdlinks-" + [guid]::NewGuid())
[IO.Directory]::CreateDirectory("$tree/.agents/notes/archived") | Out-Null
[IO.File]::WriteAllText("$tree/README.md", "# T`n`n[ref]`n`n[ref]: gone-again.md`n")
[IO.File]::WriteAllText("$tree/.agents/notes/archived/2026-01-01-frozen.md", "# Frozen`n`n[dead](broken.md)`n")
$text = Get-ViolationsText $tree
Expect-Contains 'dead reference definition reported' $text "target 'gone-again.md' does not exist"
Expect-Eq 'archived notes are not link-checked' ($text.Contains('broken.md')) $false
Remove-Item -Recurse -Force $tree

Complete-TestSuite
