#!/usr/bin/env bash
# check-antigravity.sh — verify Antigravity CLI prerequisites and configuration
# (deterministic, no model call, zero cost).
#
# Usage: ./scripts/check-antigravity.sh [target]
#   target defaults to ~/.gemini/config (global)
set -euo pipefail

check_script_dir="$(cd "$(dirname "$0")" && pwd)"
check_repo_root="$(cd "$check_script_dir/.." && pwd)"

check_target="${1:-$HOME/.gemini/config}"
if [ "${check_target#\~}" != "$check_target" ]; then
    check_target="${HOME}${check_target#\~}"
fi

echo "=== ANTIGRAVITY PREREQS ==="
if command -v agy >/dev/null 2>&1; then
    echo "AGY=$(agy --version 2>&1 | head -1)"
else
    echo "AGY=MISSING"
fi

skills_json="$check_target/skills.json"
if [ -f "$skills_json" ]; then
    skills_entries="$(python3 -c "
import json, sys
try:
    d = json.load(open('$skills_json'))
    entries = d.get('entries', [])
    repo_entries = [e for e in entries if isinstance(e, dict) and '$check_repo_root' in e.get('path', '')]
    print(len(repo_entries))
except Exception:
    print(0)
" 2>/dev/null || echo 0)"
    if [ "$skills_entries" -gt 0 ]; then
        echo "SKILLS_JSON=configured ($skills_entries marketplace entries)"
    else
        echo "SKILLS_JSON=present ($skills_json — 0 marketplace entries; run \`just configure-antigravity\`)"
    fi
else
    echo "SKILLS_JSON=MISSING ($skills_json — run \`just configure-antigravity\`)"
fi

agents_dir="$check_target/agents"
if [ -d "$agents_dir" ]; then
    agent_count="$(find "$agents_dir" -name 'agent.md' 2>/dev/null | wc -l | tr -d ' ')"
    echo "AGENTS=$agent_count installed (target: $agents_dir)"
else
    echo "AGENTS=MISSING (run \`just install-antigravity-agents\`)"
fi

hooks_json="$check_target/hooks.json"
runner_py="$check_target/run-agy-hook.py"
if [ -f "$hooks_json" ] && [ -f "$runner_py" ]; then
    hook_scripts="$(find "$check_target/hook-scripts" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')"
    echo "HOOKS=present ($hook_scripts safety hook scripts in $check_target/hook-scripts)"
else
    echo "HOOKS=MISSING (run \`just install-antigravity-hooks\`)"
fi

echo "=== END ANTIGRAVITY PREREQS ==="
