# Agent Note: PyPI publishing stays inside release-please.yml — one publisher only

Status: implemented

Related: #156 (the duplicate that shipped and was reverted here), #33 (where the in-workflow publish landed), PYPI_TOKEN (repo secret since 2026-08-23), rule 6 (verify the world, not the self-report)

## Problem

PyPI publishing was believed missing: a workflow-file *listing* showed only
ci.yml / release-please.yml / star-history.yml, and "no publish.yml" was
read as "no publish pipeline". A dedicated release-triggered publish
workflow (Trusted Publishing OIDC) shipped in #156 to fill the gap. But
release-please.yml has published every version since #33 — build + twine
upload with the PYPI_TOKEN secret, guarded by a tag/version match — and it
did publish 0.26.0 on merge (run 33941706972, "Publish to PyPI: success").
Two publishers on the same release means the second upload always fails
with "file already exists": every future release would go red.

## Decision

#156 is reverted: no dedicated publish workflow. PyPI upload remains the
last steps of the `release` job in release-please.yml (verify tag ==
gov.__version__ → python -m build → twine upload with PYPI_TOKEN), so a
release PR merge publishes exactly once, in the run that cut the release.
The wrong-note-shipped-in-#156 is deleted; this note replaces it.

## Alternatives considered

- **Keep publish.yml and strip the upload from release-please.yml** — a
  cleaner separation (release-please versions; publish.yml publishes), but
  it discards a battle-tested path for an unproven one and splits the
  release story across two files for no user-visible gain.
- **Migrate the upload to Trusted Publishing (OIDC)** — strictly better
  credentials (minutes-lived, workflow-pinned vs a long-lived account
  token) and the right move next time the PYPI_TOKEN is rotated; until
  then the token is already wired, proven, and requires zero pypi.org
  click-through. Swapping auth was not worth a PR on its own.
- **Manual twine upload per release** — the pre-#33 status quo: invisible
  in no repo file, exactly the "promise a command could check left to
  prose" failure rule 1 names.

The episode's own lesson, worth keeping: the existence check was a filename
listing, never a file read or a run log (rule 6 — the run log answered
immediately). Before adding machinery, read the machinery that is there.
