#!/bin/sh
# Install local git hooks and the pairing merge driver. Run once per clone:
#   sh scripts/install-hooks.sh
# Hooks stay fast: pre-commit runs the staged-relevant checks in seconds;
# CI owns the exhaustive matrix (bash + pwsh ports). Hooks run under git's
# bundled sh and invoke the bash port of the governance scripts; the pwsh
# twins are equivalent and run in CI. The pair gate's behavioral probes run
# both shells, so pre-commit needs pwsh on PATH for probed pairs. Re-run
# after moving the repository, because the merge driver path is baked in
# absolute form.

set -e
root=$(cd "$(dirname "$0")/.." && pwd)
hooks="$root/.git/hooks"

cat > "$hooks/pre-commit" <<EOF
#!/bin/sh
# Fast local checkpoint; exhaustive checks belong to CI.
cd "$root"
git diff --cached --check || exit 1
bash scripts/verify-agent-notes.sh || exit 1
bash scripts/verify-translation-pairing.sh || exit 1
bash scripts/verify-script-pairs.sh || exit 1
EOF
chmod +x "$hooks/pre-commit"

cat > "$hooks/pre-push" <<EOF
#!/bin/sh
cd "$root"
bash scripts/gates.sh --mode quick
EOF
chmod +x "$hooks/pre-push"

git config merge.agent-dev-pairing.driver "bash $root/scripts/translation-pairing-merge.sh %O %A %B"

echo "installed: pre-commit, pre-push, merge driver agent-dev-pairing"
