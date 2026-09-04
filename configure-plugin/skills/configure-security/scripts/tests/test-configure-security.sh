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
full="$(mktemp -d)" || { fail "mktemp -d failed"; }
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
bare="$(mktemp -d)" || { fail "mktemp -d failed"; }
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
ren="$(mktemp -d)" || { fail "mktemp -d failed"; }
printf '{"extends":["config:recommended"]}\n' > "${ren}/renovate.json"
assert_renovate_only "$ren" "root renovate.json"
rm -rf "$ren"

# A non-root config location, to pin the whole candidate list rather than one path.
ren_gh="$(mktemp -d)" || { fail "mktemp -d failed"; }
mkdir -p "${ren_gh}/.github"
printf '{"extends":["config:recommended"]}\n' > "${ren_gh}/.github/renovate.json"
assert_renovate_only "$ren_gh" ".github/renovate.json"
rm -rf "$ren_gh"

# The package.json `renovate` key form.
ren_pkg="$(mktemp -d)" || { fail "mktemp -d failed"; }
printf '{"name":"demo","renovate":{"extends":["config:recommended"]}}\n' > "${ren_pkg}/package.json"
assert_renovate_only "$ren_pkg" "package.json renovate key"
rm -rf "$ren_pkg"

# DISCRIMINATOR: a package.json with NO renovate key must NOT count. A naive
# `grep renovate package.json` would pass both this and the case above, so this
# is what proves the key check is real. The devDependency below is the exact
# shape such a grep would false-positive on.
no_ren_pkg="$(mktemp -d)" || { fail "mktemp -d failed"; }
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
dep_only="$(mktemp -d)" || { fail "mktemp -d failed"; }
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
ctx="$(mktemp -d)" || { fail "mktemp -d failed"; }
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

# -----------------------------------------------------------------------------
# Case 4: the missing-SAST severity is gated on whether CodeQL can RUN here
#   (Regression, issue #2498): the check warned `missing_sast` on every repo
#   without a CodeQL workflow, including private repos with no GitHub code
#   security — where every `github/codeql-action/*` step fails with HTTP 403, so
#   acting on the recommendation produces a workflow whose only fix is deleting
#   it. The report gave an agent no way to tell that apart from a genuine gap.
#
#   SEMANTIC: every case EXECUTES the shipped collector against a real fixture
#   repo with a STUBBED `gh` on PATH. A grep of the script for a reason token
#   would pass against a probe that never runs.
#
#   The NEGATIVE controls carry as much weight as the downgrade: a collector that
#   simply stopped warning about SAST would satisfy 4b and 4j on its own, so 4a /
#   4c / 4d / 4e / 4f all require the WARN to SURVIVE.
# -----------------------------------------------------------------------------

# Neutralise inherited git context before any sandbox git op (#1745): GIT_DIR and
# friends OVERRIDE `git -C`, so a leaked value would point these fixtures' git
# commands at the real shared checkout.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

stub_bin="$(mktemp -d)" || { fail "mktemp -d failed"; }
if [ -z "$stub_bin" ] || [ ! -d "$stub_bin" ]; then fail "bad stub dir"; fi
cat > "${stub_bin}/gh" <<'GH_STUB'
#!/usr/bin/env bash
# Canned `gh`. Logs its argv so a test can assert the probe ran — or did NOT.
printf '%s\n' "$*" >> "${GH_STUB_LOG:-/dev/null}"
if [ -n "${GH_STUB_ERR:-}" ]; then printf '%s\n' "$GH_STUB_ERR" >&2; fi
if [ -n "${GH_STUB_OUT:-}" ]; then printf '%s\n' "$GH_STUB_OUT"; fi
exit "${GH_STUB_RC:-0}"
GH_STUB
chmod +x "${stub_bin}/gh"
# A stub without the executable bit is silently skipped by PATH lookup and the
# REAL binary runs instead (~/.claude/rules/never-fabricate-test-identifiers.md).
[ -x "${stub_bin}/gh" ] || fail "gh stub is not executable"

# Builds a fixture repo whose only missing security layer is SAST unless the
# caller removes files. $2 is the remote URL.
make_repo() {
  local mr_dir="$1" mr_remote="$2"
  git -C "$mr_dir" init -q -b main >/dev/null 2>&1 || fail "git init failed in $mr_dir"
  [ -n "$mr_remote" ] && git -C "$mr_dir" remote add origin "$mr_remote"
  return 0
}

# Runs the collector with the stub on PATH. Echoes the collector's stdout; the
# caller reads $sast_rc / $sast_err_file / the stub log.
sast_out=""; sast_rc=0; sast_log=""
run_sast_case() {
  # $1 = project dir, remaining args = VAR=VALUE stub/probe env
  local rs_dir="$1"; shift
  sast_log="$(mktemp)" || fail "mktemp failed"
  local rs_err
  rs_err="$(mktemp)" || fail "mktemp failed"
  sast_out="$(env PATH="${stub_bin}:$PATH" GH_STUB_LOG="$sast_log" "$@" \
    bash "$check_script" --home-dir "$HOME" --project-dir "$rs_dir" 2>"$rs_err")"
  sast_rc=$?
  [ -s "$rs_err" ] && fail "collector wrote to stderr [$(cat "$rs_err")]"
  rm -f "$rs_err"
  return 0
}

assert_sast_warns() {
  # $1 = label. The pre-probe behaviour is the FLOOR: anything short of a
  # definitive "no" must keep raising the WARN.
  echo "$sast_out" | grep -q "TYPE=missing_sast" \
    || fail "expected the missing_sast WARN to survive for $1:\n$sast_out"
  if echo "$sast_out" | grep -q "TYPE=sast_unavailable"; then
    fail "sast_unavailable must be ABSENT for $1:\n$sast_out"
  fi
}

# 4a — GUARD INTEGRITY. Code security ENABLED on a private repo: CodeQL can run,
# so the gap is real and the WARN must stand. Without this, every "no warning"
# assertion below is satisfied by a collector that stopped warning entirely.
sast_a="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_a" "https://github.com/acme/demo.git"
run_sast_case "$sast_a" GH_STUB_OUT='true enabled'
echo "$sast_out" | grep -q "^CODEQL_AVAILABLE=yes$" \
  || fail "expected CODEQL_AVAILABLE=yes for an enabled private repo:\n$sast_out"
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=code-security-enabled$" \
  || fail "expected reason=code-security-enabled:\n$sast_out"
assert_sast_warns "code security enabled"
echo "$sast_out" | grep -q "^STATUS=WARN$" || fail "expected STATUS=WARN:\n$sast_out"
# Non-vacuity: the probe genuinely ran and hit the documented endpoint.
grep -q 'repos/{owner}/{repo}' "$sast_log" \
  || fail "expected the probe to call gh api repos/{owner}/{repo}: $(cat "$sast_log")"
rm -rf "$sast_a"

# 4b — THE REPORTED DEFECT. Code security DISABLED: the recommendation is
# unusable, so it downgrades to INFO and the message says WHY.
sast_b="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_b" "https://github.com/acme/demo.git"
run_sast_case "$sast_b" GH_STUB_OUT='true disabled'
echo "$sast_out" | grep -q "^CODEQL_AVAILABLE=no$" \
  || fail "expected CODEQL_AVAILABLE=no for a disabled private repo:\n$sast_out"
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=code-security-disabled$" \
  || fail "expected reason=code-security-disabled:\n$sast_out"
if echo "$sast_out" | grep -q "TYPE=missing_sast"; then
  fail "missing_sast must NOT be raised where CodeQL cannot run:\n$sast_out"
fi
echo "$sast_out" | grep -q "SEVERITY=INFO TYPE=sast_unavailable" \
  || fail "expected an INFO sast_unavailable row:\n$sast_out"
# The downgraded row must state the cause, not go silent (issue #2498).
echo "$sast_out" | grep "TYPE=sast_unavailable" | grep -q "code-security-disabled" \
  || fail "the downgraded row must name the reason:\n$sast_out"
echo "$sast_out" | grep "TYPE=sast_unavailable" | grep -q "403" \
  || fail "the downgraded row must say what acting on it would do:\n$sast_out"
# `code_security.status` reports whether code security is enabled HERE, not
# whether the org is licensed for it — a private repo in a GHAS-licensed org with
# the toggle off returns the identical byte. The row must therefore offer the
# settings route as well as the SARIF-free one, and must not assert a plan tier.
echo "$sast_out" | grep "TYPE=sast_unavailable" | grep -q "security settings" \
  || fail "the downgraded row must name the settings route, not only a scanner swap:\n$sast_out"
rm -rf "$sast_b"

# 4c — PUBLIC repo: code scanning is free, so a missing workflow is a real gap
# whatever the plan tier. This is the case a naive "GHAS off ⇒ suppress" fix
# gets wrong, and jq's `//` would erase it (`false // ""` is `""`).
sast_c="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_c" "https://github.com/acme/demo.git"
run_sast_case "$sast_c" GH_STUB_OUT='false '
echo "$sast_out" | grep -q "^CODEQL_AVAILABLE=yes$" \
  || fail "expected CODEQL_AVAILABLE=yes for a public repo:\n$sast_out"
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=public-repo$" \
  || fail "expected reason=public-repo:\n$sast_out"
assert_sast_warns "public repo"
rm -rf "$sast_c"

# 4d — security_and_analysis ABSENT from the payload: unknown, so the WARN stands.
sast_d="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_d" "https://github.com/acme/demo.git"
run_sast_case "$sast_d" GH_STUB_OUT='true '
echo "$sast_out" | grep -q "^CODEQL_AVAILABLE=unknown$" \
  || fail "expected CODEQL_AVAILABLE=unknown when the status field is absent:\n$sast_out"
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=status-field-absent$" \
  || fail "expected reason=status-field-absent:\n$sast_out"
assert_sast_warns "absent security_and_analysis field"
rm -rf "$sast_d"

# 4e — UNAUTHENTICATED gh: unknown, WARN preserved, and the collector itself stays
# exit 0 with empty stderr (run_sast_case fails on any stderr).
sast_e="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_e" "https://github.com/acme/demo.git"
run_sast_case "$sast_e" GH_STUB_RC=1 \
  GH_STUB_ERR='gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable. Try authenticating with: gh auth login'
echo "$sast_out" | grep -q "^CODEQL_AVAILABLE=unknown$" \
  || fail "expected CODEQL_AVAILABLE=unknown for unauthenticated gh:\n$sast_out"
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=gh-unauthenticated$" \
  || fail "expected reason=gh-unauthenticated:\n$sast_out"
assert_sast_warns "unauthenticated gh"
echo "$sast_out" | grep -q "^STATUS=WARN$" || fail "expected STATUS=WARN:\n$sast_out"
rm -rf "$sast_e"

# 4f — OPT-OUT: the documented escape hatch skips the probe entirely and keeps
# today's behaviour, with the stub proving no network call was attempted.
sast_f="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_f" "https://github.com/acme/demo.git"
run_sast_case "$sast_f" CONFIGURE_SECURITY_NO_GHAS_PROBE=1 GH_STUB_OUT='true disabled'
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=opt-out$" \
  || fail "expected reason=opt-out:\n$sast_out"
assert_sast_warns "probe opted out"
[ -s "$sast_log" ] && fail "the opt-out must invoke no gh call: $(cat "$sast_log")"
rm -rf "$sast_f"

# 4g — DESIGN PIN: a repo that already has a CodeQL workflow must cost NO network
# call. Structurally forbids a later change that probes on every run.
sast_g="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_g" "https://github.com/acme/demo.git"
mkdir -p "${sast_g}/.github/workflows"
printf 'name: CodeQL\njobs:\n  analyze:\n    steps:\n      - uses: github/codeql-action/analyze@v3\n' \
  > "${sast_g}/.github/workflows/codeql.yml"
run_sast_case "$sast_g" GH_STUB_OUT='true disabled'
echo "$sast_out" | grep -q "^CODEQL=true$" || fail "fixture invalid: CODEQL should be true:\n$sast_out"
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=not-probed$" \
  || fail "a configured repo must not be probed:\n$sast_out"
[ -s "$sast_log" ] && fail "a configured repo must invoke no gh call: $(cat "$sast_log")"
rm -rf "$sast_g"

# 4h / 4i — the two offline precondition skips, each proving no gh call is made.
sast_h="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_h" ""
run_sast_case "$sast_h" GH_STUB_OUT='true disabled'
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=no-remote$" \
  || fail "expected reason=no-remote:\n$sast_out"
assert_sast_warns "repo with no remote"
[ -s "$sast_log" ] && fail "a remote-less repo must invoke no gh call: $(cat "$sast_log")"
rm -rf "$sast_h"

sast_i="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_i" "https://gitlab.com/acme/demo.git"
run_sast_case "$sast_i" GH_STUB_OUT='true disabled'
echo "$sast_out" | grep -q "^CODEQL_AVAILABILITY_REASON=not-github$" \
  || fail "expected reason=not-github:\n$sast_out"
assert_sast_warns "non-GitHub remote"
[ -s "$sast_log" ] && fail "a non-GitHub remote must invoke no gh call: $(cat "$sast_log")"
rm -rf "$sast_i"

# 4j — THE PAYOFF. Every other layer present, SAST unavailable: the run is clean.
# Pre-fix this reported STATUS=WARN over a layer the repo cannot adopt.
sast_j="$(mktemp -d)" || { fail "mktemp -d failed"; }
make_repo "$sast_j" "https://github.com/acme/demo.git"
printf '{"extends":["config:recommended"]}\n' > "${sast_j}/renovate.json"
printf '[allowlist]\n' > "${sast_j}/.gitleaks.toml"
printf '# Security Policy\n' > "${sast_j}/SECURITY.md"
run_sast_case "$sast_j" GH_STUB_OUT='true disabled'
echo "$sast_out" | grep -q "^STATUS=OK$" \
  || fail "expected STATUS=OK when the only missing layer cannot be adopted:\n$sast_out"
echo "$sast_out" | grep -q "^ISSUE_COUNT=1$" \
  || fail "expected ISSUE_COUNT=1 (the INFO row alone):\n$sast_out"
if echo "$sast_out" | grep -q "SEVERITY=WARN"; then
  fail "no WARN row should remain:\n$sast_out"
fi
[ "$sast_rc" -eq 0 ] || fail "expected exit 0, got $sast_rc"
rm -rf "$sast_j"

rm -rf "$stub_bin"
pass "missing-SAST severity is gated on CodeQL availability, with the reason reported (#2498)"

echo "ALL TESTS PASSED"
