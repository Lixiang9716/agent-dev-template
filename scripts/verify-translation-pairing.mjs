#!/usr/bin/env node
/**
 * Verify bilingual documentation pairs.
 *
 * A pair is three sibling files: `foo.md` + `foo.zh.md` + `foo.i18n.yaml`.
 * The sidecar records the git blob hash of each side at its last
 * confirmed-consistent state, so a later edit on either side alone fails here
 * until the pair is re-confirmed with --write in the same change. Structural
 * signatures (heading counts, list counts, table rows, link targets,
 * byte-identical fenced blocks) must also match. A green gate means the pair
 * was confirmed consistent at these exact contents — not that the translation
 * is good. Translation quality belongs to review.
 */
import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { join, relative, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const ROOT = resolve(import.meta.dirname, '..')

/** Documentation scope: root-level Markdown plus docs/**. */
const SCOPE = ['*.md', 'docs/**/*.md']

/**
 * Compute the git blob hash of one file. Works on working-tree content; the
 * blob need not be staged. Fails loud outside a git repository.
 */
function blobHash(path) {
  const result = spawnSync('git', ['hash-object', path], { encoding: 'utf8', cwd: ROOT })
  if (result.status !== 0) {
    throw new Error(`verify-translation-pairing: git hash-object failed for ${path}: ${result.stderr.trim()}`)
  }
  return result.stdout.trim()
}

/** Expand the scope patterns to concrete repo-relative English-side paths. */
function expandScope() {
  const paths = new Set()
  const addDir = (dir, recursive) => {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const rel = dir === '' ? entry.name : `${dir}/${entry.name}`
      if (entry.isDirectory()) {
        if (recursive) addDir(rel, true)
      } else if (entry.name.endsWith('.md') && !entry.name.endsWith('.zh.md')) {
        paths.add(rel)
      }
    }
  }
  for (const pattern of SCOPE) {
    if (pattern === '*.md') addDir('', false)
    else if (pattern.endsWith('/**/*.md')) addDir(pattern.slice(0, -'/**/*.md'.length), true)
    else throw new Error(`verify-translation-pairing: unsupported scope pattern ${JSON.stringify(pattern)}`)
  }
  return [...paths].sort()
}

/** Parse the exact sidecar shape: pair:\n  en: <hash>\n  zh: <hash>\n. */
function parseSidecar(text, relPath) {
  const lines = text.split('\n')
  const shape = lines.length === 4 && lines[0] === 'pair:'
    && lines[1]?.startsWith('  en: ') && lines[2]?.startsWith('  zh: ') && lines[3] === ''
  if (!shape) {
    throw new Error(`verify-translation-pairing: ${relPath} must contain exactly "pair:", "  en: <hash>", "  zh: <hash>"`)
  }
  return { en: lines[1].slice(6).trim(), zh: lines[2].slice(6).trim() }
}

/** Extract fenced code blocks' exact bytes; fences are language-neutral and must be identical. */
function fences(text) {
  return [...text.matchAll(/```[^\n]*\n[\s\S]*?```/g)].map(match => match[0]).join('\n')
}

/**
 * Structural signature of one document side. Link targets are canonicalized
 * (a `.zh.md` target equals its `.md` base): each side legitimately links its
 * own language, and the switcher link to the counterpart is dropped by
 * comparing against the document's own canonical name.
 */
function signature(text, ownCanonicalName) {
  const lines = text.split('\n')
  const linkTargets = [...text.matchAll(/\]\(([^)]+)\)/g)]
    .map(match => match[1].replace(/\.zh\.md$/, '.md'))
    .filter(target => target !== ownCanonicalName)
  return {
    headings: lines.filter(l => /^#{1,6} /.test(l)).length,
    listItems: lines.filter(l => /^\s*(?:[-*+]|\d+\.)\s+/.test(l)).length,
    tableRows: lines.filter(l => l.startsWith('|')).length,
    linkTargets,
    fences: fences(text),
  }
}

/** First differing signature key, or undefined when equal. */
function firstSignatureDifference(a, b) {
  for (const key of Object.keys(a)) {
    if (JSON.stringify(a[key]) !== JSON.stringify(b[key])) return key
  }
  return undefined
}

/** True when the first six lines contain a markdown link to the counterpart. */
const linksCounterpart = (text, counterpartName) => {
  const head = text.split('\n').slice(0, 6).join('\n')
  const escaped = counterpartName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return new RegExp(`\\]\\(${escaped}\\)`).test(head)
}

/** Sibling paths for one English-side repo-relative path. */
function pairPaths(rel) {
  const base = rel.slice(0, -3)
  return {
    en: rel,
    zh: `${base}.zh.md`,
    sidecar: `${base}.i18n.yaml`,
  }
}

/**
 * Verify every pair in scope.
 * @param {string[]} [sources] - override scope with explicit English-side paths (tests).
 * @param {string} [root] - repository root; defaults to the template root.
 * @returns {string[]} violation list; empty when all pairs are consistent.
 */
export function collectViolations(sources, root = ROOT) {
  const violations = []
  for (const rel of sources ?? expandScope()) {
    const { en: enRel, zh: zhRel, sidecar: sidecarRel } = pairPaths(rel)
    const enPath = join(root, enRel)
    const zhPath = join(root, zhRel)
    const sidecarPath = join(root, sidecarRel)
    const missing = [!existsSync(enPath) && enRel, !existsSync(zhPath) && zhRel, !existsSync(sidecarPath) && sidecarRel].filter(Boolean)
    if (missing.length > 0) {
      violations.push(`${rel}: incomplete pair — missing ${missing.join(', ')}`)
      continue
    }
    let recorded
    try {
      recorded = parseSidecar(readFileSync(sidecarPath, 'utf8'), sidecarRel)
    } catch (error) {
      violations.push(error.message)
      continue
    }
    const hashes = { en: blobHash(enPath), zh: blobHash(zhPath) }
    const staleSides = [recorded.en !== hashes.en && 'English', recorded.zh !== hashes.zh && '中文'].filter(Boolean)
    if (staleSides.length > 0) {
      violations.push(`${rel}: ${staleSides.join(' and ')} side edited since the last confirmed state — re-confirm with --write in the same change, or revert`)
    }
    const diffKey = firstSignatureDifference(
      signature(readFileSync(enPath, 'utf8'), enRel.split('/').at(-1).replace(/\.md$/, '') + '.md'),
      signature(readFileSync(zhPath, 'utf8'), enRel.split('/').at(-1)),
    )
    if (diffKey !== undefined) violations.push(`${zhRel}: structural mismatch on ${diffKey}; both sides must carry the same structure`)
    if (!linksCounterpart(readFileSync(zhPath, 'utf8'), enRel.split('/').at(-1))) {
      violations.push(`${zhRel}: must link the English side in the first lines (language switcher)`)
    }
    if (!linksCounterpart(readFileSync(enPath, 'utf8'), zhRel.split('/').at(-1))) {
      violations.push(`${enRel}: must link the Chinese side in the first lines (language switcher)`)
    }
  }
  return violations
}

/** Re-record one pair's hashes after a confirmed-consistent edit. */
function writePair(rel) {
  const { en: enRel, zh: zhRel, sidecar: sidecarRel } = pairPaths(rel)
  const enPath = join(ROOT, enRel)
  const zhPath = join(ROOT, zhRel)
  const sidecarPath = join(ROOT, sidecarRel)
  const missing = [!existsSync(enPath) && enRel, !existsSync(zhPath) && zhRel].filter(Boolean)
  if (missing.length > 0) {
    console.error(`verify-translation-pairing: cannot write an incomplete pair — missing ${missing.join(', ')}`)
    return 2
  }
  writeFileSync(sidecarPath, `pair:\n  en: ${blobHash(enPath)}\n  zh: ${blobHash(zhPath)}\n`)
  console.log(`verify-translation-pairing: recorded ${enRel}`)
  return 0
}

/**
 * CLI entry.
 * @param {string[]} args - `--write <path>` re-records one pair; otherwise verify all.
 * @returns {number} process exit code.
 */
function main(args) {
  if (args[0] === '--write') {
    if (args.length !== 2) {
      console.error('verify-translation-pairing: --write takes exactly one English-side path, e.g. --write README.md')
      return 2
    }
    return writePair(relative(ROOT, resolve(ROOT, args[1])))
  }
  if (args.length > 0) {
    console.error('verify-translation-pairing: unknown arguments; only --write <path> is supported')
    return 2
  }
  const violations = collectViolations()
  if (violations.length === 0) {
    console.log('verify-translation-pairing: all pairs confirmed consistent at recorded contents.')
    return 0
  }
  console.error(`verify-translation-pairing: ${violations.length} violation(s):`)
  for (const violation of violations) console.error(`  ${violation}`)
  return 1
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2))
}
