# Agent Note: localize defensive-patterns

Status: proposed

## Problem

`docs/defensive-patterns.md` carries two patterns inherited from the upstream distillation whose motivating scars live upstream, not here: "report orthogonal outcomes" is stated over `timedOut`/`signal`/`exitCode` — this repository ships no timeouts — and "teardown must reach quiescence" speaks of closing listener registries before killing — no shipped mechanism owns listeners. The file violates its own admission rule ("add a pattern only with the failure that motivates it — a pattern without a scar is speculation"). Evidence: added in the seed commit `07d84c5`, never modified since; zero inbound references (only the budget entry and its own zh pair link to it). Meanwhile two genuinely earned local scars live only in code comments, unrecorded in the tier built for them. A second dead surface: `expect_match` in `scripts/lib.sh` has zero bash consumers while its pwsh twin `Expect-Match` is used by the signal test — a twin-asymmetric helper.

## Proposal

Rewrite the pair around local scars. Keep the orthogonal-outcomes pattern restated on the shipped split (exit code and signal name reported independently — scarred by the exit-code-to-signal mapping and the kill -9 scheduler tests). Drop the teardown-quiescence pattern (nothing local owns it). Add the two earned patterns: declarations inside a bash function are local unless declared `-gA` (scar: results vanished when `run_gates` returned, crashing the scheduler), and a persistent IFS containing a control character corrupts quoted array expansions (scar: bash 5.1 exploded `"${arr[@]}"` into characters; worked around with inline IFS in `gates.sh`). Remove the dead `expect_match` helper from `lib.sh`; the pwsh `Expect-Match` stays, asymmetry resolved by usage, not by symmetry for its own sake. The budget ceiling ratchets to the rewritten size in the same change.

## Alternatives considered

Deleting the file outright (rejected: the exit/signal pattern is locally scarred, and the two bash scars are exactly the class this tier exists to carry); keeping the inherited patterns as distillation credit (rejected: the file's own header forbids scarless patterns, and inherited scars mislead readers about what this repo ships); moving the bash scars into the owning decision notes only (rejected: notes own decisions, the patterns file owns recurring rules of thumb — different tiers); keeping `expect_match` for twin symmetry (rejected: symmetry of verifiers is the contract, not symmetry of test helpers).

## Acceptance criteria

Every pattern in the rewritten file names a mechanism this repository ships and a failure that actually occurred in it; `lib.sh` loses `expect_match` with every suite green on both shells; the zh pair is re-confirmed in the same change; the budget entry ratchets down to the new word count; a reference scan shows only honest inbound links or none.

## Risks

Restating scars from memory invites change narration; the trim-cot-leakage skill governs the rewrite. Dropping the quiescence pattern loses the upstream lesson if a listener-owning mechanism ever lands here — reintroduce it with that mechanism's first real failure.
