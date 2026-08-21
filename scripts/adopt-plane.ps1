#!/usr/bin/env pwsh
# Prove the governance plane works on foreign soil (pwsh twin of
# adopt-plane.sh). Simulates one real GitHub template derivation: the whole
# repository (minus .git, local editor state .zcode, and scripts/
# adopt-plane.test.* — the recursive guard re-checks the result) is copied
# into a fresh temporary directory, git is initialized with a local identity,
# and three facts are proven there:
#   (a) `pwsh -File scripts/gates.ps1 -Mode all` is green with zero
#       installation;
#   (b) `sh scripts/install-hooks.sh` installs, and a real `git commit`
#       passes the installed pre-commit;
#   (c) every injected mutation is rejected loudly by its gate and, for the
#       pairing and vocabulary mutations, by the pre-commit hook — each
#       naming its stage.
#
# Usage: adopt-plane.ps1 [-Scaffold <dir>] [-Verify <dir>] [-Clean]
#   (no args)   full run: scaffold into an internal temp dir, verify, clean up
#   -Scaffold <dir>  construct a scaffold only; <dir> is created when missing
#                    and must be empty otherwise; it is left in place. A
#                    refused dir (non-empty, or not a directory) is never
#                    touched.
#   -Verify <dir>    verify a previously constructed scaffold, then remove
#                    <dir>; exits non-zero when the dir's own state is broken
#                    or a rejection was missed. Only a dir carrying this
#                    script's provenance marker (.adopt-plane-provenance,
#                    written by -Scaffold) is accepted — anything else is
#                    rejected and never removed.
#   -Clean      remove this instance's own transient root; foreign instances'
#               roots are never touched (concurrency safety)
#
# Output determinism (hard contract): every line is a fixed ASCII stage line,
# byte-identical between the twin ports, so the script-pairs probe channel can
# compare them after timestamp@v1/whitespace@v1 normalization. No absolute
# path, timestamp, raw git output, or word count is ever printed; all foreign
# gate and git output is captured and mapped to PASS/FAIL/REJECT lines.
#
# Hermetic and concurrency-safe: every invocation owns a unique private
# transient root (adopt-plane.<guid> under the temp root) removed by the
# script-level finally; all transient files and the full run's internal
# scaffold live under it. No invocation ever removes an entry it did not
# create — concurrent suites (self-test and probe lanes run adopt-plane
# suites in parallel) cannot interfere with each other's scaffolds. The
# repository itself is never modified.
#
# The scaffold's copy of scripts/script-pairs.json is adjusted: the
# adopt-plane.test entry and the adopt-plane probe declaration are dropped,
# because adopt-plane.test.* are excluded from the scaffold by design — a
# probe without its test suites would fail the pair gate on foreign soil.
#
# The mutation battery injects each of four mutations, proves its gate
# rejects it, and reverts the injection:
#   pairing       append a line to README.zh.md without touching the sidecar
#                 -> verify-translation-pairing rejects (stage=pairing)
#   vocabulary    append a banned declaration-state word to docs/adoption.md
#                 -> verify-vocabulary rejects (stage=vocabulary); the edit
#                 also stales the pairing sidecar, which is what the
#                 pre-commit hook (no vocabulary verifier) rejects on
#   notes         add a malformed note under .agents/notes/
#                 -> verify-agent-notes rejects (stage=notes)
#   script-pairs  append a comment to a copied twin script without refreshing
#                 scripts/script-pairs.json
#                 -> verify-script-pairs rejects (stage=script-pairs)

param([string]$Scaffold = '', [string]$Verify = '', [switch]$Clean)

$ErrorActionPreference = 'Stop'
# Native-command stderr must never become a throwing error record: gate and
# git output is captured, never raised (pinned for pwsh 7.3+).
$PSNativeCommandUseErrorActionPreference = $false
# git must never sit waiting on a credential prompt or an index lock: a
# hung child is a hung gate (the Windows CI timeout this guard exists for).
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_OPTIONAL_LOCKS = '0'

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# The temp root honors TMPDIR (used by the bash twin and by concurrent test
# suites to scope their instances); Windows hosts fall back to the OS temp.
$script:TempRoot = if ($env:TMPDIR) { $env:TMPDIR } else { [IO.Path]::GetTempPath() }

# Every invocation owns a unique private transient root; the script-level
# finally removes it (and everything under it) on every exit path. The root
# name is never printed — output stays byte-deterministic.
$script:PrivRoot = Join-Path $script:TempRoot ('adopt-plane.' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:PrivRoot -Force)

# One fixed output line (stdout). Errors go to stderr with the same prefix.
function Write-Say([string]$line) {
  Write-Output "adopt-plane: $line"
}

# Run $command with $arguments and cwd $dir, capturing combined output into
# $script:Captured and its status into $script:CapturedRc. Foreign output is
# never echoed. Every external invocation is guarded by a stage-named
# timeout: on expiry the whole process tree is killed (taskkill /T on
# Windows — descendant processes must not outlive their parent holding the
# output handles) and $script:TimedOutStage is set so the caller can report
# the stage FAIL with the captured output instead of hanging forever.
# Output is redirected to files, never pipes: a descendant that inherits a
# pipe handle would keep it open past the parent's exit, and the reader
# would wait for EOF forever (the Windows CI hang this guard exists for).
function Invoke-InDir([string]$dir, [string]$stage, [int]$timeoutSeconds, [string]$command, [string[]]$arguments) {
  if (-not $IsWindows) {
    # Fast path: direct invocation with pipe capture. The pipe-handle
    # inheritance hang this guard exists for is Windows-specific; the guarded
    # Start-Process path stays on Windows, where the CI hang was observed.
    Push-Location $dir
    try {
      $script:Captured = (@(& $command @arguments 2>&1) -join "`n")
      $script:CapturedRc = $LASTEXITCODE
      $script:TimedOutStage = $null
    } finally {
      Pop-Location
    }
    return
  }
  $outFile = Join-Path $script:PrivRoot ('out-' + $stage + '-' + [Guid]::NewGuid().ToString('N'))
  $errFile = "$outFile.err"
  $proc = Start-Process -FilePath $command -ArgumentList $arguments -WorkingDirectory $dir `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru -NoNewWindow
  $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
  $timedOut = $false
  while (-not $proc.HasExited) {
    if ([DateTime]::UtcNow -gt $deadline) { $timedOut = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if ($timedOut) {
    if ($IsWindows) {
      $null = & taskkill /PID $proc.Id /T /F 2>$null
    } else {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    $proc.WaitForExit()
    $script:Captured = "TIMEOUT after $timeoutSeconds s`n" +
      (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue) +
      (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
    $script:CapturedRc = 124
    $script:TimedOutStage = $stage
  } else {
    $script:Captured = (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue) +
      (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
    $script:CapturedRc = $proc.ExitCode
  }
  Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
}

# Timed invocation that reports the timeout as a stage FAIL and aborts the
# run (fail loud, never a silent hang).
function Invoke-Timed([string]$dir, [string]$stage, [int]$timeoutSeconds, [string]$command, [string[]]$arguments) {
  $script:TimedOutStage = $null
  Invoke-InDir $dir $stage $timeoutSeconds $command $arguments
  if ($script:TimedOutStage) {
    [Console]::Error.WriteLine("adopt-plane: FAIL stage=$stage (timeout after ${timeoutSeconds}s)")
    [Console]::Error.WriteLine($script:Captured)
    $script:VerifyRc = 1
    throw "adopt-plane: stage $stage timed out"
  }
}

# --- scaffold -----------------------------------------------------------------

function New-Scaffold([string]$dir) {
  $script:ScaffoldOk = $false
  # A refused dir is never touched: a caller's pre-existing content (a
  # non-empty dir, or a regular file) must not be removed by this script's
  # cleanup. The finally below removes only what the build itself created —
  # the dir was missing or empty when the build started.
  if (Test-Path -LiteralPath $dir -PathType Leaf) {
    [Console]::Error.WriteLine('adopt-plane: FAIL scaffold dir is not a directory')
    return
  }
  if (Test-Path -LiteralPath $dir) {
    $items = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
    if ($items.Count -gt 0) {
      [Console]::Error.WriteLine('adopt-plane: FAIL scaffold dir is not empty')
      return
    }
  }
  $keep = $false
  try {
    if (-not (Test-Path -LiteralPath $dir)) {
      [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    $archive = Join-Path $script:PrivRoot 'copy.tar'

    # Full-tree copy, excluding the source's own git, the proof's own test
    # files, and local editor state (.zcode — never part of a derivation).
    # bash and pwsh are both copied: the foreign project keeps its twin.
    # tar is provided by Git for Windows, GNU tar, and bsdtar alike.
    Invoke-InDir $dir 'scaffold-copy' 300 'tar' @('-C', $script:Root, '--exclude=.git', '--exclude=.zcode', '--exclude=adopt-plane.test.sh', '--exclude=adopt-plane.test.ps1', '-cf', $archive, '.')
    if ($script:TimedOutStage -or $script:CapturedRc -ne 0) { throw 'scaffold copy failed' }
    Invoke-InDir $dir 'scaffold-copy' 300 'tar' @('-C', $dir, '-xf', $archive)
    if ($script:TimedOutStage -or $script:CapturedRc -ne 0) { throw 'scaffold copy failed' }
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue

    # Recursive guard: the scaffold must never carry adopt-plane.test.*.
    $stray = @(Get-ChildItem -LiteralPath $dir -Recurse -Force -Filter 'adopt-plane.test.*' -ErrorAction SilentlyContinue)
    if ($stray.Count -gt 0) {
      throw 'scaffold contains adopt-plane.test.* (recursive guard)'
    }

    # Provenance marker: the only evidence -Verify accepts. A dir without it
    # is never verified for removal — the repo root and any other lookalike
    # cannot be destroyed by a mistyped -Verify.
    [IO.File]::WriteAllText((Join-Path $dir '.adopt-plane-provenance'), "adopt-plane scaffold`n", (New-Object System.Text.UTF8Encoding($false)))

    # Drop the adopt-plane.test entry plus the adopt-plane probe and heavy
    # marks from the copied manifest: the excluded test files are their only
    # referents.
    # Dropping the probe line (the entry's last field) also strips the
    # dangling comma it leaves on the preceding line.
    $manifest = Join-Path $dir 'scripts/script-pairs.json'
    if (Test-Path -LiteralPath $manifest) {
      $lines = ([IO.File]::ReadAllText($manifest)) -split "`n"
      $out = New-Object System.Collections.Generic.List[string]
      $inTest = $false
      $inPlane = $false
      foreach ($line in $lines) {
        if ($line -ceq '  "adopt-plane.test": {') { $inTest = $true; continue }
        if ($inTest) {
          if ($line -ceq '  },' -or $line -ceq '  }') { $inTest = $false }
          continue
        }
        if ($line -ceq '  "adopt-plane": {') { $inPlane = $true }
        if ($inPlane -and ($line -ceq '  },' -or $line -ceq '  }')) { $inPlane = $false }
        if ($inPlane -and ($line -match '^    "probe": ' -or $line -match '^    "heavy": ')) {
          if ($out[$out.Count - 1].EndsWith(',')) {
            $out[$out.Count - 1] = $out[$out.Count - 1].Substring(0, $out[$out.Count - 1].Length - 1)
          }
          continue
        }
        [void]$out.Add($line)
      }
      [IO.File]::WriteAllText($manifest, ($out -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Say 'scaffold files copied'

    Invoke-InDir $dir 'scaffold-git' 300 'git' @('init', '-q', '--initial-branch=main')
    if ($script:TimedOutStage -or $script:CapturedRc -ne 0) { throw 'scaffold git init failed' }
    Invoke-InDir $dir 'scaffold-git' 300 'git' @('config', 'user.name', 'adopt-plane-proof')
    if ($script:TimedOutStage -or $script:CapturedRc -ne 0) { throw 'scaffold git init failed' }
    Invoke-InDir $dir 'scaffold-git' 300 'git' @('config', 'user.email', 'adopt-plane-proof@example.invalid')
    if ($script:TimedOutStage -or $script:CapturedRc -ne 0) { throw 'scaffold git init failed' }
    Write-Say 'scaffold git initialized'

    $script:ScaffoldOk = $true
    $keep = $true
  } catch {
    [Console]::Error.WriteLine("adopt-plane: FAIL $($_.Exception.Message)")
  } finally {
    if (-not $keep -and (Test-Path -LiteralPath $dir)) {
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

# --- mutation battery -----------------------------------------------------------
# Each stage: if the dir's own state already trips the stage's gate, the
# rejection is reported without injecting (a pre-injected mutation from a
# caller must be attributable to its stage); otherwise the mutation is
# injected, the gate must reject it, and the injection is reverted.

function Invoke-MutationPairing([string]$dir) {
  [IO.File]::AppendAllText((Join-Path $dir 'README.zh.md'), "`nadopt-plane: pairing mutation`n")
}
function Invoke-MutationVocabulary([string]$dir) {
  [IO.File]::AppendAllText((Join-Path $dir 'docs/adoption.md'), "`nThis statement is verified by nothing.`n")
}
function Invoke-MutationNotes([string]$dir) {
  [IO.File]::WriteAllText((Join-Path $dir '.agents/notes/implemented/architecture/2026-08-19-mutation-note.md'), "garbage`n", (New-Object System.Text.UTF8Encoding($false)))
}
function Invoke-MutationScriptPairs([string]$dir) {
  [IO.File]::AppendAllText((Join-Path $dir 'scripts/adopt-plane.sh'), "`n# adopt-plane: drift mutation`n")
}

# Restore one path to its committed state: unstage, then restore from HEAD
# when the path is tracked, remove it when it is not (an injected new file).
# All git output is suppressed — foreign output never reaches our stdout.
function Restore-Path([string]$dir, [string]$path) {
  Invoke-InDir $dir 'revert' 120 'git' @('reset', '-q', '--', $path)
  if ($script:TimedOutStage) { throw 'revert timed out' }
  Invoke-InDir $dir 'revert' 120 'git' @('cat-file', '-e', "HEAD:$path")
  if ($script:TimedOutStage) { throw 'revert timed out' }
  if ($script:CapturedRc -eq 0) {
    Invoke-InDir $dir 'revert' 120 'git' @('checkout', 'HEAD', '--', $path)
    if ($script:TimedOutStage) { throw 'revert timed out' }
  } else {
    Remove-Item -LiteralPath (Join-Path $dir $path) -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-RevertPairing([string]$dir) { Restore-Path $dir 'README.zh.md' }
function Invoke-RevertVocabulary([string]$dir) { Restore-Path $dir 'docs/adoption.md' }
function Invoke-RevertNotes([string]$dir) {
  Remove-Item -LiteralPath (Join-Path $dir '.agents/notes/implemented/architecture/2026-08-19-mutation-note.md') -Force -ErrorAction SilentlyContinue
}
function Invoke-RevertScriptPairs([string]$dir) { Restore-Path $dir 'scripts/adopt-plane.sh' }

# One battery stage: <dir> <stage> <gate-script> <inject-fn> <revert-fn>
# <commit-test 0|1>. The commit test proves the installed pre-commit rejects
# the mutation with a real `git commit`.
function Invoke-BatteryStage([string]$dir, [string]$stage, [string]$gate, [string]$inject, [string]$revert, [int]$commitTest) {
  Invoke-Timed $dir "gate-$stage" 900 'pwsh' @('-NoProfile', '-File', "scripts/$gate")
  $pre = $script:CapturedRc
  if ($pre -eq 0) {
    & $inject $dir
    Invoke-Timed $dir "gate-$stage" 900 'pwsh' @('-NoProfile', '-File', "scripts/$gate")
    if ($script:CapturedRc -eq 0) {
      Write-Say "FAIL stage=$stage MISSED"
      $script:BatteryFailed = 1
    } else {
      Write-Say "FAIL stage=$stage"
    }
  } else {
    Write-Say "FAIL stage=$stage"
  }
  if ($commitTest -eq 1) {
    Invoke-Timed $dir 'git-add' 300 'git' @('--no-optional-locks', 'add', '-A')
    Invoke-Timed $dir 'commit' 600 'git' @('--no-optional-locks', '-c', 'commit.gpgsign=false', 'commit', '-m', 'adopt-plane-rejected-commit')
    if ($script:CapturedRc -eq 0) {
      Write-Say "pre-commit MISSED stage=$stage"
      $script:BatteryFailed = 1
    } else {
      Write-Say 'pre-commit REJECT'
    }
  }
  if ($pre -eq 0) { & $revert $dir }
}

# --- verify --------------------------------------------------------------------

function Invoke-Verify([string]$dir) {
  # Only a dir that proves its provenance is accepted — and only then is it
  # removed. A repo root or any other lookalike (a git repo with the plane's
  # scripts is not a scaffold) is rejected and never touched: the marker is
  # written by -Scaffold and its content is fixed.
  $markerPath = Join-Path $dir '.adopt-plane-provenance'
  $proven = $false
  if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
    $marker = [IO.File]::ReadAllText($markerPath).TrimEnd("`n", "`r")
    if ($marker -ceq 'adopt-plane scaffold') { $proven = $true }
  }
  if (-not $proven -or
      -not (Test-Path -LiteralPath (Join-Path $dir '.git')) -or
      -not (Test-Path -LiteralPath (Join-Path $dir 'scripts/adopt-plane.sh')) -or
      -not (Test-Path -LiteralPath (Join-Path $dir 'scripts/gates.sh'))) {
    [Console]::Error.WriteLine('adopt-plane: FAIL not an adopt-plane scaffold (missing provenance marker; nothing was removed)')
    $script:VerifyRc = 1
    return
  }
  $failed = 0
  $gateAllOk = 0
  try {
    # The plane's gate-invisible load-bearing files must survive the copy: no
    # gate scans .gitattributes or .gitignore, so their loss is only visible
    # here.
    if (-not (Test-Path -LiteralPath (Join-Path $dir '.gitattributes'))) {
      Write-Say 'FAIL plane-file .gitattributes'
      $failed = 1
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dir '.gitignore'))) {
      Write-Say 'FAIL plane-file .gitignore'
      $failed = 1
    }
    # (a) zero-install green: gates all on the foreign soil.
    Invoke-Timed $dir 'gate-all' 900 'pwsh' @('-NoProfile', '-File', 'scripts/gates.ps1', '-Mode', 'all')
    if ($script:CapturedRc -eq 0) {
      Write-Say 'gate all PASS'
      $gateAllOk = 1
    } else {
      Write-Say 'gate all FAIL'
      $failed = 1
    }

    # (b) hook install and one real commit through the installed pre-commit.
    Invoke-Timed $dir 'install-hooks' 300 'sh' @('scripts/install-hooks.sh')
    if ($script:CapturedRc -eq 0) {
      Write-Say 'install-hooks PASS'
    } else {
      Write-Say 'install-hooks FAIL'
      $failed = 1
    }
    Invoke-Timed $dir 'git-add' 300 'git' @('--no-optional-locks', 'add', '-A')
    if ($script:CapturedRc -ne 0) {
      Write-Say 'pre-commit FAIL'
      $failed = 1
    } else {
      Invoke-Timed $dir 'commit' 600 'git' @('--no-optional-locks', '-c', 'commit.gpgsign=false', 'commit', '-m', 'adopt-plane-proof-commit')
      if ($script:CapturedRc -eq 0) {
        Write-Say 'pre-commit PASS'
      } else {
        Write-Say 'pre-commit REJECT'
        # A pristine tree whose commit is rejected is a broken proof; a broken
        # tree's rejection is the proof working (the dir-state verdict is FAIL).
        if ($gateAllOk -eq 1) { $failed = 1 }
      }
    }

    # (c) the mutation battery: every stage must reject, naming the stage;
    # the pairing and vocabulary mutations must also be rejected by
    # pre-commit.
    $script:BatteryFailed = 0
    Invoke-BatteryStage $dir 'pairing' 'verify-translation-pairing.ps1' 'Invoke-MutationPairing' 'Invoke-RevertPairing' 1
    Invoke-BatteryStage $dir 'vocabulary' 'verify-vocabulary.ps1' 'Invoke-MutationVocabulary' 'Invoke-RevertVocabulary' 1
    Invoke-BatteryStage $dir 'notes' 'verify-agent-notes.ps1' 'Invoke-MutationNotes' 'Invoke-RevertNotes' 0
    Invoke-BatteryStage $dir 'script-pairs' 'verify-script-pairs.ps1' 'Invoke-MutationScriptPairs' 'Invoke-RevertScriptPairs' 0

    if ($failed -eq 0 -and $script:BatteryFailed -eq 0) {
      Write-Say 'PASS'
      $script:VerifyRc = 0
    } else {
      Write-Say 'FAIL'
      $script:VerifyRc = 1
    }
  } finally {
    if (Test-Path -LiteralPath $dir) {
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

# --- CLI ------------------------------------------------------------------------

$script:Mode = 'run'
if ($Clean -and [string]::IsNullOrEmpty($Scaffold) -and [string]::IsNullOrEmpty($Verify)) { $script:Mode = 'clean' }
if (-not [string]::IsNullOrEmpty($Scaffold)) { $script:Mode = 'scaffold' }
if (-not [string]::IsNullOrEmpty($Verify)) { $script:Mode = 'verify' }

try {
  switch ($script:Mode) {
    'run' {
      # The full run's scaffold lives under this instance's private root.
      $dir = Join-Path $script:PrivRoot 'scaffold'
      New-Scaffold $dir
      if (-not $script:ScaffoldOk) { exit 1 }
      Invoke-Verify $dir
      exit $script:VerifyRc
    }
    'scaffold' {
      # A refused dir is left exactly as found: the finally below removes
      # only what the build created.
      New-Scaffold $Scaffold
      if (-not $script:ScaffoldOk) { exit 1 }
      exit 0
    }
    'verify' {
      Invoke-Verify $Verify
      exit $script:VerifyRc
    }
    'clean' {
      # Instance-scoped: this invocation's own transient root is removed by
      # the finally below; a foreign instance's root — including a live
      # concurrent suite's scaffold — is never touched.
      Write-Say 'clean done'
      exit 0
    }
  }
} finally {
  if (Test-Path -LiteralPath $script:PrivRoot) {
    Remove-Item -LiteralPath $script:PrivRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
