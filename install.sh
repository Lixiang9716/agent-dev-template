#!/bin/sh
# Scaffold a new project from agent-dev-template in one line:
#   curl -fsSL https://raw.githubusercontent.com/Lixiang9716/agent-dev-template/master/install.sh | sh -s -- my-project
#
# Downloads the template tarball (the latest release by default;
# AGENT_DEV_REF pins a tag or commit sha, AGENT_DEV_REPO redirects to a
# fork), extracts it into <dir> (default my-project), starts a fresh git
# history, and verifies the gates when a supported shell exists. Fail loud:
# any error aborts the scaffold with the offending step.
set -eu

REPO=${AGENT_DEV_REPO:-Lixiang9716/agent-dev-template}
TARGET=${1:-my-project}

fail() { echo "install: $1" >&2; exit 1; }

[ -e "$TARGET" ] && fail "target directory '$TARGET' already exists — pick a fresh name"

fetcher=''
if command -v curl >/dev/null 2>&1; then fetcher=curl
elif command -v wget >/dev/null 2>&1; then fetcher=wget
else fail 'need curl or wget to download the template'
fi

tmp=$(mktemp -d) || fail 'cannot create a temp directory'
trap 'rm -rf "$tmp"' EXIT INT TERM

REF=${AGENT_DEV_REF:-}
if [ -z "$REF" ]; then
  api="https://api.github.com/repos/$REPO/releases/latest"
  if [ "$fetcher" = curl ]; then
    REF=$(curl -fsSL "$api" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1) \
      || fail 'cannot query the latest release — set AGENT_DEV_REF to a tag or sha'
  else
    REF=$(wget -qO- "$api" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1) \
      || fail 'cannot query the latest release — set AGENT_DEV_REF to a tag or sha'
  fi
  [ -n "$REF" ] || fail 'no published release found — set AGENT_DEV_REF to a tag or sha'
fi

url="https://codeload.github.com/$REPO/tar.gz/$REF"
if [ "$fetcher" = curl ]; then
  curl -fsSL "$url" -o "$tmp/template.tar.gz" || fail "download of $REF failed"
else
  wget -qO "$tmp/template.tar.gz" "$url" || fail "download of $REF failed"
fi

mkdir "$TARGET" || fail "cannot create '$TARGET'"
tar -xzf "$tmp/template.tar.gz" -C "$TARGET" --strip-components=1 || fail 'extraction failed'

if command -v git >/dev/null 2>&1; then
  git -C "$TARGET" init -q || fail 'git init failed'
  git -C "$TARGET" add -A || fail 'git add failed'
else
  echo 'install: git not found — run "git init" yourself' >&2
fi

cd "$TARGET"
status='no bash 5+ or pwsh found — gates not run'
if command -v bash >/dev/null 2>&1 && bash -c 'test "${BASH_VERSINFO:-0}" && test "${BASH_VERSINFO[0]}" -ge 5' 2>/dev/null; then
  bash scripts/gates.sh --mode all || fail 'the bash gates failed on the fresh scaffold'
  status='gates green (bash)'
elif command -v pwsh >/dev/null 2>&1; then
  pwsh -File scripts/gates.ps1 -Mode all || fail 'the pwsh gates failed on the fresh scaffold'
  status='gates green (pwsh)'
fi

echo "install: scaffolded './$TARGET' at $REF ($status)"
echo "install: next: cd $TARGET && sh scripts/install-hooks.sh"
