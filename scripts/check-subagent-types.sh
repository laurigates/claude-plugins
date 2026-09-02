#!/usr/bin/env bash
# Verify every `subagent_type` named in a skill body resolves to an agent that
# actually exists.
#
# Background: a skill that instructs Claude to dispatch
# `Task(subagent_type: <name>)` is only useful if <name> resolves. A stale name
# fails at dispatch with "Agent type '<name>' not found" — the skill is
# advertised, loads fine, passes every structural lint, and then breaks on the
# one line that matters. `testing-plugin:test-analyze` shipped a 7-row routing
# table in which 6 values named agents that had been renamed years earlier
# (`code-review` → `review`, `system-debugging` → `debug`, `code-refactoring` →
# `refactor`, `test-architecture` → `test`, `cicd-pipelines` → `ci`,
# `documentation` → `docs`), so every dispatch it instructed failed.
#
# Resolution rules (see ~/.claude/rules/agent-and-tool-selection.md):
#   - `plugin:agent`  — the correct form for a plugin-provided agent. Resolves
#                       when `<plugin>/agents/<agent>.md` exists.
#   - `agent`         — bare form. Only valid for user/project-level agents
#                       (`~/.claude/agents/`, `.claude/agents/`). A bare name
#                       that a plugin *does* provide is reported as a WARN
#                       (works today only by luck of name resolution); a bare
#                       name nothing provides is an ERROR.
#   - built-ins       — `general-purpose`, `Explore`, `fork` (BUILTIN_SUBAGENT_TYPES).
#                       `fork` inherits the parent conversation (on by default
#                       since Claude Code 2.1.232).
#
# Usage:
#   bash scripts/check-subagent-types.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   --strict        Also exit 1 when only WARN-level findings exist.
#
# Exit codes:
#   0 - no unresolvable subagent_type (WARNs may still be reported)
#   1 - at least one unresolvable subagent_type (or a WARN under --strict)

set -uo pipefail

# Agent types the harness provides itself — never backed by an agents/*.md file.
BUILTIN_SUBAGENT_TYPES=(general-purpose Explore fork)

# Illustrative occurrences that are deliberately NOT Claude Code dispatches.
# Format: <path-suffix>|<value>. Keep this list tiny and justified — an entry
# here is a claim that the value is not meant to resolve at all.
SUBAGENT_TYPE_EXCEPTIONS=(
  # `deepagents` (npm) has its own `task({subagent_type})` tool; this is that
  # third-party API being documented, not a Claude Code agent.
  "langchain-plugin/skills/deep-agents/SKILL.md|research-agent"
  # Generic placeholder in a doc showing how to reference *your own* custom
  # agent defined under .claude/agents/ — no repo agent is intended.
  "agent-patterns-plugin/skills/custom-agent-definitions/REFERENCE.md|security-auditor"
)
# Test seam: extend the exception list without editing the script.
# shellcheck disable=SC2206  # intentional word-split of the test-seam env var
SUBAGENT_TYPE_EXCEPTIONS+=(${CHECK_SUBAGENT_TYPE_EXCEPTIONS:-})

proj_dir=""
strict=false
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    --strict) strict=true; shift ;;
    *)
      echo "check-subagent-types.sh: unknown argument: $1" >&2
      echo "Usage: check-subagent-types.sh [--project-dir <path>] [--strict]" >&2
      exit 2
      ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Scan from inside proj_dir with relative paths. An absolute base would make the
# `.claude/worktrees/` prune below fire on the whole tree whenever proj_dir is
# itself a worktree (its own path contains `.claude/worktrees/`), silently
# scanning nothing.
cd "$proj_dir" || { echo "check-subagent-types.sh: cannot cd to $proj_dir" >&2; exit 2; }

# --- Build the agent inventory ------------------------------------------------
# Every `<plugin>/agents/<name>.md` contributes both a qualified id
# (`<plugin>:<name>`) and a bare name (`<name>`). `.claude/worktrees/` copies
# are pruned — they are full repo checkouts made by concurrently-running
# isolated agents (#1492 class).
declare -A QUALIFIED_AGENTS=()
declare -A BARE_AGENTS=()

while IFS= read -r -d '' agent_file; do
  agent_plugin="$(basename "$(dirname "$(dirname "$agent_file")")")"
  agent_base="$(basename "$agent_file" .md)"
  QUALIFIED_AGENTS["${agent_plugin}:${agent_base}"]=1
  BARE_AGENTS["$agent_base"]="$agent_plugin"
done < <(
  find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 \
    | xargs -0 -I {} find {} -path '*/.claude/worktrees/*' -prune -o \
        -path '*/agents/*.md' -type f -print0
)

for builtin_type in "${BUILTIN_SUBAGENT_TYPES[@]}"; do
  QUALIFIED_AGENTS["$builtin_type"]=1
done

# is_exception <file> <value>
is_exception() {
  local candidate="${1#./}" value="$2" entry entry_path entry_value
  for entry in ${SUBAGENT_TYPE_EXCEPTIONS[@]+"${SUBAGENT_TYPE_EXCEPTIONS[@]}"}; do
    [ -z "$entry" ] && continue
    entry_path="${entry%%|*}"
    entry_value="${entry##*|}"
    [ "$entry_value" = "$value" ] || continue
    case "$candidate" in
      "$entry_path" | */"$entry_path") return 0 ;;
    esac
  done
  return 1
}

# --- Scan skill bodies --------------------------------------------------------
skill_files=()
while IFS= read -r -d '' skill_file; do
  skill_files+=("$skill_file")
done < <(
  find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 \
    | xargs -0 -I {} find {} -path '*/.claude/worktrees/*' -prune -o \
        -path '*/skills/*' -name '*.md' -type f -print0
)

errors=0
warns=0
refs=0
files_scanned=0
error_lines=()
warn_lines=()

echo "=== SUBAGENT TYPE RESOLUTION ==="
echo "AGENT_COUNT=${#QUALIFIED_AGENTS[@]}"

for skill_file in ${skill_files[@]+"${skill_files[@]}"}; do
  [ -f "$skill_file" ] || continue
  files_scanned=$((files_scanned + 1))
  rel_path="${skill_file#./}"

  # A dispatch is `subagent_type` followed by `:` or `=` and a value. Guards
  # against prose mentions (`subagent_type`/`subagent_prompt`), jq field reads
  # (`.subagent_type // empty`), and the uppercase shell var (SUBAGENT_TYPE=).
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    value="${match#*subagent_type}"
    value="${value#\"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value#:}"
    value="${value#=}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value#\"}"
    [ -n "$value" ] || continue
    refs=$((refs + 1))

    if is_exception "$rel_path" "$value"; then
      continue
    fi

    if [ -n "${QUALIFIED_AGENTS[$value]:-}" ]; then
      continue
    fi

    if [ -n "${BARE_AGENTS[$value]:-}" ]; then
      warns=$((warns + 1))
      warn_lines+=("  - SEVERITY=WARN TYPE=unqualified_subagent_type FILE=$rel_path VALUE=$value FIX=${BARE_AGENTS[$value]}:$value")
      continue
    fi

    errors=$((errors + 1))
    error_lines+=("  - SEVERITY=ERROR TYPE=unresolvable_subagent_type FILE=$rel_path VALUE=$value MSG=no agents/${value}.md in any plugin")
  done < <(grep -oE 'subagent_type"?[[:space:]]*[:=][[:space:]]*"?[A-Za-z][A-Za-z0-9_:.-]*' "$skill_file" 2>/dev/null || true)
done

echo "FILES_SCANNED=$files_scanned"
echo "REFS_CHECKED=$refs"
echo "UNRESOLVABLE=$errors"
echo "UNQUALIFIED=$warns"

if [ $errors -gt 0 ]; then
  echo "STATUS=ERROR"
elif [ $warns -gt 0 ]; then
  echo "STATUS=WARN"
else
  echo "STATUS=OK"
fi
echo "ISSUE_COUNT=$((errors + warns))"

if [ $((errors + warns)) -gt 0 ]; then
  echo "ISSUES:"
  for line in ${error_lines[@]+"${error_lines[@]}"}; do echo "$line"; done
  for line in ${warn_lines[@]+"${warn_lines[@]}"}; do echo "$line"; done
fi
echo "=== END SUBAGENT TYPE RESOLUTION ==="

if [ $errors -gt 0 ]; then
  echo "" >&2
  echo "Found $errors unresolvable subagent_type value(s) in skill bodies." >&2
  echo "Every dispatch a skill instructs must name an agent that exists — use the" >&2
  echo "plugin-qualified 'plugin:agent' form (e.g. agents-plugin:review). A stale" >&2
  echo "name fails at dispatch with \"Agent type not found\" and no lint sees it." >&2
  echo "See ~/.claude/rules/agent-and-tool-selection.md." >&2
  exit 1
fi

if [ "$strict" = true ] && [ $warns -gt 0 ]; then
  echo "" >&2
  echo "Found $warns unqualified subagent_type value(s) (--strict)." >&2
  exit 1
fi

exit 0
