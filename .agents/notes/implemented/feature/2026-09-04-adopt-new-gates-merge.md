# Agent Note: gov init --adopt-new gates.json — additive adoption for a customized gate set

Status: implemented

## Problem

`gov init --upgrade` correctly reports a customized gates.json as DIFFERS,
but the road from "drift detected" to "adopted" was a hand-merge: open
`site-packages/gov/templates/gates.json`, copy the new gate block, edit the
local modes and gates arrays, eyeball the JSON (issue #108, adopting 0.15.0's
conflict-markers gate into radiant). Nothing validated that the hand-merge
preserved local customizations or matched the shipped block. D34's
`--adopt` cannot help: a customized file is never overwritten — by design.

## Decision

`gov init --adopt-new gates.json` merges only the NEW shipped entries into
a customized gates.json (gate id is identity): shipped gates whose id is
absent locally are appended in template order and named in the output; every
local gate object is carried over untouched; existing modes are extended
with the newly adopted ids only (a purely-new template mode is created,
anything referencing gates outside the merge is declined with a notice);
`defaultMode` stays local with an informational note when the template
disagrees. The merged file is validated with the real schema loader
(`gates.load_config`) before anything is written — a merge the runner would
reject never lands. Non-additive drift — a shared gate id whose content
differs, structural damage, or an unsupported target — is refused loudly
with exit 2 and zero writes; that path stays the manual merge D27/D34
defined. The manifest is deliberately untouched: gates.json remains
customized, and recording a template hash would falsely claim provenance
over content that is not the template's bytes.

## Alternatives considered

- Full auto-merge / overwrite of drifted files — rejected in D34 and stays
  rejected: a three-way merge over free-form customizations is a
  data-loss machine; this feature only narrows the safe subset.
- Extending `--adopt` to do the merge — rejected: `--adopt`'s contract is
  byte-level (whole-file, hash-proven); mixing in entry-level JSON
  semantics would make one flag mean two different proof stories.
- Applying --adopt-new to every template file — rejected: rules.md and the
  READMEs are prose with no entry identity; only gates.json has a
  mechanical id key to merge on (fail loud for anything else).
- Recording a post-merge provenance hash — rejected: the hash would no
  longer mean "these are the template's bytes", corrupting D34's
  three-way era judgment for future upgrades.

## Consequences

Additive drift (new shipped gates, local gates untouched) is now a
one-command, schema-validated adoption that names what it added; the
conflicting case is named per-id and keeps the two-step hand path. If a
project locally disabled a shipped gate id (`enabled: false`) rather than
removing it, adoption is refused as non-additive drift — the operator sees
the id and decides; silently re-enabling or skipping was not an option.
