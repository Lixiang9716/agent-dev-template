#!/usr/bin/env pwsh
# change-scope contract tests (pwsh twin of change-scope.test.sh) against a
# real throwaway git repository: the four path classes partition real states,
# and an unresolvable base fails loud instead of producing an empty record.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'change-scope.ps1') -AsLib:$true

# Create a git repo with an initial commit on main; sets $script:Repo.
function New-TempRepo {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("change-scope-" + [guid]::NewGuid())
  [IO.Directory]::CreateDirectory($dir) | Out-Null
  & git -C $dir init -q --initial-branch=main
  & git -C $dir config user.email test@example.com
  & git -C $dir config user.name test
  [IO.File]::WriteAllText((Join-Path $dir 'seed.txt'), "seed`n")
  & git -C $dir add .
  & git -C $dir commit -q -m seed
  $script:Repo = $dir
}

# The four path classes partition committed, staged, unstaged, untracked.
New-TempRepo
$repo = $script:Repo
[IO.File]::WriteAllText((Join-Path $repo 'committed.txt'), "committed`n")
& git -C $repo add .
& git -C $repo commit -q -m committed
[IO.File]::WriteAllText((Join-Path $repo 'staged.txt'), "staged`n")
& git -C $repo add .
# An unstaged change must modify a tracked file; a never-added file is untracked.
[IO.File]::WriteAllText((Join-Path $repo 'committed.txt'), "committed, then modified`n")
[IO.File]::WriteAllText((Join-Path $repo 'untracked.txt'), "untracked`n")
$scope = (Get-ChangeScope $repo 'HEAD~1').Replace("`r", '')
Expect-Contains 'format version pinned' $scope '"formatVersion": 1'
Expect-Contains 'committed class lists the committed path' $scope '"committed": [
    "committed.txt"'
Expect-Contains 'staged class lists the staged path' $scope '"staged": [
    "staged.txt"'
Expect-Contains 'unstaged class lists the tracked modification' $scope '"unstaged": [
    "committed.txt"'
Expect-Contains 'untracked class lists the never-added path' $scope '"untracked.txt"'
Remove-Item -Recurse -Force $repo

# A clean tree reports empty path classes and a resolvable merge base.
New-TempRepo
$repo = $script:Repo
$scope = (Get-ChangeScope $repo 'HEAD').Replace("`r", '')
$headSha = (& git -C $repo rev-parse HEAD).Trim()
Expect-Contains 'clean tree has empty committed' $scope '"committed": []'
Expect-Contains 'clean tree has empty staged' $scope '"staged": []'
Expect-Contains 'clean tree has empty unstaged' $scope '"unstaged": []'
Expect-Contains 'clean tree has empty untracked' $scope '"untracked": []'
Expect-Contains 'merge base equals head on a clean tree' $scope ('"mergeBaseSha": "' + $headSha + '"')
Remove-Item -Recurse -Force $repo

# An unresolvable base fails loud with the git error.
New-TempRepo
$repo = $script:Repo
$err = ''
try {
  Get-ChangeScope $repo 'no-such-ref' | Out-Null
  $code = 0
} catch {
  $code = 1
  $err = $_.Exception.Message
}
Expect-Status 'unresolvable base fails' 1 $code
Expect-Contains 'unresolvable base names the git command' $err 'rev-parse'
Remove-Item -Recurse -Force $repo

Complete-TestSuite
