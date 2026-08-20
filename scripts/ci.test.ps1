#!/usr/bin/env pwsh
# CI workflow and local hook shape tests (pwsh twin of ci.test.sh): the two
# gate matrices must carry all four OS/shell legs, the light job must skip
# the schedule and the heavy job must run only on it, the heavy heartbeat
# must fire every 12 hours, the heavy-channel detection must feed
# GATES_FORCE_HEAVY into the light gates step, the summary jobs must always
# run and treat a skipped job as a pass — a skipped required check counts as
# passing on GitHub, so the guard is load-bearing — and install-hooks.sh must
# generate hooks that dispatch by interpreter, so a bash-only or pwsh-only
# host runs every local gate through its hooks. A guard only guards if the
# regression actually fails it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$ci = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../.github/workflows/ci.yml') -Raw

Expect-Eq 'eight matrix legs total' @(([regex]::Matches($ci, '(?m)^\s+- os: '))).Count 8
Expect-Eq 'two sh legs in the matrix' @(([regex]::Matches($ci, '(?m)shell: sh$'))).Count 2
# The matrix indents shell keys deeper (12 spaces) than the step-level
# `shell: pwsh` directive (8 spaces); the depth split keeps the counts honest.
Expect-Eq 'six pwsh legs in the matrix' @(([regex]::Matches($ci, '(?m)^ {10,}shell: pwsh$'))).Count 6
Expect-Contains 'ubuntu leg present' $ci 'os: ubuntu-latest'
Expect-Contains 'macos leg present' $ci 'os: macos-latest'
Expect-Contains 'windows leg present' $ci 'os: windows-latest'
Expect-Contains 'light and heavy jobs run the bash twin' $ci 'bash scripts/gates.sh --mode all'
Expect-Contains 'light and heavy jobs run the pwsh twin' $ci 'pwsh -File scripts/gates.ps1 -Mode all'
Expect-Contains 'every leg forces the probe lane' $ci "GATES_FORCE_PROBE: '1'"
Expect-Contains 'the heavy job forces the heavy lane' $ci "GATES_FORCE_HEAVY: '1'"
Expect-Contains 'the light job skips the schedule' $ci "if: github.event_name != 'schedule'"
Expect-Contains 'the heavy job runs only on the schedule' $ci "if: github.event_name == 'schedule'"
Expect-Contains 'the light summary depends on gates' $ci 'needs: [gates]'
Expect-Contains 'the heavy summary depends on gates-heavy' $ci 'needs: [gates-heavy]'
Expect-Contains 'summaries always run' $ci 'if: always()'
Expect-Contains 'summaries treat a skipped job as a pass' $ci '!= "failure"'
Expect-Contains 'heavy heartbeat runs every 12 hours' $ci "cron: '17 */12 * * *'"
Expect-Contains 'heavy-channel detection is wired' $ci 'Detect heavy-channel changes'
Expect-Contains 'heavy-channel detection writes GATES_FORCE_HEAVY via GITHUB_ENV' $ci 'echo "GATES_FORCE_HEAVY=1" >> "$GITHUB_ENV"'
Expect-Eq 'the gates steps never consume heavy-detect step outputs' @(([regex]::Matches($ci, 'steps.heavy-detect.outputs'))).Count 0

# install-hooks.sh generates hooks that dispatch by interpreter: bash when
# available, the pwsh twin otherwise — either interpreter alone runs every
# local gate through its hooks.
$hooks = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'install-hooks.sh') -Raw
Expect-Contains 'hooks prefer bash when available' $hooks 'command -v bash'
Expect-Contains 'pre-commit falls back to the pwsh twin' $hooks 'pwsh -NoProfile -File scripts/verify-agent-notes.ps1'
Expect-Contains 'pre-push falls back to the pwsh twin' $hooks 'pwsh -NoProfile -File scripts/gates.ps1 -Mode quick'
Expect-Contains 'merge driver dispatches by interpreter' $hooks 'merge-driver.sh %O %A %B'

Complete-TestSuite
