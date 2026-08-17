#!/usr/bin/env node
/**
 * Validate the Agent Notes tree: closed lifecycle and class sets, dated
 * filenames, the three-line header, and the required sections per lifecycle.
 * `archived/` is frozen and owned by archive-agent-notes.mjs; this verifier
 * never re-validates sealed content. Failures are collected and reported all
 * at once with file-relative locations.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const ROOT = resolve(import.meta.dirname, '..')
const NOTES_DIR = join(ROOT, '.agents', 'notes')

/** Closed lifecycle set; archived/ is a sibling frozen tree, not a lifecycle. */
const LIFECYCLES = new Set(['proposed', 'implemented', 'rejected'])
/** Closed class set; adding a class is a deliberate act that updates this list and the notes README. */
const CLASSES = new Set(['feature', 'bug-fix', 'simplification', 'architecture', 'process', 'testing'])
/** Sections each lifecycle requires beyond Problem. */
const REQUIRED_SECTIONS = {
  proposed: ['Proposal', 'Alternatives considered', 'Acceptance criteria', 'Risks'],
  implemented: ['Decision', 'Alternatives considered', 'Consequences'],
  rejected: ['Proposal', 'Alternatives considered'],
}
/** Proposal-era headings that must not survive into an implemented note. */
const FORBIDDEN_IN_IMPLEMENTED = ['Proposal', 'Plan', 'Migration plan', 'Acceptance criteria']

/** Recursively collect .md paths under dir. */
function walkMd(dir) {
  const out = []
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) out.push(...walkMd(full))
    else if (entry.endsWith('.md')) out.push(full)
  }
  return out
}

/** Validate one note file's header, filename, and sections. */
function checkNote(relPath, text, violations) {
  const here = (message) => violations.push(`${relPath}: ${message}`)
  const lifecycle = relPath.split('/')[0]
  const name = relPath.split('/').at(-1)
  if (!/^\d{4}-\d{2}-\d{2}-[a-z0-9]+(-[a-z0-9]+)*\.md$/.test(name)) {
    here(`filename must be yyyy-mm-dd-topic.md (kebab-case topic, dated at first proposal)`)
    return
  }
  const lines = text.split('\n')
  if (lines[0]?.startsWith('# Agent Note: ') !== true) { here('line 1 must be "# Agent Note: <title>"'); return }
  if (lines[1] !== '') here('line 2 must be empty')
  const statusLine = lines[2] ?? ''
  if (lifecycle === 'rejected') {
    if (!/^Status: rejected — .+$/.test(statusLine)) here('line 3 for a rejected note must be "Status: rejected — <why>"')
  } else if (!/^Status: (proposed|implemented)$/.test(statusLine)) {
    here(`line 3 must be exactly "Status: ${lifecycle}"`)
  }
  if ((text.match(/^Status: /gm) ?? []).length !== 1) here('exactly one "Status:" line is allowed')
  if (lines[3] !== '') here('line 4 must be empty')
  const sections = [...text.matchAll(/^## (.+)$/gm)].map(match => match[1])
  if (sections[0] !== 'Problem') here('the first section must be "## Problem"')
  for (const section of REQUIRED_SECTIONS[lifecycle] ?? []) {
    if (!sections.includes(section)) here(`lifecycle "${lifecycle}" requires a "## ${section}" section`)
  }
  if (lifecycle === 'implemented') {
    for (const heading of FORBIDDEN_IN_IMPLEMENTED) {
      if (sections.includes(heading)) here(`"## ${heading}" is proposal-era; an implemented note states what is`)
    }
  }
}

/**
 * Validate the whole notes tree.
 * @returns {string[]} violation list; empty when the tree is valid.
 */
export function collectViolations(notesDir = NOTES_DIR) {
  const violations = []
  const top = readdirSync(notesDir)
  for (const entry of top) {
    if (entry === 'README.md' || entry === 'archived') continue
    if (entry === 'INDEX.md') { violations.push('INDEX.md is forbidden: the tree layout is the index'); continue }
    if (!LIFECYCLES.has(entry)) {
      violations.push(`${entry}/: unknown lifecycle directory; closed set is ${[...LIFECYCLES].join(', ')}`)
      continue
    }
    const lifecycleDir = join(notesDir, entry)
    for (const className of readdirSync(lifecycleDir)) {
      const classDir = join(lifecycleDir, className)
      if (!statSync(classDir).isDirectory()) {
        violations.push(`${entry}/${className}: unexpected file directly under a lifecycle directory`)
        continue
      }
      if (!CLASSES.has(className)) {
        violations.push(`${entry}/${className}/: unknown class; closed set is ${[...CLASSES].join(', ')}`)
        continue
      }
      for (const file of readdirSync(classDir)) {
        const relPath = relative(notesDir, join(lifecycleDir, className, file))
        if (file === 'INDEX.md') violations.push(`${relPath}: INDEX.md is forbidden`)
        else if (file.endsWith('.md')) {
          checkNote(relPath, readFileSync(join(classDir, file), 'utf8'), violations)
        } else {
          violations.push(`${relPath}: notes are English-only Markdown; unexpected file type`)
        }
      }
    }
  }
  return violations
}

/**
 * CLI entry: report every violation and exit 1, or confirm the tree.
 * @returns {number} process exit code.
 */
function main() {
  const violations = collectViolations()
  if (violations.length === 0) {
    console.log('verify-agent-notes: the notes tree is valid.')
    return 0
  }
  console.error(`verify-agent-notes: ${violations.length} violation(s):`)
  for (const violation of violations) console.error(`  ${violation}`)
  return 1
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main()
}
