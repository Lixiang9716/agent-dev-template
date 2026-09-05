# Agent Note: PyPI publishing moves into CI via Trusted Publishing

Status: implemented

Related: v0.26.0 (first release-please-cut release; PyPI upload was still manual), rule 1 (gates over prose)

## Problem

Every version up to 0.26.0 reached PyPI by a manual, off-repo `twine upload`
run from the maintainer's machine. The steps lived in no file: the release
PR merged, the GitHub Release appeared, and PyPI stayed stale until someone
remembered. That is exactly the "promise a command could check left to
prose" failure rule 1 names — a release was not done until a human did an
invisible extra step, and nothing recorded whether it had happened.

## Decision

`.github/workflows/publish.yml` uploads to PyPI on every GitHub Release
`published` event — the event release-please already emits when its release
PR merges — and on `workflow_dispatch` for retries and backfill. Auth is
PyPI Trusted Publishing (OIDC) via `pypa/gh-action-pypi-publish@release/v1`:
no API token lives in GitHub secrets, and the upload identity is pinned to
(owner Lixiang9716, repo govrail, workflow publish.yml, environment pypi).
Before building, the workflow asserts `gov.__version__` equals the released
tag (same alignment idea as the HIGHLIGHTS guard), then builds sdist+wheel
and runs `twine check`; the upload is the last step, so a failure publishes
nothing.

## Alternatives considered

- **API token in a repo secret** (`password: ${{ secrets.PYPI_API_TOKEN }}`)
  — works without any pypi.org click-through, but the token is a
  long-lived, repo-wide credential that survives maintainer turnover and
  grants upload rights to every future contributor with secrets access.
  OIDC tokens expire in minutes and are bound to this exact workflow.
- **Trigger on tag push (`v*`) instead of release published** — fires even
  when a tag is pushed without a release, and release-please's release is
  the actual "this version is done" moment; a tag is bookkeeping.
- **Upload from the `ci.yml` gates job after merge to master** — publishes
  every commit's state rather than released versions, and couples gate
  results to an upload that should only ever reflect a tagged, released
  tree.
