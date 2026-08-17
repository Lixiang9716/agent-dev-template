# Agent Note: blob-hash bilingual pairing

Status: implemented

## Problem

Bilingual documents drift: one side gets edited, the other ages silently, and no reviewer can tell which side was last confirmed consistent.

## Decision

Each pair carries a sidecar (`foo.i18n.yaml`) recording the git blob hash of both sides at their last confirmed-consistent state. The gate recomputes hashes and fails, naming the edited side, until the pair is re-confirmed with `--write` in the same change. Structural signatures must also match; fenced code blocks are byte-identical across languages.

## Alternatives considered

Timestamp comparison (rejected: filesystem times are not portable and survive copies); comparing rendered output only (rejected: catches structural drift but not one-sided semantic edits, and gives no resumable confirmation state); no enforcement, review only (rejected: the exact silent drift this exists to prevent).

## Consequences

Editing either side requires touching the sidecar in the same PR — deliberate, visible, and mechanical. A merge driver auto-resolves sidecar conflicts when only one side advanced. The gate proves consistency, not translation quality; quality stays with review.
