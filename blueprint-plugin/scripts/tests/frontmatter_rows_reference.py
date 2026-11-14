"""Reference reader for test-frontmatter-rows.sh (#3549).

Reads `blueprint-autorun.sh --frontmatter-rows` output on stdin and checks
each row against check-schema.py `split_frontmatter` + `yaml.safe_load`, the
reading every other blueprint tool uses. Prints one `MISMATCH` line per
disagreeing field and exits 1 when there is any.

Usage: python3 frontmatter_rows_reference.py <check-schema.py> < rows
"""

from __future__ import annotations

import datetime as _dt
import importlib.util
import sys

import yaml

US = "\x1f"
RS = "\x1e"


def load_split(checker: str):
    spec = importlib.util.spec_from_file_location("check_schema", checker)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.split_frontmatter


def scalar(value) -> str:
    if value is None:
        return ""
    if isinstance(value, (_dt.date, _dt.datetime)):
        return value.isoformat()
    return str(value)


def as_list(value) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        value = [value]
    return [scalar(v) for v in value if scalar(v) != ""]


def body_heading(body: str) -> str:
    in_fence = False
    for line in body.splitlines():
        if line.lstrip(" \t").startswith(("```", "~~~")):
            in_fence = not in_fence
            continue
        if not in_fence and line.startswith("# "):
            return line[2:].strip()
    return ""


def expected_row(split_frontmatter, path: str) -> list[str] | None:
    with open(path, encoding="utf-8") as fh:
        content = fh.read()
    fm, body = split_frontmatter(content)
    if fm is None:
        return [path, "0", "", "", body_heading(body), "", "", ""]
    try:
        data = yaml.safe_load(fm) or {}
    except yaml.YAMLError:
        return None
    if not isinstance(data, dict):
        data = {}
    title = scalar(data.get("title")) or body_heading(body)
    return [
        path,
        "1",
        scalar(data.get("id")),
        scalar(data.get("status")),
        title,
        scalar(data.get("created")),
        RS.join(as_list(data.get("relates-to"))),
        RS.join(as_list(data.get("github-issues"))),
    ]


FIELDS = [
    "path",
    "has_frontmatter",
    "id",
    "status",
    "title",
    "created",
    "relates_to",
    "github_issues",
]


def main() -> int:
    split_frontmatter = load_split(sys.argv[1])
    mismatches = 0
    rows = 0
    for raw in sys.stdin.read().split("\n"):
        if not raw:
            continue
        rows += 1
        got = raw.split(US)
        if len(got) != len(FIELDS):
            print(f"MISMATCH {got[0]} field_count={len(got)}")
            mismatches += 1
            continue
        want = expected_row(split_frontmatter, got[0])
        if want is None:
            print(f"SKIPPED {got[0]} (frontmatter is not valid YAML)")
            continue
        for name, g, w in zip(FIELDS, got, want):
            if g != w:
                print(f"MISMATCH {got[0]} {name}: parser={g!r} yaml={w!r}")
                mismatches += 1
    print(f"ROWS={rows} MISMATCHES={mismatches}")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
