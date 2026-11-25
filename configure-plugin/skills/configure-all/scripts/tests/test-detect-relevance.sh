#!/usr/bin/env bash
# Regression test for detect-relevance.sh.
# Fixture repos prove: a package.json without vue/react is project type "node"
# (and node reaches the Dockerfile components, whose TYPES list names it); a
# Dockerfile, tests and an Express dependency raise the matching components to
# APPLY while absent subjects (Sentry, Kubernetes) stay SKIP; a Dockerfile that
# exists only under .claude/worktrees is not counted; --type overrides
# detection; an empty directory is "unknown" without crashing.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detector="${script_dir}/../detect-relevance.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$detector" ] || fail "detect-relevance.sh not found at $detector"

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] || fail "mktemp -d returned empty"
trap 'rm -rf "$sandbox"' EXIT

tier_of() { # <output> <component> -> TIER value
  sed -n "s/^RELEVANCE=$2 TIER=\([A-Z]*\) .*/\1/p" <<<"$1"
}
expect_tier() { # <output> <component> <tier> <label>
  local got
  got="$(tier_of "$1" "$2")"
  [ "$got" = "$3" ] || fail "$4: expected $2 TIER=$3, got '${got}'"
}

# -----------------------------------------------------------------------------
# Case 1: Node + Express service with tests, Dockerfile, workflows, CI config
# -----------------------------------------------------------------------------
node_repo="${sandbox}/node-service"
mkdir -p "${node_repo}/tests" "${node_repo}/.github/workflows" "${node_repo}/bridge"
printf '{"dependencies":{"express":"^4.18.2"}}\n' > "${node_repo}/package.json"
printf '{"dependencies":{"express":"^4.18.2"}}\n' > "${node_repo}/bridge/package.json"
printf '{}\n' > "${node_repo}/package-lock.json"
printf '{}\n' > "${node_repo}/bridge/package-lock.json"
printf 'FROM node:24-alpine\n' > "${node_repo}/bridge/Dockerfile"
printf 'it("x",()=>{})\n' > "${node_repo}/tests/a.test.js"
printf 'name: ci\n' > "${node_repo}/.github/workflows/test.yml"
printf '{}\n' > "${node_repo}/release-please-config.json"

out1="$(bash "$detector" --project-dir "$node_repo")" || fail "detector exited non-zero on node repo:\n$out1"
grep -q '^PROJECT_TYPE=node$' <<<"$out1" || fail "expected PROJECT_TYPE=node:\n$out1"
grep -q '^PROJECT_TYPE_SOURCE=detected$' <<<"$out1" || fail "expected detected source:\n$out1"
grep -q '^STATUS=OK$' <<<"$out1" || fail "expected STATUS=OK:\n$out1"
expect_tier "$out1" configure-dockerfile APPLY "node repo"
expect_tier "$out1" configure-container APPLY "node repo"
expect_tier "$out1" configure-api-tests APPLY "node repo"
expect_tier "$out1" configure-coverage APPLY "node repo"
expect_tier "$out1" configure-release-please APPLY "node repo"
expect_tier "$out1" configure-workflows APPLY "node repo"
expect_tier "$out1" configure-package-management REVIEW "two lockfiles"
expect_tier "$out1" configure-sentry SKIP "node repo"
expect_tier "$out1" configure-skaffold SKIP "node repo"
expect_tier "$out1" configure-argocd-automerge SKIP "node repo"
expect_tier "$out1" configure-memory-profiling SKIP "node repo (python only)"
expect_tier "$out1" configure-ux-testing SKIP "node repo (frontend only)"
expect_tier "$out1" configure-cache-busting SKIP "node repo"
pass "node service: type node, subjects present raise tiers, absent subjects SKIP"

# -----------------------------------------------------------------------------
# Case 2: every component the lister knows gets exactly one RELEVANCE row
# -----------------------------------------------------------------------------
lister="${script_dir}/../list-components.sh"
want="$(bash "$lister" | grep -c '^COMPONENT=')"
got="$(grep -c '^RELEVANCE=' <<<"$out1")"
[ "$want" = "$got" ] || fail "expected ${want} RELEVANCE rows (one per manifest component), got ${got}"
sum=$(( $(sed -n 's/^APPLY_COUNT=//p' <<<"$out1") + $(sed -n 's/^REVIEW_COUNT=//p' <<<"$out1") + $(sed -n 's/^SKIP_COUNT=//p' <<<"$out1") ))
[ "$sum" = "$want" ] || fail "tier counts sum to ${sum}, expected ${want}"
pass "one RELEVANCE row per manifest component; tier counts sum to the roster"

# -----------------------------------------------------------------------------
# Case 3: a Dockerfile under .claude/worktrees is not a signal
# -----------------------------------------------------------------------------
wt_repo="${sandbox}/worktree-only"
mkdir -p "${wt_repo}/.claude/worktrees/agent-1"
printf '{}\n' > "${wt_repo}/package.json"
printf 'FROM node:24\n' > "${wt_repo}/.claude/worktrees/agent-1/Dockerfile"
out3="$(bash "$detector" --project-dir "$wt_repo")" || fail "detector failed on worktree-only repo"
grep -q '^SIGNAL_DOCKERFILE=false$' <<<"$out3" || fail "worktree Dockerfile counted as a signal:\n$out3"
expect_tier "$out3" configure-dockerfile SKIP "worktree-only"
pass "agent worktrees are pruned from the probes"

# -----------------------------------------------------------------------------
# Case 4: vue dependency -> frontend; --type override wins over detection
# -----------------------------------------------------------------------------
fe_repo="${sandbox}/frontend"
mkdir -p "$fe_repo"
printf '{"dependencies":{"vue":"^3.4.0"}}\n' > "${fe_repo}/package.json"
out4="$(bash "$detector" --project-dir "$fe_repo")"
grep -q '^PROJECT_TYPE=frontend$' <<<"$out4" || fail "expected PROJECT_TYPE=frontend:\n$out4"
expect_tier "$out4" configure-ux-testing REVIEW "frontend repo"
out4b="$(bash "$detector" --project-dir "$fe_repo" --type python)"
grep -q '^PROJECT_TYPE=python$' <<<"$out4b" || fail "expected override to python:\n$out4b"
grep -q '^PROJECT_TYPE_SOURCE=override$' <<<"$out4b" || fail "expected override source:\n$out4b"
expect_tier "$out4b" configure-ux-testing SKIP "python override"
pass "vue is frontend; --type overrides detection"

# -----------------------------------------------------------------------------
# Case 5: .project-standards.yaml project_type is honoured
# -----------------------------------------------------------------------------
printf 'standards_version: "2025.1"\nproject_type: "python"\n' > "${fe_repo}/.project-standards.yaml"
out5="$(bash "$detector" --project-dir "$fe_repo")"
grep -q '^PROJECT_TYPE=python$' <<<"$out5" || fail "expected declared python:\n$out5"
grep -q '^PROJECT_TYPE_SOURCE=standards_file$' <<<"$out5" || fail "expected standards_file source:\n$out5"
pass ".project-standards.yaml project_type is honoured"

# -----------------------------------------------------------------------------
# Case 6: empty directory -> unknown, still STATUS=OK, no crash
# -----------------------------------------------------------------------------
empty="${sandbox}/empty"
mkdir -p "$empty"
out6="$(bash "$detector" --project-dir "$empty")" || fail "detector crashed on empty dir:\n$out6"
grep -q '^PROJECT_TYPE=unknown$' <<<"$out6" || fail "expected PROJECT_TYPE=unknown:\n$out6"
grep -q '^STATUS=OK$' <<<"$out6" || fail "expected STATUS=OK on empty dir:\n$out6"
pass "empty directory is unknown without crashing"

# -----------------------------------------------------------------------------
# Case 7: missing project dir -> ERROR, exit 1
# -----------------------------------------------------------------------------
out7="$(bash "$detector" --project-dir "${sandbox}/nope")" && rc7=0 || rc7=$?
[ "$rc7" -ne 0 ] || fail "expected non-zero exit for a missing project dir"
grep -q 'TYPE=no_project_dir' <<<"$out7" || fail "expected no_project_dir issue:\n$out7"
pass "missing project dir raises ERROR"

echo "ALL TESTS PASSED"
