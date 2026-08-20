#!/bin/sh
# Install local git hooks and the pairing merge driver. Run once per clone:
#   sh scripts/install-hooks.sh
# Hooks stay fast: pre-commit runs the staged-relevant checks in seconds;
# CI owns the exhaustive matrix (bash + pwsh ports). bash and pwsh are
# alternatives — each generated hook dispatches at run time: the bash port
# runs when bash is on PATH, the pwsh twin otherwise, so a bash-only or
# pwsh-only host gets every local gate through its hooks. The installer
# itself is POSIX sh: git executes hooks through sh on every platform, so sh
# is present wherever hooks can run. The pair gate's behavioral probes run
# when the cross interpreter is on PATH, are loudly skipped when it is not,
# and CI forces them (GATES_FORCE_PROBE=1). Re-run after moving the
# repository, because the merge driver path is baked in absolute form.

set -e
root=$(cd "$(dirname "$0")/.." && pwd)
hooks="$root/.git/hooks"

cat > "$hooks/pre-commit" <<EOF
#!/bin/sh
# Fast local checkpoint; exhaustive checks belong to CI. Either interpreter
# alone covers every local gate: bash when available, the pwsh twin otherwise.
cd "$root"
git diff --cached --check || exit 1
if command -v bash >/dev/null 2>&1; then
  bash scripts/verify-agent-notes.sh || exit 1
  bash scripts/verify-translation-pairing.sh || exit 1
  bash scripts/verify-script-pairs.sh || exit 1
else
  pwsh -NoProfile -File scripts/verify-agent-notes.ps1 || exit 1
  pwsh -NoProfile -File scripts/verify-translation-pairing.ps1 || exit 1
  pwsh -NoProfile -File scripts/verify-script-pairs.ps1 || exit 1
fi
EOF
chmod +x "$hooks/pre-commit"

cat > "$hooks/pre-push" <<EOF
#!/bin/sh
cd "$root"
if command -v bash >/dev/null 2>&1; then
  bash scripts/gates.sh --mode quick
else
  pwsh -NoProfile -File scripts/gates.ps1 -Mode quick
fi
EOF
chmod +x "$hooks/pre-push"

git config merge.agent-dev-pairing.driver "sh $root/scripts/merge-driver.sh %O %A %B"

echo "installed: pre-commit, pre-push, merge driver agent-dev-pairing"
