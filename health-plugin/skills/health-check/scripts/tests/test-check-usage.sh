#!/usr/bin/env bash
# Regression test for check-usage.sh (ADR-0018, usage-telemetry scope).
# Semantic invariants guarded:
#   1. Insufficient history (fresh clone / remote) → STATUS=SKIP, never "all never-fired".
#   2. Schema-drift sentinel: transcripts present but zero tool_use parsed → STATUS=WARN schema_drift.
#   3. Never-fired + dormant classification from transcript recency (file mtime vs window).
#   4. --verbose lists the offending skill names.
#   5. .claude/worktrees clones are pruned from the transcript scan.
#   6. Agent classification from namespaced subagent_type (legacy --skills-dir inventory).
#   7. A window wider than cleanupPeriodDays adds an INFO note.
#   8–13. Registry inventory (the 5,756-"enabled"-skills bug, 2026-11-10): the
#      enabled set comes from installed_plugins.json + enabledPlugins, so a plugin's
#      older cached versions and disabled plugins are not counted; matching is
#      exact, so a skill whose name is a substring of a fired skill is not fired.
#  14. One corrupt transcript line does not drop the other events in the scan batch.
#  15. REASON= is emitted on WARN and omitted on OK.
#
# Hermetic: every path is a mktemp sandbox; HOME is never read (--home-dir and
# --project-dir always point into the sandbox, CLAUDE_CODE_PLUGIN_CACHE_DIR is
# unset). CHECK_USAGE_SCRIPT overrides the script under test (used to replay a
# pre-fix copy and confirm the new cases fail on it).
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${CHECK_USAGE_SCRIPT:-${script_dir}/../check-usage.sh}"

# CHECK_USAGE_KEEP_GOING=1 records failures and continues, so a replay against
# a pre-fix copy shows every case it fails rather than only the first.
fail_count=0
fail() {
  echo -e "FAIL: $1" >&2
  fail_count=$((fail_count + 1))
  [ "${CHECK_USAGE_KEEP_GOING:-0}" = "1" ] || exit 1
}
pass() { echo "PASS: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-usage tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-usage.sh not found at $check_script"

# Guarded sandbox: an empty mktemp result must never become a real path.
sandbox() {
  local d
  d="$(mktemp -d 2>/dev/null)" || fail "mktemp -d failed"
  { [ -n "$d" ] && [ -d "$d" ]; } || fail "mktemp -d returned an empty path"
  printf '%s' "$d"
}

run_check() {  # all args forwarded; never inherits a real plugin-cache override
  env -u CLAUDE_CODE_PLUGIN_CACHE_DIR bash "$check_script" "$@"
}

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

age_file() {  # $1 = file, $2 = days in the past
  local ts=$(( $(date +%s) - $2 * 86400 ))
  touch -d "@${ts}" "$1" 2>/dev/null || touch -t "$(date -r "$ts" +%Y%m%d%H%M 2>/dev/null || echo 202001010000)" "$1"
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

# --- Registry fixtures --------------------------------------------------------
# cache_plugin <home> <marketplace> <plugin> <version> <skills csv> [agents csv]
# Creates <home>/.claude/plugins/cache/<mkt>/<plugin>/<version>/ with a manifest.
cache_plugin() {
  local home="$1" mkt="$2" plug="$3" ver="$4" skills_csv="$5" agents_csv="${6:-}"
  local root="${home}/.claude/plugins/cache/${mkt}/${plug}/${ver}" s a
  mkdir -p "${root}/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "$plug" "$ver" > "${root}/.claude-plugin/plugin.json"
  IFS=',' read -r -a _skills <<<"$skills_csv"
  for s in "${_skills[@]}"; do
    [ -n "$s" ] || continue
    mkdir -p "${root}/skills/${s}"
    printf -- '---\ndescription: x\n---\nbody\n' > "${root}/skills/${s}/SKILL.md"
  done
  IFS=',' read -r -a _agents <<<"$agents_csv"
  for a in "${_agents[@]}"; do
    [ -n "$a" ] || continue
    mkdir -p "${root}/agents"
    printf -- '---\ndescription: x\n---\nbody\n' > "${root}/agents/${a}.md"
  done
  printf '%s' "$root"
}
# write_registry <home> <json for .plugins>
write_registry() {
  jq -n --argjson p "$2" '{version:2, plugins:$p}' > "$1/.claude/plugins/installed_plugins.json"
}
# write_settings <file> <json for .enabledPlugins>
write_settings() {
  mkdir -p "$(dirname "$1")"
  jq -n --argjson e "$2" '{enabledPlugins:$e}' > "$1"
}
key_of() {  # $1 = output, $2 = KEY → value
  sed -n "s/^$2=//p" <<<"$1" | head -n1
}
# in_list <space-separated list> <item>: exact membership. grep -w is not
# enough: '-' is a word boundary, so -w "health" matches "health-check".
in_list() {
  grep -qxF -- "$2" <<<"$(tr ' ' '\n' <<<"$1")"
}
never_of() {  # $1 = verbose output → the never_fired SKILLS= list
  sed -n 's/.*TYPE=never_fired COUNT=[0-9]* SKILLS=//p' <<<"$1"
}

# -----------------------------------------------------------------------------
# Case 1: insufficient history (0 transcripts) → SKIP
# -----------------------------------------------------------------------------
home1="$(sandbox)"; make_home "$home1"; proj1="$(sandbox)"
skills1="$(sandbox)"; make_skills "$skills1" health-check git-commit
out1="$(run_check --home-dir "$home1" --skills-dir "$skills1" --project-dir "$proj1")"
grep -q "^STATUS=SKIP$" <<<"$out1" || fail "Case1 expected STATUS=SKIP, got:\n$out1"
grep -q "^HISTORY_AVAILABLE=false$" <<<"$out1" || fail "Case1 expected HISTORY_AVAILABLE=false:\n$out1"
grep -q "TYPE=insufficient_history" <<<"$out1" || fail "Case1 expected insufficient_history issue:\n$out1"
grep -q "SKILLS_NEVER_FIRED=" <<<"$out1" && fail "Case1 must not report never-fired on skip:\n$out1"
pass "insufficient history → SKIP (no all-never-fired on fresh clone)"
rm -rf "$home1" "$skills1" "$proj1"

# -----------------------------------------------------------------------------
# Case 2: schema drift — transcripts present, zero tool_use parsed → WARN
# -----------------------------------------------------------------------------
home2="$(sandbox)"; make_home "$home2"; proj2="$(sandbox)"
skills2="$(sandbox)"; make_skills "$skills2" health-check
# Two chat-only transcripts (>= min-transcripts) so it is not a SKIP.
chat_event > "$home2/.claude/projects/proj/a.jsonl"
chat_event > "$home2/.claude/projects/proj/b.jsonl"
out2="$(run_check --home-dir "$home2" --skills-dir "$skills2" --project-dir "$proj2")"
grep -q "^SCHEMA_DRIFT_SUSPECTED=true$" <<<"$out2" || fail "Case2 expected SCHEMA_DRIFT_SUSPECTED=true:\n$out2"
grep -q "^STATUS=WARN$" <<<"$out2" || fail "Case2 expected STATUS=WARN:\n$out2"
grep -q "TYPE=schema_drift" <<<"$out2" || fail "Case2 expected schema_drift issue:\n$out2"
pass "transcripts present + zero tool_use → schema_drift WARN (not all never-fired)"
rm -rf "$home2" "$skills2" "$proj2"

# -----------------------------------------------------------------------------
# Case 3: never-fired + dormant classification
#   health-check: fired recently (active)
#   git-commit:   fired long ago (dormant)
#   ha-validate:  never fired
# -----------------------------------------------------------------------------
home3="$(sandbox)"; make_home "$home3"; proj3="$(sandbox)"
skills3="$(sandbox)"; make_skills "$skills3" health-check git-commit ha-validate

recent="$home3/.claude/projects/proj/recent.jsonl"
old="$home3/.claude/projects/proj/old.jsonl"
{ skill_event "health-check"; tool_event "Bash"; } > "$recent"
skill_event "git-commit" > "$old"
# Make 'old' transcript predate the 30-day window; 'recent' stays now.
age_file "$old" 60

out3="$(run_check --home-dir "$home3" --skills-dir "$skills3" --project-dir "$proj3" --window-days 30)"
grep -q "^HISTORY_AVAILABLE=true$" <<<"$out3" || fail "Case3 expected HISTORY_AVAILABLE=true:\n$out3"
grep -q "^SKILLS_ENABLED=3$" <<<"$out3" || fail "Case3 expected SKILLS_ENABLED=3:\n$out3"
grep -q "^SKILLS_NEVER_FIRED=1$" <<<"$out3" || fail "Case3 expected SKILLS_NEVER_FIRED=1 (ha-validate):\n$out3"
grep -q "^SKILLS_DORMANT=1$" <<<"$out3" || fail "Case3 expected SKILLS_DORMANT=1 (git-commit):\n$out3"
grep -q "^STATUS=WARN$" <<<"$out3" || fail "Case3 expected STATUS=WARN:\n$out3"
pass "never-fired + dormant classified from transcript recency"

# -----------------------------------------------------------------------------
# Case 4: --verbose lists the offending skill names
# -----------------------------------------------------------------------------
out4="$(run_check --home-dir "$home3" --skills-dir "$skills3" --project-dir "$proj3" --window-days 30 --verbose)"
grep -q "TYPE=never_fired .*SKILLS=.*ha-validate" <<<"$out4" || fail "Case4 expected ha-validate in verbose never-fired list:\n$out4"
grep -q "TYPE=dormant .*SKILLS=.*git-commit" <<<"$out4" || fail "Case4 expected git-commit in verbose dormant list:\n$out4"
pass "--verbose lists offending skill names"
rm -rf "$home3" "$skills3" "$proj3"

# -----------------------------------------------------------------------------
# Case 5: .claude/worktrees clones are pruned, not scanned (#1492/#1548 class)
# -----------------------------------------------------------------------------
home5="$(sandbox)"; make_home "$home5"; proj5="$(sandbox)"
skills5="$(sandbox)"; make_skills "$skills5" health-check
skill_event "health-check" > "$home5/.claude/projects/proj/a.jsonl"
skill_event "health-check" > "$home5/.claude/projects/proj/b.jsonl"
# A worktree clone copy that must be ignored.
mkdir -p "$home5/.claude/projects/proj/.claude/worktrees/wt/x"
skill_event "health-check" > "$home5/.claude/projects/proj/.claude/worktrees/wt/x/c.jsonl"
out5="$(run_check --home-dir "$home5" --skills-dir "$skills5" --project-dir "$proj5")"
grep -q "^TRANSCRIPTS_SCANNED=2$" <<<"$out5" || fail "Case5 expected TRANSCRIPTS_SCANNED=2 (worktree clone pruned):\n$out5"
grep -q "worktrees" <<<"$out5" && fail "Case5 must not leak a worktrees path:\n$out5"
pass "worktree clones pruned from transcript scan"
rm -rf "$home5" "$skills5" "$proj5"

# -----------------------------------------------------------------------------
# Case 6: agent never-fired + dormant classification from namespaced subagent_type
#   security-audit: fired recently (active)
#   git-ops:        fired long ago (dormant)
#   ci:             never fired
# Guards the AGENT-track extension: subagent_type is namespaced in transcripts
# (plug:agent) and must normalize to the agent's filename basename in inventory.
# -----------------------------------------------------------------------------
home6="$(sandbox)"; make_home "$home6"; proj6="$(sandbox)"
inv6="$(sandbox)"; make_skills "$inv6" health-check; make_agents "$inv6" security-audit git-ops ci

recent6="$home6/.claude/projects/proj/recent.jsonl"
old6="$home6/.claude/projects/proj/old.jsonl"
{ agent_event "agents-plugin:security-audit"; tool_event "Bash"; } > "$recent6"
agent_event "git-plugin:git-ops" > "$old6"
age_file "$old6" 60

out6="$(run_check --home-dir "$home6" --skills-dir "$inv6" --project-dir "$proj6" --window-days 30)"
grep -q "^AGENTS_ENABLED=3$" <<<"$out6" || fail "Case6 expected AGENTS_ENABLED=3:\n$out6"
grep -q "^AGENTS_FIRED=2$" <<<"$out6" || fail "Case6 expected AGENTS_FIRED=2:\n$out6"
grep -q "^AGENTS_NEVER_FIRED=1$" <<<"$out6" || fail "Case6 expected AGENTS_NEVER_FIRED=1 (ci):\n$out6"
grep -q "^AGENTS_DORMANT=1$" <<<"$out6" || fail "Case6 expected AGENTS_DORMANT=1 (git-ops):\n$out6"
pass "agent never-fired + dormant classified from namespaced subagent_type"

# Case 6b: --verbose lists the offending agent names
out6b="$(run_check --home-dir "$home6" --skills-dir "$inv6" --project-dir "$proj6" --window-days 30 --verbose)"
grep -q "TYPE=agent_never_fired .*AGENTS=.*ci" <<<"$out6b" || fail "Case6b expected ci in verbose agent_never_fired list:\n$out6b"
grep -q "TYPE=agent_dormant .*AGENTS=.*git-ops" <<<"$out6b" || fail "Case6b expected git-ops in verbose agent_dormant list:\n$out6b"
pass "--verbose lists offending agent names"
rm -rf "$home6" "$inv6" "$proj6"

# -----------------------------------------------------------------------------
# Case 7: dormancy window wider than cleanupPeriodDays → INFO note (not WARN)
# -----------------------------------------------------------------------------
home7="$(sandbox)"; make_home "$home7"; proj7="$(sandbox)"
skills7="$(sandbox)"; make_skills "$skills7" health-check
skill_event "health-check" > "$home7/.claude/projects/proj/a.jsonl"
skill_event "health-check" > "$home7/.claude/projects/proj/b.jsonl"
out7a="$(run_check --home-dir "$home7" --skills-dir "$skills7" --project-dir "$proj7" --window-days 90)"
grep -q "^RETENTION_DAYS=30$" <<<"$out7a" || fail "Case7 expected default RETENTION_DAYS=30:\n$out7a"
grep -q "SEVERITY=INFO TYPE=window_exceeds_retention" <<<"$out7a" || fail "Case7 expected window_exceeds_retention INFO:\n$out7a"
grep -q "^STATUS=OK$" <<<"$out7a" || fail "Case7 INFO must not raise STATUS:\n$out7a"
echo '{"cleanupPeriodDays": 365}' > "$home7/.claude/settings.json"
out7b="$(run_check --home-dir "$home7" --skills-dir "$skills7" --project-dir "$proj7" --window-days 90)"
grep -q "^RETENTION_DAYS=365$" <<<"$out7b" || fail "Case7 expected RETENTION_DAYS=365 from user settings:\n$out7b"
grep -q "window_exceeds_retention" <<<"$out7b" && fail "Case7 window within retention must not note:\n$out7b"
pass "window wider than cleanupPeriodDays → INFO note"
rm -rf "$home7" "$skills7" "$proj7"

# =============================================================================
# Registry inventory (default: no --skills-dir)
# =============================================================================
# One fixture serves cases 8–12:
#   alpha-plugin  cached at 1.0.0 (skills a1,a2,a-old; agent rev) AND 2.0.0
#                 (skills a1,a2; agent rev). Registry points at 2.0.0 → 2 skills.
#   beta-plugin   installed, enabledPlugins=false in user settings → excluded
#                 (skills b1,b2,b3; agent beta-agent).
#   gamma-plugin  never installed (cache dir only, no registry record) → excluded.
#   delta-plugin  skills review, code-review, health, health-check — the
#                 substring trap: only code-review and health-check fire.
#   eps-plugin    user-scope 1.0.0 + project-scope 2.0.0 for this --project-dir;
#                 skills eps-thing (1.0.0) / eps-thing, eps-new (2.0.0).
#   zeta-plugin   no enabledPlugins entry, manifest defaultEnabled=false → excluded.
#   theta-plugin  user=false, project settings.local.json=true → included (local wins).
home8="$(sandbox)"; make_home "$home8"; proj8="$(sandbox)"
mkt="test-mkt"
a_old="$(cache_plugin "$home8" "$mkt" alpha-plugin 1.0.0 "a1,a2,a-old" "rev")"
a_new="$(cache_plugin "$home8" "$mkt" alpha-plugin 2.0.0 "a1,a2" "rev")"
touch "${a_old}/.orphaned_at"
b_root="$(cache_plugin "$home8" "$mkt" beta-plugin 1.0.0 "b1,b2,b3" "beta-agent")"
cache_plugin "$home8" "$mkt" gamma-plugin 1.0.0 "g1,g2" >/dev/null
d_root="$(cache_plugin "$home8" "$mkt" delta-plugin 1.0.0 "review,code-review,health,health-check")"
e_user="$(cache_plugin "$home8" "$mkt" eps-plugin 1.0.0 "eps-thing")"
e_proj="$(cache_plugin "$home8" "$mkt" eps-plugin 2.0.0 "eps-thing,eps-new")"
z_root="$(cache_plugin "$home8" "$mkt" zeta-plugin 1.0.0 "z1")"
printf '{"name":"zeta-plugin","defaultEnabled":false}\n' > "${z_root}/.claude-plugin/plugin.json"
t_root="$(cache_plugin "$home8" "$mkt" theta-plugin 1.0.0 "t1")"
write_registry "$home8" "$(jq -n \
  --arg a "$a_new" --arg b "$b_root" --arg d "$d_root" --arg eu "$e_user" --arg ep "$e_proj" \
  --arg z "$z_root" --arg t "$t_root" --arg pd "$proj8" --arg m "$mkt" '{
    ("alpha-plugin@" + $m): [{scope:"user", installPath:$a, version:"2.0.0"}],
    ("beta-plugin@"  + $m): [{scope:"user", installPath:$b, version:"1.0.0"}],
    ("delta-plugin@" + $m): [{scope:"user", installPath:$d, version:"1.0.0"}],
    ("eps-plugin@"   + $m): [{scope:"user", installPath:$eu, version:"1.0.0"},
                             {scope:"project", projectPath:$pd, installPath:$ep, version:"2.0.0"}],
    ("zeta-plugin@"  + $m): [{scope:"user", installPath:$z, version:"1.0.0"}],
    ("theta-plugin@" + $m): [{scope:"user", installPath:$t, version:"1.0.0"}]
  }')"
write_settings "$home8/.claude/settings.json" "$(jq -n --arg m "$mkt" '{
  ("alpha-plugin@" + $m): true, ("beta-plugin@" + $m): false, ("delta-plugin@" + $m): true,
  ("eps-plugin@" + $m): true, ("theta-plugin@" + $m): false }')"
write_settings "$proj8/.claude/settings.local.json" "$(jq -n --arg m "$mkt" '{("theta-plugin@" + $m): true}')"

# Transcripts: substring-trap fires, a directory-prefixed form, a bare form,
# and a namespaced agent spawn.
{
  skill_event "delta-plugin:code-review"
  skill_event "/delta-plugin:health-check"
  skill_event "alpha:a1"            # short <ns>:<name> form for alpha-plugin:a1
  skill_event "eps:new"             # directory-prefixed form for eps-plugin:eps-new
  skill_event "t1"                  # bare form
  agent_event "alpha-plugin:rev"
  tool_event "Bash"
} > "$home8/.claude/projects/proj/a.jsonl"
tool_event "Read" > "$home8/.claude/projects/proj/b.jsonl"

out8="$(run_check --home-dir "$home8" --project-dir "$proj8" --verbose)"

# Case 8: two cached versions of one plugin count once (and only the active one).
grep -q "^INVENTORY_SOURCE=registry$" <<<"$out8" || fail "Case8 expected INVENTORY_SOURCE=registry:\n$out8"
grep -q "alpha-plugin:a-old" <<<"$out8" && fail "Case8 a skill only in the orphaned 1.0.0 cache must not be inventoried:\n$out8"
never8="$(never_of "$out8")"
in_list "$never8" "alpha-plugin:a2" || fail "Case8 expected alpha-plugin:a2 listed once as never-fired:\n$out8"
a2_hits=$(grep -cxF 'alpha-plugin:a2' <<<"$(tr ' ' '\n' <<<"$never8")")
[ "$a2_hits" = "1" ] || fail "Case8 alpha-plugin:a2 listed ${a2_hits} times (two cached versions double-counted):\n$out8"
pass "two cached versions of one plugin count once (active installPath only)"

# Case 9: disabled / uninstalled / defaultEnabled=false plugins are excluded;
# a project-local true overrides a user false; the project-scope install record
# applies to its projectPath.
for gone in beta-plugin: gamma-plugin: zeta-plugin: beta-agent; do
  grep -q "$gone" <<<"$out8" && fail "Case9 '${gone}' must be excluded from the inventory:\n$out8"
done
grep -q "^PLUGINS_ENABLED=4$" <<<"$out8" || fail "Case9 expected PLUGINS_ENABLED=4 (alpha, delta, eps, theta):\n$out8"
in_list "$never8" "eps-plugin:eps-thing" || fail "Case9 expected eps-plugin:eps-thing (installed in both records) as never-fired:\n$out8"
pass "disabled, uninstalled and defaultEnabled=false plugins excluded; local enable wins"

# Case 10: a skill whose name is a substring of a fired skill is NOT fired.
in_list "$never8" "delta-plugin:review" || fail "Case10 delta-plugin:review must be never-fired (code-review fired, not review):\n$out8"
in_list "$never8" "delta-plugin:health" || fail "Case10 delta-plugin:health must be never-fired (health-check fired, not health):\n$out8"
in_list "$never8" "delta-plugin:code-review" && fail "Case10 delta-plugin:code-review fired and must not be listed:\n$out8"
pass "substring of a fired skill name is not counted as fired"

# Case 10b: same invariant on the legacy --skills-dir inventory, where keys are
# bare names, so the assertion is independent of the registry key format.
home10="$(sandbox)"; make_home "$home10"; proj10="$(sandbox)"
skills10="$(sandbox)"; make_skills "$skills10" review code-review health health-check
skill_event "code-review" > "$home10/.claude/projects/proj/a.jsonl"
skill_event "health-check" > "$home10/.claude/projects/proj/b.jsonl"
out10="$(run_check --home-dir "$home10" --skills-dir "$skills10" --project-dir "$proj10" --verbose)"
grep -q "^SKILLS_FIRED=2$" <<<"$out10" || fail "Case10b expected SKILLS_FIRED=2 (code-review, health-check only):\n$out10"
never10="$(never_of "$out10")"
in_list "$never10" "review" || fail "Case10b expected review never-fired (code-review fired):\n$out10"
in_list "$never10" "health" || fail "Case10b expected health never-fired (health-check fired):\n$out10"
pass "substring trap closed on the legacy inventory too"
rm -rf "$home10" "$skills10" "$proj10"

# Case 11: inventory sanity bound — exactly the distinct skills of the active
# installPaths: alpha 2 + delta 4 + eps(2.0.0) 2 + theta 1 = 9; agents: rev only.
grep -q "^SKILLS_ENABLED=9$" <<<"$out8" || fail "Case11 expected SKILLS_ENABLED=9:\n$out8"
grep -q "^AGENTS_ENABLED=1$" <<<"$out8" || fail "Case11 expected AGENTS_ENABLED=1 (alpha rev, deduped across versions):\n$out8"
all_skill_md=$(find "$home8/.claude/plugins/cache" -name SKILL.md | wc -l | tr -d ' ')
enabled8="$(key_of "$out8" SKILLS_ENABLED)"
[ "$enabled8" -lt "$all_skill_md" ] || fail "Case11 SKILLS_ENABLED=${enabled8} must stay below the ${all_skill_md} SKILL.md files in the cache"
pass "inventory bounded by distinct skills of active installPaths (9 of ${all_skill_md} cached SKILL.md)"

# Case 12: exact forms match — plugin:name with a leading '/', short <ns>:<name>,
# directory-prefixed <ns>:<rest>, bare name; namespaced agent.
# Fired: code-review, health-check, a1, eps-new, t1 = 5 of 9.
grep -q "^SKILLS_FIRED=5$" <<<"$out8" || fail "Case12 expected SKILLS_FIRED=5:\n$out8"
grep -q "^SKILLS_NEVER_FIRED=4$" <<<"$out8" || fail "Case12 expected SKILLS_NEVER_FIRED=4 (a2, review, health, eps-thing):\n$out8"
grep -q "^AGENTS_FIRED=1$" <<<"$out8" || fail "Case12 expected AGENTS_FIRED=1 (alpha-plugin:rev):\n$out8"
pass "plugin:name, /plugin:name, <ns>:<name>, <ns>:<rest> and bare forms match exactly"
rm -rf "$home8" "$proj8"

# -----------------------------------------------------------------------------
# Case 13: a plugin installed for another project only is not inventoried
# -----------------------------------------------------------------------------
home13="$(sandbox)"; make_home "$home13"; proj13="$(sandbox)"; other13="$(sandbox)"
k_root="$(cache_plugin "$home13" "$mkt" kappa-plugin 1.0.0 "k1")"
write_registry "$home13" "$(jq -n --arg k "$k_root" --arg o "$other13" --arg m "$mkt" \
  '{("kappa-plugin@" + $m): [{scope:"project", projectPath:$o, installPath:$k, version:"1.0.0"}]}')"
skill_event "x" > "$home13/.claude/projects/proj/a.jsonl"
skill_event "x" > "$home13/.claude/projects/proj/b.jsonl"
out13="$(run_check --home-dir "$home13" --project-dir "$proj13")"
grep -q "^SKILLS_ENABLED=0$" <<<"$out13" || fail "Case13 a project-scope install for another projectPath must not count:\n$out13"
grep -q "TYPE=no_skill_inventory" <<<"$out13" || fail "Case13 expected no_skill_inventory:\n$out13"
pass "project-scope install for another project is not inventoried"
rm -rf "$home13" "$proj13" "$other13"

# -----------------------------------------------------------------------------
# Case 14: a corrupt line does not drop the rest of the scan batch
# -----------------------------------------------------------------------------
home14="$(sandbox)"; make_home "$home14"; proj14="$(sandbox)"
skills14="$(sandbox)"; make_skills "$skills14" one two
{ printf '{"type":"assistant","message":{"content":[{"type":"tool_use"\n'; skill_event "one"; } \
  > "$home14/.claude/projects/proj/a.jsonl"
skill_event "two" > "$home14/.claude/projects/proj/b.jsonl"
out14="$(run_check --home-dir "$home14" --skills-dir "$skills14" --project-dir "$proj14")"
grep -q "^SKILLS_FIRED=2$" <<<"$out14" || fail "Case14 expected both skills fired despite a corrupt line:\n$out14"
grep -q "^TOOL_USE_EVENTS=2$" <<<"$out14" || fail "Case14 expected TOOL_USE_EVENTS=2:\n$out14"
pass "corrupt transcript line skipped without losing the batch"

# -----------------------------------------------------------------------------
# Case 15: REASON= on WARN (first finding, '+N more'), none on OK
# -----------------------------------------------------------------------------
grep -q "^STATUS=OK$" <<<"$out14" || fail "Case15 expected STATUS=OK when every skill fired:\n$out14"
grep -q "^REASON=" <<<"$out14" && fail "Case15 REASON= must be absent on OK:\n$out14"
make_skills "$skills14" three
out15="$(run_check --home-dir "$home14" --skills-dir "$skills14" --project-dir "$proj14")"
grep -q "^STATUS=WARN$" <<<"$out15" || fail "Case15 expected STATUS=WARN:\n$out15"
grep -q "^REASON=never_fired: " <<<"$out15" || fail "Case15 expected REASON=never_fired: …:\n$out15"
reason15="$(key_of "$out15" REASON)"
[ "${#reason15}" -le 200 ] || fail "Case15 REASON longer than 200 chars:\n$reason15"
# The repo's runtime contract validator, when this runs inside the repo.
contract="${script_dir}/../../../../../scripts/check-structured-output-contract.sh"
if [ -f "$contract" ]; then
  for block in "$out14" "$out15"; do
    bash "$contract" --validate - <<<"$block" >/dev/null 2>&1 \
      || fail "Case15 output fails check-structured-output-contract.sh --validate:\n$block"
  done
fi
pass "REASON= on WARN, absent on OK"
rm -rf "$home14" "$skills14" "$proj14"

if [ "$fail_count" -gt 0 ]; then
  echo "FAILED: ${fail_count} assertion(s)" >&2
  exit 1
fi
echo "ALL TESTS PASSED"
