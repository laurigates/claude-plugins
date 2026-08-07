#!/usr/bin/env bash
# shellcheck disable=SC2015   # `cmd && pass++ || fail` — ++ exits 0, so || only fires on real failure
# Regression test for scripts/check-branch-containment-guidance.sh (issue #2268).
#
# SEMANTIC, not syntactic: every case EXECUTES the guard against a planted
# fixture tree and asserts on its structured output. A grep for the rule names
# inside the guard would pass against a guard that never runs (the #1417 →
# #1819 lesson).
#
# The fixtures reproduce the two verbatim pre-fix defects:
#   - `git-plugin/agents/git-ops.md` recommending "Prefer the encoded recipe"
#     (`just -g branch-audit`) ABOVE the correct authority ladder, uncaveated.
#   - `git-plugin/skills/deadbranch/SKILL.md` listing `merge-tree` as signal 1
#     and the MERGED-PR check as signal 2.
# Plus the pagination defect the recipe's second bug came from:
#   - `gh pr list --limit 500 --json …state,mergedAt` with no `--head`.
#
# Guard integrity is weighted as heavily as detection: a check that fires on
# everything gets disabled, and a check that scans nothing reports a vacuous OK.
# So each block also pins the NEGATIVE cases (compliant file, exact per-branch
# query, scope-discovery listing, blockquote gotcha, anti-example comment) and
# asserts the fixture was actually scanned.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-branch-containment-guidance.sh"

pass=0
fail=0

ok() { echo "  ✅ $1"; pass=$((pass + 1)); }
ko() { echo "  ❌ $1"; fail=$((fail + 1)); }

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then ok "$label"; else
    ko "$label (missing: $needle)"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then
    ko "$label (unexpectedly present: $needle)"
  else ok "$label"; fi
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" = "$expected" ]; then ok "$label"; else
    ko "$label (expected '$expected', got '$actual')"
  fi
}

run_guard() {
  bash "$GUARD" --root "$1" 2>&1
}

# ---------------------------------------------------------------------------
echo "TEST A: the real repository is clean, and was actually scanned"
# ---------------------------------------------------------------------------
out_a="$(run_guard "$REPO_ROOT")"
exit_a=$?
assert_contains "$out_a" "STATUS=OK" "A1 real repo reports STATUS=OK"
assert_eq "$exit_a" "0" "A2 real repo exits 0"
# Guard integrity. An earlier draft pruned '*/.claude/worktrees/*' against
# ABSOLUTE paths; because this repo's agent worktrees live under that very
# path, every result was pruned and the guard reported a vacuous OK over ZERO
# files. Without these two assertions A1 would have passed anyway.
scanned_git="$(grep -m1 '^GIT_PLUGIN_FILES_SCANNED=' <<<"$out_a" | cut -d= -f2)"
scanned_all="$(grep -m1 '^PLUGIN_MD_SCANNED=' <<<"$out_a" | cut -d= -f2)"
if [ "${scanned_git:-0}" -gt 0 ]; then ok "A3 git-plugin corpus is non-empty ($scanned_git files)"; else
  ko "A3 git-plugin corpus is EMPTY — the OK above is vacuous"
fi
if [ "${scanned_all:-0}" -gt 0 ]; then ok "A4 plugin markdown corpus is non-empty ($scanned_all files)"; else
  ko "A4 plugin markdown corpus is EMPTY — the OK above is vacuous"
fi

# ---------------------------------------------------------------------------
echo "TEST B: the pre-fix git-ops.md routing is caught"
# ---------------------------------------------------------------------------
fx_b="$(mktemp -d)"
[ -n "$fx_b" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$fx_b/git-plugin/agents"
cat > "$fx_b/git-plugin/agents/git-ops.md" <<'EOF'
---
name: git-ops
model: opus
---

### Branch Cleanup

Prefer the encoded recipe — it prints MERGED vs REVIEW plus a paste-ready delete:

```bash
just -g branch-audit
```

Without it, classify each branch by a signal that survives a squash-merge. In order of
authority:

```bash
gh pr list --state all --head <branch> --json state,mergedAt   # MERGED PR = authoritative
git cherry main <branch>                                        # '-' = patch already upstream
```
EOF
out_b="$(run_guard "$fx_b")"
exit_b=$?
assert_contains "$out_b" "TYPE=branch_audit_uncaveated" "B1 uncaveated branch-audit mention flagged"
assert_contains "$out_b" "TYPE=recipe_before_ladder" "B2 recipe presented before the ladder flagged"
assert_contains "$out_b" "STATUS=ERROR" "B3 STATUS=ERROR"
assert_eq "$exit_b" "1" "B4 exits 1"
rm -rf "$fx_b"

# ---------------------------------------------------------------------------
echo "TEST C: the pre-fix deadbranch merge-tree-first ordering is caught"
# ---------------------------------------------------------------------------
fx_c="$(mktemp -d)"
[ -n "$fx_c" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$fx_c/git-plugin/skills/deadbranch"
cat > "$fx_c/git-plugin/skills/deadbranch/SKILL.md" <<'EOF'
---
name: deadbranch
---

### Step 1.5: Reclassify squash-merged branches

1. **`merge-tree` no-op** — merging the branch into the base changes nothing:

   ```bash
   merged=$(git merge-tree --write-tree <base> <branch>)
   ```

2. **A MERGED PR for the branch head**:

   ```bash
   gh pr list --state all --head <branch> --json state
   ```
EOF
out_c="$(run_guard "$fx_c")"
exit_c=$?
assert_contains "$out_c" "TYPE=merge_tree_before_pr" "C1 merge-tree ranked above the MERGED-PR signal flagged"
assert_contains "$out_c" "TYPE=merge_tree_uncaveated" "C2 missing positive-containment caveat flagged"
assert_eq "$exit_c" "1" "C3 exits 1"
rm -rf "$fx_c"

# ---------------------------------------------------------------------------
echo "TEST D: guard integrity — a correctly-ordered, caveated file is clean"
# ---------------------------------------------------------------------------
# Without this, every "is flagged" assertion above would also pass against a
# guard hardwired to report an issue for any file it sees.
fx_d="$(mktemp -d)"
[ -n "$fx_d" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$fx_d/git-plugin/agents"
cat > "$fx_d/git-plugin/agents/git-ops.md" <<'EOF'
---
name: git-ops
---

### Branch Cleanup

Classify each branch with the authority ladder, in this order:

```bash
gh pr list --state all --head <branch> --json number,state,mergedAt
git cherry main <branch>
git merge-tree --write-tree main <branch>
```

The squash-merge case is why ancestry is useless here. `merge-tree` is a
positive-containment shortcut only — a match proves containment, a non-match
proves nothing.

`just -g branch-audit` is a convenience, not the authority: its REVIEW bucket
measured ~90% false on two repos (issue #2268).
EOF
out_d="$(run_guard "$fx_d")"
exit_d=$?
assert_contains "$out_d" "STATUS=OK" "D1 compliant file reports STATUS=OK"
assert_eq "$exit_d" "0" "D2 exits 0"
assert_eq "$(grep -m1 '^GIT_PLUGIN_FILES_SCANNED=' <<<"$out_d" | cut -d= -f2)" "1" "D3 the compliant fixture really was scanned"
rm -rf "$fx_d"

# ---------------------------------------------------------------------------
echo "TEST E: paginated containment determination, and its exemptions"
# ---------------------------------------------------------------------------
fx_e="$(mktemp -d)"
[ -n "$fx_e" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$fx_e/demo-plugin/skills/audit"
cat > "$fx_e/demo-plugin/skills/audit/SKILL.md" <<'EOF'
---
name: audit
---

Build the branch map:

```bash
gh pr list --state all --limit 500 --json number,headRefName,state,mergedAt
```

Exact per-branch query (immune to the default page cap):

```bash
gh pr list --state all --head "$branch" --limit 100 --json state,mergedAt
```

Scope discovery, not a containment determination:

```bash
gh pr list --state merged -L 30 --json title
```

> Gotcha: `gh pr list --state all --limit 500 --json state,mergedAt` truncates.
EOF
out_e="$(run_guard "$fx_e")"
exit_e=$?
count_e="$(grep -c 'TYPE=paginated_containment' <<<"$out_e")"
assert_eq "$count_e" "1" "E1 exactly one paginated containment determination flagged"
assert_contains "$out_e" "LINE=8" "E2 flagged the repo-wide --limit 500 line"
assert_eq "$exit_e" "1" "E3 exits 1"
# The three exemptions, asserted individually so a blanket-flagging guard fails.
assert_not_contains "$out_e" "LINE=14" "E4 exact --head query not flagged"
assert_not_contains "$out_e" "LINE=20" "E5 scope-discovery listing (--json title) not flagged"
assert_not_contains "$out_e" "LINE=23" "E6 blockquote gotcha quoting the broken form not flagged"
rm -rf "$fx_e"

# ---------------------------------------------------------------------------
echo "TEST F: a containment doc with no ladder at all is caught"
# ---------------------------------------------------------------------------
# Keeps the two ordering rules from going vacuous: deleting the authoritative
# line must not be a way to satisfy "merge-tree is not listed first".
fx_f="$(mktemp -d)"
[ -n "$fx_f" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$fx_f/git-plugin/skills/cleanup"
cat > "$fx_f/git-plugin/skills/cleanup/SKILL.md" <<'EOF'
---
name: cleanup
---

Reclassify squash-merged branches with `git merge-tree --write-tree main $b`.
It is a positive-containment shortcut.
EOF
out_f="$(run_guard "$fx_f")"
assert_contains "$out_f" "TYPE=ladder_missing" "F1 containment guidance without the ladder flagged"
rm -rf "$fx_f"

# ---------------------------------------------------------------------------
echo "TEST G: empty corpus is OK, unknown argument exits 2"
# ---------------------------------------------------------------------------
# A guard that errors on an empty corpus gets disabled.
fx_g="$(mktemp -d)"
[ -n "$fx_g" ] || { echo "mktemp failed"; exit 1; }
out_g="$(run_guard "$fx_g")"
exit_g=$?
assert_contains "$out_g" "STATUS=OK" "G1 empty corpus reports STATUS=OK"
assert_eq "$exit_g" "0" "G2 empty corpus exits 0"
rm -rf "$fx_g"

out_h="$(bash "$GUARD" --only-verdictz=x 2>&1)"
exit_h=$?
assert_eq "$exit_h" "2" "G3 unknown argument exits 2 (not swallowed — #2057)"
assert_contains "$out_h" "unknown argument" "G4 unknown argument is named"
assert_not_contains "$out_h" "STATUS=" "G5 nothing is scanned after an unknown argument"

# ---------------------------------------------------------------------------
echo "TEST H: zero-scan discriminator (#2219/#2290)"
# ---------------------------------------------------------------------------
# A zero-file scan must not look like a clean scan. Plugin dirs present but
# nothing discovered is a MISFIRE (loud); no plugin dirs at all is genuinely
# nothing to check (green) — a checker that errors on a legitimately empty
# corpus gets disabled, which would make the loud case worthless.
fx_i="$(mktemp -d)"
[ -n "$fx_i" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$fx_i/git-plugin/skills/demo"      # plugin dir, deliberately no .md
out_i="$(run_guard "$fx_i")"
exit_i=$?
assert_contains "$out_i" "TYPE=nothing_scanned" "H1 plugin dirs but zero markdown is a misfire, not a clean scan"
assert_contains "$out_i" "STATUS=ERROR" "H2 misfire reports STATUS=ERROR"
assert_eq "$exit_i" "1" "H3 misfire exits 1"
rm -rf "$fx_i"

fx_j="$(mktemp -d)"
[ -n "$fx_j" ] || { echo "mktemp failed"; exit 1; }
out_j="$(run_guard "$fx_j")"
assert_contains "$out_j" "SCANNED_EMPTY=true" "H4 genuinely empty corpus is marked SCANNED_EMPTY"
assert_not_contains "$out_j" "nothing_scanned" "H5 no plugin dirs at all is NOT a misfire"
assert_contains "$out_j" "STATUS=OK" "H6 genuinely empty corpus stays STATUS=OK"
rm -rf "$fx_j"

# ---------------------------------------------------------------------------
echo "TEST I: discovery works from a worktree-shaped scan root (#2219)"
# ---------------------------------------------------------------------------
# A prune of '*/.claude/worktrees/*' matched against an ABSOLUTE scan base
# matches EVERY descendant when the root is itself an agent worktree — the
# normal state for plugin work in this repo. The whole tree is skipped and the
# guard still exits 0. This is not hypothetical: the first draft of this guard
# had exactly that bug and reported a vacuous OK over zero files.
fx_k="$(mktemp -d)"
[ -n "$fx_k" ] || { echo "mktemp failed"; exit 1; }
wt="$fx_k/repo/.claude/worktrees/agent-f00dcafe"
mkdir -p "$wt/git-plugin/agents"
cat > "$wt/git-plugin/agents/git-ops.md" <<'EOF'
---
name: git-ops
---

### Branch Cleanup

Prefer the encoded recipe:

```bash
just -g branch-audit
```

Otherwise:

```bash
gh pr list --state all --head <branch> --json state,mergedAt
```
EOF
out_k="$(run_guard "$wt")"
exit_k=$?
assert_contains "$out_k" "GIT_PLUGIN_FILES_SCANNED=1" "I1 discovers files under a worktree-shaped root"
assert_not_contains "$out_k" "SCANNED_EMPTY=true" "I2 does not claim an empty corpus"
# ...and the defect planted there must actually be caught, so the count above
# cannot be satisfied by a walk that finds the file but judges nothing.
assert_contains "$out_k" "TYPE=recipe_before_ladder" "I3 still judges the file it discovered"
assert_eq "$exit_k" "1" "I4 exits 1 on the planted defect"

# A worktree clone nested BELOW the scan root must still be pruned — the fix
# must not degrade into "never prune anything".
mkdir -p "$wt/git-plugin/.claude/worktrees/agent-cafebabe/agents"
cp "$wt/git-plugin/agents/git-ops.md" "$wt/git-plugin/.claude/worktrees/agent-cafebabe/agents/git-ops.md"
out_l="$(run_guard "$wt")"
assert_contains "$out_l" "GIT_PLUGIN_FILES_SCANNED=1" "I5 a nested worktree clone is still pruned, not double-counted"
# Scoped to the FILE= rows: the ROOT= line legitimately echoes the scan root,
# which here IS a worktree-shaped path.
assert_not_contains "$(grep 'FILE=' <<<"$out_l" || true)" ".claude/worktrees/" \
  "I6 no worktree path leaks into a reported finding"
rm -rf "$fx_k"

# ---------------------------------------------------------------------------
echo ""
echo "Passed: $pass   Failed: $fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
