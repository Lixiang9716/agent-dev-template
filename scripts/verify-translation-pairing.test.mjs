/**
 * Pairing verifier tests against a real throwaway git repository: a fresh
 * recorded pair passes, a one-sided edit fails with the side named, a
 * structural divergence fails with the signature key, and an incomplete pair
 * is reported instead of crashing.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { collectViolations } from './verify-translation-pairing.mjs'

/** Write a consistent English/Chinese pair with the sidecar still unrecorded. */
function pairBody(lang) {
  const other = lang === 'en' ? 'README.zh.md' : 'README.md'
  const text = [
    `# Title ${lang}`,
    '',
    `[${lang === 'en' ? '中文' : 'English'}](${other})`,
    '',
    '## Section',
    '',
    lang === 'en' ? 'Some words.' : '一些文字。',
    '',
    '```sh',
    'make check',
    '```',
    '',
  ].join('\n')
  return text
}

/** Create a temp git repo containing one valid recorded pair. */
function tempRepoWithPair() {
  const dir = mkdtempSync(join(tmpdir(), 'pairing-'))
  const git = (args) => {
    const result = spawnSync('git', ['-C', dir, ...args], { encoding: 'utf8' })
    assert.equal(result.status, 0, `git ${args.join(' ')}: ${result.stderr}`)
    return result.stdout
  }
  git(['init', '-q'])
  writeFileSync(join(dir, 'README.md'), pairBody('en'))
  writeFileSync(join(dir, 'README.zh.md'), pairBody('zh'))
  const hash = (name) => git(['hash-object', name]).trim()
  writeFileSync(join(dir, 'README.i18n.yaml'), `pair:\n  en: ${hash('README.md')}\n  zh: ${hash('README.zh.md')}\n`)
  return dir
}

test('a recorded consistent pair passes clean', () => {
  const dir = tempRepoWithPair()
  try {
    assert.deepEqual(collectViolations(['README.md'], dir), [])
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('a one-sided edit fails and names the edited side', () => {
  const dir = tempRepoWithPair()
  try {
    writeFileSync(join(dir, 'README.zh.md'), pairBody('zh').replace('一些文字。', '更多文字。'))
    const violations = collectViolations(['README.md'], dir)
    assert.equal(violations.length, 1)
    assert.match(violations[0], /中文 side edited/)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('a structural divergence fails with the signature key', () => {
  const dir = tempRepoWithPair()
  try {
    const drifted = pairBody('zh').replace('一些文字。', '一些文字。\n\n- 列表项')
    const git = (args) => spawnSync('git', ['-C', dir, ...args], { encoding: 'utf8' })
    writeFileSync(join(dir, 'README.zh.md'), drifted)
    writeFileSync(join(dir, 'README.i18n.yaml'), `pair:\n  en: x\n  zh: y\n`)
    const violations = collectViolations(['README.md'], dir)
    assert.ok(violations.some(v => v.includes('structural mismatch on listItems')), JSON.stringify(violations))
    assert.ok(violations.some(v => v.includes('edited since')), JSON.stringify(violations))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('an incomplete pair is reported instead of crashing', () => {
  const dir = tempRepoWithPair()
  try {
    rmSync(join(dir, 'README.i18n.yaml'))
    assert.ok(collectViolations(['README.md'], dir).some(v => v.includes('incomplete pair')))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('a fence divergence fails on the fences signature', () => {
  const dir = tempRepoWithPair()
  try {
    const en = pairBody('en')
    const zh = pairBody('zh').replace('make check', 'make build')
    writeFileSync(join(dir, 'README.md'), en)
    writeFileSync(join(dir, 'README.zh.md'), zh)
    const hash = (name) => spawnSync('git', ['-C', dir, 'hash-object', name], { encoding: 'utf8' }).stdout.trim()
    writeFileSync(join(dir, 'README.i18n.yaml'), `pair:\n  en: ${hash('README.md')}\n  zh: ${hash('README.zh.md')}\n`)
    assert.ok(collectViolations(['README.md'], dir).some(v => v.includes('structural mismatch on fences')))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
