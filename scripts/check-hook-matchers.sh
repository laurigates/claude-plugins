#!/usr/bin/env bash
# check-hook-matchers.sh — every plugin hook `matcher` must be a valid tool-name
# filter, never permission-rule syntax.
#
# WHY
# A hook `matcher` is tested against the tool NAME only. A value made of
# letters, digits, `_`, `-`, spaces, `,` and `|` is an exact name (or list of
# names); anything else is a JavaScript regular expression, unanchored. So
#     "matcher": "Write(docs/adrs/**)"
# is not a path filter: it is the regex /Write(docs/adrs/**)/, which does not
# even compile ("Nothing to repeat") and can never match the name `Write`.
# blueprint-plugin shipped 17 such matchers; none of those hooks ever ran. The
# path filter belongs in the handler's `if` field ("if": "Edit(docs/**)"), or in
# the script itself. `if` does not cover every tool: on Claude Code 2.1.295 a
# `Skill(name)` or `Skill(skill:name*)` condition never matched.
#
# WHAT IS FLAGGED (tool events: PreToolUse, PostToolUse, PostToolUseFailure,
# PermissionRequest, PermissionDenied)
#   permission_rule_matcher   `Name(` — permission-rule syntax in a matcher
#   invalid_regex_matcher     a regex-path matcher that does not compile
#                             (Python `re` approximates JavaScript here; the
#                             constructs that differ are not used in matchers)
#
# SCOPE
# <plugin>/hooks.json, <plugin>/hooks/hooks.json and the inline `hooks` of
# <plugin>/.claude-plugin/plugin.json, for every top-level *-plugin directory.
# A scan that finds no hook JSON is STATUS=ERROR TYPE=nothing_scanned, never a
# silent OK.
#
# Usage: bash scripts/check-hook-matchers.sh [--project-dir DIR]
# Exit:  0 = OK, 1 = ERROR, 2 = usage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ $# -ge 2 ] || { echo "ERROR: --project-dir needs a value" >&2; exit 2; }
      PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT_DIR" ] || { echo "ERROR: project dir not found: $PROJECT_DIR" >&2; exit 2; }
cd "$PROJECT_DIR"

python3 - <<'PY'
import glob
import json
import re
import sys

TOOL_EVENTS = {
    "PreToolUse",
    "PostToolUse",
    "PostToolUseFailure",
    "PermissionRequest",
    "PermissionDenied",
}
EXACT = re.compile(r"^[A-Za-z0-9_\-, |]*$")
PERMISSION_RULE = re.compile(r"^\s*[A-Za-z_][A-Za-z0-9_]*\(")

files = sorted(
    set(glob.glob("*-plugin/hooks.json"))
    | set(glob.glob("*-plugin/hooks/hooks.json"))
    | set(glob.glob("*-plugin/.claude-plugin/plugin.json"))
)

issues = []
scanned = 0
matchers = 0
for path in files:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        issues.append(("parse_error", f"{path}: {exc}"))
        continue
    hooks = data.get("hooks") if isinstance(data, dict) else None
    if not isinstance(hooks, dict):
        continue
    scanned += 1
    for event, blocks in hooks.items():
        if event not in TOOL_EVENTS or not isinstance(blocks, list):
            continue
        for block in blocks:
            if not isinstance(block, dict):
                continue
            matcher = block.get("matcher") or ""
            if matcher in ("", "*"):
                continue
            matchers += 1
            if PERMISSION_RULE.match(matcher):
                issues.append((
                    "permission_rule_matcher",
                    f"{path} event={event} matcher={matcher!r}"
                    " (a matcher sees only the tool name; move the path filter to the"
                    " handler's `if` field or into the script)",
                ))
                continue
            if EXACT.match(matcher):
                continue
            try:
                re.compile(matcher)
            except re.error as exc:
                issues.append((
                    "invalid_regex_matcher",
                    f"{path} event={event} matcher={matcher!r} ({exc})",
                ))

if scanned == 0:
    issues.append(("nothing_scanned", "found no *-plugin hook JSON under the project dir"))

print("=== HOOK MATCHERS ===")
print(f"FILES_SCANNED={scanned}")
print(f"TOOL_MATCHERS={matchers}")
print(f"ISSUE_COUNT={len(issues)}")
if issues:
    print("STATUS=ERROR")
    kind, msg = issues[0]
    reason = " ".join(f"{kind}: {msg}".split())[:180]
    if len(issues) > 1:
        reason += f" (+{len(issues) - 1} more)"
    print(f"REASON={reason}")
    print("ISSUES:")
    for kind, msg in issues:
        print(f"  - SEVERITY=ERROR TYPE={kind} MSG={msg}")
else:
    print("STATUS=OK")
print("=== END HOOK MATCHERS ===")
sys.exit(1 if issues else 0)
PY
