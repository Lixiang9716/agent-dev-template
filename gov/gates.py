#!/usr/bin/env python3
"""Gate runner.

Reads a gates.json (see docs/decisions.md D1/D2), runs each gate as a command
that exits non-zero on failure, and reports one outcome per gate:

    PASS    command exited 0
    FAIL    command exited non-zero
    TIMEOUT exceeded its timeoutMs
    MISSING the executable does not exist
    SKIP    a needed dependency had a blocking failure

Exit codes: 0 = all green; 1 = at least one blocking failure; 2 = config invalid.
Run order respects the ``needs`` DAG; ``concurrency`` caps parallel gate runs.

The only third-party dependency is Python 3.
"""
from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Any

BLOCKING_OUTCOMES = ("FAIL", "TIMEOUT", "MISSING")
OUTCOME_ORDER = ("FAIL", "TIMEOUT", "MISSING", "SKIP", "PASS")


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


def _command_variants(raw: Any) -> list[str]:
    """A command is a plain argv array (D1: single form, no shell variants)."""
    if isinstance(raw, list) and all(isinstance(p, str) for p in raw) and raw:
        return raw
    raise ConfigError("command must be a non-empty array of strings")


def load_config(path: str) -> tuple[dict[str, list[str]], list[Gate], int]:
    try:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
    except FileNotFoundError:
        raise ConfigError(f"{path} not found")
    except json.JSONDecodeError as e:
        raise ConfigError(f"{path} is not valid JSON: {e}")

    gates_raw = raw.get("gates", [])
    modes_raw = raw.get("modes", {})
    concurrency = raw.get("concurrency")

    gates: list[Gate] = []
    ids: set[str] = set()
    for i, g in enumerate(gates_raw):
        gid = g.get("id")
        if not isinstance(gid, str) or not gid:
            raise ConfigError(f"gate[{i}] has an empty or non-string id")
        if gid in ids:
            raise ConfigError(f"duplicate gate id: {gid}")
        ids.add(gid)
        try:
            command = _command_variants(g.get("command"))
        except ConfigError as e:
            raise ConfigError(f"gate '{gid}': {e}")
        gates.append(
            Gate(
                id=gid,
                command=command,
                label=g.get("label", ""),
                needs=[n for n in g.get("needs", [])],
                timeout_ms=g.get("timeoutMs"),
                allow_failure=bool(g.get("allowFailure", False)),
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
        if not isinstance(gate_list, list):
            raise ConfigError(f"mode '{name}' must be a list of gate ids")
        for gid in gate_list:
            if gid not in by_id:
                raise ConfigError(f"mode '{name}' references unknown gate '{gid}'")
        modes[name] = list(gate_list)

    return modes, gates, int(concurrency) if concurrency else 0


def _run_one(gate: Gate) -> tuple[Gate, str, str, bool]:
    """Run one gate; return (gate, outcome, detail, blocking_failed)."""
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
    if proc.returncode == 0:
        return gate, "PASS", "", False
    tail = (proc.stdout or "") + (proc.stderr or "")
    return gate, "FAIL", _tail(tail), True


def _tail(text: str, limit: int = 2000) -> str:
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[-limit:] + f"\n... (truncated, {len(text) - limit} more chars)"


def _summarize(name: str, gates: list[str]) -> str:
    if name is None:
        return ", ".join(gates)
    return f"{name}: {', '.join(gates)}"


def run_gates(
    gates: list[Gate],
    selection: list[str] | None,
    concurrency: int,
    fail_fast: bool,
) -> int:
    """Run the selected gates (all of them when selection is None)."""
    selected: list[Gate]
    if selection is None:
        selected = gates
    else:
        by_id = {g.id: g for g in gates}
        selected = [by_id[gid] for gid in selection]
    # Close over the needs DAG: dependents of an unselected gate still resolve.
    selected_ids = {g.id for g in selected}

    outcomes: dict[str, str] = {}
    details: dict[str, str] = {}
    blocking: dict[str, bool] = {}
    running: dict[str, Gate] = {}
    skipped: dict[str, list[str]] = {}

    # A gate can run once every selected need is settled non-blocking.
    indegree = {g.id: len([n for n in g.needs if n in selected_ids]) for g in selected}
    dependents: dict[str, list[str]] = {g.id: [] for g in selected}
    for g in selected:
        for dep in g.needs:
            if dep in selected_ids:
                dependents[dep].append(g.id)

    ready = [g for g in selected if indegree[g.id] == 0]

    with ThreadPoolExecutor(max_workers=concurrency or 1) as pool:
        pending: dict[Any, Gate] = {}
        for g in ready:
            pending[pool.submit(_run_one, g)] = g
            running[g.id] = g

        stop = False
        while pending and not stop:
            for fut in list(as_completed(pending)):
                gate = pending.pop(fut)
                g, outcome, detail, is_blocking = fut.result()
                outcomes[g.id] = outcome
                details[g.id] = detail
                blocking[g.id] = is_blocking and not g.allow_failure
                print(_outcome_line(g, outcome, detail), flush=True)
                if fail_fast and blocking[g.id]:
                    stop = True
                    # Cancel remaining futures.
                    for other in pending:
                        other.cancel()
                    pending = {}
                    break
                for child in dependents[g.id]:
                    indegree[child] -= 1
                    if indegree[child] == 0:
                        child_gate = next(c for c in selected if c.id == child)
                        if _needs_blocked(child_gate, selected_ids, blocking):
                            outcomes[child] = "SKIP"
                            skipped[child] = [
                                n for n in child_gate.needs if blocking.get(n, False)
                            ]
                            print(
                                f"SKIP {child} (needs failed: {', '.join(skipped[child])})",
                                flush=True,
                            )
                            blocking[child] = False
                            for grandchild in dependents[child]:
                                indegree[grandchild] -= 1
                                if indegree[grandchild] == 0:
                                    gc = next(c for c in selected if c.id == grandchild)
                                    pending[pool.submit(_run_one, gc)] = gc
                        else:
                            pending[pool.submit(_run_one, child_gate)] = child_gate

    # Report blocking failures with their command output tail.
    failed = [gid for gid in outcomes if blocking.get(gid, False)]
    for gid in failed:
        if details[gid]:
            print(f"--- output of {gid} ---", flush=True)
            print(details[gid], flush=True)

    counts = {o: sum(1 for v in outcomes.values() if v == o) for o in OUTCOME_ORDER}
    parts = [f"{n} {o.lower()}" for o, n in counts.items() if n]
    print(
        f"{len(outcomes)} gates: " + (", ".join(parts) if parts else "none ran"),
        flush=True,
    )
    return 1 if failed else 0


def _needs_blocked(
    gate: Gate, selected_ids: set[str], blocking: dict[str, bool]
) -> bool:
    return any(blocking.get(n, False) for n in gate.needs if n in selected_ids)


def _outcome_line(gate: Gate, outcome: str, detail: str) -> str:
    if outcome == "FAIL" and detail:
        return f"FAIL {gate.id}"
    return f"{outcome} {gate.id}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the governance gate DAG.")
    parser.add_argument("--config", default="gates.json")
    parser.add_argument("--mode", default=None, help="mode name from gates.json")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    try:
        modes, gates, concurrency = load_config(args.config)
    except ConfigError as e:
        print(f"config error: {e}", file=sys.stderr)
        return 2

    selection = None
    if args.mode:
        if args.mode not in modes:
            print(
                f"config error: unknown mode '{args.mode}' "
                f"(known: {', '.join(modes) or 'none'})",
                file=sys.stderr,
            )
            return 2
        selection = modes[args.mode]
    elif not gates:
        print("no gates configured", file=sys.stderr)
        return 0

    if not args.verbose:
        # Silence nothing here; per-gate lines are the report. Verbosity is
        # accepted for forward compatibility with a quieter default later.
        pass

    return run_gates(gates, selection, concurrency, args.fail_fast)


if __name__ == "__main__":
    raise SystemExit(main())
