#!/usr/bin/env node
/**
 * Report the explicit scope of a repository change as stable JSON.
 *
 * Consumers (the pre-push-checks and code-review skills) use this output to
 * select the smallest sufficient check set for the outgoing diff instead of
 * reflexively running every gate. The base is never guessed and never
 * fetched: the caller passes a ref it has already verified.
 */
import { spawnSync } from 'node:child_process'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

/** Bumped whenever the output shape changes; consumers pin what they read. */
export const FORMAT_VERSION = 1

/**
 * Run one git command in `repoDir`, failing loud on any git error.
 * @param {string} repoDir - repository root to run in.
 * @param {string[]} args - git argv.
 * @returns {string} stdout with the trailing newline trimmed.
 */
function git(repoDir, args) {
  const result = spawnSync('git', ['-C', repoDir, ...args], { encoding: 'utf8' })
  if (result.error !== undefined) throw new Error(`change-scope: cannot run git: ${result.error.message}`)
  if (result.status !== 0) {
    const stderr = result.stderr.trim()
    throw new Error(`change-scope: git ${args.join(' ')} failed${stderr.length > 0 ? `: ${stderr}` : ''}`)
  }
  return result.stdout.replace(/\n$/, '')
}

/**
 * Collect the change scope of `base..head` plus the working tree.
 * @param {string} repoDir - repository root.
 * @param {string} base - already-verified base ref; never guessed here.
 * @param {string} [head] - head ref; defaults to HEAD.
 * @returns {object} versioned scope record.
 */
export function collectScope(repoDir, base, head = 'HEAD') {
  const baseSha = git(repoDir, ['rev-parse', '--verify', `${base}^{commit}`])
  const headSha = git(repoDir, ['rev-parse', '--verify', `${head}^{commit}`])
  const mergeBaseSha = git(repoDir, ['merge-base', baseSha, headSha])
  const listed = (args) => {
    const out = git(repoDir, args)
    return out.length === 0 ? [] : out.split('\n').sort()
  }
  return {
    formatVersion: FORMAT_VERSION,
    base,
    baseSha,
    head,
    headSha,
    mergeBaseSha,
    committed: listed(['diff', '--name-only', mergeBaseSha, headSha]),
    staged: listed(['diff', '--name-only', '--cached']),
    unstaged: listed(['diff', '--name-only']),
    untracked: listed(['ls-files', '--others', '--exclude-standard']),
  }
}

/**
 * CLI entry: print one scope record as JSON.
 * @param {string[]} args - CLI arguments: --base <ref> [--head <ref>].
 * @returns {number} process exit code.
 */
function main(args) {
  let base
  let head = 'HEAD'
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--base' && i + 1 < args.length) base = args[++i]
    else if (args[i] === '--head' && i + 1 < args.length) head = args[++i]
    else {
      console.error(`change-scope: unknown argument ${JSON.stringify(args[i])}; only --base <ref> [--head <ref>] is supported`)
      return 2
    }
  }
  if (base === undefined) {
    console.error('change-scope: --base <ref> is required; pass a ref you have already verified — it is never guessed or fetched')
    return 2
  }
  const repoDir = resolve(import.meta.dirname, '..')
  try {
    console.log(JSON.stringify(collectScope(repoDir, base, head), null, 2))
  } catch (error) {
    console.error(error.message)
    return 1
  }
  return 0
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2))
}
