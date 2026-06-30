#!/usr/bin/env bash
# Regression test for scripts/check-plugin-readme-currency.sh
#
# Per .claude/rules/regression-testing.md: the advisory nudge ships with a test
# proving its semantic invariant — it nudges exactly when a plugin's
# skills/agents/.claude-plugin change without that plugin's README.md being
# staged in the same commit, and stays silent otherwise. Uses the
# PLUGIN_README_CURRENCY_STAGED test seam so it never touches git state.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")/.." && pwd)"
check="$script_dir/check-plugin-readme-currency.sh"

pass=0
fail=0

ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }

# run <staged-newline-list> [env-assignments...] -> echoes script stdout
run() {
  PLUGIN_README_CURRENCY_STAGED="$1" bash "$check"
}

assert_has() {
  # assert_has <desc> <text> <needle>
  if printf '%s' "$2" | grep -q -- "$3"; then ok "$1"; else ko "$1"; fi
}

assert_lacks() {
  # assert_lacks <desc> <text> <needle>
  if printf '%s' "$2" | grep -q -- "$3"; then ko "$1"; else ok "$1"; fi
}

assert_exit0() {
  # assert_exit0 <desc> <staged-list>
  if PLUGIN_README_CURRENCY_STAGED="$2" bash "$check" >/dev/null 2>&1; then
    ok "$1"
  else
    ko "$1"
  fi
}

# --- TEST A: skill changed, README not staged -> NUDGE ------------------------
out_a="$(run $'git-plugin/skills/git-foo/SKILL.md\ngit-plugin/skills/git-foo/REFERENCE.md')"
assert_has "A: nudges when skill changes without README" "$out_a" "STATUS=WARN"
assert_has "A: reports one missing README update" "$out_a" "PLUGINS_MISSING_README_UPDATE=1"
assert_has "A: names the plugin in the nudge" "$out_a" "PLUGIN=git-plugin"
assert_has "A: emits the human NUDGE banner" "$out_a" "NUDGE:"
assert_exit0 "A: still exits 0 (advisory, never blocks)" $'git-plugin/skills/git-foo/SKILL.md'

# --- TEST B: skill changed AND README staged -> no nudge ----------------------
out_b="$(run $'git-plugin/skills/git-foo/SKILL.md\ngit-plugin/README.md')"
assert_has "B: clean when README staged alongside skill" "$out_b" "STATUS=OK"
assert_has "B: zero missing README updates" "$out_b" "PLUGINS_MISSING_README_UPDATE=0"
assert_has "B: counts the plugin as changed" "$out_b" "PLUGINS_CHANGED=1"
assert_lacks "B: emits no nudge banner" "$out_b" "NUDGE:"

# --- TEST C: agents/ and .claude-plugin/ are substantive too ------------------
out_c1="$(run $'git-plugin/agents/git-ops.md')"
assert_has "C1: agents/ change triggers nudge" "$out_c1" "STATUS=WARN"
out_c2="$(run $'git-plugin/.claude-plugin/plugin.json')"
assert_has "C2: .claude-plugin/ change triggers nudge" "$out_c2" "STATUS=WARN"

# --- TEST D: non-substantive plugin changes do NOT nudge ----------------------
# CHANGELOG.md (release-please) and a bare README edit are not substantive.
out_d1="$(run $'git-plugin/CHANGELOG.md')"
assert_has "D1: CHANGELOG-only change does not nudge" "$out_d1" "STATUS=OK"
assert_has "D1: CHANGELOG-only counts no plugin changed" "$out_d1" "PLUGINS_CHANGED=0"
out_d2="$(run $'git-plugin/README.md')"
assert_has "D2: README-only edit does not nudge" "$out_d2" "STATUS=OK"

# --- TEST E: repo-level .claude-plugin/ marketplace dir is ignored ------------
# `.claude-plugin/marketplace.json` matches the *-plugin glob but is not a
# plugin — the dot-dir guard must skip it.
out_e="$(run $'.claude-plugin/marketplace.json')"
assert_has "E: repo-level .claude-plugin/ is not treated as a plugin" "$out_e" "PLUGINS_CHANGED=0"
assert_has "E: repo-level .claude-plugin/ stays OK" "$out_e" "STATUS=OK"

# --- TEST F: multiple plugins, mixed README state -----------------------------
out_f="$(run $'alpha-plugin/skills/a/SKILL.md\nbeta-plugin/agents/b.md\nbeta-plugin/README.md')"
assert_has "F: two plugins changed" "$out_f" "PLUGINS_CHANGED=2"
assert_has "F: only alpha-plugin missing README update" "$out_f" "PLUGINS_MISSING_README_UPDATE=1"
assert_has "F: alpha-plugin named in issues" "$out_f" "PLUGIN=alpha-plugin"
assert_lacks "F: beta-plugin (README staged) not flagged" "$out_f" "PLUGIN=beta-plugin"

# --- TEST G: opt-out env disables the nudge -----------------------------------
out_g="$(CLAUDE_HOOKS_DISABLE_README_CURRENCY=1 PLUGIN_README_CURRENCY_STAGED=$'git-plugin/skills/git-foo/SKILL.md' bash "$check")"
assert_has "G: opt-out reports DISABLED=true" "$out_g" "DISABLED=true"
assert_has "G: opt-out stays STATUS=OK" "$out_g" "STATUS=OK"
assert_lacks "G: opt-out emits no nudge" "$out_g" "NUDGE:"

# --- TEST H: empty staged set is a clean no-op --------------------------------
out_h="$(run '')"
assert_has "H: empty staged set is OK" "$out_h" "STATUS=OK"
assert_has "H: empty staged set counts nothing" "$out_h" "PLUGINS_CHANGED=0"

echo
echo "=== check-plugin-readme-currency: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
