#!/usr/bin/env bash
# Regression test for preflight.sh (ADR-0016 extraction, #1558).
#
# Encodes the script's structured-output contract (the semantic invariant the
# skill depends on): the =/STATUS/ISSUE_COUNT envelope, the ahead/behind +
# uncommitted + stash + conflict facts, and the fixed recommendation decision
# tree (resolve-conflicts > commit-or-stash > rebase > ready). All cases run
# against a local fixture repo with --no-fetch --base main, so the test is
# hermetic (no remote, no gh).
#
# Exit 0 on success, non-zero on first failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
preflight="${script_dir}/../preflight.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$preflight" ] || fail "preflight.sh not found at $preflight"

# Fresh fixture repo on branch main with a configured identity.
make_repo() {
  local dir
  dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'line\n' > "$dir/file.txt"
  git -C "$dir" add file.txt
  git -C "$dir" commit -q -m "initial"
  printf '%s' "$dir"
}

run() { bash "$preflight" --no-fetch --base main --project-dir "$1"; }

# -----------------------------------------------------------------------------
# Case 0: not a git repository -> STATUS=ERROR, exit 1
# -----------------------------------------------------------------------------
notrepo="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
out0="$(bash "$preflight" --no-fetch --project-dir "$notrepo")"; rc0=$?
[ "$rc0" -eq 1 ] || fail "expected exit 1 outside a repo, got $rc0"
grep -q "^STATUS=ERROR$" <<<"$out0" || fail "expected STATUS=ERROR outside a repo:\n$out0"
grep -q "TYPE=not_a_repo" <<<"$out0" || fail "expected not_a_repo issue type:\n$out0"
rm -rf "$notrepo"
pass "non-repo emits STATUS=ERROR and exits 1"

# -----------------------------------------------------------------------------
# Case 1: clean, HEAD == base -> ready / OK, no divergence
# -----------------------------------------------------------------------------
r1="$(make_repo)"
out1="$(run "$r1")"; rc1=$?
[ "$rc1" -eq 0 ] || fail "clean repo should exit 0, got $rc1"
grep -q "^=== PREFLIGHT ===$" <<<"$out1"     || fail "missing section header:\n$out1"
grep -q "^=== END PREFLIGHT ===$" <<<"$out1" || fail "missing section footer:\n$out1"
grep -q "^FETCH=skipped$" <<<"$out1"         || fail "expected FETCH=skipped with --no-fetch:\n$out1"
grep -q "^BASE_RESOLVED=true$" <<<"$out1"    || fail "expected BASE_RESOLVED=true:\n$out1"
grep -q "^AHEAD=0$" <<<"$out1"               || fail "expected AHEAD=0:\n$out1"
grep -q "^BEHIND=0$" <<<"$out1"              || fail "expected BEHIND=0:\n$out1"
grep -q "^CONFLICTS=none$" <<<"$out1"        || fail "expected CONFLICTS=none:\n$out1"
grep -q "^RECOMMENDATION=ready$" <<<"$out1"  || fail "expected RECOMMENDATION=ready:\n$out1"
grep -q "^STATUS=OK$" <<<"$out1"             || fail "expected STATUS=OK:\n$out1"
grep -q "^ISSUE_COUNT=0$" <<<"$out1"         || fail "expected ISSUE_COUNT=0:\n$out1"
rm -rf "$r1"
pass "clean HEAD==base -> ready / OK"

# -----------------------------------------------------------------------------
# Case 2: behind base, no conflict -> rebase
# -----------------------------------------------------------------------------
r2="$(make_repo)"
git -C "$r2" checkout -q -b feature
git -C "$r2" checkout -q main
printf 'extra\n' > "$r2/other.txt"
git -C "$r2" add other.txt
git -C "$r2" commit -q -m "advance main"
git -C "$r2" checkout -q feature
out2="$(run "$r2")"
grep -q "^BEHIND=1$" <<<"$out2"               || fail "expected BEHIND=1:\n$out2"
grep -q "^AHEAD=0$" <<<"$out2"                || fail "expected AHEAD=0:\n$out2"
grep -q "^CONFLICTS=none$" <<<"$out2"         || fail "expected no conflict for disjoint change:\n$out2"
grep -q "^RECOMMENDATION=rebase$" <<<"$out2"  || fail "expected RECOMMENDATION=rebase:\n$out2"
grep -q "^STATUS=WARN$" <<<"$out2"            || fail "expected STATUS=WARN when behind:\n$out2"
rm -rf "$r2"
pass "behind base, no conflict -> rebase / WARN"

# -----------------------------------------------------------------------------
# Case 3: uncommitted changes (not behind, no conflict) -> commit-or-stash
# -----------------------------------------------------------------------------
r3="$(make_repo)"
printf 'dirty\n' >> "$r3/file.txt"
out3="$(run "$r3")"
grep -q "^UNCOMMITTED=1$" <<<"$out3"                  || fail "expected UNCOMMITTED=1:\n$out3"
grep -q "^BEHIND=0$" <<<"$out3"                       || fail "expected BEHIND=0:\n$out3"
grep -q "^RECOMMENDATION=commit-or-stash$" <<<"$out3" || fail "expected commit-or-stash:\n$out3"
rm -rf "$r3"
pass "uncommitted changes -> commit-or-stash"

# -----------------------------------------------------------------------------
# Case 4: conflicting divergence -> resolve-conflicts (precedence over behind)
# -----------------------------------------------------------------------------
r4="$(make_repo)"
git -C "$r4" checkout -q -b feature
printf 'feature-line\n' > "$r4/file.txt"
git -C "$r4" commit -q -am "feature edit"
git -C "$r4" checkout -q main
printf 'main-line\n' > "$r4/file.txt"
git -C "$r4" commit -q -am "main edit"
git -C "$r4" checkout -q feature
out4="$(run "$r4")"
grep -q "^CONFLICTS=detected$" <<<"$out4"                || fail "expected CONFLICTS=detected:\n$out4"
grep -q "^CONFLICT_FILES=.*file.txt" <<<"$out4"          || fail "expected file.txt in CONFLICT_FILES:\n$out4"
grep -q "^RECOMMENDATION=resolve-conflicts$" <<<"$out4"  || fail "expected resolve-conflicts (precedence):\n$out4"
grep -q "^STATUS=WARN$" <<<"$out4"                       || fail "expected STATUS=WARN on conflict:\n$out4"
rm -rf "$r4"
pass "conflicting divergence -> resolve-conflicts (beats behind)"

# -----------------------------------------------------------------------------
# Case 5: stash state is reported
# -----------------------------------------------------------------------------
r5="$(make_repo)"
printf 'wip\n' >> "$r5/file.txt"
git -C "$r5" stash -q
out5="$(run "$r5")"
grep -q "^STASH_COUNT=1$" <<<"$out5" || fail "expected STASH_COUNT=1:\n$out5"
rm -rf "$r5"
pass "stash state reported"

# -----------------------------------------------------------------------------
# Case 6: no --issue -> existing-work lookups stay inert (hermetic, no gh)
# -----------------------------------------------------------------------------
r6="$(make_repo)"
out6="$(run "$r6")"
grep -q "^ISSUE=none$" <<<"$out6"          || fail "expected ISSUE=none without --issue:\n$out6"
grep -q "^EXISTING_PRS=none$" <<<"$out6"   || fail "expected EXISTING_PRS=none without --issue:\n$out6"
grep -q "^BRANCH_MATCHES=none$" <<<"$out6" || fail "expected BRANCH_MATCHES=none without --issue:\n$out6"
rm -rf "$r6"
pass "no --issue keeps PR/issue lookup inert"

grep -q "^GH_AUTH=" <<<"$out1" && fail "recon keys must stay absent without --recon:\n$out1"
pass "no --recon emits no recon keys"

# -----------------------------------------------------------------------------
# Recon cases: a stub gh on PATH and a fixture home keep these hermetic.
# -----------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || fail "jq is required for the recon cases"
stub_bin="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
cat > "$stub_bin/gh" <<'STUB'
#!/usr/bin/env bash
# Emits what the real gh would print after --jq.
case "$1 $2" in
  "auth status") exit "${STUB_GH_AUTH_RC:-0}" ;;
  "secret list") printf '%s\n' ${STUB_GH_SECRETS:-} ;;
  "api repos/{owner}/{repo}/environments") printf '%s\n' ${STUB_GH_ENVS:-} ;;
  "--version ") echo "STUB_GH_SENTINEL" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub_bin/gh"
[ "$(PATH="$stub_bin:$PATH" gh --version)" = "STUB_GH_SENTINEL" ] || fail "stub gh is not first on PATH"

fake_home="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
# Physical path, so it prefixes the repo root git reports (/var -> /private/var on macOS).
fake_home="$(cd "$fake_home" && pwd -P)"
mkdir -p "$fake_home/.claude"
cat > "$fake_home/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "defaultMode": "auto",
    "deny": ["Bash(gh pr merge --admin *)", "Bash(rm -rf *)"],
    "ask": ["Bash(git push *)"]
  },
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/merge-guard.sh"}]}
    ]
  }
}
JSON

recon() { PATH="$stub_bin:$PATH" bash "$preflight" --no-fetch --base main --recon --home-dir "$fake_home" --project-dir "$@"; }

# Case 7: authed, required secret present -> no blockers, gates and hooks listed
r7="$(make_repo)"
out7="$(STUB_GH_SECRETS="RELEASE_TOKEN OTHER" STUB_GH_ENVS="production" recon "$r7" --need-secret RELEASE_TOKEN)"
grep -q "^GH_AUTH=ok$" <<<"$out7"                       || fail "expected GH_AUTH=ok:\n$out7"
grep -q "^PERMISSION_MODE=auto$" <<<"$out7"             || fail "expected PERMISSION_MODE=auto:\n$out7"
grep -q "^PERMISSION_MODE_SOURCE=user$" <<<"$out7"      || fail "expected PERMISSION_MODE_SOURCE=user:\n$out7"
grep -qF "deny:Bash(gh pr merge --admin *)" <<<"$out7"  || fail "expected merge deny rule in PERMISSION_GATES:\n$out7"
grep -qF "ask:Bash(git push *)" <<<"$out7"              || fail "expected push ask rule in PERMISSION_GATES:\n$out7"
grep -qF "rm -rf" <<<"$out7"                            && fail "unrelated deny rule leaked into PERMISSION_GATES:\n$out7"
grep -q "^PRETOOLUSE_HOOKS=merge-guard.sh$" <<<"$out7"  || fail "expected merge-guard.sh in PRETOOLUSE_HOOKS:\n$out7"
grep -q "^REPO_SECRETS=RELEASE_TOKEN,OTHER$" <<<"$out7" || fail "expected REPO_SECRETS list:\n$out7"
grep -q "^ENVIRONMENTS=production$" <<<"$out7"          || fail "expected ENVIRONMENTS=production:\n$out7"
grep -q "^REPO_SECRETS_MISSING=none$" <<<"$out7"        || fail "expected REPO_SECRETS_MISSING=none:\n$out7"
grep -q "^RECON_BLOCKERS=none$" <<<"$out7"              || fail "expected RECON_BLOCKERS=none:\n$out7"
grep -q "^STATUS=OK$" <<<"$out7"                        || fail "expected STATUS=OK with no blockers:\n$out7"
rm -rf "$r7"
pass "recon, authed with secrets present -> no blockers"

# Case 8: missing secret -> blocker, STATUS=WARN, headline unchanged
r8="$(make_repo)"
out8="$(STUB_GH_SECRETS="OTHER" recon "$r8" --need-secret RELEASE_TOKEN)"
grep -q "^REPO_SECRETS_MISSING=RELEASE_TOKEN$" <<<"$out8" || fail "expected RELEASE_TOKEN missing:\n$out8"
grep -q "^RECON_BLOCKERS=secrets$" <<<"$out8"             || fail "expected RECON_BLOCKERS=secrets:\n$out8"
grep -q "^RECOMMENDATION=ready$" <<<"$out8"               || fail "recon must not change RECOMMENDATION:\n$out8"
grep -q "^STATUS=WARN$" <<<"$out8"                        || fail "expected STATUS=WARN:\n$out8"
grep -q "^ISSUE_COUNT=1$" <<<"$out8"                      || fail "expected ISSUE_COUNT=1:\n$out8"
rm -rf "$r8"
pass "recon, missing secret -> secrets blocker"

# Case 9: gh logged out -> gh_auth blocker, secrets unknown
r9="$(make_repo)"
out9="$(STUB_GH_AUTH_RC=1 recon "$r9" --need-secret RELEASE_TOKEN)"
grep -q "^GH_AUTH=failed$" <<<"$out9"                 || fail "expected GH_AUTH=failed:\n$out9"
grep -q "^REPO_SECRETS=unknown$" <<<"$out9"           || fail "expected REPO_SECRETS=unknown:\n$out9"
grep -q "^REPO_SECRETS_MISSING=unknown$" <<<"$out9"   || fail "expected REPO_SECRETS_MISSING=unknown:\n$out9"
grep -q "^RECON_BLOCKERS=gh_auth,secrets$" <<<"$out9" || fail "expected gh_auth,secrets blockers:\n$out9"
grep -q "^ISSUE_COUNT=2$" <<<"$out9"                  || fail "expected ISSUE_COUNT=2:\n$out9"
rm -rf "$r9"
pass "recon, gh logged out -> gh_auth blocker"

# Case 10: a project file inside the home dir overrides and is labelled project
r10="$(make_repo)"
mv "$r10" "$fake_home/repo"
r10="$fake_home/repo"
mkdir -p "$r10/.claude"
printf '{"permissions": {"defaultMode": "plan"}}\n' > "$r10/.claude/settings.json"
out10="$(recon "$r10")"
grep -q "^PERMISSION_MODE=plan$" <<<"$out10"           || fail "expected project PERMISSION_MODE=plan:\n$out10"
grep -q "^PERMISSION_MODE_SOURCE=project$" <<<"$out10" || fail "expected PERMISSION_MODE_SOURCE=project:\n$out10"
rm -rf "$r10"
pass "recon, project defaultMode under home dir -> source project"

rm -rf "$stub_bin" "$fake_home"

echo "ALL PASS"
