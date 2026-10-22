#!/usr/bin/env bash
# Verify every plugin agent that sets `maxTurns:` carries a `## Turn Budget`
# section telling it to deliver its report before the limit.
#
# Background (issue #3152): `agents-plugin:review` has `maxTurns: 25`, and on a
# verify-against-files brief it spent every turn investigating. The harness cut
# it off mid-tool-call and the run returned NO report (5 of 6 PR reviews in one
# session). The cap is a cost choice and stays; what has to change is what the
# agent does as it nears the cap: stop investigating at about 80% of the budget
# and deliver the report in its Output Format, marking unfinished work
# "Not verified". A cap with no such instruction fails silently in a workflow or
# an unattended dispatch.
#
# This is a SEMANTIC gate (.claude/rules/regression-testing.md): an agent
# passes only when its `## Turn Budget` section
#   - exists (a `## Turn Budget` heading outside any code fence),
#   - names the agent's own limit as `maxTurns: <N>` equal to the frontmatter
#     value (so raising or lowering the cap without updating the prose fails),
#   - names the `80%` threshold, and
#   - tells the agent to deliver a report.
#
# Usage:
#   bash scripts/check-agent-turn-budget.sh [--project-dir <path>]
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#
# Exit codes:
#   0 - every agent with maxTurns carries the section
#   1 - one or more findings (STATUS=ERROR)
#   2 - usage error, or discovery misfired (plugin dirs present, zero agents)

set -uo pipefail

proj_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-agent-turn-budget.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      proj_dir="$2"; shift 2 ;;
    *)
      echo "check-agent-turn-budget.sh: unknown argument: $1" >&2
      echo "Usage: check-agent-turn-budget.sh [--project-dir <path>]" >&2
      exit 2 ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
proj_dir="$(cd "$proj_dir" && pwd)"

# Discovery runs from INSIDE proj_dir against RELATIVE paths (#2219): an absolute
# base would let the `*/.claude/worktrees/*` prune match the scan root itself
# when the root is an agent worktree, and the guard would scan nothing.
cd "$proj_dir" || { echo "check-agent-turn-budget.sh: cannot cd to $proj_dir" >&2; exit 2; }

plugin_dirs=()
while IFS= read -r -d '' plugin_dir; do
  plugin_dirs+=("$plugin_dir")
done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0)

agent_files=()
if [ ${#plugin_dirs[@]} -gt 0 ]; then
  while IFS= read -r -d '' agent_file; do
    agent_files+=("${agent_file#./}")
  done < <(
    find "${plugin_dirs[@]}" -path '*/.claude/worktrees/*' -prune -o \
      -path '*/agents/*.md' -type f -print0 | sort -z
  )
fi

if [ ${#agent_files[@]} -eq 0 ] && [ ${#plugin_dirs[@]} -gt 0 ]; then
  echo "check-agent-turn-budget.sh: found ${#plugin_dirs[@]} plugin director(ies) but ZERO agent files; discovery misfired (#2219)" >&2
  exit 2
fi

# frontmatter_turns <file> - the maxTurns value inside the first `---` block.
frontmatter_turns() {
  awk '{ sub(/\r$/, "") }
       NR == 1 && $0 == "---" { inside = 1; next }
       inside && $0 == "---" { exit }
       inside && /^maxTurns:/ { v = $0; sub(/^maxTurns:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v); print v; exit }' "$1"
}

# turn_budget_section <file> - body of the first `## Turn Budget` section,
# skipping fenced code blocks, up to the next `## ` heading.
turn_budget_section() {
  awk '{ sub(/\r$/, "") }
       /^```/ { fence = !fence }
       !fence && /^## Turn Budget[[:space:]]*$/ && !found { found = 1; insec = 1; next }
       insec && !fence && /^## / { exit }
       insec { print }' "$1"
}

issue_count=0
findings=""
first_reason=""
add_issue() {
  # add_issue <type> <file> <msg>
  issue_count=$((issue_count + 1))
  [ -n "$first_reason" ] || first_reason="$1: $2 $3"
  findings="${findings}  - SEVERITY=ERROR TYPE=$1 FILE=$2 MSG=$3
"
}

scanned=${#agent_files[@]}
with_limit=0
compliant=0

for agent_file in ${agent_files[@]+"${agent_files[@]}"}; do
  turns="$(frontmatter_turns "$agent_file")"
  [ -n "$turns" ] || continue
  with_limit=$((with_limit + 1))

  problem=""
  if ! [[ "$turns" =~ ^[1-9][0-9]*$ ]]; then
    add_issue bad_max_turns "$agent_file" "maxTurns: $turns is not a positive integer"
    continue
  fi

  section="$(turn_budget_section "$agent_file")"
  if [ -z "$section" ]; then
    problem="missing_turn_budget|no '## Turn Budget' section; at maxTurns: $turns the agent is cut off with no report (issue #3152)"
  elif ! grep -qE "maxTurns: ${turns}([^0-9]|\$)" <<<"$section"; then
    problem="turn_budget_stale_limit|section does not name 'maxTurns: $turns', the frontmatter limit"
  elif ! grep -qF '80%' <<<"$section"; then
    problem="turn_budget_no_threshold|section does not name the 80% point at which to stop investigating"
  elif ! grep -qi 'report' <<<"$section"; then
    problem="turn_budget_no_report|section does not tell the agent to deliver a report"
  fi

  if [ -n "$problem" ]; then
    add_issue "${problem%%|*}" "$agent_file" "${problem#*|}"
  else
    compliant=$((compliant + 1))
  fi
done

echo "=== AGENT TURN BUDGET ==="
echo "AGENT_FILES_SCANNED=$scanned"
echo "AGENTS_WITH_MAXTURNS=$with_limit"
echo "AGENTS_COMPLIANT=$compliant"
if [ "$scanned" -eq 0 ]; then echo "SCANNED_EMPTY=true"; else echo "SCANNED_EMPTY=false"; fi
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  reason="$first_reason"
  [ "$issue_count" -gt 1 ] && reason="${reason:0:170} (+$((issue_count - 1)) more)"
  echo "REASON=${reason:0:200}"
  echo "ISSUES:"
  printf '%s' "$findings"
else
  echo "STATUS=OK"
fi
echo "=== END AGENT TURN BUDGET ==="

[ "$issue_count" -gt 0 ] && exit 1
exit 0
