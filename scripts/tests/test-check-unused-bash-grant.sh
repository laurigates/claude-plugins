#!/usr/bin/env bash
# shellcheck disable=SC2016   # file-level: fixture bodies are deliberate literals
#                             # (backticked Context commands, ```bash fences) and
#                             # must NOT expand. Must precede the first command.
# Regression test for scripts/check-unused-bash-grant.sh.
#
# SEMANTIC, not syntactic: it EXECUTES the checker against planted fixture trees
# rather than grepping the script for its rules (the #1417 → #1819 lesson — a
# syntactic pin on a semantic property let a broken command ship twice).
#
# The load-bearing cases are the ones where the finding count swings hardest.
# On the real corpus, "unlabeled fences count" and "an inline command must match
# a KNOWN-command list rather than any-word-plus-arg" are what separate ~5
# findings from ~50: too strict and every diagram-only skill passes, too loose
# and every prose skill counts as running shell.
#
# Guard integrity: several assertions below would pass against a checker that
# silently found nothing at all, so each "no findings" case is paired with a
# positive-control assertion (BASH_GRANTEES > 0) proving the checker actually
# parsed the fixture.

set -uo pipefail

# Neutralise inherited git context so no sandbox op can reach the shared
# checkout (#1745). The checker calls `git rev-parse --show-toplevel`.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
CHECK="$repo_root/scripts/check-unused-bash-grant.sh"

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

# make_fixture <root> <plugin/skill-name> <allowed-tools> <body-file-content>
make_skill() {
  local root="$1" rel="$2" tools="$3" body="$4"
  local dir="$root/$rel"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf -- 'name: %s\n' "$(basename "$rel")"
    printf -- 'description: Fixture skill. Use when testing.\n'
    printf -- 'allowed-tools: %s\n' "$tools"
    printf -- '---\n\n'
    printf -- '# Fixture\n\n'
    printf -- '%s\n' "$body"
  } > "$dir/SKILL.md"
}

# run_check <root> [extra args...] -> stdout in $OUT, exit in $RC
OUT=""; RC=0
run_check() {
  local root="$1"; shift
  OUT="$(bash "$CHECK" --project-dir "$root" "$@" 2>/dev/null)"
  RC=$?
}

field() { grep -m1 "^$1=" <<<"$OUT" | cut -d= -f2-; }
flagged() { grep -q "SKILL=.*$1" <<<"$OUT" && echo true || echo false; }

sandbox=$(mktemp -d) || exit 1
[ -n "$sandbox" ] || exit 1
trap 'rm -rf "$sandbox"' EXIT

##########
# A. Empty corpus -> STATUS=OK, exit 0
##########
# A checker that errors on an empty corpus gets disabled. Must hold under
# --strict too, or the eventual blocking flip breaks every unrelated repo.
empty="$sandbox/empty"; mkdir -p "$empty"
run_check "$empty"
echo "=== A: empty corpus ==="
assert "A1 empty corpus STATUS=OK"   "$([ "$(field STATUS)" = "OK" ] && echo true || echo false)"
assert "A2 empty corpus ISSUE_COUNT=0" "$([ "$(field ISSUE_COUNT)" = "0" ] && echo true || echo false)"
assert "A3 empty corpus exits 0"     "$([ "$RC" -eq 0 ] && echo true || echo false)"
run_check "$empty" --strict
assert "A4 empty corpus exits 0 even under --strict" "$([ "$RC" -eq 0 ] && echo true || echo false)"

##########
# B. Unknown argument -> exit 2, usage on stderr, NOTHING on stdout
##########
# #2057: a swallowed flag turned a bounded operation unbounded. Fail fast.
echo "=== B: unknown argument ==="
b_out="$(bash "$CHECK" --project-dir "$empty" --bogus-flag 2>/dev/null)"; b_rc=$?
b_err="$(bash "$CHECK" --project-dir "$empty" --bogus-flag 2>&1 >/dev/null)"
assert "B1 unknown arg exits 2"          "$([ "$b_rc" -eq 2 ] && echo true || echo false)"
assert "B2 unknown arg prints nothing to stdout" "$([ -z "$b_out" ] && echo true || echo false)"
assert "B3 unknown arg names the flag on stderr" "$(grep -q 'bogus-flag' <<<"$b_err" && echo true || echo false)"
assert "B4 unknown arg prints usage on stderr"   "$(grep -q 'Usage:' <<<"$b_err" && echo true || echo false)"

##########
# C. The detection matrix
##########
c="$sandbox/c"
# C1 unlabeled fence carrying a real command -> NOT flagged (30 real skills
#    carry their only commands this way)
make_skill "$c" "x-plugin/skills/unlabeled-fence" "Bash, Read" '```
git status --porcelain
```'
# C2 .venv/-prefixed interpreter in an unlabeled fence -> NOT flagged
make_skill "$c" "x-plugin/skills/venv-path" "Bash, Read" '```
.venv/bin/python scripts/layout_workflow.py in.json
```'
# C3 PLACEHOLDER-prefixed interpreter -> NOT flagged. This is a real false
#    positive the first implementation produced against
#    comfyui-plugin/skills/comfy-subgraphs-app-mode.
make_skill "$c" "x-plugin/skills/placeholder-path" "Bash, Read" '```sh
<venv>/bin/python -c "import x; print(x.__version__)"
```'
# C4 a fence of ONLY /slash:commands and comments -> FLAGGED (the real
#    testing-plugin/skills/test-tier-selection shape)
make_skill "$c" "x-plugin/skills/slash-only" "Bash, Read" '```bash
# Tier 1
/test:quick
/test:full --coverage
```'
# C5 an ASCII DIAGRAM in an unlabeled fence -> FLAGGED (4 real comfyui skills)
make_skill "$c" "x-plugin/skills/diagram-only" "Bash, Read" '```
Router ──► Shadow
   │
   ▼
```'
# C6 a skill with a sibling scripts/ dir -> NOT flagged even with no fences
make_skill "$c" "x-plugin/skills/has-scripts" "Bash, Read" 'Prose only, no fences.'
mkdir -p "$c/x-plugin/skills/has-scripts/scripts"
printf '#!/usr/bin/env bash\necho hi\n' > "$c/x-plugin/skills/has-scripts/scripts/run.sh"
# C7 a !`…` Context command -> NOT flagged
make_skill "$c" "x-plugin/skills/context-cmd" "Bash, Read" '## Context

- Status: !`git status --porcelain`'
# C8 shell only in a BUNDLED SIDECAR -> NOT flagged (progressive disclosure;
#    measuring SKILL.md alone makes agent-patterns:mcp-code-execution look inert)
make_skill "$c" "x-plugin/skills/sidecar-only" "Bash, Read" 'See REFERENCE.md.'
printf '# Reference\n\n```bash\nuv run scaffold.py --init\n```\n' > "$c/x-plugin/skills/sidecar-only/REFERENCE.md"
# C9 NO Bash grant at all + no shell -> never a finding (only grantees matter)
make_skill "$c" "x-plugin/skills/no-grant" "Read, Grep" 'Prose only.'
# C10 a scoped Bash(...) grant is not a BARE grant -> out of scope
make_skill "$c" "x-plugin/skills/scoped-grant" "Bash(git status *), Read" 'Prose only.'

run_check "$c"
echo "=== C: detection matrix (ISSUE_COUNT=$(field ISSUE_COUNT)) ==="
# Guard integrity FIRST: without this, every "not flagged" assertion below would
# also pass against a checker that parsed nothing.
assert "C0a positive control: grantees were actually found" \
  "$([ "$(field BASH_GRANTEES)" -ge 8 ] 2>/dev/null && echo true || echo false)"
assert "C0b positive control: the checker scanned every fixture skill" \
  "$([ "$(field SKILLS_SCANNED)" -eq 10 ] 2>/dev/null && echo true || echo false)"

assert "C1 unlabeled fence with a real command is NOT flagged" \
  "$([ "$(flagged 'unlabeled-fence')" = "false" ] && echo true || echo false)"
assert "C2 .venv/bin/python is NOT flagged" \
  "$([ "$(flagged 'venv-path')" = "false" ] && echo true || echo false)"
assert "C3 <placeholder>/bin/python is NOT flagged" \
  "$([ "$(flagged 'placeholder-path')" = "false" ] && echo true || echo false)"
assert "C4 a fence of only /slash:commands IS flagged" \
  "$([ "$(flagged 'slash-only')" = "true" ] && echo true || echo false)"
assert "C5 an ASCII diagram in an unlabeled fence IS flagged" \
  "$([ "$(flagged 'diagram-only')" = "true" ] && echo true || echo false)"
assert "C6 a sibling scripts/ dir means NOT flagged" \
  "$([ "$(flagged 'has-scripts')" = "false" ] && echo true || echo false)"
assert "C7 a !\`…\` context command means NOT flagged" \
  "$([ "$(flagged 'context-cmd')" = "false" ] && echo true || echo false)"
assert "C8 shell in a bundled sidecar means NOT flagged" \
  "$([ "$(flagged 'sidecar-only')" = "false" ] && echo true || echo false)"
assert "C9 a skill with no Bash grant is never reported" \
  "$([ "$(flagged 'no-grant')" = "false" ] && echo true || echo false)"
assert "C10 a scoped Bash(...) grant is not treated as a bare grant" \
  "$([ "$(flagged 'scoped-grant')" = "false" ] && echo true || echo false)"
assert "C11 exactly the two genuinely-inert skills are reported" \
  "$([ "$(field ISSUE_COUNT)" -eq 2 ] 2>/dev/null && echo true || echo false)"
assert "C12 findings present => STATUS=WARN" \
  "$([ "$(field STATUS)" = "WARN" ] && echo true || echo false)"

##########
# D. Advisory vs --strict
##########
echo "=== D: exit-code contract ==="
run_check "$c"
assert "D1 findings exit 0 in advisory (default) mode" "$([ "$RC" -eq 0 ] && echo true || echo false)"
run_check "$c" --strict
assert "D2 findings exit 1 under --strict"             "$([ "$RC" -eq 1 ] && echo true || echo false)"

##########
# E. Allowlist seam
##########
echo "=== E: allowlist ==="
OUT="$(CHECK_UNUSED_BASH_GRANT_ALLOWLIST="x-plugin/skills/diagram-only" bash "$CHECK" --project-dir "$c" 2>/dev/null)"; RC=$?
assert "E1 an allowlisted skill drops out of the findings" \
  "$([ "$(field ISSUE_COUNT)" -eq 1 ] 2>/dev/null && echo true || echo false)"
assert "E2 the exemption is counted, not silent" \
  "$([ "$(field EXEMPTED)" -eq 1 ] 2>/dev/null && echo true || echo false)"
assert "E3 a NON-allowlisted sibling is still reported" \
  "$([ "$(flagged 'slash-only')" = "true" ] && echo true || echo false)"

##########
# F. Worktree / dist pruning (#1492 / #1548 / #2214)
##########
# A .claude/worktrees/ clone and a dist/ export are copies of the same skills.
# Scanning either double-counts and can re-report the same finding.
#
# The copies MUST be planted INSIDE a plugin directory. Discovery's outer find is
# `-maxdepth 1 -type d -name '*-plugin'`, so a clone at the repo root is never
# reachable and the prune never fires — a fixture planted there passes with or
# without the prune, i.e. it guards nothing. (Caught by mutation: deleting the
# prune left an earlier version of this suite at 35/0.)
echo "=== F: prune ==="
run_check "$c"
base_scanned="$(field SKILLS_SCANNED)"; base_issues="$(field ISSUE_COUNT)"
mkdir -p "$c/x-plugin/.claude/worktrees/agent-dead/skills/diagram-only"
cp "$c/x-plugin/skills/diagram-only/SKILL.md" "$c/x-plugin/.claude/worktrees/agent-dead/skills/diagram-only/SKILL.md"
mkdir -p "$c/x-plugin/dist/opencode/skills/diagram-only"
cp "$c/x-plugin/skills/diagram-only/SKILL.md" "$c/x-plugin/dist/opencode/skills/diagram-only/SKILL.md"
run_check "$c"
assert "F1 a .claude/worktrees/ + dist/ copy does not change SKILLS_SCANNED" \
  "$([ "$(field SKILLS_SCANNED)" = "$base_scanned" ] && echo true || echo false)"
assert "F2 a .claude/worktrees/ + dist/ copy does not change ISSUE_COUNT" \
  "$([ "$(field ISSUE_COUNT)" = "$base_issues" ] && echo true || echo false)"
assert "F3 no .claude/worktrees/ path leaks into the report" \
  "$(grep -q '\.claude/worktrees' <<<"$OUT" && echo false || echo true)"
assert "F4 no dist/ path leaks into the report" \
  "$(grep -q 'dist/' <<<"$OUT" && echo false || echo true)"

##########
# G. Structured-output contract
##########
echo "=== G: output contract ==="
run_check "$c"
assert "G1 emits the section header"  "$(grep -q '^=== UNUSED BASH GRANT ===$' <<<"$OUT" && echo true || echo false)"
assert "G2 emits the section footer"  "$(grep -q '^=== END UNUSED BASH GRANT ===$' <<<"$OUT" && echo true || echo false)"
assert "G3 emits ISSUE_COUNT even when non-zero" "$(grep -q '^ISSUE_COUNT=' <<<"$OUT" && echo true || echo false)"
assert "G4 emits an ISSUES: block when findings exist" "$(grep -q '^ISSUES:$' <<<"$OUT" && echo true || echo false)"

echo ""
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
