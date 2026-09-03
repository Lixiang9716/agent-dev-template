#!/usr/bin/env python3
"""Gate runner.

Reads a gates.json (see docs/decisions.md D1/D2), runs each gate as a command
that exits non-zero on failure, and reports one outcome per gate:

    PASS    command exited 0
    FAIL    command exited non-zero
    TIMEOUT exceeded its timeoutMs
    MISSING the executable does not exist
    SKIP    a needed dependency did not pass (blocking failure, or was skipped)

Exit codes: 0 = all green; 1 = at least one blocking failure; 2 = config invalid.
Run order respects the ``needs`` DAG; ``concurrency`` caps parallel gate runs.
SKIP propagates transitively: a gate whose need was skipped is itself skipped,
never silently run and reported PASS.

Selection: ``--mode <name>`` runs that mode's gate list; otherwise the
top-level ``defaultMode`` runs (when configured); otherwise every enabled
gate. ``--base <ref>`` instead selects the gates whose ``paths`` globs match
the diff against that git ref (unpathed gates always run), and ``--gate <id>``
runs one gate. ``enabled: false`` parks a gate outside every run — reported
as a ``DISABLED`` line, never silently dropped — so "off" stays written down
in the config instead of deleting the definition. A gate with
``allowFailure: true`` reports its failure output tagged ``advisory``
without affecting the exit code. Blocking failures end with a summary block
naming each failed gate, its first output line, and how to rerun it alone.

The only third-party dependency is Python 3.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Any

BLOCKING_OUTCOMES = ("FAIL", "TIMEOUT", "MISSING")
OUTCOME_ORDER = ("FAIL", "TIMEOUT", "MISSING", "SKIP", "PASS")

_RX_CACHE: dict[str, re.Pattern[str]] = {}


def _glob_regex(pattern: str) -> re.Pattern[str]:
    """Compile a path glob: ``**`` spans directories, ``*``/``?`` do not."""
    rx = _RX_CACHE.get(pattern)
    if rx is not None:
        return rx
    out: list[str] = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "*":
            if pattern[i : i + 2] == "**":
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    rx = re.compile("^" + "".join(out) + "$")
    _RX_CACHE[pattern] = rx
    return rx


class ConfigError(Exception):
    """gates.json is invalid; fix the file, not the project."""


@dataclass
class Gate:
    id: str
    command: list[str]
    label: str = ""
    needs: list[str] = field(default_factory=list)
    timeout_ms: int | None = None
    allow_failure: bool = False
    enabled: bool = True
    paths: list[str] = field(default_factory=list)


def _require_object(value: Any, what: str) -> dict:
    if not isinstance(value, dict):
        raise ConfigError(f"{what} must be an object")
    return value


def _require_str_list(value: Any, what: str) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
        raise ConfigError(f"{what} must be an array of strings")
    return value


def _require_positive_int(value: Any, what: str) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ConfigError(f"{what} must be a positive integer")
    return value


def _command_variants(raw: Any) -> list[str]:
    """A command is a plain argv array (D1: single form, no shell variants)."""
    if isinstance(raw, list) and all(isinstance(p, str) for p in raw) and raw:
        return raw
    raise ConfigError("command must be a non-empty array of strings")


def load_config(path: str) -> tuple[dict[str, list[str]], list[Gate], int, str | None]:
    """Return (modes, gates, concurrency, default_mode).

    ``default_mode`` is None when the config declares none — callers then
    run every enabled gate (the historical default).
    """
    try:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
    except FileNotFoundError:
        raise ConfigError(f"{path} not found")
    except json.JSONDecodeError as e:
        raise ConfigError(f"{path} is not valid JSON: {e}")

    raw = _require_object(raw, "the config root")
    # D29: unknown keys abort loud — a typo like "enable": false silently
    # parks nothing, which is exactly the quiet back door D24 closed.
    allowed_top = {"modes", "defaultMode", "concurrency", "gates"}
    unknown_top = sorted(set(raw) - allowed_top)
    if unknown_top:
        raise ConfigError(
            f"unknown top-level key(s): {', '.join(unknown_top)} "
            f"(known: {', '.join(sorted(allowed_top))})"
        )
    gates_raw = raw.get("gates", [])
    if not isinstance(gates_raw, list):
        raise ConfigError("'gates' must be an array")
    modes_raw = raw.get("modes", {})
    if modes_raw is not None and not isinstance(modes_raw, dict):
        raise ConfigError("'modes' must be an object")
    concurrency = _require_positive_int(raw.get("concurrency"), "'concurrency'")

    gates: list[Gate] = []
    ids: set[str] = set()
    for i, g in enumerate(gates_raw):
        g = _require_object(g, f"gates[{i}]")
        allowed_gate = {"id", "command", "label", "needs", "timeoutMs",
                        "allowFailure", "enabled", "paths"}
        unknown = sorted(set(g) - allowed_gate)
        if unknown:
            known_id = g.get("id") or f"gates[{i}]"
            raise ConfigError(
                f"gate '{known_id}': unknown key(s): {', '.join(unknown)} "
                f"(known: {', '.join(sorted(allowed_gate))})"
            )
        gid = g.get("id")
        if not isinstance(gid, str) or not gid:
            raise ConfigError(f"gates[{i}] has an empty or non-string id")
        if gid in ids:
            raise ConfigError(f"duplicate gate id: {gid}")
        ids.add(gid)
        try:
            command = _command_variants(g.get("command"))
        except ConfigError as e:
            raise ConfigError(f"gate '{gid}': {e}")
        label = g.get("label", "")
        if not isinstance(label, str):
            raise ConfigError(f"gate '{gid}': 'label' must be a string")
        needs = g.get("needs", [])
        if not isinstance(needs, list) or not all(isinstance(n, str) for n in needs):
            raise ConfigError(f"gate '{gid}': 'needs' must be an array of strings")
        timeout = g.get("timeoutMs")
        if timeout is not None and (isinstance(timeout, bool) or not isinstance(timeout, int) or timeout <= 0):
            raise ConfigError(f"gate '{gid}': 'timeoutMs' must be a positive integer")
        allow_failure = g.get("allowFailure", False)
        if not isinstance(allow_failure, bool):
            raise ConfigError(f"gate '{gid}': 'allowFailure' must be a boolean")
        enabled = g.get("enabled", True)
        if not isinstance(enabled, bool):
            raise ConfigError(f"gate '{gid}': 'enabled' must be a boolean")
        paths = g.get("paths", [])
        if not isinstance(paths, list) or not all(isinstance(p, str) for p in paths):
            raise ConfigError(f"gate '{gid}': 'paths' must be an array of strings")
        if any(not p for p in paths):
            raise ConfigError(f"gate '{gid}': 'paths' must not contain empty strings")
        gates.append(
            Gate(
                id=gid,
                command=command,
                label=label,
                needs=list(needs),
                timeout_ms=timeout,
                allow_failure=allow_failure,
                enabled=enabled,
                paths=list(paths),
            )
        )

    # Validate needs references.
    by_id = {g.id: g for g in gates}
    for g in gates:
        for dep in g.needs:
            if dep not in by_id:
                raise ConfigError(f"gate '{g.id}' needs unknown gate '{dep}'")

    # Cycle detection via Kahn's algorithm over the needs DAG.
    indegree = {g.id: 0 for g in gates}
    dependents: dict[str, list[str]] = {g.id: [] for g in gates}
    for g in gates:
        for dep in g.needs:
            indegree[g.id] += 1
            dependents[dep].append(g.id)
    order: list[str] = []
    ready = [gid for gid, d in indegree.items() if d == 0]
    while ready:
        gid = ready.pop()
        order.append(gid)
        for child in dependents[gid]:
            indegree[child] -= 1
            if indegree[child] == 0:
                ready.append(child)
    if len(order) != len(gates):
        in_cycle = sorted(gid for gid, d in indegree.items() if d > 0)
        raise ConfigError(f"cycle among gates: {', '.join(in_cycle)}")

    modes: dict[str, list[str]] = {}
    for name, gate_list in modes_raw.items():
        gate_list = _require_str_list(gate_list, f"mode '{name}'")
        for gid in gate_list:
            if gid not in by_id:
                raise ConfigError(f"mode '{name}' references unknown gate '{gid}'")
        modes[name] = list(gate_list)

    default_mode = raw.get("defaultMode")
    if default_mode is not None:
        if not isinstance(default_mode, str) or not default_mode:
            raise ConfigError("'defaultMode' must be a non-empty string")
        if default_mode not in modes:
            known = ", ".join(modes) or "none"
            raise ConfigError(
                f"'defaultMode' references unknown mode '{default_mode}' (known: {known})"
            )

    # Reachability (D24): with modes defined, an enabled gate that belongs
    # to no mode silently never runs — a silent parking mechanism the
    # design never sanctioned. Parking is "enabled": false — the one loud
    # mechanism (a DISABLED line). Mode omission is not a parking lot.
    if modes:
        members = {gid for ids in modes.values() for gid in ids}
        unreachable = sorted(g.id for g in gates if g.enabled and g.id not in members)
        if unreachable:
            raise ConfigError(
                f"enabled gate(s) not in any mode: {', '.join(unreachable)} — "
                'park a gate with "enabled": false (the one loud mechanism); '
                "mode omission silently never runs (rules 1/6)"
            )

    return modes, gates, concurrency or 0, default_mode


def _history_path() -> Path:
    """#23/D32: history belongs to the repository, not the checkout —
    linked worktrees record into the main checkout's .gov/history (the
    git common dir's parent), so ledgers do not fragment per worktree."""
    try:
        proc = subprocess.run(["git", "rev-parse", "--git-common-dir"],
                              capture_output=True, text=True)
        if proc.returncode == 0:
            common = Path(proc.stdout.strip()).resolve()
            root = common.parent
            if root != Path.cwd():
                return root / ".gov" / "history" / "gates.jsonl"
    except OSError:
        pass
    return Path(".gov/history/gates.jsonl")


def _run_one(gate: Gate) -> tuple[Gate, str, str, bool]:
    """Run one gate; return (gate, outcome, detail, blocking_failed).

    A passing gate's output is kept as detail too: exit 0 with something
    to say (a warning, an advisory) must stay visible — passing never
    silences a gate (D20 amends D2's "passes are silent").
    """
    exe = gate.command[0]
    started = time.monotonic()
    if shutil.which(exe) is None:
        return gate, "MISSING", f"command not found: {exe}", True, 0
    try:
        proc = subprocess.run(
            gate.command,
            capture_output=True,
            text=True,
            timeout=gate.timeout_ms / 1000 if gate.timeout_ms else None,
        )
    except subprocess.TimeoutExpired:
        return gate, "TIMEOUT", f"exceeded {gate.timeout_ms}ms", True, gate.timeout_ms
    duration_ms = int((time.monotonic() - started) * 1000)
    output = ((proc.stdout or "") + (proc.stderr or "")).strip()
    if proc.returncode == 0:
        return gate, "PASS", output, False, duration_ms
    return gate, "FAIL", _tail(output), True, duration_ms


def _tail(text: str, limit: int = 2000) -> str:
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[-limit:] + f"\n... (truncated, {len(text) - limit} more chars)"


def _changed_files(base: str) -> list[str] | None:
    """Files changed against ``base`` (tracked diff + untracked); None on error."""
    files: set[str] = set()
    for cmd in (
        ["git", "diff", "--name-only", base],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            print(
                f"gov run: --base {base!r} failed: {proc.stderr.strip()}",
                file=sys.stderr,
            )
            return None
        files.update(f for f in proc.stdout.splitlines() if f)
    return sorted(files)


def _select_by_paths(
    gates: list[Gate], changed: list[str]
) -> tuple[list[str], list[str]]:
    """Gates whose paths match the diff (unpathed gates always run)."""
    selected: list[str] = []
    out: list[str] = []
    for g in gates:
        if not g.enabled:
            continue
        if not g.paths or any(
            _glob_regex(p).match(f) for p in g.paths for f in changed
        ):
            selected.append(g.id)
        else:
            out.append(g.id)
    return selected, out


def run_gates(
    gates: list[Gate],
    selection: list[str] | None,
    concurrency: int,
    fail_fast: bool,
    json_mode: bool = False,
    record_path: Path | None = None,
    changed: list[str] | None = None,
) -> int:
    """Run the selected gates (every enabled gate when selection is None).

    In ``json_mode`` the human-readable report goes to stderr and stdout
    carries exactly one JSON array — one object per gate, in config order:
    ``{gate, outcome, blocking, duration_ms, detail}`` (D25). Disabled
    gates appear with outcome ``DISABLED``.
    """

    def emit(text: str) -> None:
        if json_mode:
            print(text, file=sys.stderr, flush=True)
        else:
            print(text, flush=True)

    for g in gates:
        if not g.enabled:
            emit(f"DISABLED {g.id}")
    active = [g for g in gates if g.enabled]
    if selection is None:
        selected = active
    else:
        by_id = {g.id: g for g in gates}
        selected = [by_id[gid] for gid in selection if by_id[gid].enabled]
    selected_ids = {g.id for g in selected}
    by_id = {g.id: g for g in selected}

    outcomes: dict[str, str] = {}
    details: dict[str, str] = {}
    blocking: dict[str, bool] = {}
    durations: dict[str, int] = {}
    skipped_set: set[str] = set()

    indegree = {g.id: len([n for n in g.needs if n in selected_ids]) for g in selected}
    dependents: dict[str, list[str]] = {g.id: [] for g in selected}
    for g in selected:
        for dep in g.needs:
            if dep in selected_ids:
                dependents[dep].append(g.id)

    ready = [g for g in selected if indegree[g.id] == 0]

    with ThreadPoolExecutor(max_workers=concurrency or 1) as pool:
        pending: dict[Any, Gate] = {}

        def enqueue(gate: Gate) -> None:
            pending[pool.submit(_run_one, gate)] = gate

        def settle(gid: str) -> None:
            """Propagate a settled gate to its dependents; SKIP transitively."""
            for child in dependents[gid]:
                indegree[child] -= 1
                if indegree[child] != 0:
                    continue
                child_gate = by_id[child]
                failed_needs = [
                    n
                    for n in child_gate.needs
                    if n in selected_ids and (blocking.get(n, False) or n in skipped_set)
                ]
                if failed_needs:
                    outcomes[child] = "SKIP"
                    durations[child] = 0
                    skipped_set.add(child)
                    emit(
                        f"SKIP {child} (needs failed: {', '.join(failed_needs)})"
                    )
                    settle(child)
                else:
                    enqueue(child_gate)

        for g in ready:
            enqueue(g)

        stop = False
        while pending and not stop:
            for fut in list(as_completed(pending)):
                gate = pending.pop(fut)
                g, outcome, detail, is_blocking, duration_ms = fut.result()
                outcomes[g.id] = outcome
                details[g.id] = detail
                durations[g.id] = duration_ms
                blocking[g.id] = is_blocking and not g.allow_failure
                scope_n = None
                if changed is not None and g.paths:
                    scope_n = sum(1 for f in changed
                                  if any(_glob_regex(pt).match(f) for pt in g.paths))
                emit(_outcome_line(g, outcome, scope_n))
                if fail_fast and blocking[g.id]:
                    stop = True
                    for other in pending:
                        other.cancel()
                    pending = {}
                    break
                settle(g.id)

    failed = [gid for gid in outcomes if blocking.get(gid, False)]
    for gid, outcome in outcomes.items():
        if outcome not in BLOCKING_OUTCOMES or not details[gid]:
            continue
        if blocking.get(gid, False):
            emit(f"--- output of {gid} ---")
        else:
            # allowFailure: report loudly, block never (advisory, D2/D13).
            emit(f"--- output of {gid} (advisory; allowFailure) ---")
        emit(details[gid])

    # A pass that said something (a warning, an advisory) stays visible:
    # last 3 lines, exit code and PASS outcome unchanged (D20).
    for gid, outcome in outcomes.items():
        if outcome != "PASS" or not details[gid]:
            continue
        lines = details[gid].splitlines()
        shown = lines[-3:]
        omitted = len(lines) - len(shown)
        emit(f"--- output of {gid} (passed with output) ---")
        emit("\n".join(shown))
        if omitted > 0:
            emit(f"... ({omitted} earlier line(s) not shown)")

    if failed:
        emit(f"--- summary: {len(failed)} blocking failure(s) ---")
        for gid in failed:
            first = details[gid].strip().splitlines()[0] if details[gid].strip() else ""
            emit(f"{gid}: {first}" if first else f"{gid}:")
        emit("rerun a single gate: gov run --gate <id>")

    counts = {o: sum(1 for v in outcomes.values() if v == o) for o in OUTCOME_ORDER}
    parts = [f"{n} {o.lower()}" for o, n in counts.items() if n]
    emit(
        f"{len(outcomes)} gates: " + (", ".join(parts) if parts else "none ran")
    )

    records = []
    for g in gates:
        if not g.enabled:
            records.append(
                {"gate": g.id, "outcome": "DISABLED", "blocking": False,
                 "duration_ms": 0, "detail": ""}
            )
        elif g.id in outcomes:
            records.append(
                {"gate": g.id, "outcome": outcomes[g.id],
                 "blocking": blocking.get(g.id, False),
                 "duration_ms": durations.get(g.id, 0),
                 "detail": details.get(g.id, "")}
            )
    if json_mode:
        print(json.dumps(records, indent=2))
    if record_path is not None:
        # D28/D29: append-only history — one line per run, the plane's
        # own philosophy. Recording is the default (the file is local
        # and gitignored); --no-record opts out.
        record_path.parent.mkdir(parents=True, exist_ok=True)
        with record_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(
                {"ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                 "gates": records}, separators=(",", ":")
            ) + "\n")
    return 1 if failed else 0


def _outcome_line(gate: Gate, outcome: str, in_scope: int | None = None) -> str:
    parts = []
    if gate.allow_failure and outcome in BLOCKING_OUTCOMES:
        parts.append("(advisory; allowFailure)")
    if in_scope is not None:
        # #21/D32: a scan over zero matched files must not read like a scan.
        parts.append(f"{in_scope} in change scope" if in_scope
                     else "0 in change scope — nothing changed matches")
    return f"{outcome} {gate.id}" + (" " + " ".join(parts) if parts else "")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="gov run", description="Run the governance gate DAG.")
    parser.add_argument("--config", default="gates.json")
    parser.add_argument("--mode", default=None,
                        help="mode name from gates.json (overrides defaultMode)")
    parser.add_argument("--base", default=None,
                        help="select gates whose 'paths' match the diff against this git ref")
    parser.add_argument("--gate", default=None, help="run a single gate by id")
    parser.add_argument("--every-gate", action="store_true",
                        help="run every enabled gate — the full matrix, ignoring "
                             "modes and defaultMode (CI owns this)")
    parser.add_argument("--no-record", action="store_true",
                        help="do not append this run to .gov/history/gates.jsonl "
                             "(recording is the default; see gov trend)")
    parser.add_argument("--json", action="store_true",
                        help="machine-readable: stdout is exactly one JSON array "
                             "of {gate, outcome, blocking, duration_ms, detail}; "
                             "the human report moves to stderr")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    try:
        modes, gates, concurrency, default_mode = load_config(args.config)
    except ConfigError as e:
        print(f"config error: {e}", file=sys.stderr)
        return 2

    explicit = [flag for flag, on in (("--gate", args.gate), ("--mode", args.mode),
                                      ("--base", args.base), ("--every-gate", args.every_gate)) if on]
    if len(explicit) > 1:
        print(f"gov run: {' and '.join(explicit)} cannot be combined", file=sys.stderr)
        return 2

    selection = None
    if args.gate:
        known = {g.id for g in gates}
        if args.gate not in known:
            print(
                f"gov run: unknown gate '{args.gate}' (known: {', '.join(sorted(known)) or 'none'})",
                file=sys.stderr,
            )
            return 2
        by_id = {g.id: g for g in gates}
        if not by_id[args.gate].enabled:
            # N4/D24: explicitly naming a parked gate is operator error —
            # a silent green hides it. Parking is visible; so is this.
            print(
                f"gov run: gate '{args.gate}' is disabled — re-enable it or "
                "pick another",
                file=sys.stderr,
            )
            return 2
        selection = [args.gate]
    elif args.mode:
        if args.mode not in modes:
            print(
                f"config error: unknown mode '{args.mode}' "
                f"(known: {', '.join(modes) or 'none'})",
                file=sys.stderr,
            )
            return 2
        selection = modes[args.mode]
    elif args.base:
        changed = _changed_files(args.base)
        if changed is None:
            return 2
        selection, out = _select_by_paths(gates, changed)
        scope_line = (
            f"scope vs {args.base}: {len(selection)}/{len([g for g in gates if g.enabled])} "
            f"gate(s) selected" + (f"; out of scope: {', '.join(out)}" if out else "")
        )
        if args.json:  # stdout carries exactly one JSON value (D26)
            print(scope_line, file=sys.stderr, flush=True)
        else:
            print(scope_line, flush=True)
    elif args.every_gate:
        selection = None  # every enabled gate — the explicit full matrix
    elif default_mode:
        selection = modes[default_mode]
    elif not gates:
        print("no gates configured", file=sys.stderr)
        return 0

    changed = None
    if any(g.paths for g in gates):
        # #21/D32: annotate path-scoped gates with how many changed files
        # they cover; best-effort (git missing -> no annotation).
        probe = _changed_files(args.base) if args.base else _changed_files("HEAD")
        if probe is not None:
            changed = probe

    return run_gates(gates, selection, concurrency, args.fail_fast,
                     json_mode=args.json,
                     record_path=None if args.no_record
                     else _history_path(), changed=changed)


if __name__ == "__main__":
    raise SystemExit(main())
