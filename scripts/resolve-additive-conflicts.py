#!/usr/bin/env python3
"""Deterministically resolve *additive* merge conflicts — no LLM required.

A merge conflict is "additive" when BOTH sides only *inserted* lines relative
to the merge base (neither side modified or deleted existing lines in the
conflicted hunk). That is the classic append-only-table / changelog / registry
conflict: two PRs each add a row at the same anchor. Its correct resolution is
the union of both additions, which `git merge-file --union` produces faithfully.

This script runs as a pre-pass before any LLM-based conflict resolver: it
resolves the additive files mechanically and leaves genuinely *semantic*
conflicts (same line edited on both sides, version bumps, JSON structure) for
the LLM. Files marked `merge=union` in .gitattributes are auto-resolved by git
itself during the merge and never reach this script — this handles the rest.

Usage:
    resolve-additive-conflicts.py [FILE ...]

With no arguments it operates on the current index's conflicted files
(`git diff --name-only --diff-filter=U`). It must run inside a git repository
with an in-progress merge that has left conflicts staged.

Output follows .claude/rules/structured-script-output.md. Exit code is always 0
(parallel-safe per .claude/rules/parallel-safe-queries.md); the REMAINING_COUNT
field is the signal a caller checks to decide whether to invoke the LLM.
"""

from __future__ import annotations

import difflib
import subprocess
import sys
import tempfile
from pathlib import Path


def _git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _stage_blob(stage: int, path: str) -> str | None:
    """Return the content of an index stage (1=base, 2=ours, 3=theirs).

    Returns None when the stage is absent (e.g. add/add conflicts have no
    base at stage 1).
    """
    result = _git("show", f":{stage}:{path}")
    if result.returncode != 0:
        return None
    return result.stdout


def _is_addition_only(base: list[str], side: list[str]) -> bool:
    """True when `side` differs from `base` only by inserted lines.

    Any replace/delete opcode means the side rewrote or removed existing
    content, so a union merge would be unsafe (it would keep both versions of
    an edited line). Only `equal` and `insert` are additive-safe.
    """
    matcher = difflib.SequenceMatcher(a=base, b=side, autojunk=False)
    return all(tag in ("equal", "insert") for tag, *_ in matcher.get_opcodes())


def _union_merge(base: str, ours: str, theirs: str) -> str:
    """Faithful union merge via git's built-in driver (handles interleaving)."""
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "base").write_text(base)
        (d / "ours").write_text(ours)
        (d / "theirs").write_text(theirs)
        result = _git(
            "merge-file", "-p", "--union",
            str(d / "ours"), str(d / "base"), str(d / "theirs"),
        )
    return result.stdout


def _conflicted_files() -> list[str]:
    result = _git("diff", "--name-only", "--diff-filter=U")
    return [line for line in result.stdout.splitlines() if line]


def resolve(paths: list[str]) -> tuple[list[str], list[tuple[str, str]]]:
    """Resolve additive conflicts in `paths`.

    Returns (resolved, remaining) where `resolved` is a list of file paths that
    were union-merged and staged, and `remaining` is a list of
    (path, reason) tuples for files left for the LLM.
    """
    resolved: list[str] = []
    remaining: list[tuple[str, str]] = []

    for path in paths:
        base = _stage_blob(1, path)
        ours = _stage_blob(2, path)
        theirs = _stage_blob(3, path)

        # add/add (no base) and add/delete (one side missing) are not the
        # additive-table case — leave them for the LLM.
        if base is None or ours is None or theirs is None:
            remaining.append((path, "no-base-or-side-missing"))
            continue

        base_lines = base.splitlines(keepends=True)
        ours_lines = ours.splitlines(keepends=True)
        theirs_lines = theirs.splitlines(keepends=True)

        if not (
            _is_addition_only(base_lines, ours_lines)
            and _is_addition_only(base_lines, theirs_lines)
        ):
            remaining.append((path, "non-additive"))
            continue

        merged = _union_merge(base, ours, theirs)
        Path(path).write_text(merged)
        add = _git("add", "--", path)
        if add.returncode != 0:
            remaining.append((path, "git-add-failed"))
            continue
        resolved.append(path)

    return resolved, remaining


def main(argv: list[str]) -> int:
    paths = argv or _conflicted_files()
    resolved, remaining = resolve(paths)

    print("=== ADDITIVE CONFLICT RESOLVER ===")
    print(f"CONFLICTED_COUNT={len(paths)}")
    print(f"RESOLVED_COUNT={len(resolved)}")
    print(f"REMAINING_COUNT={len(remaining)}")
    if resolved:
        print("RESOLVED:")
        for path in resolved:
            print(f"  - FILE={path} REASON=additive-union")
    if remaining:
        print("REMAINING:")
        for path, reason in remaining:
            print(f"  - FILE={path} REASON={reason}")
    print(f"STATUS={'OK' if not remaining else 'WARN'}")
    print(f"ISSUE_COUNT={len(remaining)}")
    print("=== END ADDITIVE CONFLICT RESOLVER ===")
    # Always exit 0 so a parallel batch is not cancelled; REMAINING_COUNT is
    # the signal callers act on.
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
