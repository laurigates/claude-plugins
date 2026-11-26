#!/usr/bin/env bash
# check-hooks-json-wired.sh — every root-level <plugin>/hooks.json is loaded.
#
# WHY
# Claude Code loads a plugin's hooks from hooks/hooks.json by default. A
# root-level <plugin>/hooks.json loads only when .claude-plugin/plugin.json
# points at it ("hooks": "./hooks.json"). documentation-plugin shipped its
# public-repo leak gate in a root hooks.json with no such key, so
# `claude plugin details` listed "Hooks (0)" and the gate never ran (#3794).
# The pi, OpenCode and Antigravity exporters read the file either way, so
# nothing else noticed.
#
# WHAT IS FLAGGED
#   unwired_hooks_json   <plugin>/hooks.json exists and plugin.json has no
#                        "hooks" key naming it.
#
# A scan that finds no plugin manifest is STATUS=ERROR TYPE=nothing_scanned,
# never a silent OK.
#
# Usage: bash scripts/check-hooks-json-wired.sh [--project-dir DIR]
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
      sed -n '2,20p' "$0"; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT_DIR" ] || { echo "ERROR: project dir not found: $PROJECT_DIR" >&2; exit 2; }
cd "$PROJECT_DIR"

python3 - <<'PY'
import glob
import json
import os
import sys

manifests = sorted(glob.glob("*-plugin/.claude-plugin/plugin.json"))
issues = []
with_root_hooks = 0

for manifest in manifests:
    plugin = manifest.split("/", 1)[0]
    if not os.path.isfile(os.path.join(plugin, "hooks.json")):
        continue
    with_root_hooks += 1
    try:
        with open(manifest, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        issues.append(("unreadable_manifest", plugin, f"{manifest}: {exc}"))
        continue
    hooks = data.get("hooks")
    names = hooks if isinstance(hooks, list) else [hooks]
    if not any(isinstance(n, str) and os.path.normpath(n) == "hooks.json" for n in names):
        issues.append(("unwired_hooks_json", plugin,
                       f'{plugin}/hooks.json exists but plugin.json has no "hooks": "./hooks.json"'))

print("=== HOOKS JSON WIRED ===")
print(f"MANIFESTS={len(manifests)}")
print(f"ROOT_HOOKS_JSON={with_root_hooks}")
if not manifests:
    print("STATUS=ERROR")
    print("REASON=nothing_scanned: no *-plugin/.claude-plugin/plugin.json found")
    print("TYPE=nothing_scanned")
    print("=== END HOOKS JSON WIRED ===")
    sys.exit(1)
print(f"ISSUE_COUNT={len(issues)}")
if issues:
    kind, plugin, msg = issues[0]
    more = f" (+{len(issues) - 1} more)" if len(issues) > 1 else ""
    print("STATUS=ERROR")
    print(f"REASON={kind}: {msg}{more}")
    print("ISSUES:")
    for kind, plugin, msg in issues:
        print(f"  - SEVERITY=ERROR TYPE={kind} PLUGIN={plugin} MSG={msg}")
    print('FIX: add "hooks": "./hooks.json" to the plugin\'s .claude-plugin/plugin.json')
    print("=== END HOOKS JSON WIRED ===")
    sys.exit(1)
print("STATUS=OK")
print("=== END HOOKS JSON WIRED ===")
PY
