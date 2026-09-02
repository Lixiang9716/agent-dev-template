#!/usr/bin/env python3
"""Gate duration trends from .gov/history/ (D28, wish 12).

``gov run --record`` appends one JSON line per run to
``.gov/history/gates.jsonl`` — append-only, the plane's own philosophy.
This command reads it back: per gate, the p50 of the earlier half of the
window vs the later half, so a duration regression is a sentence, not a
memory ("tests p50 1.2s → 2.6s (×2.2)"). Runs stay stateless unless
``--record`` is asked for; the history file is outside every gates.json
validation scope by construction.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:  # package context (`gov ...`)
    from .root import anchor_to_git_root
except ImportError:  # direct script execution
    from root import anchor_to_git_root

HISTORY = Path(".gov/history/gates.jsonl")


def _p50(values: list[int]) -> float:
    vs = sorted(values)
    if not vs:
        return 0.0
    mid = len(vs) // 2
    return float(vs[mid]) if len(vs) % 2 else (vs[mid - 1] + vs[mid]) / 2


def _fmt(ms: float) -> str:
    return f"{ms / 1000:.1f}s" if ms >= 1000 else f"{ms:.0f}ms"


def main(argv: list[str] | None = None) -> int:
    anchor_to_git_root("trend")
    parser = argparse.ArgumentParser(
        prog="gov trend",
        description="Gate duration trends from .gov/history/gates.jsonl.",
    )
    parser.add_argument("--last", type=int, default=20,
                        help="how many recorded runs to consider (default: 20)")
    parser.add_argument("--gate", default=None,
                        help="show a single gate only")
    parser.add_argument("--base", default=None,
                        help="git ref: split early/late at its commit date "
                             "(default: the window's halfway point)")
    args = parser.parse_args(argv)

    if not HISTORY.is_file():
        print("trend: no history yet — never recorded; runs record by "
              "default now, so this appears after your next gov run")
        return 0
    runs = []
    for line in HISTORY.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            runs.append(json.loads(line))
        except json.JSONDecodeError:
            print(f"trend: skipping a malformed history line", file=sys.stderr)
    runs = runs[-args.last:]
    if len(runs) < 2:
        print(f"trend: {len(runs)} run(s) recorded (history exists) — "
              "need at least 2 to compare")
        return 0

    durations: dict[str, list[int]] = {}
    outcomes: dict[str, list[str]] = {}
    for run in runs:
        for rec in run.get("gates", []):
            gid = rec.get("gate")
            if gid is None:
                continue
            durations.setdefault(gid, []).append(int(rec.get("duration_ms", 0)))
            outcomes.setdefault(gid, []).append(rec.get("outcome", "?"))

    if args.base:
        import subprocess as _sp
        proc = _sp.run(["git", "show", "-s", "--format=%cI", args.base],
                       capture_output=True, text=True)
        if proc.returncode != 0 or not proc.stdout.strip():
            print(f"trend: cannot resolve {args.base!r}: {proc.stderr.strip()}",
                  file=sys.stderr)
            return 2
        from datetime import datetime as _dt

        split_at = _dt.fromisoformat(proc.stdout.strip())

        def _ts(run):
            try:
                return _dt.fromisoformat(run.get("ts", ""))
            except ValueError:
                return None

        early_run_ids = [i for i, r in enumerate(runs)
                         if _ts(r) and _ts(r) <= split_at]
        late_run_ids = [i for i, r in enumerate(runs)
                        if _ts(r) and _ts(r) > split_at]
        print(f"  split at {args.base} ({proc.stdout.strip()})")
    else:
        half = len(runs) // 2
        early_run_ids = range(0, half)
        late_run_ids = range(half, len(runs))

    def _window(gid: str, run_ids) -> list[int]:
        out = []
        for i in run_ids:
            for rec in runs[i].get("gates", []):
                if rec.get("gate") == gid:
                    out.append(int(rec.get("duration_ms", 0)))
        return out

    print(f"trend: {len(runs)} run(s) in {HISTORY}")
    movers, stable = [], []
    for gid in sorted(durations):
        if args.gate and gid != args.gate:
            continue
        early, late = _window(gid, early_run_ids), _window(gid, late_run_ids)
        if not early or not late:
            continue
        e, l = _p50(early), _p50(late)
        ratio = (l / e) if e else float("inf")
        line = f"  {gid:<16} p50 {_fmt(e)} → {_fmt(l)}"
        if ratio >= 1.5:
            movers.append(f"{line} (×{ratio:.1f} ↑)")
        elif ratio <= 0.67:
            movers.append(f"{line} (×{ratio:.1f} ↓)")
        else:
            stable.append(f"{line} — stable over {len(durations[gid])} run(s)")
    for m in movers:
        print(m)
    for s in stable:
        print(s)
    if movers:
        print("  (a mover compares window halves — it is a question to "
              "investigate, not a verdict; --gate <id> focuses one gate)")
    else:
        print("  no duration movers in this window")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
