#!/usr/bin/env bash
# configure-antigravity.sh — configure Antigravity CLI to discover this marketplace's
# skills in place via skills.json (ADR-0022 principles: zero copying, zero drift).
#
# Non-destructive: if <target>/skills.json exists, existing user entries are preserved
# and this marketplace's plugin skill directories are merged. With --remove, this
# marketplace's entries are cleanly removed.
#
# Usage: ./scripts/configure-antigravity.sh [target] [--remove] [--plugin NAME ...]
#   target defaults to ~/.gemini/config (global)
#   Each --plugin limits the add (or --remove) to that plugin's skills dir;
#   none means every plugin.
set -euo pipefail

config_script_dir="$(cd "$(dirname "$0")" && pwd)"
config_repo_root="$(cd "$config_script_dir/.." && pwd)"
# shellcheck source=/dev/null  # lib/antigravity-plugins.sh, linted on its own
. "$config_script_dir/lib/antigravity-plugins.sh"

config_target=""
config_action="add"
config_plugins=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --remove) config_action="remove"; shift ;;
        --plugin)
            [ "$#" -ge 2 ] || { echo "--plugin needs a plugin name" >&2; exit 2; }
            agy_require_plugin "$config_repo_root" "$2"
            config_plugins+=("$2")
            shift 2
            ;;
        -*) echo "unknown argument: $1" >&2; exit 2 ;;
        *)
            if [ -n "$config_target" ]; then
                echo "unexpected argument: $1 (plugin names need --plugin)" >&2
                exit 2
            fi
            config_target="$1"
            shift
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
echo "PLUGINS=${config_plugins[*]:-all}"

# Run Python helper to cleanly inspect, merge, or remove JSON entries
python3 - "$config_repo_root" "$skills_json" "$config_action" ${config_plugins[@]+"${config_plugins[@]}"} <<'PY'
import json
import sys
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve()
skills_json_path = Path(sys.argv[2]).resolve()
action = sys.argv[3]
selected = set(sys.argv[4:])

# Collect the plugin skill directories in this repo (only the selected
# plugins' when --plugin was given)
marketplace_paths = []
for p in sorted(repo_root.glob("*-plugin")):
    if selected and p.name not in selected:
        continue
    skills_dir = p / "skills"
    if skills_dir.is_dir():
        marketplace_paths.append(str(skills_dir.resolve()))

# A skills.json this script cannot read is left untouched and the run stops:
# resetting it would delete the user's own skill registrations.
current_data = {"entries": []}
if skills_json_path.is_file():
    try:
        current_data = json.loads(skills_json_path.read_text(encoding="utf-8"))
    except ValueError as exc:
        sys.exit(f"error: {skills_json_path} is not valid JSON ({exc}); fix or move it, then re-run")
    if not isinstance(current_data, dict):
        sys.exit(f"error: {skills_json_path} is not a JSON object; fix or move it, then re-run")

existing_entries = current_data.get("entries", [])
if not isinstance(existing_entries, list):
    sys.exit(f"error: {skills_json_path} has an `entries` value that is not a list; fix or move it, then re-run")

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
