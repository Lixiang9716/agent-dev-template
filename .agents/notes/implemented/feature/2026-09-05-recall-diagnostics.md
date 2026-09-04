# Agent Note: recall misses are diagnosable — corpus statement, per-term counts, --any

Status: implemented

Related: D18 (recall's read-side definition — strict AND, exit 1), D32 (shared decisions loader), D19 (skills ship byte-identical), issue #148

## Problem

Before starting work in an adopter repo, the recall-first skill ran four
probes (`gov recall 效用 utility 归因`, `landmark`, `聚类 发现`,
`多模态`) — every one exited 1 with a single line. The caller could not
distinguish three very different situations: the corpus genuinely lacks
the term; one term of the AND fails while others hit; or the query is
aimed at the wrong corpus entirely (recall's boundary — which notes,
whether the whole decisions file or only `## Dn` entries, whether
postmortems count — is invisible from outside). The skill's contract
says exit 1 means "try the other term", but with zero diagnostics each
retry is a blind guess, so agents either spam retries or give up early.

## Decision

`gov recall` answers all three questions (#148):

- **Corpus statement, every invocation** — one stderr line stating the
  per-class counts of what was searched: notes (implemented/archived
  file counts), decisions (entry count and source path via the D32
  loader — `decisions 0 (no source)` when absent), postmortems (file
  count). Context goes to stderr so stdout's ranked hits stay the first
  thing a caller reads; the statement fires on hits too, making the
  boundary visible before a miss ever happens.
- **Per-term hit counts on a miss** — after the existing
  `recall: no match for ...` line (stdout, where the miss already
  lives), one `per-term hits: 效用: 0 / utility: 2 / 归因: 0` line
  counting entries containing each term anywhere. A zero says "the
  corpus lacks it"; a nonzero beside a miss says "the AND failed". When
  some term would hit alone, the block names the escape hatch inline
  (the pairing gate's inline-fix-command pattern). No machine consumer
  parses recall stdout — `gov review` assembles its dossier from the
  module's functions, not its output — so extending the miss block on
  stdout breaks nothing.
- **`--any` relaxed mode** — ranks entries containing *some* terms by
  terms matched, then by where they hit, then the F4 lifecycle/path
  order; exit 0 when anything matches. An empty `--any` result still
  exits 1 with the same diagnostics — fail loud (D18) is not relaxed,
  only the AND is. The strict AND stays the default.

The flag registry gains `--any` (the test_flag_registry pin forces the
help text and the table to move together), and the recall-first skill
(live copy and init template, byte-identical per D19) documents the new
outputs so agents read the diagnostics instead of guessing.

## Alternatives considered

- All diagnostics on stderr — the no-match line is already stdout
  (pinned by test) and the miss block is the answer to a failed query,
  not ambient context; splitting it across streams would re-fragment
  the very report the issue calls undiagnosable. Only the per-run
  corpus context, which must not push the ranked hits down, belongs on
  stderr.
- A `--json` output mode — no consumer exists today; it would add a
  second surface bound to D26-level purity rules for a need no caller
  has expressed. The skill reads lines fine.
- Restricting per-term counts to strict-match locations (all terms in
  title, or in one heading, or in body) — misleading as a diagnostic:
  the question on a miss is "does the corpus know this term at all",
  not "does it know it in a combinable place".
- Fuzzy or semantic matching instead of `--any` — D18 rejected semantic
  recall for this scale (deterministic, auditable, zero-dependency);
  `--any` keeps literal matching and only relaxes the conjunction.
