# What's new — govrail highlights, per release

Usage-oriented highlights (the CHANGELOG carries commits; this carries
how to use them). `gov whatsnew [--since <version>]` prints from here.

## 0.17.0 — decision-row tooling for parallel branches

- `gov decision next [--count N] [--base REF]` prints the next free
  D-number from the configured decisions source; `--base origin/master`
  unions what already landed there, so a branch cut before a sibling
  landed prints the number the eventual merged history will show
  instead of re-allocating a taken one (issue #107, D40).
- `gov decision add --from FILE [--id Dn] [--dry-run]` appends a
  decision atomically and validates before writing: a number that
  already exists, a number that opens a gap, and a draft without the
  options/rejected-alternatives section are each refused by name.
- A `dir` decisions format (`{"path": ".gov/decisions", "format":
  "dir"}`, one file per decision) makes parallel appends structurally
  conflict-free: each `add` creates a new file, so two worktrees
  appending from the same base merge with no textual conflict at all.
- `gov verify-decisions --base REF` is the gate-time net: a number both
  branches added since the merge-base is a named collision with the
  renumber command in the message; pre-partitioned gaps (the number
  exists on the base) stay informational.

## 0.16.0 — additive gate adoption for customized installs

- `gov init --adopt-new gates.json` merges newly shipped gates into a
  customized gates.json by gate id: the added ids are named in the
  output, every local gate is preserved untouched, and the merged file
  is schema-validated before anything lands (issue #108, D39). This is
  the one-command answer to drift that used to mean hand-copying blocks
  out of `site-packages` templates.
- Non-additive drift — a shared gate id whose content differs locally —
  is refused loudly with the id named; those keep the two-step manual
  path. Unsupported targets fail loud too: only gates.json has an entry
  identity to merge on.
- See the drift first as always: `gov init --upgrade` lists per-file
  diffs, `--json` for agents.

## 0.15.1 — failure-first gate output

- `gov run` prints failed evidence in full and never clips it, and the
  failure line names the exact rerun command — reading a red run no
  longer means scrolling past a wall of green (issue #109).

## 0.15.0 — conflict-marker gate

- `gov verify-conflict-markers` fails naming `file:line` when a changed
  file still carries git conflict markers — the rebase failure mode git
  itself refuses to police (`git add` stages them, `git rebase
  --continue` commits them; issue #104, D38).
- A line-initial start/end/diff3 marker (exactly seven characters) is
  primary evidence; a bare `=======` counts only beside a sibling
  marker, so Markdown setext underlines stay legal. The escape hatch
  for deliberate literals: append `gov:ignore-marker` to the line.
- The gate ships in the template's `all` mode (fresh `gov init` gets
  it); existing installs see the drift with `gov init --upgrade` and
  adopt or copy the gate block. `--staged` reviews just the index;
  rejection proofs ride with `gov self-test`.

## 0.14.1 — flag registry pinned to each command's --help

- `gov audit-notes` no longer reports real flags as dead commands: notes
  documenting working runs of `gov init --adopt <file>` (also `--preview`,
  `--json`), `gov run --no-record`, `gov review --grade` read as working;
  a genuinely unknown flag (`gov init --nonexistent`) is still named
  (issue #101).
- `gov init --help`, `gov uninstall --help`, `gov verify-notes --help`
  list their real options — the terse one-line command summary is a
  description, never the machine-checked surface.
- The registry is pinned mechanically now: every command's `--help`
  options must equal `audit_notes.FLAGS`, and a registry that lags the
  CLI fails audit-notes itself (exit 2) instead of silently skipping.

## 0.14.0 — CHANGELOG ↔ HIGHLIGHTS pairing

- `gov verify-doc-sync` gate: every released version in CHANGELOG must
  have a matching HIGHLIGHTS section (version read FROM CHANGELOG, never
  guessed); ahead-of-release sections caught too. This very gate went
  red on the release PR that shipped it — the first dogfood bite.

## 0.13.2 — explicit version mapping

- `gov whatsnew` prints the installed wheel version and, when the wheel
  carries no section for itself (a docs-only release, or a section added
  after its release ships in the next wheel), says the mapping out loud
  instead of reading one version short (issue #92's wheel-lag residual).

## 0.13.1 — alignment round

- Bare `gov init --adopt --preview` names the drift inventory
  (`adoptable: N missing, M drifted`) and cross-links `--upgrade` and
  the single-file preview (issue #91).
- HIGHLIGHTS headers are aligned with wheel versions, enforced by a
  tag-coverage guard test; the index-propagation note (retry
  `pip install -U` before suspecting the release) is in CONTRIBUTING
  (issue #92).

## 0.13.0 — provenance and external references

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
