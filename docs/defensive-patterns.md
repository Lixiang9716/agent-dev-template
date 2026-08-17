# Defensive patterns

English | [中文](defensive-patterns.zh.md)

Rules for classes of defects that actually shipped somewhere and were expensive to rediscover. Each entry states the rule and the bug class it prevents. Add a pattern only with the failure that motivates it — a pattern without a scar is speculation.

## Report orthogonal outcomes independently

A process can time out AND exit 0 because it trapped the signal. Surface each independent fact (`timedOut`, `signal`, `exitCode`) on its own; never nest one flag's report inside another's branch, or a caller reads a cut-short run as a clean success.

## Teardown must reach quiescence, not just request it

Cleanup that issues kills or aborts and returns before the work stops leaves orphans. Await the children's exit after signalling, and close listener registries before killing so late completions stay silent.
