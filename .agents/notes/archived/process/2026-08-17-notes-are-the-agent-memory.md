# Agent Note: notes are the agent memory

Status: implemented

## Problem

Agents and humans re-litigate settled decisions when the reasoning — and what it beat — lived only in sessions, chats, or heads. The failure mode is not forgetting the decision; it is reopening it without the counterarguments.

## Decision

Every non-trivial change carries a note in the same PR. The five-section skeletons are enforced mechanically: implemented notes state what is (Decision, Consequences) and are forbidden proposal-era headings; every lifecycle requires `Alternatives considered`. Fully superseded notes archive under a sha256 seal and are never edited again — supersession moves forward with links.

## Alternatives considered

Free-form decision records (rejected: without enforced sections, alternatives go unwritten first and the format erodes); a wiki or issue tracker as the home (rejected: decisions must version with the code they explain, in the same PR and the same diff).

## Consequences

The notes tree is grep-able institutional memory that CI validates. Writing a note costs minutes during the PR and saves a re-litigation later; the verifier makes skipping it impossible to merge.
