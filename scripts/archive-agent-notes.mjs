#!/usr/bin/env node
/**
 * Seal and verify the archived Agent Notes tree.
 *
 * Every archived note is content-addressed by sha256 in manifest.json. Check
 * mode fails on: a sealed note whose content changed, a manifest entry with
 * no file, or a new unsealed note (run --write to seal). --write only appends
 * new hashes; it never rewrites or removes existing seals. After a triplet is
 * sealed, never edit, move, or delete it.
 */
import { createHash } from 'node:crypto'
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join, relative, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const ROOT = resolve(import.meta.dirname, '..')
const ARCHIVE_DIR = join(ROOT, '.agents', 'notes', 'archived')
const MANIFEST_PATH = join(ARCHIVE_DIR, 'manifest.json')

/** List archived note files as archive-relative posix paths, sorted. */
function archivedFiles(archiveDir = ARCHIVE_DIR) {
  const files = []
  const recurse = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name)
      if (entry.isDirectory()) recurse(full)
      else if (entry.name.endsWith('.md')) files.push(relative(ARCHIVE_DIR, full))
    }
  }
  recurse(archiveDir)
  return files.sort()
}

/** Read manifest.json, or return an empty record when absent. */
function readManifest() {
  try {
    return JSON.parse(readFileSync(MANIFEST_PATH, 'utf8'))
  } catch {
    return { files: {} }
  }
}

/** Compute the sha256 of one file's bytes. */
const sha256 = (path) => createHash('sha256').update(readFileSync(path)).digest('hex')

/**
 * Validate header shape: line 1 title, line 3 implemented status, line 4 the
 * archive date, which must not predate the filename date.
 * @returns {string[]} violations for this file.
 */
function checkHeader(relPath, text) {
  const lines = text.split('\n')
  const problems = []
  if (lines[0]?.startsWith('# Agent Note: ') !== true) problems.push(`${relPath}: line 1 must be "# Agent Note: <title>"`)
  if (lines[2] !== 'Status: implemented') problems.push(`${relPath}: line 3 must be "Status: implemented" (archived notes were decisions that shipped)`)
  const archived = lines[3] ?? ''
  if (!/^Archived: \d{4}-\d{2}-\d{2}$/.test(archived)) {
    problems.push(`${relPath}: line 4 must be "Archived: <date>"`)
    return problems
  }
  const name = relPath.split('/').at(-1)
  const filenameDate = name.slice(0, 10)
  const archivedDate = archived.slice('Archived: '.length)
  if (archivedDate < filenameDate) {
    problems.push(`${relPath}: archived date ${archivedDate} predates the filename date ${filenameDate}`)
  }
  return problems
}

/**
 * Verify or extend the seal.
 * @param {'check'|'write'} mode - check fails on drift; write appends new seals.
 * @returns {number} process exit code.
 */
function main(mode) {
  const files = archivedFiles()
  const manifest = readManifest()
  const violations = []
  for (const relPath of files) violations.push(...checkHeader(relPath, readFileSync(join(ARCHIVE_DIR, relPath), 'utf8')))
  const known = manifest.files ?? {}
  for (const relPath of files) {
    const digest = sha256(join(ARCHIVE_DIR, relPath))
    const seal = known[relPath]
    if (seal === undefined) {
      if (mode === 'write') {
        known[relPath] = { sha256: digest }
        console.log(`archive-agent-notes: sealed ${relPath}`)
      } else {
        violations.push(`${relPath}: not sealed; run "node scripts/archive-agent-notes.mjs --write" and commit the manifest`)
      }
    } else if (seal.sha256 !== digest) {
      violations.push(`${relPath}: content changed after sealing; a sealed note is never edited — restore it or supersede it with a new note`)
    }
  }
  for (const relPath of Object.keys(known)) {
    if (!files.includes(relPath)) violations.push(`${relPath}: manifest entry has no file; seals are never removed`)
  }
  if (violations.length > 0) {
    console.error(`archive-agent-notes: ${violations.length} violation(s):`)
    for (const violation of violations) console.error(`  ${violation}`)
    return 1
  }
  if (mode === 'write') writeFileSync(MANIFEST_PATH, `${JSON.stringify({ files: known }, null, 2)}\n`)
  console.log('archive-agent-notes: the archive is sealed and consistent.')
  return 0
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const mode = process.argv[2] === '--write' ? 'write' : 'check'
  process.exitCode = main(mode)
}
