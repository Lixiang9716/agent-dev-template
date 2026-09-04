# Agent Note: self-test failure classification — clean-env replay splits tool-defect from environment-suspect (issue #139)

Status: implemented

## Problem

A host environment can break specific tool paths in ways `gov self-test`
cannot see through. The #138 incident: a PyPI `argparse` 1.4.0 backport
sitting in the interpreter's site-packages, promoted AHEAD of the stdlib
by the very `PYTHONPATH` the task cases set (pointing at the installed
package's parent — i.e. site-packages itself), made every `gov task`
subcommand die with `TypeError: _SubParsersAction.__init__() got an
unexpected keyword argument 'required'`. The self-test went red on the
two task_check cases — correctly (rule 6: red is red), but the report
was undecidable on its face: tool defect or host environment? The
diagnostic burden fell entirely on the operator, who had to trace a
TypeError through argparse internals to a conclusion the report should
have carried. Every adopter hitting an environment-shaped red repeats
that trace.

## Decision

`gov self-test` classifies every FAIL (with D47). A failing
tools-family case is replayed once in a minimal clean environment: a
fresh temp-directory copy of the running package alone (stdlib-only by
design, so the copy is a complete environment) on `PYTHONPATH`, with
every host `PYTHON*` variable dropped and user-site disabled — the
stdlib necessarily resolves ahead of any site-packages entry, so the
#138 shadowing mechanism cannot occur in the replay. Replay PASS → the
FAIL line gains `environment-suspect` (check this host's site-packages
shadowing / `PYTHON*`); replay FAIL → `tool-defect` (fails in the
minimal env too; the traceback stands). A replay that cannot run —
timeout, exit 2 — is reported `unclassified` with the hand-rerun
command, never guessed. Project-family failures (`.gov/rejections/`)
get a reproduce-by-hand hint instead of a replay: arbitrary scripts may
legitimately need the host environment, so an automatic replay would
prove nothing. The FAIL line's evidence quote switches from the first
line of the assertion message (a bare `Traceback (most recent call
last):` — zero information) to the last non-empty line — the actual
killing exception (#109's failure-first principle, applied here).
Classification never changes the verdict: a classified FAIL still fails
the run; exit codes are untouched. The replay's building block is
exposed as `gov self-test --case NAME` (one case, one line, loud exit 2
on unknown names), and two diagnostic probes (`_probe_env_only_failure`,
`_probe_always_fails`) serve as the classifier's own rejection proof —
the tools-family case `test_failure_classifier_labels_tool_vs_environment`
shows each verdict is earned, not guessed. `docs/decisions.md` D47 and
tests/test_self_test_rejections.py pin the behavior.

## Alternatives considered

- Turning environment-suspect FAILs green or skipping them — rejected:
  the inverse of rule 6; red evidence outweighs diagnostic comfort, the
  classification adds a label, never a pass.
- Defining "clean" as a bare `python -S`/`-I` interpreter — rejected:
  with the site layer off, `-m gov` cannot be found, and pointing
  `PYTHONPATH` at the installed package hands the polluted directory
  right back; the temp-copy staging is the one mechanism that satisfies
  importability and de-shadowing at once.
- Printing a "check your environment" hint without replaying —
  rejected: that still leaves the trace to the operator; the issue asks
  for the comparison to be automatic where feasible.
- Replaying project cases too — rejected: an arbitrary script failing
  in a stripped env means anything; a guaranteed-red replay is noise.
- Keeping the first line as the FAIL evidence quote — rejected: zero
  information for any human reader; failure-first (#109) says the
  failure line carries its own why.

## Consequences

Green runs pay nothing (staging is lazy, replay only on failure). On a
host with the #138 backport, the report now reads
`environment-suspect 2` with the TypeError quoted on the FAIL line —
the operator's trace collapses into reading one line. Misclassification
remains possible in pathological hosts (e.g. a broken `PYTHONHOME`
makes the clean replay fail and a true env-bug read as tool-defect);
the label says what the replay proved, nothing more, and `unclassified`
exists for replays that prove nothing at all.
