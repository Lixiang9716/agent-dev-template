---
name: pre-push-checks
description: Use before pushing, force-pushing, or marking a PR ready for review, to select the smallest gate set that covers the outgoing diff without reflexively running the full repository aggregate.
---

# Pre-push checks

CI owns exhaustiveness; this skill owns coverage of the outgoing diff at the lowest cost.

1. Establish the verified base. Use the ref you actually based on (`main`, or the parent PR's head in a stack). Never guess or fetch a base — `change-scope` refuses to.
2. Report the scope (bash port shown; the pwsh twin is `pwsh -File scripts/change-scope.ps1 -Base <verified-ref>`):

   ```sh
   bash scripts/change-scope.sh --base <verified-ref>
   ```

3. From the reported path classes, pick gates:
   - anything under `scripts/` or `gates.json` → `self-test`, plus `script-pairs` when a twin script changed (re-confirm with `verify-script-pairs --write` in the same change), plus `vocabulary` when `scripts/vocabulary.json` changed (the gate's own manifest)
   - anything under `.agents/notes/` → `notes`, and `archive` when `archived/` changed
   - any `.md`/`.zh.md`/`.i18n.yaml` → `pairing`, `budgets` when ceilings or budgeted docs changed, `links` when Markdown targets or headings changed, `vocabulary` when the scanned docs surface (AGENTS.md, AGENTS.zh.md, docs/*.md) is touched
   - product-plane paths → the slots you declared for that surface (test, lint, typecheck)
4. Run the chosen mode or the individual commands. If `unstaged` or `untracked` is non-empty, either include those files in the commit or exclude them from your reasoning — never assume they are part of the diff.
5. Report exactly which commands ran and their outcomes. Do not repeat a passing check to feel safe.
