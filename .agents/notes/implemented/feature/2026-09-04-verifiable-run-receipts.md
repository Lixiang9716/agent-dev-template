# Agent Note: verifiable run receipts — "an agent verified this" becomes checkable

Status: implemented

Related: D44, issue #124, D42 (caller tag the receipt reuses), D28/D29 (append-only history), D32 (worktree history anchoring)

## Problem

Agent-authored PRs increasingly carry a hand-written verification
paragraph — "reviewer re-ran the gates: 7/7". That is a self-report:
nothing lets a downstream reader distinguish "the gates actually ran
green on this exact tree" from "the author says so". The runs DO land in
`.gov/history/gates.jsonl` (D28), but those records bind no commit, no
tree, and no caller — the claim is unfalsifiable without re-running
everything. As the count of agent-filed PRs grows, unverifiable
verification becomes the trust bottleneck of the governance plane.

## Decision

`gov run --receipt` appends a tamper-evident receipt of the run to
`.gov/history/receipts.jsonl`: `{v, id, ts, commit, tree, dirty, tag,
selection, gates[], prev, hash}` where `hash` = sha256 over the
canonical JSON (sorted keys, compact) of every other field, and `prev`
chains to the previous record's `hash` (`GENESIS` first). Editing,
deleting, or reordering any historical line breaks every later link —
`gov receipt verify` exits 2 naming the line, never coasts (rules 5/6).
`gov receipt verify <commit>` answers exactly the issue's question —
"was a full, clean, green run recorded against this exact tree?" — and
exits 0 printing the receipt id(s), which PR bodies can cite instead of
prose. "Full" means the selection covered every enabled gate (an
explicit mode counts when it names them all; a `--gate`/`--base` run is
recorded with its narrowing in #119's `selected_by` vocabulary and
refused as full evidence — proven by a tools-family self-test case);
"clean" means no tracked file differed from the commit at run time
(untracked ledgers under `.gov/history` do not dirty a receipt; tree
state is measured before any ledger write so a tracked history file
cannot dirty its own receipt); "green" means every gate PASS, advisory
failures included. The receipt also binds the commit's TREE sha: a
squash-merged PR lands with a new commit sha but the same tree, and
verification matches on the tree too. The receipt's `tag` IS the run's
caller tag (`--tag`/`$GOV_CALLER`, D42) — no second tagging flag. A
single receipt cited on its own (pasted into a PR body,
`--record '<json>'`) still self-verifies — its hash covers its own content. Receipt
recording is keyed off the flag, so runs without `--receipt` behave
exactly as today; failures are recorded as faithfully as passes, since
the receipt is the run's confession, and only verification decides what
counts as evidence. The chain is deliberately keyless (the issue's own
trade): it proves internal consistency and binding, not authorship —
real signatures are future work. Rejection proof: two tools-family
self-test cases (forged record → exit 2 "hash mismatch"; partial run →
exit 1 "partial run") plus tests/test_receipt.py.

## Alternatives considered

- Signing receipts with a key (GPG/cosign/HMAC) — deferred: the issue
  explicitly prices a plain sha256 chain as tamper-evidence "without
  key management"; key distribution across agent identities is its own
  governance problem, and blocking the checkable-today version on it
  would leave prose as the only evidence for another release cycle.
- Reusing gates.jsonl with richer records — rejected: that ledger is
  the trend datasource (D28), gitignored, and consumed by `gov trend`;
  overloading it with binding semantics would fork the meaning of a
  line per reader. A separate receipts file keeps "what ran" (metrics)
  apart from "what this run vouches for" (evidence).
- Binding only the commit sha — rejected: squash merges and rebases
  move the commit sha while keeping content; the merged tree could not
  be machine-checked against a pre-merge receipt. The tree sha is what
  "this exact tree" means (the issue's own acceptance wording).
- A `--receipt=<tag>` tagging flag of its own — rejected: D42 just
  landed `--tag`/`GOV_CALLER` as the single caller vocabulary; a second
  tagging flag is exactly the vocabulary fork D41 rejected for the
  pre-commit hook. The receipt carries the run's caller as-is.
- Trusting the PR body's prose with a convention gate — rejected: rule
  1 puts anything a command can check into a command; prose is what
  this feature replaces, not extends.
