# Agent Note: template-first positioning

Status: implemented

## Problem

Whether the repository should become an installable product (CLI, compiled binary) or stay a derived-from template kept reopening — an installer shipped and was reverted, a compiled-binary proposal was weighed — each round consuming design effort for hypothetical users.

## Decision

The repository is a self-use-first governance template, distributed by GitHub template derivation (or clone and re-init). Upstream DeepSeek Harness is the product; this repo is the portable governance plane others inherit, so nothing ships here that a derived project would have to delete. Every change passes the self-use-first filter. **This stance expires at:** 20 external derivations, or twin-port drift complaints from 3 distinct adopters. When either fires, extract the governance verifiers into a CLI tool, supersede this note with the extraction decision, and delete this clause.

## Alternatives considered

A compiled-binary CLI (rejected: derived projects would depend on the template's release channel forever, and governance must stay readable text an agent can audit); template plus tool side by side (rejected: double maintenance for a solo maintainer); keeping the repo private (rejected: sharing as a template costs nothing beyond what self-use already pays).

## Consequences

The positioning question is settled by trigger, not by opinion — the sunset clause above reopens it exactly when evidence exists, making re-litigation unnecessary. Distribution-side investment stays frozen until the trigger fires.
