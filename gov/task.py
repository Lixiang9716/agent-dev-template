#!/usr/bin/env python3
"""Task cards for subagent briefs — a versioned rules pin, not pasted prose.

Orchestrators hand subagents briefs that re-embed the repo's governance
rules by hand: half a page of restated discipline per brief, drift-prone
(a rule adoption silently outdates every template still being pasted) and
unverifiable. A task card replaces the boilerplate with a one-line pin
(``obey rules@<hash>``) plus the task's acceptance checklist, and closes
with a verifiable receipt (issue #125):

- ``gov task new "Title" --check "..."`` writes ``.gov/tasks/T-0001-*.json``
  referencing the CURRENT rule set by content hash (``.gov/rules.md`` +
  ``gates.json``, note conventions included — they live inside rules.md);
  the printed brief line replaces the boilerplate;
- ``gov task check`` recomputes the hash and names every card whose pin is
  stale after a governance adoption (also a gate, scoped to
  ``.gov/tasks/**``), and re-verifies closed cards' receipts;
- ``gov task close T-0001`` runs the gate DAG now and, only on an all-green
  run, records the receipt (outcomes + rules hash + timestamp) in the card.

Fail loud throughout (rule 5): missing rule files, malformed cards, and
ambiguous id prefixes abort with the offending name.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

try:  # package context (`gov ...`)
    from .root import anchor_to_git_root
except ImportError:  # direct script execution
    from root import anchor_to_git_root

TASKS_DIR = Path(".gov/tasks")
# The rule set a brief pins: rules.md (which embeds the note conventions,
# rule 3/4) plus the gate DAG that enforces them. Sorted for a stable hash.
RULE_FILES = (".gov/rules.md", "gates.json")
ID_RE = re.compile(r"^T-\d{4}$")
CARD_RE = re.compile(r"^(T-\d{4})(?:-(.+))?\.json$")


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rules_hash(root: Path | None = None) -> tuple[str, dict[str, str]]:
    """(combined hash, per-file hashes) over the current rule set.

    Missing rule files abort loud: a hash over a half-absent rule set would
    pin something the project never agreed to.
    """
    root = root or Path.cwd()
    parts: list[str] = []
    files: dict[str, str] = {}
    for rel in RULE_FILES:
        path = root / rel
        if not path.is_file():
            print(f"task: rule-set file {rel} not found — is this a "
                  "gov-initialized project?", file=sys.stderr)
            raise SystemExit(2)
        digest = _sha256_file(path)
        files[rel] = digest
        parts.append(f"{rel}:{digest}")
    combined = hashlib.sha256("\n".join(parts).encode()).hexdigest()
    return combined, files


def brief_line(combined: str) -> str:
    """The one line a brief carries instead of the boilerplate."""
    return f"obey rules@{combined[:12]}"


def _load_cards() -> list[tuple[str, Path, dict]]:
    """(id, path, card) sorted by id; malformed cards abort loud."""
    if not TASKS_DIR.is_dir():
        return []
    cards: list[tuple[str, Path, dict]] = []
    for p in sorted(TASKS_DIR.glob("*.json")):
        m = CARD_RE.match(p.name)
        if not m:
            print(f"task: {p.name}: card filenames must be "
                  "T-<4 digits>-<slug>.json", file=sys.stderr)
            raise SystemExit(2)
        try:
            card = json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            print(f"task: {p.name}: malformed JSON ({e})", file=sys.stderr)
            raise SystemExit(2)
        if not isinstance(card, dict) or "id" not in card or "rules" not in card:
            print(f"task: {p.name}: card needs 'id' and 'rules' fields",
                  file=sys.stderr)
            raise SystemExit(2)
        cards.append((card["id"], p, card))
    return cards


def _next_id(cards: list[tuple[str, Path, dict]]) -> str:
    used = {cid for cid, _, _ in cards}
    n = 1
    while f"T-{n:04d}" in used:
        n += 1
    return f"T-{n:04d}"


def _slugify(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    return slug[:40] or "task"


def _resolve(cards: list[tuple[str, Path, dict]], prefix: str) -> tuple[Path, dict]:
    """Resolve an id (or unique id prefix) to one card, or fail loud."""
    hits = [(p, c) for cid, p, c in cards if cid == prefix or cid.startswith(prefix)]
    if not hits:
        print(f"task: no card matches '{prefix}'", file=sys.stderr)
        raise SystemExit(2)
    if len(hits) > 1:
        names = ", ".join(c["id"] for _, c in hits)
        print(f"task: '{prefix}' is ambiguous ({names})", file=sys.stderr)
        raise SystemExit(2)
    return hits[0]


def cmd_new(args: argparse.Namespace) -> int:
    title = " ".join(args.title).strip()
    combined, files = rules_hash()
    if args.rules and not combined.startswith(args.rules):
        print(f"task new: --rules {args.rules} does not match the current "
              f"rule set ({combined[:12]}) — the rules moved since the "
              "pin was taken; re-read them before briefing",
              file=sys.stderr)
        return 2
    cards = _load_cards()
    cid = _next_id(cards)
    card = {
        "id": cid,
        "title": title,
        "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "rules": {"hash": combined, "files": files},
        "checklist": args.check or [],
        "status": "open",
        "receipt": None,
    }
    TASKS_DIR.mkdir(parents=True, exist_ok=True)
    path = TASKS_DIR / f"{cid}-{_slugify(title)}.json"
    path.write_text(json.dumps(card, indent=2) + "\n", encoding="utf-8")
    print(f"task: wrote {path}")
    print(brief_line(combined))
    for item in card["checklist"]:
        print(f"  [ ] {item}")
    return 0


def _check_receipt(cid: str, card: dict) -> list[str]:
    """Problems with a done card's receipt; empty means verifiable green."""
    problems: list[str] = []
    receipt = card.get("receipt")
    if not isinstance(receipt, dict):
        return [f"{cid}: status is done but the receipt is missing"]
    gates = receipt.get("gates")
    if not isinstance(gates, list) or not gates:
        return [f"{cid}: receipt records no gate run"]
    bad = [g.get("gate", "?") for g in gates
           if not isinstance(g, dict) or g.get("outcome") != "PASS"]
    if bad:
        problems.append(f"{cid}: receipt run is not all-green "
                        f"({', '.join(bad)})")
    pinned = card.get("rules", {}).get("hash")
    if receipt.get("rules") != pinned:
        problems.append(f"{cid}: receipt was taken against a different "
                        "rule set than the card pins")
    return problems


def cmd_check(_args: argparse.Namespace) -> int:
    combined, _files = rules_hash()
    cards = _load_cards()
    if not cards:
        print("task: no cards in .gov/tasks/")
        return 0
    problems: list[str] = []
    for cid, path, card in cards:
        status = card.get("status")
        pinned = card.get("rules", {}).get("hash", "<missing>")
        title = card.get("title", "")
        if status == "done":
            problems.extend(_check_receipt(cid, card))
            print(f"done  {cid} {title}")
        elif status == "open":
            if pinned != combined:
                problems.append(
                    f"{cid}: pins rules@{pinned[:12]} but the project is at "
                    f"rules@{combined[:12]} — the brief is stale after a "
                    f"governance adoption ({path})")
                print(f"STALE {cid} {title}")
            else:
                print(f"open  {cid} {title} ({brief_line(combined)})")
        else:
            problems.append(f"{cid}: unknown status {status!r}")
    if problems:
        print()
        for p in problems:
            print(f"task: {p}", file=sys.stderr)
        return 1
    return 0


def cmd_close(args: argparse.Namespace) -> int:
    combined, _files = rules_hash()
    cards = _load_cards()
    path, card = _resolve(cards, args.id)
    if card.get("status") != "open":
        print(f"task: {card['id']} is {card.get('status')!r}, not open",
              file=sys.stderr)
        return 2
    pinned = card.get("rules", {}).get("hash")
    if pinned != combined:
        print(f"task: {card['id']} pins rules@{str(pinned)[:12]} but the "
              f"project is at rules@{combined[:12]} — re-brief against the "
              "adopted rules (gov task check names the stale cards)",
              file=sys.stderr)
        return 1
    argv = [sys.executable, "-m", "gov", "run", "--json",
            "--mode", args.mode]
    try:
        proc = subprocess.run(argv, capture_output=True, text=True,
                              timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print(f"task: gate run timed out after {args.timeout}s",
              file=sys.stderr)
        return 1
    try:
        records = json.loads(proc.stdout)
    except json.JSONDecodeError:
        print("task: gate run produced no JSON report\n"
              f"{proc.stdout}\n{proc.stderr}", file=sys.stderr)
        return 1
    failed = [r.get("gate", "?") for r in records if r.get("outcome") != "PASS"]
    if failed:
        # A card closes only on an all-green run; a red run changes nothing
        # (the run itself is already in .gov/history/gates.jsonl).
        print(f"task: refusing to close {card['id']} — gate run not green "
              f"({', '.join(failed)})", file=sys.stderr)
        return 1
    card["receipt"] = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "mode": args.mode,
        "rules": combined,
        "green": True,
        "gates": records,
    }
    card["status"] = "done"
    path.write_text(json.dumps(card, indent=2) + "\n", encoding="utf-8")
    print(f"task: closed {card['id']} with an all-green "
          f"{args.mode} run ({len(records)} gates)")
    return 0


def cmd_list(_args: argparse.Namespace) -> int:
    cards = _load_cards()
    if not cards:
        print("task: no cards in .gov/tasks/")
        return 0
    for _cid, _p, card in cards:
        print(f"{card.get('status', '?'):5} {card.get('id', '?')} "
              f"{card.get('title', '')}")
    return 0


def main(argv: list[str] | None = None) -> int:
    anchor_to_git_root("task")
    parser = argparse.ArgumentParser(
        prog="gov task", description="task cards for subagent briefs "
        "(rules pin + checklist + completion receipt)")
    # #138: `required=True` died with a TypeError under a shadowed pre-3.7
    # argparse backport; the subcommand-required rule is enforced by hand.
    sub = parser.add_subparsers(dest="subcommand")

    p_new = sub.add_parser("new", help="create a card pinning the current "
                            "rule set; prints the one-line brief pin")
    p_new.add_argument("title", nargs="+", help="task title")
    p_new.add_argument("--check", action="append", default=[],
                       metavar="ITEM", help="acceptance checklist entry "
                       "(repeatable)")
    p_new.add_argument("--rules", metavar="HASH", default=None,
                       help="require the current rule set to match this "
                       "hash prefix; abort loud on drift")
    p_new.set_defaults(func=cmd_new)

    p_check = sub.add_parser("check", help="name stale cards and verify "
                             "receipts (gate-scoped to .gov/tasks/**)")
    p_check.set_defaults(func=cmd_check)

    p_close = sub.add_parser("close", help="run the gate DAG now and close "
                             "the card with a green-run receipt")
    p_close.add_argument("id", help="card id or unique prefix (T-0001)")
    p_close.add_argument("--mode", default="all",
                         help="gate mode to run (default: all)")
    p_close.add_argument("--timeout", type=int, default=600,
                         help="gate-run timeout in seconds (default 600)")
    p_close.set_defaults(func=cmd_close)

    p_list = sub.add_parser("list", help="list cards and their status")
    p_list.set_defaults(func=cmd_list)

    args = parser.parse_args(argv)
    if getattr(args, "func", None) is None:
        parser.error("a subcommand is required (new|check|close|list)")
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
