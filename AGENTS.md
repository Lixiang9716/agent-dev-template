# AGENTS.md — standing orders

English | [中文](AGENTS.zh.md)

Rules for agents and humans working in this repository. They supplement, never replace, the gates: a rule that can be mechanically checked is a gate, and this file links to it. These orders are language-agnostic on purpose — they govern the process, not the product code.

1. **Gates over prose.** Any promise that can be checked by a command becomes a gate in `gates.json`. A convention that cannot be checked belongs in review, not in wishful writing.
2. **Every non-trivial change carries an Agent Note in the same PR.** A note records the decision, the alternatives it beat, and the consequences — the why that code and docs cannot carry. Update the owning note in the same change that alters the shipped facts.
3. **Prove each gate rejects an invalid case.** A guard only guards if the regression actually fails it. Every verifier ships with tests that demonstrate rejection; `scripts/gates.test.sh` / `scripts/gates.test.ps1` are the pattern.
4. **Fail loud, never silently skip.** Unknown values, malformed configs, and missing referents abort with the offending name. A misconfiguration discovered late is a defect now.
5. **One home per fact.** Facts live in exactly one tier; elsewhere, link. See [docs/tiers.md](docs/tiers.md).
6. **Docs stand at HEAD.** State present behavior; no change narration ("used to", "no longer"), no citations of uncommitted drafts, no reviewer-addressed justification. A reader with no access to any session or PR thread must resolve every reference.
7. **Bilingual pairs merge whole.** A PR never lands one language of a pair without the other two files; re-confirm with `bash scripts/verify-translation-pairing.sh --write <path>` (pwsh twin: `-Write -Path <path>`) in the same change.
8. **Respect the budget.** Word ceilings in `scripts/doc-budgets.json` ratchet down. Raising one is a deliberate act argued in the PR.
9. **Select the smallest sufficient check set.** Run `bash scripts/change-scope.sh --base <verified-ref>` (pwsh twin: `-Base <verified-ref>`) and pick gates by touched surface; never reflexively run the full aggregate. CI owns exhaustiveness.
10. **Archived notes are frozen.** Never edit, move, or delete a sealed note; supersede it with a new note that links back.
11. **Grow the plane.** The governance plane is a floor, not a ceiling. When a defect class recurs, write the postmortem and distill its guardrail into a gate; when a convention is enforced by hand a third time, make it a skill; when a prose promise becomes checkable, promote it to a gate. Anchor every new fact to its one tier home — the trigger table lives in [docs/architecture.md](docs/architecture.md).
