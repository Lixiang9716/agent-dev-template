#!/usr/bin/env bash
# CI workflow and local hook shape tests (bash twin of ci.test.ps1): the two
# gate matrices must carry all four OS/shell legs, the light job must skip
# the schedule and the heavy job must run only on it, the heavy heartbeat
# must fire every 12 hours, the heavy-channel detection must feed
# GATES_FORCE_HEAVY into the light gates step, the summary jobs must always
# run and treat a skipped job as a pass — a skipped required check counts as
# passing on GitHub, so the guard is load-bearing — and install-hooks.sh must
# generate hooks that dispatch by interpreter, so a bash-only or pwsh-only
# host runs every local gate through its hooks. A guard only guards if the
# regression actually fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh

ci=$(cat .github/workflows/ci.yml)

expect_eq 'eight matrix legs total' "$(grep -cE '^[[:space:]]+- os: ' <<< "$ci")" 8
expect_eq 'two sh legs in the matrix' "$(grep -c 'shell: sh$' <<< "$ci")" 2
# The matrix indents shell keys deeper (12 spaces) than the step-level
# `shell: pwsh` directive (8 spaces); the depth split keeps the counts honest.
expect_eq 'six pwsh legs in the matrix' "$(grep -cE '^ {10,}shell: pwsh$' <<< "$ci")" 6
expect_contains 'ubuntu leg present' "$ci" 'os: ubuntu-latest'
expect_contains 'macos leg present' "$ci" 'os: macos-latest'
expect_contains 'windows leg present' "$ci" 'os: windows-latest'
expect_contains 'light and heavy jobs run the bash twin' "$ci" 'bash scripts/gates.sh --mode all'
expect_contains 'light and heavy jobs run the pwsh twin' "$ci" 'pwsh -File scripts/gates.ps1 -Mode all'
expect_contains 'every leg forces the probe lane' "$ci" "GATES_FORCE_PROBE: '1'"
expect_contains 'the heavy job forces the heavy lane' "$ci" "GATES_FORCE_HEAVY: '1'"
expect_contains 'the light job skips the schedule' "$ci" "if: github.event_name != 'schedule'"
expect_contains 'the heavy job runs only on the schedule' "$ci" "if: github.event_name == 'schedule'"
expect_contains 'the light summary depends on gates' "$ci" 'needs: [gates]'
expect_contains 'the heavy summary depends on gates-heavy' "$ci" 'needs: [gates-heavy]'
expect_contains 'summaries always run' "$ci" 'if: always()'
expect_contains 'summaries treat a skipped job as a pass' "$ci" '!= "failure"'
expect_contains 'heavy heartbeat runs every 12 hours' "$ci" "cron: '17 */12 * * *'"
expect_contains 'heavy-channel detection is wired' "$ci" 'Detect heavy-channel changes'
expect_contains 'heavy-channel detection writes GATES_FORCE_HEAVY via GITHUB_ENV' "$ci" 'echo "GATES_FORCE_HEAVY=1" >> "$GITHUB_ENV"'
expect_eq 'the gates steps never consume heavy-detect step outputs' "$(grep -c 'steps.heavy-detect.outputs' <<< "$ci")" 0

# install-hooks.sh generates hooks that dispatch by interpreter: bash when
# available, the pwsh twin otherwise — either interpreter alone runs every
# local gate through its hooks.
hooks=$(cat scripts/install-hooks.sh)
expect_contains 'hooks prefer bash when available' "$hooks" 'command -v bash'
expect_contains 'pre-commit falls back to the pwsh twin' "$hooks" 'pwsh -NoProfile -File scripts/verify-agent-notes.ps1'
expect_contains 'pre-push falls back to the pwsh twin' "$hooks" 'pwsh -NoProfile -File scripts/gates.ps1 -Mode quick'
expect_contains 'merge driver dispatches by interpreter' "$hooks" 'merge-driver.sh %O %A %B'

t_done
