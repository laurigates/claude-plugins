#!/usr/bin/env bash
# Regression test for analyze-skills.sh
#
# Run: bash project-plugin/skills/project-discovery/scripts/tests/test-analyze-skills.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Covers issue #1548 (analyze-skills.sh scans .claude/worktrees/ copies):
#   - A SKILL.md planted under .claude/worktrees/<name>/.../skills/ is NOT
#     counted, so TOTAL_SKILLS reflects only the real tree (not the N+1
#     inflation each linked worktree clone would add).
#   - No .claude/worktrees/ path leaks into the analyzer output.
# Same class as the #1492 worktree-prune fix for check-version-pin-coverage.sh.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/analyze-skills.sh"
PASS=0
FAIL=0

# Throwaway fake repo: one real skill, plus an identical worktree-clone copy
# that the analyzer must prune rather than double-count.
REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
mkdir -p "$REPO/demo-plugin/skills/demo"
printf '# Demo skill\n\nReal skill in the working tree.\n' \
  > "$REPO/demo-plugin/skills/demo/SKILL.md"

# A linked worktree is a full repo clone — the same skill appears again under
# .claude/worktrees/<name>/. The analyzer must not walk it.
mkdir -p "$REPO/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo"
printf '# Demo skill\n\nWorktree clone copy — must be pruned.\n' \
  > "$REPO/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo/SKILL.md"

OUT=$(bash "$SCRIPT" "$REPO")

field() { echo "$OUT" | grep -E "^$1=" | head -1 | cut -d= -f2-; }

assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (want '%s', got '%s')\n" "$desc" "$want" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "=== TEST: .claude/worktrees/ copies are pruned, not counted (#1548) ==="
assert_eq "TOTAL_SKILLS counts only the real skill (worktree clone pruned)" \
  "1" "$(field TOTAL_SKILLS)"

if echo "$OUT" | grep -q '/.claude/worktrees/'; then
  printf "  FAIL: no .claude/worktrees/ path leaks into output\n"; FAIL=$((FAIL + 1))
else
  printf "  PASS: no .claude/worktrees/ path leaks into output\n"; PASS=$((PASS + 1))
fi

echo ""
echo "=== TEST: --funnel bins script-less skills; STRONG wins over interactive (#1551) ==="
# ADR-0016 deterministic pre-filter. The load-bearing invariant (the thing the
# naive precedence got wrong): a skill carrying an AskUserQuestion confirmation
# step is NOT skipped when it also shows a strong procedural signal — every v1
# candidate had a descoped interactive step. STRONG must win over SKIP_INTERACTIVE.
FREPO=$(mktemp -d)
trap 'rm -rf "$REPO" "$FREPO"' EXIT

# (a) Strong + interactive: AskUserQuestion present AND >=2 data-processing pipes.
#     Must classify LLM_STRONG, never SKIP_INTERACTIVE.
mkdir -p "$FREPO/demo-plugin/skills/strong-interactive"
cat > "$FREPO/demo-plugin/skills/strong-interactive/SKILL.md" <<'EOF'
---
name: strong-interactive
description: Do a thing. Use when doing the thing.
---
# Strong interactive
Confirm with AskUserQuestion before applying.
```bash
gh pr list --json number | jq '.[].number'
git log --oneline | grep feat
```
EOF

# (b) Already extracted: ships scripts/ -> HAS_SCRIPTS (audit-only, not a candidate).
mkdir -p "$FREPO/demo-plugin/skills/has-scripts/scripts"
printf '# has-scripts\n' > "$FREPO/demo-plugin/skills/has-scripts/SKILL.md"
printf '#!/usr/bin/env bash\necho hi\n' > "$FREPO/demo-plugin/skills/has-scripts/scripts/run.sh"

# (c) Interactive, no procedure: AskUserQuestion, <3 shell blocks -> SKIP_INTERACTIVE.
mkdir -p "$FREPO/demo-plugin/skills/judgment"
cat > "$FREPO/demo-plugin/skills/judgment/SKILL.md" <<'EOF'
---
name: judgment
description: Decide something subjective. Use when choosing an approach.
---
# Judgment
Ask the user with AskUserQuestion and synthesize a recommendation.
EOF

FOUT=$(bash "$SCRIPT" "$FREPO" --funnel)
# Match the VERDICT row by exact skill name (field 4); awk is portable (BSD grep
# lacks -P). Row shape: VERDICT<TAB>verdict<TAB>plugin<TAB>skill<TAB>...
fverdict() { echo "$FOUT" | awk -F'\t' -v s="$1" '$1=="VERDICT" && $4==s {print $2; exit}'; }

assert_eq "strong+interactive skill is LLM_STRONG (not SKIP_INTERACTIVE)" \
  "LLM_STRONG" "$(fverdict strong-interactive)"
assert_eq "scripts/-bearing skill is HAS_SCRIPTS (audit-only)" \
  "HAS_SCRIPTS" "$(fverdict has-scripts)"
assert_eq "interactive no-procedure skill is SKIP_INTERACTIVE" \
  "SKIP_INTERACTIVE" "$(fverdict judgment)"
assert_eq "rollup STATUS is OK" "OK" "$(echo "$FOUT" | grep -E '^STATUS=' | cut -d= -f2)"
# ISSUE_COUNT is the LLM residue (STRONG+WEAK); here exactly the one STRONG skill.
assert_eq "rollup ISSUE_COUNT equals the residue (1 STRONG, 0 WEAK)" \
  "1" "$(echo "$FOUT" | grep -E '^ISSUE_COUNT=' | cut -d= -f2)"

echo ""
echo "PASS=$PASS"
echo "FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
