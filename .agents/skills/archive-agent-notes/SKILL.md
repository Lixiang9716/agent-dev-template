---
name: archive-agent-notes
description: Use when adding, auditing, pruning, or archiving Agent Notes; decides which implemented notes still earn their place and seals completed archives.
---

# Archiving Agent Notes

Judge every note semantically: word count and age are discovery aids, never archive criteria.

## Keep a note active when

Its rationale, alternatives, negative guarantees, or reintroduction conditions are likely to guide a future change. Length does not matter.

## Archive a note when

It documents one-shot scaffolding, a narrow adapter detail, or a superseded mechanism whose facts live on in the owning code or a newer note. Supersession requires the successor to absorb the unique rationale, then link back.

## Never

- Archive an `implemented/` note whose decision is still the shipped reality — update its facts in place instead.
- Edit, move, or delete anything under `archived/` — it is sha256-sealed; supersede forward instead.

## Procedure

1. Move the note to `archived/<class>/` keeping its filename.
2. Insert `Archived: <date>` as line 4 (not earlier than the filename date); line 3 reads `Status: implemented`.
3. Fix inbound links.
4. Seal the manifest with `gov archive-notes`, then commit in the same change.
