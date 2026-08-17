/**
 * change-scope contract tests against a real throwaway git repository: the
 * four path classes partition real states, and an unresolvable base fails
 * loud instead of producing an empty record.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { collectScope, FORMAT_VERSION } from './change-scope.mjs'

/** Create a git repo with an initial commit on main. */
function tempRepo() {
  const dir = mkdtempSync(join(tmpdir(), 'change-scope-'))
  const git = (args) => {
    const result = spawnSync('git', ['-C', dir, ...args], { encoding: 'utf8' })
    assert.equal(result.status, 0, `git ${args.join(' ')}: ${result.stderr}`)
    return result.stdout
  }
  git(['init', '--initial-branch=main', '-q'])
  git(['config', 'user.email', 'test@example.com'])
  git(['config', 'user.name', 'test'])
  writeFileSync(join(dir, 'seed.txt'), 'seed\n')
  git(['add', '.'])
  git(['commit', '-q', '-m', 'seed'])
  return { dir, git }
}

test('partitions committed, staged, unstaged, and untracked paths', () => {
  const { dir, git } = tempRepo()
  try {
    writeFileSync(join(dir, 'committed.txt'), 'committed\n')
    git(['add', '.'])
    git(['commit', '-q', '-m', 'committed'])
    writeFileSync(join(dir, 'staged.txt'), 'staged\n')
    git(['add', '.'])
    // An unstaged change must modify a tracked file; a never-added file is untracked.
    writeFileSync(join(dir, 'committed.txt'), 'committed, then modified\n')
    writeFileSync(join(dir, 'untracked.txt'), 'untracked\n')
    const scope = collectScope(dir, 'HEAD~1')
    assert.equal(scope.formatVersion, FORMAT_VERSION)
    assert.deepEqual(scope.committed, ['committed.txt'])
    assert.deepEqual(scope.staged, ['staged.txt'])
    assert.deepEqual(scope.unstaged, ['committed.txt'])
    assert.ok(scope.untracked.includes('untracked.txt'))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('a clean tree reports empty path classes and a resolvable merge base', () => {
  const { dir } = tempRepo()
  try {
    const scope = collectScope(dir, 'HEAD')
    assert.equal(scope.mergeBaseSha, scope.headSha)
    assert.equal(scope.mergeBaseSha, scope.baseSha)
    assert.deepEqual([scope.committed, scope.staged, scope.unstaged, scope.untracked], [[], [], [], []])
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('an unresolvable base fails loud with the git error', () => {
  const { dir } = tempRepo()
  try {
    assert.throws(() => collectScope(dir, 'no-such-ref'), /rev-parse/)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
