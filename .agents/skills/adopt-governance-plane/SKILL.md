---
name: adopt-governance-plane
description: Use when working in a freshly derived repository from this template (a new clone or GitHub template derivation) to walk the mechanical adoption sequence — install hooks, run the smallest sufficient gate set, calibrate the n=1 manifests, write the first Agent Note, and pass the first pre-commit and pre-push.
---

# Adopt the governance plane

The plane works on day one; this skill makes the day-one sequence mechanical. The full guide lives in [docs/adoption.md](../../../docs/adoption.md). Work through the steps in order; each step ends with a verifier that must pass before the next begins.

1. **Install the local hooks** (one command, no dependencies):

   ```sh
   sh scripts/install-hooks.sh
   ```

   Confirm with the printed "installed: pre-commit, pre-push, merge driver" line.

2. **Prove the foreign soil.** Run the adoption proof once; it copies the repository, runs every gate, commits through the pre-commit, and injects four mutations that must all be rejected:

   ```sh
   bash scripts/adopt-plane.sh          # pwsh host: pwsh -File scripts/adopt-plane.ps1
   ```

   A PASS summary means the plane works in this repository as derived. Keep it green for the life of the project.

3. **Select the smallest sufficient check set** for whatever you touch, never the full aggregate reflexively. Report the touched surface first:

   ```sh
   bash scripts/change-scope.sh --base <verified-ref>
   ```

   Pick gates by path class per the pre-push-checks skill: scripts and gates.json → `self-test` (plus `script-pairs` after a twin edit); notes → `notes`; any doc pair → `pairing`, `budgets`, `links`, `vocabulary` as relevant.

4. **Calibrate the four n=1 manifests** before the first PR, each edit followed by its gate in the same change:

   - `scripts/vocabulary.json` — banned words and exemptions; re-run the vocabulary gate and its tests.
   - `scripts/doc-budgets.json` — word ceilings; raising one is a deliberate act argued in the PR.
   - `scripts/script-pairs.json` — twin hashes; re-confirm with `bash scripts/verify-script-pairs.sh --write` in the same change.
   - `AGENTS.md` — the inherited standing orders; keep the gates-over-prose spine.

5. **Write the first Agent Note** for the first real change, following the tree's existing shape (the layout is the index): `{lifecycle}/{class}/yyyy-mm-dd-topic.md` with the three-line header and the lifecycle's required sections. Run `bash scripts/verify-agent-notes.sh` before committing.

6. **First commit and first PR.** After any doc edit, re-record the pair: `bash scripts/verify-translation-pairing.sh --write <doc>.md`. Commit — pre-commit runs the local gates — then run the chosen gate set once more before pushing; pre-push runs the quick mode, and CI owns the exhaustive matrix.

If `scripts/adopt-plane.sh` fails on this repository, diagnose and fix before doing anything else: the proof's failure names the stage (pairing, vocabulary, notes, script-pairs) that is broken on foreign soil.
