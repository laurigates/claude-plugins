#!/usr/bin/env bash
# install-opencode.sh — export this marketplace's subagents + hooks to OpenCode
# format and install them additively into an OpenCode config directory.
#
# Runs export-opencode.sh into a disposable temp dir, then copies agents/,
# plugins/ (generated hook plugins), and hook-scripts/ into <target>. The copy
# is ADDITIVE: the user's own agents/plugins under <target> are preserved
# (no rm -rf of the target trees).
#
# SKILLS ARE NOT INSTALLED (#2094). They reach OpenCode through the adapter,
# which configure-opencode.sh wires into opencode.json — see
# adapters/opencode/ and docs/opencode-export.md.
#
# Usage: ./scripts/install-opencode.sh <target> [--plugin NAME ...]
#   Each --plugin limits the install to that plugin's subagents and hook
#   plugins; when the selected plugins ship no hooks, none are installed.
set -euo pipefail

install_script_dir="$(cd "$(dirname "$0")" && pwd)"
install_repo_root="$(cd "$install_script_dir/.." && pwd)"
# shellcheck source=/dev/null  # lib/plugin-args.sh, linted on its own
. "$install_script_dir/lib/plugin-args.sh"

install_target=""
install_plugin_args=()
install_plugins=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --plugin)
            [ "$#" -ge 2 ] || { echo "--plugin needs a plugin name" >&2; exit 2; }
            require_plugin "$install_repo_root" "$2"
            install_plugin_args+=(--plugin "$2")
            install_plugins+=("$2")
            shift 2
            ;;
        -*) echo "unknown argument: $1" >&2; exit 2 ;;
        *)
            [ -z "$install_target" ] && install_target="$1"
            shift
            ;;
    esac
done
[ -n "$install_target" ] || { echo "usage: install-opencode.sh <target> [--plugin NAME ...]" >&2; exit 2; }

# Expand a leading ~ to $HOME (justfile variables are not tilde-expanded).
if [ "${install_target#\~}" != "$install_target" ]; then
    install_target="${HOME}${install_target#\~}"
fi

echo "=== OPENCODE INSTALL ==="
echo "TARGET=$install_target"
echo "PLUGINS=${install_plugins[*]:-all}"

# Cross-scope duplicate guard. OpenCode MERGES global (~/.config/opencode) and
# project (<cwd>/.opencode) agents and plugins, so installing this marketplace
# into BOTH scopes loads every agent twice and registers each hook plugin twice.
# A receipt file marks each scope we install into; if the COMPLEMENTARY scope
# already carries one, warn loudly (do not block — re-installing one scope is fine).
install_receipt=".claude-plugins-opencode-receipt"
install_global_dir="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
if [ "${install_global_dir#\~}" != "$install_global_dir" ]; then
    install_global_dir="${HOME}${install_global_dir#\~}"
fi
# OPENCODE_CONFIG is also the recipes' install target, so for a project install
# (OPENCODE_CONFIG=.opencode just setup-opencode) it names the project scope,
# not the global one; fall back to the global default then.
case "$install_global_dir" in
    *.opencode|*.opencode/) install_global_dir="$HOME/.config/opencode" ;;
esac
install_project_dir="$PWD/.opencode"

case "$install_target" in
    "$install_global_dir"|"$install_global_dir"/) install_other="$install_project_dir" ;;
    *.opencode|*.opencode/) install_other="$install_global_dir" ;;
    *) install_other="" ;;
esac

install_dup_warned=0
if [ -n "$install_other" ] && [ -f "$install_other/$install_receipt" ]; then
    install_dup_warned=1
    echo "DUPLICATE_SCOPE_DETECTED=$install_other"
    echo "WARNING=this marketplace is already installed in the complementary scope; OpenCode merges global + project agents and plugins, so launching there loads each one twice"
    echo "FIX=install into ONE scope only — remove the other with: rm -f \"$install_other/$install_receipt\" && rm -rf \"$install_other/agents\" \"$install_other/hook-scripts\" && rm -f \"$install_other\"/plugins/*-plugin-hooks.js"
fi

install_tmp="$(mktemp -d)"
trap 'rm -rf "$install_tmp"' EXIT

"$install_script_dir/export-opencode.sh" "$install_tmp" ${install_plugin_args[@]+"${install_plugin_args[@]}"} >/dev/null

mkdir -p "$install_target/agents"
cp -R "$install_tmp/agents/." "$install_target/agents/"

# Generated hook plugins (plugins/<plugin>-hooks.js) resolve their scripts via
# ../hook-scripts/<plugin>/, so the two trees must travel together.
if [ -d "$install_tmp/plugins" ]; then
    mkdir -p "$install_target/plugins" "$install_target/hook-scripts"
    cp -R "$install_tmp/plugins/." "$install_target/plugins/"
    cp -R "$install_tmp/hook-scripts/." "$install_target/hook-scripts/"
fi

install_agents="$(find "$install_target/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
# plugins/ is absent when no hook plugin was ever installed here; find's exit 1
# would abort the script under pipefail.
install_hook_plugins="$( { find "$install_target/plugins" -name '*-plugin-hooks.js' 2>/dev/null || true; } | wc -l | tr -d ' ')"

# Drop a receipt so a later install into the complementary scope can detect us.
printf 'installed_at=%s\nagents=%s\n' \
    "$install_target" "$install_agents" > "$install_target/$install_receipt"

echo "INSTALLED_AGENTS=$install_agents"
echo "INSTALLED_SKILLS=0 (adapter — see adapters/opencode/)"
echo "INSTALLED_HOOK_PLUGINS=$install_hook_plugins"
echo "RECEIPT=$install_target/$install_receipt"
if [ "$install_dup_warned" -eq 1 ]; then
    echo "STATUS=WARN"
    echo "ISSUE_COUNT=1"
else
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
fi
echo "=== END OPENCODE INSTALL ==="
