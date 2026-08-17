/**
 * Negative and positive tests for the notes verifier: every rejection rule
 * fires on a minimal violating tree, and a valid tree passes clean. A gate
 * only guards if the regression actually fails it.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { collectViolations } from './verify-agent-notes.mjs'

/** Valid implemented note body used as the base for mutations. */
const VALID_IMPLEMENTED = [
  '# Agent Note: sample decision',
  '',
  'Status: implemented',
  '',
  '## Problem',
  '',
  'A problem statement.',
  '',
  '## Decision',
  '',
  'The decision.',
  '',
  '## Alternatives considered',
  '',
  'An alternative and why it lost.',
  '',
  '## Consequences',
  '',
  'What follows.',
  '',
].join('\n')

/** Create a throwaway notes tree with one note. */
function notesTree(lifecycle, className, filename, body) {
  const dir = mkdtempSync(join(tmpdir(), 'notes-'))
  mkdirSync(join(dir, lifecycle, className), { recursive: true })
  writeFileSync(join(dir, lifecycle, className, filename), body)
  writeFileSync(join(dir, 'README.md'), '# Agent Notes\n')
  return dir
}

const violationsOf = (tree) => collectViolations(tree)

test('a valid implemented note passes clean', () => {
  const tree = notesTree('implemented', 'process', '2026-01-01-valid-note.md', VALID_IMPLEMENTED)
  try {
    assert.deepEqual(violationsOf(tree), [])
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})

test('an unknown lifecycle directory is rejected', () => {
  const tree = mkdtempSync(join(tmpdir(), 'notes-'))
  try {
    mkdirSync(join(tree, 'drafts', 'process'), { recursive: true })
    writeFileSync(join(tree, 'drafts', 'process', '2026-01-01-x.md'), VALID_IMPLEMENTED)
    writeFileSync(join(tree, 'README.md'), '# Agent Notes\n')
    assert.ok(violationsOf(tree).some(v => v.includes('unknown lifecycle')))
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})

test('an unknown class directory is rejected', () => {
  const tree = notesTree('implemented', 'misc', '2026-01-01-x.md', VALID_IMPLEMENTED)
  try {
    assert.ok(violationsOf(tree).some(v => v.includes('unknown class')))
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})

test('a malformed filename is rejected', () => {
  const tree = notesTree('implemented', 'process', 'notes.md', VALID_IMPLEMENTED)
  try {
    assert.ok(violationsOf(tree).some(v => v.includes('yyyy-mm-dd-topic.md')))
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})

test('an implemented note with a Proposal section is rejected', () => {
  const body = VALID_IMPLEMENTED.replace('## Decision', '## Proposal\n\nOld text.\n\n## Decision')
  const tree = notesTree('implemented', 'process', '2026-01-01-x.md', body)
  try {
    assert.ok(violationsOf(tree).some(v => v.includes('proposal-era')))
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})

test('a rejected note without a reason suffix on Status is rejected', () => {
  const body = VALID_IMPLEMENTED.replace('Status: implemented', 'Status: rejected')
  const tree = notesTree('rejected', 'process', '2026-01-01-x.md', body)
  try {
    assert.ok(violationsOf(tree).some(v => v.includes('Status: rejected —')))
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})

test('a proposed note missing Acceptance criteria is rejected', () => {
  const body = [
    '# Agent Note: sample proposal', '', 'Status: proposed', '',
    '## Problem', '', 'P.', '',
    '## Proposal', '', 'Do it.', '',
    '## Alternatives considered', '', 'None.', '',
    '## Risks', '', 'Few.', '',
  ].join('\n')
  const tree = notesTree('proposed', 'process', '2026-01-01-x.md', body)
  try {
    assert.ok(violationsOf(tree).some(v => v.includes('Acceptance criteria')))
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})

test('INDEX.md is rejected wherever it appears', () => {
  const tree = notesTree('implemented', 'process', '2026-01-01-x.md', VALID_IMPLEMENTED)
  try {
    writeFileSync(join(tree, 'implemented', 'process', 'INDEX.md'), '# index\n')
    assert.ok(violationsOf(tree).some(v => v.includes('INDEX.md is forbidden')))
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})

test('the archived tree is never re-validated here', () => {
  const tree = notesTree('implemented', 'process', '2026-01-01-x.md', VALID_IMPLEMENTED)
  try {
    mkdirSync(join(tree, 'archived'), { recursive: true })
    writeFileSync(join(tree, 'archived', 'anything.md'), 'not a note\n')
    assert.deepEqual(violationsOf(tree), [])
  } finally {
    rmSync(tree, { recursive: true, force: true })
  }
})
