# Agent Note: cost dimension in .gov/history — caller-reported ledger shape (`gov trend --cost`)

Status: implemented

Related: D45 (this decision), D42 (the caller-tag vehicle it rides on), #126

## Problem

Multi-agent repositories burn shared metered resources (LLM tokens/calls)
inside runs the governance plane otherwise observes, but the history
ledger records gate durations and (since D42) the caller tag — and D44's
receipts bind a run to a commit — none of it carries cost. "What did
this milestone's LLM spend cost, per workstream, per agent?" is
unanswerable from the governance record: radiant tracks
bridge/adjudication LLM budgets in its own config/ledgers (#126's
evidence), every repo invents its own ad-hoc ledger, and cost attribution
has no common language `gov trend` could read.

## Decision

Govrail standardizes the LEDGER SHAPE and never meters anything itself —
the numbers stay caller-supplied by whatever tool ran the LLMs. `gov run`
gains optional `--cost unit=value,…` (env fallback `$GOV_COST`; units are
free-form tokens, values finite non-negative numbers; the flag wins over
env). It rides the history RUN line next to D42's `caller` key, and only
when supplied, so cost-unreported runs keep byte-identical history shape;
malformed input exits 2 naming the fragment (rule 5), checked before any
gate runs. `gov trend --cost` swaps the duration mover view for a
per-caller roll-up of every cost unit (window total plus early→late
split; `--base` splits all callers at the same commit date, reusing the
existing split machinery). Untagged cost-bearing runs group under
`(untagged)`; runs without a cost field simply don't appear; a malformed
cost field in history is named on stderr and skipped rather than silently
summed; a window with nothing reported prints the opt-in pointer instead
of reading like a roll-up of zero. `--cost` is mutually exclusive with
`--by-tag` (it already groups by caller) and with `--gate` (cost belongs
to the run, not a single gate) — both exit 2 naming the conflict.
Documented as D45 in docs/decisions.md and a bilingual cookbook recipe
(pair re-confirmed); the flag registry moved with the new flags.

## Alternatives considered

- Govrail metering tokens/calls itself (wrapping gate commands in a
  counter): rejected — metering belongs to the tool that runs the LLMs;
  a governance-side meter would need a new integration for every resource
  type and would double-count tools that already track their own spend.
- A fixed unit enumeration (hardcoded tokens/calls): rejected — units
  evolve with tools; free-form unit tokens validated as finite numbers
  already suffice for rolling sums, and new units need zero code here.
- Per-gate cost fields in the gate records: rejected — cost is an
  attribute of the run (who invoked the LLMs and when), not of any single
  gate; the run line is that layer, and the per-gate record shape stays
  pinned by existing tests.
- Folding cost into D42's `--by-tag` view: rejected — duration p50 and
  cost sums are different measures; mixing them crowds both the layout
  and the semantics, so each flag keeps one focused view.

## Consequences

Cost values are trusted caller arithmetic, validated only as finite
non-negative numbers — govrail can catch a malformed ledger entry but
cannot vouch for the number itself; the ledger is attribution-ready, not
audited. Tools that never report keep today's behavior exactly.
