#!/usr/bin/env node
/**
 * Declarative DAG gate scheduler.
 *
 * Runs one mode from gates.json: a gate starts once every gate in its `needs`
 * has passed, bounded by the concurrency limit; a failed dependency marks its
 * dependents skipped with the reason instead of running them. Config problems
 * (duplicate ids, unknown needs, dependency cycles, unknown modes) abort
 * before any child process starts — a gate list that cannot be executed
 * unambiguously is never best-effort run.
 *
 * Zero runtime dependencies: node:* builtins only. See docs/architecture.md.
 */
import { spawn } from 'node:child_process'
import { availableParallelism } from 'node:os'
import { readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { pathToFileURL } from 'node:url'
import { performance } from 'node:perf_hooks'

const ROOT = resolve(import.meta.dirname, '..')
const CONFIG_PATH = resolve(ROOT, 'gates.json')

/** A validated gate ready for scheduling. */
class Gate {
  /**
   * @param {object} raw - one gates.json entry.
   * @param {string} raw.id - unique gate id.
   * @param {string[]} raw.command - argv to execute; run without a shell.
   * @param {string[]} [raw.needs] - ids that must pass first.
   * @param {boolean} [raw.allowFailure] - failure does not fail the aggregate.
   */
  constructor(raw) {
    if (typeof raw !== 'object' || raw === null) throw new Error('gates: each gate must be an object')
    if (typeof raw.id !== 'string' || raw.id.length === 0) throw new Error('gates: gate id must be a non-empty string')
    if (!Array.isArray(raw.command) || raw.command.length === 0
      || raw.command.some(part => typeof part !== 'string')) {
      throw new Error(`gates: gate "${raw.id}" needs a non-empty command string array`)
    }
    if (raw.needs !== undefined && (!Array.isArray(raw.needs)
      || raw.needs.some(dep => typeof dep !== 'string'))) {
      throw new Error(`gates: gate "${raw.id}" needs must be an array of gate ids`)
    }
    if (raw.allowFailure !== undefined && typeof raw.allowFailure !== 'boolean') {
      throw new Error(`gates: gate "${raw.id}" allowFailure must be a boolean`)
    }
    this.id = raw.id
    this.label = typeof raw.label === 'string' && raw.label.length > 0 ? raw.label : raw.id
    this.command = raw.command
    this.needs = raw.needs ?? []
    this.allowFailure = raw.allowFailure === true
  }
}

/**
 * Validate the whole parsed gates.json: unique ids, resolvable needs, an
 * acyclic graph, and modes referencing known gates.
 * @param {unknown} raw - parsed gates.json contents.
 * @returns {{ modes: Record<string, string[]>, gates: Gate[] }} normalized config.
 */
export function validateConfig(raw) {
  if (typeof raw !== 'object' || raw === null) throw new Error('gates: config must be a JSON object')
  const { modes, gates: rawGates } = raw
  if (!Array.isArray(rawGates) || rawGates.length === 0) {
    throw new Error('gates: gate list is empty — an aggregate with no gates cannot be validated or run')
  }
  if (typeof modes !== 'object' || modes === null || Array.isArray(modes)) {
    throw new Error('gates: modes must be an object mapping mode names to gate id arrays')
  }
  const byId = new Map()
  for (const entry of rawGates) {
    const gate = new Gate(entry)
    if (byId.has(gate.id)) throw new Error(`gates: duplicate gate id "${gate.id}"`)
    byId.set(gate.id, gate)
  }
  for (const gate of byId.values()) {
    for (const dep of gate.needs) {
      if (!byId.has(dep)) throw new Error(`gates: gate "${gate.id}" depends on unknown gate "${dep}"`)
    }
  }
  const cycle = findCycle(byId)
  if (cycle !== undefined) throw new Error(`gates: dependency cycle: ${cycle.join(' -> ')}`)
  for (const [name, ids] of Object.entries(modes)) {
    if (!Array.isArray(ids) || ids.length === 0 || ids.some(id => !byId.has(id))) {
      throw new Error(`gates: mode "${name}" must be a non-empty array of known gate ids`)
    }
  }
  if (!Array.isArray(modes.all)) throw new Error('gates: modes must define "all"')
  return { modes, gates: [...byId.values()] }
}

/** Return the first dependency cycle as a path of ids, or undefined. */
function findCycle(byId) {
  const complete = new Set()
  const active = new Map()
  const path = []
  const visit = (id) => {
    if (complete.has(id)) return undefined
    const start = active.get(id)
    if (start !== undefined) return [...path.slice(start), id]
    active.set(id, path.length)
    path.push(id)
    for (const dep of byId.get(id).needs) {
      const cycle = visit(dep)
      if (cycle !== undefined) return cycle
    }
    path.pop()
    active.delete(id)
    complete.add(id)
    return undefined
  }
  for (const gate of byId.values()) {
    const cycle = visit(gate.id)
    if (cycle !== undefined) return cycle
  }
  return undefined
}

/** One observed gate outcome. */
export class GateResult {
  /**
   * @param {Gate} gate - the gate that produced this result.
   * @param {'passed'|'failed'|'skipped'} status - observed outcome.
   * @param {number} durationMs - wall time for executed gates; 0 when skipped.
   * @param {string} output - combined stdout/stderr; empty when skipped.
   * @param {string} [reason] - exit/signal facts, or the skip cause.
   */
  constructor(gate, status, durationMs, output, reason) {
    this.gate = gate
    this.status = status
    this.durationMs = durationMs
    this.output = output
    if (reason !== undefined) this.reason = reason
  }

  /** Blocking outcome for the aggregate: failed or skipped without allowFailure. */
  get blocking() {
    return this.status !== 'passed' && !this.gate.allowFailure
  }
}

/** Format a finished process outcome without letting one fact hide another. */
function processReason(exitCode, signal) {
  const facts = []
  if (exitCode !== null) facts.push(`exit ${exitCode}`)
  if (signal !== null) facts.push(`signal ${signal}`)
  return facts.length === 0 ? 'no exit code or signal' : facts.join(', ')
}

/**
 * Execute one gate as a real child process, capturing its output.
 * @param {Gate} gate - gate to execute.
 * @param {string} cwd - repository root the command runs in.
 * @returns {Promise<GateResult>} the observed outcome.
 */
export function runGate(gate, cwd = ROOT) {
  return new Promise((resolveGate) => {
    const startedAt = performance.now()
    let output = ''
    let spawnError
    const child = spawn(gate.command[0], gate.command.slice(1), { cwd, stdio: ['ignore', 'pipe', 'pipe'] })
    const append = (chunk) => { output += chunk }
    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', append)
    child.stderr.on('data', append)
    child.on('error', (error) => { spawnError = `failed to start: ${error.message}` })
    child.on('close', (exitCode, signal) => {
      const failed = spawnError !== undefined || exitCode !== 0 || signal !== null
      const reason = spawnError ?? processReason(exitCode, signal)
      resolveGate(new GateResult(gate, failed ? 'failed' : 'passed', performance.now() - startedAt, output, reason))
    })
  })
}

/**
 * Run a validated gate list: start ready gates up to `maxActive`, settle them
 * as they finish, and skip pending gates whose dependencies did not pass.
 * @param {Gate[]} gates - complete gate list for the aggregate.
 * @param {number} maxActive - maximum concurrent children; a positive integer.
 * @param {(gate: Gate) => Promise<GateResult>} execute - child-process executor.
 * @param {(result: GateResult) => void} [observe] - invoked as each gate settles.
 * @returns {Promise<GateResult[]>} results in gate-list order.
 */
export async function runGates(gates, maxActive, execute, observe = () => {}) {
  if (!Number.isSafeInteger(maxActive) || maxActive < 1) {
    throw new Error(`gates: max concurrency must be a positive integer, got ${JSON.stringify(maxActive)}`)
  }
  const states = new Map(gates.map(gate => [gate.id, 'pending']))
  const results = new Map()
  const running = []
  const ready = () => gates.find(gate => states.get(gate.id) === 'pending'
    && gate.needs.every(dep => states.get(dep) === 'passed'))

  for (;;) {
    while (running.length < maxActive) {
      const gate = ready()
      if (gate === undefined) break
      states.set(gate.id, 'running')
      running.push({ gate, promise: execute(gate) })
      console.log(`gates: start ${gate.label}`)
    }
    if (running.length === 0) {
      skipPendingWithFailedDependency(states, gates, results, observe)
      break
    }
    const settled = await Promise.race(running.map(async item => ({ item, result: await item.promise })))
    running.splice(running.indexOf(settled.item), 1)
    states.set(settled.item.gate.id, settled.result.status)
    results.set(settled.item.gate.id, settled.result)
    observe(settled.result)
  }
  return gates.map((gate) => {
    const result = results.get(gate.id)
    if (result === undefined) throw new Error(`gates: missing result for ${gate.id}`)
    return result
  })
}

/**
 * Mark every remaining pending gate skipped, attributing the failed needs.
 * Reaches this state only when no gate can start and none is running, so each
 * pending gate must have a dependency that failed or was skipped; anything
 * else is a scheduler defect and fails loud instead of hanging.
 * @param {Map<string, string>} states - gate id to pending/running/passed/failed/skipped.
 * @param {Gate[]} gates - complete gate list, for looking up needs.
 * @param {Map<string, GateResult>} results - destination for skip results.
 * @param {(result: GateResult) => void} observe - result observer.
 */
function skipPendingWithFailedDependency(states, gates, results, observe) {
  const byId = new Map(gates.map(gate => [gate.id, gate]))
  let pending = gates.filter(gate => states.get(gate.id) === 'pending')
  while (pending.length > 0) {
    const gate = pending.find(item => item.needs.some(id => {
      const state = states.get(id)
      return state === 'failed' || state === 'skipped'
    }))
    if (gate === undefined) throw new Error('gates: validated graph stalled without a failed dependency')
    const failedDeps = gate.needs.filter(id => {
      const state = states.get(id)
      return state === 'failed' || state === 'skipped'
    })
    const result = new GateResult(gate, 'skipped', 0, '', `dependency failed or skipped: ${failedDeps.join(', ')}`)
    states.set(gate.id, 'skipped')
    results.set(gate.id, result)
    observe(result)
    pending = pending.filter(item => item.id !== gate.id)
  }
}

/**
 * CLI entry: run one aggregate mode and exit non-zero on any blocking outcome.
 * @param {string[]} args - CLI arguments; `--mode <name>` selects the aggregate.
 * @returns {Promise<number>} process exit code.
 */
async function main(args) {
  let mode = 'all'
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--mode' && i + 1 < args.length) mode = args[++i]
    else throw new Error(`gates: unknown argument ${JSON.stringify(args[i])}; only --mode <name> is supported`)
  }
  let config
  try {
    config = validateConfig(JSON.parse(readFileSync(CONFIG_PATH, 'utf8')))
  } catch (error) {
    console.error(`gates: invalid gates.json: ${error.message}`)
    return 1
  }
  const selected = config.modes[mode]
  if (selected === undefined) {
    const known = Object.keys(config.modes).sort().join(', ')
    console.error(`gates: unknown mode ${JSON.stringify(mode)}; known modes: ${known}`)
    return 1
  }
  const selectedGates = selected.map(id => config.gates.find(gate => gate.id === id))
  const envRaw = process.env.GATE_CONCURRENCY
  let maxActive = Math.min(availableParallelism(), selectedGates.length)
  if (envRaw !== undefined && envRaw !== '') {
    const parsed = Number.parseInt(envRaw, 10)
    if (!Number.isSafeInteger(parsed) || parsed < 1) {
      console.error(`gates: GATE_CONCURRENCY must be a positive integer, got ${JSON.stringify(envRaw)}`)
      return 1
    }
    maxActive = Math.min(parsed, selectedGates.length)
  }
  console.log(`gates: mode "${mode}" running ${selectedGates.length} gate(s) with ${maxActive} worker(s).`)
  const startedAt = performance.now()
  const results = await runGates(selectedGates, maxActive, gate => runGate(gate), (result) => {
    const seconds = (result.durationMs / 1000).toFixed(2)
    if (result.status === 'passed') {
      if (process.env.GATE_VERBOSE === '1') console.log(`gates: PASS ${result.gate.label} (${seconds}s)`)
      return
    }
    const stream = result.status === 'failed' ? console.error : console.log
    stream(`\n== ${result.status.toUpperCase()} ${result.gate.label} (${seconds}s) ==`)
    stream(`command: ${result.gate.command.join(' ')}`)
    stream(`outcome: ${result.reason ?? 'unknown'}`)
    if (result.output.length > 0) process.stderr.write(result.output)
  })
  const seconds = ((performance.now() - startedAt) / 1000).toFixed(2)
  const passed = results.filter(r => r.status === 'passed').length
  const failed = results.filter(r => r.status === 'failed').length
  const skipped = results.filter(r => r.status === 'skipped').length
  console.log(`\ngates: ${passed} passed, ${failed} failed, ${skipped} skipped in ${seconds}s.`)
  const blocking = results.filter(result => result.blocking)
  if (blocking.length > 0) {
    console.error('gates: blocking outcomes:')
    for (const result of blocking) {
      console.error(`  - ${result.status.toUpperCase()} ${result.gate.label} (${result.reason ?? 'unknown'})`)
    }
  }
  return blocking.length > 0 ? 1 : 0
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.argv.slice(2))
}
