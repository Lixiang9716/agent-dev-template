#!/bin/sh
# Install local git hooks and the pairing merge driver. Run once per clone:
#   sh scripts/install-hooks.sh
# Hooks stay fast: pre-commit runs the staged-relevant checks in seconds;
# CI owns the exhaustive matrix. Re-run after moving the repository, because
# the merge driver path is baked in absolute form.

set -e
root=$(cd "$(dirname "$0")/.." && pwd)
hooks="$root/.git/hooks"

cat > "$hooks/pre-commit" <<EOF
#!/bin/sh
# Fast local checkpoint; exhaustive checks belong to CI.
cd "$root"
git diff --cached --check || exit 1
node scripts/verify-agent-notes.mjs || exit 1
node scripts/verify-translation-pairing.mjs || exit 1
EOF
chmod +x "$hooks/pre-commit"

cat > "$hooks/pre-push" <<EOF
#!/bin/sh
cd "$root"
node scripts/gates.mjs --mode quick
EOF
chmod +x "$hooks/pre-push"

git config merge.agent-dev-pairing.driver "node $root/scripts/translation-pairing-merge.mjs %O %A %B"

echo "installed: pre-commit, pre-push, merge driver agent-dev-pairing"
