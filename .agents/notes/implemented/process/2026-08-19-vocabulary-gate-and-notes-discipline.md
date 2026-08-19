# Agent Note: vocabulary gate, notes discipline, twin probes, checkpoints

Status: implemented

## Problem

The V6.0 consensus's verification semantics — concept-level declaration-state vocabulary, status-entry discipline with mandatory sampling, normalized twin comparison, numbered checkpoints — existed only as prose in an external consensus document. This repository, which hosts the governance plane, had no mechanical home for any of the four clauses: a claim word like "已验证" could land in AGENTS.md or docs/*.md and no gate would stop it; a note's status claims carried no sampling fields; twin behavior was pinned by hash but never compared after normalization; and checkpoints had no documented contract. Four clauses, four gaps.

## Decision

- The `vocabulary` gate (new) scans AGENTS.md, AGENTS.zh.md, and docs/*.md — the pre-registered `scan` list in scripts/vocabulary.json, one home for the banned families, meta whitelist, definition markers, and window. The manifest is strict: unknown keys at the top level or inside `banned` abort naming the offender, and the version field must match the pin `EXPECTED_VOCAB_VERSION=1` kept in both ports — a mistyped whitelist key must never silently disable an exemption, and a schema migration must be a deliberate two-port act. Exemptions: backtick-quoted tokens, meta-annotation whitelist terms preceded by a structural delimiter, and ban-definition sentences whose marker ends within 6 characters before the token. The gate runs in `all` and `docs` modes.
- The pre-push-checks and code-review skills map the scanned docs surface and scripts/vocabulary.json to the vocabulary gate, so a docs-only PR selects it before push (rule 9 selection coverage; CI unchanged).
- The notes verifier enforces optional entry disciplines (any lifecycle): `- Claim:` entries require verifier/coverage/goal-link sub-bullets, `- Open:` entries require settled-by, and a paragraph containing "not-refuted" must carry sampling fields in the same paragraph (this sentence demonstrates the form: rate: every note, schedule: each verification run, reviewer: verify-agent-notes.test).
- `verify-script-pairs` gains an opt-in per-pair behavioral probe (`"probe": "test"`): both sides' sibling test suites run, and their outputs are compared after pre-registered, versioned normalization (timestamp@v1, whitespace@v1 — the registry is pinned identically in both ports). Normalized-equal passes with a blind-spot notice when raw bytes differ; still-unequal fails naming the pair. `--write` preserves probe settings.
- docs/architecture.md gains the checkpoint discipline section (numbered, append-only entries carrying verifier/coverage/goal-link; recovery resumes from the highest-numbered entry with an intact chain), paired into architecture.zh.md and architecture.i18n.yaml.
- Backward-compatibility decision: the notes rules bind only entries that are present. Historical notes without structured entries are untouched and keep passing; nobody "fixes" them into the new shape. This decision is recorded here so a future changer does not retrofit history.

## Alternatives considered

- A hard rule that every implemented note must carry a Claims section (rejected: breaks every historical note and forces boilerplate on notes that assert nothing).
- Running behavioral probes by default for every twin (rejected: probe-less pairs such as lib have no sibling test suites, and an unprobeable pair should not fail the gate by default; the manifest makes a probe an explicit per-pair act).
- Placing the normalizer registry in script-pairs.json (rejected: the versions are implementation constants shared by both ports, and the manifest's job is pair state, not code; the pinned registry lives in the ports and is audited by the test suites).
- ASCII-only word boundaries for the en family (rejected: "状态verified" would flag where the reference implementation's \b does not; the bash port runs under C.UTF-8 so [[:alpha:]] classifies CJK letters exactly like the pwsh port's IsLetterOrDigit).
- Forward-compatible manifest leniency (rejected: accepting unknown keys means a mistyped `metaWhitelistt` silently drops an exemption from the semantics — the strict schema makes config errors fail loud with the offending name, and schema growth is versioned by the pin).

## Consequences

- AGENTS.md and docs/*.md are now a declared-state vocabulary surface: any new claim word in them fails CI, with a defined exemption ladder for meta-annotation and ban definitions. Two pre-existing violations in docs/architecture.md ("re-confirmed", "validated") were rewritten as part of this change.
- Notes that make claims now owe a named verifier, coverage, and goal-link — a claim entry without them is a violation, not a style suggestion.
- Twin pairs with probes get mechanical behavioral comparison at gate time; the blind-spot notice keeps normalization visible instead of silent. Probes are enabled for verify-vocabulary and verify-agent-notes; other pairs keep hash-only confirmation until their suites are probe-clean.
- The checkpoint clause is documented but not gated in this template: recovery semantics are a product-plane concern the template records, not a gate it enforces. Documented, not integrated as a gate — recorded for honesty.
- Cross-platform: probes execute the sh twins on macOS, where bash is 3.2 — caught by CI on the macos-latest leg. Fixed in this same change: no `${var,,}`/`declare -A`/`mapfile`; regexes held in variables for `[[ =~ ]]` (the 3.2 parser rejects unquoted `(` in the pattern); empty-array expansions guarded with `${arr[@]+"${arr[@]}"}` (3.2 + `set -u` treats `${arr[@]}` on an empty array as unbound). Verified locally by running both probed test suites under a built bash 3.2 (18/18 and 53/53).

## Claims

- Claim: the vocabulary gate rejects every banned form in both languages and honors every pre-registered exemption.
  - verifier: bash scripts/verify-vocabulary.test.sh and pwsh -File scripts/verify-vocabulary.test.ps1, 53 checks 0 failed on both ports
  - coverage: en and zh banned families, meta-annotation/backtick/definition-sentence exemptions, malformed manifests, unknown keys, version pin, missing scan targets
  - goal-link: AGENTS.md rule 3 (every gate rejects an invalid case)
- Claim: the notes verifier's discipline rules bind only present entries, so historical notes pass unchanged.
  - verifier: bash scripts/verify-agent-notes.test.sh and pwsh -File scripts/verify-agent-notes.test.ps1, 18 checks 0 failed on both ports, plus the notes gate on the real tree
  - coverage: claim/open entry forms, empty sub-bullet values, plain historical notes
  - goal-link: AGENTS.md rule 2 (notes carry decisions)
- Claim: the pair probe compares twin test-suite outputs after versioned normalization and fails loud on divergence.
  - verifier: bash scripts/verify-script-pairs.test.sh and pwsh -File scripts/verify-script-pairs.test.ps1, 25 checks 0 failed on both ports, plus both pair-gate ports with probes live
  - coverage: normalizer registry, timestamp/whitespace normalization, blind-spot notice, diverging probes, probe preservation by --write
  - goal-link: AGENTS.md rule 7 (bilingual pairs merge whole)
- Claim: this note's not-refuted statements carry sampling (rate: 100% of entry-bearing notes, schedule: every verification run, reviewer: both test suites) — the note itself demonstrates the discipline it documents.
  - verifier: verify-agent-notes on the notes tree, both ports report "the notes tree is valid"
  - coverage: this note file
  - goal-link: AGENTS.md rule 2
