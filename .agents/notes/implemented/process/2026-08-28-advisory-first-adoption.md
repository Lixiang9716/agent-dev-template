# Agent Note: a fresh init never goes red — pairing ships advisory until baselined

Status: implemented

## Problem

Right after `gov init`, the first `gov run` failed: existing documents had no
pairing records, so the pairing gate reported every document as a violation.
The first experience of the tool was "install, then broken", which is exactly
the moment an adopter decides to leave.

## Decision

The injected `gates.json` ships the pairing gate with `allowFailure: true`:
the first run exits 0 while the advisory failure reports exactly what needs
baselining. The runner now tags advisory outcomes on the outcome line
(`FAIL pairing (advisory; allowFailure)`) and prints their output — an
advisory failure used to be invisible, which made allowFailure useless as an
adoption state. `gov init` prints the next steps: run, baseline with
`gov verify-pairing --write`, then remove `allowFailure` to enforce. This
repository (already baselined) keeps the gate enforcing. `init` also records
the CLI's actual version in the manifest instead of a hardcoded 0.1.0.

## Alternatives considered

- `init` probing documents and writing the baseline itself — rejected: init
  injects, it does not judge; auto-writing records would confirm "these
  translations are consistent", a human judgment the tool cannot make.
- Leaving it enforcing — rejected: that is the reported defect.
- A separate first-run "wizard" mode — rejected: more surface than one
  `allowFailure` flag the runner already understood.

## Consequences

An adopter sees the real pairing debt on run one without being blocked by it;
enforcement is one deliberate edit away. Advisory failures now print output
for every allowFailure gate, so CI logs for advisory gates grow slightly
noisier — deliberately.
