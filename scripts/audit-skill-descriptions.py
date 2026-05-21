#!/usr/bin/env python3
"""
Audit SKILL.md descriptions for auto-invocation quality and listing-budget length.

Claude auto-invokes a skill based on its `description` frontmatter field. A good
description includes a "Use when..." trigger clause so Claude can match it to
user intent, AND fits inside the per-skill share of the listing budget. This
script classifies every skill on two axes:

Trigger axis (`category`):
  MISSING     — no description field
  EMPTY       — description is empty / null / whitespace
  NO_TRIGGER  — description present but lacks a "Use when..." trigger clause
  OK          — description includes a trigger clause

Length axis (`length_category`) — see .claude/rules/skill-quality.md
"Description Length and the Listing Budget":
  IDEAL  — ≤ 150 chars (survives any per-skill truncation)
  OK     — 151–200 chars (within budget for typical plugin loadouts)
  WARN   — 201–300 chars (eats budget faster than it earns invocation accuracy)
  ERROR  — > 300 chars (almost always rewordable; rewrite before merge)

Usage:
    python scripts/audit-skill-descriptions.py                       # Summary
    python scripts/audit-skill-descriptions.py --list                # Show every offender
    python scripts/audit-skill-descriptions.py --category EMPTY      # Filter
    python scripts/audit-skill-descriptions.py --plugin git-plugin   # Filter
    python scripts/audit-skill-descriptions.py --json                # Machine-readable
    python scripts/audit-skill-descriptions.py --strict-length       # Exit 1 if any description > 300 chars
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

# Length budget thresholds — see .claude/rules/skill-quality.md
LENGTH_IDEAL_MAX = 150
LENGTH_OK_MAX = 200
LENGTH_WARN_MAX = 300
LENGTH_CATEGORIES = ("IDEAL", "OK", "WARN", "ERROR")


def classify_length(description) -> tuple[str, int]:
    """Return (length_category, char_count). Missing/empty → ("IDEAL", 0)."""
    if not isinstance(description, str):
        return "IDEAL", 0
    n = len(description.strip())
    if n == 0:
        return "IDEAL", 0
    if n <= LENGTH_IDEAL_MAX:
        return "IDEAL", n
    if n <= LENGTH_OK_MAX:
        return "OK", n
    if n <= LENGTH_WARN_MAX:
        return "WARN", n
    return "ERROR", n


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


_DISABLE_RE = re.compile(r"^disable-model-invocation:\s*true\b", re.MULTILINE)


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
                        "auto_invokable": True,
                        "reason": "unparseable frontmatter",
                    }
                )
                continue
            reason = "frontmatter YAML parse error (regex fallback)"
            # Still look for disable-model-invocation via regex
            try:
                fm_text = path.read_text(encoding="utf-8").split("\n---", 1)[0]
            except OSError:
                fm_text = ""
            auto_invokable = not _DISABLE_RE.search(fm_text)
        else:
            desc = fm.get("description")
            auto_invokable = not (fm.get("disable-model-invocation") is True)
        category = classify(desc)
        length_category, length = classify_length(desc)
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
                "length_category": length_category,
                "length": length,
                "description": preview,
                "auto_invokable": auto_invokable,
                "reason": reason,
            }
        )
    return results


def print_summary(results: list[dict]) -> None:
    total = len(results)
    overall = Counter(r["category"] for r in results)
    length_overall = Counter(r["length_category"] for r in results)
    per_plugin: dict[str, Counter] = defaultdict(Counter)
    for r in results:
        per_plugin[r["plugin"]][r["category"]] += 1

    auto_bad = sum(1 for r in results if r["category"] != "OK" and r["auto_invokable"])
    explicit_only_bad = sum(1 for r in results if r["category"] != "OK" and not r["auto_invokable"])

    print(f"Audited {total} skills across {len(per_plugin)} plugins")
    print()
    print("Trigger axis (auto-invocation matchability):")
    for cat in CATEGORIES:
        n = overall.get(cat, 0)
        pct = (n / total * 100) if total else 0.0
        print(f"  {cat:<11} {n:>4}  ({pct:5.1f}%)")
    bad = total - overall.get("OK", 0)
    print(f"  {'NEEDS FIX':<11} {bad:>4}  ({(bad / total * 100) if total else 0:5.1f}%)")
    print(f"    auto-invokable: {auto_bad:>3}  (priority)")
    print(f"    explicit-only:  {explicit_only_bad:>3}  (disable-model-invocation: true)")
    print()
    print("Length axis (listing-budget consumption):")
    length_labels = {
        "IDEAL": f"≤{LENGTH_IDEAL_MAX} chars",
        "OK": f"{LENGTH_IDEAL_MAX + 1}–{LENGTH_OK_MAX} chars",
        "WARN": f"{LENGTH_OK_MAX + 1}–{LENGTH_WARN_MAX} chars",
        "ERROR": f">{LENGTH_WARN_MAX} chars",
    }
    for cat in LENGTH_CATEGORIES:
        n = length_overall.get(cat, 0)
        pct = (n / total * 100) if total else 0.0
        marker = "  ⚠️" if cat == "WARN" else "  ❌" if cat == "ERROR" else ""
        print(f"  {cat:<6} ({length_labels[cat]:>13}) {n:>4}  ({pct:5.1f}%){marker}")
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
        trigger_ok = r["category"] == "OK"
        length_ok = r["length_category"] in ("IDEAL", "OK")
        if not show_ok and trigger_ok and length_ok:
            continue
        desc = r["description"] or "(none)"
        length_tag = ""
        if not length_ok:
            length_tag = f" [LEN={r['length_category']}/{r['length']}c]"
        print(f"[{r['category']:<10}]{length_tag} {r['path']}")
        print(f"             {desc}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="List every offender (non-OK skills)")
    parser.add_argument("--all", action="store_true", help="With --list, include OK skills too")
    parser.add_argument("--category", choices=CATEGORIES, help="Filter output to one trigger category")
    parser.add_argument(
        "--length-category",
        choices=LENGTH_CATEGORIES,
        help="Filter output to one length category (IDEAL / OK / WARN / ERROR)",
    )
    parser.add_argument("--plugin", help="Filter output to one plugin")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    parser.add_argument(
        "--auto-invokable",
        action="store_true",
        help="Filter to skills that Claude can auto-invoke (omit those with disable-model-invocation: true)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero if any skill has a MISSING or EMPTY description (pre-commit gate)",
    )
    parser.add_argument(
        "--strict-all",
        action="store_true",
        help="Exit non-zero if any auto-invokable skill is not OK (stricter CI gate; fails on NO_TRIGGER)",
    )
    parser.add_argument(
        "--strict-length",
        action="store_true",
        help="Exit non-zero if any description exceeds the listing-budget WARN threshold (>300 chars by default; pass --warn-on-200 to fail on WARN+ERROR)",
    )
    parser.add_argument(
        "--warn-on-200",
        action="store_true",
        help="With --strict-length, treat WARN (201-300 chars) as failure too (stricter gate)",
    )
    args = parser.parse_args()

    results = audit(REPO_ROOT)

    filtered = results
    if args.category:
        filtered = [r for r in filtered if r["category"] == args.category]
    if args.length_category:
        filtered = [r for r in filtered if r["length_category"] == args.length_category]
    if args.plugin:
        filtered = [r for r in filtered if r["plugin"] == args.plugin]
    if args.auto_invokable:
        filtered = [r for r in filtered if r["auto_invokable"]]

    if args.json:
        json.dump(filtered, sys.stdout, indent=2)
        sys.stdout.write("\n")
    elif args.list or args.category or args.length_category or args.plugin:
        print_list(filtered, show_ok=args.all)
    else:
        print_summary(results)

    if args.strict_all:
        bad = [r for r in results if r["category"] != "OK" and r["auto_invokable"]]
        if bad:
            print(f"\n{len(bad)} auto-invokable skills need description fixes", file=sys.stderr)
            return 1
        return 0
    if args.strict_length:
        fail_set = {"ERROR"}
        if args.warn_on_200:
            fail_set.add("WARN")
        bad = [r for r in results if r["length_category"] in fail_set]
        if bad:
            label = "exceed 300 chars" if not args.warn_on_200 else "exceed 200 chars"
            print(
                f"\n{len(bad)} skill descriptions {label} (see .claude/rules/skill-quality.md):",
                file=sys.stderr,
            )
            for r in bad:
                print(
                    f"  {r['path']} ({r['length_category']}, {r['length']} chars)",
                    file=sys.stderr,
                )
            return 1
        return 0
    if args.strict:
        bad = [r for r in results if r["category"] in ("MISSING", "EMPTY")]
        if bad:
            print(f"\n{len(bad)} skills have MISSING or EMPTY description:", file=sys.stderr)
            for r in bad:
                print(f"  {r['path']} ({r['category']})", file=sys.stderr)
            return 1
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
