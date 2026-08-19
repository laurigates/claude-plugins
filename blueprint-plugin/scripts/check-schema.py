#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "jsonschema==4.26.0",
#   "PyYAML==6.0.2",
# ]
# ///
"""Validate a blueprint document against its JSON Schema — the one engine.

WHY THIS EXISTS
---------------
Before this script, every document type had two descriptions of itself: a
schema in schemas/, and a hand-rolled field list in a bash hook. Nothing kept
them in sync, and they drifted:

  * schemas/adr.schema.json required `date` + `status`; the hook required
    `id` + `status` + `created` + `modified` and never looked at `date`.
  * The schema spelled the back-reference `superseded_by`; the hook read
    `superseded-by`. The hook's "Superseded without a replacement" check
    therefore never fired once — ADR-0014 sat Superseded with no back-link.
  * The schema allowed 4 statuses, the hook 7.
  * Nothing referenced schemas/adr.schema.json at all. It was dead text.

Now the schema is the only description. The hooks declare no field list; they
call this script. scripts/tests/test-schema-field-parity.sh fails the build if
a hook grows one back.

WHAT IT VALIDATES
-----------------
A markdown document is projected into an object the schema can describe:

    {"frontmatter": {...parsed line-1 YAML...},
     "sections": {"Context": 0, "Decision": 1, ...}}

so *section* requirements live in the schema too (`sections.required`), not in
a grep loop in bash. Plain JSON documents (feature-tracker.json) validate
directly with --json-file.

SEVERITY LIVES IN THE SCHEMA
----------------------------
Per .claude/rules/hook-block-vs-nudge.md, only safety blocks. A subschema
carrying `"x-blueprint-severity": "warning"` downgrades its failures to a
non-blocking warning — used for "Superseded needs a back-reference" and for
deprecated spellings. Everything else is an error. A subschema's `title`, when
present, is used verbatim as the message, so the schema owns the wording too.

DEGRADATION CONTRACT
--------------------
Never mutates. Stays quiet rather than wrong:

  no document / empty content    -> STATUS=OK   SCHEMA_APPLICABLE=false
  jsonschema or PyYAML missing   -> STATUS=OK   SOURCE=...:no_validator
  unreadable schema              -> STATUS=ERROR
  Edit whose old_string is absent-> STATUS=OK   (cannot reconstruct; fail open)

Exit codes:
  default    0 on OK/WARN, 1 on ERROR   (per .claude/rules/parallel-safe-queries.md)
  --hook     0 on OK/WARN, 2 on ERROR   (PreToolUse block)

Usage:
  check-schema.py --kind adr --file docs/adrs/0001-x.md
  check-schema.py --schema schemas/feature-tracker.schema.json --json-file docs/blueprint/feature-tracker.json
  check-schema.py --kind prd --hook            # PreToolUse JSON on stdin
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from pathlib import Path

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schemas"
SECTION = "BLUEPRINT SCHEMA"
HEADING_RE = re.compile(r"^##\s+(.*?)\s*$")


def emit(
    section: str,
    lines: list[str],
    status: str,
    issues: list[tuple[str, str, str]],
    hook: bool,
) -> int:
    """Print the structured block and return the process exit code."""
    stream = sys.stderr if hook else sys.stdout
    print(f"=== {section} ===", file=stream)
    for line in lines:
        print(line, file=stream)
    print(f"STATUS={status}", file=stream)
    print(f"ISSUE_COUNT={len(issues)}", file=stream)
    if issues:
        print("ISSUES:", file=stream)
        for severity, kind, msg in issues:
            print(f"  - SEVERITY={severity} TYPE={kind} MSG={msg}", file=stream)
    print(f"=== END {section} ===", file=stream)
    if status != "ERROR":
        return 0
    return 2 if hook else 1


# --------------------------------------------------------------------------
# Document projection
# --------------------------------------------------------------------------


def split_frontmatter(content: str) -> tuple[str | None, str]:
    """Return (frontmatter_text, body).

    STRICT: the opening `---` must be the very first line. The pre-reconciliation
    hooks used `awk '/^---$/{if(++n==2)exit}n'`, which happily accepted a block
    sitting anywhere in the file — every ADR in this repo had its metadata
    *below* the H1, where no standard YAML frontmatter parser would ever find
    it. Accepting that kept the documents unreadable to every tool but ours.
    """
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, content
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            return "\n".join(lines[1:idx]), "\n".join(lines[idx + 1 :])
    return None, content


def collect_sections(body: str) -> dict[str, int]:
    sections: dict[str, int] = {}
    in_fence = False
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = HEADING_RE.match(line)
        if match:
            name = match.group(1).strip()
            if name and name not in sections:
                sections[name] = len(sections)
    return sections


# --------------------------------------------------------------------------
# Schema-declared severity and wording
# --------------------------------------------------------------------------


def schema_chain(root: dict, path) -> list[dict]:
    """Every subschema from the root down to the one that failed."""
    node, chain = root, [root]
    for key in path:
        if isinstance(node, dict) and key in node:
            node = node[key]
        elif isinstance(node, list) and isinstance(key, int) and key < len(node):
            node = node[key]
        else:
            break
        if isinstance(node, (dict, list)):
            chain.append(node)  # type: ignore[arg-type]
    return [n for n in chain if isinstance(n, dict)]


def annotation(root: dict, error, key: str, default=None):
    """Deepest declared value of `key` along the failing schema path.

    The root schema is skipped: its `title` names the document type ("Architecture
    Decision Record"), which is a label, not an error message. Only a title placed
    on a subschema is a deliberate wording override.
    """
    value = default
    for node in schema_chain(root, error.absolute_schema_path)[1:]:
        if key in node:
            value = node[key]
    return value


def describe(root: dict, error) -> tuple[str, str]:
    """(severity, message) for one validation error."""
    severity = (
        "ERROR"
        if annotation(root, error, "x-blueprint-severity") != "warning"
        else "WARN"
    )
    title = annotation(root, error, "title")
    pointer = "/" + "/".join(str(p) for p in error.absolute_path)
    if isinstance(title, str) and title:
        return severity, f"AT={pointer} DETAIL={' '.join(title.split())}"
    return severity, f"AT={pointer} DETAIL={' '.join(str(error.message).split())}"


def staleness_issues(schema: dict, document: dict) -> list[tuple[str, str, str]]:
    """Warn on date fields the schema marks with x-blueprint-staleness-days."""
    issues: list[tuple[str, str, str]] = []
    props = schema.get("properties", {}).get("frontmatter", {}).get("properties", {})
    frontmatter = document.get("frontmatter") or {}
    if not isinstance(frontmatter, dict):
        return issues
    today = _dt.date.today()
    for field, spec in props.items():
        if not isinstance(spec, dict):
            continue
        limit = spec.get("x-blueprint-staleness-days")
        raw = frontmatter.get(field)
        if not isinstance(limit, int) or raw is None:
            continue
        try:
            seen = (
                raw if isinstance(raw, _dt.date) else _dt.date.fromisoformat(str(raw))
            )
        except ValueError:
            continue
        age = (today - seen).days
        if age > limit:
            issues.append(
                (
                    "WARN",
                    "stale",
                    f"AT=/frontmatter/{field} DETAIL={field} is {age} days old "
                    f"(threshold {limit}); refresh it against the current codebase",
                )
            )
    return issues


# --------------------------------------------------------------------------
# Input resolution
# --------------------------------------------------------------------------


def hook_content(payload: dict) -> tuple[str | None, str, str]:
    """(content, file_path, why) for a PreToolUse payload.

    Write carries the whole document in `content`. Edit carries only a
    fragment, so the document is reconstructed by applying the replacement to
    the file on disk — the pre-reconciliation hooks read `.tool_input.content`
    unconditionally, which is absent on Edit, so every Edit to a PRD/ADR/PRP
    silently skipped validation entirely.
    """
    tool_input = payload.get("tool_input") or {}
    path = str(tool_input.get("file_path") or "")
    content = tool_input.get("content")
    if isinstance(content, str) and content:
        return content, path, "write"
    old, new = tool_input.get("old_string"), tool_input.get("new_string")
    if isinstance(old, str) and isinstance(new, str) and path:
        try:
            current = Path(path).read_text()
        except OSError:
            return None, path, "edit_unreadable"
        if old not in current:
            return None, path, "edit_no_match"
        return current.replace(old, new, 1), path, "edit"
    return None, path, "no_content"


def resolve_schema(kind: str | None, explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    return SCHEMA_DIR / f"{kind}.schema.json"


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument(
        "--kind",
        default=None,
        help="adr | prd | prp (resolves schemas/<kind>.schema.json)",
    )
    parser.add_argument("--schema", default=None, help="explicit schema path")
    parser.add_argument("--file", default=None, help="markdown document to validate")
    parser.add_argument(
        "--json-file", default=None, help="plain JSON document to validate"
    )
    parser.add_argument(
        "--hook",
        action="store_true",
        help="read a PreToolUse payload on stdin; block with exit 2",
    )
    args = parser.parse_args()

    if not args.kind and not args.schema:
        parser.error("one of --kind or --schema is required")

    label = (args.kind or Path(args.schema).stem.replace(".schema", "")).upper()
    section = f"{SECTION} {label}"
    schema_path = resolve_schema(args.kind, args.schema)
    lines = [f"SCHEMA={schema_path}", f"KIND={args.kind or label.lower()}"]

    try:
        schema = json.loads(schema_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        lines.append("SCHEMA_APPLICABLE=false")
        return emit(
            section,
            lines,
            "ERROR",
            [("ERROR", "schema_unreadable", f"PATH={schema_path} DETAIL={exc}")],
            args.hook,
        )

    # ---- resolve the document ------------------------------------------------
    document: dict | None = None
    source = ""

    if args.json_file:
        source = args.json_file
        lines.append(f"DOCUMENT={source}")
        try:
            document = json.loads(Path(source).read_text())
        except FileNotFoundError:
            lines.append("SCHEMA_APPLICABLE=false")
            return emit(section, lines, "OK", [], args.hook)
        except (OSError, json.JSONDecodeError) as exc:
            lines.append("SCHEMA_APPLICABLE=false")
            return emit(
                section,
                lines,
                "ERROR",
                [("ERROR", "json_parse", f"DETAIL={' '.join(str(exc).split())}")],
                args.hook,
            )
    else:
        if args.hook:
            try:
                payload = json.loads(sys.stdin.read() or "{}")
            except json.JSONDecodeError:
                lines.append("SCHEMA_APPLICABLE=false")
                return emit(section, lines, "OK", [], True)
            content, source, why = hook_content(payload)
            lines.append(f"DOCUMENT={source}")
            lines.append(f"TRIGGER={why}")
            if content is None:
                lines.append("SCHEMA_APPLICABLE=false")
                return emit(section, lines, "OK", [], True)
        elif args.file:
            source = args.file
            lines.append(f"DOCUMENT={source}")
            try:
                content = Path(source).read_text()
            except OSError as exc:
                lines.append("SCHEMA_APPLICABLE=false")
                return emit(
                    section,
                    lines,
                    "ERROR",
                    [("ERROR", "unreadable", f"DETAIL={exc}")],
                    args.hook,
                )
        else:
            parser.error("one of --file, --json-file or --hook is required")

        try:
            import yaml
        except ImportError:
            lines.append(f"SOURCE={source}:no_validator")
            lines.append("SCHEMA_APPLICABLE=false")
            lines.append("HINT=install PyYAML, or run this script through uv")
            return emit(section, lines, "OK", [], args.hook)

        frontmatter_text, body = split_frontmatter(content)
        if frontmatter_text is None:
            lines.append("SCHEMA_APPLICABLE=true")
            lines.append("FRONTMATTER=absent")
            return emit(
                section,
                lines,
                "ERROR",
                [
                    (
                        "ERROR",
                        "frontmatter_missing",
                        "AT=/ DETAIL=no YAML frontmatter at line 1 — the document must open with a "
                        "`---` fence before any heading, so standard parsers can read it",
                    )
                ],
                args.hook,
            )
        try:
            parsed = yaml.safe_load(frontmatter_text)
        except yaml.YAMLError as exc:
            lines.append("SCHEMA_APPLICABLE=true")
            return emit(
                section,
                lines,
                "ERROR",
                [("ERROR", "yaml_parse", f"DETAIL={' '.join(str(exc).split())}")],
                args.hook,
            )
        if parsed is None:
            parsed = {}
        # YAML resolves unquoted YYYY-MM-DD to datetime.date; the schema speaks
        # strings, so normalise before validating rather than loosening the schema.
        if isinstance(parsed, dict):
            parsed = {
                k: (v.isoformat() if isinstance(v, (_dt.date, _dt.datetime)) else v)
                for k, v in parsed.items()
            }
        document = {"frontmatter": parsed, "sections": collect_sections(body)}

    try:
        from jsonschema import Draft7Validator
    except ImportError:
        lines.append(f"SOURCE={source}:no_validator")
        lines.append("SCHEMA_APPLICABLE=false")
        lines.append("HINT=install jsonschema, or run this script through uv")
        return emit(section, lines, "OK", [], args.hook)

    lines.append("SCHEMA_APPLICABLE=true")

    validator = Draft7Validator(schema)
    issues: list[tuple[str, str, str]] = []
    for error in sorted(
        validator.iter_errors(document), key=lambda e: list(e.absolute_path)
    ):
        severity, message = describe(schema, error)
        issues.append((severity, "schema_violation", message))
    if not args.json_file:
        issues.extend(staleness_issues(schema, document))

    status = (
        "ERROR"
        if any(sev == "ERROR" for sev, _, _ in issues)
        else ("WARN" if issues else "OK")
    )
    return emit(section, lines, status, issues, args.hook)


if __name__ == "__main__":
    sys.exit(main())
