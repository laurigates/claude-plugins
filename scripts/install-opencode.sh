#!/usr/bin/env bash
# install-opencode.sh — export this marketplace's skills + subagents to OpenCode
# format and install them additively into an OpenCode config directory.
#
# Runs export-opencode.sh into a disposable temp dir, then copies agents/ and
# skills/ into <target>/{agents,skills}. The copy is ADDITIVE: the user's own
# agents/skills under <target> are preserved (no rm -rf of the target trees).
#
# Usage: ./scripts/install-opencode.sh <target>
set -euo pipefail

install_script_dir="$(cd "$(dirname "$0")" && pwd)"
install_target="${1:?usage: install-opencode.sh <target>}"

# Expand a leading ~ to $HOME (justfile variables are not tilde-expanded).
if [ "${install_target#\~}" != "$install_target" ]; then
    install_target="${HOME}${install_target#\~}"
fi

echo "=== OPENCODE INSTALL ==="
echo "TARGET=$install_target"

# Cross-scope duplicate guard. OpenCode MERGES global (~/.config/opencode) and
# project (<cwd>/.opencode) skills, so installing this marketplace into BOTH
# scopes loads every skill twice -> "Duplicate tool names detected" at launch.
# A receipt file marks each scope we install into; if the COMPLEMENTARY scope
# already carries one, warn loudly (do not block — re-installing one scope is fine).
install_receipt=".claude-plugins-opencode-receipt"
install_global_dir="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
if [ "${install_global_dir#\~}" != "$install_global_dir" ]; then
    install_global_dir="${HOME}${install_global_dir#\~}"
fi
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
    echo "WARNING=this marketplace is already installed in the complementary scope; OpenCode merges global + project skills, so launching there will report duplicate tool names"
    echo "FIX=install into ONE scope only — remove the other with: rm -f \"$install_other/$install_receipt\" && rm -rf \"$install_other/skills\" \"$install_other/agents\""
fi

install_tmp="$(mktemp -d)"
trap 'rm -rf "$install_tmp"' EXIT

"$install_script_dir/export-opencode.sh" "$install_tmp" >/dev/null

mkdir -p "$install_target/agents" "$install_target/skills"
cp -R "$install_tmp/agents/." "$install_target/agents/"
cp -R "$install_tmp/skills/." "$install_target/skills/"

install_agents="$(find "$install_target/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
install_skills="$(find "$install_target/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')"

# Drop a receipt so a later install into the complementary scope can detect us.
printf 'installed_at_count=%s\nskills=%s\nagents=%s\n' \
    "$install_target" "$install_skills" "$install_agents" > "$install_target/$install_receipt"

echo "INSTALLED_AGENTS=$install_agents"
echo "INSTALLED_SKILLS=$install_skills"
echo "RECEIPT=$install_target/$install_receipt"
if [ "$install_dup_warned" -eq 1 ]; then
    echo "STATUS=WARN"
    echo "ISSUE_COUNT=1"
else
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
fi
echo "=== END OPENCODE INSTALL ==="
