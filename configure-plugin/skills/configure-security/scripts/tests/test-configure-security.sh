#!/usr/bin/env bash
# shellcheck disable=SC2016  # grep/sed patterns contain literal backticks/$, not expansions
# Regression test for configure-security.sh detection.
# A planted fixture WITH Dependabot + CodeQL + gitleaks + SECURITY.md must report
# all four present; a bare fixture must report them missing with STATUS=WARN.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../configure-security.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$check_script" ] || fail "configure-security.sh not found at $check_script"

# -----------------------------------------------------------------------------
# Case 1: fully-configured project → all layers present, STATUS=OK
# -----------------------------------------------------------------------------
full="$(mktemp -d)"
trap 'rm -rf "$full"' EXIT
mkdir -p "${full}/.github/workflows"
printf '{}' > "${full}/package.json"
printf 'version: 2\nupdates: []\n' > "${full}/.github/dependabot.yml"
printf 'name: CodeQL\njobs:\n  analyze:\n    steps:\n      - uses: github/codeql-action/analyze@v3\n' \
  > "${full}/.github/workflows/codeql.yml"
printf '[allowlist]\n' > "${full}/.gitleaks.toml"
printf 'repos:\n  - repo: https://github.com/gitleaks/gitleaks\n' > "${full}/.pre-commit-config.yaml"
printf '# Security Policy\n' > "${full}/SECURITY.md"

out1="$(bash "$check_script" --home-dir "$HOME" --project-dir "$full")"
echo "$out1" | grep -q "^DEPENDABOT=true$" || fail "expected DEPENDABOT=true:\n$out1"
echo "$out1" | grep -q "^CODEQL=true$" || fail "expected CODEQL=true:\n$out1"
echo "$out1" | grep -q "^GITLEAKS_CONFIG=true$" || fail "expected GITLEAKS_CONFIG=true:\n$out1"
echo "$out1" | grep -q "^SECURITY_POLICY=true$" || fail "expected SECURITY_POLICY=true:\n$out1"
echo "$out1" | grep -q "^PRE_COMMIT_GITLEAKS=true$" || fail "expected PRE_COMMIT_GITLEAKS=true:\n$out1"
echo "$out1" | grep -q "^SECURITY_LAYERS_PRESENT=3$" || fail "expected SECURITY_LAYERS_PRESENT=3:\n$out1"
echo "$out1" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK for fully-configured project:\n$out1"
echo "$out1" | grep -q "^LANG_JS=true$" || fail "expected LANG_JS=true:\n$out1"
pass "fully-configured project reports all security layers present and STATUS=OK"
rm -rf "$full"

# -----------------------------------------------------------------------------
# Case 2: bare project → all missing, STATUS=WARN
# -----------------------------------------------------------------------------
bare="$(mktemp -d)"
out2="$(bash "$check_script" --home-dir "$HOME" --project-dir "$bare")"
echo "$out2" | grep -q "^DEPENDABOT=false$" || fail "expected DEPENDABOT=false:\n$out2"
echo "$out2" | grep -q "^CODEQL=false$" || fail "expected CODEQL=false:\n$out2"
echo "$out2" | grep -q "^GITLEAKS_CONFIG=false$" || fail "expected GITLEAKS_CONFIG=false:\n$out2"
echo "$out2" | grep -q "^SECURITY_POLICY=false$" || fail "expected SECURITY_POLICY=false:\n$out2"
echo "$out2" | grep -q "^SECURITY_LAYERS_PRESENT=0$" || fail "expected SECURITY_LAYERS_PRESENT=0:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$" || fail "expected STATUS=WARN for bare project:\n$out2"
echo "$out2" | grep -q "^ISSUE_COUNT=4$" || fail "expected ISSUE_COUNT=4 for bare project:\n$out2"
pass "bare project reports all security layers missing and STATUS=WARN"
rm -rf "$bare"

# -----------------------------------------------------------------------------
# Case 3: SKILL.md `## Context` find commands must actually DETECT present files
#   (Regression, issue #1919): the commands shipped escaped single quotes
#   (`-name \'.gitleaks.toml\'`) that make find match a literal quoted filename
#   → always report MISSING even when the file exists, plus slash-in-`-name`
#   (never matches basename) and `-maxdepth` after `-path` (GNU find warns to
#   stderr → aborts the skill). This case extracts each Context find command
#   from SKILL.md, runs it against a fully-configured fixture, and asserts:
#     (a) exit 0 with EMPTY stderr (no abort), and
#     (b) NON-EMPTY output (the file is actually detected).
#   The escaped-quote / slash-in-name forms fail (b); the maxdepth-after-path
#   form fails (a) on GNU find. Also asserts the antipattern shapes are absent.
# -----------------------------------------------------------------------------
skill_md="${script_dir}/../../SKILL.md"
[ -f "$skill_md" ] || fail "SKILL.md not found at $skill_md"

# Antipattern greps over Context command lines (`^- Label: !`...``). Patterns are
# grep regexes containing literal backticks — SC2016 does not apply.
# Escaped single quotes (\'): match a literal quoted filename → always MISSING.
grep -nE "^- .*!\`[^\`]*\\\\'" "$skill_md" \
  && fail "SKILL.md Context command contains an escaped single quote (\\') — matches a literal quoted filename"
# Slash inside a -name argument: -name matches the basename only, so it never matches.
grep -nE "^- .*!\`[^\`]*-name '[^']*/" "$skill_md" \
  && fail "SKILL.md Context command uses a slash inside -name (never matches a basename)"
# -maxdepth appearing AFTER -path on one command: GNU find warns to stderr → aborts the skill.
grep -nE "^- .*!\`[^\`]*-path[^\`]*-maxdepth" "$skill_md" \
  && fail "SKILL.md Context command places -maxdepth after -path (GNU find warns to stderr, aborting the skill)"

# Fully-configured fixture — every file the Context commands probe for is present.
ctx="$(mktemp -d)"
mkdir -p "${ctx}/.github/workflows"
printf '{}' > "${ctx}/package.json"
printf 'version: 2\n' > "${ctx}/.github/dependabot.yml"
printf 'name: CodeQL\n' > "${ctx}/.github/workflows/codeql.yml"
printf '[allowlist]\n' > "${ctx}/.gitleaks.toml"
printf 'repos: []\n' > "${ctx}/.pre-commit-config.yaml"
printf '# Security Policy\n' > "${ctx}/SECURITY.md"

# Extract each `- Label: !`<cmd>`` Context find command and execute it in the fixture.
ctx_cmds="$(grep -oE '^- [^:]*: !`find[^`]*`' "$skill_md" | sed -E 's/^- [^:]*: !`//; s/`$//')"
[ -n "$ctx_cmds" ] || fail "no Context find commands extracted from SKILL.md"

ctx_count=0
while IFS= read -r ctx_cmd; do
  [ -n "$ctx_cmd" ] || continue
  ctx_count=$((ctx_count + 1))
  ctx_err="$(mktemp)"
  ctx_out="$(cd "$ctx" && eval "$ctx_cmd" 2>"$ctx_err")"
  ctx_rc=$?
  [ "$ctx_rc" -eq 0 ] || fail "Context command exited non-zero ($ctx_rc): $ctx_cmd"
  [ -s "$ctx_err" ] && fail "Context command wrote to stderr [$(cat "$ctx_err")]: $ctx_cmd"
  [ -n "$ctx_out" ] || fail "Context command detected nothing in a fully-configured project: $ctx_cmd"
  rm -f "$ctx_err"
done <<< "$ctx_cmds"

[ "$ctx_count" -ge 6 ] || fail "expected >=6 Context find commands, extracted $ctx_count"
pass "all $ctx_count SKILL.md Context find commands detect present files (exit 0, no stderr, non-empty)"
rm -rf "$ctx"

echo "ALL TESTS PASSED"
