# Bilingual pairing contract

English | [中文](README.zh.md)

Both languages carry equal authority; either may be written first. A pair is three sibling files: `foo.md`, `foo.zh.md`, and `foo.i18n.yaml`.

## The sidecar

The sidecar records the git blob hash of each side at its last confirmed-consistent state. After editing either side, re-confirm in the same change:

```sh
gov verify-pairing --write docs/example.md
```

The gate fails when a recorded hash no longer matches its file — a one-sided edit is never silent.

## Honest limits

A green gate means the pair was confirmed consistent at these exact contents — not that the translation is good. Quality belongs to review.
