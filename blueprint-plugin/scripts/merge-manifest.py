#!/usr/bin/env python3
"""Git merge driver for docs/blueprint/manifest.json — a structural 3-way merge.

The manifest is rewritten by tooling on every run (sync-ids, autorun), so two
branches that each ran a task conflict on fields that carry no real
disagreement: a run timestamp, a run counter, a registry entry each side added.
Git's line merge cannot tell those apart from a real conflict. This driver
merges the parsed JSON instead.

Registered by hooks/register-merge-driver.sh. Git invokes it as:

    merge-manifest.py %O %A %B [%P]

  %O  common ancestor (may be empty when both sides added the file)
  %A  current branch — the merged result is written back here
  %B  other branch
  %P  the path being merged (labels only)

Contract (gitattributes(5), "Defining a custom merge driver"): leave the result
in %A, exit 0 when clean, non-zero when conflicted. On conflict this driver
writes git's ordinary conflict-marker output into %A (via `git merge-file`), so
an unresolvable merge looks exactly as it would without the driver.

Merge policy, applied recursively key by key:

  * One side changed a value, the other did not  -> take the change.
  * Both sides made the same change              -> take it.
  * Objects                                      -> merge per key; a key added
    on one side is kept, a key deleted on one side and untouched on the other
    is dropped.
  * Run-state group (an object holding `last_completed_at`) -> when both sides
    ran the task, `last_completed_at`, `last_result` and `stats` all come from
    the side whose `last_completed_at` is later, so the three stay consistent.
  * ISO-8601 timestamp strings both changed      -> the later one.
  * `last_*` integer counters both raised         -> the larger one.
  * Arrays both appended to (base is a prefix of both) -> ours, then theirs'
    new items not already present.
  * Anything else changed differently on both sides -> conflict.

Two branches registering the same id (PRD-003) for different documents is the
case the last rule exists for: it stays a conflict.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

MISSING = object()
RUN_STATE_KEYS = ("last_completed_at", "last_result", "stats")


class Conflict(Exception):
    """Raised with the JSON path of the first irreconcilable value."""


def _ts(value: object) -> datetime | None:
    if not isinstance(value, str) or len(value) < 10:
        return None
    try:
        # Python < 3.11 (the macOS Xcode python3 is 3.9) rejects a "Z" suffix.
        return datetime.fromisoformat(value.replace("Z", "+00:00"))  # noqa: FURB162
    except ValueError:
        return None


def _later(a: object, b: object) -> object | None:
    ta, tb = _ts(a), _ts(b)
    if ta is None or tb is None:
        return None
    try:
        return a if ta >= tb else b
    except TypeError:  # naive vs aware timestamps
        return None


def merge(base: object, ours: object, theirs: object, path: str) -> object:
    if ours == theirs:
        return ours
    if base == ours:
        return theirs
    if base == theirs:
        return ours
    if MISSING in (ours, theirs):
        # Deleted on one side, modified on the other.
        raise Conflict(path)

    if isinstance(ours, dict) and isinstance(theirs, dict):
        return _merge_dict(base if isinstance(base, dict) else {}, ours, theirs, path)

    if isinstance(ours, list) and isinstance(theirs, list):
        base_list = base if isinstance(base, list) else []
        n = len(base_list)
        if ours[:n] == base_list and theirs[:n] == base_list:
            return ours + [x for x in theirs[n:] if x not in ours]
        raise Conflict(path)

    later = _later(ours, theirs)
    if later is not None:
        return later

    key = path.rsplit(".", 1)[-1]
    if (
        key.startswith("last_")
        and isinstance(ours, int)
        and not isinstance(ours, bool)
        and isinstance(theirs, int)
        and not isinstance(theirs, bool)
        and (base is MISSING or (isinstance(base, int) and not isinstance(base, bool)))
    ):
        return max(ours, theirs)

    raise Conflict(path)


def _merge_dict(base: dict, ours: dict, theirs: dict, path: str) -> dict:
    ours, theirs = dict(ours), dict(theirs)

    # Run-state group: when both sides ran the task, the later run's
    # timestamp, result and stats travel together.
    run_o, run_t = ours.get("last_completed_at"), theirs.get("last_completed_at")
    if run_o != run_t and run_o != base.get("last_completed_at") != run_t:
        later = _later(run_o, run_t)
        if later is not None:
            winner = ours if later is run_o else theirs
            for k in RUN_STATE_KEYS:
                if k in winner:
                    ours[k] = theirs[k] = winner[k]

    result: dict = {}
    for key in list(ours) + [k for k in theirs if k not in ours]:
        merged = merge(
            base.get(key, MISSING),
            ours.get(key, MISSING),
            theirs.get(key, MISSING),
            f"{path}.{key}" if path else key,
        )
        if merged is not MISSING:
            result[key] = merged
    return result


def _load(path: Path) -> object:
    text = path.read_text(encoding="utf-8")
    return MISSING if not text.strip() else json.loads(text)


def _text_merge(o: str, a: str, b: str, label: str) -> int:
    """Fall back to git's own line merge; writes conflict markers into %A.

    Returns 0 only when the line merge was clean AND left valid JSON. Any other
    outcome returns 1 — never a code above 128, which git reads as a driver
    crash and turns into a hard merge failure instead of a conflict.
    """
    proc = subprocess.run(
        [
            "git",
            "merge-file",
            "-L",
            f"{label} (ours)",
            "-L",
            "base",
            "-L",
            f"{label} (theirs)",
            a,
            o,
            b,
        ],
        check=False,
    )
    if proc.returncode == 0:
        try:
            json.loads(Path(a).read_text(encoding="utf-8"))
            return 0
        except ValueError:
            print("merge-manifest: line merge left invalid JSON", file=sys.stderr)
    return 1


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print("usage: merge-manifest.py %O %A %B [%P]", file=sys.stderr)
        return 2
    o, a, b = argv[1:4]
    label = argv[4] if len(argv) > 4 else "manifest.json"

    try:
        base, ours, theirs = (_load(Path(p)) for p in (o, a, b))
    except (OSError, ValueError) as exc:
        print(
            f"merge-manifest: cannot parse inputs ({exc}); line merge", file=sys.stderr
        )
        return _text_merge(o, a, b, label)

    try:
        result = merge(base, ours, theirs, "")
    except Conflict as exc:
        print(
            f"merge-manifest: conflict at {exc.args[0] or '<root>'}; line merge",
            file=sys.stderr,
        )
        return _text_merge(o, a, b, label)

    if result is MISSING:  # deleted on both sides
        Path(a).write_text("", encoding="utf-8")
        return 0
    Path(a).write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
