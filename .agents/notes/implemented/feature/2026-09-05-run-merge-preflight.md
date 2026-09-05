# Agent Note: run --merge — preflight the union of parallel branches before landing

Status: implemented

Related: D51 (this decision), D15 (gate selection by paths over a diff), D33
(scratch-fixture host safety: the three walls), D44 (verifiable run
receipts), D2 (exit-code vocabulary), D41 (flag vocabulary over new
subcommands), D46 (why "only trust PR CI" is not an answer)

## Problem

Users process work with several parallel agent branches. Each branch passes
every gate on its own tree, but the union is never tested before the merge:
text conflicts git catches, semantic collisions — each branch green, the
merge red — nobody catches, and the exposure lands after the merge, in the
tree that already shipped. Four independent reviews (concurrency
correctness, scheduler state machine, governance consistency, pragmatic
skepticism) converged on the same minimal machine: rehearse the merge
before it matters, in a scratch worktree, with gates running on every step
of the union. The layers beyond that minimum (locks, leases, scheduling
functions) are deferred by criterion (D51), not silently dropped.

## Decision

`gov run --merge <branch> [<branch>…] [--base <ref>]` ships in the runner:

- **Staged rehearsal** — a detached scratch worktree is created from the
  integration baseline (`--base`, default `origin/master`; a missing
  default is a named demand for an explicit flag, exit 2 — rule 5, never a
  guess). Branches merge in command-line order with
  `git merge --no-ff --no-edit`, and after every merge the gate DAG runs on
  that step's union tree, selected as D15's minimal sufficient set by the
  diff the step itself introduced (the previous step's tree sha, recorded
  after its gates ran, is the diff baseline; the first step diffs against
  the baseline commit). The last step's tree IS the full union, so every
  gate examines merged content.
- **Outcomes are D2's, no new codes** — 0: every step green, scratch
  cleaned, per-step summary printed. 1: a text conflict (named as
  `branch k (<name>) conflicts with already-merged set (<names>)`, with the
  conflicted files) or a red step (failed branch, already-merged set,
  failed gate names and first output lines) — the scratch worktree is KEPT
  and its path printed for inspection, later branches never run. 2: invalid
  config or ref, named before anything runs.
- **Host safety is D33's three walls, upgraded for a state-mutating
  command** — repository-resolving variables (GIT_DIR, GIT_WORK_TREE,
  GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY,
  GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_QUARANTINE_PATH) abort loudly
  (exit 2, variables named) BEFORE anything runs, instead of the scrub-
  and-announce self-test behavior: this command creates worktrees and
  merge commits, so an ambiguous domain is refused, not re-pointed
  silently. Every git call is pinned with `-C` to the caller's repo root
  (resolved once) or the scratch; the scratch must resolve
  `--show-toplevel` to itself before anything merges into it (toplevel
  guard); step subprocesses additionally get
  `GIT_CEILING_DIRECTORIES=<scratch parent>`. Acceptance tests pin the
  guarantee: before/after a preflight the host worktree is byte-identical
  (status clean, HEAD/refs/config unchanged). The preflight itself creates
  and unlinks no lock files (decision add's `.decision.lock` unlink race is
  a known defect this feature does not import); history and receipt
  ledgers keep their D32 anchoring — scratch runs record into the main
  checkout's gitignored `.gov/history`.
- **Receipts compose with the last step only, and that is stated** — with
  `--receipt`, the final step upgrades to the full matrix (every enabled
  gate) and records a D44 receipt bound to the union tree sha. The
  limitation is deliberate and written down: a per-step diff-scoped
  selection can never verify as "full evidence" (D44's verify demands
  selection kind `all`), so the receipt-bearing run is the union's full
  run; a landing that reproduces the content (a squash merge moves the
  commit sha, not the tree) then verifies via `gov receipt verify`. Without
  `--receipt` every step keeps the minimal per-step set.
- **Surface discipline** — `--merge` rejects `--mode`/`--gate`/
  `--every-gate`/`--json`/`--fail-fast`/`--verbose` (exit 2, named); the
  flag registry moves with the help text (test_flag_registry's pin);
  `--tag`/`$GOV_CALLER`, `--cost`, `--no-record` and `--config` forward to
  every step. Step invocations run the shipped `gates.py` with `--json`
  internally: stdout carries exactly one JSON array for the orchestrator's
  per-step summary, and the human report streams live on stderr — nothing
  is buffered away from the operator (D26's contract, reused).

Rejection proof: tools-family self-test case `test_run_merge_rejects_text_conflict`
(a real, subprocess-reproducible conflict — no fault injection, per the #24
lesson) plus tests/test_run_merge.py: each-branch-green/union-green with a
byte-identical host, the semantic-collision fixture (two branches insert
gates at opposite ends of gates.json — hunks separated by filler entries,
so the text merges cleanly and the loader rejects the duplicate id at step
2), the kept scene on conflict, the hostile-GIT_DIR refusal, the
missing-default-base demand, step scoping vs the receipt full matrix, and
the landed-union receipt verifying by tree sha.

## Alternatives considered

- **A separate merge-check subcommand** — vocabulary fragmentation:
  this is a run of gates with an orchestration wrapper, and D41 just
  established the precedent of extending an existing surface (`--staged`)
  over minting a second command for the same semantics.
- **Only trust PR CI** — D46's rejected section already names the hole:
  GITHUB_TOKEN pushes do not trigger CI, so a merge landing can reach
  master with no CI run at all; a preflight leaves machine-checkable
  evidence (a receipt) even when CI never fires.
- **Sleep-poll orchestration around plain `git merge` attempts** —
  unversioned coordination state, timing-dependent, and nothing about the
  union's gate status is recorded; the preflight is deterministic,
  ordered, and leaves a ledger trail.
- **The deferred layers (locks, leases, a schedule function, a queue
  service, CRDTs, head-of-line retry policies)** — all rejected with
  criteria in D51's 被否 section: they coordinate contention that does not
  exist yet, or depend on services the plane refuses to require. The
  staged rehearser is the layer that pays for itself today.
