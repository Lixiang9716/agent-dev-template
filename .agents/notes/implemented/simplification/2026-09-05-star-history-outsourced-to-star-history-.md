# Agent Note: star history outsourced to star-history.com — the self-hosted recorder had nothing to record

Status: implemented

Related: #43 (where the self-hosted recorder shipped in 0.2.0), the 2026-09-05 single-PyPI-publisher note (whose Problem read a workflow listing that included star-history.yml), rule 7 (both README sides edited together)

## Problem

The self-hosted star history (#43) ran a daily workflow that appended the
stargazers count to `stars.csv` on the `stats` branch and regenerated
`stars.svg`, which both READMEs embedded. The machinery was green every
single day — and recording nothing: the repository has exactly one star
(the maintainer's own, 2026-08-23T02:19:40Z per the API), so all 15 CSV
rows read `1` and the chart was a flat line on the floor. The READMEs
already carry a shields.io star-count badge, so the chart's only marginal
value was the trend, and there was no trend. Meanwhile the daily cron
spent an Actions run per day to write `1` into a file forever. Two facts
made the design itself suspect: GitHub's stargazers endpoint accepts
`application/vnd.github.star+json` and returns a `starred_at` timestamp
per star (verified before this change), so full history is reconstructable
at any time for repos under ~40k stars — daily recording was never the
only way to have history; and nothing the recorder had accumulated was
worth keeping.

## Decision

Both READMEs (`README.md`, `README.zh.md`, edited as one pair) now embed
`https://api.star-history.com/svg?repos=Lixiang9716/govrail&type=Date`
(verified 200, `image/svg+xml`). The recorder is deleted:
`.github/workflows/star-history.yml`, `scripts/stars_chart.py`, and the
remote `stats` branch. History predating the swap remains recoverable
from `starred_at` if the self-hosted path is ever reinstated. No earlier
note locked the self-hosted choice — recall found none — so nothing is
superseded; this note is the decision's first record.

## Alternatives considered

- **Keep self-hosted, upgraded (backfill `starred_at`, trigger on
  `watch: started` plus a weekly cron sweep for unstars, stepped chart)** —
  the best fit for the self-hosting ethos and near-zero runs after the
  change, but it buys machinery the README cannot use until stars exist;
  the embed is free until then. This is the plan to return to if
  third-party rendering ever proves unreliable.
- **Remove the chart entirely, keep the shields.io badge** — the most
  honest reading of "a 1-star chart is noise", but it abandons a working
  display slot that costs nothing to keep warm via the embed.
- **Keep as-is** — a daily run writing `1`; pure waste, rejected outright.
