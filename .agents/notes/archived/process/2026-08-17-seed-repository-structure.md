# Agent Note: seed repository structure

Status: implemented
Archived: 2026-08-17

## Problem

The template's first commit needed a tree that exercises every mechanism it ships — otherwise the gates would validate nothing real and adopters would inherit untested machinery.

## Decision

The seed tree contains a complete governance plane (scheduler, verifiers, pairing, budgets, hooks, CI), five implemented notes, one proposed note, one rejected note, and this archived note, each placed to be exercised by the gates that govern it.

## Alternatives considered

Seeding only the scripts and letting documentation accrete later (rejected: the pairing and budget gates need real pairs and real ceilings from the first commit to be green honestly).

## Consequences

This note is sealed at archive time as the worked example of the sealing procedure: `Archived:` on line 4, sha256 in manifest.json, never edited afterward.
