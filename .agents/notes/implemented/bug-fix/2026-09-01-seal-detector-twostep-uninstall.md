# Agent Note: the seal gets a detector, re-sealing cannot launder, uninstall is a real two-step

Status: implemented

## Problem

Two broken promises. The archive seal claimed "any later edit is
detectable", but the manifest had only a writer and no reader: tampering
with an archived note was caught by no tool (verify-notes skips archived
by D5, audit-notes exempts them, recall indexes them regardless), and
re-running `gov archive-notes` recomputed the hashes over the tampered
content and re-sealed — laundering the violation permanently, after which
manifest == tampered. Separately, uninstall's customization warning said
"copy out anything you want to keep, then re-run" while the same run
deleted everything right after printing it — advice that guaranteed data
loss for anyone who followed it.

## Decision

The freeze now has a detector (D23): `gov verify-archive` checks every
archived file against its pinned sha256 and both directions of absence
(unsealed files, sealed-but-missing files); it ships as a paths-scoped
gate (`.agents/notes/archived/**`) in this repository and the injected
template, so a tamper is what triggers it. `gov archive-notes` verifies
the existing seal before re-sealing: a drift aborts loud, naming the
files ("restore them or pass --rebaseline"); `--rebaseline` is explicit,
loudly-printed consent, so legitimate migrations remain possible while
silent laundering is closed. The archive-agent-notes skill (live and
shipped copies, kept identical) now seals-and-verifies in one procedure
and lists re-sealing a tampered file under Never. uninstall became a
genuine two-step: with customized files it warns, deletes nothing, and
exits 1; `gov uninstall --force` is the explicit consent that proceeds
(naming what it deletes). No customizations, no ceremony — one step.

## Alternatives considered

- Reword uninstall's message to "will be deleted now" — rejected: honest
  wording around a one-step loss is still a one-step loss; uninstall is
  rare enough to afford one confirmation.
- Fold seal verification into verify-notes — rejected: integrity is not
  format; a separate gate stays paths-triggerable and self-describing.
- Unconditional re-sealing for migration convenience — rejected: the
  convenience path is the laundering path; consent must be explicit and
  audible.

## Consequences

Tampering with history now fails a gate instead of nothing, and unsealing
laundering requires typing a flag and reading what it re-baselined. Every
uninstall over customized content costs one extra command — the price of
the promise the old message never kept.
