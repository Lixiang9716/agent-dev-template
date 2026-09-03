# What's new — govrail highlights, per release

Usage-oriented highlights (the CHANGELOG carries commits; this carries
how to use them). `gov whatsnew [--since <version>]` prints from here.

## 0.12.3 — provenance and external references

- `gov init --upgrade` distinguishes WHO moved: UPSTREAM MOVED (your
  copy is untouched since adoption — `--adopt <rel>` takes the new
  template safely) vs BOTH MOVED (merge by hand) vs legacy ambiguity
  (labeled). The manifest now records each adopted template's hash.
- `gov init --adopt <file> --preview` shows what would land and writes
  nothing; adopt discloses its manifest updates.
- `govrail:D<n>` is the legal external decision reference: citing the
  tool's decisions no longer reads as a dangling local D, and
  `gov note new --ref govrail:D24` records it as external.

## 0.12.2 — host integrity

- The self-test's scratch fixtures run behind three independent walls
  (env scrub + GIT_CEILING_DIRECTORIES + a toplevel guard that aborts
  loud on any escape): a fixture can no longer configure, stage, or
  commit into any repository but its own — verified byte-identical
  hosts from linked-worktree runs, including under hostile GIT_*
  leaks (#24).

## 0.12.1 — worktrees, hook context, blast radius

- The pre-push hook now selects gates from the push range (docs-only
  pushes skip the suite) and runs under a scrubbed environment — the
  hook-context self-test failures are gone (#20/#22). UPDATE your
  hook: it is a modified-file adoption (see gov init --upgrade).
- Bare `gov verify-pairing --write` touches only out-of-sync pairs —
  green sidecars keep the confirmation they earned (#16).
- The decisions source is configurable (`.gov/decisions.json` —
  sections or markdown-table format); with no source while notes
  reference D-refs, verify-decisions answers REFUSED, not ok (#17).
- `gov doctor` is worktree-aware and names manifest/package version
  drift (#15/#19); run history records into the main checkout, not per
  worktree (#23); path-scoped gates say `n in change scope` — zero is
  visibly not a scan (#21); the coverage ledger names executed cases
  that lack a `# gate:` declaration instead of nagging (#18).

## 0.12.0 — usability round: examples, cookbook, discovery

- `gov whatsnew` — this command: what arrived since your init version
  and how to use it. `gov init --upgrade` now points here when the
  package is newer than your manifest.
- `docs/cookbook.md` in the repository — task-oriented recipes (pairing
  went red, add a gate end-to-end, review a PR, read a trend mover).
- `examples/demo-project` is now a living specimen: every feature
  exercised (rubric, rejection cases with `# gate:` declarations,
  surfaces.json, decisions with review-by, paired docs).
- Reports point to their own next steps: the coverage ledger names the
  case file format; trend movers say what a mover means.

## 0.11.0 — review workbench, pairing round-trip, coverage ledger

- `gov review --base <ref> --grade` — dossier then interactive rubric
  grading (p/f/s/q); emits the review verdict block. Failures exit 1.
- Pairing drift errors carry the fix command inline and the sidecar
  records which side moved in which commit after which confirmation.
- `# gate: <id>` in a rejection case's first five lines feeds the
  self-test coverage ledger (`gate(n)`; uncovered gates say
  `NONE — rule 6`).
- `gov doctor` resolves every gate command — a typo'd binary is a
  problem before a run reports MISSING.
- `gov trend --gate <id> [--base <ref>]` — single-gate view; split the
  early/late window at a git ref's commit date.
- `gov init --upgrade --json` — machine-readable drift for programmatic
  adoption.

## 0.10.x — adopt, doctor, note scaffolding, strict schema

- `gov init --adopt [file…|all]` — land missing template files (never
  overwrites existing ones).
- `gov doctor` — environment self-check: PATH, Python, hooks, gates
  schema, decisions table.
- `gov note new --class <c> --ref <D> "Title"` — scaffold pre-validated;
  `gov note check` — pre-commit-light format + D-ref check.
- Unknown gates.json keys abort loud (`"enable": false` is gone).
- Run history records by default (`.gov/history/`, gitignored);
  `--no-record` opts out.

## 0.9.0 — decision guard, review dossier, skill drift, trends

- `gov verify-decisions` — decisions table: numbering, alternatives,
  orphans. `gov review --base <ref>` — one-shot review dossier.
- audit-names checks skills' gov command/flag references.
- `gov trend` reads `--record` history (p50 per window halves).
- `--staged` (index-only note-presence), dangling-record reporting.

## 0.8.0 — template upgrade path

- `gov init --upgrade` — per-file template-vs-local diffs, never writes;
  MISSING items marked adoptable.

## 0.7.x — adopter wishes round one

- `.gov/rejections/` — project rejection cases wired into self-test
  (`tools N + project M`, `--scope`, 10s budget).
- `gov run --json` — one JSON array (gate/outcome/blocking/duration_ms/
  detail); pure stdout, human report on stderr.

## 0.6.x — honesty rounds

- Gate reachability (one loud parking mechanism: `enabled: false`);
  `--every-gate`; `--gate <disabled>` exits 2.
- Archive seal detector (`gov verify-archive`) + no-laundering re-seal.
- Two-step uninstall (`--force`); retrofittable `--hooks/--ci`;
  `gov recall` / `gov audit-notes` (the memory read side); skills ship
  with the plane.
