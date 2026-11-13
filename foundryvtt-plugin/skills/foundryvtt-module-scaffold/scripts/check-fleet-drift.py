#!/usr/bin/env python3
"""Report drift between the generated FoundryVTT modules and the scaffold.

`scaffold.py` generates the module repos; this script reads them from the fleet
root (`--fleet-root`, else `$FOUNDRYVTT_FLEET_ROOT`, else the current
directory). The files it emits drift over time
and nothing reported it (#2761): the duplicate Renovate runner of #2708 sat in
generated modules until it was found by hand.

This script REPORTS. It never writes to a module, because drift is
BIDIRECTIONAL: a module can be ahead of the template (a Renovate bump, a fix
landed where it hurt) or behind it (a gate it predates). An automatic
template -> module apply would silently revert the first kind across the whole
fleet. A human or agent reads the report and lands the fix on whichever side is
behind.

Per-file authority comes from `fleet-policy.toml` (managed / seed / shared /
absent); see that file for the semantics and the per-entry rationale.

The comparable file set is DERIVED from the generator: import `scaffold.py`,
render `build_file_map` for every variant and two distinct module names, and
keep the paths that render under BOTH names with one identical body. A derived
template with no policy entry is an ERROR, so the manifest cannot silently fall
behind the scaffold.

This is the foundry sibling of comfyui-plugin's comfyui-node-scaffold checker
(issue #2761 chose a sibling now and a shared core later), so plugins stay
independently installable. A fix to the shared comparison logic (the #2756
plurality rule, for instance) has to land in both until that core exists.

Output follows .claude/rules/structured-script-output.md.
Exit 0 on OK/WARN, 1 on ERROR, 2 on an unknown argument.
"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import os
import sys
import tomllib
from collections import defaultdict
from pathlib import Path
from typing import Any

SKILL_DIR = Path(__file__).resolve().parent.parent
SCAFFOLD_PY = SKILL_DIR / "scaffold.py"
DEFAULT_POLICY = SKILL_DIR / "fleet-policy.toml"
# The fleet root comes from context: --fleet-root, else $FOUNDRYVTT_FLEET_ROOT,
# else the current directory (where the module clones sit side by side).
FLEET_ROOT_ENV = "FOUNDRYVTT_FLEET_ROOT"


def default_fleet_root() -> Path:
    return Path(os.environ.get(FLEET_ROOT_ENV) or ".")


# Never treated as a module directory. `.claude/worktrees/` holds full repo
# clones (#1492, #1548) and `dist/` is build output; walking either would
# double-count a tree under a second path.
PRUNE_NAMES = {".claude", "dist", "node_modules", ".git", ".venv"}

VALID_POLICIES = {"managed", "seed", "shared", "absent"}

# Probe contexts used to derive the context-invariant template set. Two module
# names and every variant: a path whose body is identical across all renders,
# and which appears under BOTH names, carries no substituted placeholder and is
# byte-comparable against a real module without knowing its variant or metadata.
PROBE_CONTEXTS = (
    {
        "name": "foundryvtt-probe-alpha",
        "DISPLAY": "Probe Alpha",
        "DESC": "Alpha probe description.",
        "PUBLISHER": "probe-publisher-a",
        "AUTHOR": "Probe Author A",
        "FVTT_MIN": "12",
        "FVTT_VERIFIED": "13",
        "YEAR": "2026",
        "DATE": "2026-01-01",
    },
    {
        "name": "foundryvtt-zzz-beta",
        "DISPLAY": "Zed Beta",
        "DESC": "Beta probe description, deliberately different.",
        "PUBLISHER": "probe-publisher-b",
        "AUTHOR": "Probe Author B",
        "FVTT_MIN": "11",
        "FVTT_VERIFIED": "14",
        "YEAR": "2027",
        "DATE": "2027-02-02",
    },
)


def load_scaffold() -> Any:
    spec = importlib.util.spec_from_file_location("foundry_scaffold", SCAFFOLD_PY)
    if spec is None or spec.loader is None:  # pragma: no cover - import plumbing
        raise RuntimeError(f"cannot import {SCAFFOLD_PY}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def render(module: Any, probe: dict[str, str], variant: str) -> dict[str, str]:
    # derive() warns on stderr for unconventional names; the probes are
    # conventional, but keep the report clean regardless.
    with contextlib.redirect_stderr(io.StringIO()):
        ctx = module.derive(probe["name"], None)
        ctx.update({k: v for k, v in probe.items() if k != "name"})
        return module.build_file_map(ctx, variant)


def derive_invariant_templates(module: Any) -> dict[str, str]:
    """Paths rendered under both probe names with one identical body."""
    bodies: dict[str, set[str]] = defaultdict(set)
    probes_seen: dict[str, set[int]] = defaultdict(set)
    for index, probe in enumerate(PROBE_CONTEXTS):
        for variant in module.VALID_VARIANTS:
            for path, body in render(module, probe, variant).items():
                bodies[path].add(body)
                probes_seen[path].add(index)
    return {
        path: next(iter(vals))
        for path, vals in bodies.items()
        # Both probes, not "two renders": `styles/<id>.css` renders three times
        # for ONE probe (once per variant) with the same body, but its PATH
        # carries the module id, so no real module has that path.
        if len(vals) == 1 and len(probes_seen[path]) == len(PROBE_CONTEXTS)
    }


def load_policy(path: Path) -> tuple[dict[str, dict[str, Any]], list[str]]:
    problems: list[str] = []
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}, [f"policy manifest not found: {path}"]
    except tomllib.TOMLDecodeError as exc:
        return {}, [f"policy manifest is not valid TOML: {exc}"]

    files = data.get("files", {})
    if not isinstance(files, dict):
        return {}, ["policy manifest has no [files] table"]

    entries: dict[str, dict[str, Any]] = {}
    for rel, entry in files.items():
        policy = entry.get("policy") if isinstance(entry, dict) else None
        if policy not in VALID_POLICIES:
            problems.append(f"{rel}: unknown policy {policy!r}")
            continue
        entries[rel] = entry
    return entries, problems


def discover_modules(root: Path, wanted: list[str]) -> list[Path]:
    if not root.is_dir():
        return []
    modules = []
    for child in sorted(root.iterdir()):
        if not child.is_dir() or child.name in PRUNE_NAMES:
            continue
        if not child.name.startswith("foundryvtt-"):
            continue
        # module.json marks a Foundry module; a workspace sibling such as an
        # MCP server or the harness carries none.
        if not (child / "module.json").is_file():
            continue
        if wanted and child.name not in wanted:
            continue
        modules.append(child)
    return modules


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def _group(rows: list[str]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = defaultdict(list)
    for row in rows:
        parts = row.split("|")
        grouped[parts[1]].append(parts[0])
    return grouped


def emit_issue_body(
    *,
    modules: list[str],
    findings: dict[str, list[str]],
    issue_count: int,
) -> None:
    """Markdown for a scheduled sweep. Emits NOTHING when the fleet is clean."""
    if issue_count == 0:
        return

    print(
        f"`check-fleet-drift.py` swept {len(modules)} FoundryVTT module repos "
        "against the `foundryvtt-module-scaffold` template and found "
        f"{issue_count} finding(s).\n"
    )
    print(
        "**Do not bulk-apply the template.** Drift here is bidirectional — a "
        "module can be ahead of the template (a Renovate bump) or behind it. "
        "Classify each row's direction before fixing. Per-file authority is "
        "declared in "
        "`foundryvtt-plugin/skills/foundryvtt-module-scaffold/fleet-policy.toml`.\n"
    )

    if findings["policy_problem"]:
        print("## Policy manifest problems (ERROR)\n")
        for row in findings["policy_problem"]:
            print(f"- {row}")
        print()

    if findings["unclassified_template"]:
        print("## Templates with no policy entry (ERROR)\n")
        for rel in findings["unclassified_template"]:
            print(f"- `{rel}`")
        print()

    if findings["managed_drift"]:
        print("## `managed` drift (ERROR)\n")
        print("| File | Modules |\n| --- | --- |")
        for rel, names in sorted(_group(findings["managed_drift"]).items()):
            print(f"| `{rel}` | {len(names)}: {', '.join(sorted(names))} |")
        print()

    if findings["absent_present"]:
        print("## Files that must be absent (ERROR)\n")
        print("| File | Modules |\n| --- | --- |")
        for rel, names in sorted(_group(findings["absent_present"]).items()):
            print(f"| `{rel}` | {len(names)}: {', '.join(sorted(names))} |")
        print()

    if findings["backport"]:
        print("## `shared`: the fleet leads, the template should back-port (WARN)\n")
        for row in findings["backport"]:
            print(
                f"- `{row.split('|')[0]}` — the fleet majority differs from the template"
            )
        print()

    if findings["shared_split"]:
        print("## `shared`: no fleet majority, direction undecided (WARN)\n")
        print(
            "The largest group of identical bodies is not a strict majority of the "
            "swept modules. Neither a back-port nor a module sync is implied: "
            "compare the groups and decide which body is canonical.\n"
        )
        for row in findings["shared_split"]:
            rel, largest, total = row.split("|")
            print(
                f"- `{rel}` — largest group {largest.split('=')[1]} of "
                f"{total.split('=')[1]} modules"
            )
        print()

    if findings["shared_minority"]:
        print(
            "## `shared`: a module differs from the fleet majority "
            "(under a split, the largest group) (WARN)\n"
        )
        print("| File | Modules |\n| --- | --- |")
        for rel, names in sorted(_group(findings["shared_minority"]).items()):
            print(f"| `{rel}` | {', '.join(sorted(names))} |")
        print()

    if findings["stale_policy_entry"]:
        print("## Policy entries for templates the scaffold no longer emits (WARN)\n")
        for rel in findings["stale_policy_entry"]:
            print(f"- `{rel}`")
        print()

    # Not the swept root: in CI that is a throwaway clone directory, and pasting
    # it would give a reader a path that does not exist on their machine.
    print("---\n")
    print(
        "Reproduce locally from the directory holding your module clones (or pass "
        f"`--fleet-root`, or set `{FLEET_ROOT_ENV}`):\n\n```\n"
        "python3 foundryvtt-plugin/skills/foundryvtt-module-scaffold/scripts/check-fleet-drift.py\n"
        "```\n"
    )


# Finding types in report order, with their severity. REASON= names the first
# finding at the reported severity, so ERROR types come first.
FINDING_TYPES = (
    ("policy_problem", "ERROR"),
    ("unclassified_template", "ERROR"),
    ("managed_drift", "ERROR"),
    ("absent_present", "ERROR"),
    ("backport", "WARN"),
    ("shared_split", "WARN"),
    ("shared_minority", "WARN"),
    ("stale_policy_entry", "WARN"),
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="check-fleet-drift.py",
        description="Report drift between the generated FoundryVTT modules and the scaffold.",
    )
    parser.add_argument(
        "--fleet-root",
        type=Path,
        default=None,
        help=(
            f"directory holding the module repos (default: ${FLEET_ROOT_ENV}, "
            "else the current directory)"
        ),
    )
    parser.add_argument(
        "--module",
        action="append",
        default=[],
        metavar="NAME",
        help="restrict to this module repo (repeatable)",
    )
    parser.add_argument(
        "--policy",
        type=Path,
        default=DEFAULT_POLICY,
        help="sync-policy manifest (default: the skill's fleet-policy.toml)",
    )
    parser.add_argument(
        "--issue-body",
        action="store_true",
        help=(
            "emit a markdown issue body instead of the KEY=VALUE report, and "
            "NOTHING when the fleet is clean. Always exits 0."
        ),
    )
    # argparse exits 2 with usage on an unknown argument. Never swallow one: a
    # misparsed flag is how a bounded operation silently becomes unbounded
    # (#2057).
    args = parser.parse_args(argv)

    fleet_root = (
        args.fleet_root.expanduser()
        if args.fleet_root
        else default_fleet_root().expanduser().resolve()
    )
    policy, policy_problems = load_policy(args.policy.expanduser())
    module = load_scaffold()
    templates = derive_invariant_templates(module)
    modules = discover_modules(fleet_root, args.module)

    # An `absent` path is checked against everything the scaffold emits, not
    # only the invariant set: the generator must not emit it under any variant.
    emitted: set[str] = set()
    for probe in PROBE_CONTEXTS:
        for variant in module.VALID_VARIANTS:
            emitted.update(render(module, probe, variant))
    for rel, entry in sorted(policy.items()):
        if entry["policy"] == "absent" and rel in emitted:
            policy_problems.append(f"{rel}: policy=absent but the scaffold emits it")

    findings: dict[str, list[str]] = {name: [] for name, _ in FINDING_TYPES}
    findings["policy_problem"] = policy_problems
    findings["unclassified_template"] = sorted(p for p in templates if p not in policy)
    findings["stale_policy_entry"] = sorted(
        rel
        for rel, entry in policy.items()
        if entry["policy"] != "absent" and rel not in templates
    )
    files_compared = 0

    # --- managed + shared, over the context-invariant templates --------------
    fleet_bodies: dict[str, dict[str, list[str]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for rel in sorted(templates):
        entry = policy.get(rel)
        if entry is None or entry["policy"] not in ("managed", "shared"):
            continue
        for mod in modules:
            body = read_text(mod / rel)
            files_compared += 1
            key = "<<absent>>" if body is None else body
            fleet_bodies[rel][key].append(mod.name)
            if entry["policy"] == "managed" and key != templates[rel]:
                reason = "absent" if body is None else "differs"
                findings["managed_drift"].append(f"{mod.name}|{rel}|{reason}")

    for rel, groups in fleet_bodies.items():
        if policy[rel]["policy"] != "shared":
            continue
        ranked = sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0]))
        largest_body, largest = ranked[0]
        for _body, names in ranked[1:]:
            for name in names:
                findings["shared_minority"].append(
                    f"{name}|{rel}|majority={len(largest)}|minority={len(names)}"
                )
        # BACKPORT tells a reader to move the template to the fleet's body, so
        # it needs a STRICT majority of the swept modules. A plurality is one
        # faction, and back-porting from it would regress the template (#2756).
        if len(largest) * 2 > len(modules):
            if largest_body != templates[rel]:
                findings["backport"].append(
                    f"{rel}|fleet_majority={len(largest)}|of={len(modules)}"
                )
        else:
            findings["shared_split"].append(
                f"{rel}|largest={len(largest)}|of={len(modules)}"
            )

    # --- absent: the path must exist in no module -----------------------------
    for rel, entry in sorted(policy.items()):
        if entry["policy"] != "absent":
            continue
        for mod in modules:
            files_compared += 1
            if (mod / rel).exists():
                findings["absent_present"].append(f"{mod.name}|{rel}")

    # --- report ---------------------------------------------------------------
    counts: dict[str, int] = defaultdict(int)
    for entry in policy.values():
        counts[entry["policy"]] += 1

    issues = [
        (severity, name, row)
        for name, severity in FINDING_TYPES
        for row in findings[name]
    ]
    errors = [i for i in issues if i[0] == "ERROR"]
    issue_count = len(issues)
    if errors:
        status = "ERROR"
    elif issues:
        status = "WARN"
    else:
        status = "OK"

    if args.issue_body:
        emit_issue_body(
            modules=[m.name for m in modules],
            findings=findings,
            issue_count=issue_count,
        )
        return 0

    out = print
    out("=== FLEET DRIFT ===")
    out(f"FLEET_ROOT={fleet_root}")
    out(f"FLEET_ROOT_EXISTS={'true' if fleet_root.is_dir() else 'false'}")
    out(f"POLICY_MANIFEST={args.policy}")
    out(f"MODULE_COUNT={len(modules)}")
    out(f"TEMPLATE_PATHS={len(templates)}")
    out(f"FILES_COMPARED={files_compared}")
    for name in ("managed", "shared", "seed", "absent"):
        out(f"POLICY_{name.upper()}={counts[name]}")
    out(f"POLICY_PROBLEM_COUNT={len(findings['policy_problem'])}")
    out(f"UNCLASSIFIED_TEMPLATE_COUNT={len(findings['unclassified_template'])}")
    out(f"MANAGED_DRIFT_COUNT={len(findings['managed_drift'])}")
    out(f"ABSENT_PRESENT_COUNT={len(findings['absent_present'])}")
    out(f"BACKPORT_SIGNAL_COUNT={len(findings['backport'])}")
    out(f"SHARED_SPLIT_COUNT={len(findings['shared_split'])}")
    out(f"SHARED_MINORITY_COUNT={len(findings['shared_minority'])}")
    out(f"STALE_POLICY_ENTRY_COUNT={len(findings['stale_policy_entry'])}")
    if modules:
        out("MODULES=" + ",".join(m.name for m in modules))

    sections = (
        ("policy_problem", "POLICY_PROBLEM", "policy manifest problems (ERROR)"),
        (
            "unclassified_template",
            "UNCLASSIFIED_TEMPLATE",
            "templates with no policy entry (ERROR: add one to fleet-policy.toml)",
        ),
        (
            "managed_drift",
            "MANAGED_DRIFT",
            "managed drift (ERROR; a human classifies the DIRECTION)",
        ),
        ("absent_present", "ABSENT_PRESENT", "files that must be absent (ERROR)"),
        (
            "backport",
            "BACKPORT",
            "shared: fleet leads, template should back-port (WARN)",
        ),
        (
            "shared_split",
            "SHARED_SPLIT",
            "shared: no strict fleet majority; a human picks the canonical body (WARN)",
        ),
        (
            "shared_minority",
            "SHARED_MINORITY",
            "shared: module differs from the fleet majority "
            "(under a split, the largest group) (WARN)",
        ),
        (
            "stale_policy_entry",
            "STALE_POLICY_ENTRY",
            "policy entries for templates the scaffold no longer emits (WARN)",
        ),
    )
    for name, key, title in sections:
        if findings[name]:
            out("")
            out(f"--- {title} ---")
            for row in findings[name]:
                out(f"{key}={row}")

    out("")
    out(f"STATUS={status}")
    if status != "OK":
        first = next(i for i in issues if i[0] == status)
        reason = " ".join(f"{first[1]}: {first[2]}".split())[:180]
        if issue_count > 1:
            reason += f" (+{issue_count - 1} more)"
        out(f"REASON={reason}")
    out(f"ISSUE_COUNT={issue_count}")
    if issues:
        out("ISSUES:")
        for severity, name, row in issues:
            out(f"  - SEVERITY={severity} TYPE={name} MSG={row}")
    out("=== END FLEET DRIFT ===")

    return 1 if status == "ERROR" else 0


if __name__ == "__main__":
    sys.exit(main())
