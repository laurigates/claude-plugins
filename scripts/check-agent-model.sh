#!/usr/bin/env bash
# Verify every plugin agent .md file declares `model: opus`.
#
# Background: a subagent's output feeds back into the main loop as a tool
# result, so a weaker delegate quietly degrades everything downstream. Opus 4.8
# at *low* effort beats Sonnet 4.6 at *high* effort on both quality and token
# efficiency, so `effort` (a session setting), not `model`, is the cost lever
# for delegated work. This matches the user-global standard in
# `~/.claude/rules/agent-and-tool-selection.md` ("Always Use Opus for
# Subagents") and the project rule `.claude/rules/agent-development.md`
# (§ "Model Selection for Agents").
#
# The sole sanctioned non-Opus subagent is the `agent-patterns-plugin`
# cold-read-gate haiku reader — but that is a **skill-inline**
# `Agent(model: haiku)` dispatch, not an agent `.md` file, so no agent file is
# exempt today. The AGENT_MODEL_ALLOWLIST seam below exists for any future
# measurement-instrument agent file (a low-capability model used as the
# instrument, not as a delegate).
#
# Usage:
#   bash scripts/check-agent-model.sh [--project-dir <path>] [agent.md ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   agent.md ...    Explicit files to check (pre-commit style); when present,
#                   discovery is skipped and only these files are checked.
#
# Exit codes:
#   0 - all agents run on opus
#   1 - one or more agents declare a non-opus model

set -euo pipefail

# Files exempt from the opus requirement. Empty by design: the only sanctioned
# non-Opus subagent (the cold-read-gate haiku reader) is a skill-inline dispatch,
# not an agent file. Add a path here only for a genuine measurement-instrument
# agent whose entire job is to report what confuses a low-capability reader.
# Test seam: CHECK_AGENT_MODEL_ALLOWLIST (whitespace-separated) extends it so the
# regression test can exercise the honoring path without a real exemption.
AGENT_MODEL_ALLOWLIST=()
# shellcheck disable=SC2206  # intentional word-split of the test-seam env var
AGENT_MODEL_ALLOWLIST+=(${CHECK_AGENT_MODEL_ALLOWLIST:-})

proj_dir=""
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Collect agent files. Explicit args win (pre-commit passes changed files);
# otherwise discover every `*-plugin/agents/*.md` under proj_dir (excluding
# .claude-plugin). The second-stage find prunes `.claude/worktrees/*` — agent
# worktree copies are full repo checkouts created by concurrently-running
# isolated agents, so descending into them would re-scan and mis-report sibling
# agents' checkouts (#1492 class).
agent_files=()
if [ ${#explicit_files[@]} -gt 0 ]; then
  agent_files=("${explicit_files[@]}")
else
  while IFS= read -r -d '' agent_file; do
    agent_files+=("$agent_file")
  done < <(
    find "$proj_dir" -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 \
      | xargs -0 -I {} find {} -path '*/.claude/worktrees/*' -prune -o \
          -path '*/agents/*.md' -type f -print0
  )
fi

if [ ${#agent_files[@]} -eq 0 ]; then
  echo "No agent files found"
  exit 0
fi

# is_allowlisted <file> — true if the file matches an AGENT_MODEL_ALLOWLIST entry
# (compared by trailing path so callers can pass relative or absolute forms).
is_allowlisted() {
  local candidate="${1#./}"
  local entry
  for entry in ${AGENT_MODEL_ALLOWLIST[@]+"${AGENT_MODEL_ALLOWLIST[@]}"}; do
    entry="${entry#./}"
    [ -z "$entry" ] && continue
    case "$candidate" in
      "$entry" | */"$entry") return 0 ;;
    esac
  done
  return 1
}

errors=0
checked=0

for agent_file in "${agent_files[@]}"; do
  [ -f "$agent_file" ] || continue
  checked=$((checked + 1))

  if is_allowlisted "$agent_file"; then
    continue
  fi

  agent_model=$(head -20 "$agent_file" | grep -m1 '^model:' | sed 's/^model:[[:space:]]*//' | tr -d '\r' || true)

  if [ "$agent_model" != "opus" ]; then
    echo "❌ $agent_file: model: ${agent_model:-<missing>} (must be opus; effort is the cost lever — see .claude/rules/agent-development.md)" >&2
    errors=$((errors + 1))
  fi
done

if [ $errors -gt 0 ]; then
  echo "" >&2
  echo "Found $errors agent file(s) not on opus (out of $checked checked)." >&2
  echo "Set 'model: opus' on every plugin agent. A subagent's output re-enters the" >&2
  echo "main loop as a tool result, so a weaker delegate degrades everything" >&2
  echo "downstream. Dial 'effort' down for mechanical agents instead of the model." >&2
  echo "See .claude/rules/agent-development.md § 'Model Selection for Agents'." >&2
  exit 1
fi

echo "All $checked agent files run on opus. ✅"
exit 0
