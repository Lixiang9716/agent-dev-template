# AGENTS.md — standing orders

English | [中文](AGENTS.zh.md)

<!-- gov:rules --> Read .gov/rules.md and follow it before starting work.

This repository **is** the governance plane (agent-dev-template): it ships the
gates, notes, and rules that `gov init` injects into other projects. The locked
design decisions are in [docs/decisions.md](docs/decisions.md); the machinery is
described in [docs/architecture.md](docs/architecture.md).

Run `gov self-test` to prove every governance gate can reject, and
`gov run --mode all` for the full gate DAG.
