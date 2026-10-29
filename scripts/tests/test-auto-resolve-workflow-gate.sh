#!/usr/bin/env bash
# Fixture test for the workflow-file gate in
# .github/workflows/auto-resolve-conflicts.yml.
#
# The resolver merged main into a conflicting PR branch and pushed with a PAT
# that had no `workflow` scope. Whenever the merge brought in a change under
# .github/workflows/, GitHub refused the push, the PR stayed conflicting, and
# the next push to main repeated it: all 9 failed runs between 2026-09-24 and
# 2026-10-24 (run 39462940904). The job now pushes with the release-please App
# token, and "Merge base and resolve additive conflicts" reads the App's
# `workflows` permission before a merge that changes workflow files: without
# `write` it aborts the merge, sets outcome=blocked_workflows, and comments on
# the PR once.
#
# It EXTRACTS the shipped `run:` body with PyYAML and runs it in scratch
# clones against a stub `gh`, so editing the workflow is what this tests.
#
# Usage: bash scripts/tests/test-auto-resolve-workflow-gate.sh [workflow-file]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
WORKFLOW="${1:-$repo_root/.github/workflows/auto-resolve-conflicts.yml}"
MERGE_STEP='Merge base and resolve additive conflicts'

for tool in python3 git; do
  command -v "$tool" >/dev/null || { echo "FATAL: $tool not found on PATH" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: PyYAML is required to read the workflow" >&2; exit 1; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

work="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "FATAL: mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

pass_count=0
fail_count=0
pass() { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail() { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }

echo "=== AUTO-RESOLVE WORKFLOW-FILE GATE ==="

python3 - "$WORKFLOW" "$MERGE_STEP" "$work/merge.sh" > "$work/structure" <<'PY'
import sys, yaml
path, name, out = sys.argv[1:4]
steps = yaml.safe_load(open(path, encoding="utf-8"))["jobs"]["resolve"]["steps"]
by_name = {s.get("name"): s for s in steps}
open(out, "w", encoding="utf-8").write(by_name[name]["run"])
checkout = [s for s in steps if "actions/checkout" in str(s.get("uses", ""))][0]
print("checkout_token=%s" % checkout.get("with", {}).get("token", ""))
print("pat_refs=%d" % open(path, encoding="utf-8").read().count("secrets.MY_RELEASE_PLEASE_TOKEN"))
PY
get() { sed -n "s/^$1=//p" "$work/structure"; }
# shellcheck disable=SC2016 # a literal GitHub expression, not a shell expansion
if [ "$(get checkout_token)" = '${{ steps.app-token.outputs.token }}' ]; then
  pass "the PR branch is checked out (and pushed) with the App token"
else
  fail "checkout token is '$(get checkout_token)', expected the App token"
fi
if [ "$(get pat_refs)" = "0" ]; then
  pass "no step references the MY_RELEASE_PLEASE_TOKEN PAT"
else
  fail "the PAT is still referenced $(get pat_refs) time(s)"
fi

# Stub gh: `api apps/<slug>` prints $WF_PERM (FAIL makes it fail),
# `pr view` prints $SEEN, `pr comment` appends one line to $work/comments.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$1 ${2:-}" in
  "api apps/"*)
    [ "$WF_PERM" = "FAIL" ] && { echo "stub gh: HTTP 404" >&2; exit 1; }
    echo "$WF_PERM" ;;
  "pr view") echo "$SEEN" ;;
  "pr comment") echo "comment $*" >> "$STUB_COMMENTS" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 97 ;;
esac
STUB
chmod +x "$work/bin/gh"

# Scratch origin. Branches pr-wf and pr-clean-wf start before main edits a
# workflow file; pr-plain starts after it. pr-wf and pr-plain append to the
# same file main later appends to, which leaves a conflict for the resolver.
git init -q --bare "$work/origin.git"
git clone -q "$work/origin.git" "$work/seed" 2>/dev/null
s="$work/seed"
git -C "$s" config user.email test@example.invalid
git -C "$s" config user.name test
mkdir -p "$s/.github/workflows"
printf 'a\n' > "$s/notes.txt"
printf 'name: x\n' > "$s/.github/workflows/x.yml"
git -C "$s" add -A && git -C "$s" commit -qm base
git -C "$s" branch -qM main
git -C "$s" switch -qc pr-wf
printf 'pr\n' >> "$s/notes.txt" && git -C "$s" commit -qam 'pr edit'
git -C "$s" switch -qc pr-clean-wf main
printf 'other\n' > "$s/other.txt" && git -C "$s" add other.txt && git -C "$s" commit -qm 'pr adds a file'
git -C "$s" switch -q main
printf 'on: push\n' >> "$s/.github/workflows/x.yml" && git -C "$s" commit -qam 'main edits a workflow'
git -C "$s" switch -qc pr-plain
printf 'pr\n' >> "$s/notes.txt" && git -C "$s" commit -qam 'pr edit'
git -C "$s" switch -q main
printf 'main\n' >> "$s/notes.txt" && git -C "$s" commit -qam 'main edits notes'
git -C "$s" push -q origin main pr-wf pr-clean-wf pr-plain

# The step names its multiline-output delimiter from the Linux kernel's uuid
# file. Off Linux (a macOS run of this test), point that one path at a fixture.
if [ ! -r /proc/sys/kernel/random/uuid ]; then
  printf '00000000-0000-4000-8000-000000000000\n' > "$work/uuid"
  python3 - "$work/merge.sh" "$work/uuid" <<'PY2'
import sys
p, u = sys.argv[1:3]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("/proc/sys/kernel/random/uuid", u))
PY2
fi

run_merge() { # <branch> <perm> <seen> — prints the outcome
  local d="$work/run-$1-$2-$3"
  git clone -q -b "$1" "$work/origin.git" "$d" 2>/dev/null
  git -C "$d" config user.email test@example.invalid
  git -C "$d" config user.name test
  : > "$work/out"
  (cd "$d" && PATH="$work/bin:$PATH" WF_PERM="$2" SEEN="$3" STUB_COMMENTS="$work/comments" \
    GITHUB_OUTPUT="$work/out" RUNNER_TEMP="$work" PR_NUMBER=7 BASE_BRANCH=main \
    GH_TOKEN=x APP_SLUG=laurigates-release-please REPO=o/r bash -e "$work/merge.sh" >/dev/null 2>&1) \
    || { echo "step-exited-nonzero"; return 0; }
  sed -n 's/^outcome=//p' "$work/out"
}

check() { # <label> <expected outcome> <expected new comments> <branch> <perm> <seen>
  local before after got
  before=$(wc -l < "$work/comments" | tr -d ' ')
  got="$(run_merge "$4" "$5" "$6")"
  after=$(wc -l < "$work/comments" | tr -d ' ')
  if [ "$got" = "$2" ] && [ $((after - before)) = "$3" ]; then
    pass "$1"
  else
    fail "$1 (expected outcome=$2 with $3 comment(s), got outcome='$got' with $((after - before)))"
  fi
}

: > "$work/comments"
check "a conflicting merge that changes a workflow, App without workflows:write, is skipped and commented" \
  blocked_workflows 1 pr-wf none 0
check "the comment is not repeated once the PR carries it"       blocked_workflows 0 pr-wf none 1
check "a clean merge that changes a workflow is skipped too"     blocked_workflows 1 pr-clean-wf read 0
check "an App with workflows:write proceeds to the resolver"     llm 0 pr-wf write 0
check "an unreadable App permission proceeds (the push decides)" llm 0 pr-wf FAIL 0
check "a merge that changes no workflow file proceeds"           llm 0 pr-plain none 0

echo "=== END AUTO-RESOLVE WORKFLOW-FILE GATE ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
