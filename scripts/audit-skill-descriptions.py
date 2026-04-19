#!/usr/bin/env python3
"""
Audit SKILL.md descriptions for auto-invocation quality.

Claude auto-invokes a skill based on its `description` frontmatter field. A good
description includes a "Use when..." trigger clause so Claude can match it to
user intent. This script classifies every skill in the repo into:

  MISSING     — no description field
  EMPTY       — description is empty / null / whitespace
  NO_TRIGGER  — description present but lacks a "Use when..." trigger clause
  OK          — description includes a trigger clause

See .claude/rules/skill-quality.md for the Description Quality checklist.

Usage:
    python scripts/audit-skill-descriptions.py                       # Summary
    python scripts/audit-skill-descriptions.py --list                # Show every offender
    python scripts/audit-skill-descriptions.py --category EMPTY      # Filter
    python scripts/audit-skill-descriptions.py --plugin git-plugin   # Filter
    python scripts/audit-skill-descriptions.py --json                # Machine-readable
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent

# Trigger phrases that signal an intent-matching description.
# See .claude/rules/skill-quality.md for the canonical pattern.
TRIGGER_PATTERNS = [
    r"\buse when\b",
    r"\buse this (?:skill|command) when\b",
    r"\bwhen the user\b",
    r"\bwhen (?:you|a user) (?:need|want|ask|request|mention)",
    r"\binvoke (?:this|when)\b",
    r"\btrigger(?:s|ed)? (?:on|when|by)\b",
]
TRIGGER_RE = re.compile("|".join(TRIGGER_PATTERNS), re.IGNORECASE)

CATEGORIES = ("MISSING", "EMPTY", "NO_TRIGGER", "OK")


def find_skills(root: Path) -> list[Path]:
    """Return all SKILL.md / skill.md files under *-plugin directories."""
    skills: list[Path] = []
    for plugin_dir in sorted(root.glob("*-plugin")):
        if not plugin_dir.is_dir():
            continue
        skills_dir = plugin_dir / "skills"
        if not skills_dir.is_dir():
            continue
        for skill_md in sorted(skills_dir.rglob("SKILL.md")):
            skills.append(skill_md)
        for skill_md in sorted(skills_dir.rglob("skill.md")):
            if skill_md not in skills:
                skills.append(skill_md)
    return skills


_DESC_RE = re.compile(
    r"^description:\s*(?P<value>.*?)(?=^\w[\w-]*:\s|^---\s*$|\Z)",
    re.MULTILINE | re.DOTALL,
)


def _regex_description(fm_text: str) -> str | None:
    """Best-effort extraction of description when YAML parsing fails.

    Handles single-line strings, quoted strings, and multi-line block scalars
    (`|` and `>`). Returns None if no `description:` key is present.
    """
    m = _DESC_RE.search(fm_text)
    if not m:
        return None
    value = m.group("value").rstrip()
    if not value:
        return ""
    # Block scalar: `|` or `>` followed by indented lines
    if value.lstrip().startswith(("|", ">")):
        lines = value.splitlines()[1:]
        return " ".join(line.strip() for line in lines if line.strip())
    # Quoted string
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    # Plain multi-line (YAML folds these) — join
    return " ".join(line.strip() for line in value.splitlines() if line.strip())


def extract_frontmatter(path: Path) -> tuple[dict | None, str | None]:
    """Parse the YAML frontmatter block.

    Returns `(data, fallback_description)`. `data` is the parsed dict, or None
    on parse failure. `fallback_description` is a regex-extracted description
    used when YAML parsing fails but the field is still recoverable.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None, None
    if not text.startswith("---"):
        return None, None
    parts = text.split("\n---", 1)
    if len(parts) < 2:
        return None, None
    fm_text = parts[0].lstrip("-").lstrip("\n")
    try:
        data = yaml.safe_load(fm_text)
    except yaml.YAMLError:
        return None, _regex_description(fm_text)
    if not isinstance(data, dict):
        return None, _regex_description(fm_text)
    return data, None


def classify(description) -> str:
    """Classify a description value into one of the CATEGORIES."""
    if description is None:
        return "MISSING"
    if not isinstance(description, str):
        # Non-string descriptions crash the skill loader; treat as empty.
        return "EMPTY"
    stripped = description.strip()
    if not stripped:
        return "EMPTY"
    if TRIGGER_RE.search(stripped):
        return "OK"
    return "NO_TRIGGER"


def plugin_of(skill_path: Path) -> str:
    rel = skill_path.relative_to(REPO_ROOT)
    return rel.parts[0]


def skill_slug(skill_path: Path) -> str:
    return skill_path.parent.name


def audit(root: Path) -> list[dict]:
    results = []
    for path in find_skills(root):
        fm, fallback = extract_frontmatter(path)
        reason = ""
        if fm is None:
            desc = fallback
            if fallback is None:
                results.append(
                    {
                        "plugin": plugin_of(path),
                        "skill": skill_slug(path),
                        "path": str(path.relative_to(REPO_ROOT)),
                        "category": "MISSING",
                        "description": "",
                        "reason": "unparseable frontmatter",
                    }
                )
                continue
            reason = "frontmatter YAML parse error (regex fallback)"
        else:
            desc = fm.get("description")
        category = classify(desc)
        preview = ""
        if isinstance(desc, str):
            preview = " ".join(desc.split())
            if len(preview) > 120:
                preview = preview[:117] + "..."
        results.append(
            {
                "plugin": plugin_of(path),
                "skill": skill_slug(path),
                "path": str(path.relative_to(REPO_ROOT)),
                "category": category,
                "description": preview,
                "reason": reason,
            }
        )
    return results


def print_summary(results: list[dict]) -> None:
    total = len(results)
    overall = Counter(r["category"] for r in results)
    per_plugin: dict[str, Counter] = defaultdict(Counter)
    for r in results:
        per_plugin[r["plugin"]][r["category"]] += 1

    print(f"Audited {total} skills across {len(per_plugin)} plugins")
    print()
    print("Overall:")
    for cat in CATEGORIES:
        n = overall.get(cat, 0)
        pct = (n / total * 100) if total else 0.0
        print(f"  {cat:<11} {n:>4}  ({pct:5.1f}%)")
    bad = total - overall.get("OK", 0)
    print(f"  {'NEEDS FIX':<11} {bad:>4}  ({(bad / total * 100) if total else 0:5.1f}%)")
    print()

    # Per-plugin breakdown, sorted by worst-offender count
    print(f"{'Plugin':<32} {'OK':>5} {'NO_TRIG':>8} {'EMPTY':>7} {'MISSING':>8} {'TOTAL':>6}")
    print("-" * 72)
    rows = sorted(
        per_plugin.items(),
        key=lambda kv: (-(kv[1].get("EMPTY", 0) + kv[1].get("NO_TRIGGER", 0) + kv[1].get("MISSING", 0)), kv[0]),
    )
    for plugin, counts in rows:
        tot = sum(counts.values())
        print(
            f"{plugin:<32} {counts.get('OK', 0):>5} "
            f"{counts.get('NO_TRIGGER', 0):>8} "
            f"{counts.get('EMPTY', 0):>7} "
            f"{counts.get('MISSING', 0):>8} "
            f"{tot:>6}"
        )


def print_list(results: list[dict], show_ok: bool) -> None:
    for r in results:
        if not show_ok and r["category"] == "OK":
            continue
        desc = r["description"] or "(none)"
        print(f"[{r['category']:<10}] {r['path']}")
        print(f"             {desc}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="List every offender (non-OK skills)")
    parser.add_argument("--all", action="store_true", help="With --list, include OK skills too")
    parser.add_argument("--category", choices=CATEGORIES, help="Filter output to one category")
    parser.add_argument("--plugin", help="Filter output to one plugin")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero if any skill is not OK (for CI use)",
    )
    args = parser.parse_args()

    results = audit(REPO_ROOT)

    filtered = results
    if args.category:
        filtered = [r for r in filtered if r["category"] == args.category]
    if args.plugin:
        filtered = [r for r in filtered if r["plugin"] == args.plugin]

    if args.json:
        json.dump(filtered, sys.stdout, indent=2)
        sys.stdout.write("\n")
    elif args.list or args.category or args.plugin:
        print_list(filtered, show_ok=args.all)
    else:
        print_summary(results)

    if args.strict:
        bad = [r for r in results if r["category"] != "OK"]
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
