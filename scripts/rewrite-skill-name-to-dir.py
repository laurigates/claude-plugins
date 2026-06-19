#!/usr/bin/env python3
"""Rewrite each SKILL.md `name` frontmatter field to its directory basename.

OpenCode validates skill frontmatter more strictly than Claude Code:

  1. `name` must match `[a-z0-9-]+` (lowercase alphanumeric with hyphens).
  2. `name` must equal the skill's directory name.

This repo's house style diverges on both points for a handful of skills:

  - Two auto-discovered skills carry display-style names (`UnoCSS`,
    `Lightning CSS`) that fail rule 1.
  - User-invocable skills use the *unprefixed* invocation name (`refocus`,
    `ground-response`) while their directory is plugin-prefixed
    (`project-refocus`, `prompt-engineering-ground-response`), failing rule 2.

Both are valid Claude Code (the `name` field there is a display/invocation label,
not a directory-coupled identifier), so the source tree is left untouched.
`export-opencode.sh` runs this over its disposable staging copy, where the skill
directory basenames are already globally unique and `[a-z0-9-]+`-clean — so
setting `name = basename` satisfies both OpenCode rules at once.

Usage:
  rewrite-skill-name-to-dir.py [--check] [PATH ...]

  --check   Report files that WOULD change, exit 1 if any. No writes.
  PATH      SKILL.md files; defaults to */skills/*/SKILL.md under cwd.
"""
from __future__ import annotations

import glob
import re
import sys
from pathlib import Path

FM_RE = re.compile(r"^(---\n)(.*?\n)(---\n)", re.DOTALL)
# `$` (MULTILINE) anchors just before the line's newline, so the matched span
# excludes the trailing `\n` — the replacement must not re-add one.
NAME_RE = re.compile(r"^name:[ \t]*(.*?)[ \t]*$", re.MULTILINE)


def rewrite(text: str, dir_name: str) -> tuple[str, bool]:
    """Set the frontmatter `name` field to dir_name. Returns (text, changed)."""
    m = FM_RE.match(text)
    if not m:
        return text, False
    head, body, tail = m.group(1), m.group(2), m.group(3)
    nm = NAME_RE.search(body)
    if not nm:
        return text, False
    current = nm.group(1).strip().strip("\"'")
    if current == dir_name:
        return text, False
    new_body = body[: nm.start()] + f"name: {dir_name}" + body[nm.end() :]
    return head + new_body + tail + text[m.end() :], True


def process(path: Path, check: bool) -> bool:
    """Return True if the file changed (or would change in --check mode)."""
    text = path.read_text(encoding="utf-8")
    new_text, changed = rewrite(text, path.parent.name)
    if changed and not check:
        path.write_text(new_text, encoding="utf-8")
    return changed


def main(argv: list[str]) -> int:
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if args:
        paths = [Path(p) for p in args]
    else:
        paths = [Path(p) for p in glob.glob("*/skills/*/SKILL.md")]

    changed_any = False
    for path in paths:
        if not path.is_file():
            continue
        if process(path, check):
            changed_any = True
            verb = "would rewrite" if check else "rewrote"
            print(f"{verb} name in {path}", file=sys.stderr)

    if check and changed_any:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
