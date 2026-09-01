# Project rejection cases

Rule 6: a gate that never fails is a vacuous script. Every project-defined
gate in `gates.json` ships a rejection case proving it can go red — and
this directory is where that proof runs.

## The contract

- Every **executable** file under this directory runs as part of
  `gov self-test`, with the repository root as the working directory.
- **Exit 0** = the rejection proof holds (your gate went red when it
  should have). **Non-zero** = the self-test fails, naming the file.
- One case per file, any executable language (`case-*.sh`, `case-*.py`, …).
- Files named `README*` are skipped.

## Notes

- The report counts `tools` (govrail's built-ins) and `project` (yours)
  separately: `gov self-test --scope project` runs only yours.
- Keep cases in git — and note that `gov uninstall` removes `.gov/`
  entirely, so anything you want to survive an uninstall/reinstall cycle
  belongs in the repository history, which git already gives you.
