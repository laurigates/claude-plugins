#!/usr/bin/env python3
"""Deterministic documentation check for a release-please PR.

Runs the four checks the `Release: PR documentation audit` Claude prompt asks
for, for every package whose CHANGELOG.md the PR changes:

1. CHANGELOG format: the newest `## [x.y.z]` heading has at least one
   `### <section>` from the package's `changelog-sections`, every section is in
   that list, and every section has at least one entry.
2. Version consistency: plugin.json, .release-please-manifest.json, the newest
   CHANGELOG heading and the package's marketplace.json entry agree.
3. Skill date freshness: SKILL.md `modified:` dates older than --stale-days
   (default 90) are listed as warnings, as are SKILL.md files without one.
4. Blueprint compliance: when blueprint-plugin is released, the Overall column
   of `scripts/plugin-compliance-check.sh blueprint-plugin`.

Writes a Markdown comment (`## Release Documentation Check`) to --out and the
structured summary to stdout (.claude/rules/structured-script-output.md).
Exit 0 on OK/WARN, 1 on ERROR (a ❌ row), 2 on a usage or git error.

Usage:
    python3 scripts/release-pr-doc-audit.py --base origin/main --out report.md
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

HEADING = "## Release Documentation Check"
MARKER = "<!-- release-pr-doc-check -->"
PASS, WARN, FAIL = "✅", "⚠️", "❌"
VERSION_HEADING = re.compile(r"^## \[(?P<version>[^\]]+)\]")
MODIFIED = re.compile(r"^modified:\s*['\"]?(?P<date>\d{4}-\d{2}-\d{2})")


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True
    ).stdout


def released_packages(repo: Path, base: str, packages: dict) -> list[str]:
    """Packages whose <pkg>/CHANGELOG.md the PR changes, per release config."""
    changed = git(repo, "diff", "--name-only", f"{base}...HEAD", "--", "*/CHANGELOG.md")
    names = {Path(p).parent.as_posix() for p in changed.splitlines() if p.strip()}
    return sorted(n for n in names if n in packages)


def newest_release(changelog: str) -> tuple[str | None, dict[str, int]]:
    """Version of the newest `## [x]` heading and entry counts per `### ` section."""
    version, sections, current = None, {}, None
    for line in changelog.splitlines():
        m = VERSION_HEADING.match(line)
        if m:
            if version is not None:
                break
            version = m.group("version")
            continue
        if version is None:
            continue
        if line.startswith("### "):
            current = line[4:].strip()
            sections.setdefault(current, 0)
        elif current and re.match(r"^\s*[*-] \S", line):
            sections[current] += 1
    return version, sections


def check_changelog(repo: Path, pkg: str, config: dict) -> tuple[str, list[str]]:
    allowed = [
        s["section"]
        for s in config.get("changelog-sections", [])
        if not s.get("hidden")
    ]
    path = repo / pkg / "CHANGELOG.md"
    version, sections = newest_release(path.read_text(encoding="utf-8"))
    problems = []
    if version is None:
        return FAIL, [f"{pkg}: no `## [x.y.z]` heading in CHANGELOG.md"]
    if not sections:
        problems.append(f"{pkg} {version}: no `###` section under the newest heading")
    for name, entries in sections.items():
        if allowed and name not in allowed:
            problems.append(
                f"{pkg} {version}: section `{name}` is not one of {', '.join(allowed)}"
            )
        if entries == 0:
            problems.append(f"{pkg} {version}: section `{name}` has no entries")
    return (FAIL if problems else PASS), problems


def check_versions(
    repo: Path, pkg: str, manifest: dict, marketplace: dict
) -> tuple[str, str]:
    plugin_json = json.loads(
        (repo / pkg / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8")
    )
    version, _ = newest_release(
        (repo / pkg / "CHANGELOG.md").read_text(encoding="utf-8")
    )
    entry = next(
        (p for p in marketplace.get("plugins", []) if p.get("name") == pkg), {}
    )
    found = {
        "plugin.json": plugin_json.get("version"),
        ".release-please-manifest.json": manifest.get(pkg),
        "CHANGELOG heading": version,
        "marketplace.json": entry.get("version"),
    }
    detail = f"{pkg}: " + ", ".join(f"{k} {v}" for k, v in found.items())
    return (PASS if len(set(found.values())) == 1 else FAIL), detail


def check_freshness(
    repo: Path, pkg: str, today: dt.date, stale_days: int
) -> tuple[list[str], list[str]]:
    stale, undated = [], []
    cutoff = today - dt.timedelta(days=stale_days)
    for skill in sorted((repo / pkg / "skills").glob("*/SKILL.md")):
        rel = skill.relative_to(repo).as_posix()
        head = skill.read_text(encoding="utf-8").split("\n---", 2)[0]
        m = next(
            (MODIFIED.match(ln) for ln in head.splitlines() if MODIFIED.match(ln)), None
        )
        if m is None:
            undated.append(rel)
            continue
        modified = dt.date.fromisoformat(m.group("date"))
        if modified < cutoff:
            stale.append(f"{rel} ({modified.isoformat()})")
    return stale, undated


def check_blueprint(repo: Path) -> tuple[str, str]:
    result = subprocess.run(
        [
            "bash",
            str(repo / "scripts" / "plugin-compliance-check.sh"),
            "blueprint-plugin",
        ],
        cwd=repo,
        capture_output=True,
        text=True,
    )
    row = next(
        (
            ln
            for ln in result.stdout.splitlines()
            if ln.startswith("| blueprint-plugin |")
        ),
        "",
    )
    cells = [c.strip() for c in row.strip("|").split("|")]
    overall = cells[-1] if cells and cells[-1] in (PASS, WARN, FAIL) else FAIL
    detail = "`plugin-compliance-check.sh blueprint-plugin` Overall: " + (
        overall if row else "no blueprint-plugin row in its output"
    )
    return overall, detail


def worst(statuses: list[str]) -> str:
    for s in (FAIL, WARN):
        if s in statuses:
            return s
    return PASS


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--base", required=True, help="base ref, e.g. origin/main")
    ap.add_argument("--out", required=True, type=Path, help="Markdown report path")
    ap.add_argument(
        "--repo-root", type=Path, default=Path(__file__).resolve().parent.parent
    )
    ap.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    ap.add_argument("--stale-days", type=int, default=90)
    args = ap.parse_args()
    repo = args.repo_root

    try:
        config = json.loads(
            (repo / "release-please-config.json").read_text(encoding="utf-8")
        )
        manifest = json.loads(
            (repo / ".release-please-manifest.json").read_text(encoding="utf-8")
        )
        marketplace = json.loads(
            (repo / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8")
        )
        packages = released_packages(repo, args.base, config.get("packages", {}))
    except (OSError, json.JSONDecodeError, subprocess.CalledProcessError) as e:
        print("=== RELEASE PR DOC CHECK ===")
        print("STATUS=ERROR")
        print(f"REASON=setup_failed: {str(e)[:180]}")
        print("ISSUE_COUNT=1")
        print("ISSUES:")
        print(f"  - SEVERITY=ERROR TYPE=setup_failed MSG={str(e)[:180]}")
        print("=== END RELEASE PR DOC CHECK ===")
        return 2

    rows: list[tuple[str, str, list[str]]] = []
    issues: list[tuple[str, str, str]] = []  # (severity, type, msg)

    cl_status, cl_details = [], []
    ver_status, ver_details = [], []
    stale_all, undated_all = [], []
    for pkg in packages:
        pkg_config = config["packages"][pkg]
        s, d = check_changelog(repo, pkg, pkg_config)
        cl_status.append(s)
        cl_details += d
        issues += [("ERROR", "changelog_format", m) for m in d]
        s, d = check_versions(repo, pkg, manifest, marketplace)
        ver_status.append(s)
        ver_details.append(d)
        if s == FAIL:
            issues.append(("ERROR", "version_mismatch", d))
        stale, undated = check_freshness(repo, pkg, args.today, args.stale_days)
        stale_all += stale
        undated_all += undated

    rows.append(
        (
            "CHANGELOG format",
            worst(cl_status) if packages else PASS,
            cl_details
            or [
                f"{len(packages)} package(s): newest section headings are configured changelog sections"
            ],
        )
    )
    rows.append(
        ("Version consistency", worst(ver_status) if packages else PASS, ver_details)
    )
    fresh_details = [f"not modified in {args.stale_days} days: {s}" for s in stale_all]
    fresh_details += [f"no `modified:` date: {u}" for u in undated_all]
    rows.append(
        (
            "Skill date freshness",
            WARN if fresh_details else PASS,
            fresh_details or [f"every SKILL.md modified within {args.stale_days} days"],
        )
    )
    issues += [("WARN", "stale_skill", d) for d in fresh_details]
    if "blueprint-plugin" in packages:
        s, d = check_blueprint(repo)
        rows.append(("Blueprint compliance", s, [d]))
        if s != PASS:
            issues.append(("ERROR" if s == FAIL else "WARN", "blueprint_compliance", d))
    else:
        rows.append(
            (
                "Blueprint compliance",
                PASS,
                ["n/a: blueprint-plugin is not in this release"],
            )
        )

    lines = [
        HEADING,
        "",
        MARKER,
        "",
        f"Packages: {', '.join(f'`{p}`' for p in packages) or 'none (no CHANGELOG.md changed)'}",
        "",
        "| Check | Status | Details |",
        "|-------|--------|---------|",
    ]
    for name, status, details in rows:
        summary = (
            details[0] if len(details) == 1 else f"{len(details)} item(s), listed below"
        )
        lines.append(f"| {name} | {status} | {summary} |")
    expanded = [(n, d) for n, s, d in rows if len(d) > 1]
    if expanded:
        lines += ["", "### Details"]
        for name, details in expanded:
            lines += ["", f"**{name}**", ""] + [f"- {d}" for d in details]
    lines += [
        "",
        f"Generated by `scripts/release-pr-doc-audit.py` against `{args.base}`.",
    ]
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")

    errors = [i for i in issues if i[0] == "ERROR"]
    warns = [i for i in issues if i[0] == "WARN"]
    status = "ERROR" if errors else ("WARN" if warns else "OK")
    print("=== RELEASE PR DOC CHECK ===")
    print(f"PACKAGES={','.join(packages)}")
    print(f"FAILURES={sum(1 for _, s, _ in rows if s == FAIL)}")
    print(f"WARNINGS={sum(1 for _, s, _ in rows if s == WARN)}")
    print(f"STATUS={status}")
    first = (errors or warns or [None])[0]
    if first:
        reason = f"{first[1]}: {first[2]}"[:180]
        more = len(issues) - 1
        print(f"REASON={reason}{f' (+{more} more)' if more else ''}")
    print(f"ISSUE_COUNT={len(issues)}")
    if issues:
        print("ISSUES:")
        for sev, typ, msg in issues:
            print(f"  - SEVERITY={sev} TYPE={typ} MSG={msg}")
    print("=== END RELEASE PR DOC CHECK ===")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
