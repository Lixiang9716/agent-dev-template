# Example: a project governed by govrail

This directory shows what a project looks like after `gov init` plus one real
decision. It is a **demo**, not the govrail source — the files here are exactly
what govrail injects into your project, so you can read before adopting.

## What each file is

| Path | What it is |
|---|---|
| `AGENTS.md` | The reference line govrail appends, pointing agents at the rules |
| `.gov/rules.md` | The governance rules — the single source of truth |
| `gates.json` | The gate DAG: `self-test`, `notes`, `pairing` |
| `.agents/notes/README.md` | The note format contract (three required sections) |
| `.agents/notes/implemented/**/*.md` | An example Agent Note |
| `src/main.py` | A trivial product plane, just to make it a real project |

## Reproduce it yourself

```sh
pip install govrail
cd /path/to/your/project
gov init            # creates AGENTS.md reference + .gov/rules.md + gates.json + notes README
gov run --mode all  # the gate DAG goes green
```
