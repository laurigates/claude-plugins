#!/usr/bin/env bash
# set-adapter-plugins.sh — scope the ADR-0022 skill-discovery adapter to named
# marketplace plugins, or unscope it, by editing one key of its config.
#
#   pi        <config> is skill-discovery.json (default global location
#             ~/.pi/agent/skill-discovery.json). Names set its "plugins" key;
#             no names delete the key. The file is created when names are
#             given and it is absent; with no names an absent file is left
#             absent. Written mode 600.
#   opencode  <config> is opencode.json. The adapter's options object is the
#             second element of its [path, {options}] entry in the `plugin`
#             array; names set options.plugins, no names delete it. An absent
#             file, or a file with no adapter entry, is left untouched
#             (register it first: just oc-adapter-register).
#
# Every other key is preserved (jq edit, temp file + mv). A config that is not
# a JSON object is refused, since it may hold the user's own settings.
# Removing the key on an unscoped run is what makes re-running a setup recipe
# without names really unscoped.
#
# Usage: ./scripts/set-adapter-plugins.sh <pi|opencode> <config> [plugin ...]
set -euo pipefail

sap_script_dir="$(cd "$(dirname "$0")" && pwd)"
sap_repo_root="$(cd "$sap_script_dir/.." && pwd)"
# shellcheck source=/dev/null  # lib/plugin-args.sh, linted on its own
. "$sap_script_dir/lib/plugin-args.sh"

if [ "$#" -lt 2 ]; then
    echo "usage: set-adapter-plugins.sh <pi|opencode> <config> [plugin ...]" >&2
    exit 2
fi
sap_harness="$1"
sap_config="$2"
shift 2
case "$sap_harness" in
    pi | opencode) ;;
    *) echo "error: harness must be pi or opencode, got '$sap_harness'" >&2; exit 2 ;;
esac
for sap_name in "$@"; do
    require_plugin "$sap_repo_root" "$sap_name"
done

# Expand a leading ~ (justfile variables are not tilde-expanded).
if [ "${sap_config#\~}" != "$sap_config" ]; then
    sap_config="${HOME}${sap_config#\~}"
fi

sap_plugins_json="$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(length > 0))')"

echo "=== ADAPTER PLUGIN SCOPE ==="
echo "HARNESS=$sap_harness"
echo "CONFIG=$sap_config"
echo "PLUGINS=${*:-all}"

finish() {
    echo "ACTION=$1"
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
    echo "=== END ADAPTER PLUGIN SCOPE ==="
    exit 0
}

fail() {
    echo "STATUS=ERROR"
    echo "REASON=$1: $2"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=$1 MSG=$2"
    echo "=== END ADAPTER PLUGIN SCOPE ==="
    exit 1
}

if [ ! -f "$sap_config" ]; then
    if [ "$sap_harness" = "opencode" ]; then
        finish "none (no config file; run just configure-opencode)"
    fi
    if [ "$#" -eq 0 ]; then
        finish "none (no config file, nothing to unscope)"
    fi
    mkdir -p "$(dirname "$sap_config")"
    echo '{}' > "$sap_config"
fi

if ! jq -e 'type == "object"' "$sap_config" >/dev/null 2>&1; then
    fail not_an_object "$sap_config is not a JSON object; fix or move it, then re-run"
fi

if [ "$sap_harness" = "pi" ]; then
    # shellcheck disable=SC2016  # $p is a jq variable
    sap_filter='if ($p | length) > 0 then .plugins = $p else del(.plugins) end'
else
    sap_entry="$sap_repo_root/adapters/opencode/index.ts"
    if ! jq -e --arg ext "$sap_entry" \
        '[.plugin // [] | .[] | select(type == "array") | .[0]] | index($ext) != null' \
        "$sap_config" >/dev/null; then
        finish "none (adapter not registered in $sap_config; run just oc-adapter-register)"
    fi
    # Only our tuple's options change; a missing options object is created.
    # shellcheck disable=SC2016  # $p and $ext are jq variables
    sap_filter='.plugin |= map(
        if type == "array" and .[0] == $ext then
            [.[0], ((.[1] // {}) | if ($p | length) > 0 then .plugins = $p else del(.plugins) end)]
            + .[2:]
        else . end)'
fi

sap_tmp="$(mktemp "$(dirname "$sap_config")/.adapter-plugins.XXXXXX")"
jq --argjson p "$sap_plugins_json" --arg ext "${sap_entry:-}" "$sap_filter" "$sap_config" > "$sap_tmp"
if [ "$sap_harness" = "pi" ]; then
    chmod 600 "$sap_tmp"
fi
mv "$sap_tmp" "$sap_config"

if [ "$#" -gt 0 ]; then
    finish "set"
fi
finish "removed"
