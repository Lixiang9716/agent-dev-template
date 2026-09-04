# Agent Note: Release flow drafts HIGHLIGHTS sections (verify-doc-sync --write)

Status: implemented

Related: D46, D37, issue #125 (follow-up), runbook note
2026-08-28-release-pr-approval-runbook.md (unchanged — this automates the
step that note leaves manual)

## Problem

D37's division of labor — release-please writes CHANGELOG, a human writes
the usage-oriented HIGHLIGHTS section — had no mechanism underneath the
"write the section" half. Every release since 0.19.0 (four in a row:
0.19.0, 0.20.0, 0.21.x, 0.22.0) merged its release PR and immediately
turned master's doc-sync gate red; an agent or maintainer then hand-pushed
the missing section. The gate worked every time — but a gate whose failure
is a routine step of the release process is a failure being normalized,
and each red sat on master until someone noticed.

## Decision

`gov verify-doc-sync --write` (same `--write` shape as `verify-pairing`,
no second CLI vocabulary): for every released version missing its section,
draft the section mechanically from CHANGELOG — bullets copied verbatim
(trailing provenance link groups stripped, HTML entities the release notes
escaped un-escaped), heading `x.y.z — (draft: copied from CHANGELOG,
rewrite for usage)`, newest first, inserted ahead of the first existing
section — then re-run the gate's own check and return its exit code. The
pre-0.12.0 FLOOR is the gate's own constant, shared.

The release-please workflow gains a `highlights` job that runs while the
release PR is open (`release_created != 'true'`): it checks out the
release branch, runs `--write`, and — only when the file actually changed
— commits and pushes the draft back onto the PR branch. The release merge
therefore lands CHANGELOG + version bump + HIGHLIGHTS together, and
master never sees the red. On the merge push the job skips: the section
must already be in the merged tree.

Five unit tests: draft-and-turn-green, idempotence, fail-loud without
HIGHLIGHTS, FLOOR exemption, never touches a covered version.

## Alternatives considered

**release-please config template (`extra-files` / generic updater).**
release-please substitutes version strings; it has no hook for appending a
markdown section. The config layer cannot express this step.

**Drafting usage prose.** The whole point of HIGHLIGHTS (per its header)
is "how to use them" — a judgment call. A machine-written usage section
would be invented content wearing an evidence costume; the verbatim copy
with a self-declared draft heading keeps the mechanical half (version
pairing, what the gate guards) automated and the judgment half human.

**Pushing the draft straight to master.** Bypasses the PR's CI evidence
chain, and a GITHUB_TOKEN push does not trigger workflows — master would
carry a commit no CI run ever covered. Onto the release PR branch, the
section ships inside the release merge whose post-merge CI (triggered by
the human admin merge) proves the whole tree green.

**`[skip ci]` on the draft commit.** The release PR's `gates` run should
cover the tree it ships; skipping CI on the draft commit leaves the run
stale relative to the final tree. Bot-PR CI needs one human approval
anyway (the runbook's "one click") — no noise saved that matters.
