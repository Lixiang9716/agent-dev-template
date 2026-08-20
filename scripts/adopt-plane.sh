#!/usr/bin/env bash
# Prove the governance plane works on foreign soil (bash port; pwsh twin:
# adopt-plane.ps1). Simulates one real GitHub template derivation: the whole
# repository (minus .git, local editor state .zcode, and scripts/
# adopt-plane.test.* — the recursive guard re-checks the result) is copied
# into a fresh temporary directory, git is initialized with a local identity,
# and three facts are proven there:
#   (a) `bash scripts/gates.sh --mode all` is green with zero installation;
#   (b) `sh scripts/install-hooks.sh` installs, and a real `git commit`
#       passes the installed pre-commit;
#   (c) every injected mutation is rejected loudly by its gate and, for the
#       pairing and vocabulary mutations, by the pre-commit hook — each
#       naming its stage.
#
# Usage: adopt-plane.sh [--scaffold <dir>|--verify <dir>|--clean]
#   (no args)   full run: scaffold into an internal temp dir, verify, clean up
#   --scaffold <dir>  construct a scaffold only; <dir> is created when
#                     missing and must be empty otherwise; it is left in
#                     place. A refused dir (non-empty, or not a directory)
#                     is never touched.
#   --verify <dir>    verify a previously constructed scaffold, then remove
#                     <dir>; exits non-zero when the dir's own state is broken
#                     or a rejection was missed. Only a dir carrying this
#                     script's provenance marker (.adopt-plane-provenance,
#                     written by --scaffold) is accepted — anything else is
#                     rejected and never removed.
#   --clean     remove this instance's own transient root; foreign instances'
#               roots are never touched (concurrency safety)
#
# Output determinism (hard contract): every line is a fixed ASCII stage line,
# byte-identical between the twin ports, so the script-pairs probe channel can
# compare them after timestamp@v1/whitespace@v1 normalization. No absolute
# path, timestamp, raw git output, or word count is ever printed; all foreign
# gate and git output is captured and mapped to PASS/FAIL/REJECT lines.
#
# Hermetic and concurrency-safe: every invocation owns a unique private
# transient root (mktemp -d "$TMPROOT/adopt-plane.XXXXXX") removed by an EXIT
# trap; all transient files and the full run's internal scaffold live under
# it. No invocation ever removes an entry it did not create — concurrent
# suites (self-test and probe lanes run adopt-plane suites in parallel)
# cannot interfere with each other's scaffolds. The repository itself is
# never modified.
#
# The scaffold's copy of scripts/script-pairs.json is adjusted: the
# adopt-plane.test entry and the adopt-plane probe declaration are dropped,
# because adopt-plane.test.* are excluded from the scaffold by design — a
# probe without its test suites would fail the pair gate on foreign soil.
#
# The mutation battery injects each of four mutations, proves its gate
# rejects it, and reverts the injection:
#   pairing       append a line to README.zh.md without touching the sidecar
#                 -> verify-translation-pairing rejects (stage=pairing)
#   vocabulary    append a banned declaration-state word to docs/adoption.md
#                 -> verify-vocabulary rejects (stage=vocabulary); the edit
#                 also stales the pairing sidecar, which is what the
#                 pre-commit hook (no vocabulary verifier) rejects on
#   notes         add a malformed note under .agents/notes/
#                 -> verify-agent-notes rejects (stage=notes)
#   script-pairs  append a comment to a copied twin script without refreshing
#                 scripts/script-pairs.json
#                 -> verify-script-pairs rejects (stage=script-pairs)

LC_ALL=C
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMPROOT=${TMPDIR:-/tmp}

# Every invocation owns a unique private transient root; the EXIT trap
# removes it (and everything under it) on every exit path. The root name is
# never printed — output stays byte-deterministic.
PRIVROOT=$(mktemp -d "$TMPROOT/adopt-plane.XXXXXX") || { printf 'adopt-plane: FAIL cannot create temp root\n' >&2; exit 1; }
trap 'rm -rf "$PRIVROOT"' EXIT

# One fixed output line (stdout). Errors go to stderr with the same prefix.
say() { printf 'adopt-plane: %s\n' "$1"; }

# Run $@ with cwd $1, capturing combined output into CAPTURED and its status
# into CAPTURED_RC. Foreign output is never echoed.
capture_in_dir() { # <dir> <cmd...>
  local dir=$1; shift
  CAPTURED=$( ( cd "$dir" && "$@" ) 2>&1 )
  CAPTURED_RC=$?
}

# --- scaffold ----------------------------------------------------------------

scaffold() { # <dir>
  local dir=$1
  # A refused dir is never touched: a caller's pre-existing content (a
  # non-empty dir, or a regular file) must not be removed by this script's
  # cleanup. The subshell's EXIT trap below removes only what the build
  # itself created — the dir was missing or empty when the build started.
  if [[ -e $dir && ! -d $dir ]]; then
    printf 'adopt-plane: FAIL scaffold dir is not a directory\n' >&2
    return 1
  fi
  if [[ -e $dir ]] && [[ -n $(find "$dir" -mindepth 1 2>/dev/null) ]]; then
    printf 'adopt-plane: FAIL scaffold dir is not empty\n' >&2
    return 1
  fi
  # The build runs in a subshell whose EXIT trap removes the partial scaffold
  # on any failure and keeps it only when KEEP is set on success.
  (
    trap '[[ ${KEEP:-0} == 1 ]] || rm -rf "$dir"' EXIT
    scaffold_fail() { printf 'adopt-plane: FAIL %s\n' "$2" >&2; exit 1; }
    mkdir -p "$dir" 2>/dev/null || scaffold_fail "$dir" 'cannot create scaffold dir'
    archive="$PRIVROOT/copy.tar" stray='' manifest=''

    # Full-tree copy, excluding the source's own git, the proof's own test
    # files, and local editor state (.zcode — never part of a derivation).
    # bash and pwsh are both copied: the foreign project keeps its twin.
    if ! tar -C "$ROOT" --exclude=.git --exclude=.zcode \
         --exclude=adopt-plane.test.sh --exclude=adopt-plane.test.ps1 \
         -cf "$archive" . 2>/dev/null \
       || ! tar -C "$dir" -xf "$archive" 2>/dev/null; then
      rm -f "$archive"
      scaffold_fail "$dir" 'scaffold copy failed'
    fi
    rm -f "$archive"

    # Recursive guard: the scaffold must never carry adopt-plane.test.*.
    stray=$(find "$dir" -name 'adopt-plane.test.*' 2>/dev/null)
    if [[ -n $stray ]]; then
      scaffold_fail "$dir" 'scaffold contains adopt-plane.test.* (recursive guard)'
    fi

    # Provenance marker: the only evidence --verify accepts. A dir without
    # it is never verified for removal — the repo root and any other
    # lookalike cannot be destroyed by a mistyped --verify.
    printf 'adopt-plane scaffold\n' > "$dir/.adopt-plane-provenance" \
      || scaffold_fail "$dir" 'cannot write provenance marker'

    # Drop the adopt-plane.test entry and the adopt-plane probe from the
    # copied manifest: the excluded test files are their only referents.
    # One line is buffered so that dropping the probe line (the entry's last
    # field) can also strip the dangling comma it leaves behind.
    manifest=$dir/scripts/script-pairs.json
    if [[ -f $manifest ]]; then
      if ! awk '
        $0 == "  \"adopt-plane.test\": {" { in_test = 1; next }
        in_test && ($0 == "  }," || $0 == "  }") { in_test = 0; next }
        in_test { next }
        $0 == "  \"adopt-plane\": {" { in_plane = 1 }
        in_plane && ($0 == "  }," || $0 == "  }") { in_plane = 0 }
        in_plane && $0 ~ /^    "probe": / {
          if (pending ~ /,$/) pending = substr(pending, 1, length(pending) - 1)
          next
        }
        { if (pending != "") print pending; pending = $0 }
        END { if (pending != "") print pending }
      ' "$manifest" > "$manifest.tmp"; then
        rm -f "$manifest.tmp"
        scaffold_fail "$dir" 'scaffold manifest fix failed'
      fi
      mv "$manifest.tmp" "$manifest"
    fi
    say 'scaffold files copied'

    if ! git -C "$dir" init -q --initial-branch=main 2>/dev/null \
       || ! git -C "$dir" config user.name 'adopt-plane proof' 2>/dev/null \
       || ! git -C "$dir" config user.email 'adopt-plane-proof@example.invalid' 2>/dev/null; then
      scaffold_fail "$dir" 'scaffold git init failed'
    fi
    say 'scaffold git initialized'
    KEEP=1
    exit 0
  )
}

# --- mutation battery ----------------------------------------------------------
# Each stage: if the dir's own state already trips the stage's gate, the
# rejection is reported without injecting (a pre-injected mutation from a
# caller must be attributable to its stage); otherwise the mutation is
# injected, the gate must reject it, and the injection is reverted.

mutation_pairing() { printf '\nadopt-plane: pairing mutation\n' >> "$1/README.zh.md"; }
mutation_vocabulary() { printf '\nThis statement is verified by nothing.\n' >> "$1/docs/adoption.md"; }
mutation_notes() { printf 'garbage\n' > "$1/.agents/notes/implemented/architecture/2026-08-19-mutation-note.md"; }
mutation_script_pairs() { printf '\n# adopt-plane: drift mutation\n' >> "$1/scripts/adopt-plane.sh"; }

# Restore one path to its committed state: unstage, then restore from HEAD
# when the path is tracked, remove it when it is not (an injected new file).
# All git output is suppressed — foreign output never reaches our stdout.
revert_path() { # <dir> <path>
  git -C "$1" reset -q -- "$2" 2>/dev/null
  if git -C "$1" cat-file -e "HEAD:$2" 2>/dev/null; then
    git -C "$1" checkout HEAD -- "$2" 2>/dev/null
  else
    rm -f "$1/$2"
  fi
}

revert_pairing() { revert_path "$1" README.zh.md; }
revert_vocabulary() { revert_path "$1" docs/adoption.md; }
revert_notes() { rm -f "$1/.agents/notes/implemented/architecture/2026-08-19-mutation-note.md"; }
revert_script_pairs() { revert_path "$1" scripts/adopt-plane.sh; }

# One battery stage: <dir> <stage> <gate-script> <inject-fn> <revert-fn>
# <commit-test 0|1>. The commit test proves the installed pre-commit rejects
# the mutation with a real `git commit`.
battery_stage() { # <dir> <stage> <gate-script> <inject-fn> <revert-fn> <commit-test>
  local dir=$1 stage=$2 gate=$3 inject=$4 revert=$5 commit_test=$6 pre rc
  capture_in_dir "$dir" bash "scripts/$gate"
  pre=$CAPTURED_RC
  if (( pre == 0 )); then
    "$inject" "$dir"
    capture_in_dir "$dir" bash "scripts/$gate"
    rc=$CAPTURED_RC
    if (( rc == 0 )); then
      say "FAIL stage=$stage MISSED"
      BATTERY_FAILED=1
    else
      say "FAIL stage=$stage"
    fi
  else
    say "FAIL stage=$stage"
  fi
  if (( commit_test )); then
    capture_in_dir "$dir" git add -A
    capture_in_dir "$dir" git -c commit.gpgsign=false commit -m 'adopt-plane: rejected commit'
    if (( CAPTURED_RC == 0 )); then
      say "pre-commit MISSED stage=$stage"
      BATTERY_FAILED=1
    else
      say 'pre-commit REJECT'
    fi
  fi
  if (( pre == 0 )); then
    "$revert" "$dir"
  fi
  return 0
}

# --- verify --------------------------------------------------------------------

verify() { # <dir>
  local dir=$1 failed=0 gate_all_ok=0
  # Only a dir that proves its provenance is accepted — and only then is it
  # removed. A repo root or any other lookalike (a git repo with the plane's
  # scripts is not a scaffold) is rejected and never touched: the marker is
  # written by --scaffold and its content is fixed.
  if [[ ! -f $dir/.adopt-plane-provenance || $(<"$dir/.adopt-plane-provenance") != 'adopt-plane scaffold' \
    || ! -d $dir/.git || ! -f $dir/scripts/adopt-plane.sh || ! -f $dir/scripts/gates.sh ]]; then
    printf 'adopt-plane: FAIL not an adopt-plane scaffold (missing provenance marker; nothing was removed)\n' >&2
    return 1
  fi
  # The trap must reference script-level variables (a function-local would be
  # gone by the time the EXIT trap runs) and must not clobber the startup
  # trap: this instance's private root is removed here too, so no trap
  # overwrite ever leaks it.
  VERIFY_DIR=$dir
  trap 'rm -rf "$VERIFY_DIR" "$PRIVROOT"' EXIT

  # The plane's gate-invisible load-bearing files must survive the copy: no
  # gate scans .gitattributes or .gitignore, so their loss is only visible
  # here.
  if [[ ! -f $dir/.gitattributes ]]; then
    say 'FAIL plane-file .gitattributes'
    failed=1
  fi
  if [[ ! -f $dir/.gitignore ]]; then
    say 'FAIL plane-file .gitignore'
    failed=1
  fi

  # (a) zero-install green: gates all on the foreign soil.
  capture_in_dir "$dir" bash scripts/gates.sh --mode all
  if (( CAPTURED_RC == 0 )); then
    say 'gate all PASS'
    gate_all_ok=1
  else
    say 'gate all FAIL'
    failed=1
  fi

  # (b) hook install and one real commit through the installed pre-commit.
  capture_in_dir "$dir" sh scripts/install-hooks.sh
  if (( CAPTURED_RC == 0 )); then
    say 'install-hooks PASS'
  else
    say 'install-hooks FAIL'
    failed=1
  fi
  capture_in_dir "$dir" git add -A
  if (( CAPTURED_RC != 0 )); then
    say 'pre-commit FAIL'
    failed=1
  else
    capture_in_dir "$dir" git -c commit.gpgsign=false commit -m 'adopt-plane: proof commit'
    if (( CAPTURED_RC == 0 )); then
      say 'pre-commit PASS'
    else
      say 'pre-commit REJECT'
      # A pristine tree whose commit is rejected is a broken proof; a broken
      # tree's rejection is the proof working (the dir-state verdict is FAIL).
      (( gate_all_ok )) && failed=1
    fi
  fi

  # (c) the mutation battery: every stage must reject, naming the stage; the
  # pairing and vocabulary mutations must also be rejected by pre-commit.
  BATTERY_FAILED=0
  battery_stage "$dir" pairing verify-translation-pairing.sh mutation_pairing revert_pairing 1
  battery_stage "$dir" vocabulary verify-vocabulary.sh mutation_vocabulary revert_vocabulary 1
  battery_stage "$dir" notes verify-agent-notes.sh mutation_notes revert_notes 0
  battery_stage "$dir" script-pairs verify-script-pairs.sh mutation_script_pairs revert_script_pairs 0

  (( failed == 0 && BATTERY_FAILED == 0 )) || { say 'FAIL'; return 1; }
  say 'PASS'
  return 0
}

# --- CLI -----------------------------------------------------------------------

run_full() { # scaffold into an internal temp dir under this instance's root
  local dir rc
  dir="$PRIVROOT/scaffold"
  if ! scaffold "$dir"; then
    return 1
  fi
  verify "$dir"
  rc=$?
  return $rc
}

# Instance-scoped: this invocation's own transient root is removed by the
# EXIT trap; a foreign instance's root — including a live concurrent suite's
# scaffold — is never touched.
clean_leftovers() {
  say 'clean done'
  return 0
}

MODE=run DIR=''
while (( $# )); do
  case $1 in
    --scaffold)
      if (( $# < 2 )); then printf 'adopt-plane: --scaffold needs a directory argument\n' >&2; exit 2; fi
      MODE=scaffold; DIR=$2; shift 2 ;;
    --verify)
      if (( $# < 2 )); then printf 'adopt-plane: --verify needs a directory argument\n' >&2; exit 2; fi
      MODE=verify; DIR=$2; shift 2 ;;
    --clean)
      MODE=clean; shift ;;
    *)
      printf 'adopt-plane: unknown argument "%s"; only --scaffold <dir>, --verify <dir>, --clean are supported\n' "$1" >&2
      exit 2 ;;
  esac
done

case $MODE in
  run) run_full; exit $? ;;
  # A refused dir is left exactly as found: scaffold's own trap removes only
  # what the build created.
  scaffold) scaffold "$DIR"; exit $? ;;
  verify) verify "$DIR"; exit $? ;;
  clean) clean_leftovers ;;
esac
exit 0
