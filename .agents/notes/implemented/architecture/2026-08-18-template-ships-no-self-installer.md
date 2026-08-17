# Agent Note: the template ships no self-installer

Status: implemented

## Problem

Everything inside a template repository is inherited by every project derived from it. A self-installer (curl/irm one-liners scaffolding the template's own tarball) is distribution machinery for the template itself: inside a derived project it points at someone else's repository and is dead weight to delete.

## Decision

The repository contains only what derived projects need. Distribution rides GitHub's native template mechanics — derive with `gh repo create --template` (or the "Use this template" button), or clone and re-init git. Releases tag stable points for consumers who want them (`git clone --branch`), but nothing resolves or consumes them automatically. CI proves the gates on four OS legs; macOS runs the pwsh twin only, since Apple still ships bash 3.2.

## Alternatives considered

Paired curl/irm installers modeled on binary tools like rustup and Deno (shipped briefly and reverted: those tools distribute executables, a template is distributed by forking the repository itself, and the installers became inherited junk); serving installers from a separate distribution repo (rejected: a second moving part for something GitHub already distributes natively).

## Consequences

Derived projects start clean, with no files to prune. The dual-shell platform story is unchanged: bash >= 5 or pwsh 7+, macOS and Windows on the pwsh twin. Platform evidence moved from the installer CI legs into the gates matrix (a macos pwsh leg), so the proof survived the revert.
