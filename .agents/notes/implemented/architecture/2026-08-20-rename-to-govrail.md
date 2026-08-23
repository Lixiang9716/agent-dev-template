# Agent Note: rename package to govrail

Status: implemented

## Problem

The package was named `agent-dev-template`, which is descriptive but not a
publishable brand, while the CLI command is `gov`. A shorter, brandable name
was needed before PyPI publication.

## Decision

Rename the package to `govrail` — governance + guardrail, aligned with the
`gov` CLI. Updated `pyproject.toml`, README, AGENTS.md, and the package
docstring; the repository and directory are renamed to match.

## Alternatives considered

- **Keep `agent-dev-template`** — descriptive but unwieldy as a brand name.
- **`praetorian` / `custos`** — distinctive but less self-explanatory than
  `govrail`, which names exactly what the tool is (governance guardrails).
