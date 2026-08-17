#!/usr/bin/env bash
# Seal and verify the archived Agent Notes tree (bash port; pwsh twin:
# archive-agent-notes.ps1).
#
# Every archived note is content-addressed by sha256 in manifest.json. Check
# mode fails on: a sealed note whose content changed, a manifest entry with
# no file, or a new unsealed note (run --write to seal). --write only appends
# new hashes; it never rewrites or removes existing seals. After a triplet is
# sealed, never edit, move, or delete it.

LC_ALL=C
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

ARCHIVE_DIR=$ROOT/.agents/notes/archived
MANIFEST_PATH=$ARCHIVE_DIR/manifest.json

ARCHIVE_VIOLATIONS=()
archive_violation() { ARCHIVE_VIOLATIONS+=("$1"); }

# List archived note files as archive-relative paths, sorted.
archived_files() { # <archive-dir>
  local dir=$1 f
  while IFS= read -r f; do
    printf '%s\n' "${f#"$dir"/}"
  done < <(find "$dir" -type f -name '*.md' | sort)
}

# Read manifest.json into MANIFEST_KEYS (document order); a missing or
# unparseable manifest reads as empty — --write then seals everything.
read_manifest() {
  MANIFEST_KEYS=()
  declare -gA MANIFEST_SHA=()
  [[ -f $MANIFEST_PATH ]] || return 0
  local raw
  raw=$(<"$MANIFEST_PATH") || return 0
  json_parse "$raw" || return 0
  json_type '$.files' || return 0
  json_keys '$.files'
  local key
  MANIFEST_KEYS=("${REPLY_LIST[@]}")
  for key in "${MANIFEST_KEYS[@]}"; do
    if json_get "\$.files.$key.sha256"; then
      MANIFEST_SHA[$key]=$REPLY
    fi
  done
}

# Validate header shape: line 1 title, line 3 implemented status, line 4 the
# archive date, which must not predate the filename date.
check_header() { # <rel-path> <abs-path>
  local rel=$1 path=$2 lines name filename_date archived_date
  mapfile -t lines < "$path"
  [[ ${lines[0]-} == '# Agent Note: '* ]] \
    || archive_violation "$rel: line 1 must be \"# Agent Note: <title>\""
  [[ ${lines[2]-} == 'Status: implemented' ]] \
    || archive_violation "$rel: line 3 must be \"Status: implemented\" (archived notes were decisions that shipped)"
  name=${rel##*/}
  filename_date=${name:0:10}
  if ! [[ ${lines[3]-} =~ ^Archived:[[:space:]][0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    archive_violation "$rel: line 4 must be \"Archived: <date>\""
    return 0
  fi
  archived_date=${lines[3]#Archived: }
  [[ $archived_date < $filename_date ]] \
    && archive_violation "$rel: archived date $archived_date predates the filename date $filename_date"
}

# Verify or extend the seal. <mode> is check or write; returns an exit code.
archive_main() { # <mode>
  local mode=$1 files rel digest seal violations=0 mode_msg
  read_manifest
  files=$(archived_files "$ARCHIVE_DIR")

  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    check_header "$rel" "$ARCHIVE_DIR/$rel"
  done <<< "$files"

  local sealed_new=0
  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    sha256_of "$ARCHIVE_DIR/$rel" || return 1
    digest=$REPLY
    if [[ -z ${MANIFEST_SHA[$rel]+x} ]]; then
      if [[ $mode == write ]]; then
        MANIFEST_SHA[$rel]=$digest
        MANIFEST_KEYS+=("$rel")
        sealed_new=1
        echo "archive-agent-notes: sealed $rel"
      else
        archive_violation "$rel: not sealed; run \"bash scripts/archive-agent-notes.sh --write\" and commit the manifest"
      fi
    elif [[ ${MANIFEST_SHA[$rel]} != "$digest" ]]; then
      archive_violation "$rel: content changed after sealing; a sealed note is never edited — restore it or supersede it with a new note"
    fi
  done <<< "$files"

  for rel in "${MANIFEST_KEYS[@]}"; do
    grep -qx "$rel" <<< "$files" \
      || archive_violation "$rel: manifest entry has no file; seals are never removed"
  done

  if (( ${#ARCHIVE_VIOLATIONS[@]} > 0 )); then
    printf 'archive-agent-notes: %d violation(s):\n' "${#ARCHIVE_VIOLATIONS[@]}" >&2
    local v
    for v in "${ARCHIVE_VIOLATIONS[@]}"; do
      printf '  %s\n' "$v" >&2
    done
    return 1
  fi

  if [[ $mode == write && $sealed_new == 1 ]]; then
    {
      printf '{\n  "files": {\n'
      local i=0
      for rel in "${MANIFEST_KEYS[@]}"; do
        printf '    "%s": {\n      "sha256": "%s"\n    }' "$rel" "${MANIFEST_SHA[$rel]}"
        (( ++i < ${#MANIFEST_KEYS[@]} )) && printf ',' || true
        printf '\n'
      done
      printf '  }\n}\n'
    } > "$MANIFEST_PATH"
  fi
  echo 'archive-agent-notes: the archive is sealed and consistent.'
  return 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  [[ ${1:-} == --write ]] && archive_main write || archive_main check
fi
