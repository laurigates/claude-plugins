#!/usr/bin/env bash
# Resolve a skill's SKILL.md and emit the cold-reader dispatch prompt for the
# legibility gate (Slice 1 of weak-model skill validation).
#
# The body of evaluate-legibility/SKILL.md stays declarative: it invokes this
# script to get the haiku dispatch prompt, then hands the PROMPT block to a
# Task subagent. Keeping the prompt assembly here collapses the skill's
# permission surface to `Bash(bash *)` (see .claude/rules/agentic-permissions.md).
#
# Reuses the cold-read-gate dispatch contract by name reference — see
# agent-patterns-plugin:cold-read-gate. The reader persona and output schema
# (QUESTIONS / HESITATIONS / verdict) mirror that skill; this script targets a
# SKILL.md and an *agent* reader rather than an outward artifact and a human.
#
# Usage:
#   emit-legibility-prompt.sh --plugin-skill <plugin/skill> [--repo-root <path>]
#
# Output: structured KEY=value (see .claude/rules/structured-script-output.md)
#   === LEGIBILITY PROMPT ===
#   SKILL_PATH=<absolute path>
#   PLUGIN=<plugin>
#   SKILL=<skill>
#   STATUS=OK|ERROR
#   ISSUE_COUNT=<int>
#   === PROMPT ===
#   <the dispatch prompt text>
#   === END PROMPT ===
#   === END LEGIBILITY PROMPT ===

set -uo pipefail

plugin_skill=""
repo_root="$(pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-skill) plugin_skill="$2"; shift 2 ;;
    --repo-root) repo_root="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "=== LEGIBILITY PROMPT ==="

if [ -z "$plugin_skill" ]; then
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ERROR=--plugin-skill <plugin/skill> is required"
  echo "=== END LEGIBILITY PROMPT ==="
  exit 1
fi

# Split plugin/skill on the first slash. Accept exactly one slash.
plugin_name="${plugin_skill%%/*}"
skill_name="${plugin_skill#*/}"

if [ -z "$plugin_name" ] || [ -z "$skill_name" ] || [ "$plugin_name" = "$plugin_skill" ]; then
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ERROR=argument must be in the form <plugin>/<skill> (got: ${plugin_skill})"
  echo "=== END LEGIBILITY PROMPT ==="
  exit 1
fi

# Resolve the SKILL.md path. Accept either SKILL.md or skill.md.
skill_dir="${repo_root}/${plugin_name}/skills/${skill_name}"
skill_path=""
for candidate in "${skill_dir}/SKILL.md" "${skill_dir}/skill.md"; do
  if [ -f "$candidate" ]; then
    skill_path="$candidate"
    break
  fi
done

if [ -z "$skill_path" ]; then
  echo "PLUGIN=${plugin_name}"
  echo "SKILL=${skill_name}"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ERROR=SKILL.md not found under ${skill_dir}"
  echo "=== END LEGIBILITY PROMPT ==="
  exit 1
fi

# Absolutise the path (the cold reader gets a path, not pasted text).
case "$skill_path" in
  /*) abs_path="$skill_path" ;;
  *)  abs_path="$(cd "$(dirname "$skill_path")" && pwd)/$(basename "$skill_path")" ;;
esac

echo "SKILL_PATH=${abs_path}"
echo "PLUGIN=${plugin_name}"
echo "SKILL=${skill_name}"
echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== PROMPT ==="
cat <<PROMPT
You are an agent that just loaded this SKILL.md file with ZERO prior knowledge
of the "${plugin_name}" plugin or its repository. You have NO context beyond the
text itself. Read ONLY this file (no other files, no repository exploration, no
web):
${abs_path}

From this file ALONE, answer two questions:
  (a) Could you tell WHEN to invoke this skill?
  (b) Could you carry out its FIRST concrete action?

Produce:
1. QUESTIONS — anything that left you unable to answer (a) or (b): undefined
   terms, a first execution step that names a script/file/concept the file never
   introduces, narration where you expected an instruction, a description with no
   "Use when…" trigger. Quote the exact phrase that blocked you.
2. HESITATIONS — anything that made you unsure rather than blocked: ambiguous
   ordering, a step you could guess at but not confirm, structure that obscured
   the entry point.
3. Verdict: exactly one of \`clear\` | \`needs-revision\`.

Ignore (these are artifacts of reading a skill in isolation, not defects):
- "What is the ${plugin_name} plugin?" — its identity is in the frontmatter and
  the surrounding plugin, which a real invocation supplies.
- A referenced REFERENCE.md you were told not to open — it is loaded on demand
  by design.
- Unrecognized harness variables (\$ARGUMENTS, \${CLAUDE_SKILL_DIR},
  \${CLAUDE_PLUGIN_ROOT}, \${CLAUDE_SESSION_ID}) — the harness substitutes them.
- The full tool list not appearing in the body — it lives in \`allowed-tools\`.

Concise bullets. Your final message is the deliverable.
PROMPT
echo "=== END PROMPT ==="
echo "=== END LEGIBILITY PROMPT ==="
