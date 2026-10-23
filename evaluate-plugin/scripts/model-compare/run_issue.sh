#!/usr/bin/env bash
# Run one model on one real repository issue in its own git worktree, with the
# normal Claude Code harness (CLAUDE.md, rules, plugins), and record what it
# committed.
#
# Usage: run_issue.sh <issue> <model-id> [effort]
#   Reads issues/prompts/<issue>.txt (the issue text plus the "commit locally,
#   do not push" frame). effort defaults to medium.
#
# Env:
#   MC_RUNS_DIR         outputs (default ${TMPDIR:-/tmp}/model-compare-runs)
#   MC_WORKTREE_DIR     worktree root (default ${TMPDIR:-/tmp}/model-compare-wt)
#   MC_BASE_REF         base ref for every worktree (default origin/main)
#   MC_MAX_BUDGET_USD   per-run cap (default 3.00)
#
# Each run gets a branch eval/<issue>-<model> and a worktree under
# $MC_WORKTREE_DIR; both are recreated on a re-run. Worktree creation is
# serialized with flock: parallel `git worktree add` calls race on the shared
# .git and one of them fails. Check every issue's premise before running it
# (already fixed on main? blocked on an unmerged PR?): a stale issue measures
# judgment, not the fix.
set -u
[ $# -ge 2 ] || { echo "usage: run_issue.sh <issue> <model-id> [effort]" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
I=$1 M=$2 E=${3:-medium}
PROMPT="$HERE/issues/prompts/$I.txt"
[ -f "$PROMPT" ] || { echo "no prompt: $PROMPT" >&2; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "claude CLI not found" >&2; exit 2; }
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
OUT=${MC_RUNS_DIR:-${TMPDIR:-/tmp}/model-compare-runs}/issues
WTROOT=${MC_WORKTREE_DIR:-${TMPDIR:-/tmp}/model-compare-wt}
BASE=${MC_BASE_REF:-origin/main}
WT="$WTROOT/$I.$M" BR="eval/$I-$M"
mkdir -p "$OUT" "$WTROOT"
(
  flock 9
  git -C "$REPO" worktree remove --force "$WT" 2>/dev/null
  git -C "$REPO" branch -D "$BR" 2>/dev/null
  git -C "$REPO" worktree add -q -b "$BR" "$WT" "$BASE"
) 9>"$WTROOT/.lock"
[ -d "$WT" ] || { echo "worktree failed: $WT" >&2; exit 1; }
SID=$(python3 -c 'import uuid; print(uuid.uuid4())')
START=$(date +%s)
( cd "$WT" && timeout 1800 claude -p "$(cat "$PROMPT")" --model "$M" --effort "$E" --session-id "$SID" \
    --allowedTools "Bash,Read,Edit,Write,Glob,Grep" --disallowedTools "Bash(git push:*)" "Bash(gh:*)" \
    --output-format json --max-budget-usd "${MC_MAX_BUDGET_USD:-3.00}" \
    </dev/null >"$OUT/out.$I.$M.json" 2>"$OUT/err.$I.$M.txt" )
DUR=$(( $(date +%s) - START ))
git -C "$WT" diff "$BASE"...HEAD >"$OUT/diff.$I.$M.patch"
git -C "$WT" status --short >"$OUT/dirty.$I.$M.txt"
TR=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$SID.jsonl" 2>/dev/null | head -1)
PEAK=0
[ -n "$TR" ] && PEAK=$(jq -s '[.[]|select(.type=="assistant")|.message.usage|select(.)|.input_tokens+.cache_creation_input_tokens+.cache_read_input_tokens]|max//0' "$TR")
jq -nc --arg i "$I" --arg m "$M" --arg e "$E" --argjson dur "$DUR" --argjson peak "${PEAK:-0}" --arg tr "${TR:-}" \
  --arg commits "$(git -C "$WT" log --oneline "$BASE"..HEAD)" \
  --slurpfile o <(jq -c . "$OUT/out.$I.$M.json" 2>/dev/null || echo '{}') \
  '{issue:$i, model:$m, effort:$e, dur_s:$dur, peak_prompt:$peak, commits:$commits, transcript:$tr,
    cost:($o[0].total_cost_usd//null), turns:($o[0].num_turns//null), stop:($o[0].subtype//null)}' \
  >>"$OUT/results.jsonl"
