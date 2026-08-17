#!/usr/bin/env bash
# Merge driver for `.i18n.yaml` pairing sidecars (bash port; pwsh twin:
# translation-pairing-merge.ps1), wired by install-hooks.sh as
#
#   git config merge.agent-dev-pairing.driver \
#     'bash <repo>/scripts/translation-pairing-merge.sh %O %A %B'
#
# Git invokes it with base, ours, theirs sidecar copies. The driver is
# deliberately conservative: when one side is unchanged from the base (the
# other side advanced alone — the common bilingual-edit race), take the
# advanced side and exit 0; otherwise leave a normal conflict. The verify
# gate still re-checks recorded hashes against both sides after the merge.

set -u

merge_main() { # <base> <ours> <theirs>
  if (( $# != 3 )); then
    echo 'translation-pairing-merge: expected %O %A %B from git' >&2
    return 1
  fi
  local base ours theirs
  base=$(<"$1")
  ours=$(<"$2")
  theirs=$(<"$3")
  if [[ $base == "$ours" && $base != "$theirs" ]]; then
    printf '%s\n' "$theirs" > "$2"
    return 0
  fi
  if [[ $base == "$theirs" && $base != "$ours" ]]; then
    return 0
  fi
  if [[ $ours == "$theirs" ]]; then
    return 0
  fi
  echo 'translation-pairing-merge: both sides advanced; resolve manually, then re-confirm with verify-translation-pairing.sh --write' >&2
  return 1
}

if [[ ${BASH_SOURCE[0]:-$0} == "$0" ]]; then
  merge_main "$@"
fi
