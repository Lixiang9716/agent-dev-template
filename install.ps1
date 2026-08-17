# Scaffold a new project from agent-dev-template in one line (Windows
# PowerShell or any pwsh 7+):
#   irm https://raw.githubusercontent.com/Lixiang9716/agent-dev-template/master/install.ps1 | iex
#
# The pwsh twin of install.sh: downloads the template tarball (the latest
# release by default; AGENT_DEV_REF pins a tag or commit sha, AGENT_DEV_REPO
# redirects to a fork), extracts it into my-project (AGENT_DEV_DIR overrides),
# starts a fresh git history, and verifies the gates. Fail loud: any error
# throws with the offending step instead of exiting half-installed.

param([string]$Target = $(if ($env:AGENT_DEV_DIR) { $env:AGENT_DEV_DIR } else { 'my-project' }))

$ErrorActionPreference = 'Stop'

$repo = if ($env:AGENT_DEV_REPO) { $env:AGENT_DEV_REPO } else { 'Lixiang9716/agent-dev-template' }
$ref = $env:AGENT_DEV_REF
if (-not $ref) {
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
  $ref = $release.tag_name
}

if (Test-Path -LiteralPath $Target) {
  throw "install: target directory '$Target' already exists — pick a fresh name"
}

$tmp = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ("agent-dev-" + [guid]::NewGuid()))
try {
  $tarball = Join-Path $tmp.FullName 'template.tar.gz'
  Invoke-WebRequest -Uri "https://codeload.github.com/$repo/tar.gz/$ref" -OutFile $tarball
  New-Item -ItemType Directory -Path $Target | Out-Null
  # tar ships with Windows 10+, macOS, and Linux; --strip-components drops the
  # leading <repo>-<ref>/ directory.
  tar -xzf $tarball -C $Target --strip-components=1
  if ($LASTEXITCODE -ne 0) { throw 'install: extraction failed' }
} finally {
  Remove-Item -Recurse -Force $tmp.FullName -ErrorAction SilentlyContinue
}

if (Get-Command git -ErrorAction SilentlyContinue) {
  git -C $Target init -q
  if ($LASTEXITCODE -ne 0) { throw 'install: git init failed' }
  git -C $Target add -A
  if ($LASTEXITCODE -ne 0) { throw 'install: git add failed' }
} else {
  [Console]::Error.WriteLine('install: git not found — run "git init" yourself')
}

$scaffold = Join-Path (Get-Location).Path $Target
$status = 'no pwsh 7+ found — gates not run'
if ($PSVersionTable.PSVersion.Major -ge 7 -or (Get-Command pwsh -ErrorAction SilentlyContinue)) {
  Push-Location $scaffold
  try {
    pwsh -File scripts/gates.ps1 -Mode all
    if ($LASTEXITCODE -ne 0) { throw 'install: the pwsh gates failed on the fresh scaffold' }
    $status = 'gates green (pwsh)'
  } finally {
    Pop-Location
  }
}

Write-Output "install: scaffolded './$Target' ($status)"
Write-Output "install: next: cd $Target; sh scripts/install-hooks.sh"
