#!/usr/bin/env bash
# Regression test for scripts/check-agent-turn-budget.sh (issue #3152).
#
# `agents-plugin:review` (`maxTurns: 25`) spent its whole budget investigating and
# returned NO report on 5 of 6 PR reviews. Every agent that sets `maxTurns` must
# carry a `## Turn Budget` section: name the limit, stop investigating at about
# 80%, and deliver the report.
#
# Guards:
#   A. the real repo stays clean, and the guard actually looked (guard integrity)
#   B. a compliant fixture exits 0 with STATUS=OK
#   C. a missing section exits 1 and names the file (the #3152 shape)
#   D. a section naming a different limit than the frontmatter fails
#      (raising maxTurns without updating the prose)
#   E. a section with no 80% threshold fails; one with no report instruction fails
#   F. an agent that sets no maxTurns is not scanned for the section
#   G. a heading inside a code fence does not count as the section
#   H. the pending ratchet: a listed agent is exempt; a listed agent that now
#      complies fails; a listed path that is not a maxTurns agent fails
#   I. a worktree-shaped scan root still scans (#2219 class)
#   J. an unknown argument exits 2
#   K. every failing and passing output satisfies the structured-output contract
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-agent-turn-budget.sh"
contract="$repo_root/scripts/check-structured-output-contract.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { grep -q -- "$2" <<<"$1" && echo true || echo false; }
is_true() { [ "$1" = "true" ] && echo true || echo false; }

# The runtime half of the contract (#2691): one canonical STATUS=, ISSUE_COUNT=
# equal to the ISSUES: rows, REASON= present iff non-OK.
validates() {
  printf '%s\n' "$1" | bash "$contract" --validate >/dev/null 2>&1 && echo true || echo false
}

tmp_root="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 2; }
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then echo "mktemp returned no directory" >&2; exit 2; fi
trap 'rm -rf "$tmp_root"' EXIT

# make_agent <root> <name> <turns|-> <section-body|->
# Writes <root>/demo-plugin/agents/<name>.md. turns "-" omits maxTurns; body "-"
# omits the section. The body is placed under a `## Turn Budget` heading.
make_agent() {
  local root="$1" name="$2" turns="$3" body="$4" file
  file="$root/demo-plugin/agents/$name.md"
  mkdir -p "$root/demo-plugin/agents"
  {
    echo "---"
    echo "name: $name"
    echo "model: opus"
    echo "description: Fixture agent for the turn budget test."
    echo "tools: Read"
    [ "$turns" = "-" ] || echo "maxTurns: $turns"
    echo "created: 2026-10-22"
    echo "modified: 2026-10-22"
    echo "reviewed: 2026-10-22"
    echo "---"
    echo "# Fixture"
    echo ""
    if [ "$body" != "-" ]; then
      echo "## Turn Budget"
      echo ""
      printf '%s\n' "$body"
      echo ""
    fi
    echo "## Output Format"
    echo ""
    echo "Fixture output."
  } > "$file"
}

good_body() {
  echo "\`maxTurns: $1\` ends the run. Once about 80% are used, stop investigating and deliver the report; mark the rest Not verified."
}

new_root() { local d; d="$(mktemp -d -p "$tmp_root")" || exit 2; [ -d "$d" ] || exit 2; echo "$d"; }

# --- TEST A: the real repo -----------------------------------------------------
echo "=== TEST A: real repo ==="
out="$(bash "$checker" --project-dir "$repo_root" 2>&1)"; rc=$?
assert "A real repo exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "A STATUS=OK" "$(contains "$out" '^STATUS=OK$')"
assert "A output satisfies the contract" "$(validates "$out")"
# Guard integrity: a checker that scanned nothing also prints STATUS=OK.
assert "A is not SCANNED_EMPTY" "$(contains "$out" 'SCANNED_EMPTY=false')"
n_compliant="$(sed -n 's/^AGENTS_COMPLIANT=//p' <<<"$out")"
assert "A found compliant agents (>= 13: all of agents-plugin)" "$([ "${n_compliant:-0}" -ge 13 ] && echo true || echo false)"
assert "A review.md is among the agents with a limit" "$([ -f "$repo_root/agents-plugin/agents/review.md" ] && grep -q '^## Turn Budget$' "$repo_root/agents-plugin/agents/review.md" && echo true || echo false)"

# --- TEST B: compliant fixture --------------------------------------------------
echo "=== TEST B: compliant fixture ==="
r="$(new_root)"
make_agent "$r" alpha 25 "$(good_body 25)"
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "B exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "B STATUS=OK" "$(contains "$out" '^STATUS=OK$')"
assert "B counted the agent as compliant" "$(contains "$out" 'AGENTS_COMPLIANT=1')"
assert "B carries no REASON on OK" "$([ "$(contains "$out" '^REASON=')" = false ] && echo true || echo false)"
assert "B output satisfies the contract" "$(validates "$out")"

# --- TEST C: missing section (the #3152 shape) ------------------------------------
echo "=== TEST C: missing section ==="
r="$(new_root)"
make_agent "$r" review 25 "-"
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "C exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "C STATUS=ERROR" "$(contains "$out" '^STATUS=ERROR$')"
assert "C names the file" "$(contains "$out" 'demo-plugin/agents/review.md')"
assert "C TYPE=missing_turn_budget" "$(contains "$out" 'TYPE=missing_turn_budget')"
assert "C REASON cites the limit" "$(contains "$out" '^REASON=missing_turn_budget:.*maxTurns: 25')"
assert "C failing output satisfies the contract" "$(validates "$out")"
failing_c="$out"

# --- TEST D: stale limit ------------------------------------------------------------
echo "=== TEST D: section names a different limit ==="
r="$(new_root)"
make_agent "$r" alpha 40 "$(good_body 25)"
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "D exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "D TYPE=turn_budget_stale_limit" "$(contains "$out" 'TYPE=turn_budget_stale_limit')"
assert "D failing output satisfies the contract" "$(validates "$out")"
# A longer number sharing the prefix is not the same limit (prose 250 vs frontmatter 25).
r="$(new_root)"
make_agent "$r" alpha 25 "$(good_body 250)"
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "D prose limit 250 does not satisfy a frontmatter limit of 25" "$(is_true "$([ $rc -eq 1 ] && contains "$out" 'TYPE=turn_budget_stale_limit')")"

# --- TEST E: no threshold / no report -----------------------------------------------
echo "=== TEST E: threshold and report instruction ==="
r="$(new_root)"
make_agent "$r" alpha 25 "\`maxTurns: 25\` ends the run. Stop investigating soon and deliver the report."
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "E no 80%: exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "E no 80%: TYPE=turn_budget_no_threshold" "$(contains "$out" 'TYPE=turn_budget_no_threshold')"
assert "E no 80%: satisfies the contract" "$(validates "$out")"
r="$(new_root)"
make_agent "$r" alpha 25 "\`maxTurns: 25\` ends the run. At about 80% of the budget, stop."
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "E no report: exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "E no report: TYPE=turn_budget_no_report" "$(contains "$out" 'TYPE=turn_budget_no_report')"

# --- TEST F: no maxTurns ---------------------------------------------------------------
echo "=== TEST F: agent without maxTurns ==="
r="$(new_root)"
make_agent "$r" alpha - "-"
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "F exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "F scanned the file" "$(contains "$out" 'AGENT_FILES_SCANNED=1')"
assert "F found no limit" "$(contains "$out" 'AGENTS_WITH_MAXTURNS=0')"
assert "F satisfies the contract" "$(validates "$out")"

# --- TEST G: heading inside a code fence ---------------------------------------------
echo "=== TEST G: fenced heading is not the section ==="
r="$(new_root)"
make_agent "$r" alpha 25 "-"
{
  echo ""
  echo '```'
  echo "## Turn Budget"
  echo "maxTurns: 25, about 80%, deliver the report"
  echo '```'
} >> "$r/demo-plugin/agents/alpha.md"
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "G fenced heading exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "G TYPE=missing_turn_budget" "$(contains "$out" 'TYPE=missing_turn_budget')"

# --- TEST H: pending ratchet -----------------------------------------------------------
echo "=== TEST H: pending ratchet ==="
r="$(new_root)"
make_agent "$r" legacy 20 "-"
make_agent "$r" alpha 25 "$(good_body 25)"
pend="$r/pending.txt"
printf '# comment\ndemo-plugin/agents/legacy.md\n' > "$pend"
out="$(AGENT_TURN_BUDGET_PENDING="$pend" bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "H pending agent is exempt (exit 0)" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "H pending agent counted" "$(contains "$out" 'AGENTS_PENDING=1')"
assert "H exempt run satisfies the contract" "$(validates "$out")"
# Without the list the same agent fails: the exemption is the list, nothing else.
out="$(bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "H unlisted agent fails" "$(is_true "$([ $rc -eq 1 ] && contains "$out" 'demo-plugin/agents/legacy.md')")"
# A listed agent that now complies must leave the list.
printf 'demo-plugin/agents/alpha.md\n' > "$pend"
out="$(AGENT_TURN_BUDGET_PENDING="$pend" bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "H compliant pending entry fails" "$(is_true "$([ $rc -eq 1 ] && contains "$out" 'TYPE=pending_now_compliant')")"
assert "H ratchet failure satisfies the contract" "$(validates "$out")"
# A listed path that is not a maxTurns agent is stale.
printf 'demo-plugin/agents/gone.md\n' > "$pend"
out="$(AGENT_TURN_BUDGET_PENDING="$pend" bash "$checker" --project-dir "$r" 2>&1)"; rc=$?
assert "H stale pending entry fails" "$(is_true "$([ $rc -eq 1 ] && contains "$out" 'TYPE=pending_stale')")"

# --- TEST I: worktree-shaped scan root (#2219 class) -------------------------------------
echo "=== TEST I: scan root that is itself an agent worktree ==="
wt_root="$tmp_root/.claude/worktrees/agent-fixture"
mkdir -p "$wt_root"
make_agent "$wt_root" alpha 25 "$(good_body 25)"
out="$(bash "$checker" --project-dir "$wt_root" 2>&1)"; rc=$?
assert "I exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "I scanned the agent despite the worktree-shaped root" "$(contains "$out" 'AGENT_FILES_SCANNED=1')"

# --- TEST J: unknown argument ---------------------------------------------------------------
echo "=== TEST J: unknown argument ==="
out="$(bash "$checker" --bogus 2>&1)"; rc=$?
assert "J exits 2" "$(is_true "$([ $rc -eq 2 ] && echo true)")"
assert "J names the argument" "$(contains "$out" 'unknown argument: --bogus')"

# --- TEST K: the failing fixture, piped explicitly through --validate -----------------------
echo "=== TEST K: contract validation of the failing fixture ==="
k_ok=false
if printf '%s\n' "$failing_c" | bash "$contract" --validate >/dev/null 2>&1; then k_ok=true; fi
assert "K failing fixture passes --validate" "$k_ok"

echo ""
echo "=== RESULTS ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
