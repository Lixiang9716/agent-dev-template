# Agent Note: link gate and leakage skills from upstream

Status: implemented

## Problem

The grow-the-plane rule expands the document network — more notes, more cross-references, more deep links — with nothing guarding link integrity; a dead link or a wrong anchor would surface only when a reader tripped over it. And agent-written prose drifts toward session vantage ("what I just changed") instead of repository vantage ("what is"), with the principle (rule 6) present but no method attached.

## Decision

A `links` gate (verify-md-links.sh / .ps1, distilled from upstream dsh's verify-md-links) checks that every relative link and reference definition in scope resolves to an existing file, and every `#anchor` on a Markdown target names a real heading slug (same-file anchors included; fenced blocks, URLs, and frozen archived notes excluded). Two skills join the set: `trim-cot-leakage` (the one-test method for rule 6) and `find-simplifications` (the pruning balance to the grow-the-plane rule). On its first run the link gate caught a real defect: rule 11's Chinese side anchored `#growing-the-plane` onto a translated heading whose slug differs — cross-language deep anchors cannot satisfy both the pairing gate (identical canonical targets) and link resolution, so both sides now link the page without the fragment.

## Alternatives considered

The upstream's twelve gate-runner modes (rejected: mode sprawl; all/quick/docs stay); one-physical-line-per-paragraph wrapping (rejected: formatting taste, not governance); type-equivalence and generated-catalog freshness gates (rejected: we have no generated docs); a translation terminology brief (deferred until bilingual pairs grow — trigger recorded in the positioning note's spirit).

## Consequences

New Markdown files are link-checked the moment they land in scope. Explicit `<a id>` anchors are not recognized — state the heading instead. Cross-language pairs must not carry per-language anchors, a constraint the pairing and link gates now enforce together.
