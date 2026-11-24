#!/usr/bin/env bash
# install-antigravity.sh — export this marketplace's subagents and lifecycle
# hooks into Antigravity CLI format and install them additively into an
# Antigravity config directory.
#
# Runs export-antigravity.sh into a disposable temp dir, then copies agents/
# and hooks into <target>. The installation is ADDITIVE: the user's own
# agents and hooks under <target> are preserved.
#
# SKILLS ARE NOT INSTALLED VIA COPYING. They reach Antigravity CLI in place
# via configure-antigravity.sh, which registers skills.json.
#
# Usage: ./scripts/install-antigravity.sh [target] [--agents-only] [--hooks-only] [--plugin NAME ...]
#   target defaults to ~/.gemini/config (global)
#   Each --plugin limits the install to that plugin's subagents. The safety
#   hooks belong to hooks-plugin, so a --plugin list without it installs no hooks.
set -euo pipefail

install_script_dir="$(cd "$(dirname "$0")" && pwd)"
install_repo_root="$(cd "$install_script_dir/.." && pwd)"
# shellcheck source=/dev/null  # lib/antigravity-plugins.sh, linted on its own
. "$install_script_dir/lib/antigravity-plugins.sh"

install_target=""
install_agents=1
install_hooks=1
install_plugin_args=()
install_plugins=()
install_has_hooks_plugin=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --agents-only) install_hooks=0; shift ;;
        --hooks-only)  install_agents=0; shift ;;
        --plugin)
            [ "$#" -ge 2 ] || { echo "--plugin needs a plugin name" >&2; exit 2; }
            agy_require_plugin "$install_repo_root" "$2"
            install_plugin_args+=(--plugin "$2")
            install_plugins+=("$2")
            [ "$2" = "hooks-plugin" ] && install_has_hooks_plugin=1
            shift 2
            ;;
        -*) echo "unknown argument: $1" >&2; exit 2 ;;
        *)
            [ -z "$install_target" ] && install_target="$1"
            shift
            ;;
    esac
done

if [ "$install_agents" -eq 0 ] && [ "$install_hooks" -eq 0 ]; then
    echo "--agents-only and --hooks-only are mutually exclusive" >&2
    exit 2
fi

if [ "${#install_plugin_args[@]}" -gt 0 ] && [ "$install_has_hooks_plugin" -eq 0 ]; then
    if [ "$install_agents" -eq 0 ]; then
        echo "--hooks-only with a --plugin list that omits hooks-plugin installs nothing" >&2
        exit 2
    fi
    install_hooks=0
fi

install_target="${install_target:-$HOME/.gemini/config}"

# Expand leading ~
if [ "${install_target#\~}" != "$install_target" ]; then
    install_target="${HOME}${install_target#\~}"
fi

echo "=== ANTIGRAVITY INSTALL ==="
echo "TARGET=$install_target"
echo "INSTALL_AGENTS=$install_agents"
echo "INSTALL_HOOKS=$install_hooks"
echo "PLUGINS=${install_plugins[*]:-all}"

install_tmp="$(mktemp -d)"
trap 'rm -rf "$install_tmp"' EXIT

# export-antigravity.sh exits 0 on STATUS=WARN, so read its STATUS line: a
# skipped agent or a failed hook generation must not install as success.
install_export_out="$("$install_script_dir/export-antigravity.sh" "$install_tmp" ${install_plugin_args[@]+"${install_plugin_args[@]}"} 2>&1)" || true
if ! grep -qx 'STATUS=OK' <<<"$install_export_out"; then
    printf '%s\n' "$install_export_out" >&2
    echo "STATUS=ERROR"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=export_failed MSG=export-antigravity.sh did not report STATUS=OK (output above); nothing installed"
    echo "=== END ANTIGRAVITY INSTALL ==="
    exit 1
fi

installed_agents_count=0
installed_hooks_count=0

if [ "$install_agents" -eq 1 ] && [ -d "$install_tmp/agents" ]; then
    mkdir -p "$install_target/agents"
    for agent_dir in "$install_tmp"/agents/*; do
        if [ -d "$agent_dir" ]; then
            name="$(basename "$agent_dir")"
            mkdir -p "$install_target/agents/$name"
            cp -R "$agent_dir/." "$install_target/agents/$name/"
            installed_agents_count=$((installed_agents_count + 1))
        fi
    done
fi

if [ "$install_hooks" -eq 1 ] && [ -f "$install_tmp/hooks.json" ]; then
    mkdir -p "$install_target"

    # Merge our hook entry into hooks.json. Only the `claude-safety-hooks` key
    # is ours; every other key is preserved as-is. A file that does not parse,
    # or is not a JSON object, is left untouched and the install stops: it may
    # hold the user's own hooks. The runner path is rewritten from the export's
    # temp dir to the install target.
    python3 - "$install_target/hooks.json" "$install_tmp/hooks.json" "$install_target/run-agy-hook.py" <<'PY'
import json
import shlex
import sys
from pathlib import Path

target_path = Path(sys.argv[1])
src_path = Path(sys.argv[2])
runner = str(Path(sys.argv[3]).resolve())
KEY = "claude-safety-hooks"

target_data = {}
if target_path.is_file():
    try:
        target_data = json.loads(target_path.read_text(encoding="utf-8"))
    except ValueError as exc:
        sys.exit(f"error: {target_path} is not valid JSON ({exc}); fix or move it, then re-run")
    if not isinstance(target_data, dict):
        sys.exit(f"error: {target_path} is not a JSON object; fix or move it, then re-run")

ours = json.loads(src_path.read_text(encoding="utf-8"))[KEY]
for groups in ours.values():
    for group in groups:
        for hook in group.get("hooks", []):
            hook["command"] = f"python3 -u {shlex.quote(runner)} pre-tool-use"

target_data[KEY] = ours
target_path.write_text(json.dumps(target_data, indent=2) + "\n", encoding="utf-8")
PY

    # Copy hook runner scripts and referenced script directories
    cp "$install_tmp/run-agy-hook.py" "$install_target/run-agy-hook.py"
    cp "$install_tmp/run-agy-hook.sh" "$install_target/run-agy-hook.sh"
    cp "$install_tmp/hooks_manifest.json" "$install_target/hooks_manifest.json"

    if [ -d "$install_tmp/hook-scripts" ]; then
        mkdir -p "$install_target/hook-scripts"
        cp -R "$install_tmp/hook-scripts/." "$install_target/hook-scripts/"
    fi

    installed_hooks_count="$(find "$install_target/hook-scripts" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')"
fi

receipt="$install_target/.claude-plugins-antigravity-receipt"
printf 'installed_at=%s\nagents=%s\nhook_scripts=%s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$installed_agents_count" "$installed_hooks_count" > "$receipt"

echo "INSTALLED_AGENTS=$installed_agents_count"
echo "INSTALLED_HOOK_SCRIPTS=$installed_hooks_count"
echo "RECEIPT=$receipt"
echo "STATUS=OK"
echo "=== END ANTIGRAVITY INSTALL ==="
