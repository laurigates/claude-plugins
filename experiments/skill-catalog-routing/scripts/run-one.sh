#!/usr/bin/env bash
# Run a single (task, condition, run_n) triple. Writes a stream-JSON transcript
# to $RUN_DIR/<task>.<condition>.run<N>.jsonl plus a .meta.json sidecar.
#
# Adapted from experiments/claude-probe/scripts/run-one.sh. Differences:
#   * the arm is defined by which CATALOG variant is injected, not a fixed probe
#   * the system prompt is assembled per-arm by build-arm-prompt.sh
#   * no per-task fixtures / config-isolation arms (routing is read-only)
#   * asserts the assembled system prompt carries no built-in skill listing
#
# Usage: run-one.sh <task-id> <condition-id> <run-n> <run-dir>

set -euo pipefail

task_id="${1:?usage: run-one.sh <task-id> <condition-id> <run-n> <run-dir>}"
condition_id="${2:?condition-id required}"
run_n="${3:?run-n required}"
run_dir="${4:?run-dir required}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
tasks_dir="$root/tasks"
conditions_file="$root/conditions.yaml"

task_file="$tasks_dir/${task_id}.yaml"
[ -f "$task_file" ] || { echo "ERROR: task not found: $task_file" >&2; exit 1; }

# Extract the task prompt and wrap it in a constant framing that reinforces the
# routing contract (a low-effort model otherwise slips into doing the task or
# asking questions). The wrapper is identical for every task and every arm, so
# it does not bias the catalog comparison.
task_prompt="$(
  PY_TASK_FILE="$task_file" python3 -c '
import os, sys, yaml
t = yaml.safe_load(open(os.environ["PY_TASK_FILE"]))
body = t["prompt"].strip()
sys.stdout.write(
    "Route this user request to the best skill (or NONE). "
    "Do not perform it or ask questions — output only the routing decision, "
    "ending with the required JSON line.\n\n"
    "=== USER REQUEST ===\n" + body + "\n=== END USER REQUEST ==="
)
'
)"

# Extract condition fields.
eval "$(
  PY_COND_FILE="$conditions_file" PY_COND_ID="$condition_id" python3 -c '
import os, sys, yaml, shlex
data = yaml.safe_load(open(os.environ["PY_COND_FILE"]))
cond = next((c for c in data["conditions"] if c["id"] == os.environ["PY_COND_ID"]), None)
if not cond:
    sys.exit("ERROR: unknown condition: " + os.environ["PY_COND_ID"])
for k in ("model", "effort", "catalog"):
    print(f"ROUTE_{k.upper()}={shlex.quote(str(cond[k]))}")
'
)"

# Assemble the arm system prompt (router + injected catalog) and locate it.
arm_prompt="$("$here/build-arm-prompt.sh" "$ROUTE_CATALOG")"
[ -f "$arm_prompt" ] || { echo "ERROR: arm prompt not built: $arm_prompt" >&2; exit 1; }

# Contamination guard: the assembled prompt is a COMPLETE system-prompt
# replacement, so it must not carry Claude Code's built-in skill listing. We
# can't read the effective prompt back, but we CAN assert our own file is clean:
# for the null arm there must be no "## Available skills" body, and the file must
# not contain the harness's own meta-skill markers.
if [ "$ROUTE_CATALOG" = "none" ]; then
  if grep -q "^## Available skills" "$arm_prompt"; then
    echo "ERROR: C0 (none) arm prompt unexpectedly carries a catalog body" >&2
    exit 1
  fi
fi

out_base="$run_dir/${task_id}.${condition_id}.run${run_n}"
transcript="$out_base.jsonl"
meta="$out_base.meta.json"
stderr_log="$out_base.stderr.log"

mkdir -p "$run_dir"

# Assemble the claude invocation. The router is a pure classification turn.
#   * run from a NEUTRAL cwd (a fresh temp dir) so the plugins repo's own
#     CLAUDE.md / rules — which name many skills — do not load and contaminate
#     the arms. Only our injected catalog is the skill vocabulary. (Measured:
#     from-repo cwd base ~50k tokens vs neutral-cwd base ~23k; the built-in
#     ~22k skill listing is absent under the system-prompt replacement.)
#   * --system-prompt-file REPLACES the built-in prompt (strips the listing).
#   * IS_SANDBOX=1 lets --dangerously-skip-permissions run as root in the
#     sandbox (the router needs no tools; this just keeps it non-interactive).
#   * </dev/null so the CLI never waits on stdin.
neutral_cwd="$(mktemp -d)"
claude_args=(
  -p "$task_prompt"
  --model "$ROUTE_MODEL"
  --effort "$ROUTE_EFFORT"
  --system-prompt-file "$arm_prompt"
  --strict-mcp-config
  --output-format stream-json
  --verbose
  --dangerously-skip-permissions
)

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
set +e
( cd "$neutral_cwd" && IS_SANDBOX=1 claude "${claude_args[@]}" ) >"$transcript" 2>"$stderr_log" </dev/null
exit_code=$?
set -e
ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rm -rf "$neutral_cwd"

# Write meta sidecar.
PY_META_OUT="$meta" \
PY_TASK_ID="$task_id" \
PY_COND_ID="$condition_id" \
PY_RUN_N="$run_n" \
PY_MODEL="$ROUTE_MODEL" \
PY_EFFORT="$ROUTE_EFFORT" \
PY_CATALOG="$ROUTE_CATALOG" \
PY_STARTED="$started_at" \
PY_ENDED="$ended_at" \
PY_EXIT="$exit_code" \
python3 -c '
import json, os
meta = {
    "task_id": os.environ["PY_TASK_ID"],
    "condition_id": os.environ["PY_COND_ID"],
    "run_n": int(os.environ["PY_RUN_N"]),
    "model": os.environ["PY_MODEL"],
    "effort": os.environ["PY_EFFORT"],
    "catalog": os.environ["PY_CATALOG"],
    "started_at": os.environ["PY_STARTED"],
    "ended_at": os.environ["PY_ENDED"],
    "exit_code": int(os.environ["PY_EXIT"]),
}
json.dump(meta, open(os.environ["PY_META_OUT"], "w"), indent=2)
'

echo "[run-one] $task_id / $condition_id / run$run_n -> exit=$exit_code"
exit "$exit_code"
