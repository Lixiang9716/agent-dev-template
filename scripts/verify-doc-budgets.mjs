#!/usr/bin/env node
/**
 * Enforce word-count ceilings from scripts/doc-budgets.json on the English
 * side of every in-scope document. Ceilings ratchet down; raising one is a
 * deliberate change to this manifest, made in the same PR that needs the
 * words. The Chinese side is not counted; the English side is the canonical
 * count for a pair.
 */
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const ROOT = resolve(import.meta.dirname, '..')
const MANIFEST_PATH = resolve(ROOT, 'scripts', 'doc-budgets.json')

/**
 * Count words wc-style: whitespace-separated tokens.
 * @param {string} text - document text.
 * @returns {number} word count.
 */
function wordCount(text) {
  const trimmed = text.trim()
  return trimmed.length === 0 ? 0 : trimmed.split(/\s+/).length
}

/**
 * Validate every budget entry.
 * @returns {string[]} violation list; empty when all documents fit.
 */
export function collectViolations() {
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, 'utf8'))
  const violations = []
  for (const [rel, ceiling] of Object.entries(manifest)) {
    if (!Number.isSafeInteger(ceiling) || ceiling < 1) {
      violations.push(`${rel}: ceiling must be a positive integer`)
      continue
    }
    let text
    try {
      text = readFileSync(resolve(ROOT, rel), 'utf8')
    } catch {
      violations.push(`${rel}: budgeted document is missing — renamed or deleted? update scripts/doc-budgets.json in the same change`)
      continue
    }
    const words = wordCount(text)
    if (words > ceiling) violations.push(`${rel}: ${words} words exceed the ${ceiling}-word ceiling — relocate or condense, or raise the ceiling here with justification`)
  }
  return violations
}

/**
 * CLI entry: report violations and exit 1, or confirm budgets hold.
 * @returns {number} process exit code.
 */
function main() {
  const violations = collectViolations()
  if (violations.length === 0) {
    console.log('verify-doc-budgets: every budgeted document fits its ceiling.')
    return 0
  }
  console.error(`verify-doc-budgets: ${violations.length} violation(s):`)
  for (const violation of violations) console.error(`  ${violation}`)
  return 1
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main()
}
