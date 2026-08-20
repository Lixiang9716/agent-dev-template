#!/usr/bin/env bash
# CI workflow and local hook shape tests (bash twin of ci.test.ps1): the
# gate matrix must carry all four OS/shell legs, the summary job must always
# run — a skipped required check counts as passing on GitHub, so its guard
# is load-bearing — and install-hooks.sh must generate hooks that dispatch
# by interpreter, so a bash-only or pwsh-only host runs every local gate
# through its hooks. A guard only guards if the regression actually fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh

ci=$(cat .github/workflows/ci.yml)

expect_eq 'four matrix legs total' "$(grep -cE '^[[:space:]]+- os: ' <<< "$ci")" 4
expect_eq 'one sh leg in the matrix' "$(grep -c 'shell: sh$' <<< "$ci")" 1
# The matrix indents shell keys deeper (12 spaces) than the step-level
# `shell: pwsh` directive (8 spaces); the depth split keeps the counts honest.
expect_eq 'three pwsh legs in the matrix' "$(grep -cE '^ {10,}shell: pwsh$' <<< "$ci")" 3
expect_contains 'ubuntu leg present' "$ci" 'os: ubuntu-latest'
expect_contains 'macos leg present' "$ci" 'os: macos-latest'
expect_contains 'windows leg present' "$ci" 'os: windows-latest'
expect_contains 'gates job runs the bash twin' "$ci" 'bash scripts/gates.sh --mode all'
expect_contains 'gates job runs the pwsh twin' "$ci" 'pwsh -File scripts/gates.ps1 -Mode all'
expect_contains 'gates job forces the probe lane' "$ci" "GATES_FORCE_PROBE: '1'"
expect_contains 'summary depends on gates' "$ci" 'needs: [gates]'
expect_contains 'summary always runs' "$ci" 'if: always()'
expect_contains 'heartbeat schedule present' "$ci" "cron: '17 2 * * 0'"

# install-hooks.sh generates hooks that dispatch by interpreter: bash when
# available, the pwsh twin otherwise — either interpreter alone runs every
# local gate through its hooks.
hooks=$(cat scripts/install-hooks.sh)
expect_contains 'hooks prefer bash when available' "$hooks" 'command -v bash'
expect_contains 'pre-commit falls back to the pwsh twin' "$hooks" 'pwsh -NoProfile -File scripts/verify-agent-notes.ps1'
expect_contains 'pre-push falls back to the pwsh twin' "$hooks" 'pwsh -NoProfile -File scripts/gates.ps1 -Mode quick'
expect_contains 'merge driver dispatches by interpreter' "$hooks" 'merge-driver.sh %O %A %B'

t_done
