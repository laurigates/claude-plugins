#!/usr/bin/env bash
# Regression test for evaluate-plugin's plugin-native workflow registration
# (#3684, replacing the #2829 SessionStart copy hook).
#
# evaluate-plugin-batch calls workflow('evaluate-plugin:evaluate-skill', ...).
# That name resolves only when all of these hold, and a mismatch throws at run
# time with no CI signal:
#   1. evaluate-plugin/.claude-plugin/plugin.json `workflows` lists the
#      evaluate-skill template, and the listed file exists.
#   2. The template's meta.name is `evaluate-skill`.
#   3. The batch caller's EVALUATE_SKILL_WORKFLOW literal equals
#      `<plugin name>:<meta.name>`.
#   4. The retired copy hook is gone from the manifest and from disk, so a
#      bare `evaluate-skill` is not re-registered in ~/.claude/workflows/.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
plugin_dir="$root/evaluate-plugin"
manifest="$plugin_dir/.claude-plugin/plugin.json"
batch_wf="$plugin_dir/skills/evaluate-plugin-batch/workflows/evaluate-plugin-batch.workflow.js"
expected_rel="./skills/evaluate-skill/workflows/evaluate-skill.workflow.js"

command -v jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

pass=0
fail=0
ok() { echo "PASS $1"; pass=$((pass + 1)); }
ko() { echo "FAIL $1"; fail=$((fail + 1)); }

plugin_name="$(jq -r '.name' "$manifest")"

# 1. workflows field lists the template, and the file exists.
if jq -e --arg p "$expected_rel" '(.workflows | type) == "array" and (.workflows | index($p) != null)' "$manifest" >/dev/null; then
  ok "plugin.json workflows lists $expected_rel"
else
  ko "plugin.json workflows does not list $expected_rel"
fi
listed_count="$(jq -r '.workflows // [] | length' "$manifest")"
if [[ "$listed_count" == "1" ]]; then
  ok "plugin.json registers exactly one workflow"
else
  ko "plugin.json registers $listed_count workflows; docs/dynamic-workflow-registration.md allows one"
fi
child_wf="$plugin_dir/${expected_rel#./}"
if [[ -f "$child_wf" ]]; then
  ok "registered template exists"
else
  ko "registered template missing: $child_wf"
fi

# 2. meta.name of the registered template.
meta_name="$(grep -m1 -oE "^[[:space:]]*name:[[:space:]]*'[^']+'" "$child_wf" 2>/dev/null | sed -E "s/.*'([^']+)'.*/\1/" || true)"
if [[ "$meta_name" == "evaluate-skill" ]]; then
  ok "template meta.name is evaluate-skill"
else
  ko "template meta.name is '${meta_name}', expected evaluate-skill"
fi

# 3. The caller's literal equals <plugin>:<meta.name>.
caller_name="$(grep -m1 -oE "^const EVALUATE_SKILL_WORKFLOW = '[^']+'" "$batch_wf" | sed -E "s/.*'([^']+)'/\1/" || true)"
if [[ -n "$meta_name" && "$caller_name" == "${plugin_name}:${meta_name}" ]]; then
  ok "batch caller resolves ${plugin_name}:${meta_name}"
else
  ko "batch caller calls '${caller_name}', expected '${plugin_name}:${meta_name}'"
fi

# 4. The copy hook is retired.
if jq -e '[.. | objects | .command? // empty | select(contains("sync-evaluate-skill-workflow"))] | length == 0' "$manifest" >/dev/null; then
  ok "manifest no longer runs the copy hook"
else
  ko "manifest still runs sync-evaluate-skill-workflow.sh"
fi
if [[ ! -e "$plugin_dir/hooks/sync-evaluate-skill-workflow.sh" ]]; then
  ok "copy hook script removed"
else
  ko "copy hook script still present"
fi

echo "RESULT pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
