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

    return modes, gates, concurrency or 0, default_mode


def _run_one(gate: Gate) -> tuple[Gate, str, str, bool]:
    """Run one gate; return (gate, outcome, detail, blocking_failed).

    A passing gate's output is kept as detail too: exit 0 with something
    to say (a warning, an advisory) must stay visible — passing never
    silences a gate (D20 amends D2's "passes are silent").
    """
    exe = gate.command[0]
    if shutil.which(exe) is None:
        return gate, "MISSING", f"command not found: {exe}", True
    try:
        proc = subprocess.run(
            gate.command,
            capture_output=True,
            text=True,
            timeout=gate.timeout_ms / 1000 if gate.timeout_ms else None,
        )
    except subprocess.TimeoutExpired:
        return gate, "TIMEOUT", f"exceeded {gate.timeout_ms}ms", True
    output = ((proc.stdout or "") + (proc.stderr or "")).strip()
    if proc.returncode == 0:
        return gate, "PASS", output, False
    return gate, "FAIL", _tail(output), True


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
) -> int:
    """Run the selected gates (every enabled gate when selection is None)."""
    for g in gates:
        if not g.enabled:
            print(f"DISABLED {g.id}", flush=True)
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
                    skipped_set.add(child)
                    print(
                        f"SKIP {child} (needs failed: {', '.join(failed_needs)})",
                        flush=True,
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
                g, outcome, detail, is_blocking = fut.result()
                outcomes[g.id] = outcome
                details[g.id] = detail
                blocking[g.id] = is_blocking and not g.allow_failure
                print(_outcome_line(g, outcome), flush=True)
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
            print(f"--- output of {gid} ---", flush=True)
        else:
            # allowFailure: report loudly, block never (advisory, D2/D13).
            print(f"--- output of {gid} (advisory; allowFailure) ---", flush=True)
        print(details[gid], flush=True)

    # A pass that said something (a warning, an advisory) stays visible:
    # last 3 lines, exit code and PASS outcome unchanged (D20).
    for gid, outcome in outcomes.items():
        if outcome != "PASS" or not details[gid]:
            continue
        lines = details[gid].splitlines()
        shown = lines[-3:]
        omitted = len(lines) - len(shown)
        print(f"--- output of {gid} (passed with output) ---", flush=True)
        print("\n".join(shown), flush=True)
        if omitted > 0:
            print(f"... ({omitted} earlier line(s) not shown)", flush=True)

    if failed:
        print(f"--- summary: {len(failed)} blocking failure(s) ---", flush=True)
        for gid in failed:
            first = details[gid].strip().splitlines()[0] if details[gid].strip() else ""
            print(f"{gid}: {first}" if first else f"{gid}:", flush=True)
        print("rerun a single gate: gov run --gate <id>", flush=True)

    counts = {o: sum(1 for v in outcomes.values() if v == o) for o in OUTCOME_ORDER}
    parts = [f"{n} {o.lower()}" for o, n in counts.items() if n]
    print(
        f"{len(outcomes)} gates: " + (", ".join(parts) if parts else "none ran"),
        flush=True,
    )
    return 1 if failed else 0


def _outcome_line(gate: Gate, outcome: str) -> str:
    if gate.allow_failure and outcome in BLOCKING_OUTCOMES:
        return f"{outcome} {gate.id} (advisory; allowFailure)"
    return f"{outcome} {gate.id}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="gov run", description="Run the governance gate DAG.")
    parser.add_argument("--config", default="gates.json")
    parser.add_argument("--mode", default=None,
                        help="mode name from gates.json (overrides defaultMode)")
    parser.add_argument("--base", default=None,
                        help="select gates whose 'paths' match the diff against this git ref")
    parser.add_argument("--gate", default=None, help="run a single gate by id")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    try:
        modes, gates, concurrency, default_mode = load_config(args.config)
    except ConfigError as e:
        print(f"config error: {e}", file=sys.stderr)
        return 2

    if args.gate and (args.mode or args.base):
        print("gov run: --gate cannot be combined with --mode or --base", file=sys.stderr)
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
        print(
            f"scope vs {args.base}: {len(selection)}/{len([g for g in gates if g.enabled])} "
            f"gate(s) selected" + (f"; out of scope: {', '.join(out)}" if out else ""),
            flush=True,
        )
    elif default_mode:
        selection = modes[default_mode]
    elif not gates:
        print("no gates configured", file=sys.stderr)
        return 0

    return run_gates(gates, selection, concurrency, args.fail_fast)


if __name__ == "__main__":
    raise SystemExit(main())
