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

- Archive a `proposed/` note — proposals die by rejection or ship by implementation, not by archiving.
- Edit, move, or delete anything under `archived/` — it is sha256-sealed; supersede forward instead.
- Break a pair: archiving applies to notes, which are English-only in this template; bilingual pairs follow the pairing gate instead.

## Procedure

1. Move the note to `archived/<class>/` keeping its filename.
2. Insert `Archived: <date>` as line 4 (not earlier than the filename date); line 3 reads `Status: implemented`.
3. Fix inbound links.
4. Seal: `bash scripts/archive-agent-notes.sh --write` (pwsh twin: `pwsh -File scripts/archive-agent-notes.ps1 -Write`), then commit the manifest in the same change.
