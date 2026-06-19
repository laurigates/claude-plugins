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

install_tmp="$(mktemp -d)"
trap 'rm -rf "$install_tmp"' EXIT

"$install_script_dir/export-opencode.sh" "$install_tmp" >/dev/null

mkdir -p "$install_target/agents" "$install_target/skills"
cp -R "$install_tmp/agents/." "$install_target/agents/"
cp -R "$install_tmp/skills/." "$install_target/skills/"

install_agents="$(find "$install_target/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
install_skills="$(find "$install_target/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')"
echo "INSTALLED_AGENTS=$install_agents"
echo "INSTALLED_SKILLS=$install_skills"
echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END OPENCODE INSTALL ==="
