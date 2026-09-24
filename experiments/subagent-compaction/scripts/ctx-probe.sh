#!/usr/bin/env bash
# Subagent context/compaction probe.
#
# For each (model × autoCompactEnabled) arm, run `claude -p` in an isolated fake
# HOME whose main agent spawns ONE briefed subagent that reads a filler corpus
# and reports each file's sentinel. CLAUDE_AUTOCOMPACT_PCT_OVERRIDE is set low
# so a 1M-window model compacts at ~100k instead of ~800k — cheap to trigger.
#
# Questions each arm answers (see ../README.md):
#   Q1  Does main-config autoCompactEnabled=false reach subagents?   (ac-off arm: SUBAGENT_COMPACTED)
#   Q2  Does the subagent resume its task after compacting?          (SENTINELS_* vs. DISTINCT_FILES_READ)
#   Q3  Does PreCompact fire inside a subagent, with an agent_id?    (HOOK_PreCompact, PRECOMPACT_WITH_AGENT_ID)
#
# Auth: the fake HOME has no login, so this sources CLAUDE_CODE_OAUTH_TOKEN (or
# ANTHROPIC_API_KEY) from the environment or ~/.api_tokens (`claude setup-token`).
#
# Usage: ctx-probe.sh [--models "opus[1m] sonnet[1m]"] [--arms "on off"] [--pct 10]
#                     [--files 20] [--kb 60] [--run-id ID] [--dry-run]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exp_root="$(dirname "$here")"

models="opus[1m]"
arms="on off"
pct=10
files=20
kb=60
run_id="$(date +%Y%m%dT%H%M%S)"
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --models) models="$2"; shift 2 ;;
    --arms) arms="$2"; shift 2 ;;
    --pct) pct="$2"; shift 2 ;;
    --files) files="$2"; shift 2 ;;
    --kb) kb="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for dep in jq awk sha256sum; do
  command -v "$dep" >/dev/null || { echo "STATUS=missing_dependency DEP=$dep"; exit 1; }
done
claude_bin="$(command -v claude || true)"
[ -n "$claude_bin" ] || [ "$dry_run" -eq 1 ] || { echo "STATUS=missing_dependency DEP=claude"; exit 1; }

if [ "$dry_run" -eq 0 ]; then
  if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$HOME/.api_tokens" ]; then
    set +e +u; set -a
    # shellcheck disable=SC1091
    . "$HOME/.api_tokens" 2>/dev/null
    set +a; set -e -u
  fi
  if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "STATUS=no_auth (set CLAUDE_CODE_OAUTH_TOKEN via 'claude setup-token', or ANTHROPIC_API_KEY)"
    exit 1
  fi
fi

results="$exp_root/results/$run_id"
fixture="$results/fixture"
mkdir -p "$results"
bash "$here/make-fixture.sh" "$fixture" "$files" "$kb"

last="$(printf 'f%02d.txt' "$files")"
prompt="This is a context-window probe. Do exactly this and nothing else.

Spawn ONE subagent with the Agent tool (subagent_type: general-purpose; do not set model, so it inherits yours). Give it this brief verbatim:

---
Read the files $fixture/files/f01.txt through $fixture/files/$last in numeric order with the Read tool: one whole file per call (no offset/limit), one call at a time. The last line of each file is \`SENTINEL <file> <hex>\`. After the last file, reply with only the sentinel lines, one per line, in file order. Never guess or reconstruct a sentinel that is not in a Read result visible in your current context; write \`MISSING <file>\` for that file instead.
---

Then reply with the subagent's report verbatim and nothing else."

printf 'arm\tmodel\tautocompact\tcompacted\tcompactions\tpeak_ctx\tfiles_read\tcorrect\twrong\tdeclared_missing\tabsent\tprecompact_hooks\tprecompact_agent_id\toutcome\n' > "$results/summary.tsv"

for model in $models; do
  for arm in $arms; do
    case "$arm" in on) ac=true ;; off) ac=false ;; *) echo "unknown arm: $arm" >&2; exit 2 ;; esac
    slug="$(printf '%s' "$model" | tr -c 'A-Za-z0-9' '_')-ac-$arm"
    arm_dir="$results/$slug"
    home="$arm_dir/home"
    mkdir -p "$home/.claude"

    jq -n --argjson ac "$ac" '{hasCompletedOnboarding: true, autoCompactEnabled: $ac}' > "$home/.claude.json"
    hook_cmd="bash '$here/log-hook.sh' '$arm_dir/hooks.jsonl'"
    jq -n --arg c "$hook_cmd" '{hooks: (["PreCompact","PostCompact","SubagentStart","SubagentStop"]
        | map({key: ., value: [{matcher: "", hooks: [{type: "command", command: $c}]}]}) | from_entries)}' \
      > "$home/.claude/settings.json"
    printf 'MODEL=%s\nAUTO_COMPACT_ENABLED=%s\nAUTOCOMPACT_PCT_OVERRIDE=%s\n' "$model" "$ac" "$pct" > "$arm_dir/arm.env"

    echo "=== RUN $slug ==="
    if [ "$dry_run" -eq 1 ]; then
      echo "DRY_RUN: cd $fixture/files && HOME=$home CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=$pct claude -p <prompt> --model '$model' --output-format stream-json --verbose --allowedTools Read,Agent,Task"
      continue
    fi

    # Strip inherited Claude Code session/compaction env so only this arm's settings apply.
    ( cd "$fixture/files" && env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u DISABLE_AUTO_COMPACT -u DISABLE_COMPACT \
        -u CLAUDE_CODE_DISABLE_1M_CONTEXT -u CLAUDE_CODE_SUBAGENT_MODEL \
        HOME="$home" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="$pct" \
        "$claude_bin" -p "$prompt" --model "$model" --output-format stream-json --verbose \
          --allowedTools "Read,Agent,Task" \
        > "$arm_dir/main.jsonl" 2> "$arm_dir/stderr.log" ) || echo "RUN_EXIT=$?"

    bash "$here/analyze.sh" "$arm_dir" "$fixture/sentinels.txt" | tee "$arm_dir/summary.txt"
    s="$arm_dir/summary.txt"
    v() { grep -m1 "^$1=" "$s" | cut -d= -f2- || true; }
    peak="$(grep '^PEAK_CTX=' "$s" | cut -d= -f2 | sort -n | tail -1 || true)"
    comps="$(grep '^COMPACTIONS=' "$s" | cut -d= -f2 | awk '{t += $1} END {print t + 0}')"
    read_n="$(grep '^DISTINCT_FILES_READ=' "$s" | cut -d= -f2 | sort -n | tail -1 || true)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$slug" "$model" "$ac" "$(v SUBAGENT_COMPACTED)" "${comps:-0}" "$peak" "$read_n" \
      "$(v SENTINELS_CORRECT)" "$(v SENTINELS_WRONG)" "$(v SENTINELS_DECLARED_MISSING)" "$(v SENTINELS_ABSENT)" \
      "$(v HOOK_PreCompact)" "$(v PRECOMPACT_WITH_AGENT_ID)" "$(v OUTCOME)" >> "$results/summary.tsv"
  done
done

echo "=== SUMMARY ==="
column -t -s $'\t' "$results/summary.tsv" 2>/dev/null || cat "$results/summary.tsv"
echo "RESULTS_DIR=$results"
