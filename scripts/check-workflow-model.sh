#!/usr/bin/env bash
# Verify every GitHub Actions workflow that invokes Claude pins `--model opus`
# and sets an explicit `--effort` level.
#
# Background: workflows are TOP-LEVEL Claude invocations, not subagents, so the
# "a weak delegate's output re-enters the main loop" argument (the agent-model
# guard's rationale) does not apply here. The justification is cost-economics:
# Opus 4.8 at low effort beats Sonnet 4.6 at high effort on both quality and
# token efficiency, so `effort`, not `model`, is the cost lever. Haiku supports
# no effort at all, so it cannot access that lever — haiku → opus --effort low
# is the natural replacement. Opus defaults to `--effort high`, so effort MUST
# be explicit or the savings are forfeited. See
# `.claude/rules/workflow-model-effort.md` and `.claude/rules/agent-development.md`
# (§ "Model Selection for Agents") for the sibling agent standard.
#
# Classification (per workflow file):
#   - INVOKING: references `anthropics/claude-code-action` (claude_args form) or
#               `npx @anthropic-ai/claude-code` (CLI form). Checked.
#   - REUSABLE: delegates to an external `*/.github/...reusable-*.yml` and has no
#               direct invocation — the model lives upstream. Skipped.
#   - NO-INVOCATION: never invokes Claude. Skipped silently.
#
# Usage:
#   bash scripts/check-workflow-model.sh [--project-dir <path>] [workflow.yml ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   workflow.yml …  Explicit files to check (pre-commit style); when present,
#                   discovery is skipped and only these files are checked.
#
# Exit codes:
#   0 - all invoking workflows pin opus + an explicit valid effort
#   1 - one or more workflows violate the standard

set -euo pipefail

# Files exempt from the requirement. Empty by design: the reusable external
# workflow is handled by *classification* (skip), not by allowlist. Add a path
# here only for a genuine future exception.
# Test seam: CHECK_WORKFLOW_MODEL_ALLOWLIST (whitespace-separated) extends it so
# the regression test can exercise the honoring path without a real exemption.
WORKFLOW_MODEL_ALLOWLIST=()
# shellcheck disable=SC2206  # intentional word-split of the test-seam env var
WORKFLOW_MODEL_ALLOWLIST+=(${CHECK_WORKFLOW_MODEL_ALLOWLIST:-})

VALID_EFFORTS="low medium high xhigh max"

proj_dir=""
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Collect workflow files. Explicit args win (pre-commit passes changed files);
# otherwise discover every *.yml / *.yaml directly under .github/workflows.
# Globbing the fixed path (not a recursive find) inherently excludes
# .claude/worktrees/ agent-clone copies (#1492 class).
workflow_files=()
if [ ${#explicit_files[@]} -gt 0 ]; then
  workflow_files=("${explicit_files[@]}")
else
  shopt -s nullglob
  for wf in "$proj_dir"/.github/workflows/*.yml "$proj_dir"/.github/workflows/*.yaml; do
    workflow_files+=("$wf")
  done
  shopt -u nullglob
fi

# extract_flag <file> <model|effort> — emit each flag value found at a genuine
# invocation site, one per line. Two sites only, so prose that merely *mentions*
# the flags (e.g. a prompt: block documenting `--model`/`--effort`) never counts:
#   (a) inside a claude_args: "..." string (claude-code-action form)
#   (b) a flag-only continuation line `--model <v>` / `--effort <v>` anchored at
#       line start (the npx @anthropic-ai/claude-code CLI form)
extract_flag() {
  local f="$1" flag="$2"
  {
    grep -oE "claude_args:[[:space:]]*\"[^\"]*\"" "$f" 2>/dev/null \
      | grep -oE -- "--${flag}[ =]+[a-zA-Z0-9._-]+" || true
    grep -oE "^[[:space:]]*--${flag}[ =]+[a-zA-Z0-9._-]+" "$f" 2>/dev/null || true
  } | sed -E "s/.*--${flag}[ =]+//" | tr -d '\r'
}

# is_allowlisted <file> — true if the file matches a WORKFLOW_MODEL_ALLOWLIST
# entry (compared by trailing path so callers can pass relative or absolute).
is_allowlisted() {
  local candidate="${1#./}"
  local entry
  for entry in ${WORKFLOW_MODEL_ALLOWLIST[@]+"${WORKFLOW_MODEL_ALLOWLIST[@]}"}; do
    entry="${entry#./}"
    [ -z "$entry" ] && continue
    case "$candidate" in
      "$entry" | */"$entry") return 0 ;;
    esac
  done
  return 1
}

scanned=0
invoking=0
skipped_no_invocation=0
skipped_reusable=0
issue_count=0
issues=()

for wf in "${workflow_files[@]}"; do
  [ -f "$wf" ] || continue
  scanned=$((scanned + 1))

  is_allowlisted "$wf" && continue

  # Classify.
  invokes=false
  if grep -q 'anthropics/claude-code-action' "$wf" 2>/dev/null \
     || grep -q 'npx @anthropic-ai/claude-code' "$wf" 2>/dev/null; then
    invokes=true
  fi

  if [ "$invokes" = "false" ]; then
    # Reusable-only delegation (model lives upstream) vs no invocation at all.
    if grep -qE 'uses:[[:space:]]*[^[:space:]]+/\.github/.*reusable' "$wf" 2>/dev/null; then
      skipped_reusable=$((skipped_reusable + 1))
    else
      skipped_no_invocation=$((skipped_no_invocation + 1))
    fi
    continue
  fi

  invoking=$((invoking + 1))

  # Extract --model / --effort values from genuine invocation sites only
  # (claude_args string + CLI flag-only lines) — never from prose.
  models=$(extract_flag "$wf" model)
  efforts=$(extract_flag "$wf" effort)

  wf_rel="${wf#"$proj_dir"/}"

  # Model assertions.
  if [ -z "$models" ]; then
    issues+=("  - SEVERITY=ERROR TYPE=missing_model FILE=$wf_rel MSG=claude invocation has no --model (must pin opus)")
    issue_count=$((issue_count + 1))
  else
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      if [ "$m" != "opus" ]; then
        issues+=("  - SEVERITY=ERROR TYPE=non_opus_model FILE=$wf_rel MODEL=$m MSG=must be opus (effort is the cost lever)")
        issue_count=$((issue_count + 1))
      fi
    done <<< "$models"
  fi

  # Effort assertions.
  if [ -z "$efforts" ]; then
    issues+=("  - SEVERITY=ERROR TYPE=missing_effort FILE=$wf_rel MSG=opus requires explicit --effort (default high forfeits savings)")
    issue_count=$((issue_count + 1))
  else
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      case " $VALID_EFFORTS " in
        *" $e "*) : ;;
        *)
          issues+=("  - SEVERITY=ERROR TYPE=invalid_effort FILE=$wf_rel EFFORT=$e MSG=effort must be one of: $VALID_EFFORTS")
          issue_count=$((issue_count + 1))
          ;;
      esac
    done <<< "$efforts"
  fi
done

status="OK"
[ "$issue_count" -gt 0 ] && status="ERROR"

echo "=== WORKFLOW MODEL/EFFORT ==="
echo "WORKFLOWS_SCANNED=$scanned"
echo "INVOKING_WORKFLOWS=$invoking"
echo "SKIPPED_NO_INVOCATION=$skipped_no_invocation"
echo "SKIPPED_REUSABLE=$skipped_reusable"
echo "STATUS=$status"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END WORKFLOW MODEL/EFFORT ==="

if [ "$issue_count" -gt 0 ]; then
  echo "" >&2
  echo "Found $issue_count workflow model/effort issue(s) (of $invoking invoking workflows)." >&2
  echo "Every Claude workflow must pin '--model opus' and set an explicit '--effort'" >&2
  echo "level — effort, not model, is the cost lever, and opus defaults to high." >&2
  echo "Haiku supports no effort at all. See .claude/rules/workflow-model-effort.md." >&2
  exit 1
fi

echo "All $invoking invoking workflow(s) pin opus + explicit effort. ✅"
exit 0
