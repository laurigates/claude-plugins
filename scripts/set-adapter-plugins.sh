#!/usr/bin/env bash
# set-adapter-plugins.sh — scope the ADR-0022 skill-discovery adapter to named
# marketplace plugins, or unscope it, by editing one key of its config.
#
#   pi        <config> is skill-discovery.json (default global location
#             ~/.pi/agent/skill-discovery.json). Names set its "plugins" key;
#             no names delete the key. The file is created (mode 600) when
#             names are given and it is absent; with no names an absent file
#             is left absent.
#   opencode  <config> is opencode.json. The adapter is registered in the
#             `plugin` array either as a [path, {options}] tuple or as the bare
#             path string. Names set options.plugins, turning a bare string
#             into a tuple; no names delete the key (a bare string has none).
#             Names with no adapter entry, or no file, are an error, since
#             the adapter would otherwise index every plugin while setup
#             reported success. With no names either is a no-op.
#
# Every other key is preserved. The edit is a jq filter written to a temp file
# beside the real file (a symlinked config is resolved first, so the link
# stays a link) and renamed over it, keeping the file's mode. A config that is
# not a JSON object, or an adapter entry whose options are not an object, is
# refused with STATUS=ERROR and left as it was. Removing the key on an
# unscoped run is what makes re-running a setup recipe without names really
# unscoped.
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
sap_entry="$sap_repo_root/adapters/opencode/index.ts"

echo "=== ADAPTER PLUGIN SCOPE ==="
echo "HARNESS=$sap_harness"
echo "CONFIG=$sap_config"
echo "PLUGINS=${*:-all}"

sap_tmp=""
trap 'rm -f -- "${sap_tmp:-}"' EXIT

finish() {
    echo "ACTION=$1"
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
    echo "=== END ADAPTER PLUGIN SCOPE ==="
    exit 0
}

# fail <type> <message>: REASON= is one line of at most 200 characters.
fail() {
    local sap_msg="${2//$'\n'/ }"
    echo "STATUS=ERROR"
    echo "REASON=$(printf '%s: %s' "$1" "$sap_msg" | cut -c1-200)"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=$1 MSG=$sap_msg"
    echo "=== END ADAPTER PLUGIN SCOPE ==="
    exit 1
}

# Write through a symlink: edit the file it points at, so the link survives.
# python3 because BSD and GNU readlink/realpath differ.
sap_real="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$sap_config")"
[ "$sap_real" != "$sap_config" ] && echo "CONFIG_RESOLVED=$sap_real"

sap_input="$sap_real"
sap_mode=""
if [ -f "$sap_real" ]; then
    sap_mode="$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o7777)[2:])' "$sap_real")"
elif [ "$sap_harness" = "opencode" ]; then
    [ "$#" -eq 0 ] && finish "none (no config file, nothing to unscope)"
    fail no_config "$sap_config does not exist; run just configure-opencode, then re-run"
elif [ "$#" -eq 0 ]; then
    finish "none (no config file, nothing to unscope)"
else
    sap_input=""    # new pi file: start from {}
    sap_mode="600"
fi

if [ -n "$sap_input" ] && ! jq -e 'type == "object"' "$sap_input" >/dev/null 2>&1; then
    fail not_an_object "$sap_config is not a JSON object; fix or move it, then re-run"
fi

if [ "$sap_harness" = "pi" ]; then
    # shellcheck disable=SC2016  # $p is a jq variable
    sap_filter='if ($p | length) > 0 then .plugins = $p else del(.plugins) end'
else
    # shellcheck disable=SC2016  # $ext is a jq variable
    if ! jq -e --arg ext "$sap_entry" \
        '[.plugin // [] | .[] | if type == "array" then .[0] else . end] | index($ext) != null' \
        "$sap_input" >/dev/null 2>&1; then
        [ "$#" -eq 0 ] && finish "none (adapter not registered in $sap_config, nothing to unscope)"
        fail adapter_not_registered "no skill-discovery adapter entry in $sap_config; run just oc-adapter-register, then re-run"
    fi
    # Only our entry changes. A tuple's options gain or lose "plugins"; a bare
    # path string becomes [path, {plugins}] when names are given and is left
    # alone otherwise (it has no options to unset).
    # shellcheck disable=SC2016  # $p and $ext are jq variables
    sap_filter='def scope: if ($p | length) > 0 then .plugins = $p else del(.plugins) end;
        .plugin |= map(
            if type == "array" and .[0] == $ext then
                if (.[1] // {} | type) != "object"
                then error("the adapter entry options in .plugin are not a JSON object")
                else [.[0], (.[1] // {} | scope)] + .[2:] end
            elif type == "string" and . == $ext and ($p | length) > 0 then [., ({} | scope)]
            else . end)'
fi

mkdir -p "$(dirname "$sap_real")"
sap_tmp="$(mktemp "$(dirname "$sap_real")/.adapter-plugins.XXXXXX")"
if [ -n "$sap_input" ]; then
    sap_err="$(jq --argjson p "$sap_plugins_json" --arg ext "$sap_entry" "$sap_filter" "$sap_input" 2>&1 >"$sap_tmp")" \
        || fail jq_failed "could not edit $sap_config: ${sap_err#jq: error (at *): }"
else
    sap_err="$(jq -n --argjson p "$sap_plugins_json" "{} | $sap_filter" 2>&1 >"$sap_tmp")" \
        || fail jq_failed "could not build $sap_config: $sap_err"
fi
chmod "$sap_mode" "$sap_tmp"
mv "$sap_tmp" "$sap_real"
sap_tmp=""

[ "$#" -gt 0 ] && finish "set"
finish "removed"
