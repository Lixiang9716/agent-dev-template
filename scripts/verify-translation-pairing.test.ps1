#!/usr/bin/env pwsh
# Pairing verifier tests: pwsh twin of verify-translation-pairing.test.sh
# against real throwaway git repositories: a fresh recorded pair passes, a
# one-sided edit fails with the side named, a structural divergence fails
# with the signature key, and an incomplete pair is reported, not crashed on.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'verify-translation-pairing.ps1') -AsLib:$true

# Write a consistent English/Chinese pair body with the switcher links.
function Get-PairBody([string]$lang) {
  if ($lang -eq 'en') {
    return "# Title en`n`n[中文](README.zh.md)`n`n## Section`n`nSome words.`n`n``````sh`nmake check`n``````"
  }
  return "# Title zh`n`n[English](README.md)`n`n## Section`n`n一些文字。`n`n``````sh`nmake check`n``````"
}

# Create a temp git repo containing one valid recorded pair; sets $script:Repo.
function New-TempRepoWithPair {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("pairing-" + [guid]::NewGuid())
  [IO.Directory]::CreateDirectory($dir) | Out-Null
  & git -C $dir init -q
  [IO.File]::WriteAllText((Join-Path $dir 'README.md'), (Get-PairBody 'en') + "`n")
  [IO.File]::WriteAllText((Join-Path $dir 'README.zh.md'), (Get-PairBody 'zh') + "`n")
  $enHash = (& git -C $dir hash-object README.md).Trim()
  $zhHash = (& git -C $dir hash-object README.zh.md).Trim()
  [IO.File]::WriteAllText((Join-Path $dir 'README.i18n.yaml'), "pair:`n  en: $enHash`n  zh: $zhHash`n")
  $script:Repo = $dir
}

function Get-PairingViolationsText {
  param([string]$repo)
  $v = Get-PairingViolations $repo @('README.md')
  return (@($v) -join "`n")
}

New-TempRepoWithPair
Expect-Eq 'a recorded consistent pair passes clean' (Get-PairingViolationsText $script:Repo) ''
Remove-Item -Recurse -Force $script:Repo

# A one-sided edit fails and names the edited side.
New-TempRepoWithPair
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.zh.md'), ((Get-PairBody 'zh') -replace '一些文字。', '更多文字。') + "`n")
$text = Get-PairingViolationsText $script:Repo
Expect-Eq 'a one-sided edit reports exactly one violation' @((Get-PairingViolations $script:Repo @('README.md'))).Count 1
Expect-Contains 'a one-sided edit names the Chinese side' $text '中文 side edited'
Remove-Item -Recurse -Force $script:Repo

# A structural divergence fails with the signature key and the stale hash.
New-TempRepoWithPair
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.zh.md'), ((Get-PairBody 'zh') -replace '一些文字。', "一些文字。`n`n- 列表项") + "`n")
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.i18n.yaml'), "pair:`n  en: x`n  zh: y`n")
$text = Get-PairingViolationsText $script:Repo
Expect-Contains 'a structural divergence names listItems' $text 'structural mismatch on listItems'
Expect-Contains 'the stale side is also named' $text 'edited since'
Remove-Item -Recurse -Force $script:Repo

# An incomplete pair is reported instead of crashing.
New-TempRepoWithPair
Remove-Item -LiteralPath (Join-Path $script:Repo 'README.i18n.yaml')
Expect-Contains 'an incomplete pair is reported' (Get-PairingViolationsText $script:Repo) 'incomplete pair'
Remove-Item -Recurse -Force $script:Repo

# A fence divergence fails on the fences signature.
New-TempRepoWithPair
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.md'), (Get-PairBody 'en') + "`n")
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.zh.md'), ((Get-PairBody 'zh') -replace 'make check', 'make build') + "`n")
$enHash = (& git -C $script:Repo hash-object README.md).Trim()
$zhHash = (& git -C $script:Repo hash-object README.zh.md).Trim()
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.i18n.yaml'), "pair:`n  en: $enHash`n  zh: $zhHash`n")
Expect-Contains 'a fence divergence names fences' (Get-PairingViolationsText $script:Repo) 'structural mismatch on fences'
Remove-Item -Recurse -Force $script:Repo
# Anchored counterpart links canonicalize across languages; a differing
# anchor fails on linkTargets.
New-TempRepoWithPair
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.md'), (Get-PairBody 'en') + "`n`n[deep](README.zh.md#section)`n")
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.zh.md'), (Get-PairBody 'zh') + "`n`n[深链](README.md#section)`n")
$enHash = (& git -C $script:Repo hash-object README.md).Trim()
$zhHash = (& git -C $script:Repo hash-object README.zh.md).Trim()
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.i18n.yaml'), "pair:`n  en: $enHash`n  zh: $zhHash`n")
$text = Get-PairingViolationsText $script:Repo
Expect-Eq 'anchored counterpart links pass clean' $text ''
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.zh.md'), ((Get-PairBody 'zh') + "`n`n[深链](README.md#other)`n"))
$zhHash2 = (& git -C $script:Repo hash-object README.zh.md).Trim()
[IO.File]::WriteAllText((Join-Path $script:Repo 'README.i18n.yaml'), "pair:`n  en: $enHash`n  zh: $zhHash2`n")
$text = Get-PairingViolationsText $script:Repo
Expect-Contains 'a differing anchor fails on linkTargets' $text 'structural mismatch on linkTargets'
Remove-Item -Recurse -Force $script:Repo

Complete-TestSuite
