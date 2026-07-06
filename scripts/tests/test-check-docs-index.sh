#!/usr/bin/env bash
# Regression test for scripts/check-docs-index.sh (Layer 1 docs-drift audit, #1460).
#
# Guards three things:
#   A. the real repo stays clean — every new rule must be added to the CLAUDE.md
#      Rules table (this is the recurring invariant the audit enforces)
#   B. an unindexed rule is flagged (WARN rule_not_indexed)
#   C. a plugin present in marketplace.json but missing on disk is flagged
#      (ERROR plugin_map_drift) and --strict exits non-zero
#   D. a README table row stating the wrong skill count is flagged
#      (WARN doc_count_drift); a correct row is NOT flagged (zero false positive)
#   E. a plugin-relationships.d2 node naming a non-existent plugin is flagged
#      (ERROR diagram_node_dangling) and a wrong stated count is flagged
#      (WARN diagram_count_drift); a correct node is NOT flagged (#1523)
#   F. a rule file missing `reviewed:` is flagged (WARN rule_reviewed_missing);
#      a rule file whose `reviewed:` is the `YYYY-MM-DD` placeholder is flagged
#      (WARN rule_reviewed_placeholder); a rule with a real reviewed: date is NOT
#      flagged, and a `YYYY-MM-DD` in a body example is NOT flagged (#1851)
#   G. a PLUGIN-MAP.md header stating the wrong plugin count vs marketplace, or a
#      skill floor exceeding disk, is flagged (WARN doc_count_drift); a header
#      matching disk is NOT flagged (zero false positive) (#1948)
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-docs-index.sh"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() { printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2; }
contains() { printf '%s' "$1" | grep -q "$2" && echo true || echo false; }

echo "=== TEST A: real repo is clean ==="
real_out="$(bash "$checker" --project-dir "$repo_root")"
assert "real repo STATUS should be OK" "$([ "$(field "$real_out" STATUS)" = "OK" ] && echo true || echo false)"
assert "real repo ISSUE_COUNT should be 0" "$([ "$(field "$real_out" ISSUE_COUNT)" = "0" ] && echo true || echo false)"

# --- Build a synthetic fixture repo with deliberate drift ---------------------
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/.claude/rules" "$fixture/.claude-plugin" "$fixture/docs" \
  "$fixture/alpha-plugin" "$fixture/beta-plugin"

printf '# Indexed rule\n' > "$fixture/.claude/rules/indexed.md"
printf '# Orphan rule (intentionally not in the table)\n' > "$fixture/.claude/rules/orphan.md"

# reviewed: frontmatter fixtures (#1851). All three are indexed in CLAUDE.md so
# they add no rule_not_indexed noise; TEST F asserts only the reviewed checks.
#   - rev-missing.md: no reviewed: field       → rule_reviewed_missing
#   - rev-placeholder.md: reviewed: YYYY-MM-DD  → rule_reviewed_placeholder
#   - rev-ok.md: real reviewed: date + a body YYYY-MM-DD example → NOT flagged
printf '# Rule missing reviewed\n' > "$fixture/.claude/rules/rev-missing.md"
cat > "$fixture/.claude/rules/rev-placeholder.md" <<'EOF'
---
created: 2026-07-04
modified: 2026-07-04
reviewed: YYYY-MM-DD
---

# Rule with placeholder reviewed
EOF
cat > "$fixture/.claude/rules/rev-ok.md" <<'EOF'
---
created: 2026-07-04
modified: 2026-07-04
reviewed: 2026-07-04
---

# Rule with a real reviewed date

A body example that documents the template placeholder must NOT be flagged:

```yaml
reviewed: YYYY-MM-DD
```
EOF

cat > "$fixture/CLAUDE.md" <<'EOF'
# Rules
| Rule | Purpose |
|------|---------|
| `.claude/rules/indexed.md` | listed |
| `.claude/rules/rev-missing.md` | reviewed fixture |
| `.claude/rules/rev-placeholder.md` | reviewed fixture |
| `.claude/rules/rev-ok.md` | reviewed fixture |
EOF

# marketplace has a ghost plugin (gamma) that has no dir on disk
cat > "$fixture/.claude-plugin/marketplace.json" <<'EOF'
{ "name": "m", "plugins": [
  {"name": "alpha-plugin"}, {"name": "beta-plugin"}, {"name": "gamma-plugin"} ] }
EOF
cat > "$fixture/release-please-config.json" <<'EOF'
{ "packages": { "alpha-plugin": {}, "beta-plugin": {}, "gamma-plugin": {} } }
EOF
cat > "$fixture/.release-please-manifest.json" <<'EOF'
{ "alpha-plugin": "1.0.0", "beta-plugin": "1.0.0", "gamma-plugin": "1.0.0" }
EOF
# PLUGIN-MAP.md header states a WRONG plugin count (2, actual marketplace 3) and
# a skill floor EXCEEDING disk (300+, actual 3). The body lists all plugins so
# Check 2's presence check stays clean; TEST G asserts only the header checks.
printf 'Navigation guide for 2 plugins and 300+ skills. Start here.\n\nalpha-plugin, beta-plugin, gamma-plugin\n' > "$fixture/docs/PLUGIN-MAP.md"

# alpha-plugin: 2 skills (mixed SKILL.md / skill.md) + 1 agent; beta-plugin: 1 skill, 0 agents
mkdir -p "$fixture/alpha-plugin/skills/s1" "$fixture/alpha-plugin/skills/s2" \
  "$fixture/alpha-plugin/agents" "$fixture/beta-plugin/skills/s1"
printf '# s\n' > "$fixture/alpha-plugin/skills/s1/SKILL.md"
printf '# s\n' > "$fixture/alpha-plugin/skills/s2/skill.md"
printf '# a\n' > "$fixture/alpha-plugin/agents/a1.md"
printf '# s\n' > "$fixture/beta-plugin/skills/s1/skill.md"

# README states a wrong count for alpha (5, actual 2), a correct one for beta (1),
# and wrong headline totals (2 plugins / 21 agents; actual 3 / 1).
cat > "$fixture/README.md" <<'EOF'
A curated collection of 2 Claude Code plugins providing 300+ skills and 21 agents for development workflows.

| Plugin | Skills | Description |
|--------|--------|-------------|
| **alpha-plugin** | 5 | wrong skill count |
| **beta-plugin** | 1 | correct skill count |
EOF

# Diagram: alpha node correct (2 skills + 1 agent), beta node wrong (5 skills),
# and a command-analytics node naming a plugin dir that does not exist.
mkdir -p "$fixture/docs/diagrams"
cat > "$fixture/docs/diagrams/plugin-relationships.d2" <<'EOF'
title: "Fixture" {
  shape: text
}
alpha: {
  label: "alpha\n2 skills + 1 agent"
}
beta: {
  label: "beta\n5 skills"
}
analytics: {
  label: "command-analytics\n4 skills"
}
EOF

echo "=== TEST B: unindexed rule flagged ==="
fx_out="$(bash "$checker" --project-dir "$fixture")"
assert "orphan.md should be flagged rule_not_indexed" "$(contains "$fx_out" "rule_not_indexed.*orphan.md")"

echo "=== TEST C: ghost plugin flagged + --strict exit code ==="
assert "gamma-plugin should be flagged plugin_map_drift" "$(contains "$fx_out" "plugin_map_drift.*gamma-plugin")"
assert "fixture STATUS should be ERROR" "$([ "$(field "$fx_out" STATUS)" = "ERROR" ] && echo true || echo false)"

strict_rc=0
bash "$checker" --project-dir "$fixture" --strict >/dev/null || strict_rc=$?
assert "--strict should exit 1 on ERROR drift" "$([ "$strict_rc" -eq 1 ] && echo true || echo false)"

clean_rc=0
bash "$checker" --project-dir "$repo_root" --strict >/dev/null || clean_rc=$?
assert "--strict should exit 0 on clean repo" "$([ "$clean_rc" -eq 0 ] && echo true || echo false)"

echo "=== TEST D: per-plugin count drift flagged, correct row not flagged ==="
assert "alpha-plugin wrong skill count should be flagged doc_count_drift" \
  "$(contains "$fx_out" "doc_count_drift.*alpha-plugin has 5 skills but 2")"
assert "beta-plugin correct count should NOT be flagged" \
  "$([ "$(contains "$fx_out" "doc_count_drift.*beta-plugin")" = "false" ] && echo true || echo false)"
assert "README headline plugin-count drift should be flagged" \
  "$(contains "$fx_out" "doc_count_drift.*headline states 2 plugins")"
assert "README headline agent-count drift should be flagged" \
  "$(contains "$fx_out" "doc_count_drift.*headline states 21 agents")"

echo "=== TEST E: diagram node drift flagged, correct node not flagged (#1523) ==="
assert "command-analytics dangling node should be flagged diagram_node_dangling" \
  "$(contains "$fx_out" "diagram_node_dangling.*command-analytics")"
assert "beta diagram node wrong count should be flagged diagram_count_drift" \
  "$(contains "$fx_out" "diagram_count_drift.*beta has 5 skills but 1")"
assert "alpha diagram node correct count should NOT be flagged" \
  "$([ "$(contains "$fx_out" "diagram_count_drift.*alpha")" = "false" ] && echo true || echo false)"

echo "=== TEST F: rule reviewed: frontmatter presence + placeholder (#1851) ==="
assert "rev-missing.md should be flagged rule_reviewed_missing" \
  "$(contains "$fx_out" "rule_reviewed_missing.*rev-missing.md")"
assert "rev-placeholder.md should be flagged rule_reviewed_placeholder" \
  "$(contains "$fx_out" "rule_reviewed_placeholder.*rev-placeholder.md")"
assert "rev-ok.md (real date) should NOT be flagged missing" \
  "$([ "$(contains "$fx_out" "rule_reviewed_missing.*rev-ok.md")" = "false" ] && echo true || echo false)"
assert "rev-ok.md (body YYYY example) should NOT be flagged placeholder" \
  "$([ "$(contains "$fx_out" "rule_reviewed_placeholder.*rev-ok.md")" = "false" ] && echo true || echo false)"

echo "=== TEST G: PLUGIN-MAP.md header total drift flagged, correct header not flagged (#1948) ==="
assert "PLUGIN-MAP header wrong plugin-count should be flagged doc_count_drift" \
  "$(contains "$fx_out" "doc_count_drift.*PLUGIN-MAP.md header states 2 plugins")"
assert "PLUGIN-MAP header skill-floor exceeding disk should be flagged doc_count_drift" \
  "$(contains "$fx_out" "doc_count_drift.*PLUGIN-MAP.md header claims 300+ skills")"

# Correct-header sub-case: rewrite the header to match disk (3 plugins, floor 3)
# and assert the PLUGIN-MAP header checks produce no drift.
printf 'Navigation guide for 3 plugins and 3+ skills. Start here.\n\nalpha-plugin, beta-plugin, gamma-plugin\n' > "$fixture/docs/PLUGIN-MAP.md"
fx_ok_out="$(bash "$checker" --project-dir "$fixture")"
assert "PLUGIN-MAP correct header should NOT be flagged for plugin count" \
  "$([ "$(contains "$fx_ok_out" "PLUGIN-MAP.md header states")" = "false" ] && echo true || echo false)"
assert "PLUGIN-MAP correct header should NOT be flagged for skill floor" \
  "$([ "$(contains "$fx_ok_out" "PLUGIN-MAP.md header claims")" = "false" ] && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
