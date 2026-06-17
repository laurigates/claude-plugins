#!/usr/bin/env bash
# Regression test for check-usage.sh (ADR-0018, usage-telemetry scope).
# Semantic invariants guarded:
#   1. Insufficient history (fresh clone / remote) → STATUS=SKIP, never "all never-fired".
#   2. Schema-drift sentinel: transcripts present but zero tool_use parsed → STATUS=WARN schema_drift.
#   3. Never-fired + dormant classification from transcript recency (file mtime vs window).
#   4. --verbose lists the offending skill names.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-usage.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-usage tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-usage.sh not found at $check_script"

# Emit one assistant-event JSONL line containing a Skill tool_use.
skill_event() {  # $1 = skill token
  jq -nc --arg s "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Skill",input:{skill:$s}}]}}'
}
# Emit one assistant-event JSONL line containing a non-Skill tool_use.
tool_event() {   # $1 = tool name
  jq -nc --arg n "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:{}}]}}'
}
# Emit a chat-only assistant event (no tool_use).
chat_event() {
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"hello"}]}}'
}
# Emit one assistant-event JSONL line containing an Agent tool_use.
agent_event() {  # $1 = subagent_type token (may be namespaced, e.g. plug:agent)
  jq -nc --arg s "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Agent",input:{subagent_type:$s}}]}}'
}

make_home() { mkdir -p "$1/.claude/projects/proj"; }
make_skills() {  # $1 = skills root, remaining = skill dir names
  local root="$1"; shift
  local s
  for s in "$@"; do
    mkdir -p "${root}/plug-plugin/skills/${s}"
    printf -- '---\nname: %s\n---\nbody\n' "$s" > "${root}/plug-plugin/skills/${s}/SKILL.md"
  done
}
make_agents() {  # $1 = inventory root, remaining = agent names (file <name>.md)
  local root="$1"; shift
  local a
  mkdir -p "${root}/plug-plugin/agents"
  for a in "$@"; do
    printf -- '---\nname: %s\n---\nbody\n' "$a" > "${root}/plug-plugin/agents/${a}.md"
  done
}

# -----------------------------------------------------------------------------
# Case 1: insufficient history (0 transcripts) → SKIP
# -----------------------------------------------------------------------------
home1="$(mktemp -d)"; make_home "$home1"
skills1="$(mktemp -d)"; make_skills "$skills1" health-check git-commit
out1="$(bash "$check_script" --home-dir "$home1" --skills-dir "$skills1" --project-dir /tmp)"
echo "$out1" | grep -q "^STATUS=SKIP$" || fail "Case1 expected STATUS=SKIP, got:\n$out1"
echo "$out1" | grep -q "^HISTORY_AVAILABLE=false$" || fail "Case1 expected HISTORY_AVAILABLE=false:\n$out1"
echo "$out1" | grep -q "TYPE=insufficient_history" || fail "Case1 expected insufficient_history issue:\n$out1"
echo "$out1" | grep -q "SKILLS_NEVER_FIRED=" && fail "Case1 must not report never-fired on skip:\n$out1"
pass "insufficient history → SKIP (no all-never-fired on fresh clone)"
rm -rf "$home1" "$skills1"

# -----------------------------------------------------------------------------
# Case 2: schema drift — transcripts present, zero tool_use parsed → WARN
# -----------------------------------------------------------------------------
home2="$(mktemp -d)"; make_home "$home2"
skills2="$(mktemp -d)"; make_skills "$skills2" health-check
# Two chat-only transcripts (>= min-transcripts) so it is not a SKIP.
chat_event > "$home2/.claude/projects/proj/a.jsonl"
chat_event > "$home2/.claude/projects/proj/b.jsonl"
out2="$(bash "$check_script" --home-dir "$home2" --skills-dir "$skills2" --project-dir /tmp)"
echo "$out2" | grep -q "^SCHEMA_DRIFT_SUSPECTED=true$" || fail "Case2 expected SCHEMA_DRIFT_SUSPECTED=true:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$" || fail "Case2 expected STATUS=WARN:\n$out2"
echo "$out2" | grep -q "TYPE=schema_drift" || fail "Case2 expected schema_drift issue:\n$out2"
pass "transcripts present + zero tool_use → schema_drift WARN (not all never-fired)"
rm -rf "$home2" "$skills2"

# -----------------------------------------------------------------------------
# Case 3: never-fired + dormant classification
#   health-check: fired recently (active)
#   git-commit:   fired long ago (dormant)
#    ha-validate:  never fired
# -----------------------------------------------------------------------------
home3="$(mktemp -d)"; make_home "$home3"
skills3="$(mktemp -d)"; make_skills "$skills3" health-check git-commit ha-validate

recent="$home3/.claude/projects/proj/recent.jsonl"
old="$home3/.claude/projects/proj/old.jsonl"
{ skill_event "health-check"; tool_event "Bash"; } > "$recent"
skill_event "git-commit" > "$old"
# Make 'old' transcript predate the 30-day window; 'recent' stays now.
old_ts=$(( $(date +%s) - 60*86400 ))
touch -d "@${old_ts}" "$old" 2>/dev/null || touch -t "$(date -r "$old_ts" +%Y%m%d%H%M 2>/dev/null || echo 202001010000)" "$old"

out3="$(bash "$check_script" --home-dir "$home3" --skills-dir "$skills3" --project-dir /tmp --window-days 30)"
echo "$out3" | grep -q "^HISTORY_AVAILABLE=true$" || fail "Case3 expected HISTORY_AVAILABLE=true:\n$out3"
echo "$out3" | grep -q "^SKILLS_ENABLED=3$" || fail "Case3 expected SKILLS_ENABLED=3:\n$out3"
echo "$out3" | grep -q "^SKILLS_NEVER_FIRED=1$" || fail "Case3 expected SKILLS_NEVER_FIRED=1 (ha-validate):\n$out3"
echo "$out3" | grep -q "^SKILLS_DORMANT=1$" || fail "Case3 expected SKILLS_DORMANT=1 (git-commit):\n$out3"
echo "$out3" | grep -q "^STATUS=WARN$" || fail "Case3 expected STATUS=WARN:\n$out3"
pass "never-fired + dormant classified from transcript recency"

# -----------------------------------------------------------------------------
# Case 4: --verbose lists the offending skill names
# -----------------------------------------------------------------------------
out4="$(bash "$check_script" --home-dir "$home3" --skills-dir "$skills3" --project-dir /tmp --window-days 30 --verbose)"
echo "$out4" | grep -q "TYPE=never_fired .*SKILLS=.*ha-validate" || fail "Case4 expected ha-validate in verbose never-fired list:\n$out4"
echo "$out4" | grep -q "TYPE=dormant .*SKILLS=.*git-commit" || fail "Case4 expected git-commit in verbose dormant list:\n$out4"
pass "--verbose lists offending skill names"
rm -rf "$home3" "$skills3"

# -----------------------------------------------------------------------------
# Case 5: .claude/worktrees clones are pruned, not scanned (#1492/#1548 class)
# -----------------------------------------------------------------------------
home5="$(mktemp -d)"; make_home "$home5"
skills5="$(mktemp -d)"; make_skills "$skills5" health-check
skill_event "health-check" > "$home5/.claude/projects/proj/a.jsonl"
skill_event "health-check" > "$home5/.claude/projects/proj/b.jsonl"
# A worktree clone copy that must be ignored.
mkdir -p "$home5/.claude/projects/proj/.claude/worktrees/wt/x"
skill_event "health-check" > "$home5/.claude/projects/proj/.claude/worktrees/wt/x/c.jsonl"
out5="$(bash "$check_script" --home-dir "$home5" --skills-dir "$skills5" --project-dir /tmp)"
echo "$out5" | grep -q "^TRANSCRIPTS_SCANNED=2$" || fail "Case5 expected TRANSCRIPTS_SCANNED=2 (worktree clone pruned):\n$out5"
echo "$out5" | grep -q "worktrees" && fail "Case5 must not leak a worktrees path:\n$out5"
pass "worktree clones pruned from transcript scan"
rm -rf "$home5" "$skills5"

# -----------------------------------------------------------------------------
# Case 6: agent never-fired + dormant classification from namespaced subagent_type
#   security-audit: fired recently (active)
#   git-ops:        fired long ago (dormant)
#   ci:             never fired
# Guards the AGENT-track extension: subagent_type is namespaced in transcripts
# (plug:agent) and must normalize to the agent's filename basename in inventory.
# -----------------------------------------------------------------------------
home6="$(mktemp -d)"; make_home "$home6"
inv6="$(mktemp -d)"; make_skills "$inv6" health-check; make_agents "$inv6" security-audit git-ops ci

recent6="$home6/.claude/projects/proj/recent.jsonl"
old6="$home6/.claude/projects/proj/old.jsonl"
{ agent_event "agents-plugin:security-audit"; tool_event "Bash"; } > "$recent6"
agent_event "git-plugin:git-ops" > "$old6"
old6_ts=$(( $(date +%s) - 60*86400 ))
touch -d "@${old6_ts}" "$old6" 2>/dev/null || touch -t "$(date -r "$old6_ts" +%Y%m%d%H%M 2>/dev/null || echo 202001010000)" "$old6"

out6="$(bash "$check_script" --home-dir "$home6" --skills-dir "$inv6" --project-dir /tmp --window-days 30)"
echo "$out6" | grep -q "^AGENTS_ENABLED=3$" || fail "Case6 expected AGENTS_ENABLED=3:\n$out6"
echo "$out6" | grep -q "^AGENTS_FIRED=2$" || fail "Case6 expected AGENTS_FIRED=2:\n$out6"
echo "$out6" | grep -q "^AGENTS_NEVER_FIRED=1$" || fail "Case6 expected AGENTS_NEVER_FIRED=1 (ci):\n$out6"
echo "$out6" | grep -q "^AGENTS_DORMANT=1$" || fail "Case6 expected AGENTS_DORMANT=1 (git-ops):\n$out6"
pass "agent never-fired + dormant classified from namespaced subagent_type"

# Case 6b: --verbose lists the offending agent names
out6b="$(bash "$check_script" --home-dir "$home6" --skills-dir "$inv6" --project-dir /tmp --window-days 30 --verbose)"
echo "$out6b" | grep -q "TYPE=agent_never_fired .*AGENTS=.*ci" || fail "Case6b expected ci in verbose agent_never_fired list:\n$out6b"
echo "$out6b" | grep -q "TYPE=agent_dormant .*AGENTS=.*git-ops" || fail "Case6b expected git-ops in verbose agent_dormant list:\n$out6b"
pass "--verbose lists offending agent names"
rm -rf "$home6" "$inv6"

echo "ALL TESTS PASSED"
