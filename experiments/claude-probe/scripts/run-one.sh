#!/usr/bin/env bash
# Run a single (test, condition, run_n) triple. Writes a stream-JSON transcript
# to $RUN_DIR/<test>.<condition>.run<N>.jsonl plus a .meta.json sidecar.
#
# Usage: run-one.sh <test-id> <condition-id> <run-n> <run-dir>

set -euo pipefail

test_id="${1:?usage: run-one.sh <test-id> <condition-id> <run-n> <run-dir>}"
condition_id="${2:?condition-id required}"
run_n="${3:?run-n required}"
run_dir="${4:?run-dir required}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
tests_dir="$root/tests"
prompts_dir="$root/prompts"
conditions_file="$root/conditions.yaml"

test_file="$tests_dir/${test_id}.yaml"
[ -f "$test_file" ] || { echo "ERROR: test not found: $test_file" >&2; exit 1; }

# Extract test prompt using Python (YAML is a faff in shell).
probe_prompt="$(
  PY_TEST_FILE="$test_file" python3 -c '
import os, sys
import yaml
with open(os.environ["PY_TEST_FILE"]) as f:
    t = yaml.safe_load(f)
sys.stdout.write(t["prompt"])
'
)"

# Extract condition fields.
eval "$(
  PY_COND_FILE="$conditions_file" PY_COND_ID="$condition_id" python3 -c '
import os, sys, yaml, shlex
with open(os.environ["PY_COND_FILE"]) as f:
    data = yaml.safe_load(f)
cond = next((c for c in data["conditions"] if c["id"] == os.environ["PY_COND_ID"]), None)
if not cond:
    sys.exit("ERROR: unknown condition: " + os.environ["PY_COND_ID"])
for k in ("model", "thinking", "system_prompt"):
    print(f"PROBE_{k.upper()}={shlex.quote(str(cond[k]))}")
'
)"

out_base="$run_dir/${test_id}.${condition_id}.run${run_n}"
transcript="$out_base.jsonl"
meta="$out_base.meta.json"
stderr_log="$out_base.stderr.log"

mkdir -p "$run_dir"

# Assemble the claude invocation.
claude_args=(
  -p "$probe_prompt"
  --model "$PROBE_MODEL"
  --effort "$PROBE_THINKING"
  --output-format stream-json
  --verbose
  --dangerously-skip-permissions
)

if [ "$PROBE_SYSTEM_PROMPT" = "probe" ]; then
  probe_file="$prompts_dir/probe.md"
  [ -f "$probe_file" ] || { echo "ERROR: prompt not found: $probe_file" >&2; exit 1; }
  claude_args+=(--system-prompt "$(cat "$probe_file")")
fi

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
set +e
claude "${claude_args[@]}" >"$transcript" 2>"$stderr_log"
exit_code=$?
set -e
ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Write meta sidecar.
PY_META_OUT="$meta" \
PY_TEST_ID="$test_id" \
PY_COND_ID="$condition_id" \
PY_RUN_N="$run_n" \
PY_MODEL="$PROBE_MODEL" \
PY_THINKING="$PROBE_THINKING" \
PY_SYSPROMPT="$PROBE_SYSTEM_PROMPT" \
PY_STARTED="$started_at" \
PY_ENDED="$ended_at" \
PY_EXIT="$exit_code" \
python3 -c '
import json, os
meta = {
    "test_id": os.environ["PY_TEST_ID"],
    "condition_id": os.environ["PY_COND_ID"],
    "run_n": int(os.environ["PY_RUN_N"]),
    "model": os.environ["PY_MODEL"],
    "thinking": os.environ["PY_THINKING"],
    "system_prompt": os.environ["PY_SYSPROMPT"],
    "started_at": os.environ["PY_STARTED"],
    "ended_at": os.environ["PY_ENDED"],
    "exit_code": int(os.environ["PY_EXIT"]),
}
with open(os.environ["PY_META_OUT"], "w") as f:
    json.dump(meta, f, indent=2)
'

echo "[run-one] $test_id / $condition_id / run$run_n -> exit=$exit_code"
exit "$exit_code"
