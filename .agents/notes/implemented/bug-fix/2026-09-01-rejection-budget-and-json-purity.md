# Agent Note: rejection-case budget and the --json purity contract

Status: implemented

## Problem

Two sharp edges in the freshly shipped wish round. Project rejection
cases carried a 120-second timeout — better than hanging forever, but a
runaway case (sleep 300) could still hold the default-mode self-test (and
therefore a CI job) hostage for two minutes before failing. And `gov run
--json` had one leak: the `--base` selection's "scope vs ..." line printed
to stdout ahead of the JSON array, so a consumer piping to jq saw human
text first (the other selectors were already pure — the emit routing
worked; this one print sat outside it).

## Decision

Each rejection case gets a 10-second budget (D26): overruns fail as
`(timed out after 10s)`, named, and the run continues — a rejection proof
is small by nature, and the budget is documented in the rejections README
the init injects. The --json contract is now "stdout carries exactly one
JSON value" with no exception: the scope line moved to stderr under
--json, and a parametrized test parses stdout as JSON across every
selector (default, --mode, --every-gate, --gate, --base) so future prints
cannot quietly leak back. duration_ms was already in the 0.7.0 records —
the reporter's wish 7 needed no change.

## Alternatives considered

- A configurable budget — rejected: fixed 10s plus documentation covers
  the real cases; a knob serves exceptions that should not exist.
- A 3s budget — rejected: cases that git-init scratch repositories can
  false-red on slow CI runners.

## Consequences

A runaway rejection case now costs its own 10 seconds, not the job's;
JSON consumers can pipe straight to jq under any selector, with the
purity contract regression-locked.
