#!/usr/bin/env bash
# Regression test for scripts/check-context-command-execution.sh — the semantic
# execution harness for SKILL.md `## Context` backtick commands.
#
# Guards:
#   A. a hardcoded-file grep (the /configure:all abort class) is reported FAIL
#      and --strict exits 1
#   B. the robust find -exec grep form PASSes (exit 0, empty stderr in a bare repo)
#   C. an environment gap (missing tool) is ENV_MISSING, not FAIL — so a CI box
#      lacking jq/gh never red-lights a skill
#   D. a find against a missing subdir is FAIL (the #1482 fragility class)
#   E. git history commands PASS in the sandbox (it has one commit) — no
#      false positive from a bare repo
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
harness="$repo_root/scripts/check-context-command-execution.sh"

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

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/skills/bad-grep" "$workdir/skills/good-find" \
         "$workdir/skills/env-tool" "$workdir/skills/missing-dir" \
         "$workdir/skills/git-history"

cat > "$workdir/skills/bad-grep/SKILL.md" <<'EOF'
---
name: bad-grep
---
## Context
- Standards version: !`grep -m1 "^standards_version:" .project-standards.yaml`
EOF

cat > "$workdir/skills/good-find/SKILL.md" <<'EOF'
---
name: good-find
---
## Context
- Standards version: !`find . -maxdepth 1 -name '.project-standards.yaml' -exec grep -m1 "^standards_version:" {} +`
EOF

cat > "$workdir/skills/env-tool/SKILL.md" <<'EOF'
---
name: env-tool
---
## Context
- Tool output: !`this-tool-does-not-exist-xyz --version`
EOF

cat > "$workdir/skills/missing-dir/SKILL.md" <<'EOF'
---
name: missing-dir
---
## Context
- ADRs: !`find docs/adrs -name '*.md' -type f`
EOF

cat > "$workdir/skills/git-history/SKILL.md" <<'EOF'
---
name: git-history
---
## Context
- Commit count: !`git rev-list --count HEAD`
- Last commit: !`git log --max-count=1 --format='%h %ci'`
EOF

report() {
  bash "$harness" --repo-root "$workdir" --files "$workdir/$1" 2>/dev/null
}

# A. hardcoded-file grep → FAIL + --strict exits 1
arep="$(report skills/bad-grep/SKILL.md)"
echo "$arep" | grep -q '^FAIL=1$' && a_fail=true || a_fail=false
assert "A: hardcoded-file grep is reported FAIL" "$a_fail"
bash "$harness" --repo-root "$workdir" --files "$workdir/skills/bad-grep/SKILL.md" --strict >/dev/null 2>&1
[ $? -eq 1 ] && a_strict=true || a_strict=false
assert "A: --strict exits 1 on a FAIL" "$a_strict"

# B. robust find -exec grep → no FAIL, exit 0
brep="$(report skills/good-find/SKILL.md)"
echo "$brep" | grep -q '^FAIL=0$' && echo "$brep" | grep -q '^STATUS=OK$' && b_ok=true || b_ok=false
assert "B: find -exec grep form PASSes (FAIL=0, STATUS=OK)" "$b_ok"

# C. missing tool → ENV_MISSING, not FAIL
crep="$(report skills/env-tool/SKILL.md)"
echo "$crep" | grep -q '^ENV_MISSING=1$' && echo "$crep" | grep -q '^FAIL=0$' && c_ok=true || c_ok=false
assert "C: missing tool is ENV_MISSING, not FAIL" "$c_ok"

# D. find against a missing subdir → FAIL
drep="$(report skills/missing-dir/SKILL.md)"
echo "$drep" | grep -q '^FAIL=1$' && d_ok=true || d_ok=false
assert "D: find against a missing subdir is FAIL (#1482 class)" "$d_ok"

# E. git history commands PASS (sandbox has a commit)
erep="$(report skills/git-history/SKILL.md)"
echo "$erep" | grep -q '^FAIL=0$' && echo "$erep" | grep -q '^PASS=2$' && e_ok=true || e_ok=false
assert "E: git history commands PASS in the one-commit sandbox" "$e_ok"

echo "----"
echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
