#!/usr/bin/env bash
# configure-antigravity.sh — configure Antigravity CLI to discover this marketplace's
# skills in place via skills.json (ADR-0022 principles: zero copying, zero drift).
#
# Non-destructive: if <target>/skills.json exists, existing user entries are preserved
# and this marketplace's plugin skill directories are merged. With --remove, this
# marketplace's entries are cleanly removed.
#
# Usage: ./scripts/configure-antigravity.sh [target] [--remove]
#   target defaults to ~/.gemini/config (global)
set -euo pipefail

config_script_dir="$(cd "$(dirname "$0")" && pwd)"
config_repo_root="$(cd "$config_script_dir/.." && pwd)"

config_target=""
config_action="add"

for arg in "$@"; do
    case "$arg" in
        --remove) config_action="remove" ;;
        -*) echo "unknown argument: $arg" >&2; exit 2 ;;
        *)
            if [ -z "$config_target" ]; then
                config_target="$arg"
            fi
            ;;
    esac
done

config_target="${config_target:-$HOME/.gemini/config}"

# Expand leading ~
if [ "${config_target#\~}" != "$config_target" ]; then
    config_target="${HOME}${config_target#\~}"
fi

skills_json="$config_target/skills.json"
mkdir -p "$config_target"

echo "=== ANTIGRAVITY CONFIGURE ==="
echo "TARGET=$config_target"
echo "ACTION=$config_action"
echo "REPO_ROOT=$config_repo_root"

# Run Python helper to cleanly inspect, merge, or remove JSON entries
python3 - "$config_repo_root" "$skills_json" "$config_action" <<'PY'
import json
import sys
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve()
skills_json_path = Path(sys.argv[2]).resolve()
action = sys.argv[3]

# Collect all plugin skill directories in this repo
marketplace_paths = []
for p in sorted(repo_root.glob("*-plugin")):
    skills_dir = p / "skills"
    if skills_dir.is_dir():
        marketplace_paths.append(str(skills_dir.resolve()))

current_data = {"entries": []}
if skills_json_path.is_file():
    try:
        current_data = json.loads(skills_json_path.read_text(encoding="utf-8"))
        if not isinstance(current_data, dict):
            current_data = {"entries": []}
    except Exception:
        current_data = {"entries": []}

existing_entries = current_data.get("entries", [])
if not isinstance(existing_entries, list):
    existing_entries = []

mp_set = set(marketplace_paths)

if action == "remove":
    # Keep only entries that are NOT part of this marketplace
    new_entries = [e for e in existing_entries if isinstance(e, dict) and e.get("path") not in mp_set]
    current_data["entries"] = new_entries
    skills_json_path.write_text(json.dumps(current_data, indent=2) + "\n", encoding="utf-8")
    print(f"REMOVED_ENTRIES={len(existing_entries) - len(new_entries)}")
    print(f"REMAINING_ENTRIES={len(new_entries)}")
else:
    # Add missing marketplace paths
    existing_paths = {e.get("path") for e in existing_entries if isinstance(e, dict)}
    added = 0
    new_entries = list(existing_entries)
    for mp_path in marketplace_paths:
        if mp_path not in existing_paths:
            new_entries.append({"path": mp_path})
            added += 1
    current_data["entries"] = new_entries
    skills_json_path.write_text(json.dumps(current_data, indent=2) + "\n", encoding="utf-8")
    print(f"ADDED_ENTRIES={added}")
    print(f"TOTAL_ENTRIES={len(new_entries)}")

PY

echo "STATUS=OK"
echo "=== END ANTIGRAVITY CONFIGURE ==="
