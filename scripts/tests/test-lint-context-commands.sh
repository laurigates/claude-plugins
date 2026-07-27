#!/usr/bin/env bash
# Regression test for scripts/lint-context-commands.sh — the regex denylist of
# known-bad SKILL.md `## Context` backtick command shapes.
#
# Guards:
#   A. a Context `which <tool>` probe is reported ERROR under rule
#      `which-in-context` and the script exits 1 (issue #2145 — `which` exits 1
#      silently when the tool is absent, aborting the skill before its body runs)
#   B. `which` outside a Context command line (fenced code, prose, a table cell)
#      is NOT flagged — the rule is anchored to `^- ...!\`...\``
#   C. a clean Context block exits 0 with no findings (guard integrity: the
#      new rule does not fire on everything)
#   D. the pre-existing `command-v-in-context` rule (#1205) still fires — a
#      sibling rule was not broken by the addition
#   E. the REAL repo has no `which` left in any Context block — pins the
#      project-init fix so a revert is caught
#
# The linter greps relative to its cwd, so each fixture is exercised by running
# it from a throwaway directory containing only that fixture.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
linter="$repo_root/scripts/lint-context-commands.sh"

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
if [ -z "$workdir" ] || [ ! -d "$workdir" ]; then
  echo "invalid workdir: '$workdir'" >&2
  exit 1
fi
trap 'rm -rf "$workdir"' EXIT

mkdir -p "$workdir/which-ctx/skills/probe" \
         "$workdir/which-body/skills/probe" \
         "$workdir/clean/skills/probe" \
         "$workdir/command-v/skills/probe"

# A fixture: the #2145 shape, verbatim.
cat > "$workdir/which-ctx/skills/probe/SKILL.md" <<'EOF'
---
name: probe
---
## Context

- Current directory: !`pwd`
- GitHub CLI: !`which gh`
EOF

# B fixture: `which` appears only in a fenced block, in prose, and in a table —
# never as a `- Label: !`cmd`` Context command.
cat > "$workdir/which-body/skills/probe/SKILL.md" <<'EOF'
---
name: probe
---
## Context

- Current directory: !`pwd`

## GitHub CLI Availability

Run `which gh` via the Bash tool, where a non-zero exit is survivable.

```bash
which gh
```

| Command | Meaning |
|---------|---------|
| `which gh` | prints the path, exits 1 when absent |
EOF

# C fixture: a clean Context block.
cat > "$workdir/clean/skills/probe/SKILL.md" <<'EOF'
---
name: probe
---
## Context

- Current directory: !`pwd`
- Workflows: !`find .github/workflows -maxdepth 1 -name '*.yml'`
EOF

# D fixture: the pre-existing #1205 shape.
cat > "$workdir/command-v/skills/probe/SKILL.md" <<'EOF'
---
name: probe
---
## Context

- Task CLI: !`command -v task`
EOF

run_lint() {
  # Run the linter with the fixture dir as cwd; capture output and exit code.
  ( cd "$workdir/$1" && bash "$linter" 2>&1 )
}
lint_rc() {
  ( cd "$workdir/$1" && bash "$linter" >/dev/null 2>&1 )
  echo $?
}

# A. Context `which` → ERROR [which-in-context], exit 1
a_out="$(run_lint which-ctx)"
a_rc="$(lint_rc which-ctx)"
grep -q 'ERROR \[which-in-context\]' <<<"$a_out" && [ "$a_rc" -eq 1 ] && a_ok=true || a_ok=false
assert "A: Context \`which gh\` is ERROR [which-in-context] and exits 1 (#2145)" "$a_ok"

# B. `which` outside a Context command → not flagged
b_out="$(run_lint which-body)"
b_rc="$(lint_rc which-body)"
grep -q 'which-in-context' <<<"$b_out" && b_ok=false || b_ok=true
[ "$b_rc" -eq 0 ] || b_ok=false
assert "B: \`which\` in fenced code / prose / a table is NOT flagged" "$b_ok"

# C. clean Context block → no findings, exit 0
c_out="$(run_lint clean)"
c_rc="$(lint_rc clean)"
grep -q 'All context commands OK' <<<"$c_out" && [ "$c_rc" -eq 0 ] && c_ok=true || c_ok=false
assert "C: a clean Context block exits 0 with no findings" "$c_ok"

# D. sibling rule still fires
d_out="$(run_lint command-v)"
grep -q 'ERROR \[command-v-in-context\]' <<<"$d_out" && d_ok=true || d_ok=false
assert "D: pre-existing command-v-in-context rule still fires (#1205)" "$d_ok"

# E. the real repo carries no Context `which` (pins the project-init fix)
e_out="$( cd "$repo_root" && bash "$linter" 2>&1 )"
grep -q 'which-in-context' <<<"$e_out" && e_ok=false || e_ok=true
assert "E: no \`which\` remains in any Context block repo-wide" "$e_ok"

echo "----"
echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
