#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixture workflow YAML carries literal ${{ }} / $VAR text, never expansions
# Regression test for scripts/check-comment-deliverable-assertions.sh
# (#2630 Rec 1, #2719 — the class sweep).
#
# A Claude step whose only deliverable is a PR comment can finish green while
# posting nothing, because the SDK exits 0 on a denied tool call. The guard
# requires every such step to be followed by the runtime delivery assertion
# (scripts/assert-pr-comment-delivered.sh) and by an upload of its execution
# transcript, so the next silent run both fails and names the denied call.
#
# Cases:
#   A. the real repo is clean, and the sweep is non-vacuous (>= 2 steps in scope)
#   B. a comment-granting automation step with neither → both findings, named
#   C. the same step with both → clean
#   D. an assertion placed BEFORE the Claude step does not count
#   E. tag mode (no prompt:) is out of scope — the action posts its own comment
#   F. an issue-filer (only `gh issue create`) is out of scope
#   G. a comment-granting step with no id cannot be referenced → missing_step_id
#   H. an upload not tied to the step's execution_file does not count
#   I. an unknown argument exits 2 and scans nothing
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-comment-deliverable-assertions.sh"

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
has_line() { grep -qxF -- "$2" <<<"$1" && echo true || echo false; }
has() { grep -qF -- "$2" <<<"$1" && echo true || echo false; }
lacks() { grep -qF -- "$2" <<<"$1" && echo false || echo true; }

work="$(mktemp -d)"
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

run() {
  OUT="$(bash "$checker" --project-dir "$1" 2>&1)"
  RC=$?
}

# fixture <dir> <workflow-body> — a project with one workflow, audit.yml.
fixture() {
  rm -rf "$1"
  mkdir -p "$1/.github/workflows"
  printf '%s\n' "$2" > "$1/.github/workflows/audit.yml"
}

CLAUDE_STEP='      - name: Claude audit
        id: audit
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --model opus
            --effort low
            --allowedTools "Read,Bash(gh pr comment *),mcp__github_comment"
          prompt: |
            Post one comment.'
ASSERT_STEP='      - name: Assert the comment was posted
        if: steps.audit.outcome == '"'"'success'"'"'
        run: bash scripts/assert-pr-comment-delivered.sh --repo "$GITHUB_REPOSITORY" --pr 1 --since 0'
REDACT_STEP='      - name: Redact the Claude execution transcript
        id: redact
        if: always() && steps.audit.outputs.execution_file != '"''"'
        env:
          TRANSCRIPT: ${{ steps.audit.outputs.execution_file }}
        run: cp "$TRANSCRIPT" out.json'
UPLOAD_STEP='      - name: Upload Claude execution transcript
        if: always() && steps.redact.outputs.path != '"''"'
        uses: actions/upload-artifact@v4
        with:
          name: transcript
          path: out.json'
HEAD='name: "Fixture: audit"
on: { pull_request: {} }
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6'

echo "=== TEST A: real repo is clean and the sweep is non-vacuous ==="
run "$repo_root"
assert "A: real repo exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "A: STATUS=OK" "$(has_line "$OUT" 'STATUS=OK')"
a_steps=$(sed -n 's/^COMMENT_DELIVERABLE_STEPS=//p' <<<"$OUT")
assert "A: >= 2 comment-deliverable steps in scope (got '${a_steps:-none}')" "$([ "${a_steps:-0}" -ge 2 ] 2>/dev/null && echo true || echo false)"
assert "A: tag-mode claude.yml counted as skipped, not scanned" "$([ "$(sed -n 's/^SKIPPED_TAG_MODE=//p' <<<"$OUT")" -ge 1 ] 2>/dev/null && echo true || echo false)"

echo "=== TEST B: comment-granting step with no assertion and no upload ==="
fixture "$work/b" "$HEAD
$CLAUDE_STEP"
run "$work/b"
assert "B: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "B: missing_delivery_assertion reported" "$(has "$OUT" 'TYPE=missing_delivery_assertion')"
assert "B: REASON= names the first finding" "$(grep -qE '^REASON=missing_[a-z_]+: .+' <<<"$OUT" && echo true || echo false)"
assert "B: missing_transcript_upload reported" "$(has "$OUT" 'TYPE=missing_transcript_upload')"
assert "B: names the workflow and step" "$(has "$OUT" 'FILE=.github/workflows/audit.yml JOB=audit STEP=audit')"
assert "B: one step in scope" "$(has_line "$OUT" 'COMMENT_DELIVERABLE_STEPS=1')"

echo "=== TEST C: the same step with assertion + redact + upload ==="
fixture "$work/c" "$HEAD
$CLAUDE_STEP
$ASSERT_STEP
$REDACT_STEP
$UPLOAD_STEP"
run "$work/c"
assert "C: exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "C: STATUS=OK" "$(has_line "$OUT" 'STATUS=OK')"
assert "C: no REASON= on the OK path" "$(grep -q '^REASON=' <<<"$OUT" && echo false || echo true)"
assert "C: still in scope (non-vacuous)" "$(has_line "$OUT" 'COMMENT_DELIVERABLE_STEPS=1')"

echo "=== TEST D: an assertion BEFORE the Claude step does not count ==="
fixture "$work/d" "$HEAD
$ASSERT_STEP
$CLAUDE_STEP
$REDACT_STEP
$UPLOAD_STEP"
run "$work/d"
assert "D: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "D: missing_delivery_assertion reported" "$(has "$OUT" 'TYPE=missing_delivery_assertion')"
assert "D: the upload after the step still counts" "$(lacks "$OUT" 'TYPE=missing_transcript_upload')"

echo "=== TEST E: tag mode (no prompt:) is out of scope ==="
fixture "$work/e" "$HEAD
      - name: Claude
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --model opus
            --effort medium
            --allowedTools \"Read,mcp__github_comment\""
run "$work/e"
assert "E: exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "E: SKIPPED_TAG_MODE=1" "$(has_line "$OUT" 'SKIPPED_TAG_MODE=1')"
assert "E: nothing in scope" "$(has_line "$OUT" 'COMMENT_DELIVERABLE_STEPS=0')"

echo "=== TEST F: an issue-filer is out of scope ==="
fixture "$work/f" "$HEAD
      - name: Claude audit
        id: audit
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --model opus
            --effort low
            --allowedTools \"Read,Bash(gh issue create *)\"
          prompt: |
            File one issue."
run "$work/f"
assert "F: exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "F: nothing in scope" "$(has_line "$OUT" 'COMMENT_DELIVERABLE_STEPS=0')"
assert "F: the Claude step was seen" "$(has_line "$OUT" 'CLAUDE_STEPS=1')"

echo "=== TEST G: a comment-granting step with no id ==="
fixture "$work/g" "$HEAD
$(sed '/^        id: audit$/d' <<<"$CLAUDE_STEP")
$ASSERT_STEP
$REDACT_STEP
$UPLOAD_STEP"
run "$work/g"
assert "G: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "G: missing_step_id reported" "$(has "$OUT" 'TYPE=missing_step_id')"

echo "=== TEST H: an upload not tied to execution_file does not count ==="
fixture "$work/h" "$HEAD
$CLAUDE_STEP
$ASSERT_STEP
$UPLOAD_STEP"
run "$work/h"
assert "H: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "H: missing_transcript_upload reported" "$(has "$OUT" 'TYPE=missing_transcript_upload')"
assert "H: the assertion is still recognised" "$(lacks "$OUT" 'TYPE=missing_delivery_assertion')"

echo "=== TEST I: unknown argument exits 2 and scans nothing ==="
i_out="$(bash "$checker" --strict 2>&1)"
i_rc=$?
assert "I: exits 2" "$([ "$i_rc" -eq 2 ] && echo true || echo false)"
assert "I: names the argument" "$(has "$i_out" 'unknown argument: --strict')"
assert "I: emits no report" "$(lacks "$i_out" 'WORKFLOWS_SCANNED=')"

echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
