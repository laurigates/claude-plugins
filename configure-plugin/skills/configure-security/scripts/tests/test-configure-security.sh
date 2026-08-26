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
# Guard integrity for the Renovate cases below: a project with NEITHER tool must
# still warn. Without this, a script that never warns passes every case in the
# "no warning" direction.
echo "$out2" | grep -q "^RENOVATE=false$" || fail "expected RENOVATE=false:\n$out2"
echo "$out2" | grep -q "^DEPENDENCY_AUTOMATION=false$" || fail "expected DEPENDENCY_AUTOMATION=false:\n$out2"
echo "$out2" | grep -q "TYPE=missing_dependency_automation" \
  || fail "expected the dependency-automation warning for a bare project:\n$out2"
pass "bare project reports all security layers missing and STATUS=WARN"
rm -rf "$bare"

# -----------------------------------------------------------------------------
# Case 2a: Renovate-only project → dependency-automation layer SATISFIED
#   (Regression, issue #2495): the check warned `missing_dependabot` on repos
#   that already run Renovate, so acting on the report installed a second
#   dependency bot that races Renovate on lockfiles. Renovate and Dependabot are
#   alternatives — either satisfies the layer.
#   Semantic: executes the real script and asserts the emitted KEY=VALUE output.
# -----------------------------------------------------------------------------
assert_renovate_only() {
  # $1 = fixture dir, $2 = human label for the config form under test
  local ro_dir="$1" ro_label="$2" ro_out
  ro_out="$(bash "$check_script" --home-dir "$HOME" --project-dir "$ro_dir")"
  echo "$ro_out" | grep -q "^RENOVATE=true$" \
    || fail "expected RENOVATE=true for $ro_label:\n$ro_out"
  echo "$ro_out" | grep -q "^DEPENDABOT=false$" \
    || fail "expected DEPENDABOT=false for $ro_label:\n$ro_out"
  echo "$ro_out" | grep -q "^DEPENDENCY_AUTOMATION=true$" \
    || fail "expected DEPENDENCY_AUTOMATION=true for $ro_label:\n$ro_out"
  # The layer is counted even though Dependabot is absent.
  echo "$ro_out" | grep -q "^SECURITY_LAYERS_PRESENT=1$" \
    || fail "expected SECURITY_LAYERS_PRESENT=1 for $ro_label:\n$ro_out"
  # ...and no warning is raised about it.
  if echo "$ro_out" | grep -q "TYPE=missing_dependency_automation"; then
    fail "dependency-automation warning must be ABSENT for $ro_label:\n$ro_out"
  fi
  if echo "$ro_out" | grep -q "missing_dependabot"; then
    fail "the retired missing_dependabot token must not reappear for $ro_label:\n$ro_out"
  fi
  # Only the three genuinely-missing layers remain (sast, secrets, policy).
  echo "$ro_out" | grep -q "^ISSUE_COUNT=3$" \
    || fail "expected ISSUE_COUNT=3 for $ro_label:\n$ro_out"
}

# Root renovate.json, no .github/dependabot.yml anywhere.
ren="$(mktemp -d)"
printf '{"extends":["config:recommended"]}\n' > "${ren}/renovate.json"
assert_renovate_only "$ren" "root renovate.json"
rm -rf "$ren"

# A non-root config location, to pin the whole candidate list rather than one path.
ren_gh="$(mktemp -d)"
mkdir -p "${ren_gh}/.github"
printf '{"extends":["config:recommended"]}\n' > "${ren_gh}/.github/renovate.json"
assert_renovate_only "$ren_gh" ".github/renovate.json"
rm -rf "$ren_gh"

# The package.json `renovate` key form.
ren_pkg="$(mktemp -d)"
printf '{"name":"demo","renovate":{"extends":["config:recommended"]}}\n' > "${ren_pkg}/package.json"
assert_renovate_only "$ren_pkg" "package.json renovate key"
rm -rf "$ren_pkg"

# DISCRIMINATOR: a package.json with NO renovate key must NOT count. A naive
# `grep renovate package.json` would pass both this and the case above, so this
# is what proves the key check is real. The devDependency below is the exact
# shape such a grep would false-positive on.
no_ren_pkg="$(mktemp -d)"
printf '{"name":"demo","devDependencies":{"renovate":"^41.0.0"}}\n' > "${no_ren_pkg}/package.json"
out_nrp="$(bash "$check_script" --home-dir "$HOME" --project-dir "$no_ren_pkg")"
echo "$out_nrp" | grep -q "^LANG_JS=true$" \
  || fail "fixture invalid: package.json should be detected:\n$out_nrp"
echo "$out_nrp" | grep -q "^RENOVATE=false$" \
  || fail "package.json without a top-level renovate key must not count as Renovate:\n$out_nrp"
echo "$out_nrp" | grep -q "^DEPENDENCY_AUTOMATION=false$" \
  || fail "expected DEPENDENCY_AUTOMATION=false:\n$out_nrp"
echo "$out_nrp" | grep -q "TYPE=missing_dependency_automation" \
  || fail "expected the dependency-automation warning:\n$out_nrp"
rm -rf "$no_ren_pkg"

# Guard integrity, other direction: Dependabot-only must STILL satisfy the layer.
dep_only="$(mktemp -d)"
mkdir -p "${dep_only}/.github"
printf 'version: 2\nupdates: []\n' > "${dep_only}/.github/dependabot.yml"
out_do="$(bash "$check_script" --home-dir "$HOME" --project-dir "$dep_only")"
echo "$out_do" | grep -q "^DEPENDABOT=true$" || fail "expected DEPENDABOT=true:\n$out_do"
echo "$out_do" | grep -q "^RENOVATE=false$" || fail "expected RENOVATE=false:\n$out_do"
echo "$out_do" | grep -q "^DEPENDENCY_AUTOMATION=true$" \
  || fail "Dependabot alone must still satisfy the layer:\n$out_do"
echo "$out_do" | grep -q "^SECURITY_LAYERS_PRESENT=1$" \
  || fail "expected SECURITY_LAYERS_PRESENT=1 for a Dependabot-only project:\n$out_do"
if echo "$out_do" | grep -q "TYPE=missing_dependency_automation"; then
  fail "dependency-automation warning must be ABSENT for a Dependabot-only project:\n$out_do"
fi
rm -rf "$dep_only"

pass "Renovate or Dependabot alone satisfies the dependency-automation layer (#2495)"

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
printf '{"extends":["config:recommended"]}\n' > "${ctx}/renovate.json"
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
