#!/usr/bin/env bash
# Regression test for scripts/check-workflow-model.sh
# (.claude/rules/workflow-model-effort.md — every Claude workflow pins
#  `--model opus` and an explicit `--effort` level).
#
# Guards:
#   A. the real repo stays clean — every invoking workflow is opus+effort, exit 0
#   B. an opus+effort claude_args fixture exits 0 and reports the count
#   C. a `--model haiku` workflow exits 1, names the file, reports the model
#   D. a `--model sonnet` workflow exits 1 and names the file
#   E. `--model opus` WITHOUT `--effort` exits 1 (missing_effort — the invariant
#      the agent-model guard does not have)
#   F. CLI/npx form with `--model haiku` exits 1 (second parser path)
#   G. CLI/npx form with opus+effort exits 0
#   H. a workflow with no Claude invocation is not counted, exit 0
#   I. a reusable-only workflow is skipped, exit 0
#   J. `--effort bogus` (invalid level) exits 1 (invalid_effort)
#   K. an allowlisted file is honored (via the CHECK_WORKFLOW_MODEL_ALLOWLIST seam)
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-workflow-model.sh"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

# make_action_workflow <path> <claude_args-value> — minimal claude-code-action
# workflow with the given claude_args string.
make_action_workflow() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: action workflow"
on: { workflow_dispatch: {} }
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: "$2"
          prompt: "Do a thing."
EOF
}

# make_cli_workflow <path> <model> <effort> — minimal npx-CLI form workflow.
make_cli_workflow() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: cli workflow"
on: { push: {} }
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - run: |
          cat <<'P' | npx @anthropic-ai/claude-code --print \\
            --model $2 \\
            --effort $3 \\
            --max-turns 20 \\
            -
          Resolve the thing.
          P
EOF
}

# make_cli_workflow_noeffort <path> <model> — CLI form without --effort.
make_cli_workflow_noeffort() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: cli workflow"
on: { push: {} }
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - run: |
          cat <<'P' | npx @anthropic-ai/claude-code --print --model $2 --max-turns 20 -
          Resolve the thing.
          P
EOF
}

# make_plain_workflow <path> — a workflow with no Claude invocation.
make_plain_workflow() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: plain workflow"
on: { push: {} }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - run: echo build
EOF
}

# make_reusable_workflow <path> — delegates to an external reusable workflow.
make_reusable_workflow() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: reusable caller"
on: { pull_request: {} }
jobs:
  review:
    uses: owner/.github/.github/workflows/reusable-claude-review.yml@main
    secrets: inherit
EOF
}

# run <project-dir> — invoke the checker, capture combined output + exit code.
run() {
  OUT="$(bash "$checker" --project-dir "$1" 2>&1)"
  RC=$?
}

echo "=== TEST A: real repo is clean (all invoking workflows opus+effort) ==="
run "$repo_root"
assert "real repo exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"

# --- TEST B: opus+effort claude_args fixture ---------------------------------
echo "=== TEST B: opus+effort claude_args exits 0 ==="
fx_b="$(mktemp -d)"
trap 'rm -rf "$fx_b" "${fx_c:-}" "${fx_d:-}" "${fx_e:-}" "${fx_f:-}" "${fx_g:-}" "${fx_h:-}" "${fx_i:-}" "${fx_j:-}" "${fx_k:-}"' EXIT
make_action_workflow "$fx_b/.github/workflows/good.yml" "--model opus --effort low --max-turns 25"
run "$fx_b"
assert "opus+effort fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "opus+effort fixture reports 1 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=1')"
assert "opus+effort fixture STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"

# --- TEST C: --model haiku ---------------------------------------------------
echo "=== TEST C: --model haiku exits 1 and is named ==="
fx_c="$(mktemp -d)"
make_action_workflow "$fx_c/.github/workflows/bad.yml" "--model haiku --max-turns 25"
run "$fx_c"
assert "haiku fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "haiku fixture names the file" "$(contains "$OUT" 'bad.yml')"
assert "haiku fixture reports MODEL=haiku" "$(contains "$OUT" 'MODEL=haiku')"
assert "haiku fixture TYPE=non_opus_model" "$(contains "$OUT" 'TYPE=non_opus_model')"

# --- TEST D: --model sonnet --------------------------------------------------
echo "=== TEST D: --model sonnet exits 1 and is named ==="
fx_d="$(mktemp -d)"
make_action_workflow "$fx_d/.github/workflows/legacy.yml" "--model sonnet --effort medium"
run "$fx_d"
assert "sonnet fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "sonnet fixture names the file" "$(contains "$OUT" 'legacy.yml')"
assert "sonnet fixture reports MODEL=sonnet" "$(contains "$OUT" 'MODEL=sonnet')"

# --- TEST E: opus WITHOUT --effort -------------------------------------------
echo "=== TEST E: opus without --effort exits 1 (missing_effort) ==="
fx_e="$(mktemp -d)"
make_action_workflow "$fx_e/.github/workflows/no-effort.yml" "--model opus --max-turns 25"
run "$fx_e"
assert "no-effort fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "no-effort fixture TYPE=missing_effort" "$(contains "$OUT" 'TYPE=missing_effort')"

# --- TEST F: CLI/npx form with --model haiku ---------------------------------
echo "=== TEST F: CLI form --model haiku exits 1 (second parser path) ==="
fx_f="$(mktemp -d)"
make_cli_workflow "$fx_f/.github/workflows/cli-bad.yml" haiku medium
run "$fx_f"
assert "CLI haiku fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "CLI haiku fixture reports MODEL=haiku" "$(contains "$OUT" 'MODEL=haiku')"

# --- TEST G: CLI/npx form with opus+effort -----------------------------------
echo "=== TEST G: CLI form opus+effort exits 0 ==="
fx_g="$(mktemp -d)"
make_cli_workflow "$fx_g/.github/workflows/cli-good.yml" opus medium
run "$fx_g"
assert "CLI opus+effort fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "CLI opus+effort fixture reports 1 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=1')"

# --- TEST H: no Claude invocation --------------------------------------------
echo "=== TEST H: no-invocation workflow not counted, exit 0 ==="
fx_h="$(mktemp -d)"
make_plain_workflow "$fx_h/.github/workflows/plain.yml"
run "$fx_h"
assert "plain fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "plain fixture reports 0 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=0')"
assert "plain fixture counts a skip" "$(contains "$OUT" 'SKIPPED_NO_INVOCATION=1')"

# --- TEST I: reusable-only workflow ------------------------------------------
echo "=== TEST I: reusable-only workflow skipped, exit 0 ==="
fx_i="$(mktemp -d)"
make_reusable_workflow "$fx_i/.github/workflows/reusable.yml"
run "$fx_i"
assert "reusable fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "reusable fixture reports 0 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=0')"
assert "reusable fixture counts a reusable skip" "$(contains "$OUT" 'SKIPPED_REUSABLE=1')"

# --- TEST J: invalid effort level --------------------------------------------
echo "=== TEST J: --effort bogus exits 1 (invalid_effort) ==="
fx_j="$(mktemp -d)"
make_action_workflow "$fx_j/.github/workflows/bogus.yml" "--model opus --effort bogus"
run "$fx_j"
assert "bogus-effort fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "bogus-effort fixture TYPE=invalid_effort" "$(contains "$OUT" 'TYPE=invalid_effort')"

# --- TEST K: allowlist seam is honored ---------------------------------------
echo "=== TEST K: allowlisted file is honored ==="
fx_k="$(mktemp -d)"
make_action_workflow "$fx_k/.github/workflows/instrument.yml" "--model haiku"
k_out="$(CHECK_WORKFLOW_MODEL_ALLOWLIST='.github/workflows/instrument.yml' \
  bash "$checker" --project-dir "$fx_k" 2>&1)"
k_rc=$?
assert "allowlisted haiku workflow exits 0" "$([ "$k_rc" -eq 0 ] && echo true || echo false)"
assert "allowlisted file is not named as an error" "$([ "$(contains "$k_out" 'instrument.yml')" = "false" ] && echo true || echo false)"

# --- Summary -----------------------------------------------------------------
echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
