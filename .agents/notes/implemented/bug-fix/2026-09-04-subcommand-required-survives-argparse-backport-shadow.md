# Agent Note: Subcommand-required enforced by hand; case PYTHONPATH can no longer promote stdlib shadows

Status: implemented

Related: D43, issue #138

## Problem

0.21.0 shipped `gov task` (D43) with `parser.add_subparsers(dest=...,
required=True)` — legal stdlib argparse since Python 3.7, and govrail
requires >= 3.9, so a real stdlib always accepts it. The bug reporter's
machine carried a fossil instead: the PyPI `argparse==1.4.0` backport
(the py2.7-era argparse, which predates `required`) sitting in
site-packages. It only bites when PYTHONPATH promotes site-packages
ahead of the stdlib — and `gov self-test`'s case env did exactly that
for a wheel-installed gov (`PYTHONPATH = str(HERE.parent)` IS
site-packages there). Result: `gov task`'s happy path died in
`TypeError: _SubParsersAction.__init__() got an unexpected keyword
argument 'required'`, the two task_check rejection cases failed with it
(their subprocess traceback IS the evidence they capture), and the crash
read like a stdlib bug when it was module shadowing.

## Decision

The four subcommand CLIs (`gov task`/`note`/`decision`/`receipt`) no
longer pass `required=True` to `add_subparsers`; the
missing-subcommand rule is enforced by hand right after parse —
`parser.error("a subcommand is required (…choices…)")`, same fail-loud
contract (exit 2, usage plus named choices). Self-test case envs go
through a `_pinned_env()` helper that prepends the interpreter's stdlib
dir to PYTHONPATH before the tested tree, so promoting site-packages can
never shadow stdlib modules inside case subprocesses. `gov doctor` gains
the `argparse-shadow` check: when `argparse.__file__` resolves outside
the stdlib it exits 1 naming the file and the remedy
(`pip uninstall argparse`) — rule 5 instead of an unreadable crash.
Proof: self-test case `test_task_survives_pre37_argparse_shadow` runs
`gov task new` under a pre-3.7 argparse stub, first proving the stub
reproduces the exact TypeError (rule 6); pytest covers the bare
`gov task` error and doctor naming a live shadow; CI keeps the
reporter's environment alive in a `backport-shadow` job (wheel install
plus `argparse==1.4.0`, then CLI happy paths, `gov self-test`, and
`gov doctor` with the shadow promoted via PYTHONPATH).

## Alternatives considered

**Import-guard: refuse to run when argparse is not the stdlib.** Turns
"works" into "aborts" on machines where every other command already
worked; the hand-rolled check keeps the CLIs functional everywhere while
doctor names the shadow for the human to clean up.

**Fix only the environment (uninstall the backport).** Necessary on the
reporting machine, unshippable as a release: any user can have the
fossil installed, and nothing in the plane told them — the same red
would come back from a different machine.

**Keep `required=True`, fix only the self-test env.** Clears the
self-test red but leaves the CLI class-failure one promoted PYTHONPATH
away; the kwarg saves one line that the manual error message spends on
naming the choices anyway.

## Consequences

gov's subcommand CLIs now stay within the pre-3.7 argparse surface;
argparse-only conveniences added later (e.g. BooleanOptionalAction-style
flags) need the same hand-rolled treatment or a shadow check before
adoption.
