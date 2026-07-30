#!/usr/bin/env python3
"""Report drift between the ComfyUI pack fleet and the scaffold template.

`scaffold.py` generates the pack repos under ~/repos/laurigates/comfyui-nodes.
The files it emits drift over time and, before this checker, nothing detected
it: `tests/test_publish_hygiene.py` was supposed to stay byte-identical
fleet-wide with no gate at all, and a stale `just assets` recipe silently
distorted banner artwork in one pack for months.

This script REPORTS. It never writes to a pack, because drift is BIDIRECTIONAL
— all 13 packs are ahead of the template on `release-please.yml` (ubuntu-slim +
release-please-action@v5), the template is ahead on `RELEASE-CHECKLIST.md`, and
Renovate independently pushes packs ahead on pinned versions. An automatic
template -> pack apply would be a silent-revert bug across 13 repos. A human or
agent reads the report and lands the fix on whichever side is behind.

Per-file authority comes from `fleet-policy.toml` (managed / seed / shared /
block); see that file for the semantics and the per-entry rationale.

The comparable file set is DERIVED from the generator (import `scaffold.py`,
render `build_file_map` across every variant and two distinct pack names, keep
the paths whose body is identical everywhere) — never a hand-copied list, which
would drift exactly like the thing it audits. A derived template with no policy
entry is an ERROR, so the manifest cannot silently fall behind the scaffold.

Output follows .claude/rules/structured-script-output.md.
Exit 0 on OK/WARN, 1 on ERROR, 2 on an unknown argument.
"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import re
import sys
import tomllib
from collections import defaultdict
from pathlib import Path
from typing import Any

SKILL_DIR = Path(__file__).resolve().parent.parent
SCAFFOLD_PY = SKILL_DIR / "scaffold.py"
DEFAULT_POLICY = SKILL_DIR / "fleet-policy.toml"
DEFAULT_FLEET_ROOT = Path.home() / "repos" / "laurigates" / "comfyui-nodes"

# Never treated as a pack directory. `.claude/worktrees/` holds full repo clones
# (issues #1492, #1548) and `dist/` is generated output (#2214); walking either
# double-counts the same tree under a second path.
PRUNE_NAMES = {".claude", "dist", "node_modules", ".git", ".venv", "web"}

VALID_POLICIES = {"managed", "seed", "shared", "block"}

# Probe contexts used to derive the context-invariant template set. Two names
# and every variant: a path whose rendered body is identical across all of them
# carries no substituted placeholder and is therefore byte-comparable against a
# real pack without knowing that pack's variant or metadata.
PROBE_VARIANTS = ("frontend", "backend", "gesture", "shim")
PROBE_CONTEXTS = (
    {
        "name": "comfyui-probe-alpha",
        "DISPLAY": "Probe Alpha",
        "DESC": "Alpha probe description.",
        "AUTHOR": "Probe Author A",
        "PUBLISHER": "probe-publisher-a",
        "DATE": "2026-01-01",
        "VERSION": "0.1.0",
        "widgets": ["seed"],
    },
    {
        "name": "comfyui-zzz-beta",
        "DISPLAY": "Zed Beta",
        "DESC": "Beta probe description, deliberately different.",
        "AUTHOR": "Probe Author B",
        "PUBLISHER": "probe-publisher-b",
        "DATE": "2026-02-02",
        "VERSION": "9.9.9",
        "widgets": ["cfg"],
    },
)


def load_scaffold() -> Any:
    spec = importlib.util.spec_from_file_location("comfyui_scaffold", SCAFFOLD_PY)
    if spec is None or spec.loader is None:  # pragma: no cover - import plumbing
        raise RuntimeError(f"cannot import {SCAFFOLD_PY}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_quietly(module: Any, ctx: dict[str, str], variant: str, widgets: list[str]):
    """Render a file map, swallowing the generator's author-facing warnings.

    `build_file_map` prints scaffold-time advice to stderr (e.g. a banner
    tagline that would overflow). That is useful when scaffolding a new pack
    and pure noise when auditing 13 existing ones — it would bury the report.
    """
    with contextlib.redirect_stderr(io.StringIO()):
        return module.build_file_map(ctx, variant, widgets)


def render(module: Any, probe: dict[str, Any], variant: str) -> dict[str, str]:
    ctx = module.derive(probe["name"])
    for key in ("DISPLAY", "DESC", "AUTHOR", "PUBLISHER", "DATE", "VERSION"):
        ctx[key] = probe[key]
    widgets = probe["widgets"] if variant in ("frontend", "backend") else []
    return build_quietly(module, ctx, variant, list(widgets))


def derive_invariant_templates(module: Any) -> dict[str, str]:
    """Paths whose rendered body is identical for every variant and both probes.

    Those are the templates with no effective placeholder substitution, so a
    single rendered body is the canonical content for the whole fleet.
    """
    bodies: dict[str, set[str]] = defaultdict(set)
    seen: dict[str, int] = defaultdict(int)
    for probe in PROBE_CONTEXTS:
        for variant in PROBE_VARIANTS:
            for path, body in render(module, probe, variant).items():
                bodies[path].add(body)
                seen[path] += 1
    return {
        path: next(iter(vals))
        for path, vals in bodies.items()
        # seen >= 2 rejects a path that exists in only one render (e.g. the
        # backend module, whose FILENAME carries the pack name): a single
        # observation is trivially "identical" and would be a false invariant.
        if len(vals) == 1 and seen[path] >= 2
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
        policy = entry.get("policy")
        if policy not in VALID_POLICIES:
            problems.append(f"{rel}: unknown policy {policy!r}")
            continue
        if policy == "block" and not entry.get("block"):
            problems.append(f"{rel}: policy=block requires a `block` name")
            continue
        entries[rel] = entry
    return entries, problems


def discover_packs(root: Path, wanted: list[str]) -> list[Path]:
    if not root.is_dir():
        return []
    packs = []
    for child in sorted(root.iterdir()):
        if not child.is_dir() or child.name in PRUNE_NAMES:
            continue
        if child.name.startswith(".") or not child.name.startswith("comfyui-"):
            continue
        if not (child / "pyproject.toml").is_file():
            continue
        if wanted and child.name not in wanted:
            continue
        packs.append(child)
    return packs


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def pack_context(module: Any, pack: Path) -> tuple[dict[str, str], str]:
    """Derive a pack's own render context from its name and pyproject.toml."""
    ctx = module.derive(pack.name)
    text = read_text(pack / "pyproject.toml") or ""

    def field(pattern: str, default: str) -> str:
        match = re.search(pattern, text, re.M)
        return match.group(1) if match else default

    ctx["DESC"] = field(r'^description\s*=\s*"([^"]*)"', pack.name)
    ctx["VERSION"] = field(r'^version\s*=\s*"([^"]*)"', "0.1.0")
    ctx["PUBLISHER"] = field(r'^PublisherId\s*=\s*"([^"]*)"', "laurigates")
    ctx["DISPLAY"] = field(r'^DisplayName\s*=\s*"([^"]*)"', pack.name)
    ctx["AUTHOR"] = field(r'^authors\s*=\s*\[\{\s*name\s*=\s*"([^"]*)"', "Lauri Gates")
    ctx["DATE"] = "1970-01-01"

    # The variant only changes files outside the block-compared regions, but
    # build_file_map needs one. A repo-root module named after the pack means a
    # Python backend.
    variant = "backend" if (pack / f"{ctx['PY_MODULE']}.py").is_file() else "frontend"
    return ctx, variant


BLOCK_RULE = "#" * 10


def extract_block(text: str, name: str) -> str | None:
    """Return the `########## / # <name> / ##########` section of a justfile.

    The section runs to the next `##########` rule or end of file.
    """
    lines = text.splitlines()
    start = None
    for i in range(len(lines) - 2):
        if (
            lines[i].strip() == BLOCK_RULE
            and lines[i + 1].strip() == f"# {name}"
            and lines[i + 2].strip() == BLOCK_RULE
        ):
            start = i + 3
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if lines[j].strip() == BLOCK_RULE:
            end = j
            break
    return "\n".join(lines[start:end]).strip("\n")


def _group(rows: list[str], key_index: int = 1) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = defaultdict(list)
    for row in rows:
        parts = row.split("|")
        grouped[parts[key_index]].append(parts[0])
    return grouped


def emit_issue_body(
    *,
    packs: list[str],
    managed_drift: list[str],
    block_drift: list[str],
    shared_minority: list[str],
    backport: list[str],
    unclassified: list[str],
    issue_count: int,
) -> None:
    """Markdown for a scheduled sweep. Emits NOTHING when the fleet is clean."""
    if issue_count == 0:
        return

    print(
        f"`check-fleet-drift.py` swept {len(packs)} ComfyUI pack repos against the "
        "`comfyui-node-scaffold` template and found "
        f"{issue_count} finding(s).\n"
    )
    print(
        "**Do not bulk-apply the template.** Drift here is bidirectional — every "
        "pack is ahead of the template on `release-please.yml`, the template is "
        "ahead on `RELEASE-CHECKLIST.md`, and Renovate independently pushes packs "
        "ahead on pinned versions. Classify each row's direction before fixing. "
        "Per-file authority is declared in "
        "`comfyui-plugin/skills/comfyui-node-scaffold/fleet-policy.toml`.\n"
    )

    if unclassified:
        print("## Templates with no policy entry (ERROR)\n")
        print(
            "The scaffold emits these but `fleet-policy.toml` does not classify them.\n"
        )
        for rel in unclassified:
            print(f"- `{rel}`")
        print()

    if managed_drift or block_drift:
        print("## `managed` drift (ERROR)\n")
        print("| File | Packs |\n| --- | --- |")
        for rel, names in sorted(_group(managed_drift).items()):
            print(f"| `{rel}` | {len(names)}: {', '.join(sorted(names))} |")
        for rel, names in sorted(_group(block_drift).items()):
            print(f"| `{rel}` (block) | {len(names)}: {', '.join(sorted(names))} |")
        print()

    if backport:
        print("## `shared`: the fleet leads, the template should back-port (WARN)\n")
        for row in backport:
            rel = row.split("|")[0]
            print(f"- `{rel}` — the fleet majority differs from the template")
        print()

    if shared_minority:
        print("## `shared`: a pack differs from the fleet majority (WARN)\n")
        print("| File | Packs |\n| --- | --- |")
        for rel, names in sorted(_group(shared_minority).items()):
            print(f"| `{rel}` | {', '.join(sorted(names))} |")
        print()

    # Deliberately the DEFAULT fleet root, not the swept one: in CI that is a
    # throwaway clone directory, and pasting it would give a reader a path that
    # does not exist on their machine.
    print("---\n")
    print(
        "Reproduce locally (defaults to `~/repos/laurigates/comfyui-nodes`):\n\n```\n"
        "python3 comfyui-plugin/skills/comfyui-node-scaffold/scripts/check-fleet-drift.py\n"
        "```\n"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="check-fleet-drift.py",
        description="Report drift between the ComfyUI pack fleet and the scaffold template.",
    )
    parser.add_argument(
        "--fleet-root",
        type=Path,
        default=DEFAULT_FLEET_ROOT,
        help="directory holding the pack repos (default: ~/repos/laurigates/comfyui-nodes)",
    )
    parser.add_argument(
        "--pack",
        action="append",
        default=[],
        metavar="NAME",
        help="restrict to this pack (repeatable)",
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
            "NOTHING when the fleet is clean (so a scheduled sweep files an "
            "issue only when there is drift). Always exits 0."
        ),
    )
    # argparse exits 2 with usage on an unknown argument. Never swallow one:
    # a misparsed flag is how a bounded operation silently becomes unbounded
    # (issue #2057).
    args = parser.parse_args(argv)

    fleet_root = args.fleet_root.expanduser()
    policy, policy_problems = load_policy(args.policy.expanduser())
    module = load_scaffold()
    templates = derive_invariant_templates(module)
    packs = discover_packs(fleet_root, args.pack)

    unclassified = sorted(p for p in templates if p not in policy)
    stale_entries = sorted(
        rel
        for rel, entry in policy.items()
        if entry["policy"] != "block" and rel not in templates
    )

    managed_drift: list[str] = []
    shared_minority: list[str] = []
    backport: list[str] = []
    block_drift: list[str] = []
    files_compared = 0

    # --- managed + shared, over the context-invariant templates --------------
    fleet_bodies: dict[str, dict[str, list[str]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for rel in sorted(templates):
        entry = policy.get(rel)
        if entry is None or entry["policy"] == "seed":
            continue
        for pack in packs:
            body = read_text(pack / rel)
            files_compared += 1
            key = "<<absent>>" if body is None else body
            fleet_bodies[rel][key].append(pack.name)
            if entry["policy"] == "managed" and key != templates[rel]:
                reason = "absent" if body is None else "differs"
                managed_drift.append(f"{pack.name}|{rel}|{reason}")

    for rel, groups in fleet_bodies.items():
        if policy[rel]["policy"] != "shared":
            continue
        ranked = sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0]))
        majority_body, majority_packs = ranked[0]
        for body, names in ranked[1:]:
            for name in names:
                shared_minority.append(
                    f"{name}|{rel}|majority={len(majority_packs)}|minority={len(names)}"
                )
        if majority_body != templates[rel]:
            backport.append(
                f"{rel}|fleet_majority={len(majority_packs)}|of={len(packs)}"
            )

    # --- block policy, rendered per pack -------------------------------------
    for rel, entry in sorted(policy.items()):
        if entry["policy"] != "block":
            continue
        block_name = entry["block"]
        for pack in packs:
            ctx, variant = pack_context(module, pack)
            try:
                rendered = build_quietly(module, ctx, variant, [])
            except Exception as exc:  # pragma: no cover - generator failure
                block_drift.append(
                    f"{pack.name}|{rel}#{block_name}|render_failed:{exc}"
                )
                continue
            want = extract_block(rendered.get(rel, ""), block_name)
            have_text = read_text(pack / rel)
            files_compared += 1
            if want is None:
                block_drift.append(
                    f"{pack.name}|{rel}#{block_name}|template_block_missing"
                )
                continue
            if have_text is None:
                block_drift.append(f"{pack.name}|{rel}#{block_name}|absent")
                continue
            have = extract_block(have_text, block_name)
            if have is None:
                block_drift.append(f"{pack.name}|{rel}#{block_name}|block_missing")
            elif have != want:
                block_drift.append(f"{pack.name}|{rel}#{block_name}|differs")

    # --- report --------------------------------------------------------------
    counts = defaultdict(int)
    for entry in policy.values():
        counts[entry["policy"]] += 1

    errors = (
        len(managed_drift) + len(block_drift) + len(unclassified) + len(policy_problems)
    )
    warnings = len(shared_minority) + len(backport) + len(stale_entries)
    issue_count = errors + warnings

    if not packs:
        status = "OK"
    elif errors:
        status = "ERROR"
    elif warnings:
        status = "WARN"
    else:
        status = "OK"

    if args.issue_body:
        emit_issue_body(
            packs=[p.name for p in packs],
            managed_drift=managed_drift,
            block_drift=block_drift,
            shared_minority=shared_minority,
            backport=backport,
            unclassified=unclassified,
            issue_count=issue_count,
        )
        return 0

    out = print
    out("=== FLEET DRIFT ===")
    out(f"FLEET_ROOT={fleet_root}")
    out(f"FLEET_ROOT_EXISTS={'true' if fleet_root.is_dir() else 'false'}")
    out(f"POLICY_MANIFEST={args.policy}")
    out(f"PACK_COUNT={len(packs)}")
    out(f"TEMPLATE_PATHS={len(templates)}")
    out(f"FILES_COMPARED={files_compared}")
    for name in ("managed", "shared", "seed", "block"):
        out(f"POLICY_{name.upper()}={counts[name]}")
    out(f"MANAGED_DRIFT_COUNT={len(managed_drift)}")
    out(f"BLOCK_DRIFT_COUNT={len(block_drift)}")
    out(f"SHARED_MINORITY_COUNT={len(shared_minority)}")
    out(f"BACKPORT_SIGNAL_COUNT={len(backport)}")
    out(f"UNCLASSIFIED_TEMPLATE_COUNT={len(unclassified)}")
    out(f"STALE_POLICY_ENTRY_COUNT={len(stale_entries)}")

    if packs:
        out("PACKS=" + ",".join(p.name for p in packs))

    if policy_problems:
        out("")
        out("--- policy manifest problems (ERROR) ---")
        for problem in policy_problems:
            out(f"POLICY_PROBLEM={problem}")

    if unclassified:
        out("")
        out(
            "--- templates with no policy entry (ERROR: add one to fleet-policy.toml) ---"
        )
        for rel in unclassified:
            out(f"UNCLASSIFIED_TEMPLATE={rel}")

    if managed_drift:
        out("")
        out("--- managed drift (ERROR; a human classifies the DIRECTION) ---")
        for row in managed_drift:
            out(f"MANAGED_DRIFT={row}")

    if block_drift:
        out("")
        out("--- managed block drift (ERROR) ---")
        for row in block_drift:
            out(f"BLOCK_DRIFT={row}")

    if shared_minority:
        out("")
        out("--- shared: pack differs from the fleet majority (WARN) ---")
        for row in shared_minority:
            out(f"SHARED_MINORITY={row}")

    if backport:
        out("")
        out("--- shared: fleet leads, template should back-port (WARN) ---")
        for row in backport:
            out(f"BACKPORT={row}")

    if stale_entries:
        out("")
        out("--- policy entries for templates the scaffold no longer emits (WARN) ---")
        for rel in stale_entries:
            out(f"STALE_POLICY_ENTRY={rel}")

    out("")
    out(f"ISSUE_COUNT={issue_count}")
    out(f"STATUS={status}")
    out("=== END FLEET DRIFT ===")

    return 1 if status == "ERROR" else 0


if __name__ == "__main__":
    sys.exit(main())
