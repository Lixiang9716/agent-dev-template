#!/usr/bin/env pwsh
# Merge driver for `.i18n.yaml` pairing sidecars (pwsh port; bash twin:
# translation-pairing-merge.sh), wired by install-hooks.sh as
#
#   git config merge.agent-dev-pairing.driver \
#     'pwsh <repo>/scripts/translation-pairing-merge.ps1 %O %A %B'
#
# Git invokes it with base, ours, theirs sidecar copies. The driver is
# deliberately conservative: when one side is unchanged from the base (the
# other side advanced alone — the common bilingual-edit race), take the
# advanced side and exit 0; otherwise leave a normal conflict. The verify
# gate still re-checks recorded hashes against both sides after the merge.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)

$ErrorActionPreference = 'Stop'

if ($Files.Count -ne 3) {
  [Console]::Error.WriteLine('translation-pairing-merge: expected %O %A %B from git')
  exit 1
}
$base = [IO.File]::ReadAllText($Files[0])
$ours = [IO.File]::ReadAllText($Files[1])
$theirs = [IO.File]::ReadAllText($Files[2])

if ($base -eq $ours -and $base -ne $theirs) {
  [IO.File]::WriteAllText($Files[1], $theirs)
  exit 0
}
if ($base -eq $theirs -and $base -ne $ours) { exit 0 }
if ($ours -eq $theirs) { exit 0 }

[Console]::Error.WriteLine('translation-pairing-merge: both sides advanced; resolve manually, then re-confirm with verify-translation-pairing.ps1 -Write')
exit 1
