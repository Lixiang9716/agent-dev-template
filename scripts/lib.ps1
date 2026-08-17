# Shared library for the pwsh governance scripts: test assertions for
# scripts/*.test.ps1 and small helpers. Dot-sourced, never executed alone.

$ErrorActionPreference = 'Stop'

# --- test assertions ------------------------------------------------------------

if (-not (Get-Variable -Name T_Total -Scope Script -ErrorAction SilentlyContinue)) {
  $script:T_Total = 0
  $script:T_Failed = 0
}

function Fail([string]$desc) {
  $script:T_Failed++
  [Console]::Error.WriteLine("FAIL $desc")
}

function Expect-Eq([string]$desc, $actual, $expected) {
  $script:T_Total++
  if ("$actual" -ne "$expected") { Fail "${desc}: expected [$expected], got [$actual]" }
}

function Expect-Contains([string]$desc, $haystack, $needle) {
  $script:T_Total++
  if (-not ("$haystack".IndexOf($needle, [StringComparison]::Ordinal) -ge 0)) {
    Fail "${desc}: [$haystack] does not contain [$needle]"
  }
}

function Expect-Match([string]$desc, $text, [string]$pattern) {
  $script:T_Total++
  if (-not ("$text" -match $pattern)) { Fail "${desc}: [$text] does not match /$pattern/" }
}

function Expect-Status([string]$desc, [int]$expected, [int]$actual) {
  $script:T_Total++
  if ($actual -ne $expected) { Fail "${desc}: expected status $expected, got $actual" }
}

function Complete-TestSuite {
  [Console]::Error.WriteLine("$($script:T_Total) check(s), $($script:T_Failed) failed")
  if ($script:T_Failed -gt 0) { exit 1 }
  exit 0
}

# --- helpers ---------------------------------------------------------------------

# The sha256 of one file's bytes, lowercase hex.
function Get-FileSha256([string]$path) {
  (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Run git with args in $repoDir; returns stdout as one newline-joined string
# (trailing newline trimmed); throws on failure with the git command and
# stderr in the message.
function Invoke-Git([string]$repoDir, [string[]]$Arguments) {
  $out = & git -C $repoDir @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') failed: $out"
  }
  $joined = (@($out) -join "`n")
  return $joined.TrimEnd("`n")
}
