# Adopting the plane into a project

English | [中文](adoption.zh.md)

The plane is adopted with one command per action. The rules live in
[.gov/rules.md](../.gov/rules.md); the locked decisions are in
[decisions.md](decisions.md).

## Install and remove

```sh
gov init --project <path>       # inject gates, notes, rules, reference
gov uninstall --project <path>  # reverse exactly; removes only what init created
```

`init` is idempotent (re-running is a no-op) and non-invasive: it creates
`.gov/rules.md`, adds `gates.json` and the notes README only when they are
missing, appends one reference line to AGENTS.md, and never overwrites the
project's own files.

## First-day loop

```sh
gov run --mode all      # the full gate DAG, zero install
gov self-test             # prove every governance gate can reject
gov change-scope --base HEAD~1   # smallest sufficient check set
```

Then make a real change, record it as an Agent Note, and re-run the gates.
