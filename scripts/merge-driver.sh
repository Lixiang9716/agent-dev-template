#!/bin/sh
# Merge driver dispatcher (single-side, no twin — the installer wires it as
#   git config merge.agent-dev-pairing.driver 'sh <repo>/scripts/merge-driver.sh %O %A %B'
# and git executes the driver through sh). bash and pwsh are alternatives:
# the bash merge port runs when bash is on PATH, the pwsh twin otherwise,
# so a bash-only or pwsh-only host gets a working driver. Only sh builtins
# and `command -v` are used, so a minimal PATH cannot break the dispatch.

case $0 in
  */*) d=${0%/*} ;;
  *) d=. ;;
esac
root=$(CDPATH= cd -- "$d/.." && pwd)
if command -v bash >/dev/null 2>&1; then
  exec bash "$root/scripts/translation-pairing-merge.sh" "$@"
else
  exec pwsh -NoProfile -File "$root/scripts/translation-pairing-merge.ps1" "$@"
fi
