# Agent Note: adoption proof and first-day guide

Status: implemented

## Problem

The template's derivation promise lived in prose: README told a derived project to run gates and install hooks, but nothing proved the plane actually holds on foreign soil — a fresh copy of the repository, git init, zero installation. A broken gate, or a gate that silently accepted a mutation, would surface only when some adopter hit it. First-day guidance was scattered README prose with no checklist an agent could execute mechanically, and no skill (rule 11) and no mechanical evidence behind it.

## Decision

- `scripts/adopt-plane.sh` + `scripts/adopt-plane.ps1` ship as a twin-port open-loop adoption proof. Each port copies the whole repository (excluding `.git`, local editor state `.zcode`, and `scripts/adopt-plane.test.*` — the recursive guard re-checks the result) into a temporary directory, runs `git init` with a local identity, then proves three facts there: (a) `gates.sh --mode all` is green with zero installation (pwsh port: `gates.ps1 -Mode all`); (b) `sh scripts/install-hooks.sh` installs and one real `git commit` passes the installed pre-commit; (c) four injected mutations are rejected loudly, each naming its stage — a one-sided README.zh.md edit (pairing), a banned declaration-state word in docs/adoption.md (vocabulary), a malformed note under `.agents/notes/` (notes), and a twin-script edit without a manifest refresh (script-pairs) — and the pairing and vocabulary mutations are additionally rejected by the pre-commit hook. The CLI is `--scaffold <dir>` (construct only), `--verify <dir>` (verify a constructed tree, then remove it), and `--clean` (instance-scoped); no arguments run the full scaffold-and-verify cycle. `--scaffold` writes a provenance marker (`.adopt-plane-provenance`) that `--verify` requires: a directory that cannot prove it was built by this script — the repository root included — is rejected and never removed. The verify phase also asserts the gate-invisible plane files (`.gitattributes`, `.gitignore`) survived the copy; their loss is a named failure.
- Output is deterministic line by line — fixed ASCII stage lines only, no absolute paths, timestamps, raw git output, or counts — so the script-pairs probe channel can compare the twin outputs after timestamp@v1/whitespace@v1 normalization. Every foreign gate and git command's output is captured and mapped to PASS/FAIL/REJECT lines. Cleanup is trap-based in the bash port and try/finally in the pwsh port; the repository itself is never modified.
- The temp namespace is per-instance: every invocation owns a unique private transient root under the temp root, removed on every exit path, so concurrent executions (the self-test and probe lanes run adopt-plane suites in parallel) cannot delete each other's scaffolds; `--clean` removes only its own instance's root, never a foreign one.
- The scaffold's copied `scripts/script-pairs.json` drops the adopt-plane.test entry and the adopt-plane probe declaration: the test files are excluded from the scaffold by design, and a probe without its test suites would fail the pair gate on foreign soil.
- `scripts/adopt-plane.test.sh` + `.ps1` are the rejection tests for the proof itself (rule 3): the full run passes with deterministic output, each mutation injected into a fresh scaffold fails the verify run naming its stage, and every temporary directory is cleaned up (hermetic contract).
- `docs/adoption.md` (plus `docs/adoption.zh.md` and `docs/adoption.i18n.yaml`) is the first-day guide: what the plane gives you, the four n=1 manifests to calibrate (vocabulary.json, doc-budgets.json, script-pairs.json, AGENTS.md), the notes tree as inherited seed memory with the first-note shape, and the derivation-to-first-PR checklist. README.md and README.zh.md gain a "First day" section linking it, and `.agents/skills/adopt-governance-plane/SKILL.md` turns the same route into an agent-executable skill.

## Alternatives considered

- Extracting the governance verifiers into a CLI tool (rejected: the template-first positioning sunset clause is frozen — it expires at 20 external derivations or 3 distinct-adopter twin-port drift complaints; this change builds the evidence channel that trigger will fire on, it does not reopen the positioning decision).
- A docs-only first-day guide (rejected: prose cannot show that a gate rejects on foreign soil — the open-loop proof is the mechanical form of the same promise, per the gates-over-prose axiom).
- An installer (rejected previously — see implemented/architecture/2026-08-18-template-ships-no-self-installer.md: derived projects must start clean, and distribution rides GitHub's template mechanics).
- A minimal synthetic scaffold instead of the full copy (rejected: a hand-built miniature tree could pass while the real template tree fails — the whole point of foreign soil is that it is the real tree, exactly what a derivation copies).

## Consequences

- The n=1 evidence channel exists: the template is its own first adopter, and the proof's green run is the recorded baseline (rule 3's tests re-run it); the sunset clause's triggers now have a measurement lane.
- README.md's word ceiling rose deliberately (rule 8) from 481 to 510 to make room for the "First day" section; `docs/adoption.md` gets a new budget entry of 650 — a new home, not a raise.
- The recursive guard is structural: adopt-plane.test.* can never appear in the scaffold, so the proof cannot re-run itself inside itself on foreign soil.
- Two data-destruction guards shipped after review: a refused scaffold target (a non-empty directory or a regular file) is left exactly as found — the build's cleanup removes only what the build created — and `--verify` requires the provenance marker, so the repository root or any lookalike is rejected and never removed. The verify phase additionally asserts the gate-invisible plane files (`.gitattributes`, `.gitignore`) survived the copy; their loss is the fifth rejection case of the battery, beyond the four injected mutations.
- The temp namespace is per-instance: each invocation owns a unique `adopt-plane.*` root under the temp root, `--clean` is instance-scoped, and the test suites scope their own private TMPDIR — concurrent executions (the self-test and probe lanes of the gates aggregate, parallel CI legs) cannot delete each other's scaffolds or trip each other's residue assertions. `.zcode/` is gitignored (local editor state) and excluded from the scaffold copy, so a derivation never inherits it.
- The proof is intentionally heavy: the full run executes the foreign gates all (about a minute in the bash port, about two in the pwsh port), and the test suite runs the proof plus the five rejection-case verifies (about five minutes in the bash port, eight in the pwsh port); CI's four matrix legs run it through the existing self-test and probe lanes, adding roughly 16 minutes per leg — no new CI wiring.
- Foreign-soil audit outcome: every existing test suite (*.test.sh / *.test.ps1, except adopt-plane.test.*) runs inside the scaffold through the foreign self-test gate during every proof run. One pre-existing hermeticity defect was found and fixed in this change: gates.test.sh's subshell-wrapped scheduling scenarios lost their `GATE_TMPDIR` (set inside the command substitution), so the outer `rm -rf` no-oped and each run leaked three empty temp dirs into the temp root — invisible until the adoption suite's per-suite residue assertions counted them. The scenarios now clean up via a subshell EXIT trap; no other suite needed changes.
- Design note for future changers: the vocabulary mutation also stales the pairing sidecar (every vocabulary-scanned doc is part of a bilingual pair), so its pre-commit rejection is delivered by the pairing verifier — pre-commit has no vocabulary verifier; the vocabulary gate's own rejection is proven by the battery's direct gate run.

## Claims

- Claim: the full adoption proof passes end to end — foreign gates all green, hooks installed, a real commit through pre-commit, all four battery mutations rejected naming their stages, the gate-invisible plane files asserted, and zero residue left behind.
  - verifier: bash scripts/adopt-plane.test.sh and pwsh -File scripts/adopt-plane.test.ps1
  - coverage: the pristine full run, five per-mutation verify runs, instance-scoped --clean, and per-suite temp-root residue assertions
  - goal-link: AGENTS.md rule 3 (every verifier ships tests that demonstrate rejection)
- Claim: the twin ports of the proof emit line-identical deterministic output, comparable by the script-pairs probe channel.
  - verifier: scripts/adopt-plane.test.ps1 compared against scripts/adopt-plane.test.sh through the verify-script-pairs probe (probe=test on the adopt-plane pair, GATES_FORCE_PROBE=1 in CI)
  - coverage: both ports' full runs and all five mutation verifies, normalized by timestamp@v1 and whitespace@v1
  - goal-link: AGENTS.md rule 7 (twin ports confirm together)
- Claim: the existing governance test suites run on foreign soil, so the scaffold's self-test gate passes inside every proof run.
  - verifier: bash scripts/adopt-plane.test.sh (its full run executes the foreign self-test gate, which runs every copied *.test.sh)
  - coverage: ci, change-scope, gates (its GATE_TMPDIR leak fixed in this same change), lib, verify-agent-notes, verify-md-links, verify-script-pairs, verify-translation-pairing, verify-vocabulary test suites in the scaffold
  - goal-link: AGENTS.md rule 9 (the smallest sufficient check set; CI owns exhaustiveness)
