#!/usr/bin/env node
/**
 * Merge driver for `.i18n.yaml` pairing sidecars, wired by install-hooks.sh as
 *
 *   git config merge.agent-dev-pairing.driver \
 *     'node <repo>/scripts/translation-pairing-merge.mjs %O %A %B'
 *
 * Git invokes it with base, ours, theirs sidecar copies. The driver is
 * deliberately conservative: when one side is unchanged from the base (the
 * other side advanced alone — the common bilingual-edit race), take the
 * advanced side and exit 0; otherwise leave a normal conflict. The verify
 * gate still re-checks recorded hashes against both sides after the merge.
 */
import { readFileSync, writeFileSync } from 'node:fs'

/**
 * Driver entry: %O base, %A ours (result), %B theirs.
 * @param {string[]} args - three temp file paths from git.
 * @returns {number} 0 when auto-resolved (result written to %A), 1 to conflict.
 */
function main(args) {
  if (args.length !== 3) {
    console.error('translation-pairing-merge: expected %O %A %B from git')
    return 1
  }
  const [base, ours, theirs] = args.map(path => readFileSync(path, 'utf8'))
  const [, oursPath] = args
  if (base === ours && base !== theirs) {
    writeFileSync(oursPath, theirs)
    return 0
  }
  if (base === theirs && base !== ours) return 0
  if (ours === theirs) return 0
  console.error('translation-pairing-merge: both sides advanced; resolve manually, then re-confirm with verify-translation-pairing.mjs --write')
  return 1
}

process.exitCode = main(process.argv.slice(2))
