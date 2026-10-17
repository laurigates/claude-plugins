#!/usr/bin/env bash
# check-hook-timeout-units.sh — every plugin hook `timeout` is in SECONDS.
#
# WHY
# Claude Code documents a hook `timeout` as "Seconds before canceling"
# (https://code.claude.com/docs/en/hooks). Plugin manifests carried values that
# read as milliseconds (5000, 15000, 60000), which is 83 minutes to 16 hours.
# Since `"onFailure": "block"` (#3077) a timeout on a safety hook blocks the
# tool call, so a budget that never fires is a hook that can hang a session
# instead (#3079).
#
# WHAT IS FLAGGED
#   ms_timeout   a hook entry whose `timeout` is a number >= 1000. No hook needs
#                a budget of 1000 s (16 min); every such value in this repo was
#                a millisecond figure written as seconds.
#
# SCOPE
# <plugin>/hooks.json, <plugin>/hooks/hooks.json and the inline `hooks` of
# <plugin>/.claude-plugin/plugin.json, for every top-level *-plugin directory.
# A scan that finds no hook JSON is STATUS=ERROR TYPE=nothing_scanned, never a
# silent OK.
#
# Usage: bash scripts/check-hook-timeout-units.sh [--project-dir DIR]
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
      sed -n '2,24p' "$0"; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT_DIR" ] || { echo "ERROR: project dir not found: $PROJECT_DIR" >&2; exit 2; }
cd "$PROJECT_DIR"

python3 - <<'PY'
import glob
import json
import sys

MAX_SECONDS = 999

files = sorted(
    set(glob.glob("*-plugin/hooks.json"))
    | set(glob.glob("*-plugin/hooks/hooks.json"))
    | set(glob.glob("*-plugin/.claude-plugin/plugin.json"))
)

issues = []
scanned = 0
timeouts = 0
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
        if not isinstance(blocks, list):
            continue
        for block in blocks:
            entries = block.get("hooks") if isinstance(block, dict) else None
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict) or "timeout" not in entry:
                    continue
                timeouts += 1
                value = entry["timeout"]
                if isinstance(value, bool) or not isinstance(value, (int, float)):
                    continue
                if value > MAX_SECONDS:
                    label = entry.get("command") or entry.get("prompt") or entry.get("type") or "?"
                    label = " ".join(str(label).split())[:80]
                    issues.append((
                        "ms_timeout",
                        f"{path} event={event} timeout={value} ({label}); hook"
                        " timeouts are seconds, divide a millisecond figure by 1000",
                    ))

if scanned == 0:
    issues.append(("nothing_scanned", "found no *-plugin hook JSON under the project dir"))

print("=== HOOK TIMEOUT UNITS ===")
print(f"FILES_SCANNED={scanned}")
print(f"TIMEOUTS_CHECKED={timeouts}")
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
print("=== END HOOK TIMEOUT UNITS ===")
sys.exit(1 if issues else 0)
PY
