# Documentation tiers: one home per fact

English | [中文](tiers.zh.md)

Each fact has exactly one home — the tier whose job it is. Everywhere else links there. When two places need the same fact, one of them is wrong on the day they drift.

| Fact | Home |
|---|---|
| Standing orders for agents and humans | [AGENTS.md](../AGENTS.md) |
| How the governance plane works | [architecture.md](architecture.md) |
| Why a decision was made, what it beat | `.agents/notes/` (Agent Notes) |
| Why a failure happened, why guardrails missed it | `docs/postmortem/` |
| Bilingual pairing contract | [i18n/README.md](i18n/README.md) |
| Word ceilings | `scripts/doc-budgets.json` |
| Gate definitions and modes | `gates.json` |
| Product code knowledge | the product plane's own docs, owned by you |

A new fact first picks its tier, then lands once. Budgets hold each home to a size a reader can actually finish.
