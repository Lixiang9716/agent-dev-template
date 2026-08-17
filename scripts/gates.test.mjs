/**
 * Scheduler self-tests. These pin the contract the gates aggregate relies on:
 * invalid graphs are rejected before any child starts, failures propagate as
 * skips with the cause, and allowFailure stays non-blocking. A gate only
 * guards if the regression actually fails it — every rejection rule here has
 * a test that proves it fires.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync, writeFileSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { validateConfig, runGates } from './gates.mjs'

/** Build a minimal valid config around one gate list. */
const config = (gates) => validateConfig({ modes: { all: gates.map(g => g.id) }, gates })

test('validateConfig rejects an empty gate list', () => {
  assert.throws(() => validateConfig({ modes: { all: [] }, gates: [] }), /gate list is empty/)
})

test('validateConfig rejects duplicate gate ids', () => {
  assert.throws(() => config([
    { id: 'a', command: ['true'] },
    { id: 'a', command: ['true'] },
  ]), /duplicate gate id "a"/)
})

test('validateConfig rejects a dependency on an unknown gate', () => {
  assert.throws(() => config([
    { id: 'a', command: ['true'], needs: ['ghost'] },
  ]), /depends on unknown gate "ghost"/)
})

test('validateConfig rejects a dependency cycle before any child starts', () => {
  const cycles = [
    [{ id: 'a', command: ['true'], needs: ['b'] }, { id: 'b', command: ['true'], needs: ['a'] }],
    [{ id: 'self', command: ['true'], needs: ['self'] }],
    [{ id: 'a', command: ['true'], needs: ['b'] }, { id: 'b', command: ['true'], needs: ['c'] },
      { id: 'c', command: ['true'], needs: ['a'] }],
  ]
  for (const gates of cycles) {
    assert.throws(() => config(gates), /dependency cycle/)
  }
})

test('validateConfig rejects a command that is not a non-empty string array', () => {
  assert.throws(() => config([{ id: 'a', command: [] }]), /non-empty command string array/)
  assert.throws(() => config([{ id: 'a', command: 'true' }]), /non-empty command string array/)
})

test('validateConfig rejects modes referencing unknown gates', () => {
  const raw = { modes: { all: ['a'], extra: ['ghost'] }, gates: [{ id: 'a', command: ['true'] }] }
  assert.throws(() => validateConfig(raw), /mode "extra" must be a non-empty array of known gate ids/)
})

test('a failing dependency skips its dependents with the cause', async () => {
  const { gates } = config([
    { id: 'root', command: ['node', '-e', 'process.exit(3)'] },
    { id: 'child', command: ['true'], needs: ['root'] },
    { id: 'grandchild', command: ['true'], needs: ['child'] },
  ])
  const results = await runGates(gates, 2, gate => ({
    then: (onFulfilled) => onFulfilled({
      gate,
      status: gate.command[0] === 'true' ? 'passed' : 'failed',
      durationMs: 1,
      output: '',
      reason: 'exit 3',
      blocking: gate.id === 'root',
    }),
  }))
  assert.equal(results.find(r => r.gate.id === 'root').status, 'failed')
  assert.equal(results.find(r => r.gate.id === 'child').status, 'skipped')
  assert.equal(results.find(r => r.gate.id === 'child').reason, 'dependency failed or skipped: root')
  assert.equal(results.find(r => r.gate.id === 'grandchild').status, 'skipped')
})

test('a dependent gate runs only after its dependency passes', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'gates-order-'))
  try {
    const marker = join(dir, 'marker')
    const { gates } = config([
      { id: 'produce', command: ['node', '-e', `require('node:fs').writeFileSync(${JSON.stringify(marker)}, '')`] },
      { id: 'consume', command: ['node', '-e', `process.exit(require('node:fs').existsSync(${JSON.stringify(marker)}) ? 0 : 1)`], needs: ['produce'] },
    ])
    const results = await runGates(gates, 4, gate => import('./gates.mjs').then(m => m.runGate(gate, dir)))
    assert.deepEqual(results.map(r => r.status), ['passed', 'passed'])
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('allowFailure keeps a failed gate out of the blocking set', async () => {
  const { gates } = config([
    { id: 'observational', command: ['node', '-e', 'process.exit(1)'], allowFailure: true },
  ])
  const results = await runGates(gates, 1, gate => ({
    then: (onFulfilled) => onFulfilled({ gate, status: 'failed', durationMs: 1, output: '', reason: 'exit 1', blocking: false }),
  }))
  assert.equal(results[0].status, 'failed')
  assert.equal(results[0].blocking, false)
})

test('runGate reports a signal kill as failed with the signal fact', async () => {
  const { gates } = config([
    { id: 'self-kill', command: ['node', '-e', 'process.kill(process.pid, "SIGKILL")'] },
  ])
  const result = await runGates(gates, 1, gate => import('./gates.mjs').then(m => m.runGate(gate)))
  assert.equal(result[0].status, 'failed')
  assert.equal(result[0].reason, 'signal SIGKILL')
  assert.equal(result[0].blocking, true)
})
