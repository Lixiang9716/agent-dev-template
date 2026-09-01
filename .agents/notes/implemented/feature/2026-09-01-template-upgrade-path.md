# Agent Note: gov init --upgrade — seeing template drift, never writing it

Status: implemented

## Problem

`gov init` is one-shot: an initialized project has no mechanical way to
learn what the shipped templates changed since its init — only the
changelog and a hand-made diff. Templates evolve (rules gained a project
rule, the template gates gained gates, 0.7.0 added the rejections
README, skills ship now), and the first adopter already carries a
customized rules.md (its own rule 8): the next template update would be
a manual-diff adventure with real merge risk.

## Decision

`gov init --upgrade` is a read-only report (D27): the manifest's init
version against the running package version for era context, then a
per-file comparison of every injected file (rules.md, the notes and
rejections READMEs, the skills, plus the created gates.json and gov.yml)
against the current templates. Matching files are listed, files added by
newer templates and never created by the old init are marked
MISSING — safe to add, and drifted files get a unified diff
(template side vs local side) capped at 40 lines. Attribution is honest:
same-version drift means customized locally; older-version drift says
"customized locally and/or template evolved" — indistinguishable is
stated as indistinguishable. Nothing is written; adopting a change stays
a human edit, with D23's two-step philosophy for customized files. A
project where everything matches is told it is safe to refresh.

## Alternatives considered

- Auto-merge or overwrite — rejected: a three-way merge over
  customizations is a data-loss machine; D23 just fixed the same class
  for uninstall.
- Report only the version gap — rejected: a version number carries no
  per-file information; the manual diff would remain.

## Consequences

Adopters can see template drift with one command and merge at their own
pace; the report's diff is exactly what a hand-merge needs. The report
cannot tell which side moved when both the package and the project
changed since init — it says so instead of guessing.
