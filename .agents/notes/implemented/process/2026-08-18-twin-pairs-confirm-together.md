# Agent Note: twin pairs confirm together

Status: implemented

## Problem

Seventeen script twins carry one governance contract, and nothing mechanical connected them: a fix landing on one side with its twin forgotten would surface only if a test suite or a platform-specific CI leg happened to expose it — the variant-selection defect reached Windows exactly that way. The positioning note's drift-complaint trigger watches for symptoms; no gate watched the cause.

## Decision

`scripts/script-pairs.json` pins the git blob hash of both sides of every discovered pair (any `scripts/<name>.sh` with a sibling `<name>.ps1`). The `script-pairs` gate fails on a drifted side, an unconfirmed new pair, or a stale entry, naming the offender; re-confirming with `--write` in the same change is the explicit "the twin was considered" acknowledgment — covering behavior fixes (touch both sides) and shell-specific fixes (touch one, re-record). The gate runs in `all` and `quick` modes and in the pre-commit hook, so drift fails at commit time, not at review. Hash freshness is all it checks: behavioral equivalence stays owned by the per-port test suites and the CI matrix.

## Alternatives considered

Per-pair sidecars modeled on `.i18n.yaml` (rejected: seventeen manifest files of noise for one fact each); structural signature comparison across ports (rejected: bash and pwsh share no textual structure — the bilingual gate's signature idea does not transfer to code); banning shell-specific one-sided fixes (rejected: they are legitimate, as the bash-5.1 IFS workaround proved — they just owe a re-confirm).

## Consequences

Every scripts-touching change that alters a twin owes a `--write` in the same commit — visible in the diff, mechanical to satisfy. New pairs must be consciously added; deletions refresh the manifest. The write refreshes to current reality and reports what changed, so the manifest can never silently disagree with the tree.
