#!/usr/bin/env python3
"""Repair docs/regression-ledger.md after merging the base into a pre-split branch.

#3469 split the regression ledger into one file per entry under
docs/regression-ledger/ and left docs/regression-ledger.md as an index page
with no table rows. A branch cut before the split still carries the old
single-file table, and on such a branch `.gitattributes` still marks the page
`merge=union`. Merging the base into it then keeps the whole pre-split table
and appends it to the new index page (about 466 rows per PR, #3490); without
the mark, the page conflicts and resolve-additive-conflicts.py union-merges it
the same way.

This script runs during an in-progress merge (after `git merge --no-commit`
and the additive pre-pass) and, when the base's index holds no table rows:

  1. finds the rows the branch itself added to the old table (rows in HEAD's
     page that the merge base's page lacks),
  2. writes each one as docs/regression-ledger/<number>-<slug>.md, skipping a
     row the base already carries as an entry file,
  3. restores docs/regression-ledger.md to the base's index and stages it.

A row with no `#N` reference cannot be named, so nothing is changed and the
script reports it; scripts/check-regression-ledger.sh (`row_in_index`) then
keeps blocking the PR until a human moves the row.

Usage:
    repair-split-ledger.py <base-ref>      e.g. origin/main

Output follows .claude/rules/structured-script-output.md. Exit code is always
0; STATUS / ISSUE_COUNT are the signal.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

INDEX = "docs/regression-ledger.md"
ENTRY_DIR = "docs/regression-ledger"
SLUG_WORDS = 7


def _git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=False)


def _show(ref: str, path: str) -> str | None:
    result = _git("show", f"{ref}:{path}")
    return result.stdout if result.returncode == 0 else None


def table_rows(text: str | None) -> list[str]:
    """Table rows of a ledger page, header and separator excluded."""
    if not text:
        return []
    rows = []
    for line in text.splitlines():
        if not line.startswith("|"):
            continue
        if re.fullmatch(r"\|[\s:|-]+\|?", line):  # separator
            continue
        if line.startswith("| Issue | Root Cause |"):  # header
            continue
        rows.append(line)
    return rows


def entry_number(row: str) -> str | None:
    """The issue/PR number a row records: the first #N in its last cell."""
    cells = [c for c in row.strip().strip("|").split("|")]
    for cell in reversed(cells):
        match = re.search(r"#(\d+)", cell)
        if match:
            return match.group(1)
        if cell.strip():
            break
    return None


def entry_slug(row: str) -> str:
    first = row.strip().strip("|").split("|", 1)[0]
    words = re.findall(r"[a-z0-9]+", first.lower())
    return "-".join(words[:SLUG_WORDS]) or "entry"


def base_entries(base: str) -> set[str]:
    listing = _git("ls-tree", "-r", "--name-only", base, "--", ENTRY_DIR)
    contents = set()
    for path in listing.stdout.splitlines():
        text = _show(base, path)
        if text:
            contents.add(text.strip())
    return contents


def repair(base: str) -> dict[str, object]:
    report: dict[str, object] = {"written": [], "unnumbered": [], "action": "none"}
    base_index = _show(base, INDEX)
    if base_index is None or table_rows(base_index):
        report["action"] = "skip-base-not-split"
        return report

    current = Path(INDEX).read_text() if Path(INDEX).exists() else ""
    conflicted = "<<<<<<< " in current
    if not table_rows(current) and not conflicted:
        report["action"] = "skip-index-clean"
        return report

    merge_base = _git("merge-base", "HEAD", base).stdout.strip()
    old_rows = set(table_rows(_show(merge_base, INDEX))) if merge_base else set()
    branch_rows = [r for r in table_rows(_show("HEAD", INDEX)) if r not in old_rows]

    unnumbered = [r for r in branch_rows if entry_number(r) is None]
    if unnumbered:
        report["unnumbered"] = unnumbered
        report["action"] = "blocked-unnumbered-row"
        return report

    existing = base_entries(base)
    written: list[str] = []
    for row in branch_rows:
        if row.strip() in existing:
            continue
        stem = f"{entry_number(row)}-{entry_slug(row)}"
        path = Path(ENTRY_DIR) / f"{stem}.md"
        n = 2
        while path.exists() and path.read_text().strip() != row.strip():
            path = Path(ENTRY_DIR) / f"{stem}-{n}.md"
            n += 1
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(row + "\n")
        _git("add", "--", str(path))
        written.append(str(path))

    Path(INDEX).write_text(base_index)
    _git("add", "--", INDEX)
    report["written"] = written
    report["action"] = "repaired"
    return report


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: repair-split-ledger.py <base-ref>", file=sys.stderr)
        return 2
    report = repair(argv[0])
    written = report["written"]
    unnumbered = report["unnumbered"]
    assert isinstance(written, list) and isinstance(unnumbered, list)
    print("=== SPLIT LEDGER REPAIR ===")
    print(f"ACTION={report['action']}")
    print(f"ENTRIES_WRITTEN={len(written)}")
    for path in written:
        print(f"  - FILE={path}")
    if unnumbered:
        print("UNNUMBERED:")
        for row in unnumbered:
            print(f"  - ROW={row[:120]}")
    print(f"STATUS={'WARN' if unnumbered else 'OK'}")
    print(f"ISSUE_COUNT={len(unnumbered)}")
    print("=== END SPLIT LEDGER REPAIR ===")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
