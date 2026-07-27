#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "jsonschema==4.26.0",
# ]
# ///
"""Validate docs/blueprint/manifest.json against schemas/manifest.schema.json (issue #2136).

WHY THIS EXISTS
---------------
The manifest is the control surface every blueprint skill reads, and until now
nothing validated it. Every consumer degrades gracefully on bad input --
`get-automation-config.sh` coerces a non-numeric `autonomy_level` to 0,
`get-validation-config.sh` falls back per key, `blueprint-sync-ids.sh` treats a
missing `id_registry` as absent. That is correct RUNTIME behaviour, but it makes
a typo indistinguishable from an intentional omission: `autonomy_levle: 3` reads
as level 0, `adr_dris: [...]` reads as unconfigured, and nothing says a word.

The closed blocks in the schema (`additionalProperties: false` on `automation`,
`validation`, `structure`, `project`, `workspaces`, `id_registry` and the root)
are what actually catch that class. Open blocks -- `task_registry`,
`custom_overrides`, the `generated` / `documents` / `github_issues` maps -- carry
user or registry data whose key set legitimately varies.

DEGRADATION CONTRACT
--------------------
This is a diagnostic, not a gate on the skills that read the manifest. It never
mutates anything, and it stays quiet rather than wrong:

  no manifest                -> STATUS=OK   SOURCE=none
  manifest is not valid JSON -> STATUS=ERROR (json_parse issue)
  format_version < schema's  -> STATUS=WARN  SCHEMA_APPLICABLE=false, no diff noise
                                (run /blueprint:upgrade first)
  jsonschema unimportable    -> STATUS=OK   SOURCE=<manifest>:no_validator

Run it either way:

  ./check-manifest-schema.py --project-dir .      # uv resolves jsonschema (PEP723)
  python3 check-manifest-schema.py --project-dir .  # uses an installed jsonschema,
                                                    # else fails open (exit 0)

Output follows .claude/rules/structured-script-output.md. Exit 0 on OK/WARN,
1 on ERROR (per .claude/rules/parallel-safe-queries.md, ERROR is the only
non-zero so a clean-but-degraded run never cancels sibling calls).

Usage: check-manifest-schema.py [--project-dir DIR] [--schema PATH] [--manifest PATH]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SECTION = "BLUEPRINT MANIFEST SCHEMA"


def emit(lines: list[str], status: str, issues: list[tuple[str, str, str]]) -> int:
    """Print the structured block and return the process exit code."""
    print(f"=== {SECTION} ===")
    for line in lines:
        print(line)
    print(f"STATUS={status}")
    print(f"ISSUE_COUNT={len(issues)}")
    if issues:
        print("ISSUES:")
        for severity, kind, msg in issues:
            print(f"  - SEVERITY={severity} TYPE={kind} MSG={msg}")
    print(f"=== END {SECTION} ===")
    return 1 if status == "ERROR" else 0


def version_tuple(raw: str) -> tuple[int, ...] | None:
    parts = raw.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        return None
    return tuple(int(p) for p in parts)


def resolve_manifest(project_dir: Path, override: str | None) -> Path | None:
    if override:
        candidate = Path(override)
        return candidate if candidate.is_file() else None
    # Same resolution order as get-automation-config.sh / get-validation-config.sh.
    for rel in ("docs/blueprint/manifest.json", "docs/blueprint/.manifest.json"):
        candidate = project_dir / rel
        if candidate.is_file():
            return candidate
    return None


def describe(error) -> str:  # jsonschema.ValidationError
    """One-line, grep-friendly rendering of a validation error.

    The JSON pointer is what makes a finding actionable: `/automation` plus
    "Additional properties are not allowed ('autonomy_levle' was unexpected)"
    names both the block and the typo.
    """
    pointer = "/" + "/".join(str(p) for p in error.absolute_path)
    message = " ".join(str(error.message).split())
    return f"AT={pointer} DETAIL={message}"


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--project-dir", default=".")
    parser.add_argument("--schema", default=None)
    parser.add_argument("--manifest", default=None)
    args = parser.parse_args()

    project_dir = Path(args.project_dir)
    schema_path = (
        Path(args.schema)
        if args.schema
        else Path(__file__).resolve().parent.parent / "schemas" / "manifest.schema.json"
    )

    manifest_path = resolve_manifest(project_dir, args.manifest)
    if manifest_path is None:
        return emit(["SOURCE=none", "MANIFEST=", "SCHEMA_APPLICABLE=false"], "OK", [])

    lines = [f"MANIFEST={manifest_path}"]

    try:
        schema = json.loads(schema_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        lines.append(f"SOURCE={manifest_path}:no_schema")
        lines.append("SCHEMA_APPLICABLE=false")
        return emit(
            lines,
            "ERROR",
            [("ERROR", "schema_unreadable", f"PATH={schema_path} DETAIL={exc}")],
        )

    schema_version = str(schema.get("x-blueprint-format-version", "0.0.0"))
    lines.append(f"SCHEMA={schema_path}")
    lines.append(f"SCHEMA_FORMAT_VERSION={schema_version}")

    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        lines.append(f"SOURCE={manifest_path}:unparseable")
        lines.append("MANIFEST_FORMAT_VERSION=")
        lines.append("SCHEMA_APPLICABLE=false")
        return emit(
            lines,
            "ERROR",
            [("ERROR", "json_parse", f"DETAIL={' '.join(str(exc).split())}")],
        )

    manifest_version = ""
    if isinstance(manifest, dict):
        raw = manifest.get("format_version")
        manifest_version = raw if isinstance(raw, str) else ""
    lines.append(f"MANIFEST_FORMAT_VERSION={manifest_version}")

    # An older-format manifest is not a schema violation -- it is an upgrade the
    # user has not run yet. Validating it against the current schema would bury
    # that one actionable fact under a wall of spurious findings.
    mv, sv = version_tuple(manifest_version), version_tuple(schema_version)
    if mv is None or sv is None or mv < sv:
        lines.append(f"SOURCE={manifest_path}:format_version_below_schema")
        lines.append("SCHEMA_APPLICABLE=false")
        detail = manifest_version or "<missing or malformed>"
        return emit(
            lines,
            "WARN",
            [
                (
                    "WARN",
                    "format_version_below_schema",
                    f"HAS={detail} SCHEMA={schema_version} "
                    "FIX=run /blueprint:upgrade before schema validation applies",
                )
            ],
        )

    try:
        from jsonschema import Draft7Validator
    except ImportError:
        # Fail open: a missing validator is an environment gap, not a manifest
        # defect. Siblings in this directory degrade the same way on absent jq.
        lines.append(f"SOURCE={manifest_path}:no_validator")
        lines.append("SCHEMA_APPLICABLE=false")
        lines.append("HINT=install jsonschema, or run this script through uv")
        return emit(lines, "OK", [])

    lines.append(f"SOURCE={manifest_path}")
    lines.append("SCHEMA_APPLICABLE=true")

    validator = Draft7Validator(schema)
    errors = sorted(validator.iter_errors(manifest), key=lambda e: list(e.absolute_path))
    issues = [("ERROR", "schema_violation", describe(e)) for e in errors]
    return emit(lines, "ERROR" if issues else "OK", issues)


if __name__ == "__main__":
    sys.exit(main())
