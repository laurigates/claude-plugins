#!/usr/bin/env bash
# Prepare an eval run directory and write a run manifest.
#
# Creates:
#   <runs-root>/<plugin>/<skill>/<runs|baseline>/<eval-id>-run-<N>/
# Writes:
#   <runs-root>/<plugin>/<skill>/<runs|baseline>/<eval-id>-run-<N>/manifest.json
#
# <runs-root> is, in order: $EVAL_RUNS_ROOT; else <repo-root>/tmp/eval-runs (the
# repo's gitignored temp dir); else ${TMPDIR:-/tmp}/claude-eval-runs when the
# skill dir is not inside a git checkout.
#
# WHY NOT <skill-dir>/eval-results/ (issue #2667): runs used to be staged there,
# which is inside `**/skills/**`. Path-scoped rules load whole into any agent
# that touches a matching path, and 14 of this repo's rules are scoped to that
# glob — so an eval subagent writing its transcript pulled all of them in, and
# the haiku arm of the golden-set sweep died on HTTP 400 "Prompt is too long".
# The run dir is therefore refused if it would land under a `skills/` component.
# Aggregated outputs (benchmark.json, model-matrix.json) still live in
# <skill-dir>/eval-results/ — those are written by the orchestrator, not by the
# eval subagent.
#
# Usage:
#   prepare_run.sh --skill-dir <path> --eval-id <id> --run <N> [--baseline]
#
# Output: KEY=value lines
#   RUN_DIR=<absolute path>
#   MANIFEST=<absolute path>
#   STARTED_AT=<iso8601>

set -uo pipefail

skill_dir=""
eval_id=""
run_num=""
baseline=false

while [ $# -gt 0 ]; do
  case "$1" in
    --skill-dir) skill_dir="$2"; shift 2 ;;
    --eval-id) eval_id="$2"; shift 2 ;;
    --run) run_num="$2"; shift 2 ;;
    --baseline) baseline=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$skill_dir" ] || [ -z "$eval_id" ] || [ -z "$run_num" ]; then
  echo "ERROR: --skill-dir, --eval-id, and --run are required" >&2
  exit 1
fi

if [ ! -d "$skill_dir" ]; then
  echo "ERROR: skill directory not found: $skill_dir" >&2
  exit 1
fi

echo "=== PREPARE RUN ==="

subdir="runs"
if [ "$baseline" = true ]; then
  subdir="baseline"
fi

abs_skill_dir="$(cd "$skill_dir" && pwd -P)"

# Key the run by <plugin>/<skill> so two skills with the same eval id and run
# number never share a directory under the common runs root.
skill_name="$(basename "$abs_skill_dir")"
skill_parent="$(dirname "$abs_skill_dir")"
if [ "$(basename "$skill_parent")" = "skills" ]; then
  skill_key="$(basename "$(dirname "$skill_parent")")/$skill_name"
else
  skill_key="$skill_name"
fi

repo_root="$(git -C "$abs_skill_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "${EVAL_RUNS_ROOT:-}" ]; then
  runs_root="$EVAL_RUNS_ROOT"
elif [ -n "$repo_root" ]; then
  runs_root="$repo_root/tmp/eval-runs"
else
  runs_root="${TMPDIR:-/tmp}"
  runs_root="${runs_root%/}/claude-eval-runs"
fi
case "$runs_root" in
  /*) ;;
  *) runs_root="$(pwd -P)/$runs_root" ;;
esac

run_dir="$runs_root/$skill_key/$subdir/${eval_id}-run-${run_num}"

# Refuse a run dir under a `skills/` component (the `**/skills/**` glob). Only
# the part below the repo root is checked: the repo itself may legitimately live
# under a directory called skills/, and rule globs are repo-relative.
rel_run_dir="$run_dir"
if [ -n "$repo_root" ]; then
  rel_run_dir="${run_dir#"$repo_root"/}"
fi
case "/$rel_run_dir/" in
  */skills/*)
    echo "ERROR: run dir would land under a skills/ directory: $run_dir" >&2
    echo "       path-scoped rules on **/skills/** would load into the eval subagent (#2667); set EVAL_RUNS_ROOT elsewhere" >&2
    exit 1
    ;;
esac

mkdir -p "$run_dir"

started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
manifest="$run_dir/manifest.json"

jq -n \
  --arg eid "$eval_id" \
  --argjson run "$run_num" \
  --arg ts "$started_at" \
  --argjson baseline "$baseline" \
  '{eval_id: $eid, run: $run, started_at: $ts, baseline: $baseline}' \
  > "$manifest"

echo "RUN_DIR=$run_dir"
echo "MANIFEST=$manifest"
echo "STARTED_AT=$started_at"
