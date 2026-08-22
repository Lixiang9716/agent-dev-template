---
name: pre-push-checks
description: Use before pushing, force-pushing, or marking a PR ready for review, to select the smallest gate set that covers the outgoing diff without reflexively running the full repository aggregate.
---

# Pre-push checks

CI owns exhaustiveness; this skill owns coverage of the outgoing diff at the lowest cost.

1. Establish the verified base. Use the ref you actually based on (`main`, or the parent PR's head in a stack). Never guess or fetch a base.
2. Report the scope:

   ```sh
   gov change-scope --base <verified-ref>
   ```

3. From the reported surfaces, pick gates:
   - `governance` (gates.py, verify_*, self_test.py, gov.py, change_scope.py) → `self-test`
   - `notes` (`.agents/notes/`) → `notes`
   - `docs` (`.md`/`.zh.md`/`.i18n.yaml`) → `pairing`
   - product-plane code → the slots you declared for that surface (test, lint, typecheck)
4. Run the chosen mode or the individual commands. If there are unstaged or untracked files, either include them or exclude them from your reasoning — never assume they are part of the diff.
5. Report exactly which commands ran and their outcomes. Do not repeat a passing check to feel safe.
