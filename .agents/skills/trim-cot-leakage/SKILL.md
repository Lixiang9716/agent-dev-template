---
name: trim-cot-leakage
description: Use when auditing or fixing prose that reads like a leaked reasoning transcript — session-only citations such as (decision N) or audit codes, change narration like "used to" or "no longer", stack or review vantage ("a later PR", "rejected in review"), reviewer-addressed justification, or hedged planning residue in docs, notes, or comments.
---

# Trimming chain-of-thought leakage

Leakage is prose whose vantage is the authoring session rather than the repository: it cites artifacts only that session could see, narrates the change instead of the state, or argues with a reviewer who has left. AGENTS.md rule 6 owns the principle; this skill is the method.

## The one test

For every suspect passage ask: **could a reader at HEAD, with no access to any session transcript, PR thread, or uncommitted draft, resolve every reference and verify every claim?** If no, restate the surviving facts from the repository's vantage and delete the rest. If yes, it is not leakage — though on current-state surfaces a resolvable change story still violates rule 6.

## Procedure

1. Mark suspect passages: session-only citations, change narration, control-flow narration ("first we", "then this calls"), reviewer-addressed clauses, hedged planning residue.
2. Split each passage into repository facts versus transcript. Restate each fact so it stands at HEAD; cite only committed, reachable artifacts.
3. Delete what carries no repository fact outright — an audit code, a change narration, a review exchange. Never delete alone when a factual clause survives inside.
4. Re-run the pairing gate when a bilingual pair changed; re-record in the same change.
