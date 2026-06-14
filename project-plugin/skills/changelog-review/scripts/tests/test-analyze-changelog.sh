#!/usr/bin/env bash
# Regression tests for analyze-changelog.sh
#
# Run: bash project-plugin/skills/changelog-review/scripts/tests/test-analyze-changelog.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Covers issue #1638 (changelog-review blind to tool deprecations):
#   - A "Deprecated `TaskOutput` tool" line is counted (DEPRECATION dimension).
#   - A deprecated identifier referenced in plugin code is surfaced as a
#     candidate file — the "changelog → plugin code" bridge that the rule-doc-
#     only map lacked. This is the exact miss that left bash-antipatterns.sh
#     recommending the dead TaskOutput tool.
#   - A deprecation token NOT referenced anywhere does not raise the actionable
#     flag (no false positives).
#   - An oversized excerpt (review stall) flags STATUS=WARN.
#   - A pure feature excerpt stays STATUS=OK with no deprecation.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/analyze-changelog.sh"
PASS=0
FAIL=0

# Throwaway fake repo: one plugin hook that references the deprecated tool, plus
# a rules dir so keyword→rule-doc mapping has somewhere to point.
REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
mkdir -p "$REPO/fake-plugin/hooks" "$REPO/.claude/rules"
cat > "$REPO/fake-plugin/hooks/bash-antipatterns.sh" <<'EOF'
# REMINDER: Use the Read tool on the task-output file path.
# (The TaskOutput tool is deprecated.)
EOF
# Identifiers that appear NEAR deprecation keywords in the changelog but are not
# themselves being deprecated (the #1638 sweep false positives). Referenced here
# so that a too-loose extractor WOULD surface them — making the negative
# assertions below meaningful.
cat > "$REPO/fake-plugin/hooks/coexist.sh" <<'EOF'
# uses SendMessage between agents; reads enabledPlugins and mcpServers config
EOF
: > "$REPO/.claude/rules/skill-development.md"

run() {
  # run <excerpt-content> [extra-args...] -> sets OUT to the script's stdout
  local content="$1"; shift
  local exc; exc=$(mktemp)
  printf '%s\n' "$content" > "$exc"
  OUT=$(bash "$SCRIPT" --excerpt "$exc" --repo-dir "$REPO" --tracked 2.1.76 --latest 2.1.138 "$@")
  rm -f "$exc"
}

field() { echo "$OUT" | grep -E "^$1=" | head -1 | cut -d= -f2-; }

assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (want '%s', got '%s')\n" "$desc" "$want" "$got"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2"
  if echo "$OUT" | grep -qF "$needle"; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (output missing: %s)\n" "$desc" "$needle"; FAIL=$((FAIL + 1))
  fi
}

assert_absent() {
  local desc="$1" needle="$2"
  if echo "$OUT" | grep -qF "$needle"; then
    printf "  FAIL: %s (output unexpectedly contains: %s)\n" "$desc" "$needle"; FAIL=$((FAIL + 1))
  else
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  fi
}

echo "=== analyze-changelog.sh tests ==="

# ── deprecation referenced in plugin code (the #1638 miss) ───────────────────
echo ""
echo "deprecated tool referenced in plugin code is surfaced as a candidate:"
run "## 2.1.83
- Deprecated \`TaskOutput\` tool in favor of using \`Read\` on the background task's output file path"

assert_eq "DEPRECATION dimension counts the line" "1" "$(field DEPRECATION)"
assert_eq "ACTIONABLE_DEPRECATION raised" "1" "$(field ACTIONABLE_DEPRECATION)"
assert_contains "DEPRECATED_TOKENS names TaskOutput" "DEPRECATED_TOKENS=TaskOutput"
assert_contains "candidate surfaces the referencing hook file" "fake-plugin/hooks/bash-antipatterns.sh"
assert_eq "STATUS is WARN for an actionable deprecation" "WARN" "$(field STATUS)"
assert_contains "issue row explains the actionable deprecation" "TYPE=actionable_deprecation"

# ── deprecation of an unreferenced identifier → no false positive ────────────
echo ""
echo "deprecation of an identifier absent from the repo does not raise the flag:"
run "## 2.1.99
- Deprecated \`SomeNonexistentTool\` in favor of the new flow"

assert_eq "DEPRECATION still counted" "1" "$(field DEPRECATION)"
assert_eq "ACTIONABLE_DEPRECATION stays 0 (token not in repo)" "0" "$(field ACTIONABLE_DEPRECATION)"
assert_absent "no fake-plugin candidate surfaced" "fake-plugin/hooks"

# ── verb-anchored extraction rejects co-located non-deprecations (#1638 sweep) ─
# Real shapes from the 2.1.138→2.1.176 sweep where a deprecation keyword sat on
# the same line as a live identifier that was NOT being deprecated.
echo ""
echo "co-located identifiers (not the deprecation subject) do not raise the flag:"
run "## 2.1.166
- Hardened cross-session messaging: messages relayed via \`SendMessage\` from other Claude sessions no longer carry user authority
## 2.1.153
- \`--strict-mcp-config\` no longer strips inline \`mcpServers\` from explicitly-passed agent definitions
## 2.1.152
- Fixed /doctor reporting for stale \`enabledPlugins\` entries referencing removed marketplaces or dropped plugins"

assert_eq "DEPRECATION count still fires on the coarse keywords" "3" "$(field DEPRECATION)"
assert_eq "ACTIONABLE_DEPRECATION stays 0 (none is the deprecation subject)" "0" "$(field ACTIONABLE_DEPRECATION)"
assert_absent "SendMessage not surfaced as a candidate" "coexist.sh"

# Counterpart true positive: the same verb-first shape that the sweep correctly
# caught (an env var that was genuinely removed) still surfaces.
run "## 2.1.160
- Removed \`TaskOutput\`; it is now a no-op"
assert_eq "verb-first 'Removed \`X\`' still raises the flag" "1" "$(field ACTIONABLE_DEPRECATION)"
assert_contains "the removed identifier is surfaced" "DEPRECATED_TOKENS=TaskOutput"

# ── oversized batch (review stall) flags WARN ────────────────────────────────
echo ""
echo "oversized excerpt (review stall) flags STATUS=WARN:"
run "## 2.1.05
- New feature
## 2.1.04
- New feature
## 2.1.03
- New feature" --max-versions 2

assert_eq "VERSION_COUNT counts the headings" "3" "$(field VERSION_COUNT)"
assert_eq "STATUS WARN on oversized batch" "WARN" "$(field STATUS)"
assert_contains "issue row explains the oversized batch" "TYPE=oversized_batch"

# ── pure feature excerpt stays clean ─────────────────────────────────────────
echo ""
echo "a pure feature excerpt has no deprecation and stays OK:"
run "## 2.1.90
- Added a new /color command for per-session prompt bar color"

assert_eq "DEPRECATION is 0" "0" "$(field DEPRECATION)"
assert_eq "ACTIONABLE_DEPRECATION is 0" "0" "$(field ACTIONABLE_DEPRECATION)"
assert_eq "STATUS OK" "OK" "$(field STATUS)"

# ── keyword → rule-doc mapping preserved ─────────────────────────────────────
echo ""
echo "keyword hits still map to rule-doc candidates:"
run "## 2.1.50
- New hook events: WorktreeCreate, TaskCompleted
- New permission model for subagents"

assert_contains "hook keyword maps to hooks-reference.md" ".claude/rules/hooks-reference.md"
assert_contains "agent keyword maps to agent-development.md" ".claude/rules/agent-development.md"
assert_contains "permission keyword maps to agentic-permissions.md" ".claude/rules/agentic-permissions.md"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
