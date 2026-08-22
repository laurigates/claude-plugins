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
#   H. the COMMITTED plugin-relationships.svg is compared against the .d2: a
#      disagreeing label is flagged (ERROR diagram_svg_stale), a .d2 node absent
#      from the .svg is flagged (ERROR diagram_svg_node_missing), a matching
#      label is NOT flagged, and --strict exits 1 when a stale .svg is the ONLY
#      drift — the #2450 shape that used to merge green (#2453)
#   I. a plugin README leading-cell `/<ns>:<name>` row that resolves to no skill
#      directory is flagged (ERROR readme_row_dangling); resolution is EXACT (a
#      longer directory sharing the prefix is not a match) and namespace-aware (a
#      legitimate cross-plugin row is NOT flagged) (#2453)
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

# --- Check 6 fixture: a COMMITTED .svg that disagrees with the .d2 (#2453) ----
# Mimics the d2-emitted tspan pair, one node per state:
#   alpha     — label matches the .d2 exactly        → must NOT be flagged
#   beta      — label disagrees ("1 skills" vs "5")  → diagram_svg_stale
#   analytics — absent from the .svg entirely        → diagram_svg_node_missing
# A check hardwired to flag every node would fail the alpha control; a check
# that silently found nothing would fail the DIAGRAM_SVG_NODES=3 assertion.
cat > "$fixture/docs/diagrams/plugin-relationships.svg" <<'EOF'
<?xml version="1.0" encoding="utf-8"?><svg xmlns="http://www.w3.org/2000/svg" data-d2-version="v0.7.1"><text><tspan x="1.0" y="1.0">alpha</tspan><tspan x="1.0" dy="18.5">2 skills + 1 agent</tspan></text><text><tspan x="2.0" y="2.0">beta</tspan><tspan x="2.0" dy="18.5">1 skills</tspan></text></svg>
EOF

# --- Check 7 fixture: plugin README `/<ns>:<name>` leading-cell rows (#2453) ---
# alpha-plugin/skills/ holds s1/ and s2/; the extra `longname-suffix/` directory
# carries no skill.md, so it is invisible to skill_count() and cannot disturb
# TEST D / TEST E counts — it exists only to prove resolution is EXACT.
#   /alpha:s1        → resolves via the bare `<name>/` form   → NOT flagged
#   /alpha:ghost     → resolves to nothing                    → readme_row_dangling
#   /alpha:longname  → only a LONGER dir shares the prefix    → readme_row_dangling
#                      (the pre-review prefix-tolerant rule would have hidden it)
# beta-plugin's README cites a skill owned by ANOTHER plugin — the cross-plugin
# shape that a namespace-blind resolver would hard-ERROR on a required gate:
#   /alpha:s2 in beta-plugin/README.md → resolves in alpha-plugin → NOT flagged
mkdir -p "$fixture/alpha-plugin/skills/longname-suffix"
cat > "$fixture/alpha-plugin/README.md" <<'EOF'
# alpha-plugin

| Skill | Description |
|-------|-------------|
| `/alpha:s1` | resolves via the bare name |
| `/alpha:ghost` | phantom row — no directory |
| `/alpha:longname` | prefix-only match against longname-suffix/ |
EOF
cat > "$fixture/beta-plugin/README.md" <<'EOF'
# beta-plugin

| Skill | Description |
|-------|-------------|
| `/alpha:s2` | legitimate cross-plugin row |
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

echo "=== TEST H: committed .svg vs .d2 source, and --strict gates on it (#2453) ==="
assert "beta .svg label disagreeing with the .d2 should be flagged diagram_svg_stale" \
  "$(contains "$fx_out" "diagram_svg_stale.*renders beta as '1 skills'")"
assert "a .d2 node absent from the .svg should be flagged diagram_svg_node_missing" \
  "$(contains "$fx_out" "diagram_svg_node_missing.*command-analytics")"
assert "alpha .svg label matching the .d2 should NOT be flagged" \
  "$([ "$(contains "$fx_out" "diagram_svg_stale.*renders alpha")" = "false" ] && echo true || echo false)"
assert "DIAGRAM_SVG_NODES should count the .d2 nodes compared (3)" \
  "$([ "$(field "$fx_out" DIAGRAM_SVG_NODES)" = "3" ] && echo true || echo false)"
assert "diagram_svg_stale must be ERROR, not WARN, so --strict can gate it" \
  "$(contains "$fx_out" "SEVERITY=ERROR TYPE=diagram_svg_stale")"

# The #2450 shape end-to-end: a repo whose ONLY drift is a stale .svg must exit
# non-zero under --strict. Before this check the same repo exited 0 (WARN-free
# STATUS=OK), so a .d2 edit landed without re-rendering merged green.
svg_fx="$(mktemp -d)"
mkdir -p "$svg_fx/.claude/rules" "$svg_fx/.claude-plugin" "$svg_fx/docs/diagrams" \
  "$svg_fx/alpha-plugin/skills/s1" "$svg_fx/alpha-plugin/agents" \
  "$svg_fx/beta-plugin/skills/s1"
printf '# s\n' > "$svg_fx/alpha-plugin/skills/s1/SKILL.md"
printf '# a\n' > "$svg_fx/alpha-plugin/agents/a1.md"
printf '# s\n' > "$svg_fx/beta-plugin/skills/s1/skill.md"
cat > "$svg_fx/.claude/rules/indexed.md" <<'EOF'
---
created: 2026-08-21
modified: 2026-08-21
reviewed: 2026-08-21
---

# Indexed rule
EOF
cat > "$svg_fx/CLAUDE.md" <<'EOF'
# Rules
| Rule | Purpose |
|------|---------|
| `.claude/rules/indexed.md` | listed |
EOF
printf '{ "name": "m", "plugins": [ {"name": "alpha-plugin"}, {"name": "beta-plugin"} ] }\n' \
  > "$svg_fx/.claude-plugin/marketplace.json"
printf '{ "packages": { "alpha-plugin": {}, "beta-plugin": {} } }\n' > "$svg_fx/release-please-config.json"
printf '{ "alpha-plugin": "1.0.0", "beta-plugin": "1.0.0" }\n' > "$svg_fx/.release-please-manifest.json"
printf 'Navigation guide for 2 plugins and 2+ skills. Start here.\n\nalpha-plugin, beta-plugin\n' \
  > "$svg_fx/docs/PLUGIN-MAP.md"
cat > "$svg_fx/README.md" <<'EOF'
A curated collection of 2 Claude Code plugins providing 2+ skills and 1 agents for development workflows.

| Plugin | Skills | Description |
|--------|--------|-------------|
| **alpha-plugin** | 1 | correct |
| **beta-plugin** | 1 | correct |
EOF
cat > "$svg_fx/docs/diagrams/plugin-relationships.d2" <<'EOF'
alpha: {
  label: "alpha\n1 skills + 1 agent"
}
beta: {
  label: "beta\n1 skills"
}
EOF
cat > "$svg_fx/docs/diagrams/plugin-relationships.svg" <<'EOF'
<?xml version="1.0" encoding="utf-8"?><svg xmlns="http://www.w3.org/2000/svg" data-d2-version="v0.7.1"><text><tspan x="1.0" y="1.0">alpha</tspan><tspan x="1.0" dy="18.5">1 skills + 1 agent</tspan></text><text><tspan x="2.0" y="2.0">beta</tspan><tspan x="2.0" dy="18.5">1 skills</tspan></text></svg>
EOF
# Confirm the fixture is green FIRST, so the red below is attributable to the
# .d2 edit alone.
healed_rc=0
bash "$checker" --project-dir "$svg_fx" --strict >/dev/null || healed_rc=$?
assert "fixture whose .svg agrees with its .d2 should exit 0 under --strict" \
  "$([ "$healed_rc" -eq 0 ] && echo true || echo false)"

# Now the #2450 move: grow a skill, bump the .d2 count and the README /
# PLUGIN-MAP totals that track it, but do NOT re-render the .svg.
mkdir -p "$svg_fx/beta-plugin/skills/s2"
printf '# s\n' > "$svg_fx/beta-plugin/skills/s2/skill.md"
cat > "$svg_fx/docs/diagrams/plugin-relationships.d2" <<'EOF'
alpha: {
  label: "alpha\n1 skills + 1 agent"
}
beta: {
  label: "beta\n2 skills"
}
EOF
cat > "$svg_fx/README.md" <<'EOF'
A curated collection of 2 Claude Code plugins providing 3+ skills and 1 agents for development workflows.

| Plugin | Skills | Description |
|--------|--------|-------------|
| **alpha-plugin** | 1 | correct |
| **beta-plugin** | 2 | correct |
EOF
printf 'Navigation guide for 2 plugins and 3+ skills. Start here.\n\nalpha-plugin, beta-plugin\n' \
  > "$svg_fx/docs/PLUGIN-MAP.md"
stale_out="$(bash "$checker" --project-dir "$svg_fx")"
stale_rc=0
bash "$checker" --project-dir "$svg_fx" --strict >/dev/null || stale_rc=$?
assert "a .d2 edit committed without re-rendering should be flagged diagram_svg_stale" \
  "$(contains "$stale_out" "diagram_svg_stale.*renders beta as '1 skills'")"
assert "--strict must exit 1 when the ONLY drift is a stale .svg (the #2450 shape)" \
  "$([ "$stale_rc" -eq 1 ] && echo true || echo false)"
assert "the stale .svg must be the SOLE finding (no collateral fixture drift)" \
  "$([ "$(field "$stale_out" ISSUE_COUNT)" = "1" ] && echo true || echo false)"
rm -rf "$svg_fx"

echo "=== TEST I: README /<ns>:<name> rows resolve to a skill directory (#2453) ==="
assert "a row naming no directory should be flagged readme_row_dangling" \
  "$(contains "$fx_out" "readme_row_dangling.*lists /alpha:ghost")"
assert "resolution must be EXACT — a longer directory sharing the prefix is not a match" \
  "$(contains "$fx_out" "readme_row_dangling.*lists /alpha:longname")"
assert "a row resolving via the bare <name>/ form should NOT be flagged" \
  "$([ "$(contains "$fx_out" "readme_row_dangling.*lists /alpha:s1")" = "false" ] && echo true || echo false)"
assert "a legitimate CROSS-PLUGIN row should NOT be flagged (namespace-aware)" \
  "$([ "$(contains "$fx_out" "readme_row_dangling.*lists /alpha:s2")" = "false" ] && echo true || echo false)"
assert "readme_row_dangling must be ERROR so --strict gates it" \
  "$(contains "$fx_out" "SEVERITY=ERROR TYPE=readme_row_dangling")"
assert "README_SKILL_ROWS should count every leading-cell row scanned (4)" \
  "$([ "$(field "$fx_out" README_SKILL_ROWS)" = "4" ] && echo true || echo false)"
assert "README_ROW_PLUGINS should count the plugin READMEs contributing rows (2)" \
  "$([ "$(field "$fx_out" README_ROW_PLUGINS)" = "2" ] && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
