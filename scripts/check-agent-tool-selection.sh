#!/usr/bin/env bash
# Verify every plugin agent .md file embeds a "## Tool Selection" section in
# its body, so the most-violated bash-vs-harness rules ride along in the
# agent's system prompt rather than relying on inherited memory.
#
# Background: agent threads do not reliably load `~/.claude/rules/*.md`, so
# rules like "use Glob, not find" produced 200+ weekly hook reminders even
# though the same guidance lived in the user's rule files. The fix is to
# bake the rules into each agent's system prompt — see issue #1109.
#
# What counts as compliant:
#   - The agent file contains a literal `## Tool Selection` heading.
#   - The section mentions both `Glob` and `Grep` (a coarse content sniff
#     that catches the "section exists but is empty / placeholder-only"
#     failure mode).
#
# Regression: agents-plugin/agents/*.md, testing-plugin/agents/test-runner.md,
# friction-learner.md, and the rest had no Tool Selection section, so each
# spawned thread re-discovered the bash hook blocks (issue #1109).
#
# Usage:
#   bash scripts/check-agent-tool-selection.sh             # all agents
#   bash scripts/check-agent-tool-selection.sh path/to/agent.md ...
#
# Exit codes:
#   0 - all agents compliant
#   1 - one or more agents missing the section

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# Collect agent files. If args were passed, use those; otherwise discover
# every `*-plugin/agents/*.md` (excluding .claude-plugin and node_modules).
agent_files=()
if [ $# -gt 0 ]; then
  for arg in "$@"; do
    agent_files+=("$arg")
  done
else
  while IFS= read -r -d '' agent_file; do
    agent_files+=("$agent_file")
  done < <(
    find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 \
      | xargs -0 -I {} find {} -path '*/agents/*.md' -type f -print0
  )
fi

if [ ${#agent_files[@]} -eq 0 ]; then
  echo "No agent files found"
  exit 0
fi

errors=0
checked=0

for agent_file in "${agent_files[@]}"; do
  [ -f "$agent_file" ] || continue
  checked=$((checked + 1))

  if ! grep -qE '^## Tool Selection$' "$agent_file"; then
    echo "❌ $agent_file: missing '## Tool Selection' section" >&2
    errors=$((errors + 1))
    continue
  fi

  # Coarse content sniff — make sure the section names both alternatives the
  # canonical block calls out, not just a placeholder heading.
  if ! grep -q 'Glob' "$agent_file" || ! grep -q 'Grep' "$agent_file"; then
    echo "❌ $agent_file: '## Tool Selection' section does not mention Glob and Grep" >&2
    errors=$((errors + 1))
    continue
  fi
done

if [ $errors -gt 0 ]; then
  echo "" >&2
  echo "Found $errors agent file(s) missing or with stub Tool Selection section (out of $checked checked)." >&2
  echo "Each plugin agent must embed the Tool Selection block — see issue #1109." >&2
  exit 1
fi

echo "All $checked agent files have a Tool Selection section. ✅"
exit 0
