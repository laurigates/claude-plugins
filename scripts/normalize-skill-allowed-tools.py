#!/usr/bin/env python3
"""Normalize SKILL.md `allowed-tools`/`disallowed-tools` frontmatter to YAML block lists.

Claude Code accepts a space- or comma-separated string OR a YAML list for these
fields (https://code.claude.com/docs/en/skills). This repo's house style is the
compact comma-separated string form, but rulesync's claudecode importer requires
the YAML list form and hard-aborts otherwise.

`export-opencode.sh` runs this over its disposable staging copy so the source tree
keeps the compact form (fewer tokens, passes the skill-size lint). It is written to
be safe to run against the source too, should that policy ever change.

Only the comma-separated string form is rewritten. Tool tokens themselves may
contain spaces (e.g. `Bash(git status *)`), so the delimiter is the comma. Files
already in block-list form are left untouched (idempotent).

Usage:
  normalize-skill-allowed-tools.py [--check] [PATH ...]

  --check   Report files that WOULD change, exit 1 if any. No writes.
  PATH      SKILL.md files or globs; defaults to */skills/*/SKILL.md under cwd.
"""
from __future__ import annotations

import glob
import re
import sys
from pathlib import Path

FIELDS = ("allowed-tools", "disallowed-tools")
FM_RE = re.compile(r"^(---\n)(.*?\n)(---\n)", re.DOTALL)


def normalize_block(fm_body: str) -> tuple[str, bool]:
    """Rewrite string-form FIELDS in a frontmatter body to YAML block lists."""
    changed = False
    out_lines: list[str] = []
    for line in fm_body.splitlines(keepends=True):
        m = re.match(r"^(allowed-tools|disallowed-tools):[ \t]*(.*?)[ \t]*\n$", line)
        if not m:
            out_lines.append(line)
            continue
        key, value = m.group(1), m.group(2)
        # Empty value => already a YAML block list (items on following lines). Skip.
        # Bracket value => already an inline array. Skip.
        if value == "" or value.startswith("["):
            out_lines.append(line)
            continue
        tools = [t.strip() for t in value.split(",") if t.strip()]
        out_lines.append(f"{key}:\n")
        out_lines.extend(f"  - {t}\n" for t in tools)
        changed = True
    return "".join(out_lines), changed


def process(path: Path, check: bool) -> bool:
    """Return True if the file changed (or would change in --check mode)."""
    text = path.read_text(encoding="utf-8")
    m = FM_RE.match(text)
    if not m:
        return False
    new_body, changed = normalize_block(m.group(2))
    if not changed:
        return False
    if not check:
        new_text = m.group(1) + new_body + m.group(3) + text[m.end():]
        path.write_text(new_text, encoding="utf-8")
    return True


def main(argv: list[str]) -> int:
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if args:
        files = [Path(p) for a in args for p in glob.glob(a, recursive=True)]
    else:
        files = [Path(p) for p in glob.glob("*-plugin/skills/*/SKILL.md")]
    changed = [f for f in files if process(f, check)]
    verb = "would change" if check else "changed"
    print(f"{verb}: {len(changed)} / {len(files)} SKILL.md files")
    for f in changed[:10]:
        print(f"  {verb}: {f}")
    if len(changed) > 10:
        print(f"  ... and {len(changed) - 10} more")
    if check and changed:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
